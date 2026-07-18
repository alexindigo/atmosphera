import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // ——— Data model values (read from widgetData, written to settingsChanged) ———
  property string valueAppId: widgetData?.appId ?? ""
  property string valueCustomLabel: widgetData?.customLabel ?? ""

  // Params (Docker-style list of strings, for flags like ["-e", "neomutt"])
  property var valueParams: widgetData?.params ?? []

  // Icon
  property string valueIconSource: widgetData?.iconSource ?? ""
  property string valueIconType: widgetData?.iconType ?? "auto"

  // Display
  property bool valueShowLabel: widgetData?.showLabel === true
  property bool valueSingleClick: widgetData?.singleClick !== false
  property bool valueShowBg: widgetData?.showBackground !== false
  property bool valueRounded: widgetData?.roundedCorners !== false

  // Appearance
  property var valueEnvVars: widgetData?.environmentVars ?? []
  property real valueContentPadding: widgetData?.contentPadding ?? Settings.data.desktopWidgets.widgetContentPadding
  property real valueBlendStrength: widgetData?.blendStrength ?? Settings.data.desktopWidgets.iconBlendStrength
  property real valueHueAdjustment: widgetData?.hueAdjustment ?? Settings.data.desktopWidgets.iconHueAdjustment

  // Only show the terminal/command-mode toggle during creation (not edit).
  readonly property bool isCreateMode: (widgetData?.appId ?? "") === ""
  property bool valueTerminalMode: false

  // ——— Merged icon list (hicolor/scalable/apps, local overrides system) ———
  property var _mergedIcons: []
  property bool _iconsReady: false

  function _buildIconsFromFind() {
    var lines = _iconFindProcess.stdout.text.trim().split('\n').filter(function (l) { return l; });
    var seen = {};
    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].trim();
      if (!p)
        continue;
      var name = p.substring(p.lastIndexOf('/') + 1);
      if (!seen[name])
        seen[name] = p;
    }
    var names = Object.keys(seen).sort();
    _mergedIcons = names.map(function (n) { return { name: n, path: seen[n] }; });
    _iconsReady = true;
  }

  Process {
    id: _iconFindProcess
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (exitCode) {
      if (exitCode === 0) root._buildIconsFromFind();
    }
  }

  // ——— App list model (all installed apps) ———
  ListModel {
    id: appListModel
  }

  function rebuildAppList() {
    appListModel.clear();
    var apps = (DesktopEntries.applications.values || []).filter(a => a && !a.noDisplay && !a.hidden).sort((a, b) => (a.name || "").localeCompare(b.name || ""));
    for (var i = 0; i < apps.length; i++) {
      appListModel.append({
                            key: apps[i].id,
                            name: apps[i].name || apps[i].id
                          });
    }
  }

  // ——— Terminal list model (installed terminals only) ———
  ListModel {
    id: terminalListModel
  }

  function rebuildTerminalList() {
    terminalListModel.clear();
    var terminals = TerminalRegistry.getInstalledTerminals();
    for (var i = 0; i < terminals.length; i++) {
      terminalListModel.append({
                                 key: terminals[i].id,
                                 name: terminals[i].name
                               });
    }
  }

  // ——— Params list model (docker-style editable list) ———
  ListModel {
    id: paramsModel
  }

  function rebuildParamsModel() {
    paramsModel.clear();
    var arr = root.valueParams || [];
    for (var i = 0; i < arr.length; i++) {
      paramsModel.append({
                           value: String(arr[i])
                         });
    }
  }

  // ——— Env vars list model ———
  ListModel {
    id: envVarsModel
  }

  function rebuildEnvVarsModel() {
    envVarsModel.clear();
    var vars = root.valueEnvVars || [];
    for (var i = 0; i < vars.length; i++) {
      var v = vars[i];
      envVarsModel.append({
                            key: v.key || "",
                            value: v.value || ""
                          });
    }
  }

  function tryAutoIconForCommand() {
    if (!(root.isCreateMode && root.valueTerminalMode)) return;
    if (valueIconType !== "auto") return;
    if (!_iconsReady) return;

    var cmd = "";
    for (var i = 0; i < paramsModel.count; i++) {
      var val = String(paramsModel.get(i).value || "").trim();
      if (!val || val.startsWith("-") || val.includes("/")) continue;
      cmd = val;
      break;
    }
    if (!cmd) return;

    for (var j = 0; j < _mergedIcons.length; j++) {
      var iconName = _mergedIcons[j].name.replace(/\.svgz?$/i, "");
      if (iconName === cmd) {
        root.valueIconSource = _mergedIcons[j].path;
        root.valueIconType = "icons";
        save();
        return;
      }
    }
  }

  Component.onCompleted: {
    rebuildAppList();
    rebuildTerminalList();
    rebuildParamsModel();
    rebuildEnvVarsModel();
    var localDir = Quickshell.env("HOME") + "/.local/share/icons/hicolor/scalable/apps";
    _iconFindProcess.command = ["find", "-L", localDir, "/usr/share/icons/hicolor/scalable/apps", "-maxdepth", "1", "-type", "f", "(", "-name", "*.svg", "-o", "-name", "*.svgz", ")"];
    _iconFindProcess.running = true;
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      rebuildAppList();
    }
  }

  // ==================== MODE TOGGLE ====================

  NToggle {
    id: terminalToggle
    visible: root.isCreateMode
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.app-shortcut-terminal-mode-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-terminal-mode-description")
    checked: root.valueTerminalMode
    onToggled: c => {
      root.valueTerminalMode = c;
      // Only auto-pick a terminal if we don't already have one selected
      if (c && terminalListModel.count > 0 && !(root.valueAppId in TerminalRegistry.terminals)) {
        var firstTermId = terminalListModel.get(0).key;
        root.valueAppId = firstTermId;
        root.valueParams = TerminalRegistry.defaultRunArgs(firstTermId).slice();
        if (root.valueParams.length === 0 || root.valueParams[root.valueParams.length - 1] !== "")
          root.valueParams.push("");
        rebuildParamsModel();
      }
      save();
    }
  }

  // ==================== APPLICATION PICKER (App mode) ====================

  NHeader {
    visible: !terminalToggle.checked
    label: I18n.tr("panels.desktop-widgets.app-shortcut-application-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-application-description")
  }

  NSearchableComboBox {
    id: appCombo
    stacked: true
    Layout.fillWidth: true
    visible: !terminalToggle.checked
    model: appListModel
    placeholder: I18n.tr("panels.desktop-widgets.app-shortcut-application-placeholder")
    currentKey: root.valueAppId
    onSelected: k => {
      root.valueAppId = k;
      root.valueParams = TerminalRegistry.defaultRunArgs(k);
      rebuildParamsModel();
      save();
    }
  }

  // ==================== TERMINAL PICKER (Command mode) ====================

  NHeader {
    visible: terminalToggle.checked
    label: I18n.tr("panels.desktop-widgets.app-shortcut-terminal-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-terminal-description")
  }

  NSearchableComboBox {
    id: terminalCombo
    stacked: true
    Layout.fillWidth: true
    visible: terminalToggle.checked
    model: terminalListModel
    placeholder: I18n.tr("panels.desktop-widgets.app-shortcut-terminal-placeholder")
    currentKey: root.valueAppId
    onSelected: k => {
      root.valueAppId = k;
      root.valueParams = TerminalRegistry.defaultRunArgs(k).slice();
      // Ensure a blank slot so the user can type their command
      if (root.valueParams.length === 0 || root.valueParams[root.valueParams.length - 1] !== "")
        root.valueParams.push("");
      rebuildParamsModel();
      save();
    }
  }

  // ==================== PARAMS EDITOR ====================

  NHeader {
    visible: terminalToggle.checked
    label: I18n.tr("panels.desktop-widgets.app-shortcut-params-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-params-description")
  }

  NHeader {
    visible: !terminalToggle.checked
    label: I18n.tr("panels.desktop-widgets.app-shortcut-params-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-params-app-description")
  }

  Repeater {
    model: paramsModel

    delegate: RowLayout {
      width: parent.width
      spacing: Style.marginS

      NTextInput {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.desktop-widgets.app-shortcut-params-placeholder")
        text: model.value
        onTextChanged: {
          paramsModel.setProperty(index, "value", text);
          save();
          root.tryAutoIconForCommand();
        }
      }

      NButton {
        icon: Icon.trash
        tooltipText: I18n.tr("common.remove")
        onClicked: {
          paramsModel.remove(index);
          save();
        }
      }
    }
  }

  NButton {
    text: I18n.tr("panels.desktop-widgets.app-shortcut-params-add")
    icon: Icon.add
    onClicked: {
      paramsModel.append({
                           value: ""
                         });
    }
  }

  // ==================== ICON PICKER ====================

  NHeader {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-icon-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-icon-description")
  }

  // Icon source type toggle
  RowLayout {
    spacing: Style.marginS
    Layout.fillWidth: true

    NButton {
      text: I18n.tr("panels.desktop-widgets.app-shortcut-icon-auto")
      icon: Icon.refresh
      outlined: root.valueIconType !== "auto"
      onClicked: {
        root.valueIconType = "auto";
        root.valueIconSource = "";
        save();
      }
    }

    NButton {
      text: I18n.tr("panels.desktop-widgets.app-shortcut-icon-icons")
      icon: Icon.apps
      outlined: root.valueIconType !== "icons"
      onClicked: {
        root.valueIconType = "icons";
        root.valueIconSource = "";
        save();
        Qt.callLater(() => iconsPicker.open());
      }
    }

    NButton {
      text: I18n.tr("panels.desktop-widgets.app-shortcut-icon-file")
      icon: Icon.folderOpen
      outlined: root.valueIconType !== "file"
      onClicked: {
        root.valueIconType = "file";
        root.valueIconSource = "";
        save();
        Qt.callLater(() => filePicker.open());
      }
    }
  }

  // Icons picker — merged SVGs from hicolor/scalable/apps
  Popup {
    id: iconsPicker
    modal: true
    parent: Overlay.overlay
    width: Math.round(900 * Style.uiScaleRatio)
    height: Math.round(700 * Style.uiScaleRatio)
    anchors.centerIn: Overlay.overlay
    padding: Style.marginXL

    property string _selectedPath: ""
    property string _searchQuery: ""

    readonly property var _filteredIcons: {
      if (!_searchQuery) return root._mergedIcons;
      var q = _searchQuery.toLowerCase();
      return root._mergedIcons.filter(function (e) { return e.name.toLowerCase().includes(q); });
    }

    readonly property int _columns: 6
    readonly property int _cellW: Math.floor(grid.width / _columns)
    readonly property int _cellH: Math.round(_cellW * 0.7 + 36)

    onOpened: {
      _selectedPath = "";
      _searchQuery = "";
      searchInput.forceActiveFocus();
    }

    background: Rectangle {
      color: Color.mSurface
      radius: Style.iRadiusL
      border.color: Color.mPrimary
      border.width: Style.borderM
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        NText {
          text: I18n.tr("panels.desktop-widgets.app-shortcut-icon-icons-picker-title")
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
        }
        NIconButton {
          icon: Icon.close
          tooltipText: I18n.tr("common.close")
          onClicked: iconsPicker.close()
        }
      }

      NDivider { Layout.fillWidth: true }

      NTextInput {
        id: searchInput
        Layout.fillWidth: true
        label: I18n.tr("common.search")
        placeholderText: I18n.tr("placeholders.search-icons")
        text: iconsPicker._searchQuery
        onTextChanged: iconsPicker._searchQuery = text.trim().toLowerCase()
      }

      NGridView {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.margins: Style.marginM
        cellWidth: iconsPicker._cellW
        cellHeight: iconsPicker._cellH
        model: iconsPicker._filteredIcons
        reserveScrollbarSpace: false
        gradientColor: Color.mSurface

        delegate: Rectangle {
          width: grid.cellWidth
          height: grid.cellHeight
          radius: Style.iRadiusS
          color: (iconsPicker._selectedPath === modelData.path) ? Qt.alpha(Color.mPrimary, 0.15) : "transparent"
          border.color: (iconsPicker._selectedPath === modelData.path) ? Color.mPrimary : "transparent"
          border.width: (iconsPicker._selectedPath === modelData.path) ? Style.borderS : 0

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: iconsPicker._selectedPath = modelData.path
            onDoubleClicked: {
              root.valueIconSource = modelData.path;
              root.valueIconType = "icons";
              root.save();
              iconsPicker.close();
            }
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS

            Image {
              Layout.alignment: Qt.AlignHCenter
              Layout.preferredWidth: Math.min(grid.cellWidth - Style.marginS * 2, 48)
              Layout.preferredHeight: 32
              source: "file://" + modelData.path
              fillMode: Image.PreserveAspectFit
              smooth: true
              asynchronous: true
              sourceSize: Qt.size(48, 48)
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              Layout.fillWidth: true
              elide: Text.ElideRight
              wrapMode: Text.NoWrap
              maximumLineCount: 1
              horizontalAlignment: Text.AlignHCenter
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              text: modelData.name
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        Item { Layout.fillWidth: true }
        NButton {
          text: I18n.tr("common.cancel")
          outlined: true
          onClicked: iconsPicker.close()
        }
        NButton {
          text: I18n.tr("common.apply")
          icon: Icon.check
          enabled: iconsPicker._selectedPath !== ""
          onClicked: {
            if (iconsPicker._selectedPath) {
              root.valueIconSource = iconsPicker._selectedPath;
              root.valueIconType = "icons";
              root.save();
            }
            iconsPicker.close();
          }
        }
      }
    }
  }

  // Icon file picker popup
  NFilePicker {
    id: filePicker
    parent: Overlay.overlay
    title: I18n.tr("panels.desktop-widgets.app-shortcut-icon-file-picker-title")
    nameFilters: ["*.png", "*.svg", "*.jpg", "*.jpeg", "*.ico"]
    onAccepted: paths => {
      if (paths && paths.length > 0) {
        root.valueIconSource = paths[0];
        root.valueIconType = "file";
        save();
      }
    }
  }

  // ==================== CUSTOM LABEL ====================

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.app-shortcut-custom-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-custom-label-description")
    text: root.valueCustomLabel
    onTextChanged: {
      root.valueCustomLabel = text;
      save();
    }
  }

  // ==================== DISPLAY TOGGLES ====================

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-show-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-show-label-description")
    checked: root.valueShowLabel
    onToggled: c => {
      root.valueShowLabel = c;
      save();
    }
  }

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-single-click")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-single-click-description")
    checked: root.valueSingleClick
    onToggled: c => {
      root.valueSingleClick = c;
      save();
    }
  }

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-show-background")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-show-background-description")
    checked: root.valueShowBg
    onToggled: c => {
      root.valueShowBg = c;
      save();
    }
  }

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-rounded-corners")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-rounded-corners-description")
    checked: root.valueRounded
    onToggled: c => {
      root.valueRounded = c;
      save();
    }
  }

  // ==================== ENVIRONMENT VARIABLES ====================

  NDivider {
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NHeader {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-environment-vars-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-environment-vars-description")
  }

  Repeater {
    model: envVarsModel

    delegate: RowLayout {
      width: parent.width
      spacing: Style.marginS

      NTextInput {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.desktop-widgets.app-shortcut-env-var-key-placeholder")
        text: model.key
        onTextChanged: {
          envVarsModel.setProperty(index, "key", text);
          save();
        }
      }

      NTextInput {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.desktop-widgets.app-shortcut-env-var-value-placeholder")
        text: model.value
        onTextChanged: {
          envVarsModel.setProperty(index, "value", text);
          save();
        }
      }

      NButton {
        icon: Icon.trash
        tooltipText: I18n.tr("common.remove")
        onClicked: {
          envVarsModel.remove(index);
          save();
        }
      }
    }
  }

  NButton {
    text: I18n.tr("panels.desktop-widgets.app-shortcut-env-var-add")
    icon: Icon.add
    onClicked: {
      envVarsModel.append({
                            key: "",
                            value: ""
                          });
    }
  }

  // ==================== APPEARANCE (shared) ====================

  AtmoWidgetAppearance {
    blendStrength: root.valueBlendStrength
    blendStrengthDefault: Settings.data.desktopWidgets.iconBlendStrength
    onBlendStrengthEdited: v => {
      root.valueBlendStrength = v;
      save();
    }

    hueAdjustment: root.valueHueAdjustment
    hueAdjustmentDefault: Settings.data.desktopWidgets.iconHueAdjustment
    onHueAdjustmentEdited: v => {
      root.valueHueAdjustment = v;
      save();
    }

    contentPadding: root.valueContentPadding
    contentPaddingDefault: Settings.data.desktopWidgets.widgetContentPadding
    onContentPaddingEdited: v => {
      root.valueContentPadding = v;
      save();
    }
  }

  // ==================== SAVE ====================

  function save() {
    // Serialize params model to array
    var params = [];
    for (var i = 0; i < paramsModel.count; i++) {
      var p = paramsModel.get(i);
      if (p.value && p.value.trim() !== "") {
        params.push(p.value.trim());
      }
    }

    // Serialize env vars model to array
    var envVars = [];
    for (var i = 0; i < envVarsModel.count; i++) {
      var item = envVarsModel.get(i);
      if (item.key && item.key.trim() !== "") {
        envVars.push({
                       key: item.key.trim(),
                       value: item.value
                     });
      }
    }

    settingsChanged({
                      appId: valueAppId,
                      customLabel: valueCustomLabel,
                      params: params,
                      iconSource: valueIconSource,
                      iconType: valueIconType,
                      showLabel: valueShowLabel,
                      singleClick: valueSingleClick,
                      showBackground: valueShowBg,
                      roundedCorners: valueRounded,
                      environmentVars: envVars,
                      blendStrength: valueBlendStrength,
                      hueAdjustment: valueHueAdjustment,
                      contentPadding: valueContentPadding
                    });
  }
}
