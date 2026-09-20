import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 artemisa81

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
  property bool failSafe: false
  property real hysteresisDeg: 2
  property int smoothingMs: 140
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
  property bool everConnected: false
  property string sensorPhase: "starting"
  property string sensorError: ""

  // manual angle override for testing; NaN disables the override
  property real manualAngle: NaN

  property var persistSettings: null

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      value = value.slice(7)
    try {
      return decodeURIComponent(value)
    } catch (error) {
      return value
    }
  }

  readonly property string helperPath: root.localPath(Qt.resolvedUrl("bin/lookaway-sensor"))

  function boolValue(value, fallback) {
    if (value === true || value === "true" || value === 1 || value === "1" || value === "on")
      return true
    if (value === false || value === "false" || value === 0 || value === "0" || value === "off")
      return false
    return fallback
  }

  function finiteNumber(value, fallback) {
    var number = Number(value)
    return isFinite(number) ? number : fallback
  }

  function configure(options) {
    var value = options || ({})
    if (value.enabled !== undefined) root.enabled = root.boolValue(value.enabled, true)
    if (value.demo !== undefined) root.demo = root.boolValue(value.demo, false)
    if (value.comfortDeg !== undefined)
      root.comfortDeg = Util.clamp(root.finiteNumber(value.comfortDeg, 15), 2, 30)
    if (value.fullCoverDeg !== undefined)
      root.fullCoverDeg = Util.clamp(root.finiteNumber(value.fullCoverDeg, 33), root.comfortDeg + 1, 60)
    if (value.dimStrength !== undefined)
      root.dimStrength = Util.clamp(root.finiteNumber(value.dimStrength, 0.92), 0.1, 1)
    if (value.failSafe !== undefined) root.failSafe = root.boolValue(value.failSafe, false)
    if (value.hysteresisDeg !== undefined)
      root.hysteresisDeg = Util.clamp(root.finiteNumber(value.hysteresisDeg, 2), 0, 8)
    if (value.smoothingMs !== undefined)
      root.smoothingMs = Util.clamp(Math.round(root.finiteNumber(value.smoothingMs, 140)), 0, 500)
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
  property bool engaged: false

  readonly property real effectiveHysteresis: Math.min(root.hysteresisDeg,
    Math.max(0, root.comfortDeg - 1))

  function updateEngaged() {
    if (root.offsetAngle > root.comfortDeg)
      root.engaged = true
    else if (root.offsetAngle < root.comfortDeg - root.effectiveHysteresis)
      root.engaged = false
  }

  onOffsetAngleChanged: root.updateEngaged()
  onComfortDegChanged: root.updateEngaged()
  onHysteresisDegChanged: root.updateEngaged()

  readonly property real effectiveComfort: root.engaged
    ? Math.max(1, root.comfortDeg - root.effectiveHysteresis)
    : root.comfortDeg

  readonly property real offsetAngle: isNaN(root.manualAngle)
    ? Math.sqrt(root.normalizedYaw * root.normalizedYaw + root.normalizedPitch * root.normalizedPitch)
    : root.manualAngle

  readonly property real cover: {
    if (!root.enabled)
      return 0
    if (!root.connected && isNaN(root.manualAngle))
      return root.failSafe && root.everConnected ? 1 : 0
    var a = root.offsetAngle
    var lo = root.effectiveComfort
    if (a <= lo)
      return 0
    if (a >= root.fullCoverDeg)
      return 1
    return (a - lo) / (root.fullCoverDeg - lo)
  }

  // Split the two source-over rectangles so their combined opacity never
  // exceeds dimStrength at full cover.
  readonly property real directionalScrimMax: root.dimStrength * 0.5
  readonly property real fullScrimMax: {
    var remaining = 1 - root.directionalScrimMax
    return remaining > 0 ? (root.dimStrength - root.directionalScrimMax) / remaining : 1
  }
  readonly property bool active: root.cover > 0.001
  readonly property string stateLabel: !root.enabled
    ? "off"
    : (root.demo ? "demo" : (root.connected ? "listening" : root.sensorPhase))
  readonly property bool sensorWarning: root.enabled && !root.demo && !root.connected

  function recenter() {
    if (!root.connected && isNaN(root.manualAngle))
      return "not-connected"
    root.centerYaw = root.yaw
    root.centerPitch = root.pitch
    root.calibrated = true
    return "recentered"
  }

  function setEnabled(on) {
    root.enabled = (on === true || on === "true" || on === "on")
    root.saveSetting("enabled", root.enabled)
    return root.enabled ? "on" : "off"
  }

  function toggle() {
    return root.setEnabled(!root.enabled)
  }

  function setDemo(on) {
    root.demo = (on === true || on === "true" || on === "on")
    root.saveSetting("demo", root.demo)
    return root.demo ? "demo-on" : "demo-off"
  }

  function setFailSafe(on) {
    root.failSafe = (on === true || on === "true" || on === "on")
    root.saveSetting("failSafe", root.failSafe)
    return root.failSafe ? "failsafe-on" : "failsafe-off"
  }

  function setHysteresis(deg) {
    root.hysteresisDeg = Util.clamp(root.finiteNumber(deg, 2), 0, 8)
    root.saveSetting("hysteresisDeg", root.hysteresisDeg)
    return "" + root.effectiveHysteresis
  }

  function setSmoothing(ms) {
    root.smoothingMs = Util.clamp(Math.round(root.finiteNumber(ms, 140)), 0, 500)
    root.saveSetting("smoothingMs", root.smoothingMs)
    return "" + root.smoothingMs
  }

  function saveSetting(key, value) {
    if (typeof root.persistSettings !== "function")
      return
    var changes = ({})
    changes[key] = value
    root.persistSettings(changes)
  }

  function parseSample(line) {
    try {
      var sample = JSON.parse(String(line).trim())
      if (!sample)
        return
      var source = String(sample.source || "airpods")
      root.connected = sample.connected === true
      if (typeof sample.phase === "string") {
        root.sensorPhase = sample.phase
        if (sample.phase !== "error" && sample.phase !== "stalled")
          root.sensorError = ""
      }
      if (typeof sample.error === "string") root.sensorError = sample.error
      if (typeof sample.yaw === "number")
        root.yaw = sample.yaw
      if (typeof sample.pitch === "number")
        root.pitch = sample.pitch
      if (typeof sample.roll === "number")
        root.roll = sample.roll
      root.lastSampleMs = Date.now()
      if (root.connected) {
        root.sensorPhase = "listening"
        root.sensorError = ""
        if (source !== "demo") root.everConnected = true
      }
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
      active: root.active,
      phase: root.sensorPhase,
      failSafe: root.failSafe,
      hysteresisDeg: root.effectiveHysteresis,
      smoothingMs: root.smoothingMs,
      sensorWarning: root.sensorWarning,
      error: root.sensorError
    })
  }

  // ------------------------------------------------------------ sensor input
  property bool sensorHolding: false
  readonly property bool sensorWanted: root.enabled && !root.sensorHolding
  property real sensorLaunchStartedMs: Date.now()
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
    sensorRestart.stop()
    root.sensorRestarting = true
    root.sensorPendingStart = true
    if (sensor.running) {
      root.sensorExpectedStop = true
      root.sensorHolding = true
    } else {
      Qt.callLater(root.finishSensorRestart)
    }
  }

  function finishSensorRestart() {
    if (!root.sensorPendingStart)
      return
    root.sensorPendingStart = false
    root.sensorHolding = false
    root.sensorRestarting = false
  }

  property bool sensorRestarting: false
  property bool sensorExpectedStop: false
  property bool sensorPendingStart: false

  onDemoChanged: restartSensor()
  onAirpodsMacChanged: restartSensor()
  onStartVariantChanged: restartSensor()
  onSensorWantedChanged: if (root.sensorWanted) root.sensorLaunchStartedMs = Date.now()
  onEnabledChanged: {
    if (!root.enabled) {
      sensorRestart.stop()
      root.sensorExpectedStop = false
      root.sensorPendingStart = false
      root.sensorHolding = false
      root.sensorRestarting = false
    }
  }

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
      if (root.sensorExpectedStop) {
        root.sensorExpectedStop = false
        Qt.callLater(root.finishSensorRestart)
        return
      }
      if (root.sensorRestarting)
        return
      root.sensorPhase = exitCode === 0 ? "stopped" : "crashed"
      root.sensorError = exitCode === 0 ? "" : ("sensor exited with code " + exitCode)
      if (root.sensorWanted && !sensorRestart.running)
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

  // A failed Process launch is not guaranteed to emit onExited on every
  // Quickshell backend. The helper normally emits waiting/connecting status;
  // if neither that nor a live sample arrives, force a fresh launch.
  Timer {
    id: sensorLaunchWatchdog
    interval: 5000
    repeat: true
    running: root.sensorWanted && !root.sensorRestarting
    onTriggered: {
      if (sensorRestart.running)
        return
      if (root.sensorPhase === "paused")
        return
      var last = root.lastSampleMs > 0 ? root.lastSampleMs : root.sensorLaunchStartedMs
      if (Date.now() - last > 20000) {
        root.sensorPhase = "stalled"
        root.sensorError = "sensor helper produced no status"
        root.restartSensor()
      }
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: root.connected
    onTriggered: {
      if (root.lastSampleMs > 0 && Date.now() - root.lastSampleMs > 1500) {
        root.connected = false
        root.sensorPhase = "stalled"
      }
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
        opacity: Util.clamp(root.cover * 2, 0, 1) * root.directionalScrimMax
        Behavior on opacity { NumberAnimation { duration: root.smoothingMs; easing.type: Easing.OutCubic } }
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: Util.alpha(Color.background, root.normalizedYaw >= 0 ? 1 : 0) }
          GradientStop { position: 1; color: Util.alpha(Color.background, root.normalizedYaw >= 0 ? 0 : 1) }
        }
      }

      // Late phase (cover 0.5..1): the whole display settles under the scrim.
      Rectangle {
        anchors.fill: parent
        opacity: Util.clamp((root.cover - 0.5) * 2, 0, 1) * root.fullScrimMax
        Behavior on opacity { NumberAnimation { duration: root.smoothingMs; easing.type: Easing.OutCubic } }
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
    function failsafe(on: string): string { return root.setFailSafe(on) }
    function hysteresis(deg: string): string { return root.setHysteresis(deg) }
    function smoothing(ms: string): string { return root.setSmoothing(ms) }

    function comfort(deg: string): string {
      root.comfortDeg = Util.clamp(root.finiteNumber(deg, 15), 2, 30)
      if (root.fullCoverDeg <= root.comfortDeg)
        root.fullCoverDeg = Math.min(60, root.comfortDeg + 1)
      root.saveSetting("comfortDeg", root.comfortDeg)
      root.saveSetting("fullCoverDeg", root.fullCoverDeg)
      return "" + root.comfortDeg
    }

    function full(deg: string): string {
      root.fullCoverDeg = Util.clamp(root.finiteNumber(deg, 33), root.comfortDeg + 1, 60)
      root.saveSetting("fullCoverDeg", root.fullCoverDeg)
      return "" + root.fullCoverDeg
    }

    function test(deg: string): string {
      var value = Number(deg)
      if (deg === "" || deg === "off" || !isFinite(value) || value < 0)
        root.manualAngle = NaN
      else
        root.manualAngle = Math.min(180, Math.max(0, value))
      return isNaN(root.manualAngle) ? "test-off" : ("" + root.manualAngle)
    }
  }
}
