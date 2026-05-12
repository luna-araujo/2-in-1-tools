import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property var transformsByOutput: ({})
    property var busyByOutput: ({})
    property string _queryReason: ""
    property string _queryOutputName: ""
    property string _applyOutputName: ""
    property string _applyTarget: ""
    property bool _applyShouldShowSuccessToast: false
    property bool _applyShouldShowErrorToast: true
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})
    readonly property var cfg: pluginApi?.pluginSettings ?? ({})
    readonly property bool showSuccessToast: cfg.showSuccessToast ?? defaults.showSuccessToast ?? true
    readonly property bool autoTabletBarDensity: cfg.autoTabletBarDensity ?? defaults.autoTabletBarDensity ?? false
    readonly property bool exclusiveDockInTabletMode: cfg.exclusiveDockInTabletMode ?? defaults.exclusiveDockInTabletMode ?? false
    readonly property bool autoRotateInTabletMode: cfg.autoRotateInTabletMode ?? defaults.autoRotateInTabletMode ?? false
    readonly property bool flipVerticalSensorOrientation: cfg.flipVerticalSensorOrientation ?? defaults.flipVerticalSensorOrientation ?? false
    readonly property string buttonBehavior: cfg.buttonBehavior ?? defaults.buttonBehavior ?? "toggle-auto-rotate-lock"
    readonly property string tabletBarDensity: cfg.tabletBarDensity ?? defaults.tabletBarDensity ?? "default"
    readonly property string tabletModeStateFile: cfg.tabletModeStateFile ?? defaults.tabletModeStateFile ?? "/tmp/noctalia-tablet-mode"
    readonly property string lastNonTabletBarDensity: cfg.lastNonTabletBarDensity ?? defaults.lastNonTabletBarDensity ?? ""
    readonly property string lastNonTabletDockType: cfg.lastNonTabletDockType ?? defaults.lastNonTabletDockType ?? ""
    readonly property bool lastNonTabletDockEnabled: cfg.lastNonTabletDockEnabled ?? defaults.lastNonTabletDockEnabled ?? true
    property bool _tabletDensityManaged: false
    property bool _tabletDockManaged: false
    property bool _tabletModeDetected: false
    property bool _autoRotateLocked: false
    property string _autoRotateOutputName: ""
    property string _autoRotateSavedTransform: ""
    property string _autoRotatePendingTransform: ""
    property string _autoRotateLastAppliedTransform: ""
    property string _autoRotateRestoreOutputName: ""
    property string _autoRotateRestoreTransform: ""
    property bool _autoRotateSessionActive: false

    function _copyMap(map) {
        return Object.assign({}, map || {})
    }

    function _normalizeTransform(transform) {
        var value = (transform || "").toString().trim().toLowerCase()
        switch (value) {
        case "90":
        case "180":
        case "270":
            return value
        case "normal":
        case "":
            return "Normal"
        default:
            return "Normal"
        }
    }

    function _barDensity() {
        return Settings.data?.bar?.density ?? "default"
    }

    function _dockType() {
        return Settings.data?.dock?.dockType ?? "floating"
    }

    function _dockEnabled() {
        return Settings.data?.dock?.enabled ?? true
    }

    function _savePluginSetting(key, value) {
        if (!pluginApi) return
        pluginApi.pluginSettings[key] = value
        pluginApi.saveSettings()
    }

    function _applyTabletDensity() {
        var target = (root.tabletBarDensity || "default").trim()
        if (!target)
            target = "default"

        if (!root._tabletDensityManaged) {
            if (!root.lastNonTabletBarDensity)
                root._savePluginSetting("lastNonTabletBarDensity", root._barDensity())
            root._tabletDensityManaged = true
        }

        if (Settings.data?.bar && Settings.data.bar.density !== target)
            Settings.data.bar.density = target
    }

    function _restoreDesktopDensity() {
        if (!root._tabletDensityManaged)
            return

        var restoreDensity = root.lastNonTabletBarDensity || "default"
        if (Settings.data?.bar && Settings.data.bar.density !== restoreDensity)
            Settings.data.bar.density = restoreDensity

        root._tabletDensityManaged = false
        if (root.lastNonTabletBarDensity)
            root._savePluginSetting("lastNonTabletBarDensity", "")
    }

    function _applyTabletDockMode() {
        if (!Settings.data?.dock)
            return

        if (!root._tabletDockManaged) {
            root._savePluginSetting("lastNonTabletDockType", root._dockType())
            root._savePluginSetting("lastNonTabletDockEnabled", root._dockEnabled())
            root._tabletDockManaged = true
        }

        if (!Settings.data.dock.enabled)
            Settings.data.dock.enabled = true
        if (Settings.data.dock.dockType !== "exclusive")
            Settings.data.dock.dockType = "exclusive"
    }

    function _restoreDesktopDockMode() {
        if (!root._tabletDockManaged)
            return

        if (Settings.data?.dock) {
            Settings.data.dock.enabled = root.lastNonTabletDockEnabled
            Settings.data.dock.dockType = root.lastNonTabletDockType || "floating"
        }

        root._tabletDockManaged = false
        root._savePluginSetting("lastNonTabletDockType", "")
        root._savePluginSetting("lastNonTabletDockEnabled", true)
    }

    function _syncTabletModeState(active) {
        root._tabletModeDetected = active

        if (!root.autoTabletBarDensity) {
            root._restoreDesktopDensity()
            if (!active && root.lastNonTabletBarDensity)
                root._savePluginSetting("lastNonTabletBarDensity", "")
        } else if (active)
            root._applyTabletDensity()
        else {
            if (!root._tabletDensityManaged && root.lastNonTabletBarDensity)
                root._savePluginSetting("lastNonTabletBarDensity", "")
            root._restoreDesktopDensity()
        }

        if (!root.exclusiveDockInTabletMode) {
            root._restoreDesktopDockMode()
            if (!active && root.lastNonTabletDockType)
                root._savePluginSetting("lastNonTabletDockType", "")
        } else if (active)
            root._applyTabletDockMode()
        else
            root._restoreDesktopDockMode()

        root._syncAutoRotateLifecycle()
    }

    function refreshTabletModeState() {
        if (tabletModeProc.running)
            return

        tabletModeProc.command = [
            "sh",
            "-c",
            "if [ -f \"$1\" ]; then cat \"$1\"; else printf off; fi",
            "2-in-1-tools",
            root.tabletModeStateFile
        ]
        tabletModeProc.running = true
    }

    function _setBusy(outputName, busy) {
        if (!outputName) return
        var next = _copyMap(root.busyByOutput)
        next[outputName] = busy
        root.busyByOutput = next
    }

    function _setTransform(outputName, transform) {
        if (!outputName) return
        var next = _copyMap(root.transformsByOutput)
        next[outputName] = root._normalizeTransform(transform)
        root.transformsByOutput = next
    }

    function transformForOutput(outputName) {
        return root._normalizeTransform(root.transformsByOutput[outputName] || "Normal")
    }

    function isBusy(outputName) {
        return !!root.busyByOutput[outputName]
    }

    function transformLabel(transform) {
        switch (transform) {
        case "90": return "90 degrees"
        case "180": return "180 degrees"
        case "270": return "270 degrees"
        default: return "Normal"
        }
    }

    function _nextTransform(transform) {
        switch (transform) {
        case "Normal": return "90"
        case "90": return "180"
        case "180": return "270"
        default: return "Normal"
        }
    }

    function _transformArg(transform) {
        return transform === "Normal" ? "normal" : transform
    }

    function _isInternalOutput(outputName) {
        return /^(eDP|LVDS|DSI)/.test(outputName || "")
    }

    function _internalDisplayFromOutputs(outputs) {
        if (!outputs)
            return ""

        var names = Object.keys(outputs)
        for (var i = 0; i < names.length; ++i) {
            if (root._isInternalOutput(names[i]))
                return names[i]
        }

        return names.length === 1 ? names[0] : ""
    }

    function _orientationToTransform(orientation) {
        switch ((orientation || "").trim().toLowerCase()) {
        case "normal": return "Normal"
        case "bottom-up": return "180"
        case "left-up": return root.flipVerticalSensorOrientation ? "270" : "90"
        case "right-up": return root.flipVerticalSensorOrientation ? "90" : "270"
        default: return ""
        }
    }

    function _requestOutputs(reason, outputName) {
        if (queryProc.running)
            return false

        root._queryReason = reason || ""
        root._queryOutputName = outputName || ""
        queryProc.command = ["niri", "msg", "--json", "outputs"]
        queryProc.running = true
        return true
    }

    function _setAutoRotatePendingTransform(transform) {
        var normalized = root._normalizeTransform(transform)
        if (!root._autoRotateSessionActive || !root._autoRotateOutputName)
            return
        if (root._autoRotateLocked)
            return
        if (normalized === root._autoRotateLastAppliedTransform)
            return

        root._autoRotatePendingTransform = normalized
        root._syncAutoRotateLifecycle()
    }

    function _startOrientationMonitor() {
        if (orientationProc.running)
            return

        orientationProc.command = ["monitor-sensor", "--accel"]
        orientationProc.running = true
    }

    function _stopOrientationMonitor() {
        if (orientationProc.running)
            orientationProc.running = false
    }

    function _beginAutoRotateSession(outputName) {
        if (!outputName)
            return

        root._autoRotateOutputName = outputName
        root._autoRotateSavedTransform = root.transformForOutput(outputName)
        root._autoRotateLastAppliedTransform = root._autoRotateSavedTransform
        root._autoRotatePendingTransform = ""
        root._autoRotateLocked = false
        root._autoRotateSessionActive = true
        root._startOrientationMonitor()
    }

    function _applyTransform(outputName, target, shouldShowSuccessToast, shouldShowErrorToast) {
        if (!outputName || applyProc.running)
            return false

        root._applyOutputName = outputName
        root._applyTarget = root._normalizeTransform(target)
        root._applyShouldShowSuccessToast = !!shouldShowSuccessToast
        root._applyShouldShowErrorToast = shouldShowErrorToast !== false
        root._setBusy(outputName, true)
        applyProc.command = ["niri", "msg", "output", outputName, "transform", root._transformArg(root._applyTarget)]
        applyProc.running = true
        return true
    }

    function _endAutoRotateSession() {
        root._stopOrientationMonitor()

        if (!root._autoRotateSessionActive) {
            root._autoRotateOutputName = ""
            root._autoRotateSavedTransform = ""
            root._autoRotatePendingTransform = ""
            root._autoRotateLastAppliedTransform = ""
            return
        }

        var outputName = root._autoRotateOutputName
        var restoreTransform = root._autoRotateSavedTransform || "Normal"

        root._autoRotateSessionActive = false
        root._autoRotateOutputName = ""
        root._autoRotateSavedTransform = ""
        root._autoRotatePendingTransform = ""
        root._autoRotateLastAppliedTransform = ""
        root._autoRotateLocked = false

        root._autoRotateRestoreOutputName = outputName
        root._autoRotateRestoreTransform = restoreTransform
    }

    function _syncAutoRotateLifecycle() {
        var shouldAutoRotate = root._tabletModeDetected && root.autoRotateInTabletMode

        if (!shouldAutoRotate) {
            if (root._autoRotateRestoreOutputName && !applyProc.running) {
                var restoreOutputName = root._autoRotateRestoreOutputName
                var restoreTransform = root._autoRotateRestoreTransform || "Normal"
                root._autoRotateRestoreOutputName = ""
                root._autoRotateRestoreTransform = ""
                if (!root._applyTransform(restoreOutputName, restoreTransform, false, false)) {
                    root._autoRotateRestoreOutputName = restoreOutputName
                    root._autoRotateRestoreTransform = restoreTransform
                }
                return
            }

            root._endAutoRotateSession()
            return
        }

        if (!root._autoRotateSessionActive) {
            root._requestOutputs("auto-rotate-start", "")
            return
        }

        if (!root._autoRotateOutputName) {
            root._endAutoRotateSession()
            return
        }

        if (root._autoRotateLocked) {
            root._stopOrientationMonitor()
            return
        }

        root._startOrientationMonitor()

        if (!root._autoRotatePendingTransform || applyProc.running)
            return

        var pending = root._autoRotatePendingTransform
        root._autoRotatePendingTransform = ""
        if (!root._applyTransform(root._autoRotateOutputName, pending, false, false))
            root._autoRotatePendingTransform = pending
    }

    function refreshTransform(outputName) {
        if (!outputName)
            return
        root._requestOutputs("refresh-output", outputName)
    }

    function cycleTransform(outputName) {
        if (!outputName) {
            ToastService.showError("No output selected for rotation")
            return
        }
        if (root.isBusy(outputName) || applyProc.running) return

        var current = root.transformForOutput(outputName)
        var target = root._nextTransform(current)

        root._applyTransform(outputName, target, root.showSuccessToast, true)
    }

    function buttonUsesManualRotate() {
        return root.buttonBehavior === "manual-rotate"
    }

    function buttonIconName() {
        if (root.buttonUsesManualRotate())
            return "rotate-cw"
        return root._autoRotateLocked ? "lock-square" : "rotate-clockwise"
    }

    function buttonTooltip(outputName) {
        if (root.buttonUsesManualRotate()) {
            var transform = outputName ? root.transformForOutput(outputName) : "Normal"
            return "Rotate display · Current: " + root.transformLabel(transform)
        }

        if (!root.autoRotateInTabletMode)
            return "Enable Auto-rotate screen in tablet mode in plugin settings"
        if (!root._tabletModeDetected)
            return "Auto-rotate toggle is available in tablet mode"
        if (!root._autoRotateOutputName)
            return "Auto-rotate is unavailable because no internal display was detected"
        return root._autoRotateLocked ? "Rotation locked" : "Auto-rotate enabled"
    }

    function buttonEnabled(outputName) {
        if (root.buttonUsesManualRotate())
            return !!outputName && !root.isBusy(outputName)
        return !applyProc.running
    }

    function activatePrimaryButton(outputName) {
        if (root.buttonUsesManualRotate()) {
            root.cycleTransform(outputName)
            return
        }

        root.toggleAutoRotateLock()
    }

    function toggleAutoRotateLock() {
        if (!root.autoRotateInTabletMode || !root._tabletModeDetected || !root._autoRotateOutputName)
            return

        root._autoRotateLocked = !root._autoRotateLocked
        if (!root._autoRotateLocked)
            root._requestOutputs("refresh-output", root._autoRotateOutputName)
        root._syncAutoRotateLifecycle()
    }

    Process {
        id: queryProc
        stdout: StdioCollector {}

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root._queryReason = ""
                root._queryOutputName = ""
                root._syncAutoRotateLifecycle()
                return
            }

            try {
                var outputs = JSON.parse(queryProc.stdout.text.trim())
                var names = Object.keys(outputs)
                for (var i = 0; i < names.length; ++i) {
                    var outputName = names[i]
                    var output = outputs[outputName]
                    if (output && output.logical && output.logical.transform)
                        root._setTransform(outputName, output.logical.transform)
                }

                if (root._queryReason === "auto-rotate-start")
                    root._beginAutoRotateSession(root._internalDisplayFromOutputs(outputs))
            } catch (error) {
                console.warn("2-in-1-tools: failed to parse niri outputs JSON:", error)
            } finally {
                root._queryReason = ""
                root._queryOutputName = ""
                root._syncAutoRotateLifecycle()
            }
        }
    }

    Process {
        id: applyProc
        stderr: StdioCollector {}

        onExited: (exitCode, exitStatus) => {
            var outputName = root._applyOutputName
            root._setBusy(outputName, false)

            if (exitCode === 0) {
                root._setTransform(outputName, root._applyTarget)
                if (root._applyShouldShowSuccessToast)
                    ToastService.showSuccess("Display rotated to " + root.transformLabel(root._applyTarget))
                root.refreshTransform(outputName)
                if (outputName === root._autoRotateOutputName)
                    root._autoRotateLastAppliedTransform = root._applyTarget
                root._syncAutoRotateLifecycle()
                return
            }

            if (root._applyShouldShowErrorToast) {
                var message = "Failed to rotate output"
                var detail = applyProc.stderr.text.trim()
                if (detail)
                    message += ": " + detail
                ToastService.showError(message)
            }
            root.refreshTransform(outputName)
            root._syncAutoRotateLifecycle()
        }
    }

    Process {
        id: tabletModeProc
        stdout: StdioCollector {}

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                return

            var value = tabletModeProc.stdout.text.trim().toLowerCase()
            root._syncTabletModeState(value === "on" || value === "true" || value === "1")
        }
    }

    Process {
        id: orientationProc
        stdout: SplitParser {
            onRead: data => {
                var match = /Accelerometer orientation(?: changed)?:\s*([a-z-]+)/i.exec(data)
                if (!match)
                    return

                var target = root._orientationToTransform(match[1])
                if (!target)
                    return

                root._setAutoRotatePendingTransform(target)
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root._tabletModeDetected && root.autoRotateInTabletMode && root._autoRotateSessionActive)
                root._startOrientationMonitor()
        }
    }

    onAutoRotateInTabletModeChanged: root._syncAutoRotateLifecycle()
    onTabletModeStateFileChanged: root.refreshTabletModeState()

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshTabletModeState()
    }

    Component.onDestruction: {
        tabletModeProc.running = false
        queryProc.running = false
        applyProc.running = false
        orientationProc.running = false
    }
}
