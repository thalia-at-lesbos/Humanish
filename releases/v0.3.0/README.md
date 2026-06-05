# Humanish v0.3.0

Release builds exported with Godot 3.6.2-stable (GLES3). Each binary is
self-contained — the game data pack (`.pck`) is embedded — so no extra files are
needed alongside it. Verify downloads against `SHA256SUMS` (`sha256sum -c SHA256SUMS`).

| Platform | File | Run |
|---|---|---|
| Linux (x86_64) | `linux/Humanish.x86_64` | `chmod +x Humanish.x86_64 && ./Humanish.x86_64` |
| Windows (x64) | `windows/Humanish.exe` | double-click `Humanish.exe` |
| macOS | `macos/Humanish.zip` | unzip, then open `Humanish.app` |

Notes:
- The macOS app is ad-hoc signed only; on first launch use right-click → Open (or
  clear quarantine) to get past Gatekeeper.
- This release adds the simple computer player (PlayerAI) and the per-player
  human/AI toggle in the new-game setup screen.
