// Test-only interposition at the installed backend's existing IO boundaries.
// Never substitutes file bytes or a success receipt. Children cannot use it.
#include "configjsonbackend.h"
#include "configevidence_p.h"
#include <QCryptographicHash>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>
#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <cstdlib>

namespace {
const pid_t subject = ::getpid();
const bool subjectProcess = [] {
    const auto inherited = ::getenv("ATCQ_NATIVE_SUBJECT");
    if (inherited && QByteArray(inherited) != QByteArray::number(subject)) return false;
    ::setenv("ATCQ_NATIVE_SUBJECT", QByteArray::number(subject).constData(), 1);
    return true;
}();

template<typename Function> Function original(const char *symbol) {
    auto result = reinterpret_cast<Function>(::dlsym(RTLD_NEXT, symbol));
    if (!result) qFatal("native IO test symbol unavailable");
    return result;
}

QString control(const QString &phase, const QString &target, const QJsonObject &facts = {}) {
    // An exec'd helper has a different executable, even when LD_PRELOAD was
    // inherited. Only the owned qs process may claim/consume a scheduling rule.
    const auto executable = QFileInfo(QFileInfo(QStringLiteral("/proc/self/exe")).symLinkTarget()).fileName();
    if (!subjectProcess || ::getpid() != subject || (executable != "qs" && executable != "quickshell")) return {};
    const auto name = qEnvironmentVariable("ATCQ_NATIVE_SCHEDULE");
    if (name.isEmpty()) return {};
    QFile schedule(name);
    if (!schedule.open(QIODevice::ReadOnly) || schedule.size() > 65536) qFatal("native IO test schedule unavailable");
    const auto document = QJsonDocument::fromJson(schedule.readAll());
    if (!document.isObject() || !document.object()["rules"].isArray()) qFatal("native IO test schedule invalid");
    const auto root = QFileInfo(name).absolutePath() + '/';
    for (const auto &value : document.object()["rules"].toArray()) {
        const auto rule = value.toObject();
        if (rule["phase"].toString() != phase || rule["file"].toString() != target) continue;
        bool matches = true;
        for (const auto &key : {"sourceId", "role", "observationPhase", "sha256"})
            if (rule.contains(key) && rule[key] != facts[key]) matches = false;
        if (!matches) continue;
        const auto enabled = rule["enabled"].toString();
        if (!enabled.isEmpty()) {
            if (!enabled.startsWith(root) || enabled.contains("/../") || QFileInfo(enabled).isSymLink())
                qFatal("native IO test enable flag escapes its directory");
            if (!QFileInfo::exists(enabled)) continue;
        }
        const auto marker = rule["marker"].toString(), gate = rule["gate"].toString();
        const auto error = rule["error"].toString();
        if (!error.isEmpty() && !error.startsWith("controlled-native-")) qFatal("native IO test error must identify instrumentation");
        if (!marker.startsWith(root) || marker.contains("/../") ||
            (error.isEmpty() && (!gate.startsWith(root) || gate.contains("/../") || QFileInfo(gate).isSymLink())))
            qFatal("native IO test rule escapes its directory");
        QFile claim(marker);
        if (!claim.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
            if (QFileInfo::exists(marker)) {
                if (rule["repeat"].toBool() && !error.isEmpty()) return error;
                continue;
            }
            qFatal("native IO test rule claim failed");
        }
        if (!claim.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)) qFatal("native IO test marker permissions");
        claim.write(QJsonDocument(QJsonObject{{"phase", phase}, {"file", target}, {"pid", int(subject)},
            {"thread", QString::number(quintptr(QThread::currentThreadId()))}, {"observation", facts}}).toJson(QJsonDocument::Compact));
        claim.close();
        if (!error.isEmpty()) return error;
        const int descriptor = ::open(QFile::encodeName(gate).constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
        if (descriptor < 0) qFatal("native IO test gate unavailable");
        QElapsedTimer deadline; deadline.start(); QByteArray release;
        while (deadline.elapsed() < 30000 && !release.contains('\n')) {
            struct pollfd watch{descriptor, POLLIN, 0};
            if (::poll(&watch, 1, 20) < 0) break;
            char bytes[64]; const auto count = ::read(descriptor, bytes, sizeof(bytes));
            if (count > 0) release.append(bytes, count);
        }
        ::close(descriptor);
        if (!release.contains('\n')) return "test-control-deadline";
        if (release.trimmed() != "0") return "controlled-native-" + phase;
    }
    return {};
}
}

namespace configqml {
QString ConfigJsonBackend::fault(const QString &phase, const QString &file) const {
    const auto injected = control(phase, file);
    if (!injected.isEmpty()) return injected;
    using Function = QString (*)(const ConfigJsonBackend *, const QString &, const QString &);
    static const auto forward = original<Function>("_ZNK9configqml17ConfigJsonBackend5faultERK7QStringS3_");
    return forward(this, phase, file);
}

ConfigBackendResult ConfigJsonBackend::read(const QString &id, const QString &expectedTarget) {
    const auto before = control("read-before", path(id));
    using Function = ConfigBackendResult (*)(ConfigJsonBackend *, const QString &, const QString &);
    static const auto forward = original<Function>("_ZN9configqml17ConfigJsonBackend4readERK7QStringS3_");
    auto result = forward(this, id, expectedTarget);
    const auto after = control("read-after", path(id), QJsonObject{{"sourceId", id},
        {"presence", result.observedPresence ? (*result.observedPresence ? "present" : "absent") : "unknown"},
        {"bytesAvailable", result.bytesAvailable}, {"bytesBase64", QString::fromLatin1(result.bytes.toBase64())},
        {"sha256", QString::fromLatin1(QCryptographicHash::hash(result.bytes, QCryptographicHash::Sha256).toHex())},
        {"revision", QString::fromLatin1(result.revision.token)}, {"error", result.error.code}});
    const auto injected = before.isEmpty() ? after : before;
    if (!injected.isEmpty()) {
        result.success = false;
        result.error = ConfigError(injected, id, "read", path(id));
    }
    return result;
}

std::optional<ConfigEvidenceReference> retainEvidence(const QString &root, const ConfigEvidenceObservation &observation) {
    const auto injected = control("retain-before", root, QJsonObject{{"sourceId", observation.sourceId},
        {"role", observation.role}, {"observationPhase", observation.phase}, {"presence", observation.presence},
        {"bytesState", observation.bytesState}, {"bytesBase64", QString::fromLatin1(observation.bytes.toBase64())},
        {"sha256", QString::fromLatin1(QCryptographicHash::hash(observation.bytes, QCryptographicHash::Sha256).toHex())},
        {"revision", QString::fromLatin1(observation.revision.token)}, {"requestId", observation.requestId},
        {"groupToken", observation.groupToken}, {"attemptId", observation.attemptId},
        {"observationOrder", QString::number(observation.observationOrder)}});
    if (!injected.isEmpty()) return {};
    using Function = std::optional<ConfigEvidenceReference> (*)(const QString &, const ConfigEvidenceObservation &);
    static const auto forward = original<Function>("_ZN9configqml14retainEvidenceERK7QStringRKNS_25ConfigEvidenceObservationE");
    return forward(root, observation);
}
}
