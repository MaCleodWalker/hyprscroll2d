#!/usr/bin/env bash

set -eu

start_marker="-- hyprscroll2d:start"
end_marker="-- hyprscroll2d:end"
workspace_override="${1:-}"
config_file="${HYPRSCROLL2D_HYPRLAND_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua}"
repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ -n "$workspace_override" ]; then
  case "$workspace_override" in
    *[!0-9]*)
      printf 'Error: workspace must be a positive number.\n' >&2
      exit 1
      ;;
  esac

  if [ "$workspace_override" -lt 1 ]; then
    printf 'Error: workspace must be a positive number.\n' >&2
    exit 1
  fi
fi

if [ ! -f "$config_file" ]; then
  printf 'Error: Omarchy Hyprland config not found at %s\n' "$config_file" >&2
  exit 1
fi

if ! grep -q 'default.hypr.omarchy' "$config_file"; then
  printf 'Error: this installer currently supports Omarchy only.\n' >&2
  printf 'Generic Hyprland users can load layout/init.lua and provide custom bindings.\n' >&2
  exit 1
fi

if grep -Fq -- "$start_marker" "$config_file"; then
  printf 'Hyprscroll2D is already configured in %s\n' "$config_file"
  exit 0
fi

if grep -q 'hyprscroll2d/layout/init.lua' "$config_file"; then
  printf 'Error: an unmarked Hyprscroll2D setup already exists in %s\n' "$config_file" >&2
  printf 'Remove the old Hyprscroll2D lines before running this installer.\n' >&2
  exit 1
fi

case "$repo_dir" in
  *$'\n'*|*$'\r'*)
    printf 'Error: the repository path cannot contain a newline.\n' >&2
    exit 1
    ;;
esac

escaped_repo=${repo_dir//\\/\\\\}
escaped_repo=${escaped_repo//\"/\\\"}
timestamp="$(date +%Y%m%d%H%M%S)"
backup_file="${config_file}.hyprscroll2d.bak.${timestamp}"
before_errors=""

if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  before_errors="$(hyprctl configerrors 2>/dev/null || true)"
fi

cp -p -- "$config_file" "$backup_file"

{
  printf '\n%s\n' "$start_marker"
  printf 'do\n'
  printf '  local hyprscroll2d = "%s"\n' "$escaped_repo"
  printf '  local hyprscroll2d_config = dofile(hyprscroll2d .. "/layout/config.lua")\n'
  printf '  dofile(hyprscroll2d .. "/layout/init.lua")\n'
  printf '  dofile(hyprscroll2d .. "/integration/omarchy.lua")\n'
  if [ -n "$workspace_override" ]; then
    printf '  hyprscroll2d_config.workspace = %s\n' "$workspace_override"
  fi
  printf '  assert(type(hyprscroll2d_config.workspace) == "number" and hyprscroll2d_config.workspace >= 1 and hyprscroll2d_config.workspace %% 1 == 0, "hyprscroll2d: config.workspace must be a positive integer")\n'
  printf '  hl.workspace_rule({ workspace = tostring(hyprscroll2d_config.workspace), layout = "lua:hyprscroll2d" })\n'
  printf 'end\n'
  printf '%s\n' "$end_marker"
} >> "$config_file"

if command -v luac >/dev/null 2>&1 && ! luac -p "$config_file"; then
  cp -p -- "$backup_file" "$config_file"
  printf 'Error: generated Lua was invalid; restored %s\n' "$backup_file" >&2
  exit 1
fi

if [ "${HYPRSCROLL2D_SKIP_RELOAD:-0}" != "1" ] && command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  if ! hyprctl reload >/dev/null; then
    printf 'Warning: Hyprland could not reload. The config was installed; reload it later.\n' >&2
  else
    after_errors="$(hyprctl configerrors 2>/dev/null || true)"
    if [ -z "$before_errors" ] && [ -n "$after_errors" ]; then
      cp -p -- "$backup_file" "$config_file"
      hyprctl reload >/dev/null 2>&1 || true
      printf 'Error: Hyprland reported new config errors; restored %s\n' "$backup_file" >&2
      printf '%s\n' "$after_errors" >&2
      exit 1
    fi
  fi
fi

if [ -n "$workspace_override" ]; then
  printf 'Installed Hyprscroll2D on workspace %s.\n' "$workspace_override"
else
  printf 'Installed Hyprscroll2D using the workspace configured in layout/config.lua.\n'
fi
printf 'Config backup: %s\n' "$backup_file"
printf 'Open a window on the configured workspace and use Super+Arrow to explore.\n'
