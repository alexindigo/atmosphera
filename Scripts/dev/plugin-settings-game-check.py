#!/usr/bin/env python3
"""Finite Tamagotchi field, child, game and originating native-writer contract."""
import argparse
import importlib.util
import json
from pathlib import Path
spec=importlib.util.spec_from_file_location('game_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
CONFIG=['difficulty','volume','showDebug','showPercentage']
STATS=['hunger','happiness','cleanliness','energy']
ANCHORS={
 'Main.qml':['property var _games: new Map()','pluginApi?.settingsReady ? gameFor(pluginApi) : null','if (!api || !api.settingsReady || !api.settingsContext || !api.settingsContext.current()) return null','const context = api.settingsContext','_games.has(context)','runtimeApi: api','settingsContext: context','root._games.delete(context); retired.destroy()','_games.set(context, game)'],
 'GameClient.qml':['required property var runtimeApi','required property var settingsContext','runtimeApi.settingsContext === settingsContext && settingsContext.current()','readonly property var cfg: settingsContext.settingsView','readonly property real difficulty: cfg.difficulty ?? 50','0.3 + (difficulty / 100) * 1.7','runtimeApi.saveSettings()','if (!current) return','interval: 30000; running: root.current','root.retired = true; root.retire(root)'],
 'BarWidget.qml':['pluginApi?.mainInstance?.gameFor(pluginApi)','Math.min(game?.hunger ?? 100','text: root._minStat + "%"'],
 'Panel.qml':['pluginApi?.mainInstance?.gameFor(pluginApi)','StatBars {','Pet {','Bed {','Food {','Ball {','DebugButtons {'],
 'Pet.qml':['property var game: null','game: root.game','root.game?.feed(10)','root.game?.clean(2.5)','foodBurstRequested()','cleanBurstRequested()','foodParticle.burst()','cleanParticle.burst()'],
 'Food.qml':['property var game: null','root.game.eating = true','root.game.eating = false','root.wasDropped = root.Drag.drop() !== Qt.IgnoreAction'],
 'Bed.qml':['root.game?.sleep()'],
 'Ball.qml':['property var game: null','root.game?.petState','root.game?.play(18)'],
 'components/StatBars.qml':['property var game: null','(pluginApi?.pluginSettings?.showPercentage ?? false) ? 1 : 0'],
 'components/DebugButtons.qml':['property var game: null','pluginApi?.pluginSettings?.showDebug','root.game.feed(-10)','root.game.clean(-10)','root.game && root.game.current'],
 'components/AnimationController.qml':['property var game: null','root.game?.petState ?? "idle"','const state = root.game','root.game.isDirty'],
}
def check(source,manifest):
    code={k:syntax.compact(v)[0] for k,v in source.items()}
    fields=manifest['metadata']['settingsSchema']['fields']; assert set(fields)==set(CONFIG+STATS)
    for key in CONFIG: assert fields[key]['editorUsage']=='configuration'
    for key in STATS:
        assert fields[key]['editorUsage']=='operational'
        syntax.require(code['GameClient.qml'],'runtimeApi.pluginSettings.'+key+' = '+key,key+' native writer')
        syntax.require(code['components/StatBars.qml'],'property int '+key+': game?.'+key,key+' stat reader')
        syntax.require(code['GameClient.qml'],'property int '+key+': cfg.'+key,key+' original integer state')
    for name,anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[name],anchor,name+': '+anchor)
    for name in source:
        if name not in ('Main.qml','BarWidget.qml','Panel.qml','Settings.qml'): assert 'mainInstance' not in code[name],name+' borrowed shared game'
    assert code['Panel.qml'].count(syntax.squash('game: root.game'))==6,'all six Panel children receive selected game'
    syntax.require(code['Pet.qml'],'volume: pluginApi?.pluginSettings?.volume','selected sound volume')
    for anchor in ('return min + Math.random() * (max - min)', 'energy + 3.5 * _randFactor()', 'hunger - 0.03 * f * _randFactor()', 'happiness - 0.005 * f * _randFactor()', 'cleanliness - 0.02 * f * _randFactor()', 'energy - 0.03 * f * _randFactor()', 'hunger - 0.05 * f * _randFactor()', 'cleanliness - 0.05 * f * _randFactor()'):
        syntax.require(code['GameClient.qml'],anchor,'original random/decay formula')
    for key in CONFIG: syntax.require(code['Settings.qml'],'pluginApi?.field("'+key+'")',key+' intent')
    assert syntax.squash('property bool enabled:') not in code['components/DebugButtons.qml']
    return dict(configuration=CONFIG,operational=STATS,gameOwner='Main per captured runtime API',store='existing native fields',contentMigration=False,runtimeAcceptance=False)
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 for name in ('source','plugins','report'): parser.add_argument('--'+name,type=Path,required=True)
 parser.add_argument('--selftest',action='store_true'); args=parser.parse_args(); root=args.plugins/'tamagotchi'
 sources={str(p.relative_to(root)):p.read_text() for p in root.rglob('*.qml')}; manifest=json.loads((root/'manifest.json').read_text())
 member=check(sources,manifest); controls=[]
 mutations=[('Main.qml','const context = api.settingsContext','const context = pluginApi.settingsContext','shared-identity'),('Main.qml','runtimeApi: api','runtimeApi: pluginApi','shared-writer'),('GameClient.qml','settingsContext.settingsView','runtimeApi.mainInstance.pluginApi.pluginSettings','shared-config'),('GameClient.qml','root.current; repeat: true','true; repeat: true','retired-timer'),('GameClient.qml','root.retired = true; root.retire(root)','root.retired = true','retirement'),('Panel.qml','game: root.game','game: pluginApi.mainInstance.sharedGame','shared-child'),('BarWidget.qml','text: root._minStat + "%"','text: "wrong"','rendered-stat'),('Pet.qml','root.game?.feed(10)','pluginApi.mainInstance.feed(10)','shared-feed'),('Ball.qml','root.game?.play(18)','pluginApi.mainInstance.play(18)','shared-play'),('GameClient.qml','runtimeApi.pluginSettings.hunger = hunger','runtimeApi.mainInstance.pluginApi.pluginSettings.hunger = hunger','wrong-native-writer')]
 mutations.extend([('GameClient.qml','property int energy:','property real energy:','integer-state'),('GameClient.qml','Math.random() * (max - min)','Math.random()','random-domain'),('GameClient.qml','energy + 3.5 * _randFactor()','energy + 7 * _randFactor()','sleep-decay'),('GameClient.qml','hunger - 0.05 * f * _randFactor()','hunger - 0.1 * f * _randFactor()','awake-decay')])
 if args.selftest:
  for name,old,new,label in mutations:
   assert old in sources[name],label
   changed=dict(sources); changed[name]=sources[name].replace(old,new)
   try: check(changed,manifest)
   except (AssertionError,ValueError) as error: controls.append(dict(control=label,rejectedAt=str(error)))
   else: raise RuntimeError('game control escaped: '+label)
 args.report.write_text(json.dumps(dict(status='PASS',member=member,controls=controls,runtimeAcceptance=False),indent=2)+'\n')
 print('GAME_CHECK: PASS (4 configuration, 4 operational, %d controls)'%len(controls))
if __name__=='__main__': main()
