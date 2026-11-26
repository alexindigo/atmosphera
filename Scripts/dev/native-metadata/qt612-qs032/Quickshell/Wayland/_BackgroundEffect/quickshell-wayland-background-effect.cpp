/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<qml.hpp>)
#  include <qml.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Wayland__BackgroundEffect()
{
    qmlRegisterModule("Quickshell.Wayland._BackgroundEffect", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::wayland::background_effect::BackgroundEffect>("Quickshell.Wayland._BackgroundEffect", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Wayland._BackgroundEffect", 0, 1);
}

static const QQmlModuleRegistration quickshellWaylandBackgroundEffectRegistration("Quickshell.Wayland._BackgroundEffect", qml_register_types_Quickshell_Wayland__BackgroundEffect);
