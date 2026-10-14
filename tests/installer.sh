#!/usr/bin/env bash

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
config_file="$temp_dir/hyprland.lua"

printf '%s\n' 'require("default.hypr.omarchy")' > "$config_file"

OMALATTICE_HYPRLAND_CONFIG="$config_file" \
OMALATTICE_SKIP_RELOAD=1 \
  "$repo_dir/install.sh" 7 >/dev/null

grep -Fq -- '-- omalattice:start' "$config_file"
grep -Fq -- 'omalattice_config.workspace = 7' "$config_file"
grep -Fq -- 'workspace = tostring(omalattice_config.workspace)' "$config_file"
grep -Fq -- "local omalattice = \"$repo_dir\"" "$config_file"
grep -Fq -- 'local omalattice_config = dofile(omalattice .. "/layout/config.lua")' "$config_file"
grep -Fq -- 'dofile(omalattice .. "/layout/init.lua")' "$config_file"

OMALATTICE_HYPRLAND_CONFIG="$config_file" \
OMALATTICE_SKIP_RELOAD=1 \
  "$repo_dir/uninstall.sh" >/dev/null

if grep -Fq -- '-- omalattice:start' "$config_file"; then
  printf 'installer test failed: marker survived uninstall\n' >&2
  exit 1
fi

grep -Fq -- 'require("default.hypr.omarchy")' "$config_file"

printf '%s\n' 'require("default.hypr.omarchy")' > "$config_file"
OMALATTICE_HYPRLAND_CONFIG="$config_file" \
OMALATTICE_SKIP_RELOAD=1 \
  "$repo_dir/install.sh" >/dev/null

grep -Fq -- 'local omalattice_config = dofile(omalattice .. "/layout/config.lua")' "$config_file"
if grep -Fq -- 'omalattice_config.workspace =' "$config_file"; then
  printf 'installer test failed: default install should use config workspace\n' >&2
  exit 1
fi

OMALATTICE_HYPRLAND_CONFIG="$config_file" \
OMALATTICE_SKIP_RELOAD=1 \
  "$repo_dir/uninstall.sh" >/dev/null

printf 'ok - installer and uninstaller\n'
