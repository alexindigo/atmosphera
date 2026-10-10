pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

// Consumer-side check that an Atmosphera singleton name resolves to the
// Atmosphera service. Qt resolves C++ types of imported modules before QML
// singletons, so a same-named upstream type (QtQuick 6.12's Color) silently
// replaces ours in every file that imports that module.
Singleton {
  id: root

  readonly property var atmoColorContract: ({
                                              "properties": ["mPrimary", "mOnPrimary", "mSecondary", "mSurface", "mOnSurface", "mSurfaceVariant", "mOnSurfaceVariant", "mOutline", "mError"],
                                              "functions": ["resolveColorKey", "resolveOnColorKey", "resolveColorKeyOptional", "adaptiveOpacity", "smartAlpha"]
                                            })

  // `service` is whatever the CALLER's imports resolved the name to.
  function verify(name, service, contract) {
    const missing = [];
    for (const p of contract.properties)
      if (service?.[p] === undefined)
        missing.push(p);
    for (const f of contract.functions)
      if (typeof service?.[f] !== "function")
        missing.push(f + "()");
    if (missing.length > 0) {
      Logger.e("SingletonCheck", `${name} does not resolve to Atmosphera's service (shadowed by an imported module?); missing: ${missing.join(", ")}`);
      return false;
    }
    Logger.i("SingletonCheck", `${name} resolves to Atmosphera's service`);
    return true;
  }
}
