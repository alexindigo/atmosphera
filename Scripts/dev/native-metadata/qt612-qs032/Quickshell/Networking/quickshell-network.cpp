/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<device.hpp>)
#  include <device.hpp>
#endif
#if __has_include(<enums.hpp>)
#  include <enums.hpp>
#endif
#if __has_include(<network.hpp>)
#  include <network.hpp>
#endif
#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif
#if __has_include(<wifi.hpp>)
#  include <wifi.hpp>
#endif
#if __has_include(<wired.hpp>)
#  include <wired.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Networking()
{
    qmlRegisterModule("Quickshell.Networking", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::network::ConnectionFailReason>("Quickshell.Networking", 0);
    qmlRegisterEnum<qs::network::ConnectionFailReason::Enum>("qs::network::ConnectionFailReason::Enum");
    qmlRegisterTypesAndRevisions<qs::network::ConnectionState>("Quickshell.Networking", 0);
    qmlRegisterEnum<qs::network::ConnectionState::Enum>("qs::network::ConnectionState::Enum");
    qmlRegisterTypesAndRevisions<qs::network::DeviceType>("Quickshell.Networking", 0);
    qmlRegisterEnum<qs::network::DeviceType::Enum>("qs::network::DeviceType::Enum");
    qmlRegisterTypesAndRevisions<qs::network::Network>("Quickshell.Networking", 0);
    qmlRegisterTypesAndRevisions<qs::network::NetworkBackendType>("Quickshell.Networking", 0);
    qmlRegisterEnum<qs::network::NetworkBackendType::Enum>("qs::network::NetworkBackendType::Enum");
    qmlRegisterTypesAndRevisions<qs::network::NetworkConnectivity>("Quickshell.Networking", 0);
    qmlRegisterEnum<qs::network::NetworkConnectivity::Enum>("qs::network::NetworkConnectivity::Enum");
    qmlRegisterTypesAndRevisions<qs::network::NetworkDevice>("Quickshell.Networking", 0);
    qmlRegisterTypesAndRevisions<qs::network::NetworkingQml>("Quickshell.Networking", 0);
    qmlRegisterTypesAndRevisions<qs::network::WifiDevice>("Quickshell.Networking", 0);
    qmlRegisterTypesAndRevisions<qs::network::WifiDeviceMode>("Quickshell.Networking", 0);
    qmlRegisterEnum<qs::network::WifiDeviceMode::Enum>("qs::network::WifiDeviceMode::Enum");
    qmlRegisterTypesAndRevisions<qs::network::WifiNetwork>("Quickshell.Networking", 0);
    qmlRegisterTypesAndRevisions<qs::network::WifiSecurityType>("Quickshell.Networking", 0);
    qmlRegisterEnum<qs::network::WifiSecurityType::Enum>("qs::network::WifiSecurityType::Enum");
    qmlRegisterTypesAndRevisions<qs::network::WiredDevice>("Quickshell.Networking", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Networking", 0, 1);
}

static const QQmlModuleRegistration quickshellNetworkingRegistration("Quickshell.Networking", qml_register_types_Quickshell_Networking);
