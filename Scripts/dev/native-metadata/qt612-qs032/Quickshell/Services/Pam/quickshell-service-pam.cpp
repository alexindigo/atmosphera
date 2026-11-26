/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<conversation.hpp>)
#  include <conversation.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Services_Pam()
{
    qmlRegisterModule("Quickshell.Services.Pam", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<PamContext>("Quickshell.Services.Pam", 0);
    qmlRegisterTypesAndRevisions<PamError>("Quickshell.Services.Pam", 0);
    qmlRegisterEnum<PamError::Enum>("PamError::Enum");
    qmlRegisterTypesAndRevisions<PamResult>("Quickshell.Services.Pam", 0);
    qmlRegisterEnum<PamResult::Enum>("PamResult::Enum");
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Services.Pam", 0, 1);
}

static const QQmlModuleRegistration quickshellServicesPamRegistration("Quickshell.Services.Pam", qml_register_types_Quickshell_Services_Pam);
