/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<session_lock.hpp>)
#  include <session_lock.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Wayland()
{
    qmlRegisterModule("Quickshell.Wayland", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<WlSessionLock>("Quickshell.Wayland", 0);
    qmlRegisterTypesAndRevisions<WlSessionLockSurface>("Quickshell.Wayland", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Wayland", 0, 1);
}

static const QQmlModuleRegistration quickshellWaylandRegistration("Quickshell.Wayland", qml_register_types_Quickshell_Wayland);
