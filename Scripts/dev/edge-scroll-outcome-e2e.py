#!/usr/bin/env python3
"""Outcome feedback acceptance on both real niri outputs, assigned VM only."""
import importlib.util
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import threading
import time
from PIL import Image, ImageChops

spec = importlib.util.spec_from_file_location('edge_e2e', Path(__file__).with_name('edge-scroll-e2e.py'))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)
harness.PROBE = harness.PROBE.replace('property int edgePulseCount: 0', r'''
  property int edgePulseCount: 0
  property var edgeOutcomes: []
  property var directOutcomes: []
  property var edgeFrames: []
  Connections {
    target: EdgeScrollService
    ignoreUnknownSignals: true
    function onNavigationFinished(zone, outcome) {
      shellRoot.edgeOutcomes.push({zone: zone, outcome: outcome, at: Date.now()});
    }
  }
  FrameAnimation {
    running: EdgeScrollService.activeZone !== null
    onTriggered: shellRoot.edgeFrames.push({at: Date.now(), progress: EdgeScrollService.progress,
      wall: EdgeScrollService["wallFeedback"] || false, pulse: EdgeScrollService.stepPulse,
      reduced: EdgeScrollService.reducedMotion})
  }
''').replace('ready: Settings.isLoaded,', '''direct: shellRoot.directOutcomes, outcomes: shellRoot.edgeOutcomes,
        frames: shellRoot.edgeFrames, wall: EdgeScrollService["wallFeedback"] || false,
        ready: Settings.isLoaded,''').replace('function stop() {',
            r'''function clearFrames() { shellRoot.edgeFrames=[]; }
    function dismissStartupToast() { ToastService.dismissToast(); }
    function direct(output: string, edge: string, requestId: int) {
      CompositorService.niriBackend.navigateEdge(output,edge,requestId,function(result) {
        shellRoot.directOutcomes.push(result);
      });
    }
    function concurrent() {
      direct("Virtual-1","top",901);
      direct("Virtual-2","bottom",902);
    }
    function stop() {''')


