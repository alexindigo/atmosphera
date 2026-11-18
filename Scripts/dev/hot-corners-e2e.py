#!/usr/bin/env python3
"""Real niri hot-corner acceptance (H1-H9). Run only in the assigned two-output VM.

Every corner command appends its corner name to <workspace>/fired.log; the shell
probe also records HotCornersService.fired(corner, screen). The pointer is a
guest-local wlr virtual pointer over the whole output layout.
"""
import argparse
import json
import os
from pathlib import Path
import re
import select
import shlex
import shutil
import subprocess
import sys
import time
from presentation_harness import check_execution_paths, run_harness, write_receipt
from qml_probe import inject_probe, probe_owner_path

CORNERS = ['topLeft', 'topRight', 'bottomLeft', 'bottomRight']
CASES = ['H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'H9', 'H7', 'H8']

PROBE = r'''
  property var hotFired: []
  Connections {
    target: HotCornersService
    function onFired(corner, screenName) { shellRoot.hotFired = shellRoot.hotFired.concat([{corner: corner, screen: screenName}]); }
  }
  function hotFind(item, predicate) {
    if (!item) return null;
    if (predicate(item)) return item;
    for (var child of (item.children || [])) {
      var found = hotFind(child, predicate);
      if (found) return found;
    }
    return null;
  }
  function hotWalk(item, predicate, result) {
    if (!item) return result;
    if (predicate(item)) result.push(item);
    for (var child of (item.children || [])) hotWalk(child, predicate, result);
    return result;
  }
  function hotRect(item) {
    if (!item) return null;
    var p = item.mapToGlobal(0, 0);
    return {x: p.x, y: p.y, width: item.width, height: item.height, visible: item.visible};
  }
  function hotPanel() { return PanelService.getPanel("settingsPanel", Quickshell.screens[0], false); }
  function hotPage() {
    var panel = hotPanel();
    return panel && panel._settingsContent ? hotFind(panel._settingsContent, x => x.objectName === "hotCornersSettings") : null;
  }
  function hotField(name) { return hotFind(hotPage(), x => x.objectName === "hotCorner-" + name); }
  function hotDescribe(field) {
    if (!field) return null;
    var control = hotFind(field, x => x.popup !== undefined && x.currentIndex !== undefined);
    if (!control) {
      var input = hotFind(field, x => x.inputItem !== undefined);
      return {rect: hotRect(field), text: input ? input.text : null};
    }
    var popup = control.popup;
    var editor = hotFind(field, x => x.objectName === "combo-custom-editor");
    var buttons = hotWalk(editor, x => x.text === I18n.tr("widgets.action-picker.use-command") && x.clicked !== undefined, []);
    return {rect: hotRect(field), label: field._closedText, subtitle: field.displaySubtitle,
      slot: hotRect(hotFind(field, x => x.objectName === "combo-chevron-slot")),
      clear: hotRect(hotFind(field, x => x.objectName === "combo-clear-slot")),
      popup: popup.visible, popupOpened: popup.opened, query: field.searchText, count: field.activeModel ? field.activeModel.count : 0,
      footer: hotRect(hotFind(popup.contentItem, x => x.objectName === "combo-custom-footer")),
      editor: hotRect(editor), use: buttons.length ? hotRect(buttons[0]) : null};
  }
  IpcHandler {
    target: "hotCornersE2e"
    function state(): string {
      var corners = Settings.data.general.hotCorners;
      var panel = PanelService.getPanel("controlCenterPanel", Quickshell.screens[0], false);
      var edges = ScreenZonesService.edgeZones;
      return JSON.stringify({ready: Settings.isLoaded && ActionRegistry.ready, screen0: Quickshell.screens[0].name,
        fired: shellRoot.hotFired, active: HotCornersService.activeZone, configured: HotCornersService.configuredCorners,
        values: {topLeft: corners.topLeft, topRight: corners.topRight, bottomLeft: corners.bottomLeft,
                 bottomRight: corners.bottomRight, delayMs: corners.delayMs},
        cornerZones: ScreenZonesService.cornerZones, edgeEnabled: EdgeScrollService.enabled,
        edgeActive: EdgeScrollService.activeZone, edgeScreens: Object.keys(edges).length,
        barType: Settings.data.bar.barType, controlCenter: panel ? panel.isPanelOpen : false,
        settingsOpen: hotPanel() ? hotPanel().isPanelOpen : false});
    }
    function configure(text: string) {
      var values = JSON.parse(text);
      if (values.barType !== undefined) Settings.data.bar.barType = values.barType;
      if (values.edgeScrolling !== undefined) Settings.data.bar.edgeScrolling = values.edgeScrolling;
      if (values.delayMs !== undefined) Settings.data.general.hotCorners.delayMs = values.delayMs;
    }
    function openPage() {
      var panel = hotPanel();
      panel.openToTab(10, 3);
    }
    function page(): string {
      var panel = hotPanel();
      var page = hotPage();
      if (!panel || !panel.isPanelVisible || !panel.sizeAnimationComplete || !page) return JSON.stringify({ready: false});
      // General is the first, already-loaded tab: re-request a pending sub-tab.
      if (!page.visible && panel._settingsContent._pendingSubTab === 3) panel.openToTab(10, 3);
      var fields = {};
      for (var name of ["topLeft", "topRight", "bottomLeft", "bottomRight"]) {
        fields[name] = hotDescribe(hotField(name));
        fields[name + "-seconds"] = hotDescribe(hotField(name + "-seconds"));
      }
      var sliderRow = hotFind(page, x => x.objectName === "hotCornersDelaySlider");
      var slider = hotFind(sliderRow, x => x.snapMode !== undefined && x.handle !== undefined);
      return JSON.stringify({ready: page.visible, fields: fields,
        slider: slider ? {rect: hotRect(slider), handle: hotRect(slider.handle), leftPadding: slider.leftPadding,
                          availableWidth: slider.availableWidth, value: slider.value, from: slider.from, to: slider.to} : null});
    }
    function reveal(name: string) {
      var item = name === "top" ? hotPage() : name === "slider" ? hotFind(hotPage(), x => x.objectName === "hotCornersDelaySlider") : hotField(name);
      if (!item) return;
      for (var p = item.parent; p; p = p.parent) {
        if (p.contentY !== undefined && p.contentHeight !== undefined) {
          var pos = item.mapToItem(p.contentItem, 0, 0);
          p.contentY = name === "top" ? 0 : Math.max(0, Math.min(p.contentHeight - p.height, pos.y - 40));
          return;
        }
      }
    }
    function closePanels() { if (PanelService.openedPanel) PanelService.openedPanel.closeImmediately(); }
    function stop() { Qt.quit(); }
  }
'''


def run(argv, **kwargs):
    return subprocess.run(list(map(str, argv)), check=True, text=True, capture_output=True, timeout=30, **kwargs).stdout


def wait_for(function, description, timeout=20):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = function()
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError, TypeError):
            last = None
        if last:
            return last
        time.sleep(.05)
    raise AssertionError(f'timed out: {description}; last={last!r}')


