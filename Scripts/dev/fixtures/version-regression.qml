// Actual Version and plugin compatibility consumers in a private shell copy.
import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Services.Plugins as Plugins

Item {
  id: probe
  property bool observed: false

  Component.onCompleted: Version.init()

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
      Version.markChangelogSeen(Version.currentVersion);
      identity.seen = Version.changelogLastSeenVersion;
      Version.changelogStateLoaded = true;
      Version.showLatestChangelog();
      identity.prompt = Version.changelogPending;
      Version.viewChangelog(null);
      identity.manualTarget = Version.changelogCurrentVersion;
      console.log("VERSION_PROBE|" + JSON.stringify(identity));
      finish.start();
    }
  }

  Timer {
    id: finish
    interval: 1000
    onTriggered: {
      console.log("VERSION_PERSISTED|" + JSON.stringify(ShellState.getChangelogState()));
      Qt.exit(0);
    }
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(2)
  }
}
