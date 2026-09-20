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
        + " — left click toggle, right click recenter")
      : "LookAway"
    onPressed: function(mouseButton) {
      if (!root.service)
        return
      if (mouseButton === Qt.RightButton)
        root.service.recenter()
      else
        root.service.toggle()
    }
  }
}
