import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 180
    minHeight: 70

    // ── Settings (reactive, mirrored from pluginData) ────────────────
    readonly property int barCount: Math.max(6, Math.min(48, pluginData.barCount ?? 24))
    // The level helper already reports perceptual (dB-mapped) levels, so the
    // gain here is only the user's taste knob, not a fix for tiny linear RMS.
    readonly property real sensitivity: (pluginData.sensitivity ?? 100) / 100
    readonly property real responseCurve: 0.85
    // Where the levels come from: hyprwhspr IPC files, the microphone, the
    // system output monitor, both, or auto (hyprwhspr if installed, else output).
    readonly property string audioSource: pluginData.audioSource ?? "output"
    readonly property bool showIcon: pluginData.showIcon ?? true
    readonly property bool showBackground: pluginData.showBackground ?? false
    readonly property string colorMode: pluginData.colorMode ?? "primary"
    readonly property color customColor: pluginData.customColor ?? Theme.primary
    // What to show when hyprwhspr is NOT recording:
    //   "dim"    – faint placeholder (bars at rest + outline) so the widget stays
    //              visible and resizable without having to start dictation
    //   "hidden" – fully transparent (pure overlay; only appears while recording)
    readonly property string idleBehavior: pluginData.idleBehavior ?? "dim"
    readonly property real idleOpacity: Math.max(0, Math.min(1, (pluginData.idleOpacity ?? 40) / 100))
    // Overall opacity of the equalizer while recording.
    readonly property real activeOpacity: Math.max(0.1, Math.min(1, (pluginData.activeOpacity ?? 100) / 100))
    readonly property real motionSpeed: Math.max(0.25, Math.min(2.5, (pluginData.motionSpeed ?? 100) / 100))
    // Bars swell toward the center (classic voice-assistant silhouette).
    readonly property bool envelopeShape: pluginData.envelopeShape ?? true

    readonly property bool active: root.recording || root.smooth > 0.002
    readonly property bool idleVisible: !active && root.idleBehavior === "dim"

    readonly property color barColor: root.colorMode === "custom" ? root.customColor
        : root.colorMode === "error" ? Theme.error
        : root.colorMode === "secondary" ? Theme.secondary
        : Theme.primary

    // Per-bar color: solid for most modes; "duo" sweeps primary → secondary
    // across the row.
    function barColorAt(i) {
        if (root.colorMode !== "duo")
            return root.barColor
        var t = root.barCount > 1 ? i / (root.barCount - 1) : 0
        var a = Theme.primary
        var b = Theme.secondary
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }

    // ── Size from settings sliders ───────────────────────────────────
    // Desktop-widget size is stored per-monitor in the instance's "positions".
    // The Width/Height sliders write widthPx/heightPx into the instance config;
    // here we mirror those into the saved size so the slider resizes the widget
    // live (no right-click-drag needed).
    readonly property int cfgWidth: Math.round(pluginData.widthPx ?? 0)
    readonly property int cfgHeight: Math.round(pluginData.heightPx ?? 0)

    onCfgWidthChanged: if (root.cfgWidth > 0) sizeApplyTimer.restart()
    onCfgHeightChanged: if (root.cfgHeight > 0) sizeApplyTimer.restart()

    Timer {
        id: sizeApplyTimer
        interval: 120
        onTriggered: root.applyConfiguredSize()
    }

    function applyConfiguredSize() {
        if (!root.instanceId || root.cfgWidth <= 0 || root.cfgHeight <= 0)
            return
        var positions = (root.instanceData && root.instanceData.positions) ? root.instanceData.positions : {}
        var keys = Object.keys(positions)
        if (keys.length === 0)
            keys = [""]
        for (var i = 0; i < keys.length; i++) {
            var cur = positions[keys[i]] || {}
            if (cur.width === root.cfgWidth && cur.height === root.cfgHeight)
                continue
            SettingsData.updateDesktopWidgetInstancePosition(root.instanceId, keys[i], {
                "width": root.cfgWidth,
                "height": root.cfgHeight
            })
        }
    }

    // On first run, seed the sliders from the widget's actual current size so
    // they reflect reality instead of snapping to an arbitrary default.
    function initSizeFromCurrent() {
        if (!root.instanceId || (pluginData.widthPx ?? 0) > 0)
            return
        var positions = (root.instanceData && root.instanceData.positions) ? root.instanceData.positions : {}
        var w = 0, h = 0
        for (var k in positions) {
            if (positions[k] && positions[k].width) {
                w = positions[k].width
                h = positions[k].height
                break
            }
        }
        if (!w) {
            w = Math.round(root.width) || 380
            h = Math.round(root.height) || 130
        }
        SettingsData.updateDesktopWidgetInstanceConfig(root.instanceId, {
            "widthPx": Math.round(w),
            "heightPx": Math.round(h)
        })
    }

    Component.onCompleted: {
        root.rebuildBars()
        Qt.callLater(root.initSizeFromCurrent)
    }

    // ── Runtime state ────────────────────────────────────────────────
    property bool recording: false
    property real level: 0.0
    property real smooth: 0.0
    property real phase: 0.0

    onActiveChanged: if (!active) root.phase = 0

    // Per-bar constants, rebuilt when the bar count or envelope changes:
    // envelope weight plus randomized wave phases/frequencies so the motion
    // looks organic instead of a marching sine.
    property var _env: []
    property var _rnd: []

    onBarCountChanged: rebuildBars()
    onEnvelopeShapeChanged: rebuildBars()

    function rebuildBars() {
        var env = [], rnd = []
        for (var i = 0; i < root.barCount; i++) {
            var t = (i + 0.5) / root.barCount
            env.push(root.envelopeShape
                ? 0.30 + 0.70 * Math.pow(Math.sin(Math.PI * t), 1.5)
                : 1)
            rnd.push({
                "p1": Math.random() * 6.283,
                "p2": Math.random() * 6.283,
                "s1": 5.5 + Math.random() * 2.5,
                "s2": 9.0 + Math.random() * 4.0
            })
        }
        root._env = env
        root._rnd = rnd
    }

    // ── State + level monitor (same hyprwhspr IPC files as the bar widget) ──
    // All shell builtins (test/read/printf + read-based sleep on a pipe), so the
    // steady state forks no processes at all — v1 spawned cat+sleep ~28×/s.
    // While idle it prints a single "I" on the transition and then stays
    // silent, so the QML side is fully quiescent between recordings.
    // The helper ships next to this component and prints one "R <level>" line
    // per ~80 ms while audio is present, plus a single "I" when it stops.
    readonly property string helperPath: Qt.resolvedUrl("audioLevel.py").toString().replace(/^file:\/\//, "")

    Process {
        id: monitor
        running: true
        command: ["python3", root.helperPath, "--source", root.audioSource]
        stdout: SplitParser {
            onRead: line => root.onMonitorLine(line)
        }
        onExited: restartTimer.start()
    }

    Timer {
        id: restartTimer
        interval: 1500
        onTriggered: monitor.running = true
    }

    // A running Process keeps the command it was started with, so switching the
    // audio source has to cycle the child.
    onAudioSourceChanged: {
        monitor.running = false
        sourceRestartTimer.restart()
    }

    Timer {
        id: sourceRestartTimer
        interval: 250
        onTriggered: monitor.running = true
    }

    function onMonitorLine(line) {
        var s = (line || "").trim()
        if (s.length === 0)
            return
        if (s.charAt(0) === "R") {
            root.recording = true
            var v = parseFloat(s.substring(2))
            root.level = isNaN(v) ? 0 : Math.max(0, Math.min(1, v))
        } else {
            root.recording = false
            root.level = 0
        }
    }

    // Frame-synced, dt-correct animation: runs only while active, pauses with
    // the window, and replaces v1's fixed 16 ms Timer + per-bar Behavior
    // animations (2 animation controllers per bar) with one imperative pass.
    FrameAnimation {
        running: root.active
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    function step(dt) {
        var boosted = Math.min(1, root.level * root.sensitivity)
        var target = Math.pow(boosted, root.responseCurve)
        // Exponential smoothing with real time constants: fast attack, slow
        // release, independent of frame rate.
        var tau = target > root.smooth ? 0.05 : 0.18
        root.smooth += (target - root.smooth) * (1 - Math.exp(-dt / tau))
        if (!root.recording && root.smooth < 0.002)
            root.smooth = 0
        root.phase += dt * root.motionSpeed

        var n = eqRepeater.count
        for (var i = 0; i < n; i++) {
            var bar = eqRepeater.itemAt(i)
            var r = root._rnd[i]
            if (!bar || !r)
                continue
            // Two incommensurate sines per bar → organic shimmer, no visible loop.
            var w = 0.34
                + 0.42 * (0.5 + 0.5 * Math.sin(root.phase * r.s1 + r.p1))
                + 0.24 * (0.5 + 0.5 * Math.sin(root.phase * r.s2 + r.p2))
            bar.mag = Math.min(1, root.smooth * (root._env[i] || 1) * w)
        }
    }

    // Geometry derived from the user-resizable widget area.
    readonly property real maxBarH: root.height * 0.78
    readonly property real gap: Math.max(2, root.width * 0.012)
    readonly property real barW: Math.max(2.5, (root.width * 0.92 - gap * (barCount - 1)) / barCount)
    readonly property real eqLeft: (root.width - (barCount * barW + (barCount - 1) * gap)) / 2

    // ── Visuals ──────────────────────────────────────────────────────
    // Full opacity while recording; a faint placeholder when idle (so the
    // widget can be selected/resized) unless idleBehavior is "hidden".
    opacity: root.active ? root.activeOpacity : (root.idleBehavior === "hidden" ? 0 : root.idleOpacity)
    Behavior on opacity {
        NumberAnimation { duration: 350; easing.type: Easing.InOutQuad }
    }

    // Backing panel: shown when the user enabled it, OR as an outline hint in
    // the idle "dim" state so the resizable bounds are visible.
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        visible: root.showBackground || root.idleVisible
        color: root.showBackground ? Theme.withAlpha(Theme.surfaceContainer, 0.55)
                                    : Theme.withAlpha(Theme.surfaceContainer, 0.22)
        border.width: 1
        border.color: root.showBackground
            ? Theme.withAlpha(Theme.outline, 0.25)
            : Theme.withAlpha(root.barColor, 0.35)
    }

    // Fixed-size container (no Row): bars position themselves, so per-frame
    // height changes don't trigger a layout pass.
    Item {
        id: eqArea
        anchors.fill: parent
        scale: root.active ? 1 : 0.9
        transformOrigin: Item.Center
        Behavior on scale {
            NumberAnimation { duration: 300; easing.type: Easing.OutBack }
        }

        Repeater {
            id: eqRepeater
            model: root.barCount
            Rectangle {
                id: bar
                property real mag: 0
                readonly property color base: root.barColorAt(index)
                x: root.eqLeft + index * (root.barW + root.gap)
                anchors.verticalCenter: parent.verticalCenter
                width: root.barW
                radius: root.barW / 2
                height: Math.max(root.barW, bar.mag * root.maxBarH)
                opacity: 0.55 + 0.45 * bar.mag
                color: bar.base
            }
        }
    }

    // Soft pulsing mic glyph in the corner while recording.
    Item {
        visible: root.showIcon
        width: 26
        height: 26
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 6

        Rectangle {
            anchors.centerIn: parent
            width: 20 + 14 * root.smooth
            height: width
            radius: width / 2
            color: root.barColor
            opacity: 0.16 * root.smooth
        }
        Rectangle {
            anchors.centerIn: parent
            width: 22 + 6 * root.smooth
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Theme.withAlpha(root.barColor, root.active ? 0.55 : 0.25)
        }
        DankIcon {
            anchors.centerIn: parent
            name: root.active ? "mic" : "mic_off"
            size: 15
            color: root.active ? root.barColor : Theme.withAlpha(root.barColor, 0.7)
        }
    }
}
