# Monix Linux Package

This package installs the Windows build of Monix through Wine.

Run:

```bash
bash install-monix.sh
```

The installer copies Monix to `~/.local/opt/monix`, creates a `monix` launcher in `~/.local/bin`, and adds a desktop entry.

Note: the current Monix telemetry engine is built with Windows APIs. This Linux package is a compatibility package, not a native Linux telemetry port.
