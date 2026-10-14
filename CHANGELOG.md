# Changelog

## Unreleased

- Pan a scrollable overview automatically when the mouse is near the edge of
  the viewport (`overview_autoscroll_speed`).
- Make clicking an overview thumbnail enter that window and close the overview.
- Fix three-finger left/right swipes switching workspaces on an Omalattice
  workspace: they now move focus, and the workspace swipe returns elsewhere.
- Add `hover_focus_delay` to debounce focus-follows-mouse on Omalattice
  workspaces, so crossing the edge peeks no longer scrolls the grid.
- Make the focus swipes follow the touchpad `natural_scroll` setting.
- Add `gesture_fingers` to set the finger count for the focus swipes.

## v0.3.0 - 2026-10-14

Omalattice is a fork of Hyprscroll2D by kirollosatef. Entries below this
release were published upstream as Hyprscroll2D.

- Rename the project, plugin ID (`io.github.macleodwalker.omalattice`), layout
  and state files to Omalattice.
- Show live scaled thumbnails with titles on the workspace overview, so windows
  no longer resize or appear zoomed in.
- Add three-finger up/down swipes that focus windows in Omalattice.
- Add Omalattice to the `Super+L` layout rotation (dwindle, scrolling,
  Omalattice) and remember the workspaces that use it.
- Make `workspace` in `layout/config.lua` optional instead of defaulting to 9.
- Close up empty columns and rows when windows close or move, so the grid has
  no blank space between windows.
- Keep overview windows at least a quarter of the viewport in size and scroll
  larger workspaces with scroll bars, wheel scrolling and selection follow.

## v0.2.0 - 2026-08-24

- Add native installation through `omarchy plugin add`.
- Reload the layout automatically after a Hyprland configuration reload.
- Add an Omarchy marketplace-compatible service manifest.

## v0.1.0 - 2026-08-24

First experimental preview.

- Add an infinite two-dimensional grid and camera.
- Add horizontal and vertical focus, movement, swapping, and panning.
- Add independent width and height presets.
- Keep neighboring rows and columns visible with configurable edge peeks.
- Add conditional Omarchy integration for an isolated test workspace.
- Add safe Omarchy install and uninstall scripts with config backups.
- Add core, Hyprland adapter, and Omarchy integration tests.
