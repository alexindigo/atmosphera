// Actual popup, field-only page, native editors and real persistence.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property var api: null
  property var instance: null
  property var held: null
  property var afterFault: null
  property bool faultBlocked: false
  property bool hold: false
  property bool stale: false
  property int applies: 0
  property int receipts: 0
  property string phase: "opening"
  property var manifest: null
  property var retainedPreview: null
  readonly property var placement: ({
                                      kind: "bar",
                                      list: "global",
                                      section: "left",
                                      index: 0
                                    })
  readonly property bool cold: Quickshell.env("PHA_SESSION_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/session-fixture/manifest.json"
    blockLoading: true
    printErrors: false
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("SESSION_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function show(selected) {
    if (host.popupContentItem !== popup)
      check(host.showDialog(popup), "actual host admitted");
    check(selected ? popup.openInstanceSettings(manifest, selected) : popup.openPluginSettings(manifest), "selected editor open admitted");
  }
  Component {
    id: nullFactory
    QtObject {
      required property var unavailable
    }
  }
  Component {
    id: openingSessionFactory
    PluginSettingsSession {
      commitInputs: () => {}
      captureInputs: () => ({})
      acknowledgeInputs: () => {}
      resetInputs: () => {}
    }
  }
  function openingProbes(next) {
    var failures = [];
    var createEditor = api.createSettingsEditor;
    function probe(label, inject, attempt, delay) {
      var session = openingSessionFactory.createObject(root);
      var failed = 0;
      var presented = 0;
      session.openingFailed.connect(function () {
        failed++;
      });
      session.presentRequested.connect(function () {
        presented++;
      });
      inject(session);
      var accepted = session.openPluginSettings(manifest);
      api.createSettingsEditor = createEditor;
      if (accepted !== attempt)
        failures.push(label + ": unexpected admission");
      function verify() {
        if (failed !== 1 || presented !== 0 || session.editor || session.pageApi || session.fields || session.currentPluginApi)
          failures.push(label + ": failed=" + failed + " presented=" + presented + " editor=" + !!session.editor + " fields=" + !!session.fields + " api=" + !!session.currentPluginApi);
        session.presentationClosed();
        session.destroy();
        delay();
      }
      // whenReady schedules a Qt.callLater delivery synchronously on admission.
      Qt.callLater(verify);
    }
    probe("refused editor", function () {
      api.createSettingsEditor = () => null;
    }, false, function () {
      probe("null fields", function (session) {
        session._fieldsFactory = nullFactory;
      }, true, function () {
        probe("null page API", function (session) {
          session._pageApiFactory = nullFactory;
        }, true, function () {
          try {
            check(!failures.length, failures.join("; "));
            console.log("PLUGIN_SETTINGS_SESSION: OPENING_REFUSALS_RELEASED");
            next();
          } catch (error) {
            fail(error);
          }
        });
      });
    });
  }
  function fault(mode, next) {
    afterFault = next;
    faultProcess.command = ["python3", "-B", Quickshell.env("PHA_SESSION_FAULT"), Settings.configDir.replace(/\/$/, ""), mode];
    faultProcess.running = true;
  }
  function registrationProbes() {
    var key = "registration-fixture";
    var probeManifest = Object.assign({}, manifest, {
                                        id: key,
                                        entryPoints: {
                                          settings: "Page.qml"
                                        }
                                      });
    Registry.installedPlugins = Object.assign({}, Registry.installedPlugins, {
                                                [key]: probeManifest
                                              });
    var originalApi = null;
    var session = openingSessionFactory.createObject(root);
    var effects = [];
    var failures = [];
    function expect(ok, message) {
      if (!ok)
        failures.push(message);
    }
    function finish() {
      check(failures.length === 0, failures.join("; "));
      console.log("PLUGIN_SETTINGS_SESSION: RETIRED_REGISTRATION_REFUSED");
      console.log("PLUGIN_SETTINGS_SESSION: PASS");
      Qt.exit(0);
    }
    session.acknowledgeInputs = () => effects.push("acknowledged");
    session.captureInputs = () => 0;
    session.saved.connect(() => effects.push("saved"));
    session.settingsCompleted.connect(function (result) {
      effects.push(result.error?.code || result.status);
      if (Service.getPluginAPI(key) === originalApi)
        fail("registration probe completed before retirement: " + JSON.stringify(result));
    });
    session.presentRequested.connect(function () {
      try {
        session.page = {
          settingsDirty: false
        };
        session.fields.field("label").set("probe-written");
        var reader = originalApi.settingsReadOwner;
        // Hold delivery at the host boundary after actual native observation.
        // The native editor also holds retirement open during this call stack.
        session.currentPluginApi = {
          settingsContext: originalApi.settingsContext,
          settingsReadOwner: {
            readProjection: {
              synchronize: function (observation, complete) {
                reader.readProjection.synchronize(observation, function (read) {
                  try {
                    check(read.status === "observed" && originalApi.settingsReady, "actual native receipt from a ready registration");
                    Service.loadPlugin(key, null, function (cached) {
                      try {
                        expect(cached.status === "failed" && cached.error?.code === "plugin-load-cancelled", "cached callback accepted a retired registration");
                        check(session.confirmDiscard(), "failed observation can be discarded");
                        session.destroy();
                      } catch (error) {
                        fail(error);
                      }
                    });
                    Service.unloadPlugin(key, true, function (unloaded) {
                      try {
                        check(unloaded.status !== "failed", "retirement settles after editor release");
                        Service.loadPlugin(key, null, function (first) {
                          try {
                            check(first.status === "loaded" && Service.getPluginAPI(key) !== originalApi, "first callback receives the registered replacement");
                            Service.unloadPlugin(key, true);
                          } catch (error) {
                            fail(error);
                          }
                        });
                        Service.loadPlugin(key, null, function (second) {
                          try {
                            expect(second.status === "failed" && second.error?.code === "plugin-load-cancelled", "coalesced callback accepted a registration retired by its sibling");
                            finish();
                          } catch (error) {
                            fail(error);
                          }
                        });
                      } catch (error) {
                        fail(error);
                      }
                    });
                    check(Service.getPluginAPI(key) === null && originalApi.settingsReady, "registration retires while the native owner is still ready");
                    complete(read);
                    expect(effects.join(",") === "settings-runtime-owner", "retired observation delivered " + effects.join(","));
                  } catch (error) {
                    fail(error);
                  }
                });
              }
            }
          }
        };
        Qt.callLater(function () {
          try {
            check(session.applySettings(), "native observation Apply admitted");
          } catch (error) {
            fail(error);
          }
        });
      } catch (error) {
        fail(error);
      }
    });
    Service.loadPlugin(key, null, function (result) {
      try {
        originalApi = Service.getPluginAPI(key);
        check(result.status === "loaded" && originalApi, "registration probe plugin loaded");
        check(session.openPluginSettings(probeManifest, "settings"), "registration probe editor admitted");
      } catch (error) {
        fail(error);
      }
    });
  }
  function openSessionOwner(callback) {
    Service._openSettingsOwner("session-quarantine", function (quarantined) {
      try {
        check(quarantined !== null, "quarantined source owner remains available for diagnosis");
        var refused = false;
        try {
          quarantined.settingsScope.values.label = "must-not-replace-directory";
        } catch (error) {
          refused = String(error).indexOf("source-quarantined") !== -1;
        }
        check(refused, "native startup directory quarantine refuses input");
        console.log("PLUGIN_SETTINGS_SESSION: QUARANTINE_PRESERVED");
        Service._openSettingsOwner("session-fixture", callback);
      } catch (error) {
        fail(error);
      }
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "session-fixture": manifest
    };
    openSessionOwner(function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("session-fixture", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "session-fixture": {
            api: api
          }
        };
        if (cold) {
          check(api.pluginSettings.label === "final", "separate cold shared consumer");
          PluginInstances.openRuntime(api, placement, function (result) {
            try {
              check(result.status === "opened" && result.editor.values.label === "final", "separate cold instance consumer");
              check(PluginInstances.entryFor(placement).instanceSettings === undefined, "cold reset removed override");
              result.editor.detach();
              console.log("PLUGIN_SETTINGS_SESSION: COLD_PASS");
              Qt.exit(0);
            } catch (error) {
              fail(error);
            }
          });
          return;
        }
        openingProbes(prepare);
      } catch (error) {
        fail(error);
      }
    });
  }
  function prepare() {
    try {
      var factory = api.createSettingsEditor;
      var previewFactory = api.createSettingsPreview;
      api.createSettingsPreview = function (editor) {
        root.retainedPreview = previewFactory(editor);
        return root.retainedPreview;
      };
      api.createSettingsEditor = function (fieldIntent) {
        var editor = factory(fieldIntent);
        return {
          get fieldCapture() {
            return editor.fieldCapture;
          },
          get handle() {
            return editor.handle;
          },
          get _releasePending() {
            return editor._releasePending;
          },
          get initialValue() {
            return editor.initialValue;
          },
          get values() {
            return editor.values;
          },
          get previewValues() {
            return editor.previewValues;
          },
          get writable() {
            return editor.writable;
          },
          get ready() {
            return editor.ready;
          },
          get busy() {
            return editor.busy;
          },
          get dirty() {
            return editor.dirty;
          },
          get closed() {
            return editor.closed;
          },
          get error() {
            return editor.error;
          },
          whenReady: editor.whenReady,
          release: editor.release,
          discard: editor.discard,
          copyValue: editor.copyValue,
          setField: editor.setField,
          stageFieldResets: editor.stageFieldResets,
          unsetField: editor.unsetField,
          publishPreview: editor.publishPreview,
          previewScope: editor.previewScope,
          rebased: editor.rebased,
          fields: editor.fields,
          apply: function (value, callback) {
            applies++;
            editor.apply(value, function (result) {
              if (root.hold)
                root.held = function () {
                  callback(result);
                };
              else
              callback(result);
            });
            if (root.stale)
              root.api.pluginSettings.label = "newer";
          }
        };
      };
      Settings.data.bar.widgets.left = [
            {
              id: "plugin:session-fixture",
              tag: "keep",
              instanceSettings: {
                label: "instance"
              }
            }
          ];
      Settings.saveSelected([["bar", "widgets", "left"]], function (result) {
        try {
          check(result.status !== "failed", "fixture placement saved");
          show();
          phase = "cancel";
        } catch (error) {
          fail(error);
        }
      });
    } catch (error) {
      fail(error);
    }
  }
  function drive() {
    var page = popup.settingsPage;
    if (phase === "cancel" && popup.opened && page) {
      check(!popup.dirty && api.pluginSettings.label === "shared", "untouched opening is nonpublishing");
      page.setLabel("local-discard");
      check(host.close() === false && popup.discardPending, "dirty host Close refused");
      popup.keepEditing();
      check(popup.settingsPage === page && page.labelText === "local-discard", "Keep editing retains exact page/input");
      check(!popup.openPluginSettings(manifest), "second Open refuses replacement");
      popup.confirmDiscard();
      phase = "reopen";
    } else if (phase === "reopen" && !popup.visible && !popup.currentPlugin) {
      check(api.pluginSettings.label === "shared", "discard left owner unchanged");
      show();
      phase = "apply";
    } else if (phase === "apply" && popup.opened && page) {
      page.setLabel("saved");
      check(page.pluginApi.previewSettings({
                                             label: "saved"
                                           }), "selected preview before Apply");
      hold = true;
      popup.applySettings();
      popup.applySettings();
      check(!popup.requestClose() && !popup.confirmDiscard() && popup.busy && applies === 1, "busy excludes competing actions");
      host.visible = false;
      phase = "held";
    } else if (phase === "held" && held) {
      check(host.visible && host.popupContentItem === popup && popup.visible, "native hide retains the same held-completion page and host");
      check(popup.busy && receipts === 0 && page.callbacks === 0, "native result held before completion feedback");
      var complete = held;
      held = null;
      hold = false;
      complete();
      phase = "held-settled";
    } else if (phase === "held-settled" && !popup.busy) {
      check(!popup.busy && !popup.saveFailed && !popup.dirty && page.callbacks === 2 && page.completionOrder === "signal,callback,callback", "current receipt and signal-before-callback ordering");
      check(!page.pluginApi.previewDirty, "fully acknowledged preview left before runtime completion");
      page.submitInput = false;
      popup.applySettings();
      phase = "noop";
    } else if (phase === "noop" && !popup.busy) {
      check(!popup.saveFailed && page.lastStatus === "nothing_to_save" && page.callbacks === 4, "actual no-op receipt acknowledged");
      page.submitInput = true;
      page.setLabel("before-newer-preview");
      check(page.pluginApi.previewSettings({
                                             label: "before-newer-preview"
                                           }), "preview before held write");
      hold = true;
      popup.applySettings();
      phase = "newer-preview-held";
    } else if (phase === "newer-preview-held" && held) {
      // Simulate an already-retained input continuation arriving after native
      // writer settlement but before the host receives its held acknowledgment.
      check(retainedPreview.update({
                                     label: "newer-preview"
                                   }), "newer preview revision admitted by retained capability");
      var newerComplete = held;
      held = null;
      hold = false;
      newerComplete();
      phase = "newer-preview-retained";
    } else if (phase === "newer-preview-retained" && !popup.busy) {
      check(popup.saveFailed && page.pluginApi.previewDirty && page.pluginApi.field("label").value === "newer-preview", "newer pending preview and field input never discarded");
      check(page.labelText === "before-newer-preview", "unacknowledged page buffer retained");
      page.setLabel("newer-preview");
      popup.applySettings();
      phase = "newer-preview-retry";
    } else if (phase === "newer-preview-retry" && !popup.busy) {
      check(!popup.saveFailed && !page.pluginApi.previewDirty && api.pluginSettings.label === "newer-preview", "later Apply commits retained newer input and leaves only its preview");
      fault("block", function () {
        popup.settingsPage.setLabel("failed-local");
        check(popup.settingsPage.pluginApi.previewSettings({
                                                             label: "failed-local"
                                                           }), "failed-write preview staged");
        popup.applySettings();
        phase = "failure";
      });
      phase = "fault";
    } else if (phase === "failure" && !popup.busy) {
      check(popup.saveFailed && popup.visible && page.labelText === "failed-local" && page.lastStatus === "failed", "real IO failure retains input");
      check(page.pluginApi.previewDirty, "failed-write preview untouched");
      check(!popup.requestClose() && popup.discardPending, "failed close requires discard");
      popup.keepEditing();
      fault("repair", function () {
        popup.applySettings();
        phase = "retry";
      });
      phase = "fault";
    } else if (phase === "retry" && !popup.busy) {
      check(!popup.saveFailed && page.lastStatus !== "failed", "same editor retry succeeds after repair");
      stale = true;
      page.setLabel("stale-local");
      check(page.pluginApi.previewSettings({
                                             label: "stale-local"
                                           }), "stale-write preview staged");
      popup.applySettings();
      phase = "stale";
    } else if (phase === "stale" && !popup.busy) {
      check(popup.saveFailed && page.labelText === "stale-local" && api.pluginSettings.label === "newer", "saved-but-stale retains local input and newer owner");
      check(page.pluginApi.previewDirty, "stale-write preview untouched");
      popup.requestClose();
      popup.confirmDiscard();
      stale = false;
      phase = "final-open";
    } else if (phase === "final-open" && !popup.visible && !popup.currentPlugin) {
      show();
      phase = "final";
    } else if (phase === "final" && popup.opened && page) {
      page.setLabel("final");
      popup.applySettings();
      phase = "final-wait";
    } else if (phase === "final-wait" && !popup.busy) {
      check(!popup.saveFailed && api.pluginSettings.label === "final", "current final shared value");
      popup.requestClose();
      phase = "instance-open";
    } else if (phase === "instance-open" && !popup.visible && !popup.currentPlugin) {
      instance = PluginInstances.apiFor("session-fixture", placement);
      show(instance);
      phase = "instance";
    } else if (phase === "instance" && popup.opened && page) {
      check(page.labelText === "instance", "selected instance values");
      page.setLabel("selected");
      popup.applySettings();
      phase = "instance-wait";
    } else if (phase === "instance-wait" && !popup.busy && instance.pluginSettings.label === "selected") {
      check(!popup.saveFailed && api.pluginSettings.label === "final", "instance Apply does not change shared owner");
      page.setLabel("unsaved-before-reset");
      popup.resetButton.clicked();
      popup.resetInstanceSettings();
      phase = "reset";
    } else if (phase === "reset" && !popup.busy && popup.settingsPage && popup.settingsPage.labelText === "final") {
      check(!popup.saveFailed && !popup.dirty && !popup.resetConfirmation.visible, "current Reset reloads and retires input");
      check(PluginInstances.entryFor(placement).instanceSettings === undefined && Settings.data.bar.widgets.left[0].tag === "keep", "native reset sparse persistence and opaque row retained");
      check(popup.requestClose(), "clean Close accepted");
      phase = "legacy-open";
    } else if (phase === "legacy-open" && !popup.visible && !popup.currentPlugin) {
      manifest = Object.assign({}, manifest, {
                                 entryPoints: {
                                   settings: "Legacy.qml"
                                 }
                               });
      show();
      phase = "legacy-close";
    } else if (phase === "legacy-close" && popup.opened && page) {
      check(typeof page.settingsDirty !== "boolean", "legacy page has no tracked dirty predicate");
      page.setLabel("untracked-local-buffer");
      check(!popup.requestClose() && popup.discardPending && popup.settingsPage === page, "untracked page Close conservatively confirms without Save");
      popup.keepEditing();
      check(popup.settingsPage === page && page.labelText === "untracked-local-buffer", "untracked buffer survives Keep editing");
      check(popup.confirmDiscard(), "untracked input discarded only explicitly");
      phase = "registration-open";
    } else if (phase === "registration-open" && !popup.visible && !popup.currentPlugin) {
      phase = "registration-probes";
      registrationProbes();
    }
  }
  Process {
    id: faultProcess
    onExited: code => {
      try {
        check(code === 0, "guarded permission fault");
        faultBlocked = command[command.length - 1] === "block";
        var next = afterFault;
        afterFault = null;
        next();
      } catch (error) {
        fail(error);
      }
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    NPluginSettingsPopup {
      id: popup
      parent: host.dialogParent
      screen: Quickshell.screens[0]
      onSettingsCompleted: root.receipts++
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Timer {
    interval: 45000
    running: true
    onTriggered: root.fail("session watchdog at " + root.phase)
  }
  Component.onCompleted: begin()
}
