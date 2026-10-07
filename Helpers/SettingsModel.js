.pragma library
.import "sha256.js" as Checksum

// One owner per Settings instance. Only transition() can enter a mutating
// handler. Continuations and job references stay inside this closure; the
// adapter receives detached effects and returns their original operation token.
function create(configuration) {
    var config = detached(configuration);
    var root = {
        isLoaded: false, _schemaTree: null, _defaultSettings: null,
        _sections: [], _sawAnyFile: false, _snapshot: null,
        _overrides: {}, _legacyOverrides: {}, _runtimeSnapshot: null,
        _persistQueue: [], _persistWaiters: [], _persistDirtySections: {},
        _persistRevisions: {}, _persistSerial: 0, _persistRunning: false,
        _persistLastError: "", _persistBatchError: "", _activePersist: null,
        _acceptedFiles: {}, _foreignEpochs: {}, _confirmedOwn: {},
        _readWaiters: {}, _readSerials: {}, _acceptedReadSerials: {},
        _acceptGenerations: {}, _nonReadAcceptGenerations: {},
        _publicationGenerations: {}, _readsInFlight: {}, _observationWaiters: {},
        _persistResults: {}, _pendingPaths: {}, _captureSerial: 0,
        _bindingIntents: {}, _ordinaryIntents: {}, _setupBundles: {},
        _confirmedOriginEpochs: {}, _captureDepth: 0,
        _notifyingEffective: false, _effectivePending: false,
        _observedNotifications: [], _notifyingObserved: false,
        _bindingsManaged: false, _bindingsUnresolved: false,
        _acceptedBindingChoice: "none"
    };
    var effects = null;
    var current = null; // Detached input for this transition, never a working truth.
    var operationSerial = 0;
    var operations = {};
    var readDeliveries = {};
    var applications = {};
    var assignments = {};
    var captures = {};
    var saveDeliveries = {};

    function effect(kind, detail) {
        detail.kind = kind;
        effects.push(detached(detail));
    }
    function log(level, message, path) {
        effect("log", {level: level, message: message, path: path || ""});
    }
    function filePathFor(section) {
        return section === "legacy" ? config.settingsFile : config.overridesDir + section + ".json";
    }
    function getDefaultValue(path) {
        return root._defaultSettings ? getPathValue(root._defaultSettings, path) : undefined;
    }
    function isKnownSchemaPath(path) {
        if (!root._schemaTree) return true;
        var parts = path.split("."), node = root._schemaTree;
        for (var i = 0; i < parts.length; i++) {
            if (node === null || node === undefined) return false;
            if (Array.isArray(node)) return true;
            if (typeof node !== "object" || !Object.prototype.hasOwnProperty.call(node, parts[i])) return false;
            node = node[parts[i]];
        }
        return true;
    }
    function pendingPathOverlaps(section, path) {
        var pending = root._pendingPaths[section] || {};
        for (var local in pending) {
            if (local === "" || path === "" || local === path || path.indexOf(local + ".") === 0 || local.indexOf(path + ".") === 0) return true;
        }
        return false;
    }
    function effectiveDiskEnvironment() {
        var section = root._acceptedFiles.bindings;
        var choice = section && section.data ? section.data.environment : undefined;
        if (typeof choice !== "string" || choice === "")
            choice = root._legacyOverrides && root._legacyOverrides.bindings ? root._legacyOverrides.bindings.environment : undefined;
        return typeof choice === "string" && choice !== "" ? choice : "none";
    }
    function notifyEffectiveChanges() {
        if (!root.isLoaded) return;
        if (root._captureDepth || root._notifyingEffective) {
            root._effectivePending = true;
            return;
        }
        root._effectivePending = false;
        var changes = [];
        diffLeaves(root._runtimeSnapshot || current, current, "", changes);
        root._runtimeSnapshot = detached(current);
        var sections = [];
        for (var i = 0; i < changes.length; i++) {
            var section = changes[i].path.split(".")[0];
            if (sections.indexOf(section) === -1) sections.push(section);
        }
        root._notifyingEffective = true;
        effect("effective", {sections: sections});
    }
    function queueObservedNotification(kind, value) {
        root._observedNotifications.push({kind: kind, value: value});
        if (!root._captureDepth) flushObservedNotifications();
    }
    function notifyObservedAcceptance(acceptance) {
        if (acceptance && acceptance.environment !== null) queueObservedNotification("environment", acceptance.environment);
    }
    function flushObservedNotifications() {
        if (root._captureDepth || root._notifyingObserved) return;
        root._notifyingObserved = true;
        effect("observed", {});
    }
    function mergePendingChanges() {
        if (!root.isLoaded || !root._snapshot) return [];
        var changes = [];
        diffLeaves(root._snapshot, current, "", changes);
        if (!changes.length) {
            notifyEffectiveChanges();
            return [];
        }
        var operation = ++root._captureSerial, touched = [];
        for (var i = 0; i < changes.length; i++) {
            var c = changes[i], dot = c.path.indexOf(".");
            var section = dot === -1 ? c.path : c.path.substring(0, dot);
            var rel = dot === -1 ? "" : c.path.substring(dot + 1);
            if (section === "settingsVersion") continue;
            if (!root._pendingPaths[section]) root._pendingPaths[section] = {};
            root._pendingPaths[section][rel] = operation;
            if (root._overrides[section] === undefined) root._overrides[section] = {};
            if (c.deleted) {
                if (rel !== "") deepDelete(root._overrides[section], rel);
            } else if (rel === "") root._overrides[section] = detached(c.value);
            else deepSet(root._overrides[section], rel, detached(c.value));
            if (touched.indexOf(section) === -1) touched.push(section);
        }
        root._snapshot = detached(current);
        notifyEffectiveChanges();
        return touched;
    }
    function rememberInitialFile(section, raw, exists, data) {
        root._acceptedFiles[section] = {exists: exists, raw: raw,
            sha256: exists ? Checksum.sha256(raw) : "", identity: "", data: detached(data), valid: true};
        root._foreignEpochs[section] = 0;
    }
    function isCurrentConfirmedOwn(section, state) {
        var own = root._confirmedOwn[section];
        if (!own || !state || !own.identity || own.identity !== state.identity || own.exists !== state.exists || own.sha256 !== state.sha256) return false;
        if (own.identity !== "missing") return true;
        var accepted = root._acceptedFiles[section];
        return !state.exists && accepted && !accepted.exists && accepted.identity === "missing";
    }
    function acceptObservedFile(section, raw, exists, data, observedState, readContext) {
        var state = observedState ? detached(observedState) : {
            exists: exists, sha256: exists ? Checksum.sha256(raw) : "", raw: raw,
            data: detached(data), identity: "", valid: true};
        if (root._activePersist && root._activePersist.section === section && root._activePersist.stage === "promote" && (!readContext || readContext.writer === root._activePersist)) {
            root._activePersist.observations.push(state);
            return false;
        }
        var prior = root._acceptedFiles[section], own = root._confirmedOwn[section];
        var isOwn = isCurrentConfirmedOwn(section, state);
        var identityChanged = prior && prior.identity && state.identity && prior.identity !== state.identity;
        var changed = !prior || prior.exists !== state.exists || prior.sha256 !== state.sha256 || identityChanged;
        if (own && !isOwn && changed) {
            delete root._confirmedOwn[section];
            delete root._confirmedOriginEpochs[section];
        }
        if (!prior || prior.exists !== state.exists || prior.sha256 !== state.sha256 || prior.identity !== state.identity) {
            root._acceptGenerations[section] = (root._acceptGenerations[section] || 0) + 1;
            if (!readContext) root._nonReadAcceptGenerations[section] = (root._nonReadAcceptGenerations[section] || 0) + 1;
        }
        root._acceptedFiles[section] = state;
        if (isOwn || !changed) return false;
        root._foreignEpochs[section] = (root._foreignEpochs[section] || 0) + 1;
        if (section === "legacy") root._legacyOverrides = state.data;
        var environment = effectiveDiskEnvironment();
        var legacyBindingsChanged = section === "legacy" && JSON.stringify(prior && prior.data ? prior.data.bindings : null) !== JSON.stringify(state.data.bindings || null);
        var requested = null;
        if (root._bindingsManaged && (section === "bindings" || legacyBindingsChanged || environment !== root._acceptedBindingChoice)) {
            root._acceptedBindingChoice = environment;
            requested = environment;
        }
        return {environment: requested};
    }
    function resolveAcceptedLeaf(section, path) {
        var accepted = root._acceptedFiles[section];
        var value = getPathValue(accepted ? accepted.data : {}, path);
        if (value !== undefined) return value;
        var legacy = getPathValue(root._legacyOverrides || {}, section + "." + path);
        return legacy !== undefined ? legacy : getDefaultValue(section + "." + path);
    }

    // An application is a scope, not a bulk QObject patch. The façade asks for
    // each leaf at its actual assignment boundary, including recursive leaves.
    function beginObservation(token) {
        var app = applications[token];
        if (!app || app.begun) return [];
        app.begun = true;
        root._captureDepth++;
        var section = app.section, state = app.state;
        var previous = section === "legacy" ? root._legacyOverrides || {} :
            (root._acceptedFiles[section] ? root._acceptedFiles[section].data : root._overrides[section] || {});
        mergePendingChanges();
        app.acceptance = acceptObservedFile(section, state.raw, state.exists, state.data, state, app.observation);
        var changes = [];
        if (app.acceptance) diffExternalLeaves(previous, state.data, "", changes);
        app.changes = changes;
        app.previousEnvironment = current.bindings.environment;
        if (changes.length && section !== "legacy" && !root._persistDirtySections[section]) {
            root._overrides[section] = detached(state.data);
            var local = root._pendingPaths[section] || {};
            for (var path in local) {
                var value = getPathValue(current[section], path);
                if (value === undefined) deepDelete(root._overrides[section], path);
                else deepSet(root._overrides[section], path, detached(value));
            }
        }
        return changes.map(function (change) { return section === "legacy" ? change.path : section + "." + change.path; });
    }
    function observationLeaf(token, path) {
        var app = applications[token];
        if (!app || !app.begun) return;
        var dot = path.indexOf("."), section = dot === -1 ? path : path.substring(0, dot);
        var relative = dot === -1 ? "" : path.substring(dot + 1);
        mergePendingChanges();
        if ((section === "bindings" && root._bindingsManaged) || section === "settingsVersion" || (app.section === "legacy" && relative === "") || pendingPathOverlaps(section, relative)) return;
        var value = resolveAcceptedLeaf(section, relative);
        if (value !== undefined) effect("applyValue", {path: path, value: value});
    }
    function prepareLeaf(path, value) {
        if (!isKnownSchemaPath(path)) {
            log("w", "Ignoring unknown setting: " + path);
            return null;
        }
        var existing = getPathValue(current, path);
        if (value !== null && typeof value === "object" && !Array.isArray(value) && existing !== null && existing !== undefined && typeof existing === "object") {
            return {children: Object.keys(value).map(function (key) { return {path: path + "." + key, value: value[key]}; })};
        }
        mergePendingChanges();
        var dot = path.indexOf("."), section = path.substring(0, dot), relative = path.substring(dot + 1);
        if (pendingPathOverlaps(section, relative)) return null;
        var token = ++operationSerial;
        assignments[token] = {path: path, before: getPathValue(root._snapshot, path)};
        deepSet(root._snapshot, path, detached(value));
        return {token: token, value: detached(value)};
    }
    function endObservation(token) {
        var app = applications[token];
        if (!app || !app.begun) return;
        delete applications[token];
        if (app.acceptance) {
            notifyObservedAcceptance(app.acceptance);
            if (app.changes.length) {
                if (current.bindings.environment !== app.previousEnvironment) queueObservedNotification("changed", "bindings.environment");
                queueObservedNotification("reload", "");
                notifyEffectiveChanges();
            }
        }
        mergePendingChanges();
        root._captureDepth--;
        if (!root._captureDepth) {
            notifyEffectiveChanges();
            flushObservedNotifications();
        }
        deliverRead(app.delivery);
    }

    function capturePersist(section, provenance, origin) {
        var tree = root._overrides[section] || {};
        var accepted = origin ? origin.base : root._acceptedFiles[section] || {exists: false, sha256: "", identity: "", data: {}};
        var intent = {section: section, path: config.overridesDir + section + ".json",
            json: Object.keys(tree).length === 0 ? null : JSON.stringify(tree, null, 2) + "\n",
            base: detached(accepted), foreignEpoch: origin ? origin.foreignEpoch : root._foreignEpochs[section] || 0,
            captureId: ++root._captureSerial, coveredPaths: detached(root._pendingPaths[section] || {}), provenance: provenance || "ordinary"};
        captures[intent.captureId] = intent;
        return intent;
    }
    function captureOrdinarySection(section) {
        var intents = root._ordinaryIntents[section] || [], latest = intents.length ? intents[intents.length - 1] : null;
        var tree = root._overrides[section] || {};
        var json = Object.keys(tree).length === 0 ? null : JSON.stringify(tree, null, 2) + "\n";
        var paths = root._pendingPaths[section] || {};
        if (!latest || latest.json !== json || JSON.stringify(latest.coveredPaths) !== JSON.stringify(paths)) {
            latest = capturePersist(section, "ordinary", intents.length ? intents[0] : null);
            intents.push(latest);
            root._ordinaryIntents[section] = intents;
        }
        return intents;
    }
    function enqueuePersist(intent, callbackToken, fullSave, deferStart) {
        var revision = ++root._persistSerial;
        var job = {section: intent.section, path: intent.path, json: intent.json,
            base: detached(intent.base), foreignEpoch: intent.foreignEpoch, revision: revision,
            intent: intent, stage: "waiting", observations: [], retry: intent.failed === true};
        root._persistDirtySections[job.section] = true;
        root._persistRevisions[job.section] = revision;
        root._persistQueue.push(job);
        if (callbackToken) root._persistWaiters.push({covered: [revision], callbackToken: callbackToken, full: fullSave === true, held: false});
        // Pumping is a fresh decision after the effect adapter finishes delivery.
        return revision;
    }
    function persistSections(sections, callbackToken, managed, fullSave, automatic) {
        var covered = [];
        if (root._activePersist) covered.push(root._activePersist.revision);
        for (var qi = 0; qi < root._persistQueue.length; qi++) covered.push(root._persistQueue[qi].revision);
        var held = false;
        for (var i = 0; i < sections.length; i++) {
            var section = sections[i];
            if (section === "bindings" && root._bindingsManaged && !managed) { held = true; continue; }
            var intents = captureOrdinarySection(section), blockedAutomatic = false;
            for (var ii = 0; ii < intents.length; ii++) {
                var intent = intents[ii];
                if (intent.lastRevision && !root._persistResults[intent.lastRevision]) {
                    if (covered.indexOf(intent.lastRevision) === -1) covered.push(intent.lastRevision);
                    continue;
                }
                if (automatic && (intent.failed || blockedAutomatic)) {
                    blockedAutomatic = true;
                    if (intent.lastRevision && covered.indexOf(intent.lastRevision) === -1) covered.push(intent.lastRevision);
                    continue;
                }
                intent.lastRevision = enqueuePersist(intent, null, fullSave, true);
                covered.push(intent.lastRevision);
            }
        }
        root._persistWaiters.push({covered: covered, callbackToken: callbackToken, full: fullSave === true, held: held});
        checkPersistWaiters();
    }
    function save(callbackToken, automatic) {
        var touched = mergePendingChanges();
        for (var pendingSection in root._pendingPaths) {
            if (Object.keys(root._pendingPaths[pendingSection]).length && touched.indexOf(pendingSection) === -1) touched.push(pendingSection);
        }
        for (var section in root._persistDirtySections) {
            if (!(section === "bindings" && root._bindingsManaged) && touched.indexOf(section) === -1 && !root._persistRunning && !root._persistQueue.length) touched.push(section);
        }
        persistSections(touched, callbackToken, false, true, automatic === true);
    }
    function bindingBegin(identity) {
        var key = identity || "bindings-" + (++root._persistSerial);
        root._captureDepth++;
        if (!root._bindingIntents[key]) mergePendingChanges();
        return {identity: key, captured: !!root._bindingIntents[key]};
    }
    function bindingSubmit(key, environment, callbackToken) {
        var intent = root._bindingIntents[key];
        if (!intent) {
            notifyEffectiveChanges();
            if (!root._overrides.bindings) root._overrides.bindings = {};
            root._overrides.bindings.environment = environment;
            root._snapshot.bindings = detached(current.bindings);
            if (!root._pendingPaths.bindings) root._pendingPaths.bindings = {};
            root._pendingPaths.bindings.environment = ++root._captureSerial;
            intent = capturePersist("bindings", "bindings:" + key);
            root._bindingIntents[key] = intent;
        }
        enqueuePersist(intent, callbackToken, false, true);
    }
    function setupSubmit(requestId, callbackToken) {
        var bundle = root._setupBundles[requestId];
        if (!bundle) {
            var touched = mergePendingChanges();
            bundle = {requestId: requestId, intents: [], coveredRevisions: []};
            var sections = ["general", "bar", "wallpaper", "colorSchemes", "dock"];
            for (var si = 0; si < sections.length; si++) {
                var section = sections[si];
                if (touched.indexOf(section) === -1 && !(root._ordinaryIntents[section] || []).length && !Object.keys(root._pendingPaths[section] || {}).length) continue;
                var captured = captureOrdinarySection(section);
                for (var ci = 0; ci < captured.length; ci++) bundle.intents.push(captured[ci]);
            }
            root._setupBundles[requestId] = bundle;
        }
        var covered = [], replaySections = {}, previousRevisions = {};
        for (var bi = 0; bi < bundle.intents.length; bi++) {
            var intent = bundle.intents[bi];
            var revision = bundle.coveredRevisions[bi] || intent.lastRevision;
            var result = revision ? root._persistResults[revision] : null;
            if (!revision || (result && !result.success) || replaySections[intent.section] || revision <= (previousRevisions[intent.section] || 0)) {
                revision = enqueuePersist(intent, null, false, true);
                intent.lastRevision = revision;
                replaySections[intent.section] = true;
            }
            previousRevisions[intent.section] = revision;
            covered.push(revision);
        }
        bundle.coveredRevisions = covered.slice();
        root._persistWaiters.push({covered: covered, callbackToken: callbackToken, full: false, held: false});
        checkPersistWaiters();
    }

    function runSectionIo(mode, section, temporary, input, complete) {
        var token = ++operationSerial;
        var owner = root._activePersist && root._activePersist.section === section ? root._activePersist.revision : 0;
        operations[token] = {mode: mode, section: section, owner: owner, complete: complete};
        effect("io", {token: token, owner: owner, mode: mode, section: section, temporary: temporary, input: input});
    }
    function refreshAccepted(section, complete, job, settlement, callbackToken) {
        if (!root._readWaiters[section]) root._readWaiters[section] = [];
        root._readWaiters[section].push({callback: complete, callbackToken: callbackToken || null,
            job: job || null, settlement: settlement === true});
        effect("reload", {section: section});
    }
    function finishObservedRead(section) {
        var callbacks = root._readWaiters[section] || [];
        root._readWaiters[section] = [];
        if (!root.isLoaded && !callbacks.length) return;
        var writer = root._activePersist && root._activePersist.section === section ? root._activePersist : null;
        var observation = {serial: (root._readSerials[section] || 0) + 1,
            generation: root._acceptGenerations[section] || 0,
            authority: root._nonReadAcceptGenerations[section] || 0,
            publication: root._publicationGenerations[section] || 0,
            prior: root._acceptedFiles[section] ? detached(root._acceptedFiles[section]) : null,
            writer: writer, writerStage: writer ? writer.stage : "",
            writerPublication: writer && writer.publicationState ? detached(writer.publicationState) : null};
        root._readSerials[section] = observation.serial;
        root._readsInFlight[section] = (root._readsInFlight[section] || 0) + 1;
        function delivered(success, state, error, stale) {
            var token = ++operationSerial;
            readDeliveries[token] = {section: section, callbacks: callbacks, index: 0,
                success: success, state: state, error: error, stale: stale};
            effect("readNext", {token: token});
            return token;
        }
        runSectionIo("inspect", section, null, undefined, function (success, payload, error) {
            var state = success ? payload.state : null;
            var stale = observation.serial < (root._acceptedReadSerials[section] || 0) || observation.authority !== (root._nonReadAcceptGenerations[section] || 0) || observation.publication !== (root._publicationGenerations[section] || 0);
            if (state) {
                if (writer && !writer.finished && root._activePersist === writer && (observation.writerStage === "promote" || observation.writerStage === "readback" || writer.settling)) {
                    writer.observations.push(detached(state));
                    if (observation.writerStage === "readback" && !sameFileVersion(state, observation.writerPublication)) captureJobConflict(writer, state, true);
                }
                if (writer && !writer.finished && root._activePersist === writer && writer.stage === "promote") {
                    // Captured dispatch owner, not the execution-time active job.
                } else if (stale) {
                    var known = sameFileVersion(observation.prior, state) || sameFileVersion(root._acceptedFiles[section], state);
                    if (!known) {
                        runSectionIo("retain", section, config.cacheDir + "settings-conflicts", state, function (retained, ignored, retentionError) {
                            if (!retained) effect("saveFailed", {error: retentionError || "Settings observation retention failed"});
                            delivered(false, state, retentionError || "Stale Settings observation", retained);
                        });
                        return;
                    }
                } else {
                    root._acceptedReadSerials[section] = observation.serial;
                    if (state.valid) {
                        var token = ++operationSerial;
                        applications[token] = {section: section, state: state, observation: observation,
                            delivery: {section: section, callbacks: callbacks, index: 0,
                                success: success, state: state, error: error, stale: false}};
                        effect("observation", {token: token});
                        return;
                    }
                    notifyObservedAcceptance(acceptObservedFile(section, state.raw, state.exists, state.data, state, observation));
                }
            }
            delivered(stale ? false : success, state, stale ? "Stale Settings observation" : error, stale);
        });
    }
    function deliverRead(delivery) {
        var token = ++operationSerial;
        readDeliveries[token] = delivery;
        effect("readNext", {token: token});
    }
    function readNext(token, callbackError) {
        var delivery = readDeliveries[token];
        if (!delivery) return;
        if (delivery.delivering) {
            var old = delivery.delivering;
            delivery.delivering = null;
            if (callbackError) {
                log("e", "Settings read callback failed", filePathFor(delivery.section));
                if (old.job && !old.job.finished && root._activePersist === old.job) finishPersistJob(old.job, false, "Settings read callback failed");
            }
        }
        while (delivery.index < delivery.callbacks.length) {
            var waiter = delivery.callbacks[delivery.index++], owner = waiter.job;
            if (owner && (owner.finished || (owner.settling && !waiter.settlement) || root._activePersist !== owner)) continue;
            if (delivery.stale && owner) {
                refreshAccepted(delivery.section, waiter.callback, owner, waiter.settlement, waiter.callbackToken);
                continue;
            }
            if (waiter.callbackToken) {
                delivery.delivering = waiter;
                effect("readCallback", {token: token, callbackToken: waiter.callbackToken,
                    success: delivery.success, state: delivery.state, error: delivery.error});
            } else {
                try { waiter.callback(delivery.success, delivery.state, delivery.error); }
                catch (exception) {
                    log("e", "Settings read callback failed", filePathFor(delivery.section));
                    if (owner && !owner.finished && root._activePersist === owner) finishPersistJob(owner, false, "Settings read callback failed");
                }
                effect("readNext", {token: token});
            }
            return;
        }
        delete readDeliveries[token];
        root._readsInFlight[delivery.section]--;
        finishObservationWaiters(delivery.section);
    }
    function finishObservationWaiters(section) {
        if ((root._readsInFlight[section] || 0) !== 0 || (root._readWaiters[section] || []).length) return;
        var waiters = root._observationWaiters[section] || [];
        root._observationWaiters[section] = [];
        for (var i = 0; i < waiters.length; i++) {
            var waiter = waiters[i];
            if (!waiter.job.finished && root._activePersist === waiter.job) waiter.callback();
        }
    }
    function joinObservedReads(section, job, complete) {
        if (!root._observationWaiters[section]) root._observationWaiters[section] = [];
        root._observationWaiters[section].push({job: job, callback: complete});
        finishObservationWaiters(section);
    }
    function pump() {
        if (root._persistRunning || root._captureDepth || root._notifyingEffective || root._notifyingObserved || Object.keys(saveDeliveries).length) return;
        if (!root._persistQueue.length) { checkPersistWaiters(); return; }
        var job = root._persistQueue.shift();
        root._persistRunning = true;
        root._activePersist = job;
        job.conflicts = config.cacheDir + "settings-conflicts";
        retainIntentConflicts(job, function (success, error) {
            if (!success) { completePersistJob(job, false, error); return; }
            startPersistRead(job);
        });
    }
    function startPersistRead(job) {
        job.stage = "read";
        refreshAccepted(job.section, function (success, state, error) {
            if (!success) { finishPersistJob(job, false, error); return; }
            var isOwn = isCurrentConfirmedOwn(job.section, state);
            var compatiblePublication = job.intent.publicationUncertain && (job.json === null ? !state.exists : state.exists && state.sha256 === Checksum.sha256(job.json));
            var externalResolution = !isOwn && !compatiblePublication && job.retry &&
                ((state.exists === job.intent.base.exists && state.sha256 === job.intent.base.sha256) || (job.json !== null && state.exists && state.sha256 === Checksum.sha256(job.json)));
            if (job.intent.unresolvedConflict) {
                if (!externalResolution) {
                    captureJobConflict(job, state);
                    finishPersistJob(job, false, "Unresolved Settings conflict at " + job.path);
                    return;
                }
                job.intent.unresolvedConflict = false;
                job.intent.publicationUncertain = false;
                var related = root._ordinaryIntents[job.section] || [];
                for (var ri = 0; ri < related.length; ri++) {
                    if (related[ri].foreignEpoch === job.intent.foreignEpoch && related[ri].base.exists === job.intent.base.exists && related[ri].base.sha256 === job.intent.base.sha256) related[ri].unresolvedConflict = false;
                }
            }
            if ((root._foreignEpochs[job.section] || 0) !== job.foreignEpoch) {
                var sameOriginOwn = isCurrentConfirmedOwn(job.section, state) && root._confirmedOriginEpochs[job.section] === job.intent.foreignEpoch;
                var originalRestored = state.exists === job.intent.base.exists && state.sha256 === job.intent.base.sha256;
                var exactIntentPresent = job.json !== null && state.exists && state.sha256 === Checksum.sha256(job.json);
                if (sameOriginOwn || (job.retry && (originalRestored || exactIntentPresent))) {
                    job.foreignEpoch = root._foreignEpochs[job.section] || 0;
                    job.base = state;
                } else {
                    captureJobConflict(job, state);
                    finishPersistJob(job, false, "Settings conflict at " + job.path);
                    return;
                }
            }
            if (isCurrentConfirmedOwn(job.section, state)) job.base = state;
            else if (job.base.sha256 !== state.sha256 || job.base.exists !== state.exists) {
                captureJobConflict(job, state);
                finishPersistJob(job, false, "Settings conflict at " + job.path);
                return;
            } else job.base = state;
            job.temporary = job.path + ".tmp-" + config.session + "-" + job.revision;
            job.conflicts = config.cacheDir + "settings-conflicts";
            job.stage = "prepare";
            runSectionIo("prepare", job.section, job.temporary, {base: job.base, raw: job.json, conflicts: job.conflicts}, function (ok, prepared, failure) {
                if (!ok) {
                    captureHelperConflict(job, prepared);
                    finishPersistJob(job, false, failure || "Settings preparation failed");
                    return;
                }
                job.prepared = prepared;
                refreshAccepted(job.section, function (fresh, latest, readError) {
                    if (!fresh || (root._foreignEpochs[job.section] || 0) !== job.foreignEpoch || latest.identity !== prepared.base.identity) {
                        if (latest) captureJobConflict(job, latest);
                        finishPersistJob(job, false, readError || "Settings conflict at " + job.path);
                        return;
                    }
                    joinObservedReads(job.section, job, function () {
                        var joined = root._acceptedFiles[job.section];
                        if ((root._foreignEpochs[job.section] || 0) !== job.foreignEpoch || !sameFileVersion(joined, prepared.base) || job.intent.unresolvedConflict) {
                            captureJobConflict(job, joined, true);
                            finishPersistJob(job, false, "Settings pre-publication join conflict at " + job.path);
                            return;
                        }
                        job.stage = "promote";
                        root._publicationGenerations[job.section] = (root._publicationGenerations[job.section] || 0) + 1;
                        runSectionIo("promote", job.section, job.temporary, {
                            base: prepared.base, prepared_sha256: prepared.prepared_sha256, delete: prepared.delete, conflicts: job.conflicts
                        }, function (published, result, publicationError) {
                            if (!published) {
                                captureHelperConflict(job, result);
                                finishPersistJob(job, false, publicationError || "Settings publication failed");
                                return;
                            }
                            rememberJobPublication(job, result);
                            job.publicationState = detached(result.state);
                            joinObservedReads(job.section, job, function () {
                                for (var oi = 0; oi < job.observations.length; oi++) captureJobConflict(job, job.observations[oi]);
                                root._confirmedOwn[job.section] = result.state;
                                root._confirmedOriginEpochs[job.section] = job.intent.foreignEpoch;
                                root._acceptedFiles[job.section] = result.state;
                                root._acceptGenerations[job.section] = (root._acceptGenerations[job.section] || 0) + 1;
                                root._nonReadAcceptGenerations[job.section] = (root._nonReadAcceptGenerations[job.section] || 0) + 1;
                                root._acceptedBindingChoice = effectiveDiskEnvironment();
                                if (job.intent.unresolvedConflict) {
                                    finishPersistJob(job, false, "Observed foreign content during publication at " + job.path);
                                    return;
                                }
                                job.stage = "readback";
                                refreshAccepted(job.section, function (confirmed, observed, confirmationError) {
                                    joinObservedReads(job.section, job, function () {
                                        var joined = root._acceptedFiles[job.section];
                                        var matches = confirmed && sameFileVersion(observed, result.state) && sameFileVersion(joined, result.state) && isCurrentConfirmedOwn(job.section, joined) && !job.intent.unresolvedConflict;
                                        if (!matches && joined) captureJobConflict(job, joined, true);
                                        finishPersistJob(job, matches, confirmationError || "Settings readback conflict at " + job.path);
                                    });
                                }, job);
                            });
                        });
                    });
                }, job);
            });
        }, job);
    }
    function sameFileVersion(first, second) {
        return first && second && first.exists === second.exists && first.identity === second.identity && first.sha256 === second.sha256;
    }
    function conflictKey(state) {
        return String(state.exists) + ":" + state.sha256 + ":" + (state.identity || "");
    }
    function captureJobConflict(job, state, force) {
        if (!state) return;
        var ownResult = job.json === null ? !state.exists : state.exists && state.sha256 === Checksum.sha256(job.json);
        if (!force && (ownResult || (state.exists === job.base.exists && state.sha256 === job.base.sha256))) return;
        if (!job.intent.foreignObservations) job.intent.foreignObservations = [];
        var key = conflictKey(state);
        for (var i = 0; i < job.intent.foreignObservations.length; i++) {
            if (conflictKey(job.intent.foreignObservations[i]) === key) { job.intent.unresolvedConflict = true; return; }
        }
        job.intent.foreignObservations.push(detached(state));
        job.intent.unresolvedConflict = true;
    }
    function rememberJobPublication(job, payload) {
        if (!payload || !payload.publication || !payload.publication.attempted) return;
        if (!job.intent.publicationWitnesses) job.intent.publicationWitnesses = [];
        job.intent.publicationWitnesses.push(detached({revision: job.revision,
            publication: payload.publication, state: payload.state || null, inspected: payload.inspected || []}));
        if (!payload.ok || payload.publication.uncertain) {
            job.intent.publicationUncertain = true;
            job.intent.unresolvedConflict = true;
        }
        if (payload.publication.completed && payload.state && (job.json === null ? !payload.state.exists : payload.state.exists && payload.state.sha256 === Checksum.sha256(job.json))) job.publicationState = detached(payload.state);
    }
    function captureHelperConflict(job, payload) {
        if (!payload) return;
        rememberJobPublication(job, payload);
        captureJobConflict(job, payload.state, payload.conflict === true);
        if (payload.retained && payload.state) {
            if (!job.intent.retainedObservations) job.intent.retainedObservations = {};
            job.intent.retainedObservations[conflictKey(payload.state)] = payload.retained;
        }
    }
    function retainIntentConflicts(job, complete) {
        var observations = job.intent.foreignObservations || [];
        if (!job.intent.retainedObservations) job.intent.retainedObservations = {};
        var index = 0;
        function next() {
            while (index < observations.length && job.intent.retainedObservations[conflictKey(observations[index])]) index++;
            if (index === observations.length) { complete(true, ""); return; }
            var state = observations[index++];
            runSectionIo("retain", job.section, job.conflicts || config.cacheDir + "settings-conflicts", state, function (success, payload, error) {
                if (!success) { complete(false, error || "Settings conflict retention failed"); return; }
                job.intent.retainedObservations[conflictKey(state)] = payload.retained;
                next();
            });
        }
        next();
    }
    function finishPersistJob(job, success, error) {
        if (job.finished || job.settling) return;
        job.settling = true;
        var reconciled = 0, passes = 0;
        function reconcile() {
            while (reconciled < job.observations.length) {
                var state = job.observations[reconciled++];
                captureJobConflict(job, state, !sameFileVersion(state, job.base) && !sameFileVersion(state, job.publicationState));
            }
        }
        function settle() {
            joinObservedReads(job.section, job, function () {
                reconcile();
                var retainedCount = (job.intent.foreignObservations || []).length;
                retainIntentConflicts(job, function (retained, retentionError) {
                    if (!retained) {
                        joinObservedReads(job.section, job, function () {
                            reconcile();
                            completePersistJob(job, false, retentionError || "Settings conflict retention failed");
                        });
                        return;
                    }
                    refreshAccepted(job.section, function (fresh, state, readError) {
                        if (!fresh) { success = false; error = readError || error || "Settings settlement read failed"; }
                        joinObservedReads(job.section, job, function () {
                            reconcile();
                            if ((job.intent.foreignObservations || []).length > retainedCount) {
                                if (++passes < 8) { settle(); return; }
                                completePersistJob(job, false, "Settings conflict observations remain unstable at " + job.path);
                                return;
                            }
                            completePersistJob(job, success && !job.intent.unresolvedConflict, error || (job.intent.unresolvedConflict ? "Unresolved Settings conflict at " + job.path : ""));
                        });
                    }, job, true);
                });
            });
        }
        settle();
    }
    function completePersistJob(job, success, error) {
        if (job.finished) return;
        job.finished = true;
        job.intent.failed = !success;
        if (success && job.intent.provenance === "ordinary") {
            var retained = root._ordinaryIntents[job.section] || [];
            root._ordinaryIntents[job.section] = retained.filter(function (intent) { return intent !== job.intent; });
            if (!root._ordinaryIntents[job.section].length) delete root._ordinaryIntents[job.section];
        }
        root._persistResults[job.revision] = {success: success, error: success ? "" : error || "Settings persistence failed"};
        if (success) {
            var pending = root._pendingPaths[job.section] || {}, covered = job.intent.coveredPaths || {};
            for (var path in covered) { if (pending[path] === covered[path]) delete pending[path]; }
            if (!Object.keys(pending).length) delete root._pendingPaths[job.section];
        }
        if (success && root._persistRevisions[job.section] === job.revision && !(root._ordinaryIntents[job.section] && root._ordinaryIntents[job.section].length)) delete root._persistDirtySections[job.section];
        if (!success) log("e", error || "Settings persistence failed", job.path);
        root._activePersist = null;
        root._persistRunning = false;
        checkPersistWaiters();
    }
    function checkPersistWaiters() {
        var remaining = [], ready = [];
        for (var i = 0; i < root._persistWaiters.length; i++) {
            var waiter = root._persistWaiters[i], complete = true, error = "";
            for (var j = 0; j < waiter.covered.length; j++) {
                var result = root._persistResults[waiter.covered[j]];
                if (!result) complete = false;
                else if (!result.success && !error) error = result.error;
            }
            if (complete) {
                if (waiter.held || (waiter.full && root._bindingsUnresolved)) error = error || "Managed bindings work remains unresolved";
                ready.push({waiter: waiter, error: error});
            } else remaining.push(waiter);
        }
        root._persistWaiters = remaining;
        for (var ri = 0; ri < ready.length; ri++) {
            var finished = ready[ri], token = ++operationSerial;
            saveDeliveries[token] = {error: finished.error};
            effect("saveDelivery", {token: token, callbackToken: finished.waiter.callbackToken,
                success: !finished.error, error: finished.error});
        }
    }
    function captureOwned(id) {
        var intent = captures[id];
        if (!intent) return false;
        if (root._activePersist && root._activePersist.intent === intent) return true;
        if (root._persistQueue.some(function (job) { return job.intent === intent; })) return true;
        if ((root._ordinaryIntents[intent.section] || []).indexOf(intent) !== -1) return true;
        for (var key in root._bindingIntents) if (root._bindingIntents[key] === intent) return true;
        for (var bundle in root._setupBundles) if (root._setupBundles[bundle].intents.indexOf(intent) !== -1) return true;
        return false;
    }

    function transition(input) {
        if (effects !== null) throw new Error("Nested Settings model transition");
        var event = detached(input), value;
        effects = [];
        current = event.current;
        try {
            switch (event.type) {
            case "schema":
                root._schemaTree = detached(event.schema);
                root._sections = Object.keys(event.schema).filter(function (key) { return key !== "settingsVersion"; });
                break;
            case "initialFile":
                if (event.section === "legacy") root._legacyOverrides = detached(event.data);
                else root._overrides[event.section] = detached(event.data);
                rememberInitialFile(event.section, event.raw, event.exists, event.data);
                if (event.sawFile) root._sawAnyFile = true;
                break;
            case "loaded":
                root._snapshot = detached(current);
                root._runtimeSnapshot = detached(current);
                root._acceptedBindingChoice = effectiveDiskEnvironment();
                root.isLoaded = true;
                break;
            case "defaults": root._defaultSettings = event.value; break;
            case "managed": root._bindingsManaged = true; root._acceptedBindingChoice = effectiveDiskEnvironment(); break;
            case "unresolved": root._bindingsUnresolved = event.value; break;
            case "captureBegin": root._captureDepth++; break;
            case "captureEnd":
                root._captureDepth--;
                if (!root._captureDepth) { notifyEffectiveChanges(); flushObservedNotifications(); }
                break;
            case "effective": notifyEffectiveChanges(); break;
            case "effectiveDelivered":
                root._notifyingEffective = false;
                if (root._effectivePending) notifyEffectiveChanges();
                break;
            case "observedNext": value = root._observedNotifications.shift() || null; break;
            case "observedDelivered": root._notifyingObserved = false; break;
            case "merge": value = mergePendingChanges(); break;
            case "rebaseline": root._snapshot = detached(current); break;
            case "save": save(event.callbackToken, event.automatic); break;
            case "persist": persistSections(event.sections, event.callbackToken, event.managed, event.fullSave, event.automatic); break;
            case "bindingBegin": value = bindingBegin(event.identity); break;
            case "bindingSubmit": bindingSubmit(event.identity, event.environment, event.callbackToken); break;
            case "setupBegin": root._captureDepth++; value = !!root._setupBundles[event.identity]; break;
            case "setupSubmit": setupSubmit(event.identity, event.callbackToken); break;
            case "readRequest": refreshAccepted(event.section, null, null, event.settlement, event.callbackToken); break;
            case "readDispatch": finishObservedRead(event.section); break;
            case "ioCompleted":
                var operation = operations[event.token];
                if (!operation || event.owner !== operation.owner) break;
                delete operations[event.token];
                operation.complete(event.success, event.payload, event.error);
                break;
            case "readNext": readNext(event.token, event.callbackError); break;
            case "observationBegin": value = beginObservation(event.token); break;
            case "observationLeaf": observationLeaf(event.token, event.path); break;
            case "observationEnd": endObservation(event.token); break;
            case "leafPrepare": value = prepareLeaf(event.path, event.value); break;
            case "leafAssigned":
                var assignment = assignments[event.token];
                if (!assignment) break;
                delete assignments[event.token];
                if (!event.applied) {
                    if (assignment.before === undefined) deepDelete(root._snapshot, assignment.path);
                    else deepSet(root._snapshot, assignment.path, assignment.before);
                }
                break;
            case "saveDeliveryBegin":
                var saveDelivery = saveDeliveries[event.token];
                value = saveDelivery ? saveDelivery.error ? "failed" : !root._bindingsUnresolved ? "saved" : "" : "";
                break;
            case "saveDelivered": delete saveDeliveries[event.token]; break;
            case "resetBegin":
                value = event.touched.slice();
                var dot = event.path.indexOf("."), section = dot === -1 ? event.path : event.path.substring(0, dot);
                var rel = dot === -1 ? "" : event.path.substring(dot + 1);
                if (event.sectionReset || rel === "") root._overrides[section] = {};
                else if (root._overrides[section] !== undefined) deepDelete(root._overrides[section], rel);
                if (value.indexOf(section) === -1) value.push(section);
                break;
            case "resetEnd": root._snapshot = detached(current); persistSections(event.sections); break;
            case "pump": pump(); break;
            default: throw new Error("Unknown Settings transition: " + event.type);
            }
            return {returnValue: detached(value), orderedEffects: detached(effects)};
        } finally { effects = null; current = null; }
    }
    function query(name, args) {
        args = detached(args || {});
        var value;
        switch (name) {
        case "default": value = getDefaultValue(args.path); break;
        case "known": value = isKnownSchemaPath(args.path); break;
        case "sections": value = root._sections; break;
        case "sawFile": value = root._sawAnyFile; break;
        case "loaded": value = root.isLoaded; break;
        case "hasSnapshot": value = !!root._snapshot; break;
        case "managed": value = root._bindingsManaged; break;
        case "pumpReady": value = !root._persistRunning && !root._captureDepth && !root._notifyingEffective && !root._notifyingObserved && !Object.keys(saveDeliveries).length && root._persistQueue.length > 0; break;
        case "environment": value = effectiveDiskEnvironment(); break;
        case "capture": value = captures[args.id] || null; break;
        case "captureOwned": value = captureOwned(args.id); break;
        case "path": value = filePathFor(args.section); break;
        case "diff": value = []; diffLeaves(args.before, args.after, args.prefix || "", value); break;
        default: throw new Error("Unknown Settings query: " + name);
        }
        return detached(value);
    }
    function inspect() {
        var shared = {};
        for (var section in root._acceptedFiles) shared[section] = root._acceptedFiles[section].data === root._overrides[section];
        return detached({state: root, ownership: {acceptedSharesWorking: shared,
            captureOwned: Object.keys(captures).filter(function (id) { return captureOwned(id); })}});
    }
    return {transition: transition, query: query, inspect: inspect};
}

