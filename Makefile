.PHONY: test check

test:
	lua tests/run.lua
	lua tests/hyprland_adapter.lua
	lua tests/omarchy_integration.lua
	lua tests/hover.lua
	bash tests/installer.sh

check: test
	luac -p layout/*.lua integration/*.lua tests/*.lua
	bash -n install.sh uninstall.sh tests/installer.sh
	python3 -m json.tool manifest.json >/dev/null
	test -f Service.qml
	@if command -v omarchy >/dev/null 2>&1; then omarchy plugin validate .; fi
