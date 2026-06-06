#!/usr/bin/env bash
# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Launch the headless multiplayer server. It runs the same engine as the desktop
# client, windowless, holding the one authoritative game; clients connect over
# WebSocket (see scenes/net/server_runner.gd and docs/design/network-design.md).
#
# A default save file is REQUIRED (--save): the server autosaves the
# authoritative game to it every turn.
#
# Usage:
#   ./run_server.sh --save=game.sav                          # 2 players, port 9080
#   ./run_server.sh --save=game.sav --players=3 --ai=1       # server plays 1 slot
#   ./run_server.sh --save=game.sav --port=9000 --world=small --map=continents
#   ./run_server.sh --save=ongoing.sav --load=/path/to/game.sav
#
# A bare --save name lands under the user saves dir; one with a "/" is a full path.
# Override the engine binary with GODOT=… (defaults to `godot3`). Every flag is
# forwarded verbatim to NetConfig (src/net/net_config.gd); --server is implied.
set -euo pipefail

GODOT="${GODOT:-godot3}"
RUNNER="res://scenes/net/server_runner.gd"

exec "$GODOT" --no-window -s "$RUNNER" -- --server "$@"
