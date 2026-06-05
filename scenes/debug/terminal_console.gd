# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Node

# Terminal-side debug console. In a windowed debug build this spawns a worker
# thread that blocks on stdin and feeds each typed line into the SHARED
# DebugConsole engine (the same one the '~' overlay uses). State mutation must
# happen on the main thread, so the reader only hands lines back via
# call_deferred — it never touches GameState itself.
#
# It deliberately does NOT start under headless/GUT runs (detected from the
# command line), because there is no interactive terminal there and reading the
# script-mode stdin would interfere with the test harness.

var _console        # DebugConsole
var _thread: Thread
var _running: bool = false

func init(console) -> void:
	_console = console

# Begin reading stdin on a worker thread. No-op unless this is an interactive
# windowed debug build.
func start_console() -> void:
	if not _is_interactive_debug():
		return
	if _console == null:
		return
	_running = true
	_thread = Thread.new()
	_thread.start(self, "_read_loop")
	print("[DBG] terminal console ready — type 'help' (commands run on the game thread)")

# True only for an interactive, windowed debug build. Excludes release exports
# and the headless/GUT test runner (`--no-window -s addons/gut/gut_cmdln.gd`).
func _is_interactive_debug() -> bool:
	if not OS.is_debug_build():
		return false
	for arg in OS.get_cmdline_args():
		if arg == "--no-window" or arg.find("gut_cmdln") != -1:
			return false
	return true

# Worker thread: block on stdin, hand each non-empty line to the main thread.
func _read_loop(_userdata) -> void:
	while _running:
		var line: String = OS.read_string_from_stdin().strip_edges()
		if not _running:
			break
		if line == "":
			continue
		call_deferred("_run_line", line)

# Runs on the main thread (via call_deferred), so it is safe to mutate state.
func _run_line(line: String) -> void:
	if _console == null:
		return
	var out: String = _console.execute(line)
	if out != "":
		print(out)

func _exit_tree() -> void:
	# Signal the reader to stop. A thread parked in read_string_from_stdin only
	# unblocks on the next line, so on quit you may need to press Enter once in
	# the terminal for the join to complete (documented in docs/design/debug.md).
	_running = false
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
		_thread = null
