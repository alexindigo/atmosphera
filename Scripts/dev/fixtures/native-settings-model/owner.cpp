#include "owner.h"
#include "access.h"
#include "configworker_p.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QJSEngine>
#include <QQmlEngine>
#include <chrono>
#include <utility>
#include <QDirIterator>
#include <sys/stat.h>

using namespace configqml;
using Probe = ConfigStoreTestAccess;
using D = ConfigDescriptor;
using T = D::Type;
struct NativeModelOwner::Packets { QList<ConfigWorkerPacket> values; };
NativeModelOwner::NativeModelOwner(QObject *parent) : QObject(parent) {}

static QVariantMap resultMap(const ConfigResult &result) {
    QVariantList evidence, coverage, publications;
    for (const auto &item : result.evidence) evidence.append(item.directory);
    for (const auto &item : result.coverage)
        coverage.append(QVariantMap{{"path", item.path}, {"inputThrough", QString::number(item.inputThrough)},
                                    {"intentRevision", QString::number(item.intentRevision)}});
    for (const auto &item : result.publications)
        publications.append(QVariantMap{{"sourceId", item.sourceId}, {"success", item.success}, {"state", item.state}});
    return {{"status", result.status}, {"requestId", QString::number(result.requestId)}, {"storeId", result.storeId},
            {"operation", result.operation}, {"inputPrefix", QString::number(result.inputPrefix)},
            {"publicationState", result.publicationState}, {"error", result.error.code}, {"evidence", evidence},
            {"coverage", coverage}, {"publications", publications}, {"groupToken", result.groupToken},
            {"attemptId", result.attemptId}, {"unresolvedGroups", result.unresolvedGroups}};
}
ModelLeaf::ModelLeaf(ConfigStore *store, const ConfigPath &prefix, QObject *parent)
    : ConfigFacade(store, prefix, parent) {
    connect(this, &ConfigFacade::settingChanged, this, [this] { emit changed(); });
}
NativeModelOwner::~NativeModelOwner() {
    std::lock_guard<std::mutex> lock(m_control->mutex);
    m_control->stopping = true;
    m_control->released.notify_all();
}
void NativeModelOwner::componentComplete() {
    if (!QDir::isAbsolutePath(m_directory) || !QDir().mkpath(m_directory)) qFatal("test workspace required");
    auto record = D(T::Record); record.open = true;
    record.fields["values"] = D::list(D::leaf(T::String, QString()), {});
    ConfigStoreOptions options;
    options.autoSave = false;
    options.schema = ConfigSchema(D::group({
        {"ui", D::group({{"scale", D::leaf(T::Real, m_invalidSchema ? QVariant(QString("invalid")) : QVariant(m_default))}})},
        {"general", D::group({{"scaleRatio", D::leaf(T::Real, 1.0)}})},
        {"bindings", D::group({{"environment", D::leaf(T::String, QString("none"))}})},
        {"bar", D::group({{"records", D::list(record, {QVariantMap{{"values", QVariantList{QString("initial")}}}})}})}}));
    ConfigLayer layer; layer.id = "user"; layer.kind = ConfigLayerKind::File;
    layer.policy = ConfigAdmissionPolicy::FieldFallback; layer.writable = true;
    for (const auto &name : {QString("ui"), QString("general"), QString("bar"), QString("bindings")}) {
        ConfigSource source; source.id = name; source.prefix = {name}; layer.sources.append(source);
        ConfigJsonFile file; file.layerId = "user"; file.sourceId = name; file.path = m_directory + '/' + name + ".json";
        file.watchMode = ConfigWatchMode::StartupSnapshot; file.conflictPolicy = ConfigConflictPolicy::StrictPendingRebase;
        options.jsonFiles.append(file);
    }
    options.layers = {layer}; options.evidenceDirectory = m_directory + "/evidence";
    const auto control = m_control; QPointer<NativeModelOwner> guard(this);
    options.fileFault = [control, guard](const QString &phase, const QString &file) {
        std::unique_lock<std::mutex> lock(control->mutex);
        if (control->phase != phase || (!control->source.isEmpty() && QFileInfo(file).baseName() != control->source)) return QString();
        control->phase.clear(); control->observed = phase; control->waiting = true;
        if (guard) QMetaObject::invokeMethod(guard, [guard] { if (guard) emit guard->changed(); }, Qt::QueuedConnection);
        if (!control->released.wait_for(lock, std::chrono::seconds(12), [&] { return control->proceed || control->stopping; }))
            return QString("test-control-deadline");
        control->waiting = false; control->proceed = false;
        return std::exchange(control->error, {});
    };
    m_store = new ConfigStore(options, this);
    m_ui = new ModelLeaf(m_store, {"ui"}, this); m_general = new ModelLeaf(m_store, {"general"}, this);
    m_bar = new ModelLeaf(m_store, {"bar"}, this); m_bindings = new ModelLeaf(m_store, {"bindings"}, this);
    m_packets = std::make_unique<Packets>();
    connect(Probe::worker(m_store), &ConfigWorker::packetReady, this, [this](const ConfigWorkerPacket &packet) {
        m_packets->values.append(packet); emit changed();
    });
    connect(m_store, &ConfigStore::statusChanged, this, [this] { emit changed(); });
    connect(m_store, &ConfigStore::completed, this, [this](const ConfigResult &result) { emit completed(resultMap(result)); });
    connect(m_store, &ConfigStore::valuesChanged, this, [this](const QList<ConfigPath> &paths) {
        QVariantList result; for (const auto &path : paths) result.append(QVariant(path)); emit valuesChanged(result);
    });
    emit changed();
}
bool NativeModelOwner::ready() const { return m_store && m_store->status() == ConfigStore::Status::Ready; }
bool NativeModelOwner::held() const { std::lock_guard<std::mutex> lock(m_control->mutex); return m_control->waiting; }
QString NativeModelOwner::heldPhase() const { std::lock_guard<std::mutex> lock(m_control->mutex); return m_control->observed; }
int NativeModelOwner::callbackCount() const { return m_store ? Probe::callbacks(m_store) : 0; }
QVariant NativeModelOwner::value(const QStringList &path) const { return m_store->presentation(path); }
QVariant NativeModelOwner::defaultValue(const QStringList &path) const {
    const auto descriptor = m_store->schema().descriptor(path);
    return descriptor && descriptor->defaultValue ? *descriptor->defaultValue : QVariant();
}
QVariantMap NativeModelOwner::info(const QStringList &path) const {
    auto info = m_store->info(path);
    return {{"latestInput", QString::number(info.latestInput)}, {"workerCovered", QString::number(info.workerCovered)},
            {"intentRevision", QString::number(info.intentRevision)}, {"contentRevision", QString::number(info.contentRevision)},
            {"generation", QString::number(info.publicationGeneration)}};
}
QVariantMap NativeModelOwner::group(const QString &token) const {
    const auto group = m_store->groupInfo(token); QVariantList attempts;
    for (const auto &attempt : group.attempts) attempts.append(QVariantMap{{"id", attempt.attemptId}, {"status", attempt.status}});
    return {{"token", group.groupToken}, {"capturePrefix", QString::number(group.capturePrefix)}, {"state", group.state}, {"attempts", attempts}};
}
QVariantList NativeModelOwner::failures() const { QVariantList result; for (const auto &failure : m_store->failures()) result.append(resultMap(failure)); return result; }
QVariantList NativeModelOwner::inputs() const {
    QVariantList result; for (const auto &input : m_store->inputs()) result.append(QVariantMap{
        {"sequence", QString::number(input.sequence)}, {"path", input.path}, {"value", input.value}}); return result;
}
QString NativeModelOwner::identity(const QString &source) const {
    if (!QStringList{"ui", "general", "bar", "bindings"}.contains(source)) qFatal("test source refused");
    struct stat state;
    if (::stat(QFile::encodeName(m_directory + '/' + source + ".json").constData(), &state)) return "missing";
    return QString::number(state.st_ino) + ':' + QString::number(state.st_mtim.tv_sec) + ':' + QString::number(state.st_mtim.tv_nsec);
}
bool NativeModelOwner::evidenceContains(const QString &bytes) const {
    QDirIterator files(m_directory + "/evidence", QDir::Files, QDirIterator::Subdirectories); int count = 0;
    while (files.hasNext() && ++count < 1000) { QFile file(files.next()); if (file.size() < 65536 && file.open(QIODevice::ReadOnly) && file.readAll() == bytes.toUtf8()) return true; }
    return false;
}
ConfigStore::Callback NativeModelOwner::callback(const QJSValue &function) {
    QPointer<NativeModelOwner> guard(this);
    return [guard, function](const ConfigResult &result) mutable {
        if (!guard || !function.isCallable()) return;
        const auto returned = function.call({qmlEngine(guard)->toScriptValue(resultMap(result))});
        if (returned.isError()) qWarning("controlled test observer threw");
    };
}
QString NativeModelOwner::save(const QJSValue &cb) { return QString::number(m_store->save(this, callback(cb))); }
QString NativeModelOwner::reload(const QJSValue &cb) { return QString::number(m_store->reload(this, callback(cb))); }
QString NativeModelOwner::close(const QJSValue &cb) { return QString::number(m_store->close(this, callback(cb))); }
QString NativeModelOwner::retain(const QString &key, const QVariantList &paths, const QVariantList &edits, const QJSValue &cb) {
    ConfigRetainedGroupOptions options; options.requestKey = key;
    for (const auto &path : paths) options.paths.append(path.toStringList());
    for (const auto &value : edits) { auto edit = value.toMap(); options.edits.append({edit["path"].toStringList(), true, edit["value"]}); }
    return QString::number(m_store->retainGroup(options, this, callback(cb)));
}
QString NativeModelOwner::saveGroup(const QString &token, bool retry, const QJSValue &cb) {
    return QString::number(retry ? m_store->retryGroup(token, this, callback(cb)) : m_store->saveGroup(token, this, callback(cb)));
}
void NativeModelOwner::arm(const QString &phase, const QString &source) {
    std::lock_guard<std::mutex> lock(m_control->mutex); m_control->phase = phase; m_control->source = source;
    m_control->proceed = false; m_control->observed.clear(); m_control->error.clear();
}
void NativeModelOwner::release(const QString &error) {
    std::lock_guard<std::mutex> lock(m_control->mutex); m_control->error = error; m_control->proceed = true; m_control->released.notify_all();
}
void NativeModelOwner::reject(const QStringList &path, bool enabled, const QJSValue &cb) {
    const auto token = ++m_nextControl; m_controlCallbacks[token] = cb;
    QPointer<NativeModelOwner> guard(this); auto *worker = Probe::worker(m_store);
    QMetaObject::invokeMethod(worker, [worker, guard, path, enabled, token] {
        worker->setAdmission([path, enabled](const ConfigInput &input) { return enabled && input.path == path ? QString("test-admission") : QString(); });
        if (guard) QMetaObject::invokeMethod(guard, [guard, token] { if (guard) guard->controlDone(token); }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
}
void NativeModelOwner::holdReplies(bool enabled, const QJSValue &cb) {
    const auto token = ++m_nextControl; m_controlCallbacks[token] = cb;
    QPointer<NativeModelOwner> guard(this); auto *worker = Probe::worker(m_store);
    QMetaObject::invokeMethod(worker, [worker, enabled, guard, token] {
        worker->holdReplies(enabled);
        if (guard) QMetaObject::invokeMethod(guard, [guard, token] { if (guard) guard->controlDone(token); }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
}
void NativeModelOwner::releaseReplies(int count, const QJSValue &cb) {
    const auto token = ++m_nextControl; m_controlCallbacks[token] = cb;
    QPointer<NativeModelOwner> guard(this); auto *worker = Probe::worker(m_store);
    QMetaObject::invokeMethod(worker, [worker, count, guard, token] {
        worker->releaseReplies(count);
        if (guard) QMetaObject::invokeMethod(guard, [guard, token] { if (guard) guard->controlDone(token); }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
}
void NativeModelOwner::controlDone(quint64 token) { auto cb = m_controlCallbacks.take(token); if (cb.isCallable()) cb.call(); }
int NativeModelOwner::packetCount() const { return m_packets ? m_packets->values.size() : 0; }
void NativeModelOwner::replay(int index, bool wrongOwner) {
    auto packet = m_packets->values.at(index); if (wrongOwner) ++packet.snapshot.topology;
    Probe::inject(m_store, packet);
}
void NativeModelOwner::writeRaw(const QString &source, const QString &bytes) {
    if (!QStringList{"ui", "general", "bar", "bindings"}.contains(source)) qFatal("test source refused");
    QSaveFile file(m_directory + '/' + source + ".json");
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes.toUtf8()) != bytes.toUtf8().size() || !file.commit()) qFatal("test write failed");
}
QString NativeModelOwner::readRaw(const QString &source) const {
    if (!QStringList{"ui", "general", "bar", "bindings"}.contains(source)) qFatal("test source refused");
    QFile file(m_directory + '/' + source + ".json"); if (!file.open(QIODevice::ReadOnly)) return {}; return QString::fromUtf8(file.readAll());
}
