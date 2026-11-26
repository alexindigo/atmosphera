/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<flow.hpp>)
#  include <flow.hpp>
#endif
#if __has_include(<identity.hpp>)
#  include <identity.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Services_Polkit()
{
    qmlRegisterModule("Quickshell.Services.Polkit", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::service::polkit::AuthFlow>("Quickshell.Services.Polkit", 0);
    qmlRegisterTypesAndRevisions<qs::service::polkit::Identity>("Quickshell.Services.Polkit", 0);
    qmlRegisterTypesAndRevisions<qs::service::polkit::PolkitAgent>("Quickshell.Services.Polkit", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Services.Polkit", 0, 1);
}

static const QQmlModuleRegistration quickshellServicesPolkitRegistration("Quickshell.Services.Polkit", qml_register_types_Quickshell_Services_Polkit);
