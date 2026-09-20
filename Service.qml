import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Injected by omarchy-shell for service plugins.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  // ---------------------------------------------------------------- settings
  property bool enabled: true
  property bool demo: false
  property real comfortDeg: 15
  property real fullCoverDeg: 33
  property real dimStrength: 0.92
  property string airpodsMac: ""
  property string startVariant: "auto"

  // ------------------------------------------------------------- sensor state
  property bool connected: false
  property real yaw: 0
  property real pitch: 0
  property real roll: 0
  property real lastSampleMs: 0

  // calibration: the orientation that points at the screen
  property real centerYaw: 0
  property real centerPitch: 0
  property bool calibrated: false

  // manual angle override for testing; NaN disables the override
  property real manualAngle: NaN

  readonly property string helperPath: Qt.resolvedUrl("bin/lookaway-sensor").toString().replace("file://", "")

  function configure(options) {
    var value = options || ({})
    if (value.enabled !== undefined) root.enabled = value.enabled !== false
    if (value.demo !== undefined) root.demo = value.demo === true
    if (value.comfortDeg !== undefined) root.comfortDeg = Util.clamp(Number(value.comfortDeg) || 15, 2, 30)
    if (value.fullCoverDeg !== undefined) root.fullCoverDeg = Util.clamp(Number(value.fullCoverDeg) || 33, root.comfortDeg + 1, 60)
    if (value.dimStrength !== undefined) root.dimStrength = Util.clamp(Number(value.dimStrength) || 0.92, 0.1, 1)
    if (value.mac !== undefined) root.airpodsMac = String(value.mac || "")
    if (value.startVariant !== undefined) {
      var variant = String(value.startVariant || "auto")
      root.startVariant = (variant === "alt" || variant === "def") ? variant : "auto"
    }
  }

  // --------------------------------------------------------------- geometry
  readonly property real normalizedYaw: {
    var d = root.yaw - root.centerYaw
    while (d > 180) d -= 360
    while (d < -180) d += 360
    return d
  }

  readonly property real normalizedPitch: root.pitch - root.centerPitch

  // Schmitt-trigger on the comfort boundary: engage once the offset passes
  // `comfortDeg`, but only release once it drops `hysteresisDeg` below, so a
  // head resting near the threshold cannot flicker the scrim on and off.
  property real hysteresisDeg: 2
  property bool engaged: false

  onOffsetAngleChanged: {
    if (root.offsetAngle > root.comfortDeg)
      root.engaged = true
    else if (root.offsetAngle < root.comfortDeg - root.hysteresisDeg)
      root.engaged = false
  }

  readonly property real effectiveComfort: root.engaged
    ? Math.max(1, root.comfortDeg - root.hysteresisDeg)
    : root.comfortDeg

  readonly property real offsetAngle: isNaN(root.manualAngle)
    ? Math.sqrt(root.normalizedYaw * root.normalizedYaw + root.normalizedPitch * root.normalizedPitch)
    : root.manualAngle

  readonly property real cover: {
    if (!root.enabled)
      return 0
    if (!root.connected && isNaN(root.manualAngle))
      return 0
    var a = root.offsetAngle
    var lo = root.effectiveComfort
    if (a <= lo)
      return 0
    if (a >= root.fullCoverDeg)
      return 1
    return (a - lo) / (root.fullCoverDeg - lo)
  }

  readonly property real scrimOpacity: root.cover * root.dimStrength
  readonly property bool active: root.cover > 0.001
  readonly property string stateLabel: !root.enabled
    ? "off"
    : (root.demo ? "demo" : (root.connected ? "listening" : "waiting"))

  function recenter() {
    root.centerYaw = root.yaw
    root.centerPitch = root.pitch
    root.calibrated = true
    return "recentered"
  }

  function setEnabled(on) {
    root.enabled = (on === true || on === "true" || on === "on")
    return root.enabled ? "on" : "off"
  }

  function toggle() {
    root.enabled = !root.enabled
    return root.enabled ? "on" : "off"
  }

  function setDemo(on) {
    root.demo = (on === true || on === "true" || on === "on")
    return root.demo ? "demo-on" : "demo-off"
  }

  function parseSample(line) {
    try {
      var sample = JSON.parse(String(line).trim())
      if (!sample)
        return
      root.connected = sample.connected === true
      if (typeof sample.yaw === "number")
        root.yaw = sample.yaw
      if (typeof sample.pitch === "number")
        root.pitch = sample.pitch
      if (typeof sample.roll === "number")
        root.roll = sample.roll
      root.lastSampleMs = Date.now()
      if (root.connected && (sample.recal === true || !root.calibrated)) {
        root.centerYaw = root.yaw
        root.centerPitch = root.pitch
        root.calibrated = true
      }
    } catch (error) {
      // ignore malformed samples
    }
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.enabled,
      demo: root.demo,
      connected: root.connected,
      calibrated: root.calibrated,
      yaw: Math.round(root.normalizedYaw * 10) / 10,
      pitch: Math.round(root.normalizedPitch * 10) / 10,
      offset: Math.round(root.offsetAngle * 10) / 10,
      comfortDeg: root.comfortDeg,
      fullCoverDeg: root.fullCoverDeg,
      cover: Math.round(root.cover * 1000) / 1000,
      active: root.active
    })
  }

  // ------------------------------------------------------------ sensor input
  property bool sensorHolding: false
  readonly property bool sensorWanted: root.enabled && !root.sensorHolding
  readonly property var sensorCommand: {
    var command = ["python3", root.helperPath]
    if (root.demo)
      command.push("--demo")
    else {
      command.push("--start", root.startVariant)
      if (root.airpodsMac)
        command.push("--mac", root.airpodsMac)
    }
    return command
  }

  // Restart the feed when the mode changes, so toggling demo swaps the process.
  function restartSensor() {
    root.sensorHolding = true
    Qt.callLater(function() { root.sensorHolding = false })
  }

  onDemoChanged: restartSensor()
  onAirpodsMacChanged: restartSensor()
  onStartVariantChanged: restartSensor()

  Process {
    id: sensor
    running: root.sensorWanted
    command: root.sensorCommand
    stdout: SplitParser {
      onRead: function(line) {
        root.parseSample(line)
      }
    }
    onExited: function(exitCode) {
      root.connected = false
      sensorRestart.restart()
    }
  }

  // The feed loops and reconnects internally; this only catches an unexpected
  // exit (e.g. a crash) and brings it back without a shell restart.
  Timer {
    id: sensorRestart
    interval: 2000
    onTriggered: root.restartSensor()
  }

  Timer {
    interval: 500
    repeat: true
    running: root.connected
    onTriggered: {
      if (Date.now() - root.lastSampleMs > 1500)
        root.connected = false
    }
  }

  // ---------------------------------------------------------------- scrim UI
  // Latch the layer surface open past the end of the fade so the opacity
  // animation has something to play on; hiding the window at cover 0 would
  // otherwise cut the fade-out short.
  property bool overlayLatched: false

  onCoverChanged: {
    if (root.cover > 0.001) {
      root.overlayLatched = true
      hideLatcher.stop()
    } else {
      hideLatcher.restart()
    }
  }

  Timer {
    id: hideLatcher
    interval: 260
    onTriggered: root.overlayLatched = false
  }

  // One passive, click-through, fullscreen layer surface per output. Hyprland
  // blurs the backdrop of this layer (see ~/.config/hypr/lookaway.lua), so the
  // screen softens without ever capturing its contents.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: scrim
      required property var modelData
      screen: modelData
      visible: root.overlayLatched
      color: "transparent"

      WlrLayershell.namespace: "lookaway-scrim"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region {}

      // Early phase (cover 0..0.5): the side opposite the turn fills in.
      Rectangle {
        anchors.fill: parent
        opacity: Util.clamp(root.cover * 2, 0, 1) * root.dimStrength
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: Util.alpha(Color.background, root.normalizedYaw >= 0 ? 1 : 0) }
          GradientStop { position: 1; color: Util.alpha(Color.background, root.normalizedYaw >= 0 ? 0 : 1) }
        }
      }

      // Late phase (cover 0.5..1): the whole display settles under the scrim.
      Rectangle {
        anchors.fill: parent
        opacity: Util.clamp((root.cover - 0.5) * 2, 0, 1) * root.dimStrength
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        color: Color.background
      }
    }
  }

  // -------------------------------------------------------------------- IPC
  IpcHandler {
    target: "lookaway"

    function enable(): string { return root.setEnabled(true) }
    function disable(): string { return root.setEnabled(false) }
    function toggle(): string { return root.toggle() }
    function recenter(): string { return root.recenter() }
    function status(): string { return root.statusJson() }
    function demo(on: string): string { return root.setDemo(on) }

    function comfort(deg: string): string {
      root.comfortDeg = Util.clamp(Number(deg) || 15, 2, 30)
      if (root.fullCoverDeg <= root.comfortDeg)
        root.fullCoverDeg = Math.min(60, root.comfortDeg + 1)
      return "" + root.comfortDeg
    }

    function full(deg: string): string {
      root.fullCoverDeg = Util.clamp(Number(deg) || 33, root.comfortDeg + 1, 60)
      return "" + root.fullCoverDeg
    }

    function test(deg: string): string {
      if (deg === "" || deg === "off" || Number(deg) < 0)
        root.manualAngle = NaN
      else
        root.manualAngle = Math.max(0, Number(deg))
      return isNaN(root.manualAngle) ? "test-off" : ("" + root.manualAngle)
    }
  }
}
