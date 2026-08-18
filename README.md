# Hyprwhspr Voice Overlay

An on-screen / desktop voice visualizer for [hyprwhspr](https://github.com/goodroot/hyprwhspr),
built as a [DankMaterialShell](https://danklinux.com) **desktop widget** (the same kind as Dank
Audio Visualizer). A large mirrored equalizer, driven by the live microphone level, that appears
while hyprwhspr is recording.

![screenshot](screenshot.png)

## Features

- **Center envelope** (toggleable) — bars swell toward the middle, the classic voice-assistant
  silhouette.
- Organic motion: each bar gets two randomized, incommensurate sine components, so there is no
  visible "marching wave" loop.
- A **Primary → Secondary sweep** color mode that blends the theme colors across the row.
- Subtle pop-in (overshoot scale) when recording starts, a pulsing mic glyph, and a dim idle
  placeholder.
- **Cheap while idle** — the IPC monitor is pure shell builtins with a `read`-based sub-second
  sleep, so it forks no subprocesses in steady state. While idle it goes silent entirely and the
  QML side is fully quiescent between recordings.
- Animation is a `FrameAnimation`: frame-synced and dt-correct (attack/release are real time
  constants, independent of refresh rate), and it pauses with the window. Bars are absolutely
  positioned, so per-frame height changes never trigger layout passes.

## Behavior

- **Recording** → full-opacity animated equalizer + pulsing mic icon.
- **Idle** → controlled by the *When not recording* setting:
  - **Show dim placeholder** (default) — a faint outlined panel with resting bars, so the widget
    stays visible and you can move/resize it from the desktop-widget handles **without having to
    start dictation**.
  - **Hidden (overlay only)** — fully transparent; only appears while recording.

Like all DMS desktop widgets it lives on the wallpaper/background layer, so it's visible on the
desktop and (with *Show on overview* enabled) on the overview overlay — not floating above
normal application windows.

## Data source

Reads hyprwhspr's IPC files:
`$XDG_CONFIG_HOME/hyprwhspr/recording_status` (presence = recording) and
`$XDG_CONFIG_HOME/hyprwhspr/audio_level` (live `0.000`–`1.000` mic level). Both only exist while
hyprwhspr records, so the overlay is inherently scoped to hyprwhspr.

## Install / use

```bash
git clone https://github.com/lucianosrp/HyprwhsprVoiceOverlay ~/.config/DankMaterialShell/plugins/HyprwhsprVoiceOverlay
dms restart   # desktop plugins are compiled at shell start
```

Desktop plugins are **not** enabled from the plugin list — add the widget from the
DankMaterialShell desktop-widget controls (Settings → Widgets, or the desktop widget picker),
then drag/resize it and toggle *Show on overview* / *Click-through* as desired.

## Settings

- **When not recording** — dim placeholder (resizable) vs hidden (overlay only).
- **Bars** (6–48), **Center envelope**, **Sensitivity** (50–500%), **Motion speed** (25–250%).
- **Color** — Primary / Secondary / Primary → Secondary sweep / Error / Custom.
- **Show mic glyph** — pulsing mic icon in the corner.
- **Show background panel** — translucent panel behind the bars for busy wallpapers.

## Requirements

- DankMaterialShell ≥ 1.2.0
- hyprwhspr

## License

MIT

> Note: `DesktopPluginComponent` does **not** support `defaultWidth`/`defaultHeight`/`forceSquare`
> (despite older docs) — only `minWidth`/`minHeight`. Default size comes from the instance's saved
> position.
