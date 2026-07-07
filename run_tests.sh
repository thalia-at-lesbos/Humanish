#!/usr/bin/env bash
# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Local test runner: the unit suites first, then the integration playthrough as
# a final gate. Splitting the run keeps the broad end-to-end scenario from
# muddying unit failures and matches the ordering CI uses (.github/workflows/
# build.yml).
#
# The engine binary exits 0 regardless of GUT results, so each phase is piped
# through `tee` (output stays live) into a temp log that is then checked. A
# phase fails — and the script exits 1 immediately — if any of these hold:
#   * the GUT summary reports a non-zero "Failing tests" count;
#   * the summary line is missing entirely (the run aborted before finishing);
#   * an engine-level "SCRIPT ERROR" appears anywhere in the output (GUT
#     swallows these and still reports the suite green — see CLAUDE.md).
#
# Override the engine binary with GODOT=… (defaults to the local editor binary
# `godot3`, which swallows --no-window). CI uses its headless `godot` build and
# runs the two phases as separate steps without --no-window — see build.yml.
set -uo pipefail

GODOT="${GODOT:-godot3}"
GUT="addons/gut/gut_cmdln.gd"

# Every unit directory except tests/integration (and tests/support, which holds
# no test_* files). Listed explicitly so the unit phase excludes the playthrough.
UNIT_DIRS="res://tests/core,res://tests/world,res://tests/sim,res://tests/api,res://tests/scenes,res://tests/net"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# run_phase <name> <gut-args…> — run one GUT phase, teeing live output to $LOG,
# then fail hard on any of the conditions listed in the header.
run_phase() {
    local name="$1"
    shift
    echo "== $name =="
    "$GODOT" --no-window -s "$GUT" "$@" 2>&1 | tee "$LOG"
    local engine_status="${PIPESTATUS[0]}"

    if [ "$engine_status" -ne 0 ]; then
        echo "FAIL: $name — engine exited with status $engine_status." >&2
        exit 1
    fi

    # GUT swallows engine-level script errors and still reports green; a parse
    # error in any loaded script must fail the run.
    if grep -q "SCRIPT ERROR" "$LOG"; then
        echo "FAIL: $name — SCRIPT ERROR in output (GUT may still report green):" >&2
        grep -m 5 "SCRIPT ERROR" "$LOG" >&2
        exit 1
    fi

    # The GUT 7.4.3 run summary ends with a Totals block containing
    # "Failing tests     N". Strip ANSI colour codes before matching.
    local fail_line
    fail_line="$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -E '^Failing tests[[:space:]]+[0-9]+' | tail -n 1)"
    if [ -z "$fail_line" ]; then
        echo "FAIL: $name — no GUT summary found (run aborted before finishing?)." >&2
        exit 1
    fi

    local fail_count="${fail_line##*[[:space:]]}"
    if [ "$fail_count" -ne 0 ]; then
        echo "FAIL: $name — $fail_count failing test(s)." >&2
        exit 1
    fi
}

run_phase "Unit suites" -gdir="$UNIT_DIRS" -ginclude_subdirs -gexit
run_phase "Integration playthrough (final gate)" -gdir=res://tests/integration -ginclude_subdirs -gexit

echo "All test phases passed."
