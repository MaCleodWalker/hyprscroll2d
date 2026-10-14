# Contributing

Thank you for helping build Omalattice.

Before proposing a change:

1. Keep layout geometry and navigation logic independent from Hyprland APIs.
2. Add or update a test in `tests/run.lua`.
3. Run `lua tests/run.lua`.
4. Keep the experimental integration opt-in and easy to disable.

For minimap interaction changes, run `make test-qml` with Qt Quick Test
installed. If `qmltestrunner` is not on your PATH, specify its location:

```bash
make test-qml QMLTESTRUNNER=/usr/lib/qt6/bin/qmltestrunner
```

These tests run offscreen and do not change your Hyprland configuration.

Bug reports should include the Hyprland version, monitor geometry, relevant
configuration and exact reproduction steps.
