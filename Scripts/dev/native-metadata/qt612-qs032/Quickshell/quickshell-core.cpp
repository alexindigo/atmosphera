/****************************************************************************
** Generated QML type registration code
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtQml/qqml.h>
#include <QtQml/qqmlmoduleregistration.h>

#if __has_include(<boundcomponent.hpp>)
#  include <boundcomponent.hpp>
#endif
#if __has_include(<clock.hpp>)
#  include <clock.hpp>
#endif
#if __has_include(<colorquantizer.hpp>)
#  include <colorquantizer.hpp>
#endif
#if __has_include(<desktopentry.hpp>)
#  include <desktopentry.hpp>
#endif
#if __has_include(<easingcurve.hpp>)
#  include <easingcurve.hpp>
#endif
#if __has_include(<elapsedtimer.hpp>)
#  include <elapsedtimer.hpp>
#endif
#if __has_include(<lazyloader.hpp>)
#  include <lazyloader.hpp>
#endif
#if __has_include(<model.hpp>)
#  include <model.hpp>
#endif
#if __has_include(<persistentprops.hpp>)
#  include <persistentprops.hpp>
#endif
#if __has_include(<popupanchor.hpp>)
#  include <popupanchor.hpp>
#endif
#if __has_include(<qmlglobal.hpp>)
#  include <qmlglobal.hpp>
#endif
#if __has_include(<qmlscreen.hpp>)
#  include <qmlscreen.hpp>
#endif
#if __has_include(<qsmenu.hpp>)
#  include <qsmenu.hpp>
#endif
#if __has_include(<qsmenuanchor.hpp>)
#  include <qsmenuanchor.hpp>
#endif
#if __has_include(<region.hpp>)
#  include <region.hpp>
#endif
#if __has_include(<reload.hpp>)
#  include <reload.hpp>
#endif
#if __has_include(<retainable.hpp>)
#  include <retainable.hpp>
#endif
#if __has_include(<scriptmodel.hpp>)
#  include <scriptmodel.hpp>
#endif
#if __has_include(<shell.hpp>)
#  include <shell.hpp>
#endif
#if __has_include(<singleton.hpp>)
#  include <singleton.hpp>
#endif
#if __has_include(<transformwatcher.hpp>)
#  include <transformwatcher.hpp>
#endif
#if __has_include(<types.hpp>)
#  include <types.hpp>
#endif
#if __has_include(<variants.hpp>)
#  include <variants.hpp>
#endif


#if !defined(QT_STATIC)
#define Q_QMLTYPE_EXPORT Q_DECL_EXPORT
#else
#define Q_QMLTYPE_EXPORT
#endif
Q_QMLTYPE_EXPORT void qml_register_types_Quickshell()
{
    qmlRegisterModule("Quickshell", 0, 0);
    QT_WARNING_PUSH QT_WARNING_DISABLE_DEPRECATED
    qmlRegisterTypesAndRevisions<BoundComponent>("Quickshell", 0);
    qmlRegisterAnonymousType<QQuickItem, 254>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<Box>("Quickshell", 0);
    QMetaType::fromType<Box *>().id();
    qmlRegisterTypesAndRevisions<ColorQuantizer>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<DesktopAction>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<DesktopEntries>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<DesktopEntry>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<EasingCurve>("Quickshell", 0);
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &Edges::staticMetaObject;},
            "Edges");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&Edges::staticMetaObject, "Quickshell", 0, nullptr, &Edges::staticMetaObject, nullptr);
    qmlRegisterEnum<Edges::Enum>("Edges::Enum");
    qmlRegisterEnum<Edges::Flags>("Edges::Flags");
    qmlRegisterEnum<Edges::Enum>("Edges::Enum");
    qmlRegisterTypesAndRevisions<ElapsedTimer>("Quickshell", 0);
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &Intersection::staticMetaObject;},
            "Intersection");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&Intersection::staticMetaObject, "Quickshell", 0, nullptr, &Intersection::staticMetaObject, nullptr);
    qmlRegisterEnum<Intersection::Enum>("Intersection::Enum");
    qmlRegisterTypesAndRevisions<LazyLoader>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<Margins>("Quickshell", 0);
    QMetaType::fromType<Margins *>().id();
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &ObjectComparison::staticMetaObject;},
            "ObjectComparison");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&ObjectComparison::staticMetaObject, "Quickshell", 0, nullptr, &ObjectComparison::staticMetaObject, nullptr);
    qmlRegisterEnum<ObjectComparison::Enum>("ObjectComparison::Enum");
    qmlRegisterTypesAndRevisions<PendingRegion>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<PersistentProperties>("Quickshell", 0);
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &PopupAdjustment::staticMetaObject;},
            "PopupAdjustment");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&PopupAdjustment::staticMetaObject, "Quickshell", 0, nullptr, &PopupAdjustment::staticMetaObject, nullptr);
    qmlRegisterEnum<PopupAdjustment::Enum>("PopupAdjustment::Enum");
    qmlRegisterEnum<PopupAdjustment::Flags>("PopupAdjustment::Flags");
    qmlRegisterEnum<PopupAdjustment::Enum>("PopupAdjustment::Enum");
    qmlRegisterTypesAndRevisions<PopupAnchor>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<PostReloadHook>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<QuickshellGlobal>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<QuickshellScreenInfo>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<QuickshellSettings>("Quickshell", 0);
    {
        Q_CONSTINIT static auto metaType = QQmlPrivate::metaTypeForNamespace(
            [](const QtPrivate::QMetaTypeInterface *) {return &RegionShape::staticMetaObject;},
            "RegionShape");
        QMetaType(&metaType).id();
    }
    qmlRegisterNamespaceAndRevisions(&RegionShape::staticMetaObject, "Quickshell", 0, nullptr, &RegionShape::staticMetaObject, nullptr);
    qmlRegisterEnum<RegionShape::Enum>("RegionShape::Enum");
    qmlRegisterTypesAndRevisions<ReloadPropagator>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<Reloadable>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<RetainableHook>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<RetainableLock>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<ScriptModel>("Quickshell", 0);
    qmlRegisterAnonymousType<QAbstractItemModel, 254>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<ShellRoot>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<Singleton>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<SystemClock>("Quickshell", 0);
    qmlRegisterEnum<SystemClock::Enum>("SystemClock::Enum");
    qmlRegisterTypesAndRevisions<TransformWatcher>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<UntypedObjectModel>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<Variants>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<qs::menu::QsMenuAnchor>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<qs::menu::QsMenuButtonType>("Quickshell", 0);
    qmlRegisterEnum<qs::menu::QsMenuButtonType::Enum>("qs::menu::QsMenuButtonType::Enum");
    qmlRegisterTypesAndRevisions<qs::menu::QsMenuEntry>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<qs::menu::QsMenuHandle>("Quickshell", 0);
    qmlRegisterTypesAndRevisions<qs::menu::QsMenuOpener>("Quickshell", 0);
    QT_WARNING_POP
    qmlRegisterModule("Quickshell", 0, 1);
}

static const QQmlModuleRegistration quickshellRegistration("Quickshell", qml_register_types_Quickshell);
