// Actual UI entry for the guest-only deployment regression. No settings mock.
import AtmospheraSettingsTest 1.0
import DBus 1.0 as DBusQML
import Niri 1.0
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Modules.Bar.Widgets as BarWidgets
import qs.Modules.Panels.Media
import qs.Modules.Panels.Settings.Tabs.General
import qs.Modules.Panels.SetupWizard
import qs.Modules.Panels.Tray
import qs.Services.Keyboard
import qs.Services.Session
import qs.Services.System
import qs.Services.UI

ShellRoot {
  SettingsBootstrap {
    id: settingsBootstrap
  }
  Loader {
    active: settingsBootstrap.ready
    sourceComponent: Component {
      Item {
        id: probe
        readonly property string mode: Quickshell.env("DEPLOYMENT_CASE") || "settings"
        property bool ready: false
        property bool failNextFinish: false
        property int eventSerial: 0
        property var capturedOrdinaryId: null
        property string capturedOrdinaryJson: ""
        property string capturedOrdinaryBase: ""
        property bool watchMissingAcceptance: false
        property bool watchManagedEffective: false
        property bool watchAcceptedChoice: false
        property string terminalRetryTrigger: ""
        property bool terminalRetryArmed: false
        property var privateTerminals: ({})
        property int privateTransferSerial: 0
        property string privateTransferText: ""
        property var capturedOrdinaryFrozen: null
        property bool externalListenerArmed: false
        property string externalListenerKind: ""
        property string externalListenerPath: ""
        property var modelDefaultScale: Settings.getDefaultValue("ui.fontDefaultScale")
        property var modelDefaultObservations: []
        property bool modelCallbackArmed: false
        property bool modelCallbackActive: false
        property bool modelCallbackReturned: false
        property var modelCallbackEvents: []
        property var modelCallbackSignalState: null
        property var modelCallbackBefore: null
        property string modelCallbackOuter: ""
        property string modelCallbackNested: ""
        property int modelCallbackSavedSignals: 0
        NativeStoreProbe {
          id: nativeOwner
          target: Settings.store
        }
        function nativeState() {
          return nativeOwner.sample([["ui", "fontDefaultScale"], ["general", "scaleRatio"], ["bar", "position"], ["bindings", "environment"], ["bar", "widgets", "left"], ["general", "futureRaw"]]);
        }
        onModelDefaultScaleChanged: modelDefaultObservations.push({
                                                                    "defined": modelDefaultScale !== undefined,
                                                                    "value": modelDefaultScale === undefined ? null : modelDefaultScale
                                                                  })

        function listValues(value) {
          var result = [];
          for (var i = 0; i < value.length; i++)
            result.push(value[i]);
          return result;
        }

        function privateSnapshot() {
          // Delivered only as an IPC return value on the owned pipe, never in report().
          var paths = ["ui.fontDefaultScale", "general.scaleRatio", "general.dimmerOpacity", "general.keybinds.keyUp", "general.keybinds.keyDown", "general.keybinds.keyLeft", "bar.widgets.left", "bindings.environment"];
          var information = {};
          for (var path of paths)
            information[path] = Settings.store.info(path.split("."));
          return JSON.parse(JSON.stringify({
                                             "native": {
                                               "sources": Settings.store.sourceStates,
                                               "paths": information,
                                               "owner": probe.nativeState()
                                             },
                                             "consumer": {
                                               "uiScale": Settings.data.ui.fontDefaultScale,
                                               "generalScale": Settings.data.general.scaleRatio,
                                               "dimmer": Settings.data.general.dimmerOpacity,
                                               "keyUp": probe.listValues(Settings.data.general.keybinds.keyUp),
                                               "keyDown": probe.listValues(Settings.data.general.keybinds.keyDown),
                                               "keyLeft": probe.listValues(Settings.data.general.keybinds.keyLeft),
                                               "widgetsLeft": probe.listValues(Settings.data.bar.widgets.left)
                                             }
                                           }));
        }
        function sourceState(section) {
          var states = Settings.store.sourceStates;
          for (var state of states)
            if (state.sourceId === section)
              return state;
          return null;
        }

        function terminalSnapshot(token) {
          probe.privateTerminals[token] = probe.privateSnapshot();
        }

        function beginPrivateTransfer(value) {
          var serialized = JSON.stringify(value);
          if (typeof serialized !== "string" || serialized.length === 0 || serialized.length >= 16 * 1024 * 1024)
            throw new Error("Invalid private snapshot transfer body");
          probe.privateTransferSerial++;
          probe.privateTransferText = serialized.replace(/[\u007f-\uffff]/g, function (character) {
            return "\\u" + ("0000" + character.charCodeAt(0).toString(16)).slice(-4);
          });
          return JSON.stringify({
                                  protocol: "deployment-private-v1",
                                  id: probe.privateTransferSerial,
                                  length: probe.privateTransferText.length
                                });
        }

        function captureFields(intent) {
          return JSON.parse(JSON.stringify({
                                             "captureId": intent.captureId,
                                             "provenance": intent.provenance,
                                             "section": intent.section,
                                             "path": intent.path,
                                             "json": intent.json,
                                             "base": intent.base,
                                             "foreignEpoch": intent.foreignEpoch,
                                             "coveredPaths": intent.coveredPaths
                                           }));
        }

        function externalListener(path) {
          if (!probe.externalListenerArmed || path !== probe.externalListenerPath)
            return;
          probe.externalListenerArmed = false;
          var before = probe.privateSnapshot();
          if (path === "bar.widgets.left")
            Settings.data.bar.widgets.left[0].correctiveLocal = {
              "values": [false, 0, null, ""]
            };
          else
          Settings.data.ui.fontDefaultScale = 1.7;
          probe.terminalSnapshot("listener-after-edit");
          probe.privateTerminals["listener-before-edit"] = before;
          var state = probe.nativeState();
          probe.report("corrective-listener", {
                         "path": path,
                         "kind": probe.externalListenerKind,
                         "inputPrefix": state.inputPrefix,
                         "pendingRequests": state.pendingRequests
                       });
          if (probe.externalListenerKind === "save") {
            Settings.saveImmediate(function (result) {
              probe.terminalSnapshot("corrective-listener-save");
              probe.report("save-callback", {
                             "token": "corrective-listener-save",
                             "success": result.status === "saved" || result.status === "nothing_to_save",
                             "error": result.error,
                             "receipt": result
                           });
            });
            probe.terminalSnapshot("listener-after-save-call");
          }
        }

        Connections {
          target: Settings.data.ui
          function onFontDefaultScaleChanged() {
            probe.externalListener("ui.fontDefaultScale");
          }
        }
        Connections {
          target: Settings.data.bar.widgets
          function onLeftChanged() {
            probe.externalListener("bar.widgets.left");
          }
        }

        function terminalRetry() {
          terminalRetryArmed = false;
          var environment = BindingsService.headEnvironment;
          BindingsService.retryHead(function (success, error, id, attempt) {
            probe.report("callback", {
                           "token": "terminal-retry",
                           "success": success,
                           "error": error,
                           "requestId": id,
                           "attemptId": attempt,
                           "capturedEnvironment": environment,
                           "state": BindingsService.state
                         });
          });
          BindingsService.requestEnvironment("none", function (success, error, id, attempt) {
            probe.report("callback", {
                           "token": "terminal-enqueued",
                           "success": success,
                           "error": error,
                           "requestId": id,
                           "attemptId": attempt,
                           "capturedEnvironment": "none",
                           "state": BindingsService.state
                         });
          });
        }

        function report(event, detail) {
          console.log("DEPLOYMENT_PROBE|" + JSON.stringify({
                                                             "event": event,
                                                             "serial": ++probe.eventSerial,
                                                             "at": Date.now(),
                                                             "environment": Settings.data.bindings.environment,
                                                             "detail": detail || "",
                                                             "queue": JSON.parse(JSON.stringify(BindingsService.status))
                                                           }));
        }

        function start() {
          if (ready)
            return;
          ready = true;
          if (mode === "terminal-startup") {
            probe.terminalRetryTrigger = "signal";
            probe.terminalRetryArmed = true;
            var startupEnvironment = Settings.data.bindings.environment;
            BindingsService.observeStartup(function (success, error, id, attempt) {
              probe.report("startup-observer", {
                             "token": "startup-frozen",
                             "success": success,
                             "error": error,
                             "requestId": id,
                             "attemptId": attempt,
                             "capturedEnvironment": startupEnvironment
                           });
            });
            BindingsService.observeStartup(function (success, error, id, attempt) {
              probe.report("startup-observer", {
                             "token": "startup-frozen-second",
                             "success": success,
                             "error": error,
                             "requestId": id,
                             "attemptId": attempt,
                             "capturedEnvironment": startupEnvironment
                           });
            });
            BindingsService.init(function (environment, complete) {
              complete(false, "captured startup failure");
            }, function (success, error, id, attempt) {
              probe.report("callback", {
                             "token": "terminal-original",
                             "success": success,
                             "error": error,
                             "requestId": id,
                             "attemptId": attempt,
                             "capturedEnvironment": startupEnvironment,
                             "state": BindingsService.state
                           });
              probe.report("startup", {
                             "success": success,
                             "error": error
                           });
            });
          } else if (mode !== "runtime-consumers") {
            InitService.init(function (success, error) {
              probe.report("startup", {
                             "success": success,
                             "error": error
                           });
            });
          }
          win.visible = true;
          if (mode === "wizard")
            wizard.open();
          report("ready", mode);
        }

        Connections {
          target: Settings
          function onSettingsLoaded() {
            probe.start();
          }
          function onSettingsSaved() {
            probe.report("saved", "");
            if (probe.modelCallbackActive)
              probe.modelCallbackSavedSignals++;
          }
          function onSettingsSaveCompleted(result) {
            probe.report("native-save-completed", {
                           requestId: result.requestId,
                           operation: result.operation,
                           status: result.status,
                           inputPrefix: result.inputPrefix,
                           coverage: result.coverage,
                           error: result.error ? result.error.code : ""
                         });
            if (!probe.modelCallbackActive || result.operation !== "save")
              return;
            probe.modelCallbackEvents.push({
                                             event: "signal",
                                             requestId: result.requestId,
                                             status: result.status,
                                             pending: probe.nativeState().pendingRequests
                                           });
            if (probe.modelCallbackArmed) {
              probe.modelCallbackArmed = false;
              probe.modelCallbackSignalState = probe.nativeState();
              probe.modelCallbackNested = Settings.saveImmediate(function (nested) {
                probe.modelCallbackEvents.push({
                                                 "event": "nested-callback",
                                                 "requestId": nested.requestId,
                                                 "status": nested.status,
                                                 "returned": probe.modelCallbackReturned,
                                                 "pending": probe.nativeState().pendingRequests
                                               });
                probe.modelCallbackActive = false;
                probe.report("model-facade-contract", {
                               before: probe.modelCallbackBefore,
                               outer: probe.modelCallbackOuter,
                               nested: probe.modelCallbackNested,
                               atSignal: probe.modelCallbackSignalState,
                               after: probe.nativeState(),
                               savedSignals: probe.modelCallbackSavedSignals,
                               events: probe.modelCallbackEvents
                             });
              });
            }
          }
          function onSettingsReloaded() {
            probe.report("settings-reloaded", "");
          }
          function onSettingsSaveFailed(error) {
            probe.terminalSnapshot("first-failed-notification-" + probe.eventSerial);
            probe.report("save-failed", error);
          }
          function onBindingsEnvironmentRequested(environment) {
            var state = probe.sourceState("bindings");
            if (probe.watchMissingAcceptance)
              probe.report("audit-missing-acceptance", {
                             "selected": environment,
                             "exists": state && state.presence === "present",
                             "identity": state ? state.revision : ""
                           });
            if (probe.watchAcceptedChoice) {
              probe.watchAcceptedChoice = false;
              probe.report("audit-accepted-choice", {
                             "coherentRaw": Settings.effectiveDiskEnvironment() === environment,
                             "identitySettled": state && state.revision !== ""
                           });
              BindingsService.requestEnvironment("none", function (success, error, id, attempt) {
                probe.report("callback", {
                               "token": "accepted-tail",
                               "success": success,
                               "error": error,
                               "requestId": id,
                               "attemptId": attempt,
                               "state": BindingsService.state
                             });
              });
            }
          }
          function onEffectiveSettingsChanged(section) {
            if (probe.mode === "runtime-consumers")
              probe.report("effective-change", section);
            if (probe.watchManagedEffective && section === "bindings") {
              probe.watchManagedEffective = false;
              var state = probe.nativeState();
              var intent = state.groups.some(function (group) {
                return group.requestKey === BindingsService.headRequestId;
              });
              probe.report("audit-managed-effective", {
                             "intentInstalled": !!intent,
                             "snapshotSettled": state.paths["bindings.environment"].admittedFingerprint === state.paths["bindings.environment"].presentedFingerprint
                           });
              Settings.data.ui.fontDefaultScale = 1.6;
              Settings.saveImmediate(function (result) {
                probe.report("save-callback", {
                               "token": "effective-save",
                               "success": result.status === "saved" || result.status === "nothing_to_save",
                               "error": result.error,
                               "receipt": result
                             });
              });
              BindingsService.requestEnvironment("none", function (success, error, id, attempt) {
                probe.report("callback", {
                               "token": "effective-tail",
                               "success": success,
                               "error": error,
                               "requestId": id,
                               "attemptId": attempt,
                               "state": BindingsService.state
                             });
              });
            }
          }
        }

        Connections {
          target: BindingsService
          function onRequestFinished(requestId, attemptId, environment, success, error) {
            probe.terminalSnapshot("handoff-" + requestId + "-" + attemptId);
            probe.report("handoff", {
                           "requestId": requestId,
                           "attemptId": attemptId,
                           "selected": environment,
                           "success": success,
                           "error": error
                         });
            if (!success && probe.terminalRetryArmed && probe.terminalRetryTrigger === "signal")
              probe.terminalRetry();
          }
          function onStateChanged() {
            if (BindingsService.state === "Stopped" && probe.terminalRetryArmed && probe.terminalRetryTrigger === "status")
              probe.terminalRetry();
          }
          function onStageChanged(requestId, attemptId, stage, environment) {
            probe.report("stage", {
                           "requestId": requestId,
                           "attemptId": attemptId,
                           "stage": stage,
                           "selected": environment
                         });
          }
        }

        Connections {
          target: NiriConnection
          function onConnectedChanged() {
            probe.report("transport", {
                           "connected": NiriConnection.isConnected
                         });
          }
        }

        Component.onCompleted: {
          if (Settings.isLoaded)
            start();
        }

        IpcHandler {
          target: "deploymentprobe"
          function finish() {
            if (probe.failNextFinish) {
              probe.failNextFinish = false;
              throw new Error("injected teardown refusal");
            }
            probe.report("finishing", {
                           "queue": BindingsService.status
                         });
            Qt.exit(0);
          }
          // Concurrency/failure legs exercise the public selection/application seam;
          // first deployment and wizard legs use physical clicks on shipped controls.
          function request(environment: string, token: string) {
            var complete = function (success, error, requestId, attemptId) {
              probe.terminalSnapshot(token);
              probe.report("callback", {
                             "token": token,
                             "success": success,
                             "error": error,
                             "requestId": requestId || "",
                             "attemptId": attemptId || 0,
                             "capturedEnvironment": environment,
                             "state": typeof BindingsService.state === "string" ? BindingsService.state : "legacy"
                           });
            };
            var identity = BindingsService.requestEnvironment(environment, complete);
            probe.report("submitted", {
                           "requestId": identity,
                           "token": token,
                           "capturedEnvironment": environment
                         });
          }
          function retry(token: string) {
            var environment = BindingsService.headEnvironment;
            var identity = BindingsService.retryHead(function (success, error, requestId, attemptId) {
              probe.terminalSnapshot(token);
              probe.report("callback", {
                             "token": token,
                             "success": success,
                             "error": error,
                             "requestId": requestId,
                             "attemptId": attemptId,
                             "capturedEnvironment": environment,
                             "state": BindingsService.state
                           });
            });
            probe.report("retry-submitted", {
                           "requestId": identity,
                           "token": token
                         });
          }
          function save(token: string) {
            Settings.saveImmediate(function (result) {
              probe.terminalSnapshot(token);
              probe.report("save-callback", {
                             "token": token,
                             "success": result.status === "saved" || result.status === "nothing_to_save",
                             "error": result.error,
                             "receipt": result
                           });
            });
          }
          function settle(token: string) {
            Settings.store.flush(function (result) {
              probe.report("save-callback", {
                             token: token,
                             success: result.status === "saved" || result.status === "nothing_to_save",
                             error: result.error,
                             receipt: result
                           });
            });
          }
          function modelDefaults(method: string) {
            Settings[method]();
          }
          function modelFacadeState(): string {
            return probe.beginPrivateTransfer({
                                                "defaultDefined": probe.modelDefaultScale !== undefined,
                                                "boundDefault": probe.modelDefaultScale === undefined ? null : probe.modelDefaultScale,
                                                "defaultObservations": probe.modelDefaultObservations,
                                                "native": probe.nativeState()
                                              });
          }
          function modelCallbackReentry() {
            probe.modelCallbackEvents = [];
            probe.modelCallbackArmed = true;
            probe.modelCallbackActive = true;
            probe.modelCallbackReturned = false;
            probe.modelCallbackSavedSignals = 0;
            probe.modelCallbackBefore = probe.nativeState();
            probe.modelCallbackOuter = Settings.saveImmediate(function (result) {
              probe.modelCallbackEvents.push({
                                               "event": "outer-callback",
                                               "requestId": result.requestId,
                                               "status": result.status,
                                               "returned": probe.modelCallbackReturned,
                                               "pending": probe.nativeState().pendingRequests
                                             });
            });
            probe.modelCallbackReturned = true;
          }
          function status(token: string) {
            probe.report("status", {
                           "token": token,
                           "wizardOpen": wizard.isPanelOpen,
                           "wizardChoice": wizard.selectedBindingEnvironment,
                           "wizardSubmitted": wizard.submittedStatus ? JSON.parse(JSON.stringify(wizard.submittedStatus)) : null,
                           "wizardOutstanding": wizard.workOutstanding,
                           "niriConnected": NiriConnection.isConnected,
                           "scale": Settings.data.ui.fontDefaultScale,
                           "owner": BindingsService.status
                         });
          }
          function editScale(value: string) {
            Settings.data.ui.fontDefaultScale = Number(value);
            Settings.saveImmediate();
          }
          function auditSaveScale(value: string, token: string) {
            Settings.data.ui.fontDefaultScale = Number(value);
            var request = Settings.saveImmediate(function (result) {
              probe.terminalSnapshot(token);
              probe.report("save-callback", {
                             "token": token,
                             "success": result.status === "saved" || result.status === "nothing_to_save",
                             "error": result.error,
                             "receipt": result
                           });
            });
            var state = probe.nativeState();
            probe.capturedOrdinaryId = request;
            probe.capturedOrdinaryFrozen = {
              requestId: request,
              inputPrefix: state.inputPrefix,
              inputs: state.inputs
            };
          }
          function auditCaptureScale(value: string) {
            Settings.data.ui.fontDefaultScale = Number(value);
          }
          function auditEdit(path: string, value: string) {
            var parts = path.split(".");
            var target = Settings.data;
            for (var i = 0; i < parts.length - 1; i++)
              target = target[parts[i]];
            target[parts[parts.length - 1]] = JSON.parse(value);
          }
          function auditRead(section: string, token: string, throwing: string) {
            Settings.store.reload(function (result) {
              var state = probe.sourceState(section);
              probe.report("audit-read", {
                             "token": token,
                             "success": result.status === "reloaded",
                             "error": result.error,
                             "exists": state ? state.presence === "present" : null,
                             "identity": state ? state.revision : "",
                             "receipt": result,
                             "consumerScale": Settings.data.ui.fontDefaultScale
                           });
              if (throwing === "throw")
                throw new Error("injected old read callback failure");
            });
          }
          function auditWatchMissing() {
            probe.watchMissingAcceptance = true;
          }
          function auditWatchManagedEffective() {
            probe.watchManagedEffective = true;
          }
          function auditWatchAcceptedChoice() {
            probe.watchAcceptedChoice = true;
          }
          function auditTerminalRetry(trigger: string) {
            probe.terminalRetryTrigger = trigger;
            probe.terminalRetryArmed = true;
          }
          function auditCaptureABA(intermediate: string, finalValue: string) {
            Settings.data.ui.fontDefaultScale = Number(intermediate);
            Settings.data.ui.fontDefaultScale = Number(finalValue);
          }
          function auditState(token: string) {
            // Ownership/consumer observations only; never log captured raw payloads.
            var state = probe.nativeState();
            probe.report("audit-state", {
                           "token": token,
                           "uiScale": Settings.data.ui.fontDefaultScale,
                           "dimmer": Settings.data.general.dimmerOpacity,
                           "generalScale": Settings.data.general.scaleRatio,
                           "native": state,
                           "hasSnapshotFutureRaw": state.paths["general.futureRaw"].admittedPresent
                         });
          }
          function auditNativeState(): string {
            return probe.beginPrivateTransfer(probe.nativeState());
          }
          function nativePacketsBegin() {
            nativeOwner.beginPackets();
          }
          function nativePackets(): string {
            return probe.beginPrivateTransfer(nativeOwner.packets([["ui", "fontDefaultScale"], ["general", "scaleRatio"]]));
          }
          function nativePacketRelease(index: int) {
            nativeOwner.releasePacket(index);
          }
          function nativePacketsEnd() {
            nativeOwner.endPackets();
          }
          function auditPrivateState(): string {
            return probe.beginPrivateTransfer({
                                                "current": probe.privateSnapshot(),
                                                "terminals": probe.privateTerminals,
                                                "native": probe.nativeState(),
                                                "frozenCapture": probe.capturedOrdinaryFrozen
                                              });
          }
          function auditPrivateBegin(): string {
            return auditPrivateState();
          }
          function auditPrivateChunk(identity: int, offset: int, count: int): string {
            if (identity !== probe.privateTransferSerial || offset < 0 || count < 1 || count > 4096 || offset >= probe.privateTransferText.length)
              throw new Error("Invalid private snapshot transfer frame");
            return JSON.stringify({
                                    "id": identity,
                                    "offset": offset,
                                    "body": probe.privateTransferText.slice(offset, offset + count)
                                  });
          }
          function correctiveEditOnly(path: string, value: string) {
            var parts = path.split(".");
            var target = Settings.data;
            for (var i = 0; i < parts.length - 1; i++)
              target = target[parts[i]];
            target[parts[parts.length - 1]] = JSON.parse(value);
          }
          function correctiveCapture(path: string, value: string): string {
            var parts = path.split(".");
            var section = parts[0];
            var before = probe.sourceState(section);
            var beforeInput = Settings.store.info(parts);
            var decoded = JSON.parse(value);
            var target = Settings.data;
            for (var i = 0; i < parts.length - 1; i++)
              target = target[parts[i]];
            target[parts[parts.length - 1]] = decoded;
            return probe.beginPrivateTransfer({
                                                "input": value,
                                                "decoded": decoded,
                                                "decodedNativeArray": Array.isArray(decoded),
                                                "before": before,
                                                "after": probe.sourceState(section),
                                                "beforeInput": beforeInput,
                                                "current": probe.privateSnapshot()
                                              });
          }
          function correctiveListen(kind: string, path: string) {
            probe.externalListenerKind = kind;
            probe.externalListenerPath = path;
            probe.externalListenerArmed = true;
          }
          function correctiveReset(path: string) {
            Settings.resetValue(path);
          }
          function hugeSave(token: string) {
            Settings.data.bar.middleClickCommand = "private-stdin-fixture-" + Array(150000).join("x");
            Settings.saveImmediate(function (result) {
              probe.report("save-callback", {
                             "token": token,
                             "success": result.status === "saved" || result.status === "nothing_to_save",
                             "error": result.error,
                             "receipt": result
                           });
            });
          }
          function saveThrow(token: string) {
            Settings.data.ui.fontDefaultScale = 1.25;
            Settings.saveImmediate(function (result) {
              probe.report("save-callback", {
                             "token": token,
                             "success": result.status === "saved" || result.status === "nothing_to_save",
                             "error": result.error,
                             "receipt": result
                           });
              throw new Error("injected callback throw");
            });
          }
          function requestThrow(environment: string, token: string) {
            BindingsService.requestEnvironment(environment, function (success, error, id, attempt) {
              probe.report("callback", {
                             "token": token,
                             "success": success,
                             "error": error,
                             "requestId": id,
                             "attemptId": attempt,
                             "state": BindingsService.state
                           });
              throw new Error("injected callback throw");
            });
          }
          function reentrant(environment: string, token: string, nextEnvironment: string) {
            BindingsService.requestEnvironment(environment, function (success, error, id, attempt) {
              probe.report("callback", {
                             "token": token,
                             "success": success,
                             "error": error,
                             "requestId": id,
                             "attemptId": attempt,
                             "state": BindingsService.state
                           });
              BindingsService.requestEnvironment(nextEnvironment, function (nextSuccess, nextError, nextId, nextAttempt) {
                probe.report("callback", {
                               "token": token + "-nested",
                               "success": nextSuccess,
                               "error": nextError,
                               "requestId": nextId,
                               "attemptId": nextAttempt,
                               "state": BindingsService.state
                             });
              });
            });
          }
          function repeatInit(token: string) {
            InitService.init(function (success, error) {
              probe.report("startup-observer", {
                             "token": token,
                             "success": success,
                             "error": error
                           });
            });
          }
          function teardownFault() {
            probe.failNextFinish = true;
          }
          function wizardClose() {
            wizard.close();
          }
          function wizardOpen() {
            wizard.open();
          }
          function auditWizardSelection() {
            wizard.selectedScaleRatio = 1.2;
            wizard.selectedBarPosition = "bottom";
            wizard.selectedBindingEnvironment = "macos";
          }
          function auditWizardFinish() {
            wizard.completeSetup();
          }
          function auditWizardScale(value: string) {
            wizard.selectedScaleRatio = Number(value);
            wizard.applyUISettings();
          }
          function auditWizardApplySelection() {
            wizard.applyUISettings();
          }
          function runtimeConsumerValues(token: string) {
            probe.report("runtime-consumers", runtimeComponents.item.values(token));
          }
          function runtimeConsumerEdit(token: string) {
            // Actual settings and actual consumer components; no persistence or
            // consumer owner is replaced by a mock. Mutate the opaque widget
            // records in-place to require effective invalidation on the save seam.
            Settings.data.bar.widgets.left[0].pinned = ["Atmosphera Harness Tray"];
            Settings.data.bar.widgets.left[1].compactMode = true;
            Settings.data.bar.widgets.left[1].panelShowAlbumArt = false;
            Settings.data.notifications.enabled = false;
            Settings.saveImmediate(function (result) {
              probe.report("save-callback", {
                             "token": token,
                             "success": result.status === "saved" || result.status === "nothing_to_save",
                             "error": result.error,
                             "receipt": result
                           });
            });
          }
          function runtimeOpenDrawer() {
            runtimeComponents.item.openDrawer();
          }
        }

        Timer {
          interval: 900000
          running: true
          onTriggered: {
            probe.report("watchdog", "");
            Qt.exit(2);
          }
        }

        FloatingWindow {
          id: win
          title: "bindings-deployment-regression"
          implicitWidth: 1000
          implicitHeight: 680
          visible: false
          color: AtmoColor.mSurface || "#202020"
          Loader {
            anchors.fill: parent
            anchors.margins: 24
            active: probe.mode === "settings" && probe.ready
            sourceComponent: Component {
              ShortcutsSubTab {}
            }
          }
          Loader {
            id: runtimeComponents
            active: probe.mode === "runtime-consumers" && probe.ready
            sourceComponent: Component {
              Item {
                width: 500
                height: 120
                function values(token) {
                  return {
                    "token": token,
                    "privateBus": Quickshell.env("DBUS_SESSION_BUS_ADDRESS"),
                    "trayPinned": consumerTray.pinned,
                    "trayBlacklist": consumerTray.blacklist,
                    "trayIdentities": SystemTray.items.values.map(function (item) {
                      return {
                        "id": item.id,
                        "title": item.title,
                        "tooltipTitle": item.tooltipTitle
                      };
                    }),
                    "trayFiltered": consumerTray.filteredItems.length,
                    "drawerItems": consumerDrawer.itemCount,
                    "mediaCompact": consumerMedia.compactMode,
                    "mediaAlbumArt": consumerMedia.showAlbumArt,
                    "notificationHistoryCount": NotificationService.historyModel.count,
                    "notificationSummaries": NotificationService.getHistorySnapshot().map(function (entry) {
                      return entry.summary;
                    })
                  };
                }
                function openDrawer() {
                  consumerDrawer.open();
                }
                DBusQML.DBusAdaptor {
                  service: "org.kde.StatusNotifierItem.AtmospheraHarness"
                  path: "/StatusNotifierItem"
                  iface: "org.kde.StatusNotifierItem"
                  connection: DBusQML.SessionBus
                  property string category: "ApplicationStatus"
                  property string identifier: "Atmosphera Harness Tray"
                  property string title: "Atmosphera Harness Tray"
                  property string status: "Active"
                  property string iconName: "folder"
                  property string iconThemePath: ""
                  property bool itemIsMenu: false
                  property var menu: new DBusQML.objectPath("/MenuBar")
                  _members: {
                    "Id": "identifier"
                  }
                  _signatures: {
                    "Category": "s",
                    "Id": "s",
                    "Title": "s",
                    "Status": "s",
                    "IconName": "s",
                    "IconThemePath": "s",
                    "ItemIsMenu": "b",
                    "Menu": "o"
                  }
                  function activate(x, y) {
                  }
                  function secondaryActivate(x, y) {
                  }
                  function contextMenu(x, y) {
                  }
                  function scroll(delta, orientation) {
                  }
                }
                BarWidgets.Tray {
                  id: consumerTray
                  screen: Quickshell.screens[0] || null
                  widgetId: "Tray"
                  section: "left"
                  sectionWidgetIndex: 0
                }
                BarWidgets.MediaMini {
                  id: consumerMini
                  screen: Quickshell.screens[0] || null
                  widgetId: "MediaMini"
                  section: "left"
                  sectionWidgetIndex: 1
                  Component.onCompleted: {
                    if (screen)
                      BarService.registerWidget(screen.name, "left", "MediaMini", 1, consumerMini);
                  }
                  Component.onDestruction: {
                    if (screen)
                      BarService.unregisterWidget(screen.name, "left", "MediaMini", 1);
                  }
                }
                MediaPlayerPanel {
                  id: consumerMedia
                  screen: Quickshell.screens[0] || null
                  property var modelData: ({
                                             "name": screen ? screen.name : ""
                                           })
                }
                TrayDrawerPanel {
                  id: consumerDrawer
                  screen: Quickshell.screens[0] || null
                  widgetSection: "left"
                  widgetIndex: 0
                  property var modelData: ({
                                             "name": screen ? screen.name : ""
                                           })
                }
                Component.onCompleted: Qt.callLater(function () {
                  consumerDrawer.open();
                })
              }
            }
          }
          SetupWizard {
            id: wizard
            onClosed: probe.report("wizard-closed", "")
            objectName: "deploymentRegressionWizard"
            anchors.fill: parent
            screen: Quickshell.screens[0] || null
            property var modelData: ({
                                       "name": screen ? screen.name : ""
                                     })
          }
        }
      }
    }
  }
}
