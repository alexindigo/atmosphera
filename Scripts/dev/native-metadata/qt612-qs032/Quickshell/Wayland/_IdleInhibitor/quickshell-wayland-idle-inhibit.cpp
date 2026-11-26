/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<inhibitor.hpp>)
#  include <inhibitor.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Wayland__IdleInhibitor()
{
    qmlRegisterModule("Quickshell.Wayland._IdleInhibitor", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::wayland::idle_inhibit::IdleInhibitor>("Quickshell.Wayland._IdleInhibitor", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Wayland._IdleInhibitor", 0, 1);
}

static const QQmlModuleRegistration quickshellWaylandIdleInhibitorRegistration("Quickshell.Wayland._IdleInhibitor", qml_register_types_Quickshell_Wayland__IdleInhibitor);
