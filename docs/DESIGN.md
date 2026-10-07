# Hyprscroll2D design

## Mental model

Each tiled window occupies an integer grid coordinate `(column, row)`. The
workspace camera also has a grid coordinate. Rendering translates every window
relative to that camera.

The largest window size is slightly smaller than the viewport. Columns and
rows are packed using the largest window in each band rather than a fixed
screen-sized pitch. This keeps neighboring edges visible even when individual
windows use smaller presets. With a 48px peek and a 12px inter-cell gap, at
least 36px of an adjacent maximum-sized row or column remains visible.

## Initial behavior

- New windows are placed in the first free cell to the right of the focused
  window.
- Directional focus prefers a window on the same row or column, then the
  nearest directional candidate.
- Moving into an occupied cell swaps the two windows.
- Moving into an empty cell preserves the hole and moves the window there.
- The camera follows focus unless the user explicitly pans it.
- Width and height use discrete presets to prevent accidental overlaps.
- Overview mode scales every workspace window into the viewport. Directional
  focus or clicking a window selects it without leaving the overview; confirming
  returns to the normal layout centered on that window.

## Intended controls

| Action | Binding |
| --- | --- |
| Focus | `Super+Arrow` |
| Move window | `Super+Shift+Arrow` |
| Pan camera | `Super+Ctrl+Arrow` |
| Grow width | `Super+-` |
| Shrink width | `Super+=` |
| Grow height | `Super+Shift+=` |
| Shrink height | `Super+Shift+-` |
| Toggle overview | `Super+M` |
| Confirm selected window | `Super+Enter` |
| Exit overview | `Super+Escape` |

Bindings must delegate to Omarchy's original actions whenever another layout
is active.

## Roadmap

1. Validate off-screen placement and animation on Hyprland 0.56.2.
2. Add safe Omarchy bindings and an experimental workspace rule.
3. Add state persistence across Hyprland reloads.
4. Add mouse/touchpad camera panning.
5. Harden groups, fullscreen, multi-monitor moves and special workspaces.
