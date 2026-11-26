/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<floatingwindow.hpp>)
#  include <floatingwindow.hpp>
#endif
#if __has_include(<panelinterface.hpp>)
#  include <panelinterface.hpp>
#endif
#if __has_include(<popupwindow.hpp>)
#  include <popupwindow.hpp>
#endif
#if __has_include(<windowinterface.hpp>)
#  include <windowinterface.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell__Window()
{
    qmlRegisterModule("Quickshell._Window", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<Anchors>("Quickshell._Window", 0);
    QMetaType::fromType<Anchors *>().id();
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &ExclusionMode::staticMetaObject;},
            "ExclusionMode");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&ExclusionMode::staticMetaObject, "Quickshell._Window", 0, nullptr, &ExclusionMode::staticMetaObject, nullptr);
    qmlRegisterEnum<ExclusionMode::Enum>("ExclusionMode::Enum");
    qmlRegisterTypesAndRevisions<FloatingWindowInterface>("Quickshell._Window", 0);
    qmlRegisterTypesAndRevisions<PanelWindowInterface>("Quickshell._Window", 0);
    qmlRegisterTypesAndRevisions<ProxyPopupWindow>("Quickshell._Window", 0);
    QMetaType::fromType<ProxyWindowBase *>().id();
    qmlRegisterTypesAndRevisions<QsSurfaceFormat>("Quickshell._Window", 0);
    QMetaType::fromType<QsSurfaceFormat *>().id();
    qmlRegisterTypesAndRevisions<QsWindowAttached>("Quickshell._Window", 0);
    qmlRegisterTypesAndRevisions<WindowInterface>("Quickshell._Window", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell._Window", 0, 1);
}

static const QQmlModuleRegistration quickshellWindowRegistration("Quickshell._Window", qml_register_types_Quickshell__Window);