def corner_point(output, corner):
    """Two pixels inside the corner of a 1280x800 output at x offset 0/1280."""
    x0 = 0 if output == 'Virtual-1' else 1280
    x = x0 + (2 if corner.endswith('Left') else 1277)
    y = 2 if corner.startswith('top') else 797
    return x, y


def inside(shell, work, cases):
    results = []
    fixtures = []
    pointer = None
    process = None
    fired_log = work / 'fired.log'

    def ipc(method, *values):
        return run(['qs', 'ipc', '--pid', process.pid, 'call', 'hotCornersE2e', method, *values]).strip()

    def state():
        return json.loads(ipc('state'))

    def page():
        return json.loads(ipc('page'))

    def configure(**values):
        ipc('configure', json.dumps(values))
        time.sleep(.3)

    def niri(*args):
        return run(['niri', 'msg', *args])

    def focused():
        return json.loads(niri('-j', 'focused-window'))

    def column():
        return focused()['layout']['pos_in_scrolling_layout'][0]

    def overview_open():
        return json.loads(niri('-j', 'overview-state'))['is_open']

    def pointer_command(command):
        pointer.stdin.write(command + '\n')
        pointer.stdin.flush()
        assert select.select([pointer.stdout], [], [], 20)[0], 'pointer acknowledgement timeout'
        assert pointer.stdout.readline().strip() == 'OK'

    def move(x, y):
        pointer_command(f'move {int(x)} {int(y)} 2560 800')

    def click(rect):
        assert rect and rect['visible'], rect
        move(rect['x'] + rect['width'] / 2, rect['y'] + rect['height'] / 2)
        time.sleep(.05)
        pointer_command('button 272 1')
        pointer_command('button 272 0')
        time.sleep(.15)

    def keys(*names):
        run(['wtype', *[v for name in names for v in ('-k', name)]])
        time.sleep(.15)

    def replace(text):
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '--', text])
        time.sleep(.2)

    def rest():
        move(640, 400)
        time.sleep(.15)

    def lines():
        return fired_log.read_text().split() if fired_log.exists() else []

    def hold(x, y, seconds):
        rest()
        move(x, y)
        time.sleep(seconds)
        rest()
        time.sleep(.35)

    def passed(name, **details):
        results.append(dict(name=name, passed=True, **details))
        (work / 'cases.json').write_text(json.dumps(results, indent=2))
        print('PASS ' + name, flush=True)

    def screenshot(name):
        time.sleep(.3)
        run(['grim', '-o', 'Virtual-1', work / (name + '.png')])

    def spawn(title):
        log = (work / (title + '.log')).open('w')
        child = subprocess.Popen(['foot', '--app-id=hot-corner-fixture', '--title=' + title,
                                  'sh', '-c', 'printf "Hot corner test window\\n"; sleep 1700'], stdout=log, stderr=log)
        fixtures.append((child, log))
        return wait_for(lambda: next((w for w in json.loads(niri('-j', 'windows')) if w['title'] == title), None), title)

    def expect_one(name, output, corner, x=None, y=None, seconds=.5):
        before, fired = lines(), len(state()['fired'])
        px, py = (x, y) if x is not None else corner_point(output, corner)
        hold(px, py, seconds)
        after = wait_for(lambda: (l if len(l := lines()) > len(before) else None), f'{name}: line for {output} {corner}', 3)
        time.sleep(.3)
        after = lines()
        new = after[len(before):]
        assert new == [corner], (name, output, corner, new)
        events = state()['fired'][fired:]
        assert events == [{'corner': corner, 'screen': output}], (name, events)

    def expect_none(name, x, y, seconds):
        before, fired = lines(), len(state()['fired'])
        hold(x, y, seconds)
        time.sleep(.5)
        assert lines() == before and len(state()['fired']) == fired, (name, lines()[len(before):])

    def layers():
        return [layer['namespace'] for layer in json.loads(niri('-j', 'layers'))
                if layer['namespace'].startswith('atmosphera-hot-corner-')]

    def open_page():
        ipc('closePanels')
        ipc('openPage')
        wait_for(lambda: page()['ready'], 'hot corners page')
        time.sleep(.4)
        return page()

    def field(name):
        return page()['fields'][name]

    def open_field(name):
        ipc('reveal', name)
        time.sleep(.2)
        click(field(name)['slot'])
        return wait_for(lambda: (f if (f := field(name))['popupOpened'] else None), f'{name} popup')

    try:
        process = subprocess.Popen(['qs', '-p', shell, '--no-color'])
        wait_for(lambda: state()['ready'], 'shell IPC readiness', 60)
        assert state()['screen0'] == 'Virtual-1'
        outputs = json.loads(niri('-j', 'outputs'))
        logical = {name: o['logical'] for name, o in outputs.items() if o['logical']}
        assert logical['Virtual-1'] == {**logical['Virtual-1'], 'x': 0, 'y': 0, 'width': 1280, 'height': 800}, logical
        assert logical['Virtual-2'] == {**logical['Virtual-2'], 'x': 1280, 'y': 0, 'width': 1280, 'height': 800}, logical
        pointer = subprocess.Popen([work / 'pointer-build/pointer'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, text=True, bufsize=1)
        assert select.select([pointer.stdout], [], [], 20)[0], 'virtual pointer readiness timeout'
        assert pointer.stdout.readline().strip() == 'READY'
        niri('action', 'close-overview')
        rest()
        initial = state()
        assert initial['configured'] == CORNERS and initial['values']['delayMs'] == 200, initial
        expected_layers = sorted(f'atmosphera-hot-corner-{o}-{c}' for o in ('Virtual-1', 'Virtual-2') for c in CORNERS)
        wait_for(lambda: sorted(layers()) == expected_layers, 'eight corner layer surfaces')
        overlay = [l for l in json.loads(niri('-j', 'layers')) if l['namespace'].startswith('atmosphera-hot-corner-')]
        assert all(l['layer'] == 'Overlay' and l['keyboard_interactivity'] == 'None' for l in overlay), overlay
        (work / 'layers-initial.json').write_text(niri('-j', 'layers'))
        passed('setup: eight Overlay corner surfaces, no keyboard focus', layers=expected_layers)

        bar_types = ['framed', 'simple', 'floating'] if 'H1' in cases else ['framed'] if 'H1-framed' in cases else []
        for bar_type in bar_types:
            configure(barType=bar_type)
            wait_for(lambda: state()['barType'] == bar_type, bar_type)
            time.sleep(1)
            for output in ('Virtual-1', 'Virtual-2'):
                for corner in CORNERS:
                    expect_one(f'H1 {bar_type}', output, corner)
            passed(f'H1 {bar_type}: each of 8 corners, 500 ms hold, exactly one line for that corner and output')
        configure(barType='framed')

        if 'H2' in cases:
            expect_none('H2', *corner_point('Virtual-1', 'bottomRight'), .08)
            expect_none('H2 inner', *corner_point('Virtual-2', 'bottomLeft'), .08)
            passed('H2: 80 ms pass-through fires nothing')

        if 'H3' in cases:
            before = lines()
            hold(*corner_point('Virtual-1', 'topRight'), 2)
            time.sleep(.3)
            assert lines()[len(before):] == ['topRight'], lines()[len(before):]
            hold(*corner_point('Virtual-1', 'topRight'), .5)
            time.sleep(.3)
            assert lines()[len(before):] == ['topRight', 'topRight'], lines()[len(before):]
            passed('H3: 2 s hold fires once; leave and re-enter fires once more')

        if 'H4' in cases:
            before = lines()
            x, y = corner_point('Virtual-1', 'bottomLeft')
            rest(); pointer_command('button 272 1'); move(x, y); time.sleep(.5)
            pointer_command('button 272 0'); time.sleep(.5); rest(); time.sleep(.3)
            assert lines() == before, lines()[len(before):]
            move(x, y); time.sleep(.05); pointer_command('button 272 1'); time.sleep(.5)
            pointer_command('button 272 0'); time.sleep(.5); rest(); time.sleep(.3)
            assert lines() == before, lines()[len(before):]
            # Right and middle presses in the corner are harmless too.
            for code in (273, 274):
                move(x, y); time.sleep(.05); pointer_command(f'button {code} 1'); time.sleep(.5)
                pointer_command(f'button {code} 0'); time.sleep(.3); rest(); time.sleep(.3)
                assert lines() == before and process.poll() is None, (code, lines()[len(before):])
            expect_one('H4 re-armed', 'Virtual-1', 'bottomLeft')
            passed('H4: button held on entry and left/right/middle presses during the dwell fire nothing; leaving re-arms')

        fullscreen_window = None
        if 'H5' in cases or 'H9' in cases:
            niri('action', 'focus-monitor', 'Virtual-1')
            for col in range(3):
                window = spawn(f'hot-corner-{col}')
                if fullscreen_window is None:
                    fullscreen_window = window
            (work / 'fixture-windows.json').write_text(niri('-j', 'windows'))

        if 'H5' in cases:
            niri('action', 'focus-window', '--id', str(fullscreen_window['id']))
            wait_for(lambda: focused()['id'] == fullscreen_window['id'], 'fixture focused')
            rest()
            niri('action', 'fullscreen-window')
            wait_for(lambda: focused()['layout']['window_size'] == [1280, 800], 'fullscreen fixture geometry')
            for bar_type in ('framed', 'simple'):
                configure(barType=bar_type)
                time.sleep(1)
                if bar_type == 'framed':
                    screenshot('h5-fullscreen-framed')
                expect_one(f'H5 {bar_type}', 'Virtual-1', 'topRight')
                expect_one(f'H5 {bar_type}', 'Virtual-1', 'bottomRight')
                assert focused()['layout']['window_size'] == [1280, 800], 'fixture left fullscreen'
            niri('action', 'fullscreen-window')
            wait_for(lambda: focused()['layout']['window_size'] != [1280, 800], 'leave fullscreen')
            configure(barType='framed')
            passed('H5: above a fullscreen window (framed and simple), TR and BR fire once each')

        if 'H6' in cases:
            before = lines()
            rest()
            assert not overview_open()
            move(0, 0)
            wait_for(overview_open, 'niri native corner opens the overview', 3)
            time.sleep(.5)
            assert lines() == before, lines()[len(before):]
            niri('action', 'close-overview')
            wait_for(lambda: not overview_open(), 'overview closed')
            move(2, 2)
            time.sleep(.5)
            assert not overview_open()
            rest(); time.sleep(.3)
            assert lines()[len(before):] == ['topLeft'], lines()[len(before):]
            assert not overview_open()
            passed('H6: niri keeps the exact corner pixel (overview, no line); (2,2) fires TL once, overview stays closed')

        if 'H9' in cases:
            configure(barType='framed', edgeScrolling=True)
            wait_for(lambda: state()['edgeEnabled'], 'edge scrolling enabled')
            # niri lists windows in no particular order: take the first spawned,
            # leftmost column so the right edge has a column to step to.
            first = next(w['id'] for w in json.loads(niri('-j', 'windows')) if w['title'] == 'hot-corner-0')
            niri('action', 'focus-window', '--id', str(first))
            wait_for(lambda: focused()['id'] == first, 'first fixture focused')
            start = column()
            hold(1276, 400, .95)
            assert column() == start + 1, (start, column())
            start = column()
            before, fired = lines(), len(state()['fired'])
            rest()
            move(*corner_point('Virtual-1', 'bottomRight'))
            samples = []
            for _ in range(8):
                time.sleep(.06)
                samples.append(state()['edgeActive'])
            rest(); time.sleep(.6)
            assert lines()[len(before):] == ['bottomRight'], lines()[len(before):]
            assert state()['fired'][fired:] == [{'corner': 'bottomRight', 'screen': 'Virtual-1'}], state()['fired'][fired:]
            assert column() == start and all(sample is None for sample in samples), (column(), samples)
            passed('H9: framed with edge scrolling, the right edge steps once; BR fires, no edge step')

        if 'H7' in cases:
            open_page()
            ipc('reveal', 'bottomRight')
            time.sleep(.3)
            click(field('bottomRight')['clear'])
            wait_for(lambda: state()['values']['bottomRight'] == '', 'BR cleared by the page')
            ipc('closePanels')
            wanted = sorted(n for n in expected_layers if not n.endswith('-bottomRight'))
            wait_for(lambda: sorted(layers()) == wanted, 'BR corner surfaces removed')
            expect_none('H7', *corner_point('Virtual-1', 'bottomRight'), .5)
            passed('H7: clearing BR on the page removes both BR surfaces; holding BR fires nothing', layers=wanted)

        if 'H8' in cases:
            custom = "printf '%s\\n' customBottomLeft >> " + shlex.quote(str(fired_log))
            untouched = state()['values']['bottomRight']
            open_page()
            open_field('topLeft')
            replace('control center')
            keys('Return')
            wait_for(lambda: state()['values']['topLeft'] == 'atmosphera ipc controlCenter toggle', 'TL control center')
            open_field('topRight')
            replace('keep awake for')
            keys('Return')
            wait_for(lambda: state()['values']['topRight'] == 'atmosphera ipc idleInhibitor enableFor 900', 'TR keep awake')
            ipc('reveal', 'topRight-seconds')
            time.sleep(.2)
            click(field('topRight-seconds')['rect'])
            replace('1200')
            wait_for(lambda: state()['values']['topRight'] == 'atmosphera ipc idleInhibitor enableFor 1200', 'TR 1200 s')
            f = open_field('bottomLeft')
            click(f['footer'])
            wait_for(lambda: field('bottomLeft')['editor']['visible'], 'custom editor')
            replace(custom)
            click(field('bottomLeft')['use'])
            wait_for(lambda: state()['values']['bottomLeft'] == custom, 'BL custom command')
            ipc('reveal', 'slider')
            time.sleep(.3)
            slider = page()['slider']
            fraction = (600 - slider['from']) / (slider['to'] - slider['from'])
            handle = slider['handle']['width']
            x = slider['rect']['x'] + slider['leftPadding'] + fraction * (slider['availableWidth'] - handle) + handle / 2
            click(dict(x=x - .5, y=slider['handle']['y'] + slider['handle']['height'] / 2 - .5, width=1, height=1, visible=True))
            wait_for(lambda: state()['values']['delayMs'] == 600, 'delay 600 from the slider')
            ipc('reveal', 'top')
            screenshot('h8-page-populated-framed')
            open_field('topLeft')
            replace('panel')
            time.sleep(.3)
            screenshot('h8-picker-open')
            keys('Escape')
            ipc('closePanels')
            expected = {'topLeft': 'atmosphera ipc controlCenter toggle',
                        'topRight': 'atmosphera ipc idleInhibitor enableFor 1200',
                        'bottomLeft': custom, 'bottomRight': untouched, 'delayMs': 600}
            shard = work / 'config/atmosphera/settings/general.json'

            def persisted():
                stored = json.loads(shard.read_text()).get('hotCorners', {})
                return {**{'topLeft': '', 'topRight': '', 'bottomLeft': '', 'bottomRight': '', 'delayMs': 200}, **stored}
            wait_for(lambda: persisted() == expected, 'general shard holds the page values', 10)
            (work / 'general-shard.json').write_text(shard.read_text())
            before = lines()
            hold(*corner_point('Virtual-1', 'bottomLeft'), .4)
            time.sleep(.4)
            assert lines() == before, lines()[len(before):]
            hold(*corner_point('Virtual-1', 'bottomLeft'), .8)
            wait_for(lambda: lines()[len(before):] == ['customBottomLeft'], 'custom BL after 800 ms', 3)
            assert not state()['controlCenter']
            hold(*corner_point('Virtual-1', 'topLeft'), .8)
            wait_for(lambda: state()['controlCenter'], 'TL opens the control center', 5)
            ipc('closePanels')
            passed('H8: page round trip persists exact strings and 600; 400 ms no fire, 800 ms fires; TL opens the control center',
                   persisted=expected)
        print('HOT_CORNERS_E2E: PASS', flush=True)
    finally:
        if pointer is not None:
            pointer.stdin.close()
            pointer.wait(timeout=10)
        for child, log in fixtures:
            child.terminate()
            child.wait(timeout=10)
            log.close()
        try:
            niri('action', 'close-overview')
        except subprocess.SubprocessError:
            pass
        if process is not None:
            try:
                ipc('stop')
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                pass
            process.wait(timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path)
    parser.add_argument('--case', default='all', help='all, or a comma list of ' + ', '.join(CASES + ['H1-framed']))
    parser.add_argument('--inside', nargs=2, type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    cases = CASES if args.case == 'all' else args.case.split(',')
    unknown = [case for case in cases if case not in CASES + ['H1-framed']]
    if unknown:
        parser.error(f'unknown case: {unknown}')
    if args.inside:
        return inside(*args.inside, cases)
    source = args.source.resolve()
    work = (args.workspace or source.parent / ('hot-corners-e2e-' + time.strftime('%Y%m%d-%H%M%S'))).resolve()
    check_execution_paths(parser, work, source=source)
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
    owner = probe_owner_path(shell)
    owner.write_text('import Quickshell.Io\nimport qs.Services.Actions\n' + inject_probe(owner.read_text(), PROBE))
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', DISPLAY='', ATMOSPHERA_UPGRADELOG_URL='http://127.0.0.1:9')
    # The default (GL) scene graph, as in the action-picker captures: the
    # software backend does not draw the colourised icons.
    env.pop('QT_QUICK_BACKEND', None)
    # Corner commands such as "atmosphera ipc ..." reach this instance.
    env['PATH'] = str(shell / 'Scripts/bash') + ':' + env['PATH']
    for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
        (work / leaf).mkdir()
        env[key] = str(work / leaf)
    settings = work / 'config/atmosphera/settings'
    settings.mkdir(parents=True)
    commands = {corner: f"printf '%s\\n' {corner} >> {shlex.quote(str(work / 'fired.log'))}" for corner in CORNERS}
    (settings / 'general.json').write_text(json.dumps({'showChangelogOnStartup': False,
                                                       'hotCorners': {**commands, 'delayMs': 200}}))
    # Same visual fixture as the action-picker captures: icon set and UI font.
    (settings / 'ui.json').write_text(json.dumps({'fontDefault': 'Liberation Sans'}))
    shutil.copytree(shell / 'builtin/plugins/atmosphera-icons', work / 'config/atmosphera/plugins/atmosphera-icons')
    (work / 'config/atmosphera/plugins.json').write_text(json.dumps(
        {'version': 5, 'sources': [], 'states': {'atmosphera-icons': {'enabled': True}}}))
    build = work / 'pointer-build'
    build.mkdir()
    protocol = source / 'Scripts/dev/wlr-virtual-pointer-unstable-v1.xml'
    for mode, name in [('client-header', 'virtual-pointer-client.h'), ('private-code', 'virtual-pointer-protocol.c')]:
        run(['wayland-scanner', mode, protocol, build / name])
    flags = run(['pkg-config', '--cflags', '--libs', 'wayland-client']).split()
    run(['cc', '-I', build, source / 'Scripts/dev/edge-scroll-test-pointer.c', build / 'virtual-pointer-protocol.c',
         *flags, '-o', build / 'pointer'])
    outputs_before = json.loads(run(['niri', 'msg', '-j', 'outputs']))
    execution = run_harness(['dbus-run-session', '--', sys.executable, '-B', __file__, '--inside', shell, work,
                             '--case', ','.join(cases)], work, env, 1500)
    outputs_after = json.loads(run(['niri', 'msg', '-j', 'outputs']))
    text = (work / 'shell.log').read_text(errors='replace')
    errors = [line for line in text.splitlines() if re.search(
        r'TypeError:|ReferenceError:|SyntaxError:|is not a type|Failed to load configuration', line)]
    cases_file = work / 'cases.json'
    receipt = dict(passed='HOT_CORNERS_E2E: PASS' in text and not errors and outputs_before == outputs_after,
                   cases=json.loads(cases_file.read_text()) if cases_file.exists() else [],
                   outputs_unchanged=outputs_before == outputs_after, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
