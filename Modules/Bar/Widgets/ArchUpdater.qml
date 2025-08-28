import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  sizeRatio: 0.8
  colorBg: Color.mSurfaceVariant
  // Highlight color based on update source
  colorFg: {
    if (ArchUpdaterService.totalUpdates === 0)
      return Color.mOnSurface
    if (ArchUpdaterService.updates > 0 && ArchUpdaterService.aurUpdates > 0)
      return Color.mPrimary
    if (ArchUpdaterService.updates > 0)
      return Color.mPrimary
    return Color.mSecondary
  }
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  // Icon states
  icon: {
    if (ArchUpdaterService.busy || ArchUpdaterService.aurBusy) {
      return "sync"
    }
    if (ArchUpdaterService.totalUpdates > 0) {
      return "system_update_alt"
    }
    return "task_alt"
  }

  // Tooltip with repo vs AUR breakdown and sample lists
  tooltipText: {
    if (ArchUpdaterService.busy || ArchUpdaterService.aurBusy)
      return "Checking for updates…"

    const repoCount = ArchUpdaterService.updates
    const aurCount = ArchUpdaterService.aurUpdates
    const total = ArchUpdaterService.totalUpdates

    if (total === 0)
      return "System is up to date ✓"

    let header = total === 1 ? "One package can be upgraded:" : (total + " packages can be upgraded:")

    function sampleList(arr, n, colorLabel) {
      const limit = Math.min(arr.length, n)
      let s = ""
      for (var i = 0; i < limit; ++i) {
        const p = arr[i]
        s += (i ? "\n" : "") + (p.name + ": " + p.oldVersion + " → " + p.newVersion)
      }
      if (arr.length > limit)
        s += "\n… and " + (arr.length - limit) + " more"
      return (colorLabel ? (colorLabel + "\n") : "") + (s || "None")
    }

    const repoHeader = repoCount > 0 ? ("Repo (" + repoCount + "):") : "Repo: 0"
    const aurHeader = aurCount > 0 ? ("AUR (" + aurCount + "):") : "AUR: 0"

    const repoBlock = repoCount > 0 ? (repoHeader + "\n\n" + sampleList(ArchUpdaterService.repoPackages,
                                                                        5)) : repoHeader
    const aurBlock = aurCount > 0 ? (aurHeader + "\n\n" + sampleList(ArchUpdaterService.aurPackages, 5)) : aurHeader

    return header + "\n\n" + repoBlock + "\n\n" + aurBlock + "\n\nClick to update system"
  }

  onClicked: {
    if (ArchUpdaterService.busy || ArchUpdaterService.aurBusy) {
      return
    }

    PanelService.getPanel("archUpdaterPanel").toggle(screen, this)
    ArchUpdaterService.doPoll()
    ArchUpdaterService.doAurPoll()
  }
}
