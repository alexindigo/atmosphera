pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  property var pools: ({})
  property var _poolList: []

  function registerPool(poolId, descriptor) {
    root.pools[poolId] = descriptor;
    root._rebuildList();
    Logger.i("WallpaperProvider", `Registered pool: ${poolId} (${descriptor.label})`);
  }

  function unregisterPool(poolId) {
    delete root.pools[poolId];
    root._rebuildList();
    Logger.i("WallpaperProvider", `Unregistered pool: ${poolId}`);
  }

  function unregisterPluginPools(pluginId) {
    var changed = false;
    for (var pid in root.pools) {
      if (root.pools[pid].pluginId === pluginId) {
        delete root.pools[pid];
        changed = true;
        Logger.i("WallpaperProvider", `Unregistered pool for plugin: ${pluginId}`);
      }
    }
    if (changed) {
      root._rebuildList();
    }
  }

  function availablePools() {
    return root._poolList;
  }

  function getActivePools(screenName) {
    var config = root._getMonitorConfig(screenName);
    var active = [];
    for (var i = 0; i < root._poolList.length; i++) {
      var pool = root._poolList[i];
      var entry = root._findPoolConfig(config, pool.id);
      if (entry && entry.active) {
        active.push(pool);
      }
    }
    return active;
  }

  function getRotationPools(screenName) {
    var config = root._getMonitorConfig(screenName);
    var rotating = [];
    for (var i = 0; i < root._poolList.length; i++) {
      var pool = root._poolList[i];
      var entry = root._findPoolConfig(config, pool.id);
      if (entry && entry.active && entry.rotate) {
        rotating.push(pool);
      }
    }
    return rotating;
  }

  function _getMonitorConfig(screenName) {
    var monitors = Settings.data.wallpaper.monitorPools || [];
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name === screenName) {
        return monitors[i].pools || [];
      }
    }
    return [];
  }

  function _findPoolConfig(config, poolId) {
    for (var i = 0; i < config.length; i++) {
      if (config[i].id === poolId) {
        return config[i];
      }
    }
    return null;
  }

  function _rebuildList() {
    var list = [];
    for (var pid in root.pools) {
      list.push(root.pools[pid]);
    }
    root._poolList = list.sort(function (a, b) {
      return (a.label || "").localeCompare(b.label || "");
    });
    root.poolsChanged();
  }
}
