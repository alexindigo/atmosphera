#!/usr/bin/env python3
"""Actual OBS native page/Bar/CC/Panel consumers against a loopback protocol."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value

runner = module('obs_host', 'plugin-settings-host-assets-regression.py')
web = module('obs_frames', 'plugin-settings-query-lifecycle-regression.py')


class ObsConnection(web.HassConnection):
    def handle(self):
        import base64
        import socket
        self.server.sockets.add(self.request)
        try:
            self.rfile.readline(); headers = {}
            while True:
                line = self.rfile.readline().decode().strip()
                if not line: break
                key, value = line.split(':', 1); headers[key.lower()] = value.strip()
            digest = hashlib.sha1((headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()
            self.wfile.write(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + base64.b64encode(digest) + b'\r\n\r\n'); self.wfile.flush()
            self.server.record(event='open')
            self.send(dict(op=0, d=dict(rpcVersion=1)))
            while not self.server.stopping.is_set():
                row = self.receive()
                if row['op'] == 1:
                    self.send(dict(op=2, d=dict(negotiatedRpcVersion=1))); continue
                assert row['op'] == 6, row
                data = row['d']; kind = data['requestType']
                self.server.record(event='request', request=kind, data=data)
                hold = self.server.case/('hold-'+kind)
                if hold.exists():
                    (self.server.case/('held-'+kind)).write_text('held')
                    while hold.exists() and not self.server.stopping.wait(.02): pass
                state = json.loads((self.server.case/'obs-state.json').read_text())
                active = {'GetRecordStatus':'recording','GetReplayBufferStatus':'replay','GetStreamStatus':'streaming','GetVirtualCamStatus':'camera'}
                response = dict(outputActive=state.get(active.get(kind), False), outputDuration=61000) if kind in active else {}
                changes = {'StartRecord':('recording',True),'StopRecord':('recording',False),'StartReplayBuffer':('replay',True),'StopReplayBuffer':('replay',False),'StartStream':('streaming',True),'StopStream':('streaming',False)}
                if kind in changes:
                    state[changes[kind][0]] = changes[kind][1]; (self.server.case/'obs-state.json').write_text(json.dumps(state))
                failed = (self.server.case/('fail-'+kind)).exists()
                self.send(dict(op=7,d=dict(requestId=data['requestId'],requestType=kind,requestStatus=dict(result=not failed,code=500 if failed else 100,comment='synthetic failure'),responseData=response)))
        except (EOFError, OSError, socket.error):
            self.server.record(event='closed')
        except Exception as error:
            self.server.record(event='error', error=str(error))
        finally:
            self.server.sockets.discard(self.request)


class ObsEndpoint(web.HassEndpoint):
    def __init__(self, case):
        super().__init__(case); self.RequestHandlerClass = ObsConnection


ENDPOINT = '''#!/usr/bin/python3
import fcntl,json,os,sys,time
from pathlib import Path
b=Path(os.environ['PHA_OBS_CASE']);name=Path(sys.argv[0]).name;args=sys.argv[1:]
start=(Path('/proc')/str(os.getpid())/'stat').read_text().split(') ',1)[1].split()[19]
with (b/'requests.jsonl').open('a') as f:
 fcntl.flock(f,fcntl.LOCK_EX);f.write(json.dumps(dict(endpoint=name,argv=args,pid=os.getpid(),start=start))+'\\n');f.flush()
hold=b/('hold-'+name)
if hold.exists():
 (b/('held-'+name)).write_text(str(os.getpid()))
 parent=Path('/proc')/str(os.getppid())/'stat';identity=parent.read_text().split(') ',1)[1].split()[19]
 while hold.exists():
  try:
   if parent.read_text().split(') ',1)[1].split()[19]!=identity:raise SystemExit(0)
  except FileNotFoundError:raise SystemExit(0)
  time.sleep(.02)
if name=='pidof':raise SystemExit(0 if (b/'running').exists() else 1)
if name=='pkill':(b/'running').unlink(missing_ok=True)
elif name=='obs':(b/'running').write_text('inert')
elif name not in ('obs-open','obs-new-open'):raise SystemExit('unreviewed OBS endpoint '+name)
'''


def seed(case, plugins):
    for name in ('config/settings/plugins','config/obs-studio/plugin_config/obs-websocket','cache','state','home','bin'): (case/name).mkdir(parents=True)
    product=case/'config/plugins/obs-control'; shutil.copytree(plugins/'obs-control',product)
    runner.write_json(case/'config/settings.json',dict(settingsVersion=62)); runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
    runner.write_json(case/'obs-state.json',dict(recording=True,replay=False,streaming=False,camera=False))
    (case/'running').write_text('inert'); (case/'requests.jsonl').write_text(''); (case/'socket.jsonl').write_text('')
    for name in ('pidof','pkill','obs','obs-open','obs-new-open'):
        path=case/'bin'/name; path.write_text(ENDPOINT); path.chmod(0o755)
    return product


def hashes(case):
    return {str(p.relative_to(case)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((case/'config').rglob('*.json'))}


def run(args, profile, scope):
    with FixtureResources() as resources:
        return run_with_endpoint(args, profile, scope, resources)


def run_with_endpoint(args, profile, scope, resources):
    case,out=args.work_root/scope,args.output/scope; case.mkdir(); out.mkdir(); (out/'persisted').mkdir()
    install=case/'install'; shutil.copytree(args.source,install,copy_function=os.link,ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
    product=seed(case,args.original_plugins or args.plugins)
    if args.shared_reader:
        for name in ('BarWidget.qml','Panel.qml','ControlCenterWidget.qml','components/ObsButton.qml'):
            path=product/name; text=path.read_text(); old='settingsConsumerFor(root.pluginApi.settingsContext)'; assert text.count(old)==1
            path.write_text(text.replace(old,'settingsConsumerFor(root.pluginApi.mainInstance.pluginApi.settingsContext)'))
    resources.defer(shutil.copy2,case/'requests.jsonl',out/'requests.jsonl')
    resources.defer(shutil.copy2,case/'socket.jsonl',out/'socket.jsonl')
    endpoint=ObsEndpoint(case)
    resources.serve(endpoint,interrupt=endpoint.finish)
    runner.write_json(case/'config/obs-studio/plugin_config/obs-websocket/config.json',dict(server_enabled=True,server_port=endpoint.server_address[1],server_password=''))
    shared=dict(barLabelMode='icon-only',showElapsedInBar=True,pollIntervalMs=10000,showBarWhenReady=False,showBarWhenRecording=True,showControlCenterWhenRecording=True,opaque='shared')
    initial=dict(shared=shared,bar=dict(widgets=dict(left=[dict(id='plugin:obs-control',instanceSettings=row) for row in ({'opaque':'selected'},{'barLabelMode':'icon-only','showBarWhenRecording':False,'showControlCenterWhenRecording':False,'opaque':'sibling'},{'opaque':'inherited'})])))
    edited=deepcopy(initial); (edited['shared'] if scope=='shared' else edited['bar']['widgets']['left'][0]['instanceSettings'])['barLabelMode']='duration'
    reset=deepcopy(edited); (reset['shared'] if scope=='shared' else reset['bar']['widgets']['left'][0]['instanceSettings']).pop('barLabelMode')
    following=deepcopy(reset); following['shared']['barLabelMode']='short-label'
    expected=dict(initial=initial,discarded=initial,edited=edited,**{'reset-staged':edited},reset=reset,following=following)
    runner.write_json(case/'input.json',dict(plugin='obs-control'))
    runner.write_json(case/'expectations.json',expected); runner.write_json(case/'config/settings/plugins/obs-control.json',shared); runner.write_json(case/'config/settings/bar.json',initial['bar'])
    runner.write_json(out/'sources.json',{str(p.relative_to(product)):hashlib.sha256(p.read_bytes()).hexdigest() for p in product.rglob('*') if p.is_file()})
    env=dict(PHA_OBS_CASE=str(case),PHA_OBS_SCOPE=scope,PHA_OBS_DISK=str(args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py'),PHA_OBS_OUTPUT=str(out),HOME=str(case/'home'),XDG_CONFIG_HOME=str(case/'config'),PATH=str(case/'bin')+':'+os.environ['PATH'])
    controlled=bool(args.original_plugins or args.shared_reader)
    modes=[('edit','')] if controlled else [('edit',''),('cold','edited'),('reset',''),('cold','reset'),('follow',''),('cold','following')]
    for mode,boundary in modes:
        part=out/(mode+('-'+boundary if boundary else '')); part.mkdir(); before=hashes(case)
        text=runner.run_fixture(profile,install,case,part,args.source/'Scripts/dev/fixtures/plugin-settings-obs-native.qml',extra_env=dict(env,PHA_OBS_MODE=mode,PHA_OBS_BOUNDARY=boundary),extra_lint=tuple(sorted(product.rglob('*.qml'))),timeout=90)
        assert 'OBS_NATIVE: PASS '+scope+' '+mode+' '+boundary in text
        assert not any(word in text for word in ('TypeError:','ReferenceError:','SyntaxError:','Binding loop detected'))
        after=hashes(case); runner.write_json(part/'configuration-hashes.json',dict(before=before,after=after))
        if mode=='cold': assert before==after,'cold consumer published'
        observed=json.loads(text.split('OBS_NATIVE_CONSUMER ')[1].splitlines()[0]); name=boundary or {'edit':'edited','reset':'reset','follow':'following'}[mode]
        doc=expected[name]; defaults=json.loads((product/'manifest.json').read_text())['metadata']['defaultSettings']; values=[dict(defaults,**doc['shared'])]
        values += [dict(values[0],**row['instanceSettings']) for row in doc['bar']['widgets']['left']]
        good=all(row['mode']==value['barLabelMode'] and row['bar']==value['showBarWhenRecording'] and row['cc']==value['showControlCenterWhenRecording'] and (row['text']=='' if value['barLabelMode']=='icon-only' else row['rendered'] and (bool(re.fullmatch(r'REC \d\d:\d\d',row['text'])) if value['barLabelMode']=='duration' else row['text']=='REC')) and row['client'] for row,value in zip(observed,values))
        assert good != controlled,('actual OBS child consumers',observed,values)
        if controlled:
            assert observed[1]['mode'] != values[1]['barLabelMode'], 'control must reach the selected native label mismatch, not just a missing client'
        runner.write_json(part/'consumer.json',dict(status='REJECTED' if controlled else 'PASS',observed=observed))
    resources.close()
    boundaries=['initial','discarded','edited'] if controlled else list(expected)
    for name in boundaries: assert json.loads((out/'persisted'/(name+'.json')).read_text())==dict(status='PASS',values=expected[name])
    rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    for row in rows:
        stat=Path('/proc')/str(row['pid'])/'stat'; assert not stat.exists() or stat.read_text().split(') ',1)[1].split()[19]!=row['start'],row
    assert not any(json.loads(line)['event']=='error' for line in (out/'socket.jsonl').read_text().splitlines())
    runner.write_json(out/'result.json',dict(status='PASS',scope=scope,kind='original-native-red' if args.original_plugins else 'shared-reader-control' if args.shared_reader else 'native',completeNativeBoundaries=boundaries,nonpublishingColdReaders=[] if controlled else ['edited','reset','following'],endpointRows=len(rows),allEndpointIdentitiesAbsent=True,physicalProof=False))
    runner.remove_completed_installs(case,out)


def main():
    parser=argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for name in ('source','plugins','work-root','output'): parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--original-plugins',type=Path); parser.add_argument('--scope',choices=('instance','shared')); parser.add_argument('--shared-reader',action='store_true')
    args=parser.parse_args(); profile=activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve()!=args.source.resolve()/'Scripts/dev/plugin-settings-obs-regression.py': parser.error('execute supplied source')
    for path,parent in ((args.work_root,profile.work_base),(args.output,profile.journal_base)):
        if path!=path.resolve() or path==parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        inputs=[Path(__file__),args.source/'Scripts/dev/fixtures/plugin-settings-obs-native.qml',args.source/'Scripts/dev/plugin-settings-query-lifecycle-regression.py',args.source/'Scripts/dev/fixtures/plugin-settings-query-disk.py']
        runner.write_json(args.output/'inputs.json',{str(p.relative_to(args.source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        for scope in ((args.scope,) if args.scope else ('instance','shared')): run(args,profile,scope)
        runner.write_json(args.output/'result.json',dict(status='PASS',completeGroupAcceptance=False))

if __name__=='__main__': main()
