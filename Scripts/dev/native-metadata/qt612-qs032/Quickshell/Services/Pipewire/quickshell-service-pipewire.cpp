/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<link.hpp>)
#  include <link.hpp>
#endif
#if __has_include(<node.hpp>)
#  include <node.hpp>
#endif
#if __has_include(<peak.hpp>)
#  include <peak.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Services_Pipewire()
{
    qmlRegisterModule("Quickshell.Services.Pipewire", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::service::pipewire::Pipewire>("Quickshell.Services.Pipewire", 0);
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwAudioChannel>("Quickshell.Services.Pipewire", 0);
    qmlRegisterEnum<qs::service::pipewire::PwAudioChannel::Enum>("qs::service::pipewire::PwAudioChannel::Enum");
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwLinkGroupIface>("Quickshell.Services.Pipewire", 0);
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwLinkIface>("Quickshell.Services.Pipewire", 0);
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwLinkState>("Quickshell.Services.Pipewire", 0);
    qmlRegisterEnum<qs::service::pipewire::PwLinkState::Enum>("qs::service::pipewire::PwLinkState::Enum");
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwNodeAudioIface>("Quickshell.Services.Pipewire", 0);
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwNodeIface>("Quickshell.Services.Pipewire", 0);
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwNodeLinkTracker>("Quickshell.Services.Pipewire", 0);
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwNodePeakMonitor>("Quickshell.Services.Pipewire", 0);
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwNodeType>("Quickshell.Services.Pipewire", 0);
    qmlRegisterEnum<qs::service::pipewire::PwNodeType::Flag>("qs::service::pipewire::PwNodeType::Flag");
    qmlRegisterEnum<qs::service::pipewire::PwNodeType::Flags>("qs::service::pipewire::PwNodeType::Flags");
    qmlRegisterEnum<qs::service::pipewire::PwNodeType::Flag>("qs::service::pipewire::PwNodeType::Flag");
    QMetaType::fromType<qs::service::pipewire::PwObjectIface *>().id();
    qmlRegisterTypesAndRevisions<qs::service::pipewire::PwObjectTracker>("Quickshell.Services.Pipewire", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Services.Pipewire", 0, 1);
}

static const QQmlModuleRegistration quickshellServicesPipewireRegistration("Quickshell.Services.Pipewire", qml_register_types_Quickshell_Services_Pipewire);
