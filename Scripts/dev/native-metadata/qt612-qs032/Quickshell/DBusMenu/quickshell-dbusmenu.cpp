/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<dbusmenu.hpp>)
#  include <dbusmenu.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_DBusMenu()
{
    qmlRegisterModule("Quickshell.DBusMenu", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::dbus::dbusmenu::DBusMenu>("Quickshell.DBusMenu", 0);
    qmlRegisterTypesAndRevisions<qs::dbus::dbusmenu::DBusMenuItem>("Quickshell.DBusMenu", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.DBusMenu", 0, 1);
}

static const QQmlModuleRegistration quickshellDBusMenuRegistration("Quickshell.DBusMenu", qml_register_types_Quickshell_DBusMenu);
