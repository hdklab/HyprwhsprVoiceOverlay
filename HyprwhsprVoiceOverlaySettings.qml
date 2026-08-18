import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "hyprwhsprVoiceOverlay"

    StyledText {
        width: parent.width
        text: "Hyprwhspr Voice Overlay"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "A large floating equalizer for the desktop / overview overlay. It fades in only while hyprwhspr is recording. Place and resize it from the desktop-widget controls; enable 'show on overview' in DankMaterialShell to see it over the overview."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "widthPx"
        label: "Width"
        description: "Widget width in pixels. Resizes the widget live (alternative to right-click-dragging the corner)."
        minimum: 180
        maximum: 1600
        defaultValue: 380
        unit: "px"
    }

    SliderSetting {
        settingKey: "heightPx"
        label: "Height"
        description: "Widget height in pixels."
        minimum: 70
        maximum: 800
        defaultValue: 130
        unit: "px"
    }

    SelectionSetting {
        settingKey: "idleBehavior"
        label: "When not recording"
        description: "Dim placeholder keeps the widget visible so you can move/resize it without starting hyprwhspr. Hidden makes it a pure overlay that only appears while recording."
        options: [
            {label: "Show dim placeholder", value: "dim"},
            {label: "Hidden (overlay only)", value: "hidden"}
        ]
        defaultValue: "dim"
    }

    SliderSetting {
        settingKey: "activeOpacity"
        label: "Active opacity"
        description: "Overall opacity of the equalizer while recording."
        minimum: 10
        maximum: 100
        defaultValue: 100
        unit: "%"
    }

    SliderSetting {
        settingKey: "idleOpacity"
        label: "Idle opacity"
        description: "How visible the dim placeholder is when not recording. Higher makes it easier to find and resize."
        minimum: 10
        maximum: 100
        defaultValue: 40
        unit: "%"
    }

    SliderSetting {
        settingKey: "barCount"
        label: "Bars"
        description: "Number of equalizer bars"
        minimum: 6
        maximum: 48
        defaultValue: 24
    }

    ToggleSetting {
        settingKey: "envelopeShape"
        label: "Center envelope"
        description: "Bars swell toward the center like classic voice assistants. Off = uniform height across the row."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "sensitivity"
        label: "Sensitivity"
        description: "Gain applied to the mic level. 150–200% suits most mics."
        minimum: 50
        maximum: 500
        defaultValue: 200
        unit: "%"
    }

    SliderSetting {
        settingKey: "motionSpeed"
        label: "Motion speed"
        description: "How fast the bars shimmer while recording."
        minimum: 25
        maximum: 250
        defaultValue: 100
        unit: "%"
    }

    SelectionSetting {
        settingKey: "colorMode"
        label: "Color"
        options: [
            {label: "Primary", value: "primary"},
            {label: "Secondary", value: "secondary"},
            {label: "Primary → Secondary sweep", value: "duo"},
            {label: "Error / Red", value: "error"},
            {label: "Custom", value: "custom"}
        ]
        defaultValue: "primary"
    }

    ColorSetting {
        settingKey: "customColor"
        label: "Custom color"
        description: "Used when Color is set to Custom"
        defaultValue: Theme.primary
    }

    ToggleSetting {
        settingKey: "showIcon"
        label: "Show mic glyph"
        description: "Pulsing microphone icon in the corner while recording."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showBackground"
        label: "Show background panel"
        description: "Translucent rounded panel behind the bars for legibility over busy wallpapers."
        defaultValue: false
    }
}
