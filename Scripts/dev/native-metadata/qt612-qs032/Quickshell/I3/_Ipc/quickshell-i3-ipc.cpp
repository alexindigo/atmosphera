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
#if __has_include(<listener.hpp>)
#  include <listener.hpp>
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
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_I3__Ipc()
{
    qmlRegisterModule("Quickshell.I3._Ipc", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::i3::ipc::I3IpcEvent>("Quickshell.I3._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::i3::ipc::I3IpcListener>("Quickshell.I3._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::i3::ipc::I3IpcQml>("Quickshell.I3._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::i3::ipc::I3Monitor>("Quickshell.I3._Ipc", 0);
    qmlRegisterTypesAndRevisions<qs::i3::ipc::I3Workspace>("Quickshell.I3._Ipc", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.I3._Ipc", 0, 1);
}

static const QQmlModuleRegistration quickshellI3IpcRegistration("Quickshell.I3._Ipc", qml_register_types_Quickshell_I3__Ipc);
