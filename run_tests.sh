#!/usr/bin/env bash
# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Local test runner: the unit suites first, then the integration playthrough as
# a final gate. Splitting the run keeps the broad end-to-end scenario from
# muddying unit failures and matches the ordering CI uses (.github/workflows/
# build.yml). `set -e` stops at the first failing phase.
#
# Override the engine binary with GODOT=… (defaults to the local editor binary
# `godot3`, which swallows --no-window). CI uses its headless `godot` build and
# runs the two phases as separate steps without --no-window — see build.yml.
set -euo pipefail

GODOT="${GODOT:-godot3}"
GUT="addons/gut/gut_cmdln.gd"

# Every unit directory except tests/integration (and tests/support, which holds
# no test_* files). Listed explicitly so the unit phase excludes the playthrough.
UNIT_DIRS="res://tests/core,res://tests/world,res://tests/sim,res://tests/api,res://tests/scenes"

echo "== Unit suites =="
"$GODOT" --no-window -s "$GUT" -gdir="$UNIT_DIRS" -ginclude_subdirs -gexit

echo "== Integration playthrough (final gate) =="
"$GODOT" --no-window -s "$GUT" -gdir=res://tests/integration -ginclude_subdirs -gexit

echo "All test phases passed."
