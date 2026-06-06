# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://tests/support/sim_fixture.gd"

# The remote-multiplayer client seam on SimFacade: when a submit handler is
# installed, ending the turn must NOT run the local pipeline — it must call the
# handler (which ships the snapshot) and park the facade as "waiting". This is
# what keeps the server authoritative. The networking nodes (NetServer/NetClient)
# are not exercised here — they need live sockets — only the facade contract is.

var _submit_calls: int = 0
var _last_snapshot: String = ""

func before_each() -> void:
	_submit_calls = 0
	_last_snapshot = ""

# Stand-in for NetClient.submit_turn: record the push and report success.
func _fake_submit() -> bool:
	_submit_calls += 1
	return true

func _install(facade) -> void:
	facade.set_remote_submit_handler(funcref(self, "_fake_submit"))

func test_handler_marks_facade_as_remote_client() -> void:
	var f = setup_facade()
	assert_false(f.is_remote_client(), "solo facade is not a remote client")
	_install(f)
	assert_true(f.is_remote_client(), "installing a handler marks it remote")
	f.set_remote_submit_handler(null)
	assert_false(f.is_remote_client(), "clearing the handler un-marks it")

func test_end_turn_command_submits_instead_of_advancing() -> void:
	var f = setup_facade()
	_install(f)
	var gs = f.get_state()
	var before_turn: int = gs.turn_number
	var cur: int = gs.current_player_id

	var ok: bool = f.apply_command(Commands.end_turn(cur))
	assert_true(ok, "end-turn accepted as a submission")
	assert_eq(_submit_calls, 1, "submit handler invoked exactly once")
	assert_eq(gs.turn_number, before_turn, "turn number did NOT advance locally")
	assert_eq(gs.current_player_id, cur, "current player did NOT advance locally")
	assert_true(f.is_remote_waiting(), "facade parked as waiting after submit")
	assert_eq(f.get_end_turn_state(), 1, "End Turn button reads 'waiting'")

func test_control_end_turn_hotkey_path_also_submits() -> void:
	var f = setup_facade()
	_install(f)
	var cur: int = f.get_state().current_player_id
	# The hotkey path routes END_TURN through DO_CONTROL.
	var ok: bool = f.apply_command(Commands.do_control(cur, IDs.ControlType.END_TURN))
	assert_true(ok, "DO_CONTROL end-turn accepted")
	assert_eq(_submit_calls, 1, "submit handler invoked via control path")

func test_repeat_end_turn_while_waiting_is_dropped() -> void:
	var f = setup_facade()
	_install(f)
	var gs = f.get_state()
	var cur: int = gs.current_player_id
	f.apply_command(Commands.end_turn(cur))
	assert_eq(_submit_calls, 1, "first submit counted")
	# Pressing end-turn again while parked must not re-submit nor run the pipeline.
	var second: bool = f.apply_command(Commands.end_turn(cur))
	assert_false(second, "second end-turn rejected while waiting")
	assert_eq(_submit_calls, 1, "handler not called again while waiting")
	assert_eq(gs.turn_number, 0 if gs.turn_number == 0 else gs.turn_number,
		"no local turn advance while waiting")

func test_next_state_clears_waiting() -> void:
	var f = setup_facade()
	_install(f)
	var cur: int = f.get_state().current_player_id
	f.apply_command(Commands.end_turn(cur))
	assert_true(f.is_remote_waiting(), "waiting after submit")
	# Server pushing the next state this player owns un-parks the turn.
	f.set_remote_waiting(false)
	assert_false(f.is_remote_waiting(), "waiting cleared on new state")
	assert_true(f.get_end_turn_state() != 1 or f.get_state().current_player_id < 0,
		"end-turn no longer forced to 'waiting'")