function detached(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}
function getPathValue(obj, path) {
    var parts = path.split("."), current = obj;
    for (var i = 0; i < parts.length; i++) {
        if (current === undefined || current === null) return undefined;
        current = current[parts[i]];
    }
    return current;
}
function deepSet(obj, path, value) {
    var parts = path.split("."), current = obj;
    for (var i = 0; i < parts.length - 1; i++) {
        if (current[parts[i]] === undefined || current[parts[i]] === null || typeof current[parts[i]] !== "object") current[parts[i]] = {};
        current = current[parts[i]];
    }
    current[parts[parts.length - 1]] = value;
}
function deepDelete(obj, path) {
    var parts = path.split("."), stack = [], current = obj;
    for (var i = 0; i < parts.length - 1; i++) {
        if (current[parts[i]] === undefined || current[parts[i]] === null || typeof current[parts[i]] !== "object") return;
        stack.push({obj: current, key: parts[i]});
        current = current[parts[i]];
    }
    delete current[parts[parts.length - 1]];
    for (var j = stack.length - 1; j >= 0; j--) {
        var entry = stack[j];
        if (Object.keys(entry.obj[entry.key]).length === 0) delete entry.obj[entry.key];
        else break;
    }
}
function diffLeaves(before, after, prefix, out) {
    if (before === after) return;
    var beforeIsObj = before !== null && typeof before === "object" && !Array.isArray(before);
    var afterIsObj = after !== null && typeof after === "object" && !Array.isArray(after);
    if (!beforeIsObj || !afterIsObj) {
        if (JSON.stringify(before) !== JSON.stringify(after)) out.push({path: prefix, value: after, deleted: after === undefined});
        return;
    }
    var key;
    for (key in before) {
        var p = prefix ? prefix + "." + key : key;
        if (!(key in after)) out.push({path: p, value: undefined, deleted: true});
        else diffLeaves(before[key], after[key], p, out);
    }
    for (key in after) {
        if (!(key in before)) out.push({path: prefix ? prefix + "." + key : key, value: after[key], deleted: false});
    }
}
function diffExternalLeaves(before, after, prefix, out) {
    if (Array.isArray(before) || Array.isArray(after)) { diffLeaves(before, after, prefix, out); return; }
    var beforeObject = before !== null && typeof before === "object" && !Array.isArray(before);
    var afterObject = after !== null && typeof after === "object" && !Array.isArray(after);
    if (beforeObject || afterObject) {
        var keys = Object.keys(beforeObject ? before : {}), added = Object.keys(afterObject ? after : {});
        for (var ai = 0; ai < added.length; ai++) if (keys.indexOf(added[ai]) === -1) keys.push(added[ai]);
        for (var ki = 0; ki < keys.length; ki++) {
            var key = keys[ki];
            diffExternalLeaves(beforeObject ? before[key] : undefined, afterObject ? after[key] : undefined, prefix ? prefix + "." + key : key, out);
        }
        return;
    }
    diffLeaves(before, after, prefix, out);
}
