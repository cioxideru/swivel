# Agent notes

Swivel is a ~700-line Swift macOS menu-bar app (Command + Shift layout switching, smooth and reversible mouse wheel scrolling). README.md is the full reference: architecture, algorithms, permissions, preferences, troubleshooting. Its section "Notes for AI agents and contributors" lists the rules that matter when changing code.

- Build: `./build.sh` (set `SIGN_IDENTITY` to keep macOS permissions across rebuilds). It must finish without warnings.
- Scrolling lives in `Sources/Wheel.swift`, the keyboard in `Sources/LayoutSwitcher.swift`, the menu and permission flow in `Sources/main.swift`.
- Everything runs on the main run loop; keep event tap callbacks short.
