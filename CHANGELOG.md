# Changelog

## Unreleased

- Show live scaled thumbnails with titles on the workspace overview, so windows
  no longer resize or appear zoomed in.
- Add three-finger up/down swipes that focus windows in Hyprscroll2D.
- Add Hyprscroll2D to the `Super+L` layout rotation (dwindle, scrolling,
  Hyprscroll2D) and remember the workspaces that use it.
- Make `workspace` in `layout/config.lua` optional instead of defaulting to 9.
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
