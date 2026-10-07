# Hyprscroll2D

[![Tests](https://github.com/kirollosatef/hyprscroll2d/actions/workflows/tests.yml/badge.svg)](https://github.com/kirollosatef/hyprscroll2d/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Hyprscroll2D is an experimental two-dimensional scrolling layout for Hyprland.
It turns a workspace into an expandable grid and lets you move through it in
every direction.

Unlike column-only scrolling layouts, windows can live above, below, left and
right of each other. Configurable edge peeks keep nearby rows and columns
visible, so you never lose the shape of your workspace.

## What works

- Infinite two-dimensional window placement
- Focus and camera movement on both axes
- Directional window movement with collision swapping
- Independent width and height presets
- Visible edge peeks for neighboring rows and columns
- A compact overview of all workspace windows
- Per-workspace in-memory layout state
- Omarchy bindings that fall back to the normal action outside Hyprscroll2D

## Status

`v0.2.0` is an experimental preview for Hyprland `0.56.x`. It has been
live-tested on Hyprland `0.56.2` and is intentionally enabled on only one
workspace during evaluation.

The layout uses Hyprland's Lua custom-layout API, so it does not require a
compiled Hyprland plugin. Native Omarchy Shell packaging loads the layout and
keeps it active across Hyprland config reloads. Other Lua-configured Hyprland
installations can load the layout, but must provide their own bindings.

## Install on Omarchy

### Recommended: Omarchy plugin command

Requirements:

- Current Omarchy Quattro with Hyprland `0.56.x`

Install and enable directly from GitHub:

```bash
omarchy plugin add https://github.com/kirollosatef/hyprscroll2d --enable
```

The plugin loads Hyprscroll2D at runtime without editing your Hyprland config.
It enables the layout on the workspace set by `workspace` in
[`layout/config.lua`](layout/config.lua), which defaults to 9. Change that value
and reload Hyprland to use a different workspace.

Update it later with:

```bash
omarchy plugin update io.github.kirollosatef.hyprscroll2d
```

The repository contains a validated Omarchy `manifest.json` and can be
installed through the official `omarchy plugin` command today. A listing on
the community [Omarchy Plugin Marketplace](https://omarchyplugins.com/) is a
separate review process and does not make a plugin part of Omarchy's bundled
first-party plugins.

### Alternative: config installer

If your Omarchy version does not yet provide `omarchy plugin`, clone the
project and run the config installer:

Clone the project and run the installer:

```bash
git clone https://github.com/kirollosatef/hyprscroll2d.git \
  ~/.local/share/hyprscroll2d
~/.local/share/hyprscroll2d/install.sh
```

This alternative installer uses the workspace configured in
[`layout/config.lua`](layout/config.lua) by default. Passing a workspace number
overrides the config for this installation:

```bash
~/.local/share/hyprscroll2d/install.sh 8
```

The installer:

- creates a timestamped backup of `~/.config/hypr/hyprland.lua`;
- enables Hyprscroll2D only on the configured workspace;
- reloads Hyprland and checks for configuration errors;
- restores the backup automatically if the new block causes an error.

For a manual installation, add the following near the end of
`~/.config/hypr/hyprland.lua`, after the Omarchy defaults and your normal
`require("hypr.*")` lines:

```lua
local hyprscroll2d = os.getenv("HOME") .. "/.local/share/hyprscroll2d"
local hyprscroll2d_config = dofile(hyprscroll2d .. "/layout/config.lua")
dofile(hyprscroll2d .. "/layout/init.lua")
dofile(hyprscroll2d .. "/integration/omarchy.lua")

-- Start safely on one experimental workspace.
hl.workspace_rule({ workspace = tostring(hyprscroll2d_config.workspace), layout = "lua:hyprscroll2d" })
```

Then reload and validate the configuration:

```bash
hyprctl reload
hyprctl configerrors
```

If `hyprctl configerrors` prints nothing, the manual setup is ready.

## Controls

| Action | Binding |
| --- | --- |
| Focus a window | `Super+Arrow` |
| Move or swap a window | `Super+Shift+Arrow` |
| Pan the camera | `Super+Ctrl+Arrow` |
| Grow window width | `Super+-` |
| Shrink window width | `Super+=` |
| Grow window height | `Super+Shift+=` |
| Shrink window height | `Super+Shift+-` |
| Toggle workspace overview | `Super+M` |
| Select the focused overview window | `Super+Enter` |
| Exit overview | `Super+Escape` |

The focus, move and resize bindings retain Omarchy's normal behavior whenever
the active window is not using Hyprscroll2D. `Super+Enter` selects the overview
window while overview is active and otherwise keeps Omarchy's terminal action.

In overview mode, every window is scaled into the viewport. Use `Super+Arrow`
to select a window or click one directly, then press `Super+Enter` to return to
it. `Super+M` and `Super+Escape` also exit overview mode.
Overview resizes the actual windows, so their contents respond to the smaller
window size according to each application's normal resize behavior. The Lua
custom-layout API cannot uniformly scale a client's rendered pixels.

## Customize the layout

Edit [`layout/config.lua`](layout/config.lua) to change:

- `workspace`: workspace number that uses Hyprscroll2D (default: `9`)
- `peek_x` and `peek_y`: visible pixels from neighboring columns and rows
- `gap_x` and `gap_y`: spacing between cells
- `width_steps` and `height_steps`: available size presets
- `default_width_step` and `default_height_step`: initial window dimensions

Reload Hyprland after changing the values.

## Update a config installation

```bash
git -C ~/.local/share/hyprscroll2d pull --ff-only
hyprctl reload
hyprctl configerrors
```

## Uninstall

If installed using `omarchy plugin add`, run:

```bash
omarchy plugin remove io.github.kirollosatef.hyprscroll2d --yes
hyprctl reload
```

The reload restores Omarchy's normal bindings and removes the runtime layout.

If installed using the alternative config installer, run its uninstaller
before deleting the repository:

```bash
~/.local/share/hyprscroll2d/uninstall.sh
```

It removes only the marked Hyprscroll2D block and creates another timestamped
config backup. Once it finishes, remove the cloned repository:

```bash
rm -rf ~/.local/share/hyprscroll2d
```

## Known limitations

- State is reset when Hyprland reloads.
- Fullscreen, groups, multi-monitor moves, and special workspaces need more
  testing.
- The bundled conditional keybinding integration supports Omarchy.
- Compatibility outside Hyprland `0.56.x` is not yet guaranteed.

Please report issues with your Hyprland version, monitor geometry, relevant
configuration, and exact reproduction steps.

## Development

Run the full test and syntax suite:

```bash
make check
```

The geometry and navigation engine is isolated from Hyprland APIs so it can be
tested with plain Lua. See [`docs/DESIGN.md`](docs/DESIGN.md) for the behavioral
model and roadmap, and [`docs/RESEARCH.md`](docs/RESEARCH.md) for related
projects, important differences and technical background.

## Contributing

Contributions and real-world testing are welcome. Read
[`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

Created by [kirollosatef](https://github.com/kirollosatef).

## License

MIT
