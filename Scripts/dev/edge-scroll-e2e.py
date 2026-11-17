#!/usr/bin/env python3
"""Real niri edge-scroll acceptance. Run only in the assigned two-output VM."""
import argparse
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import time
from presentation_harness import check_execution_paths, run_harness, write_receipt
from qml_probe import inject_probe, probe_owner_path


PROBE = r'''
  property int edgePulseCount: 0
  property int edgeReducedPulseFrames: 0
  Connections { target: EdgeScrollService; function onStepped() { shellRoot.edgePulseCount++; } }
  FrameAnimation {
    running: EdgeScrollService.reducedMotion && EdgeScrollService.activeZone !== null
    // Observe the settled frame, after both this observer and the service's
    // FrameAnimation have run; callback ordering is not a presented frame.
    onTriggered: Qt.callLater(function () {
      if (EdgeScrollService.stepPulse) shellRoot.edgeReducedPulseFrames++;
    })
  }
  IpcHandler {
    target: "edgeScrollTest"
    function state(): string {
      var widget = BarService.lookupWidget("ControlCenter", "Virtual-1");
      var point = widget ? widget.mapToItem(null, 0, 0) : null;
      return JSON.stringify({ready: Settings.isLoaded, enabled: EdgeScrollService.enabled,
        active: EdgeScrollService.activeZone, progress: EdgeScrollService.progress,
        pulse: EdgeScrollService.stepPulse, reducedMotion: EdgeScrollService.reducedMotion,
        pulseCount: shellRoot.edgePulseCount, reducedPulseFrames: shellRoot.edgeReducedPulseFrames,
        zones: EdgeScrollService.screenZones, dock: DockGeometryService.revealRect("Virtual-1"),
        panel: PanelService.openedPanel?.objectName || "", tooltip: TooltipService.activeTooltip?.visible || false,
        widget: widget ? {x: point.x + 8, y: point.y, width: widget.width, height: widget.height,
                          hovered: widget.hovering} : null});
    }
    function configure(text: string) {
      var values = JSON.parse(text);
      if (values.setting !== undefined) Settings.data.bar.edgeScrolling = values.setting;
      if (values.hold !== undefined) Settings.data.bar.edgeScrollHoldMs = values.hold;
      if (values.framed !== undefined) Settings.data.bar.barType = values.framed ? "framed" : "simple";
      if (values.hideOnOverview !== undefined) Settings.data.bar.hideOnOverview = values.hideOnOverview;
      if (values.animationDisabled !== undefined) Settings.data.general.animationDisabled = values.animationDisabled;
      if (values.powerSaver !== undefined) PowerProfileService.profile = values.powerSaver ? PowerProfile.PowerSaver : PowerProfile.Balanced;
      if (values.dock !== undefined) Settings.data.dock.enabled = values.dock;
      if (values.dockMode !== undefined) Settings.data.dock.displayMode = values.dockMode;
    }
    function openSettings() {
      PanelService.getPanel("settingsPanel", Quickshell.screens[0], false).openToTab(2, 2);
    }
    function closePanel() { if (PanelService.openedPanel) PanelService.openedPanel.closeImmediately(); }
    function stop() { Qt.quit(); }
  }
'''

SCREEN_PROBE = r'''
  IpcHandler {
    target: "edgeScreen-" + (root.screen?.name || "unknown")
    function mask(): string {
      function flatten(region) {
        var rectangles = [];
        if (region.width > 0 && region.height > 0)
          rectangles.push([region.x, region.y, region.width, region.height, region.intersection]);
        for (var child of region.regions) rectangles = rectangles.concat(flatten(child));
        return rectangles;
      }
      var base = [];
      for (var region of clickableMask.regions.slice(0, 3)) base = base.concat(flatten(region));
      var all = [];
      for (var region of clickableMask.regions) all = all.concat(flatten(region));
      return JSON.stringify({base: base, all: all, sensorRegions: edgeSensors.inputRegions.length,
        inputRects: edgeSensors.inputRegions.map(function(r) { return [r.x,r.y,r.width,r.height,r.intersection]; }),
        regionCount: clickableMask.regions.length,
        sensorActive: edgeSensors.active, width: root.width, height: root.height});
    }
  }
'''

DOCK_PROBE = r'''
  IpcHandler {
    target: "edgeDock-" + (peekWindow.screen?.name || "unknown")
    function state(): string {
      return JSON.stringify({hidden: root.hidden, loaded: root.dockLoaded,
        hovered: root.peekHovered, rect: peekWindow.revealRect});
    }
  }
'''


