/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<notification.hpp>)
#  include <notification.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Services_Notifications()
{
    qmlRegisterModule("Quickshell.Services.Notifications", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::service::notifications::Notification>("Quickshell.Services.Notifications", 0);
    qmlRegisterTypesAndRevisions<qs::service::notifications::NotificationAction>("Quickshell.Services.Notifications", 0);
    qmlRegisterTypesAndRevisions<qs::service::notifications::NotificationCloseReason>("Quickshell.Services.Notifications", 0);
    qmlRegisterEnum<qs::service::notifications::NotificationCloseReason::Enum>("qs::service::notifications::NotificationCloseReason::Enum");
    qmlRegisterTypesAndRevisions<qs::service::notifications::NotificationServerQml>("Quickshell.Services.Notifications", 0);
    qmlRegisterTypesAndRevisions<qs::service::notifications::NotificationUrgency>("Quickshell.Services.Notifications", 0);
    qmlRegisterEnum<qs::service::notifications::NotificationUrgency::Enum>("qs::service::notifications::NotificationUrgency::Enum");
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Services.Notifications", 0, 1);
}

static const QQmlModuleRegistration quickshellServicesNotificationsRegistration("Quickshell.Services.Notifications", qml_register_types_Quickshell_Services_Notifications);
