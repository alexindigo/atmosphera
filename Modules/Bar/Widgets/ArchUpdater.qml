import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
    id: root
    visible: Settings.data.bar.showArchUpdater && ArchUpdaterService.isArchBased
    sizeMultiplier: 0.8

    colorBg: Color.mSurfaceVariant
    colorFg: Color.mOnSurface
    colorBorder: Color.transparent
    colorBorderHover: Color.transparent

    icon: !ArchUpdaterService.ready ? "block" : (ArchUpdaterService.busy ? "sync" : (ArchUpdaterService.updatePackages.length > 0 ? "system_update" : "task_alt"))

    tooltipText: {
        if (!ArchUpdaterService.checkupdatesAvailable)
            return "Please install pacman-contrib to use this feature.";
        if (ArchUpdaterService.busy)
            return "Checking for updates…";

        var count = ArchUpdaterService.updatePackages.length;
        if (count === 0)
            return "No updates available";

        var header = count === 1 ? "One package can be upgraded:" : (count + " packages can be upgraded:");

        var list = ArchUpdaterService.updatePackages || [];
        var s = "";
        var limit = Math.min(list.length, 10);
        for (var i = 0; i < limit; ++i) {
            var p = list[i];
            s += (i ? "\n" : "") + (p.name + ": " + p.oldVersion + " → " + p.newVersion);
        }
        if (list.length > 10)
            s += "\n… and " + (list.length - 10) + " more";

        return header + "\n" + s;
    }

    onClicked: {
        if (!ArchUpdaterService.ready || ArchUpdaterService.busy)
            return;
        ArchUpdaterService.runUpdate();
    }
}