def run(argv, **kwargs):
    return subprocess.run(list(map(str, argv)), check=True, text=True, capture_output=True, timeout=30, **kwargs).stdout


def wait_for(function, description, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = function()
        if value:
            return value
        time.sleep(.02)
    raise AssertionError('timed out: ' + description)


def inside(shell, work, daemon=False):
    results = []
    fixtures = []
    pointer = None
    process = None
    instance_pid = None
    def ipc(method, *values):
        result = subprocess.run(['qs', 'ipc', '--pid', str(instance_pid), 'call', 'edgeScrollTest', method, *values],
                                text=True, capture_output=True, timeout=30, check=True)
        if method == 'state' and not result.stdout.strip():
            with (work / 'ipc-diagnostic.log').open('a') as log:
                log.write(repr(dict(stdout=result.stdout, stderr=result.stderr)) + '\n')
        return result.stdout.strip()
    def state():
        return json.loads(ipc('state'))
    def configure(**values):
        ipc('configure', json.dumps(values))
        time.sleep(.1)
    def niri(*args):
        return run(['niri', 'msg', *args])
    def action(*args):
        niri('action', *args)
    def focused():
        return json.loads(niri('-j', 'focused-window'))
    def column():
        window = focused()
        if window is None:
            # niri intentionally has no keyboard-focused window in overview.
            # Its focused workspace still reports the active tile identity.
            ws = next(w for w in json.loads(niri('-j', 'workspaces')) if w['is_focused'])
            window = next(w for w in json.loads(niri('-j', 'windows')) if w['id'] == ws['active_window_id'])
        return window['layout']['pos_in_scrolling_layout'][0]
    def workspace():
        return next(w for w in json.loads(niri('-j', 'workspaces')) if w['is_focused'])['idx']
    def pointer_command(command):
        pointer.stdin.write(command + '\n'); pointer.stdin.flush()
        assert select.select([pointer.stdout], [], [], 20)[0], 'pointer acknowledgement timeout'
        assert pointer.stdout.readline().strip() == 'OK'
    def move(x, y):
        outputs = json.loads(niri('-j', 'outputs'))
        logical = [o['logical'] for o in outputs.values() if o['logical']]
        width = max(r['x'] + r['width'] for r in logical)
        height = max(r['y'] + r['height'] for r in logical)
        pointer_command(f'move {x} {y} {width} {height}')
    def rest():
        move(600, 400)
        wait_for(lambda: state()['active'] is None, 'leave cancels immediately')
    def hold(x, y, seconds, active=True):
        rest()
        started = time.monotonic()
        move(x, y)
        if active:
            try:
                wait_for(lambda: state()['active'], 'sensor enter')
            except AssertionError:
                (work / 'sensor-timeout.json').write_text(json.dumps(state(), indent=2))
                (work / 'mask-timeout.json').write_text(run(['qs','ipc','--pid',str(instance_pid),'call','edgeScreen-Virtual-1','mask']))
                run(['grim', '-c', '-o', 'Virtual-1', work / 'sensor-timeout.png'])
                raise
        # Readiness IPC is part of the hold, not extra dwell time. In
        # particular it must not turn a 650 ms seam check into an 800 ms hold.
        time.sleep(max(0, seconds - (time.monotonic() - started)))
        move(600, 400)
        time.sleep(.1)
    def passed(name, **details):
        results.append(dict(name=name, passed=True, **details))
        (work / 'cases.json').write_text(json.dumps(results, indent=2))
        print('PASS ' + name, flush=True)
    def screenshot(name):
        run(['grim', '-o', 'Virtual-1', work / (name + '.png')])
    def spawn(title):
        log = (work / (title + '.log')).open('w')
        child = subprocess.Popen(['foot', '--app-id=edge-scroll-fixture', '--title=' + title,
                                  'sh', '-c', 'printf "Edge scrolling test window\\n"; sleep 850'], stdout=log, stderr=log)
        fixtures.append((child, log))
        return wait_for(lambda: next((w for w in json.loads(niri('-j', 'windows')) if w['title'] == title), None), title)

    try:
        process = subprocess.Popen(['qs', '-p', shell, '--no-color', *(['-d'] if daemon else [])])
        instance_pid = process.pid
        if daemon:
            assert process.wait(timeout=60) == 0, 'daemon cold-load parent exit'
            instances = json.loads(run(['qs','list','--all','--json']))
            owned = [row for row in instances if Path(row['config_path']).resolve() == shell / 'shell.qml']
            assert len(owned) == 1, owned
            instance_pid = owned[0]['pid']
            passed('daemon cold load: qs -p tree -d exits zero')
        def ready():
            try: return state()['ready']
            except (subprocess.CalledProcessError, json.JSONDecodeError): return False
        wait_for(ready, 'shell IPC readiness', 60)
        pointer = subprocess.Popen([work / 'pointer-build/pointer'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, text=True, bufsize=1)
        assert select.select([pointer.stdout], [], [], 20)[0], 'virtual pointer readiness timeout'
        assert pointer.stdout.readline().strip() == 'READY'
        niri('output', 'Virtual-2', 'off')
        wait_for(lambda: len(state()['zones']) == 1, 'single-output geometry')
        configure(setting=False, dock=False, hideOnOverview=False)
        action('close-overview')
        primary = []
        for index in range(1, 4):
            action('focus-workspace', str(index))
            for col in range(3 if index == 1 else 1):
                window = spawn(f'edge-{index}-{col}')
                if index == 1: primary.append(window['id'])
        action('focus-window', '--id', str(primary[0]))
        wait_for(lambda: focused()['id'] == primary[0], 'first fixture focused')
        rest()
        configure(setting=True)
        time.sleep(.3)
        start = column()
        (work / 'fixture-windows.json').write_text(niri('-j', 'windows'))
        hold(1279, 400, 1.65)
        assert column() == start + 2, (start, column())
        passed('outer right: default 600/900, 1.65 s advances exactly two columns')
        hold(0, 400, 1.65)
        assert column() == start
        passed('outer left: returns exactly two columns')
        configure(hold=1000)
        move(0,400)
        wait_for(lambda: state()['progress'] > .25, 'hold before unrelated dock geometry change')
        holding = state()
        configure(dock=True, dockMode='auto_hide')
        wait_for(lambda: state()['dock'], 'dock changes other edge geometry')
        unchanged = state()
        assert unchanged['active']['key'] == holding['active']['key'] and unchanged['progress'] >= holding['progress']
        rest(); configure(dock=False, hold=600)
        passed('unchanged active zone survives unrelated geometry publication')
        before = workspace(); hold(600, 799, .75); assert workspace() == before + 1
        hold(600, 0, .75); assert workspace() == before
        passed('bottom and top bar outer row switch workspaces')
        before = (column(), workspace())
        hold(1279, 0, 2, active=False)
        assert (column(), workspace()) == before
        passed('corner held 2 s: no action')
        rest(); action('fullscreen-window')
        # niri Window has no fullscreen flag; the actual terminal must occupy
        # the full output geometry before this coverage assertion starts.
        wait_for(lambda: focused()['layout']['window_size'] == [1280,800], 'fullscreen fixture geometry')
        hold(1279,400,.8,active=False)
        assert state()['active'] is None and column() == before[0]
        action('fullscreen-window'); wait_for(lambda: focused()['layout']['window_size'] != [1280,800], 'leave fullscreen')
        passed('fullscreen covers the edge: no action')
        rest(); pointer_command('button 272 1'); move(1279, 400); time.sleep(1)
        assert column() == before[0] and state()['active'] is None
        pointer_command('button 272 0'); rest()
        move(1279, 400); wait_for(lambda: state()['active'], 'pre-press hold')
        pointer_command('button 272 1'); time.sleep(.8)
        assert state()['active'] is None and column() == before[0]
        pointer_command('button 272 0'); rest()
        passed('held button on entry and stationary press both suppress steps')
        configure(setting=False)
        hold(1279, 400, 1, active=False); assert column() == before[0]
        mask = json.loads(run(['qs', 'ipc', '--pid', str(instance_pid), 'call', 'edgeScreen-Virtual-1', 'mask']))
        assert mask['sensorRegions'] == 0 and mask['all'] == mask['base'], mask
        passed('setting off: no action, input mask equals original regions', mask=mask)
        configure(setting=True)
        action('open-overview'); wait_for(lambda: state()['enabled'], 'overview visible enabled')
        hold(1279, 400, .75); assert column() == before[0] + 1
        passed('overview with bar visible: column advances')
        configure(hideOnOverview=True)
        assert not state()['enabled']
        before_col = column(); hold(1279, 400, .7, active=False); assert column() == before_col
        passed('overview with hidden bar: no action')
        action('close-overview'); configure(hideOnOverview=False)
        niri('output', 'Virtual-2', 'on')
        wait_for(lambda: len(state()['zones']) == 2, 'dual-output geometry')
        action('focus-window', '--id', str(primary[0]))
        wait_for(lambda: focused()['id'] == primary[0], 'first fixture focused for inner edge')
        before_col = column(); hold(1276, 400, .65); assert column() == before_col
        hold(1276, 400, .95); assert column() == before_col + 1
        passed('inner seam: 0.65 s none, fresh 0.95 s exactly one step')
        # Focus must follow the sensor's output, not the keyboard-focused output.
        rest(); action('focus-monitor', 'Virtual-2'); hold(1276, 400, .95)
        assert column() == before_col + 2
        assert next(w for w in json.loads(niri('-j', 'workspaces')) if w['is_focused'])['output'] == 'Virtual-1'
        passed('step focuses pointer output before the directional action')
        rest(); configure(dock=True, dockMode='auto_hide')
        dock = wait_for(lambda: state()['dock'], 'dock reveal publication')
        before_ws = workspace()
        def dock_state():
            return json.loads(run(['qs','ipc','--pid',str(instance_pid),'call','edgeDock-Virtual-1','state']))
        assert dock_state()['rect'] == dock
        for enabled in (False, True):
            configure(setting=enabled)
            wait_for(lambda: dock_state()['hidden'] and not dock_state()['loaded'], 'dock initially hidden/unloaded')
            move(int(dock['x'] + dock['width'] / 2), 799)
            wait_for(lambda: dock_state()['hovered'] and not dock_state()['hidden'] and dock_state()['loaded'], 'dock reveal still shows/loads')
            time.sleep(.8)
            assert workspace() == before_ws and state()['active'] is None
            rest()
            wait_for(lambda: dock_state()['hidden'] and not dock_state()['loaded'], 'dock still hides/unloads on leave')
        passed('auto-hide dock reveal/show/hide unchanged with edge scrolling off/on', dock=dock)
        configure(dock=False)
        # Same widget, same outer-row hit target: a passive sensor cannot steal it.
        widget = wait_for(lambda: state()['widget'], 'bar ControlCenter widget')
        x = round(widget['x'] + widget['width'] / 2)
        move(x, 0); time.sleep(.1); pointer_command('button 272 1'); pointer_command('button 272 0')
        wait_for(lambda: state()['panel'].startswith('controlCenterPanel'), 'bar outer-row click')
        ipc('closePanel'); rest(); move(x, int(widget['height'] / 2))
        wait_for(lambda: state()['tooltip'], 'bar widget tooltip')
        assert state()['widget']['hovered']
        assert state()['tooltip']
        passed('bar outer-row click, widget hover and tooltip unchanged')
        rest(); configure(hold=1000)
        action('focus-window', '--id', str(primary[-1]))
        screenshot('edge-rest')
        move(0, 400)
        wait_for(lambda: .42 < state()['progress'] < .62, 'half ramp')
        screenshot('edge-ramp')
        wait_for(lambda: state()['pulse'], 'step pulse', 5)
        screenshot('edge-blink')
        rest(); time.sleep(.15)
        configure(animationDisabled=True)
        action('focus-window', '--id', str(primary[-1]))
        before_frames = state()
        move(0, 400); wait_for(lambda: state()['progress'] > .4, 'reduced-motion ramp')
        screenshot('edge-reduced-ramp')
        assert state()['reducedMotion']
        wait_for(lambda: state()['pulseCount'] == before_frames['pulseCount'] + 1, 'reduced-motion step')
        wait_for(lambda: state()['reducedPulseFrames'] == before_frames['reducedPulseFrames'] + 1, 'one presented reduced-motion pulse frame')
        wait_for(lambda: not state()['pulse'], 'reduced-motion pulse finishes')
        after_frames = state()
        (work / 'reduced-motion-frames.json').write_text(json.dumps(dict(before=before_frames, after=after_frames), indent=2))
        assert after_frames['reducedPulseFrames'] == before_frames['reducedPulseFrames'] + 1, (
            before_frames['reducedPulseFrames'], after_frames['reducedPulseFrames'])
        rest(); configure(animationDisabled=False, hold=600)
        configure(powerSaver=True)
        move(0,400); wait_for(lambda: state()['progress'] > .3, 'power-saving ramp')
        assert state()['reducedMotion']
        rest(); configure(powerSaver=False)
        passed('glow ramp/pulse/rest, reduced-motion single-frame pulse and power-saving ramp')
        ipc('openSettings'); time.sleep(.7); screenshot('edge-settings-framed')
        configure(framed=False); time.sleep(.3); screenshot('edge-settings-simple')
        configure(framed=True); ipc('closePanel')
        passed('settings framed and non-framed captures')
        print('EDGE_SCROLL_E2E: PASS', flush=True)
    finally:
        if pointer is not None:
            pointer.stdin.close()
            pointer.wait(timeout=10)
        for child, log in fixtures:
            child.terminate(); child.wait(timeout=10); log.close()
        if process is not None:
            if daemon and instance_pid:
                decoded = run(['qs','--no-color','log','--pid',str(instance_pid)])
                (work / 'daemon-shell.log').write_text(decoded)
                print(decoded, flush=True)
            try: ipc('stop')
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired): pass
            process.wait(timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path)
    parser.add_argument('--inside', nargs=2, type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--daemon', action='store_true', help='also prove the literal daemon cold-load route')
    args = parser.parse_args()
    if args.inside:
        return inside(*args.inside, daemon=args.daemon)
    source = args.source.resolve()
    work = (args.workspace or source.parent / ('edge-e2e-' + time.strftime('%Y%m%d-%H%M%S'))).resolve()
    check_execution_paths(parser, work, source=source)
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
    owner = probe_owner_path(shell)
    owner.write_text('import Quickshell.Io\nimport Quickshell.Services.UPower\nimport qs.Services.Power\n' + inject_probe(owner.read_text(), PROBE))
    screen = shell / 'Modules/MainScreen/MainScreen.qml'
    screen.write_text('import Quickshell.Io\n' + inject_probe(screen.read_text(), SCREEN_PROBE, root_id='root'))
    dock = shell / 'Modules/Dock/Dock.qml'
    dock.write_text('import Quickshell.Io\n' + inject_probe(dock.read_text(), DOCK_PROBE, root_id='peekWindow'))
    if os.environ.get('EDGE_SCROLL_DIAGNOSTICS') == '1':
        sensors = shell / 'Modules/MainScreen/EdgeScrollSensors.qml'
        text = sensors.read_text().replace('onHoveredChanged: {', 'onHoveredChanged: { console.log("EDGE_HOVER", root.originX, root.originY, hovered, point.position, point.pressedButtons);')
        text = text.replace('onActiveChanged: {', 'onActiveChanged: { console.log("EDGE_PRESS", active, point.pressedButtons);')
        sensors.write_text(text)
        controller = shell / 'Services/UI/EdgeScrollController.qml'
        text = controller.read_text().replace('function buttonsChanged(buttons) {', 'function buttonsChanged(buttons) { console.log("EDGE_BUTTONS", buttons);')
        controller.write_text(text)
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', DISPLAY='')
    for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        (work / leaf).mkdir(); env[key] = str(work / leaf)
    settings = work / 'config/atmosphera/settings'; settings.mkdir(parents=True)
    (settings / 'general.json').write_text(json.dumps({'showChangelogOnStartup': False}))
    build = work / 'pointer-build'; build.mkdir()
    protocol = source / 'Scripts/dev/wlr-virtual-pointer-unstable-v1.xml'
    for mode, name in [('client-header','virtual-pointer-client.h'),('private-code','virtual-pointer-protocol.c')]:
        run(['wayland-scanner', mode, protocol, build / name])
    flags = run(['pkg-config','--cflags','--libs','wayland-client']).split()
    run(['cc','-I',build,source / 'Scripts/dev/edge-scroll-test-pointer.c',build / 'virtual-pointer-protocol.c',*flags,'-o',build / 'pointer'])
    execution = run_harness(['dbus-run-session','--',sys.executable,'-B',__file__,'--inside',shell,work,
                             *(['--daemon'] if args.daemon else [])], work, env, 850)
    text = (work / 'shell.log').read_text()
    errors = [line for line in text.splitlines() if any(e in line for e in
              ['TypeError:', 'ReferenceError:', 'SyntaxError:', 'Failed to load configuration'])]
    receipt = dict(passed='EDGE_SCROLL_E2E: PASS' in text and not errors, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
