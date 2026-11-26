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
#if __has_include(<hyprland_toplevel.hpp>)
#  include <hyprland_toplevel.hpp>
#endif
#if __has_include(<monitor.hpp>)
#  include <monitor.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif
#if __has_include(<workspace.hpp>)
#  include <workspace.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Hyprland__Ipc()
{
    qmlRegisterModule("Quickshell.Hyprland._Ipc", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::hyprland::ipc::HyprlandIpcEvent>("Quickshell.Hyprland._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::hyprland::ipc::HyprlandIpcQml>("Quickshell.Hyprland._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::hyprland::ipc::HyprlandMonitor>("Quickshell.Hyprland._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::hyprland::ipc::HyprlandToplevel>("Quickshell.Hyprland._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::hyprland::ipc::HyprlandWorkspace>("Quickshell.Hyprland._Ipc", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Hyprland._Ipc", 0, 1);
}

static const QQmlModuleRegistration quickshellHyprlandIpcRegistration("Quickshell.Hyprland._Ipc", qml_register_types_Quickshell_Hyprland__Ipc);
