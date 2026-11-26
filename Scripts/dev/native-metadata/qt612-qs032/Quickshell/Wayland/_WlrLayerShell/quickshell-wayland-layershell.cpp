/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<wlr_layershell.hpp>)
#  include <wlr_layershell.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Wayland__WlrLayerShell()
{
    qmlRegisterModule("Quickshell.Wayland._WlrLayerShell", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    QMetaType::fromType<ProxyWindowBase *>().id();
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &qs::wayland::layershell::WlrKeyboardFocus::staticMetaObject;},
            "qs::wayland::layershell::WlrKeyboardFocus");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&qs::wayland::layershell::WlrKeyboardFocus::staticMetaObject, "Quickshell.Wayland._WlrLayerShell", 0, nullptr, &qs::wayland::layershell::WlrKeyboardFocus::staticMetaObject, nullptr);
    qmlRegisterEnum<qs::wayland::layershell::WlrKeyboardFocus::Enum>("qs::wayland::layershell::WlrKeyboardFocus::Enum");
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &qs::wayland::layershell::WlrLayer::staticMetaObject;},
            "qs::wayland::layershell::WlrLayer");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&qs::wayland::layershell::WlrLayer::staticMetaObject, "Quickshell.Wayland._WlrLayerShell", 0, nullptr, &qs::wayland::layershell::WlrLayer::staticMetaObject, nullptr);
    qmlRegisterEnum<qs::wayland::layershell::WlrLayer::Enum>("qs::wayland::layershell::WlrLayer::Enum");
    qmlRegisterTypesAndRevisions<qs::wayland::layershell::WlrLayershell>("Quickshell.Wayland._WlrLayerShell", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Wayland._WlrLayerShell", 0, 1);
}

static const QQmlModuleRegistration quickshellWaylandWlrLayerShellRegistration("Quickshell.Wayland._WlrLayerShell", qml_register_types_Quickshell_Wayland__WlrLayerShell);
