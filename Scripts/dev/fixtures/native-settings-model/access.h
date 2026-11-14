#pragma once
#include "configstore.h"
#include "configworker_p.h"
#include "configshutdown_p.h"

// One definition across both test consumers. Observations stay on the owner
// thread; this never reaches into mutable worker state from the GUI thread.
namespace configqml {
class ConfigStoreTestAccess {
public:
    static ConfigWorker *worker(ConfigStore *store) { return store->m_worker; }
    static int callbacks(ConfigStore *store) { return store->m_pending.size(); }
    static QList<quint64> pending(ConfigStore *store) { return store->m_pending.keys(); }
    static quint64 nextCompletion(ConfigStore *store) { return store->m_nextCompletion; }
    static quint64 inputPrefix(ConfigStore *store) { return store->m_sequence; }
    static QMap<QString, ConfigGroupInfo> groups(ConfigStore *store) { return store->m_groups; }
    static void inject(ConfigStore *store, const ConfigWorkerPacket &packet) { store->receive(packet); }
    static QMetaObject::Connection intercept(ConfigStore *store, QObject *observer,
        const std::function<void(const ConfigWorkerPacket &)> &callback) {
        QObject::disconnect(store->m_owner.get(), &ConfigWorkerOwner::packetReady, store, &ConfigStore::receive);
        return QObject::connect(store->m_owner.get(), &ConfigWorkerOwner::packetReady, observer, callback);
    }
    static void restore(ConfigStore *store) {
        QObject::connect(store->m_owner.get(), &ConfigWorkerOwner::packetReady, store, &ConfigStore::receive, Qt::UniqueConnection);
    }
};
}
