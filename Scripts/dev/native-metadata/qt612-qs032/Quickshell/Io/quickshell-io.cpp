/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<datastream.hpp>)
#  include <datastream.hpp>
#endif
#if __has_include(<fileview.hpp>)
#  include <fileview.hpp>
#endif
#if __has_include(<ipchandler.hpp>)
#  include <ipchandler.hpp>
#endif
#if __has_include(<jsonadapter.hpp>)
#  include <jsonadapter.hpp>
#endif
#if __has_include(<process.hpp>)
#  include <process.hpp>
#endif
#if __has_include(<processcore.hpp>)
#  include <processcore.hpp>
#endif
#if __has_include(<socket.hpp>)
#  include <socket.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Io()
{
    qmlRegisterModule("Quickshell.Io", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<DataStream>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<DataStreamParser>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<Process>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<Socket>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<SocketServer>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<SplitParser>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<StdioCollector>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<qs::io::FileView>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<qs::io::FileViewAdapter>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<qs::io::FileViewError>("Quickshell.Io", 0);
    qmlRegisterEnum<qs::io::FileViewError::Enum>("qs::io::FileViewError::Enum");
    qmlRegisterTypesAndRevisions<qs::io::JsonAdapter>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<qs::io::JsonObject>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<qs::io::ipc::IpcHandler>("Quickshell.Io", 0);
    qmlRegisterTypesAndRevisions<qs::io::process::ProcessContext>("Quickshell.Io", 0);
    QMetaType::fromType<qs::io::process::ProcessContext *>().id();
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Io", 0, 1);
}

static const QQmlModuleRegistration quickshellIoRegistration("Quickshell.Io", qml_register_types_Quickshell_Io);
