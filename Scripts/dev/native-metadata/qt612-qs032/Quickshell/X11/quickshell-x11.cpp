/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<panel_window.hpp>)
#  include <panel_window.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_X11()
{
    qmlRegisterModule("Quickshell.X11", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    QMetaType::fromType<ProxyWindowBase *>().id();
    qmlRegisterTypesAndRevisions<XPanelWindow>("Quickshell.X11", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.X11", 0, 1);
}

static const QQmlModuleRegistration quickshellX11Registration("Quickshell.X11", qml_register_types_Quickshell_X11);
