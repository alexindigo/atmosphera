/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<cliprect.hpp>)
#  include <cliprect.hpp>
#endif
#if __has_include(<marginwrapper.hpp>)
#  include <marginwrapper.hpp>
#endif
#if __has_include(<wrapper.hpp>)
#  include <wrapper.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell_Widgets()
{
    qmlRegisterModule("Quickshell.Widgets", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<ClippingRectangleBorder>("Quickshell.Widgets", 0);
    QMetaType::fromType<ClippingRectangleBorder *>().id();
    qmlRegisterTypesAndRevisions<qs::widgets::MarginWrapperManager>("Quickshell.Widgets", 0);
    qmlRegisterTypesAndRevisions<qs::widgets::WrapperManager>("Quickshell.Widgets", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell.Widgets", 0, 1);
}

static const QQmlModuleRegistration quickshellWidgetsRegistration("Quickshell.Widgets", qml_register_types_Quickshell_Widgets);
