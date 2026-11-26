/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<item.hpp>)
#  include <item.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Services_SystemTray()
{
    qmlRegisterModule("Quickshell.Services.SystemTray", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<SystemTray>("Quickshell.Services.SystemTray", 0);
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &qs::service::sni::Category::staticMetaObject;},
            "qs::service::sni::Category");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&qs::service::sni::Category::staticMetaObject, "Quickshell.Services.SystemTray", 0, nullptr, &qs::service::sni::Category::staticMetaObject, nullptr);
    qmlRegisterEnum<qs::service::sni::Category::Enum>("qs::service::sni::Category::Enum");
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &qs::service::sni::Status::staticMetaObject;},
            "qs::service::sni::Status");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&qs::service::sni::Status::staticMetaObject, "Quickshell.Services.SystemTray", 0, nullptr, &qs::service::sni::Status::staticMetaObject, nullptr);
    qmlRegisterEnum<qs::service::sni::Status::Enum>("qs::service::sni::Status::Enum");
    qmlRegisterTypesAndRevisions<qs::service::sni::StatusNotifierItem>("Quickshell.Services.SystemTray", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Services.SystemTray", 0, 1);
}

static const QQmlModuleRegistration quickshellServicesSystemTrayRegistration("Quickshell.Services.SystemTray", qml_register_types_Quickshell_Services_SystemTray);
