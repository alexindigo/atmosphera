#pragma once
#include <configfacade.h>
#include <configstore.h>
#include <QJSValue>
#include <QQmlParserStatus>
#include <QtQml/qqmlregistration.h>
#include <condition_variable>
#include <mutex>

class ModelLeaf : public configqml::ConfigFacade {
    Q_OBJECT
    Q_PROPERTY(double scale READ scale WRITE setScale NOTIFY changed)
    Q_PROPERTY(double scaleRatio READ scaleRatio WRITE setScaleRatio NOTIFY changed)
    Q_PROPERTY(QString environment READ environment WRITE setEnvironment NOTIFY changed)
    Q_PROPERTY(QVariantList records READ records WRITE setRecords NOTIFY changed)
public:
    ModelLeaf(configqml::ConfigStore *store, const configqml::ConfigPath &prefix, QObject *parent);
    double scale() const { return readSetting({"scale"}).toDouble(); }
    double scaleRatio() const { return readSetting({"scaleRatio"}).toDouble(); }
    QString environment() const { return readSetting({"environment"}).toString(); }
    QVariantList records() const { return readSetting({"records"}).toList(); }
    void setScale(double value) { writeSetting({"scale"}, value); }
    void setScaleRatio(double value) { writeSetting({"scaleRatio"}, value); }
    void setEnvironment(const QString &value) { writeSetting({"environment"}, value); }
    void setRecords(const QVariantList &value) { writeSetting({"records"}, value); }
signals:
    void changed();
};

class NativeModelOwner : public QObject, public QQmlParserStatus {
    Q_OBJECT
    QML_NAMED_ELEMENT(NativeModelOwner)
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString directory MEMBER m_directory)
    Q_PROPERTY(double schemaDefault MEMBER m_default)
    Q_PROPERTY(bool invalidSchema MEMBER m_invalidSchema)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QObject *ui READ ui NOTIFY changed)
    Q_PROPERTY(QObject *general READ general NOTIFY changed)
    Q_PROPERTY(QObject *bar READ bar NOTIFY changed)
    Q_PROPERTY(QObject *bindings READ bindings NOTIFY changed)
    Q_PROPERTY(bool held READ held NOTIFY changed)
    Q_PROPERTY(QString heldPhase READ heldPhase NOTIFY changed)
    Q_PROPERTY(int callbackCount READ callbackCount NOTIFY changed)
public:
    explicit NativeModelOwner(QObject *parent = nullptr);
    ~NativeModelOwner() override;
    void classBegin() override {}
    void componentComplete() override;
    bool ready() const;
    QString error() const { return m_store ? m_store->error() : QString(); }
    QObject *ui() const { return m_ui; }
    QObject *general() const { return m_general; }
    QObject *bar() const { return m_bar; }
    QObject *bindings() const { return m_bindings; }
    bool held() const;
    QString heldPhase() const;
    int callbackCount() const;
    Q_INVOKABLE QVariantMap info(const QStringList &path) const;
    Q_INVOKABLE QVariantMap group(const QString &token) const;
    Q_INVOKABLE QVariantList failures() const;
    Q_INVOKABLE QVariantList inputs() const;
    Q_INVOKABLE QString identity(const QString &source) const;
    Q_INVOKABLE bool evidenceContains(const QString &bytes) const;
    Q_INVOKABLE QVariant value(const QStringList &path) const;
    Q_INVOKABLE QVariant defaultValue(const QStringList &path) const;
    Q_INVOKABLE QString save(const QJSValue &callback);
    Q_INVOKABLE QString reload(const QJSValue &callback);
    Q_INVOKABLE QString close(const QJSValue &callback);
    Q_INVOKABLE QString retain(const QString &key, const QVariantList &paths, const QVariantList &edits, const QJSValue &callback);
    Q_INVOKABLE QString saveGroup(const QString &token, bool retry, const QJSValue &callback);
    Q_INVOKABLE void arm(const QString &phase, const QString &source = QString());
    Q_INVOKABLE void release(const QString &error = QString());
    Q_INVOKABLE void reject(const QStringList &path, bool enabled, const QJSValue &callback);
    Q_INVOKABLE void holdReplies(bool enabled, const QJSValue &callback);
    Q_INVOKABLE void releaseReplies(int count, const QJSValue &callback);
    Q_INVOKABLE int packetCount() const;
    Q_INVOKABLE void replay(int index, bool wrongOwner);
    Q_INVOKABLE void writeRaw(const QString &source, const QString &bytes);
    Q_INVOKABLE QString readRaw(const QString &source) const;
signals:
    void changed();
    void completed(const QVariantMap &result);
    void valuesChanged(const QVariantList &paths);
private:
    struct Control {
        std::mutex mutex;
        std::condition_variable released;
        QString phase, source, observed, error;
        bool waiting = false, proceed = false, stopping = false;
    };
    struct Packets;
    configqml::ConfigStore::Callback callback(const QJSValue &function);
    void controlDone(quint64 token);
    QString m_directory;
    double m_default = 1;
    bool m_invalidSchema = false;
    configqml::ConfigStore *m_store = nullptr;
    ModelLeaf *m_ui = nullptr, *m_general = nullptr, *m_bar = nullptr, *m_bindings = nullptr;
    std::shared_ptr<Control> m_control = std::make_shared<Control>();
    std::unique_ptr<Packets> m_packets;
    quint64 m_nextControl = 0;
    QMap<quint64, QJSValue> m_controlCallbacks;
};
