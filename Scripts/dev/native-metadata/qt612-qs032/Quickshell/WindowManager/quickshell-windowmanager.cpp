/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<screenprojection.hpp>)
#  include <screenprojection.hpp>
#endif
#if __has_include(<windowmanager.hpp>)
#  include <windowmanager.hpp>
#endif
#if __has_include(<windowset.hpp>)
#  include <windowset.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_WindowManager()
{
    qmlRegisterModule("Quickshell.WindowManager", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<qs::wm::ScreenProjection>("Quickshell.WindowManager", 0);
    qmlRegisterTypesAndRevisions<qs::wm::WindowManagerQml>("Quickshell.WindowManager", 0);
    qmlRegisterTypesAndRevisions<qs::wm::Windowset>("Quickshell.WindowManager", 0);
    qmlRegisterTypesAndRevisions<qs::wm::WindowsetProjection>("Quickshell.WindowManager", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.WindowManager", 0, 1);
}

static const QQmlModuleRegistration quickshellWindowManagerRegistration("Quickshell.WindowManager", qml_register_types_Quickshell_WindowManager);
