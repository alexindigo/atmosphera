#pragma once
#include <QObject>
#include <QPointer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include "configworker_p.h"

namespace configqml { class ConfigStore; }

// Explicit test observations of the actual production owner, never a proxy or
// replacement owner. No settings value is cached or written by this object.
class NativeStoreProbe : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QObject *target MEMBER m_target)
public:
    explicit NativeStoreProbe(QObject *parent = nullptr) : QObject(parent) {}
    ~NativeStoreProbe() override;
    Q_INVOKABLE QVariantMap sample(const QVariantList &paths) const;
    Q_INVOKABLE void beginPackets();
    Q_INVOKABLE QVariantList packets(const QVariantList &paths) const;
    Q_INVOKABLE void releasePacket(int index);
    Q_INVOKABLE void endPackets();
private:
    QPointer<QObject> m_target;
    QPointer<configqml::ConfigStore> m_core;
    QMetaObject::Connection m_route;
    QList<configqml::ConfigWorkerPacket> m_packets;
    QSet<int> m_released;
};
