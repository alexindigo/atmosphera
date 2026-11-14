#include "probe.h"
#include "access.h"
#include "configstore.h"
#include "configworker_p.h"
#include <QCryptographicHash>
#include <QMetaEnum>

using namespace configqml;

NativeStoreProbe::~NativeStoreProbe() {
    if (m_core) {
        QObject::disconnect(m_route);
        ConfigStoreTestAccess::restore(m_core);
    }
}

void NativeStoreProbe::beginPackets() {
    if (m_core) qFatal("native packet schedule already active");
    m_core = m_target ? m_target->findChild<ConfigStore *>() : nullptr;
    if (!m_core || m_core->status() != ConfigStore::Status::Ready) qFatal("native packet schedule requires ready real owner");
    m_packets.clear(); m_released.clear();
    m_route = ConfigStoreTestAccess::intercept(m_core, this, [this](const ConfigWorkerPacket &packet) {
        // Exactly the installed worker packet, with immutable admitted snapshot.
        // The probe never constructs/changes a result, source body or generation.
        m_packets.append(packet);
    });
}

QVariantList NativeStoreProbe::packets(const QVariantList &paths) const {
    QVariantList result;
    for (int index = 0; index < m_packets.size(); ++index) {
        const auto &packet = m_packets[index];
        const auto &admitted = packet.admitted ? *packet.admitted : packet.snapshot;
        QVariantMap values;
        QVariantList changedPaths;
        for (auto it = packet.snapshot.values.cbegin(); it != packet.snapshot.values.cend(); ++it)
            changedPaths.append(QVariant(it.key()));
        for (const auto &item : paths) {
            const auto path = item.toStringList();
            if (m_core && !m_core->schema().sensitive(path)) values[path.join('.')] = admitted.values.value(path);
        }
        result.append(QVariantMap{{"index", index}, {"released", m_released.contains(index)},
            {"generation", QString::number(packet.snapshot.generation)},
            {"inputPrefix", QString::number(packet.snapshot.inputPrefix)}, {"values", values},
            {"changedPaths", changedPaths},
            {"requestId", packet.result ? QString::number(packet.result->requestId) : QString()},
            {"operation", packet.result ? packet.result->operation : QString()},
            {"status", packet.result ? packet.result->status : QString()}});
    }
    return result;
}

void NativeStoreProbe::releasePacket(int index) {
    if (!m_core || index < 0 || index >= m_packets.size() || m_released.contains(index))
        qFatal("native packet release must select one owned undelivered packet");
    m_released.insert(index);
    ConfigStoreTestAccess::inject(m_core, m_packets[index]);
}

void NativeStoreProbe::endPackets() {
    if (!m_core) qFatal("native packet schedule not active");
    for (int index = 0; index < m_packets.size(); ++index)
        if (!m_released.contains(index)) releasePacket(index);
    QObject::disconnect(m_route);
    ConfigStoreTestAccess::restore(m_core);
    m_core.clear();
}

QVariantMap NativeStoreProbe::sample(const QVariantList &paths) const {
    auto *store = m_target ? m_target->findChild<ConfigStore *>() : nullptr;
    if (!store) qFatal("native test probe requires the actual ConfigStore child");
    const auto snapshot = store->snapshot();
    QVariantMap information;
    for (const auto &item : paths) {
        const auto path = item.toStringList();
        const auto info = store->info(path);
        const auto admitted = snapshot.values.value(path);
        information[path.join('.')] = QVariantMap{
            {"path", path}, {"latestInput", QString::number(info.latestInput)},
            {"workerCovered", QString::number(info.workerCovered)},
            {"pathGeneration", QString::number(info.pathGeneration)},
            {"publicationGeneration", QString::number(info.publicationGeneration)},
            {"contentRevision", QString::number(info.contentRevision)},
            {"intentRevision", QString::number(info.intentRevision)}, {"admittedPresent", snapshot.values.contains(path)},
            {"presentedFingerprint", QString::fromLatin1(QCryptographicHash::hash(
                encodeMemoryValue({{"value", store->value(path)}}), QCryptographicHash::Sha256).toHex())},
            {"admittedFingerprint", QString::fromLatin1(QCryptographicHash::hash(
                encodeMemoryValue({{"value", admitted}}), QCryptographicHash::Sha256).toHex())}};
    }
    QVariantList inputs, failures;
    for (const auto &input : store->inputs()) {
        const auto bytes = encodeMemoryValue({{"value", input.value}});
        inputs.append(QVariantMap{{"sequence", QString::number(input.sequence)}, {"path", input.path},
            {"fingerprint", QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex())}});
    }
    for (const auto &failure : store->failures())
        failures.append(QVariantMap{{"requestId", QString::number(failure.requestId)}, {"operation", failure.operation},
            {"inputPrefix", QString::number(failure.inputPrefix)}, {"status", failure.status}, {"code", failure.error.code}});
    QVariantList pending, groups;
    for (const auto id : ConfigStoreTestAccess::pending(store)) pending.append(QString::number(id));
    for (const auto &group : ConfigStoreTestAccess::groups(store)) {
        QVariantList attempts;
        for (const auto &attempt : group.attempts)
            attempts.append(QVariantMap{{"attemptId", attempt.attemptId}, {"status", attempt.status}});
        groups.append(QVariantMap{{"token", group.groupToken}, {"requestKey", group.requestKey},
            {"capturePrefix", QString::number(group.capturePrefix)}, {"state", group.state}, {"attempts", attempts}});
    }
    return {{"status", QString::fromLatin1(QMetaEnum::fromType<ConfigStore::Status>().valueToKey(int(store->status())))},
        {"admittedPrefix", QString::number(snapshot.inputPrefix)},
        {"admittedGeneration", QString::number(snapshot.generation)}, {"paths", information},
        {"inputs", inputs}, {"failures", failures}, {"groups", groups}, {"pendingRequests", pending},
        {"nextCompletion", QString::number(ConfigStoreTestAccess::nextCompletion(store))},
        {"inputPrefix", QString::number(ConfigStoreTestAccess::inputPrefix(store))}};
}
