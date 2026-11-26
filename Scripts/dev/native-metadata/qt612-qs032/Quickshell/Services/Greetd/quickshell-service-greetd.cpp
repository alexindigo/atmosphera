/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<connection.hpp>)
#  include <connection.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Services_Greetd()
{
    qmlRegisterModule("Quickshell.Services.Greetd", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<Greetd>("Quickshell.Services.Greetd", 0);
    qmlRegisterTypesAndRevisions<GreetdState>("Quickshell.Services.Greetd", 0);
    qmlRegisterEnum<GreetdState::Enum>("GreetdState::Enum");
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Services.Greetd", 0, 1);
}

static const QQmlModuleRegistration quickshellServicesGreetdRegistration("Quickshell.Services.Greetd", qml_register_types_Quickshell_Services_Greetd);
