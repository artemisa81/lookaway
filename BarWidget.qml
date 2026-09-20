pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 artemisa81

// The bar entry point owns the button and forwards the shell's panel lifecycle
// to the nested settings panel.
BarWidget {
  id: root
  moduleName: "io.github.artemisa81.lookaway"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.artemisa81.lookaway") : null

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

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
}
