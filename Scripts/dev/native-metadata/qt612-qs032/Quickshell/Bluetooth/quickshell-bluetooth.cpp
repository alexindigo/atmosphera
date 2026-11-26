/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<adapter.hpp>)
#  include <adapter.hpp>
#endif
#if __has_include(<bluez.hpp>)
#  include <bluez.hpp>
#endif
#if __has_include(<device.hpp>)
#  include <device.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Bluetooth()
{
    qmlRegisterModule("Quickshell.Bluetooth", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::bluetooth::BluetoothAdapter>("Quickshell.Bluetooth", 0);
    qmlRegisterTypesAndRevisions<qs::bluetooth::BluetoothAdapterState>("Quickshell.Bluetooth", 0);
    qmlRegisterEnum<qs::bluetooth::BluetoothAdapterState::Enum>("qs::bluetooth::BluetoothAdapterState::Enum");
    qmlRegisterTypesAndRevisions<qs::bluetooth::BluetoothDevice>("Quickshell.Bluetooth", 0);
    qmlRegisterTypesAndRevisions<qs::bluetooth::BluetoothDeviceState>("Quickshell.Bluetooth", 0);
    qmlRegisterEnum<qs::bluetooth::BluetoothDeviceState::Enum>("qs::bluetooth::BluetoothDeviceState::Enum");
    qmlRegisterTypesAndRevisions<qs::bluetooth::BluezQml>("Quickshell.Bluetooth", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Bluetooth", 0, 1);
}

static const QQmlModuleRegistration quickshellBluetoothRegistration("Quickshell.Bluetooth", qml_register_types_Quickshell_Bluetooth);