def inside(shell, work, daemon=False):
    run, wait = harness.run, harness.wait_for
    # Transparent, guest-local IPC proxy: retain the real compositor traffic and
    # inject one explicit transport error without mutating niri or its session.
    real_socket = os.environ['NIRI_SOCKET']
    proxy_path = str(work/'niri.sock')
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(proxy_path); listener.listen()
    fail_query = threading.Event()
    wire = (work/'wire.jsonl').open('w')
    wire_lock = threading.Lock()
    def record(direction, connection, line):
        with wire_lock:
            wire.write(json.dumps(dict(at=time.monotonic(),direction=direction,
                connection=connection,data=line.decode(errors='replace'))) + '\n'); wire.flush()
    def relay(source, destination, direction, connection):
        buffer=b''
        try:
            while chunk:=source.recv(65536):
                buffer+=chunk
                while b'\n' in buffer:
                    line,buffer=buffer.split(b'\n',1); record(direction,connection,line)
                destination.sendall(chunk)
        except OSError:
            pass
        finally:
            try: destination.shutdown(socket.SHUT_WR)
            except OSError: pass
    def accept():
        connection=0
        while True:
            try: client,_=listener.accept()
            except OSError: return
            connection+=1
            first=b''
            while b'\n' not in first:
                chunk=client.recv(65536)
                if not chunk: break
                first+=chunk
            if fail_query.is_set() and first.strip()==b'"Workspaces"':
                fail_query.clear(); record('shell->niri',connection,first.strip())
                response=b'{"Err":"edge navigation injected test error"}\n'
                record('niri->shell',connection,response.strip()); client.sendall(response); client.close()
                continue
            server=socket.socket(socket.AF_UNIX); server.connect(real_socket)
            record('shell->niri',connection,first.strip()); server.sendall(first)
            for source,destination,direction in [(client,server,'shell->niri'),(server,client,'niri->shell')]:
                threading.Thread(target=relay,args=(source,destination,direction,connection),daemon=True).start()
    threading.Thread(target=accept,daemon=True).start()
    owner = harness.probe_owner_path(shell)
    owner.write_text('import qs.Services.Compositor\n' + owner.read_text())
    glow = shell / 'Modules/MainScreen/EdgeScrollGlow.qml'
    frame_probe = r'''
  property bool wallCaptureDone: false
  FrameAnimation {
    running: root.wall && root.zone !== null
    onTriggered: {
      var shape=root.children[0];
      console.log("EDGE_WALL_FRAME", JSON.stringify({at:Date.now(),edge:root.zone.edge,
        output:root.zone.screenName,phase:root.wallPhase,recoil:root.recoil,opacity:root.opacity,
        depth:root.depth,reduced:root.reducedMotion,bounds:[root.width,root.height],
        shape:[shape.x,shape.y,shape.width,shape.height]}));
      if (!root.wallCaptureDone && root.wallPhase > 0.25) {
        root.wallCaptureDone=true;
        Quickshell.execDetached(["grim","-o",root.zone.screenName,CAPTURE_ROOT + "/rendered-wall-" +
          root.zone.screenName + "-" + root.zone.edge + (root.reducedMotion ? "-reduced" : "-motion") + ".png"]);
      }
    }
  }
'''.replace('CAPTURE_ROOT', json.dumps(str(work)))
    glow.write_text('import Quickshell\n' + glow.read_text().replace('id: root', 'id: root\n' + frame_probe, 1)
                    .replace('if (wall) {', 'if (wall) { wallCaptureDone=false;', 1))
    if os.environ.get('EDGE_SCROLL_DIAGNOSTICS') == '1':
        backend = shell / 'Services/Compositor/NiriIpcBackend.qml'
        text = backend.read_text().replace('function navigateEdge(output, edge, requestId, completed) {',
            'function navigateEdge(output, edge, requestId, completed) { console.log("EDGE_REQUEST", output, edge, requestId, _edgeNavigationBusy);')
        text = text.replace('function finish(outcome) {', 'function finish(outcome) { console.log("EDGE_RESULT",requestId,outcome);')
        text = text.replace('var target = EdgeNavigation.resolve(output, edge, workspaceList, windowList);',
            'var target = EdgeNavigation.resolve(output, edge, workspaceList, windowList); console.log("EDGE_TARGET",JSON.stringify(target));')
        backend.write_text(text)
        controller = shell / 'Services/UI/EdgeScrollController.qml'
        controller.write_text(controller.read_text().replace('function resolveNavigation(requestId, outcome) {',
            'function resolveNavigation(requestId, outcome) { console.log("EDGE_RESOLVE",requestId,outcome,_pendingRequestId,JSON.stringify(activeZone));'))
    process = subprocess.Popen(['qs', '-p', shell, '--no-color'],env=dict(os.environ,NIRI_SOCKET=proxy_path))
    pointer = None
    fixtures = []
    cases = []
    config = Path('/home/tester/.config/niri/config.kdl')
    original_config = config.read_text()
    (work / 'niri-config-before.kdl').write_text(original_config)

    def ipc(method, *values):
        return run(['qs', 'ipc', '--pid', str(process.pid), 'call', 'edgeScrollTest', method, *values]).strip()
    def state():
        return json.loads(ipc('state'))
    def configure(**values):
        ipc('configure', json.dumps(values))
        time.sleep(.08)
    def niri(*args):
        return run(['niri', 'msg', *args])
    def action(*args):
        niri('action', *args)
    def query(name):
        return json.loads(niri('-j', name))
    def move(x, y):
        pointer.stdin.write(f'move {x} {y} 2560 800\n'); pointer.stdin.flush()
        assert select.select([pointer.stdout], [], [], 10)[0]
        assert pointer.stdout.readline().strip() == 'OK'
    def rest():
        move(600, 400)
        wait(lambda: state()['active'] is None, 'pointer leaves edge')
        time.sleep(.1)
    def passed(name, **details):
        cases.append(dict(name=name, passed=True, **details))
        (work / 'cases.json').write_text(json.dumps(cases, indent=2))
        print('PASS ' + name, flush=True)
    def capture(name, output):
        run(['grim', '-o', output, work / (name + '.png')])
    def attempt(output, edge, expected, name, capture_wall=False, cross_output=False):
        rest()
        ipc('clearFrames')
        before = state()
        windows = query('windows')
        positions = dict(left=(0 if output == 'Virtual-1' else 1282, 400),
                         right=(1276 if output == 'Virtual-1' else 2559, 400),
                         top=(600 if output == 'Virtual-1' else 1880, 0),
                         bottom=(600 if output == 'Virtual-1' else 1880, 799))
        move(*positions[edge])
        wait(lambda: state()['active'], 'edge entered')
        if capture_wall:
            wait(lambda: .45 < state()['progress'] < .7, 'ramp')
            capture(name + '-ramp', output)
        # Old implementation has no outcome contract: still observe its false pulse.
        def feedback():
            current = state()
            return current if (len(current['outcomes']) > len(before['outcomes']) or
                               current['pulseCount'] > before['pulseCount']) else None
        try:
            after = wait(feedback, 'navigation feedback', 4)
        except AssertionError:
            (work / (name + '-timeout.json')).write_text(json.dumps(dict(state=state(),
                workspaces=query('workspaces'),windows=query('windows')), indent=2))
            raise
        if capture_wall:
            capture(name + '-wall', output)
        if expected != 'moved':
            assert after['pulseCount'] == before['pulseCount'], 'false success pulse: ' + name
        assert len(after['outcomes']) == len(before['outcomes']) + 1, ('missing outcome', name, after)
        outcome = after['outcomes'][-1]
        assert outcome['outcome'] == expected, (name, outcome)
        assert outcome['zone']['screenName'] == output and outcome['zone']['edge'] == edge
        if expected == 'boundary':
            assert after['wall'] or any(f['wall'] for f in after['frames'][len(before['frames']):]), ('confirmed boundary has no wall', name)
            wait(lambda: not state()['wall'], 'wall finishes', 1)
        else:
            assert not after['wall'], ('false wall', name)
        if expected == 'moved':
            if cross_output and after['active'] is None:
                assert after['pulseCount'] == before['pulseCount'], ('pointer warp flashed a cancelled hold', name)
            else:
                assert after['pulseCount'] == before['pulseCount'] + 1, ('missing moved pulse', name)
        rest()
        passed(name, outcome=outcome, before_windows=windows, after_windows=query('windows'),
               frames=state()['frames'][len(before['frames']):])

    try:
        def ready():
            try: return state()['ready']
            except (subprocess.CalledProcessError, json.JSONDecodeError): return False
        wait(ready, 'shell ready', 60)
        configure(setting=False, dock=False, hideOnOverview=False)
        action('close-overview')
        # Keep pointer focus independent of keyboard focus for cross-output proof.
        config.write_text(original_config.replace('focus-follows-mouse max-scroll-amount="10%"',
                                                  '// focus-follows-mouse max-scroll-amount="10%"'))
        niri('output', 'Virtual-2', 'on')
        wait(lambda: sum(o['logical'] is not None for o in query('outputs').values()) == 2, 'two outputs')
        pointer = subprocess.Popen([work / 'pointer-build/pointer'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, text=True, bufsize=1)
        assert pointer.stdout.readline().strip() == 'READY'
        for output in ['Virtual-1', 'Virtual-2']:
            configure(setting=False)
            rest(); action('focus-monitor', output); action('focus-workspace', '1')
            ids = []
            for i in range(3):
                title = output + '-outcome-' + str(i)
                child = subprocess.Popen(['foot', '--app-id=edge-outcome-fixture', '--title=' + title,
                    '-o', 'colors-dark.background=' + ['302030', '203030', '303020'][i],
                    'python3', '-B', '-c', 'import time; print(' + repr(title + ' ' + ' '.join(f'{n:03}' for n in range(200))) + '); time.sleep(600)'])
                fixtures.append(child)
                window = wait(lambda: next((w for w in query('windows') if w['title'] == title), None), title)
                ids.append(window['id'])
                action('set-column-width', '1800')
            action('focus-window', '--id', str(ids[-1])); time.sleep(.6)
            # The private DBus harness cannot activate the real user systemd
            # bindings queue. Its retained startup diagnostic is unrelated to
            # these captures; dismiss it through its owner before visual proof.
            ipc('dismissStartupToast'); time.sleep(.2)
            capture(output + '-wide-rest', output)
            configure(setting=True)
            attempt(output, 'right', 'boundary', output + '-wide-last-right', True)
            capture(output + '-wide-after', output)
            before_client = Image.open(work / (output + '-wide-rest.png')).crop((100,400,1200,700))
            after_client = Image.open(work / (output + '-wide-after.png')).crop((100,400,1200,700))
            assert ImageChops.difference(before_client, after_client).getbbox() is None, 'wall moved wide client pixels'
            # A floating active window cannot establish tiled bounds.
            configure(setting=False); action('toggle-window-floating'); time.sleep(.3)
            configure(setting=True)
            attempt(output, 'right', 'unknown', output + '-floating-no-wall')
            configure(setting=False); action('toggle-window-floating')
            for wid in ids:
                action('focus-window', '--id', str(wid)); action('set-column-width', '1100')
            action('focus-window', '--id', str(ids[0])); time.sleep(.6)
            configure(setting=True)
            attempt(output, 'left', 'boundary', output + '-first-left')
            # Keyboard focus deliberately starts on the other output.
            configure(setting=False)
            action('focus-monitor', 'Virtual-2' if output == 'Virtual-1' else 'Virtual-1')
            configure(setting=True)
            capture(output + '-neighbour-before', output)
            attempt(output, 'right', 'moved', output + '-partly-visible-cross-output', cross_output=True)
            assert query('focused-window')['id'] == ids[1]
            assert next(w for w in query('workspaces') if w['is_focused'])['output'] == output
            capture(output + '-neighbour-after', output)
            before_client = Image.open(work / (output + '-neighbour-before.png')).crop((100,400,1200,700))
            after_client = Image.open(work / (output + '-neighbour-after.png')).crop((100,400,1200,700))
            assert ImageChops.difference(before_client, after_client).getbbox() is not None, 'focus changed without displayed client movement'
            attempt(output, 'left', 'moved', output + '-left-moved')
            attempt(output, 'right', 'moved', output + '-partly-visible-pulse')
            attempt(output, 'left', 'moved', output + '-left-return')
            attempt(output, 'top', 'boundary', output + '-first-workspace-top')
            attempt(output, 'bottom', 'moved', output + '-trailing-empty-enter')
            attempt(output, 'bottom', 'boundary', output + '-trailing-empty-wall')
            attempt(output, 'top', 'moved', output + '-workspace-return')
            configure(animationDisabled=True)
            action('focus-window', '--id', str(ids[-1]))
            attempt(output, 'right', 'boundary', output + '-reduced-wall', True)
            configure(animationDisabled=False, setting=False)
            for child in fixtures:
                if child.poll() is None: child.terminate(); child.wait(timeout=10)
            fixtures = []
        rest()
        fail_query.set()
        ipc('direct','missing-output','right','900')
        wait(lambda: any(row['requestId']==900 for row in state()['direct']), 'error outcome')
        assert next(row for row in state()['direct'] if row['requestId']==900)['outcome']=='error'
        ipc('concurrent')
        wait(lambda: len(state()['direct'])==3, 'serialized adapter requests')
        direct = {row['requestId']:row['outcome'] for row in state()['direct']}
        assert direct=={900:'error',901:'boundary',902:'unknown'}, direct
        assert not state()['wall'] and not state()['pulse']
        passed('adapter error and concurrent cross-output requests stay correlated without a backlog', outcomes=direct)
        print('EDGE_SCROLL_E2E: PASS', flush=True)
    finally:
        config.write_text(original_config)
        (work / 'niri-config-after.kdl').write_text(config.read_text())
        if pointer is not None:
            pointer.stdin.close(); pointer.wait(timeout=10)
        for child in fixtures:
            if child.poll() is None: child.terminate(); child.wait(timeout=10)
        try: ipc('stop')
        except subprocess.SubprocessError: pass
        process.wait(timeout=20)
        listener.close()


if __name__ == '__main__':
    if '--inside' not in sys.argv and '--workspace' not in sys.argv and '--help' not in sys.argv:
        sys.exit('--workspace is required')
    harness.inside = inside
    harness.__file__ = __file__
    result = harness.main()
    if not result and '--inside' not in sys.argv:
        work = Path(sys.argv[sys.argv.index('--workspace') + 1]).resolve()
        receipt_path=work/'result.json'
        receipt=json.loads(receipt_path.read_text())
        receipt.update(passed=False,rendered_feedback=False)
        receipt_path.write_text(json.dumps(receipt,indent=2))
        frames = [json.loads(line.split('EDGE_WALL_FRAME ',1)[1]) for line in (work/'shell.log').read_text().splitlines()
                  if 'EDGE_WALL_FRAME ' in line]
        for frame in frames:
            x,y,width,height=frame['shape']; bound_width,bound_height=frame['bounds']
            assert x>=0 and y>=0 and x+width<=bound_width+.001 and y+height<=bound_height+.001, 'glow escaped the frame'
            compression=bound_width-width if frame['edge'] in ['left','right'] else bound_height-height
            assert abs(compression-frame['recoil'])<.001, 'rendered shape did not compress'
        for output in ['Virtual-1','Virtual-2']:
            for edge in ['left','right','top','bottom']:
                motion = [f for f in frames if f['output']==output and f['edge']==edge and not f['reduced']]
                assert motion and max(f['recoil'] for f in motion)>1.8, (output,edge,'no 2 px compression')
                assert all(0<=f['recoil']<=min(2,f['depth']) for f in motion)
            reduced = [f for f in frames if f['output']==output and f['reduced']]
            assert reduced and all(f['recoil']==0 for f in reduced), 'reduced motion displaced glow'
            assert any(f['phase']<.5 and abs(f['opacity']-.75)<.01 for f in reduced), 'no steady cap'
            assert any(f['phase']>.65 and f['opacity']<.6 for f in reduced), 'no reduced fade'
        (work/'wall-motion.json').write_text(json.dumps(frames,indent=2))
        receipt.update(passed=True,rendered_feedback=True)
        receipt_path.write_text(json.dumps(receipt,indent=2))
        print('PASS rendered four-edge 2 px compression/recoil and reduced-motion steady cap/fade')
    sys.exit(result)
