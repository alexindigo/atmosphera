#!/usr/bin/env python3
"""Actual generic Settings page/input retention through host navigation, guest only."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

MODULES = (
    'Modules/MainScreen/SmartPanel.qml', 'Services/UI/PanelService.qml', 'Services/UI/SettingsPanelService.qml',
    'Widgets/NPluginSettingsPopup.qml', 'Widgets/NTabBar.qml', 'Widgets/NTabButton.qml',
    'Modules/Panels/Settings/SettingsContent.qml', 'Modules/Panels/Settings/SettingsPanel.qml',
    'Modules/Panels/Settings/SettingsPanelWindow.qml', 'Modules/Panels/Settings/Bar/MonitorWidgetsConfig.qml',
    'Modules/Panels/Settings/Tabs/Bar/BarTab.qml', 'Modules/Panels/Settings/Tabs/ControlCenter/ControlCenterTab.qml',
    'Modules/Panels/Settings/Tabs/DesktopWidgetsTab.qml', 'Modules/Panels/Settings/Tabs/Plugins/InstalledSubTab.qml',
    'Modules/Panels/Settings/Tabs/Plugins/PluginsTab.qml',
    'Modules/Panels/Wallpaper/WallpaperPanel.qml', 'Modules/Panels/ControlCenter/Widgets/NightLight.qml',
    'Modules/Bar/Widgets/Brightness.qml',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--baseline-source', type=Path, required=True)
    parser.add_argument('--baseline-log', type=Path, required=True)
    parser.add_argument('--presentation', choices=('window', 'attached', 'centered'), default='window')
    parser.add_argument('--route', choices=('desktop', 'plugins'), default='desktop')
    parser.add_argument('--failure-phase', action='store_true')
    parser.add_argument('--negative-control', choices=('registration', 'popup-close', 'panel-replacement', 'late-panel-replacement'))
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        install = args.work_root / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        rejected_at = None
        if args.negative_control == 'registration':
            for name in ('Modules/Panels/Settings/Tabs/DesktopWidgetsTab.qml', 'Modules/Panels/Settings/Tabs/Plugins/InstalledSubTab.qml'):
                path = install / name
                text = path.read_text()
                anchor = '    registerPresentation: SettingsPanelService.registerEditorPresentation\n'
                assert text.count(anchor) == 1
                path.write_text(text.replace(anchor, ''))
            rejected_at = 'service-tab retained navigation owner'
        elif args.negative_control == 'popup-close':
            path = install / 'Widgets/NPluginSettingsPopup.qml'
            text = path.read_text()
            start = text.index('    // A native host hide or a caller using Popup.close()')
            end = text.index('    resetInstanceDialog.close();', start)
            path.write_text(text[:start] + text[end:])
            rejected_at = 'popup-direct-close retained actual presentation'
        elif args.negative_control == 'panel-replacement':
            if args.presentation == 'window':
                parser.error('panel-replacement control requires an actual panel presentation')
            path = install / 'Services/UI/PanelService.qml'
            text = path.read_text()
            anchor = '    if (panel.exclusiveOpen !== false && openedPanel && openedPanel !== panel && openedPanel.canClose && !openedPanel.canClose())\n      return false;\n'
            assert text.count(anchor) == 1
            path.write_text(text.replace(anchor, ''))
            rejected_at = 'panel-replacement retained actual presentation'
        elif args.negative_control == 'late-panel-replacement':
            if args.presentation == 'window':
                parser.error('late-panel-replacement control requires an actual panel presentation')
            path = install / 'Modules/MainScreen/SmartPanel.qml'
            text = path.read_text()
            start = text.index('    if (owner !== root && PanelService.willOpenPanel(root) === false) {')
            end = text.index('    if (generation !== root.presentationGeneration || !root._requestedOpen || root.isClosing)', start)
            path.write_text(text[:start] + '    if (owner !== root)\n      PanelService.willOpenPanel(root);\n' + text[end:])
            rejected_at = 'late replacement cannot show an unowned competing surface'
        shared, seed = runner.seed_todo(args.work_root, args.plugins)
        before = shared.read_bytes()
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-navigation.qml'
        error = None
        try:
            text = runner.run_fixture(profile, install, args.work_root, args.output, fixture,
                extra_env=dict(PHA_NAVIGATION_MODE=args.presentation, PHA_NAVIGATION_ROUTE=args.route, PHA_NAVIGATION_FAILURE='1' if args.failure_phase else '0'),
                extra_lint=[install / path for path in MODULES])
        except RuntimeError as failure:
            error = str(failure)
            text = (args.output / 'runtime.log').read_text()
        finally:
            (args.work_root / 'config/settings').chmod(0o700)
            (args.work_root / 'config/settings/plugins').chmod(0o700)
        rows = [json.loads(line.split('NAVIGATION_RESULT ', 1)[1]) for line in text.splitlines() if 'NAVIGATION_RESULT ' in line]
        diagnostics = [line for line in text.splitlines() if any(marker in line for marker in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed'))]
        # Existing full-shell evidence already characterizes this synchronous
        # XdgIcon name/path loop. Require both the exact unchanged owner and an
        # explicit baseline receipt; report it, never call this a clean runtime.
        baseline_text = args.baseline_log.read_text()
        owner = Path('Services/System/HostService.qml')
        same_owner = (args.source / owner).read_bytes() == (args.baseline_source / owner).read_bytes()
        baseline = [line for line in diagnostics if same_owner and line in baseline_text and
                    'XdgIcon at @Services/System/HostService.qml[29:3]: Binding loop detected for property "name"' in line]
        bad = [line for line in diagnostics if line not in baseline]
        desktop = args.work_root / 'config/settings/desktopWidgets.json'
        placements = json.loads(desktop.read_text())['monitorWidgets'] if desktop.exists() else []
        expected_row = dict(id='plugin:todo')
        if args.failure_phase and args.route == 'desktop':
            # Native detach cannot cancel persistence already requested by
            # Apply (overlay-editors.md). This is not an unapplied Discard.
            # The main Settings owner autosaves its admitted atomic placement;
            # the plugin draft's manual owner does not autosave after failure.
            expected_row['instanceSettings'] = dict(exportPath='/pending/navigation')
        shared_matches = shared.read_bytes() == before
        readback = bool(placements) and placements[0]['widgets'] == [expected_row] and shared_matches
        passed = not error and not bad and len(rows) == 1 and readback
        control_passed = bool(args.negative_control and error and ('NAVIGATION_ASSERT: ' + rejected_at) in text)
        runner.write_json(args.output / 'result.json', dict(status='PASS' if control_passed else 'FAIL' if args.negative_control else 'PASS' if passed else 'FAIL', fixtureError=error,
            negativeControl=args.negative_control, rejectedAt=rejected_at, catalogCoverageNotCertified=bool(args.negative_control),
            inputs={name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in MODULES},
            fixtureSha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
            diagnostics=bad, baselineDiagnostics=baseline, baselineLogSha256=hashlib.sha256(args.baseline_log.read_bytes()).hexdigest(),
            unchangedBaselineOwnerSha256=hashlib.sha256((args.source / owner).read_bytes()).hexdigest() if same_owner else None,
            observations=rows, independentSharedAndPlacementReadback=readback, cleanRuntimeNotCertified=True,
            admittedPlacementApplyPersistedAfterDetach=args.failure_phase and args.route == 'desktop',
            manualPluginOwnerUnpublishedAfterFailure=args.failure_phase and args.route == 'plugins',
            unappliedDiscardLeavesBytesUnchanged=not args.failure_phase and readback))
        if args.negative_control:
            if not control_passed:
                raise RuntimeError('negative control did not fail at its exact consumer assertion: ' + str(rejected_at))
            print('PLUGIN_SETTINGS_NAVIGATION_CONTROL: PASS (' + args.negative_control + '; actual native/UI result FAIL as expected)', flush=True)
            return
        if not passed:
            raise RuntimeError('navigation retention failed: ' + str(error or bad or rows))
        runner.remove_completed_installs(args.work_root, args.output)
        print('PLUGIN_SETTINGS_NAVIGATION: PASS', flush=True)


if __name__ == '__main__':
    main()
