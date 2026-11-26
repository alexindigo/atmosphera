/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<core.hpp>)
#  include <core.hpp>
#endif
#if __has_include(<device.hpp>)
#  include <device.hpp>
#endif
#if __has_include(<powerprofiles.hpp>)
#  include <powerprofiles.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Services_UPower()
{
    qmlRegisterModule("Quickshell.Services.UPower", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::service::upower::PerformanceDegradationReason>("Quickshell.Services.UPower", 0);
    qmlRegisterEnum<qs::service::upower::PerformanceDegradationReason::Enum>("qs::service::upower::PerformanceDegradationReason::Enum");
    qmlRegisterTypesAndRevisions<qs::service::upower::PowerProfile>("Quickshell.Services.UPower", 0);
    qmlRegisterEnum<qs::service::upower::PowerProfile::Enum>("qs::service::upower::PowerProfile::Enum");
    qmlRegisterTypesAndRevisions<qs::service::upower::PowerProfileHold>("Quickshell.Services.UPower", 0);
    QMetaType::fromType<qs::service::upower::PowerProfileHold *>().id();
    qmlRegisterTypesAndRevisions<qs::service::upower::PowerProfilesQml>("Quickshell.Services.UPower", 0);
    qmlRegisterTypesAndRevisions<qs::service::upower::UPowerDevice>("Quickshell.Services.UPower", 0);
    qmlRegisterTypesAndRevisions<qs::service::upower::UPowerDeviceState>("Quickshell.Services.UPower", 0);
    qmlRegisterEnum<qs::service::upower::UPowerDeviceState::Enum>("qs::service::upower::UPowerDeviceState::Enum");
    qmlRegisterTypesAndRevisions<qs::service::upower::UPowerDeviceType>("Quickshell.Services.UPower", 0);
    qmlRegisterEnum<qs::service::upower::UPowerDeviceType::Enum>("qs::service::upower::UPowerDeviceType::Enum");
    qmlRegisterTypesAndRevisions<qs::service::upower::UPowerQml>("Quickshell.Services.UPower", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Services.UPower", 0, 1);
}

static const QQmlModuleRegistration quickshellServicesUPowerRegistration("Quickshell.Services.UPower", qml_register_types_Quickshell_Services_UPower);
