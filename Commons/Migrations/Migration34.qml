import QtQuick

QtObject {
  id: root

  // Migrate desktop widget MediaPlayer legacy properties
  // - hideWhenIdle: true -> hideMode: "idle"
  // - visualizerVisibility: false -> showVisualizer: false
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v34");

    // Check rawJson for desktop widgets
    if (rawJson?.desktopWidgets?.monitorWidgets) {
      var monitorWidgets = rawJson.desktopWidgets.monitorWidgets;
      var migrated = false;

      // Ensure adapter has desktopWidgets.monitorWidgets
      if (!adapter.desktopWidgets) {
        adapter.desktopWidgets = {};
      }
      if (!adapter.desktopWidgets.monitorWidgets) {
        adapter.desktopWidgets.monitorWidgets = [];
      }

      for (var i = 0; i < monitorWidgets.length; i++) {
        var monitor = monitorWidgets[i];
        if (monitor.widgets && Array.isArray(monitor.widgets)) {
          // Find or create corresponding monitor in adapter
          var adapterMonitorIndex = -1;
          for (var k = 0; k < adapter.desktopWidgets.monitorWidgets.length; k++) {
            if (adapter.desktopWidgets.monitorWidgets[k].name === monitor.name) {
              adapterMonitorIndex = k;
              break;
            }
          }

          // Create monitor entry if it doesn't exist
          if (adapterMonitorIndex < 0) {
            adapter.desktopWidgets.monitorWidgets.push({
                                                         "name": monitor.name,
                                                         "widgets": []
                                                       });
            adapterMonitorIndex = adapter.desktopWidgets.monitorWidgets.length - 1;
          }

          // Ensure widgets array exists
          if (!adapter.desktopWidgets.monitorWidgets[adapterMonitorIndex].widgets) {
            adapter.desktopWidgets.monitorWidgets[adapterMonitorIndex].widgets = [];
          }

          for (var j = 0; j < monitor.widgets.length; j++) {
            var widget = monitor.widgets[j];

            // Only migrate MediaPlayer widgets
            if (widget.id === "MediaPlayer") {
              var needsUpdate = false;

              // Get existing widget from adapter or create new one
              var adapterWidget = (j < adapter.desktopWidgets.monitorWidgets[adapterMonitorIndex].widgets.length) ? adapter.desktopWidgets.monitorWidgets[adapterMonitorIndex].widgets[j] : Object.assign({}, widget);

              // Migrate hideWhenIdle to hideMode
              if (widget.hideWhenIdle === true && (adapterWidget.hideMode === undefined || adapterWidget.hideMode === "visible")) {
                adapterWidget.hideMode = "idle";
                if (adapterWidget.hideWhenIdle !== undefined) {
                  delete adapterWidget.hideWhenIdle;
                }
                needsUpdate = true;
                logger.i("Settings", "Migrated MediaPlayer hideWhenIdle=true to hideMode=idle for monitor: " + (monitor.name || "unknown"));
              }

              // Migrate visualizerVisibility to showVisualizer
              if (widget.visualizerVisibility === false && adapterWidget.showVisualizer === undefined) {
                adapterWidget.showVisualizer = false;
                if (adapterWidget.visualizerVisibility !== undefined) {
                  delete adapterWidget.visualizerVisibility;
                }
                needsUpdate = true;
                logger.i("Settings", "Migrated MediaPlayer visualizerVisibility=false to showVisualizer=false for monitor: " + (monitor.name || "unknown"));
              }

              // Update the widget if changes were made
              if (needsUpdate) {
                // Ensure widget exists in adapter array
                while (adapter.desktopWidgets.monitorWidgets[adapterMonitorIndex].widgets.length <= j) {
                  adapter.desktopWidgets.monitorWidgets[adapterMonitorIndex].widgets.push({});
                }
                adapter.desktopWidgets.monitorWidgets[adapterMonitorIndex].widgets[j] = adapterWidget;
                migrated = true;
              }
            }
          }
        }
      }

      if (migrated) {
        logger.i("Settings", "Migration to v34 completed: migrated MediaPlayer widget properties");
      } else {
        logger.i("Settings", "Migration to v34 completed: no MediaPlayer widgets needed migration");
      }
    }

    return true;
  }
}
