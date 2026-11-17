// Actual Version and plugin compatibility consumers in a private shell copy.
import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings.Tabs.About
import qs.Services
import qs.Services.Plugins as Plugins
import qs.Services.UI

ShellRoot {
  SettingsBootstrap {
    id: directories
  }
  Loader {
    active: directories.ready && Settings.isLoaded && I18n.isLoaded
    sourceComponent: Item {
      id: probe
      property bool observed: false
      property var identity: ({})
      property var panel: null
      property int stage: 0
      // Supply the same screen context as AllScreens, without starting unrelated
      // session services or changing the guest's compositor configuration.
      property ShellScreen modelData: Quickshell.screens[0]

      MainScreen {
        screen: probe.modelData
      }
      PanelWindow {
        visible: about.active
        implicitWidth: 820
        implicitHeight: 620
        Loader {
          id: about
          anchors.fill: parent
          active: false
          sourceComponent: ChangelogSubTab {}
        }
      }

      function find(item, predicate) {
        if (!item)
          return null;
        if (predicate(item))
          return item;
        if (item.children)
          for (let child of item.children) {
            const result = find(child, predicate);
            if (result)
              return result;
          }
        return null;
      }

      Component.onCompleted: {
        Version.init();
        // Exercise a startup request before asynchronous version/state/content load.
        Version.checkChangelogPrompt();
      }

      Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
          if (Settings.isLoaded && !probe.observed) {
            probe.observed = true;
            settle.start();
          }
        }
      }

      Timer {
        id: settle
        interval: 1500
        onTriggered: {
          const builds = ["0.8.0", "v0.8.0", "0.8.0-gabc123456", "0.8.0.r12.gabc123456", "v0.8.0-12-gabc123456", "0.8.0.r12.gabc123456-2"];
          const comparisons = builds.map(v => ({
            version: v,
            equal: Version.compareVersions(v, "0.8.0"),
            next: Version.compareVersions(v, "0.8.1"),
            hash: Version.versionCommitHash(v),
            git: Version.classifyIsGitVersion(v)
          }));
          // Private runner metadata selects source-release requirements; build-format
          // comparison vectors above deliberately remain fixed compatibility inputs.
          const requirements = JSON.parse(Quickshell.env("ATMOSPHERA_VERSION_PROBE_REQUIREMENTS") || '["0.8.0", "0.8.1"]');
          const compatibility = requirements.map(v => ({
            required: v,
            result: Plugins.Service.checkPluginCompatibility({
                                                               id: "version-probe",
                                                               minAtmospheraVersion: v
                                                             })
          }));
          const identity = {
            current: Version.currentVersion,
            release: Version.currentReleaseVersion,
            known: Version.versionKnown,
            packaged: Version.versionFromPackage,
            git: Version.isGitVersion,
            hash: Version.versionCommitHash(Version.currentVersion),
            parts: Version.parseVersionParts(Version.currentVersion),
            comparisons: comparisons,
            compatibility: compatibility,
            major: Version.parseVersionParts("v4"),
            minor: Version.parseVersionParts("4.6"),
            noctalia4: Plugins.Service.checkPluginCompatibility({
                                                                  minNoctaliaVersion: "v4.99"
                                                                }),
            noctalia5: Plugins.Service.checkPluginCompatibility({
                                                                  minNoctaliaVersion: "v5"
                                                                })
          };
          probe.panel = PanelService.getPanel("changelogPanel", probe.modelData);
          identity.prompt = probe.panel.isPanelOpen || Version.popupScheduled;
          identity.automaticNotes = Version.releaseContent;
          identity.initialSeen = Version.changelogLastSeenVersion;
          if (!probe.panel.isPanelOpen)
            Version.viewChangelog(probe.modelData);
          // MainScreen is ready; also exercise the queued-panel readiness path.
          Version.openWhenReady();
          identity.manualTarget = Version.changelogCurrentVersion;
          probe.identity = identity;
          probe.stage = 1;
        }
      }

      Timer {
        id: finish
        interval: 1200
        onTriggered: {
          probe.identity.seen = Version.changelogLastSeenVersion;
          console.log("VERSION_PROBE|" + JSON.stringify(probe.identity));
          console.log("VERSION_PERSISTED|" + JSON.stringify(ShellState.getChangelogState()));
          Qt.exit(0);
        }
      }

      Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
          if (probe.stage === 1) {
            probe.identity.manualNotes = Version.releaseContent;
            if (probe.panel.isPanelOpen || Version.releaseContent.trim() !== "") {
              if (!probe.panel.isPanelVisible)
                return;
              const button = probe.find(probe.panel, item => item.text === I18n.tr("changelog.panel.buttons-dismiss") && typeof item.clicked === "function");
              if (!button || button.width <= 0 || button.height <= 0)
                return;
              probe.identity.dialogRendered = !!probe.find(probe.panel, item => item.textFormat === Text.MarkdownText && item.text && item.width > 0 && item.height > 0);
              button.clicked();
              probe.identity.okClicked = true;
            }
            probe.stage = 2;
          } else if (probe.stage === 2 && !probe.panel.isPanelOpen) {
            about.active = true;
            probe.stage = 3;
          } else if (probe.stage === 3 && about.item) {
            const content = probe.find(about.item, item => item.releaseContent !== undefined);
            if (!content)
              return;
            probe.identity.aboutNotes = content.releaseContent;
            probe.identity.aboutRendered = !!probe.find(about.item, item => item.textFormat === Text.MarkdownText && item.text && item.width > 0 && item.height > 0);
            if (content.releaseContent && !probe.identity.aboutRendered)
              return;
            finish.start();
            probe.stage = 4;
          }
        }
      }

      Timer {
        interval: 15000
        running: true
        onTriggered: Qt.exit(2)
      }
    }
  }
}
