pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 artemisa81

Panel {
  id: root
  moduleName: "io.github.artemisa81.lookaway"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.artemisa81.lookaway") : null

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(root.foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool currentEnabled: root.service ? root.service.enabled : root.boolSetting("enabled", true)
  readonly property bool currentDemo: root.service ? root.service.demo : root.boolSetting("demo", false)
  readonly property bool currentFailSafe: root.service ? root.service.failSafe : root.boolSetting("failSafe", false)
  readonly property real currentComfort: root.service ? root.service.comfortDeg : root.numberSetting("comfortDeg", 15)
  readonly property real currentFullCover: root.service ? root.service.fullCoverDeg : root.numberSetting("fullCoverDeg", 33)
  readonly property real currentDimStrength: root.service ? root.service.dimStrength : root.numberSetting("dimStrength", 0.92)
  readonly property real currentHysteresis: root.service ? root.service.hysteresisDeg : root.numberSetting("hysteresisDeg", 2)
  readonly property real currentSmoothing: root.service ? root.service.smoothingMs : root.numberSetting("smoothingMs", 140)
  readonly property string currentMac: root.service ? root.service.airpodsMac : String(root.setting("mac", ""))
  readonly property string currentStartVariant: root.service
    ? root.service.startVariant : String(root.setting("startVariant", "auto"))

  function boolSetting(name, fallback) {
    var value = root.setting(name, fallback)
    if (value === true || value === "true" || value === "on" || value === 1 || value === "1")
      return true
    if (value === false || value === "false" || value === "off" || value === 0 || value === "0")
      return false
    return fallback
  }

  function numberSetting(name, fallback) {
    var value = Number(root.setting(name, fallback))
    return isFinite(value) ? value : fallback
  }

  function snap(value, minimum, maximum, step) {
    var next = Number(value)
    if (!isFinite(next)) next = minimum
    next = minimum + Math.round((next - minimum) / step) * step
    var precision = step < 1 ? 2 : 0
    next = Number(next.toFixed(precision))
    return Math.max(minimum, Math.min(maximum, next))
  }

  function saveSlider(key, value, minimum, maximum, step) {
    var actualMinimum = minimum
    if (key === "fullCoverDeg")
      actualMinimum = root.currentComfort + 1

    var next = root.snap(value, actualMinimum, maximum, step)
    var changes = ({})
    changes[key] = next

    // Keep the cover ramp valid if the comfort boundary moves past it.
    if (key === "comfortDeg" && root.currentFullCover <= next)
      changes.fullCoverDeg = Math.min(60, next + 1)

    root.persistSettings(changes)
  }

  function configureService() {
    if (!root.service)
      return
    root.service.persistSettings = function(changes) { root.persistSettings(changes) }
    root.service.configure({
      enabled: root.setting("enabled", true),
      demo: root.setting("demo", false),
      comfortDeg: root.setting("comfortDeg", 15),
      fullCoverDeg: root.setting("fullCoverDeg", 33),
      dimStrength: root.setting("dimStrength", 0.92),
      failSafe: root.setting("failSafe", false),
      hysteresisDeg: root.setting("hysteresisDeg", 2),
      smoothingMs: root.setting("smoothingMs", 140),
      mac: root.setting("mac", ""),
      startVariant: root.setting("startVariant", "auto")
    })

    var fixes = ({})
    var requestedFull = Number(root.setting("fullCoverDeg", 33))
    if (!isFinite(requestedFull) || requestedFull !== root.service.fullCoverDeg)
      fixes.fullCoverDeg = root.service.fullCoverDeg
    var requestedHysteresis = Number(root.setting("hysteresisDeg", 2))
    if (!isFinite(requestedHysteresis) || requestedHysteresis !== root.service.hysteresisDeg)
      fixes.hysteresisDeg = root.service.hysteresisDeg
    var requestedSmoothing = Number(root.setting("smoothingMs", 140))
    if (!isFinite(requestedSmoothing) || requestedSmoothing !== root.service.smoothingMs)
      fixes.smoothingMs = root.service.smoothingMs
    if (Object.keys(fixes).length > 0)
      root.persistSettings(fixes)
  }

  function persistSettings(changes) {
    var entry = { id: root.moduleName }
    var current = root.settings || ({})
    for (var existing in current) {
      if (existing !== "id") entry[existing] = current[existing]
    }
    for (var key in changes || ({})) entry[key] = changes[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  onServiceChanged: configureService()
  onSettingsChanged: configureService()
  Component.onCompleted: configureService()
  Component.onDestruction: {
    if (root.service)
      root.service.persistSettings = null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.service && root.service.sensorWarning ? "!"
      : (root.service && root.service.active ? "◉" : "○")
    active: root.service ? root.service.active : false
    dimmed: !(root.service && root.service.enabled)
    tooltipText: root.service
      ? ("LookAway: " + root.service.stateLabel
        + (root.service.sensorWarning ? " — sensor unavailable" : "")
        + " — left toggle, right recenter, middle settings")
      : "LookAway — middle click for settings"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        root.open()
        return
      }
      if (!root.service) return
      if (mouseButton === Qt.RightButton)
        root.service.recenter()
      else
        root.service.toggle()
    }
  }

  KeyboardPanel {
    id: settingsPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: settingsPanel.fittedContentWidth(Style.space(390))
    contentHeight: settingsPanel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      Flickable {
        id: settingsScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentColumn
          width: settingsScroll.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "LookAway"
            meta: root.service ? root.service.stateLabel : "starting"
            detail: root.currentDemo ? "demo" : (root.service && root.service.connected ? "connected" : "offline")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.service && root.service.active ? "◉" : "○"
                color: root.service && root.service.active ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                checked: root.currentEnabled
                foreground: root.foreground
                accent: root.accent
                onToggled: root.persistSettings({ enabled: !root.currentEnabled })
              }
            }
          }

          Text {
            visible: root.service && root.service.sensorWarning
            width: parent.width
            text: root.service && root.service.sensorError !== ""
              ? root.service.sensorError : "AirPods sensor unavailable"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Toggle {
              width: parent.width
              label: "Demo feed"
              description: "Preview the shield without connecting AirPods."
              checked: root.currentDemo
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ demo: !root.currentDemo })
            }

            Toggle {
              width: parent.width
              label: "Fail-safe cover"
              description: "Cover the screen after a live sensor session is lost."
              checked: root.currentFailSafe
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ failSafe: !root.currentFailSafe })
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(comfortHeader.implicitHeight, comfortValue.implicitHeight)

              PanelSectionHeader {
                id: comfortHeader
                text: "COMFORT ZONE"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: comfortValue
                text: Math.round(comfortSlider.dragging ? comfortSlider.liveValue : root.currentComfort) + " deg"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: comfortSlider
              width: parent.width
              bar: root.bar
              minimum: 2
              maximum: 30
              step: 1
              integer: true
              value: root.currentComfort
              onReleased: function(value) { root.saveSlider("comfortDeg", value, 2, 30, 1) }
            }

            Text {
              width: parent.width
              text: "Movement inside this angle is ignored. Lower it to engage sooner."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(fullCoverHeader.implicitHeight, fullCoverValue.implicitHeight)

              PanelSectionHeader {
                id: fullCoverHeader
                text: "FULL COVER"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: fullCoverValue
                text: Math.round(fullCoverSlider.dragging ? fullCoverSlider.liveValue : root.currentFullCover) + " deg"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: fullCoverSlider
              width: parent.width
              bar: root.bar
              minimum: Math.min(59, root.currentComfort + 1)
              maximum: 60
              step: 1
              integer: true
              value: root.currentFullCover
              onReleased: function(value) { root.saveSlider("fullCoverDeg", value, fullCoverSlider.minimum, 60, 1) }
            }

            Text {
              width: parent.width
              text: "The screen reaches full cover at this angle."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(dimHeader.implicitHeight, dimValue.implicitHeight)

              PanelSectionHeader {
                id: dimHeader
                text: "SCRIM STRENGTH"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: dimValue
                text: Math.round((dimSlider.dragging ? dimSlider.liveValue : root.currentDimStrength) * 100) + "%"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: dimSlider
              width: parent.width
              bar: root.bar
              minimum: 0.1
              maximum: 1
              step: 0.05
              value: root.currentDimStrength
              onReleased: function(value) { root.saveSlider("dimStrength", value, 0.1, 1, 0.05) }
            }

            Text {
              width: parent.width
              text: "Maximum opacity of the directional and full-screen scrims."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(hysteresisHeader.implicitHeight, hysteresisValue.implicitHeight)

              PanelSectionHeader {
                id: hysteresisHeader
                text: "THRESHOLD HYSTERESIS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: hysteresisValue
                text: Number(hysteresisSlider.dragging ? hysteresisSlider.liveValue : root.currentHysteresis).toFixed(1) + " deg"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: hysteresisSlider
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 8
              step: 0.5
              value: root.currentHysteresis
              onReleased: function(value) { root.saveSlider("hysteresisDeg", value, 0, 8, 0.5) }
            }

            Text {
              width: parent.width
              text: "Extra release margin near the comfort boundary; 0 is most sensitive."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(smoothingHeader.implicitHeight, smoothingValue.implicitHeight)

              PanelSectionHeader {
                id: smoothingHeader
                text: "VISUAL SMOOTHING"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: smoothingValue
                text: Math.round((smoothingSlider.dragging ? smoothingSlider.liveValue : root.currentSmoothing) / 10) * 10 + " ms"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: smoothingSlider
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 500
              step: 10
              integer: true
              value: root.currentSmoothing
              onReleased: function(value) { root.saveSlider("smoothingMs", value, 0, 500, 10) }
            }

            Text {
              width: parent.width
              text: "Fade duration only; lower is faster and higher is calmer."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "AIRPODS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: macField
              width: parent.width
              text: root.currentMac
              placeholderText: "MAC address (optional; auto-detect)"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              onEditingFinished: root.persistSettings({ mac: text.trim() })
            }

            Dropdown {
              width: parent.width
              label: "Head-tracking start packet"
              value: root.currentStartVariant
              options: [
                { value: "auto", label: "Auto (recommended)" },
                { value: "alt", label: "Alternative packet" },
                { value: "def", label: "Default packet" }
              ]
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(value) { root.persistSettings({ startVariant: value }) }
            }

            Text {
              width: parent.width
              text: "Leave the MAC empty to find a paired device named AirPods."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Recenter"
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.recenter()
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Done"
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.close()
            }
          }
        }
      }
    }
  }
}
