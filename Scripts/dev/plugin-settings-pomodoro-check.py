#!/usr/bin/env python3
"""Finite Pomodoro field, selected timer, legacy writer and lifetime contract."""
import argparse
import importlib.util
import json
from pathlib import Path
spec=importlib.util.spec_from_file_location('pomo_syntax',Path(__file__).with_name('plugin-settings-claude-check.py'))
syntax=importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
CONFIG=['workDuration','shortBreakDuration','longBreakDuration','sessionsBeforeLongBreak','autoStartBreaks','autoStartWork','compactMode','playSound']
ANCHORS={
 'Main.qml':['property var _settingsConsumers: new Map()', '_settingsConsumers.has(context)', 'settingsContext: context', '_settingsConsumers.set(context, timer)', 'root._settingsConsumers.delete(context); retired.destroy()', 'api?.settingsReady ? settingsConsumerFor(api.settingsContext) : null', 'readonly property var settingsConsumer: timerFor(pluginApi)', 'root.pluginApi.pluginSettings[key] = values[key]', 'path: Qt.resolvedUrl("settings.json")', 'function start() { root.pomodoroStart(); }'],
 'TimerClient.qml':['required property var settingsContext', 'readonly property bool current: !retired && settingsContext.current()', 'readonly property var cfg: settingsContext.settingsView', 'property int workDuration: _computeWorkDuration()', 'property int shortBreakDuration: _computeShortBreakDuration()', 'property int longBreakDuration: _computeLongBreakDuration()', 'property int sessionsBeforeLongBreak: _computeSessionsBeforeLongBreak()', '(cfg.workDuration ?? 25) * 60', '(cfg.shortBreakDuration ?? 5) * 60', '(cfg.longBreakDuration ?? 15) * 60', 'cfg.sessionsBeforeLongBreak ?? 4', 'cfg.autoStartBreaks ?? false', 'cfg.autoStartWork ?? false', 'cfg.compactMode ?? false', 'cfg.playSound !== false', 'interval: 1000', 'running: root.current && root.pomodoroRunning', 'interval: 5000', 'root.pomodoroCompletedSessions + 1 >= root.sessionsBeforeLongBreak', 'root.pomodoroCompletedSessions++', 'root.pomodoroCompletedSessions = 0', 'repeat: true, volume: 0.3', 'if (!root.current || generation !== root.actionGeneration) return', 'root.pomodoroStart(false)', 'updateTimer.stop()', 'alarmLimitTimer.stop()', 'Component.onDestruction: release()', 'root.release(); root.retire(root)'],
 'BarWidget.qml':['pluginApi?.mainInstance?.timerFor(pluginApi)', 'return formatTime(mainInstance.pomodoroRemainingSeconds)', 'mainInstance.pomodoroStart()', 'mainInstance.pomodoroSkip()'],
 'Panel.qml':['pluginApi?.mainInstance?.timerFor(pluginApi)', 'mainInstance.compactMode', 'mainInstance.sessionsBeforeLongBreak', 'mainInstance.pomodoroStart()', 'text: formatTime(remainingSeconds, totalSeconds)'],
 'Settings.qml':['settingsConsumerFor(root.pluginApi.runtimeContext)?.refresh()'],
}
def check(sources,manifest):
    code={name:syntax.syntax.compact(text)[0] for name,text in sources.items()}
    fields=manifest['metadata']['settingsSchema']['fields']; assert set(fields)==set(CONFIG)
    assert all(fields[key]['editorUsage']=='configuration' for key in CONFIG)
    for key in CONFIG: syntax.require(code['Settings.qml'],'pluginApi?.field("'+key+'")',key+' explicit intent')
    ANCHORS['TimerClient.qml'] = [anchor if anchor != 'interval: 5000' else 'interval: 5000; repeat: false' for anchor in ANCHORS['TimerClient.qml']]
    for name,anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[name],anchor,name+': '+anchor)
    for action in ('pomodoroStart','pomodoroPause','pomodoroResetSession','pomodoroResetAll','pomodoroSkip','pomodoroStopAlarm','pomodoroSetMode','pomodoroAdvanceToNextPhase','pomodoroOnFinished'):
        import re
        assert re.search(r'function'+action+r'\([^)]*\)\{if\(!current\)return',code['TimerClient.qml']),action+' admission'
    assert 'pluginSettings' not in code['TimerClient.qml'],'read-only policy client, no new writer'
    assert 'workDuration=' not in code['TimerClient.qml'],'duration binding is not replaced by snapshot assignments'
    return dict(configuration=CONFIG,timerOwner='Main per captured context',legacyWriter='existing plugin-level native API',runtimeAcceptance=False)
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('source','plugins','report'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--selftest',action='store_true'); a=p.parse_args(); root=a.plugins/'pomodoro'
    sources={f.name:f.read_text() for f in root.glob('*.qml')}; manifest=json.loads((root/'manifest.json').read_text())
    member=check(sources,manifest); controls=[]
    mutations=[('Main.qml','settingsContext: context','settingsContext: pluginApi.settingsContext','shared-identity'),('Main.qml','root.pluginApi.pluginSettings[key] = values[key]','root.pluginApi.pluginSettings.workDuration = values[key]','legacy-writer'),('TimerClient.qml','property int workDuration:','property real workDuration:','typed-duration'),('TimerClient.qml','interval: 1000','interval: 2000','tick-policy'),('TimerClient.qml','interval: 5000','interval: 50000','alarm-policy'),('TimerClient.qml','generation !== root.actionGeneration','false','delayed-auto'),('TimerClient.qml','if (!current) return;','if (false) return;','action-admission'),('TimerClient.qml','Component.onDestruction: release()','Component.onDestruction: {}','destruction'),('BarWidget.qml','pluginApi?.mainInstance?.timerFor(pluginApi)','pluginApi?.mainInstance','shared-bar'),('Panel.qml','pluginApi?.mainInstance?.timerFor(pluginApi)','pluginApi?.mainInstance','shared-panel'),('BarWidget.qml','return formatTime(mainInstance.pomodoroRemainingSeconds)','return "wrong"','rendered-child'),('Settings.qml','settingsConsumerFor(root.pluginApi.runtimeContext)?.refresh()','settingsConsumerFor(root.pluginApi.mainInstance.pluginApi.settingsContext)?.refresh()','completion-origin')]
    if a.selftest:
        for name,old,new,label in mutations:
            assert old in sources[name]; changed=dict(sources); changed[name]=changed[name].replace(old,new)
            try: check(changed,manifest)
            except (AssertionError,ValueError) as error: controls.append(dict(control=label,rejectedAt=str(error)))
            else: raise RuntimeError('Pomodoro control escaped '+label)
    a.report.write_text(json.dumps(dict(status='PASS',member=member,controls=controls,runtimeAcceptance=False),indent=2)+'\n')
    print('POMODORO_CHECK: PASS (8 fields, %d controls)'%len(controls))
if __name__=='__main__': main()
