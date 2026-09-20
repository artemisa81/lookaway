pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.artemisa81.lookaway"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.artemisa81.lookaway") : null

  function configureService() {
    if (!root.service)
      return
    root.service.configure({
      enabled: root.setting("enabled", true),
      demo: root.setting("demo", false),
      comfortDeg: root.setting("comfortDeg", 15),
      fullCoverDeg: root.setting("fullCoverDeg", 33),
      dimStrength: root.setting("dimStrength", 0.92),
      mac: root.setting("mac", ""),
      startVariant: root.setting("startVariant", "auto")
    })
  }

  onServiceChanged: configureService()
  onSettingsChanged: configureService()
  Component.onCompleted: configureService()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.service && root.service.active ? "◉" : "○"
    active: root.service ? root.service.active : false
    dimmed: !(root.service && root.service.enabled)
    tooltipText: root.service
      ? ("LookAway: " + root.service.stateLabel + " — left click toggle, right click recenter")
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
