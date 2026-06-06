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

# The presentation-facing facade contract: dirty flags, selection state, capability
# queries, interface modes, the popup queue, widget help text, display-gating
# queries, and the unit-mission commands the HUD issues.

func _city(facade, player_id, x, y):
	return make_settlement(facade.get_state(), player_id, x, y, 2)

func _unit(facade, player_id, unit_type, x, y):
	return make_unit(facade.get_state(), unit_type, player_id, x, y).id

# ── Dirty flags ───────────────────────────────────────────────────────────────

func test_dirty_flags_set_by_move_stack() -> void:
	var f = setup_facade(1)
	var gs = f.get_state()
	# Guarantee passable land for the move (the generated map may place water here).
	gs.map.get_tile(2, 2).terrain_id = "grassland"
	gs.map.get_tile(3, 2).terrain_id = "grassland"
	_unit(f, gs.players[0].id, "warrior", 2, 2)
	gs.current_player_id = gs.players[0].id
	f.apply_command(Commands.move_stack(gs.players[0].id, 2, 2, 3, 2))
	assert_true(f.get_dirty().is_dirty(IDs.DirtyRegion.WORLD), "move_stack must dirty the WORLD region")

func test_dirty_flags_set_by_set_sliders() -> void:
	var f = setup_facade(2)
	var gs = f.get_state()
	gs.current_player_id = gs.players[0].id
	f.apply_command(Commands.set_sliders(gs.players[0].id, 50, 30, 10, 10))
	assert_true(f.get_dirty().is_dirty(IDs.DirtyRegion.HUD_GROUPS), "set_sliders must dirty HUD_GROUPS")

func test_dirty_flags_clear_after_read() -> void:
	var f = setup_facade(3)
	var gs = f.get_state()
	gs.current_player_id = gs.players[0].id
	f.apply_command(Commands.set_sliders(gs.players[0].id, 50, 30, 10, 10))
	var dirty = f.get_dirty()
	assert_true(dirty.is_dirty(IDs.DirtyRegion.HUD_GROUPS), "Flag should be dirty before clearing")
	dirty.clear(IDs.DirtyRegion.HUD_GROUPS)
	assert_false(dirty.is_dirty(IDs.DirtyRegion.HUD_GROUPS), "Flag should be clear after clear()")

# ── Selection ─────────────────────────────────────────────────────────────────

func test_select_unit_updates_selection_state() -> void:
	var f = setup_facade(4)
	var uid = _unit(f, f.get_state().players[0].id, "warrior", 3, 3)
	f.select_unit(uid)
	assert_eq(f.get_selection().head_unit(), uid, "head_unit should equal the selected unit id")

func test_select_city_updates_selection_state() -> void:
	var f = setup_facade(5)
	var cid = _city(f, f.get_state().players[0].id, 5, 5).id
	f.select_city(cid)
	assert_eq(f.get_selection().head_city(), cid, "head_city should equal the selected city id")

func test_select_stack_selects_all_owned_units_on_tile() -> void:
	var f = setup_facade(6)
	var gs = f.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = _unit(f, pid, "warrior", 4, 4)
	var b = _unit(f, pid, "scout", 4, 4)
	# An enemy unit and a friendly unit elsewhere must be excluded.
	_unit(f, gs.players[1].id, "warrior", 4, 4)
	_unit(f, pid, "archer", 9, 9)

	var n = f.select_stack(4, 4)
	assert_eq(n, 2, "Only the two owned units on the tile are selected")
	var ids = f.get_selection().selected_unit_ids
	assert_true(a in ids and b in ids, "Both owned units on the tile are in the selection")
	assert_eq(f.get_selection().head_unit(), a, "Head is the first owned unit in spawn order")

func test_cycle_idle_units_visits_all_idle() -> void:
	var f = setup_facade(6)
	var gs = f.get_state()
	var pid = gs.players[0].id
	var uid1 = _unit(f, pid, "warrior", 2, 2)
	var uid2 = _unit(f, pid, "warrior", 4, 4)
	gs.current_player_id = pid
	f.cycle_idle_units()
	var first = f.get_selection().head_unit()
	f.cycle_idle_units()
	var second = f.get_selection().head_unit()
	assert_true(first != second, "Cycling twice should select a different idle unit")
	assert_true(first == uid1 or first == uid2, "First cycled unit must be one of the idle units")

# ── Capability queries ──────────────────────────────────────────────────────────

func test_can_do_control_end_turn_allowed() -> void:
	assert_true(setup_facade(7).can_do_control(IDs.ControlType.END_TURN),
		"END_TURN control should always be allowed")

func test_can_handle_action_blocked_by_mode() -> void:
	var f = setup_facade(8)
	var uid = _unit(f, f.get_state().players[0].id, "warrior", 2, 2)
	f.select_unit(uid)
	f.enter_interface_mode(IDs.InterfaceMode.PLACE_PING)
	assert_false(f.can_handle_action(0, 3, 2),
		"Actions should be blocked in a non-SELECTION interface mode")

# ── Interface mode ──────────────────────────────────────────────────────────────

func test_interface_mode_tile_validity_in_go_to_mode() -> void:
	var f = setup_facade(9)
	var uid = _unit(f, f.get_state().players[0].id, "warrior", 2, 2)
	f.select_unit(uid)
	f.enter_interface_mode(IDs.InterfaceMode.GO_TO)
	assert_true(f.get_mode_tile_validity(3, 2) > 0, "Adjacent in-bounds tile should be valid in GO_TO mode")
	assert_eq(f.get_mode_tile_validity(-1, -1), 0, "Out-of-bounds tile should be invalid in GO_TO mode")

# ── Popup queue ───────────────────────────────────────────────────────────────

func test_popup_queue_serializes_and_pops_in_order() -> void:
	var f = setup_facade(10)
	f.push_popup({"type": IDs.PopupType.TEXT_NOTICE, "text": "Hello"})
	f.push_popup({"type": IDs.PopupType.CONFIRM, "text": "Sure?"})
	var first = f.get_pending_popup()
	assert_eq(int(first.get("type", -1)), IDs.PopupType.TEXT_NOTICE,
		"First pending popup should be TEXT_NOTICE")
	f.resolve_popup({})
	var second = f.get_pending_popup()
	assert_eq(int(second.get("type", -1)), IDs.PopupType.CONFIRM,
		"Second pending popup should be CONFIRM after first resolved")

# ── Widget help text ──────────────────────────────────────────────────────────

func test_widget_help_unit_returns_nonempty_string() -> void:
	var f = setup_facade(11)
	var uid = _unit(f, f.get_state().players[0].id, "warrior", 2, 2)
	var help = f.widget_help({"type": IDs.WidgetType.UNIT_MODEL, "data1": uid})
	assert_true(help.length() > 0, "Unit widget help must be non-empty")
	assert_true("warrior" in help or "Strength" in help, "Unit help should describe the unit")

func test_widget_help_finance_breakdown_contains_numbers() -> void:
	var f = setup_facade(12)
	var help = f.widget_help({"type": IDs.WidgetType.HELP_FINANCE, "data1": f.get_state().players[0].id})
	assert_true(help.length() > 0, "Finance help must be non-empty")
	assert_true("Treasury" in help or "Finance" in help, "Finance help should contain relevant keywords")

func test_widget_help_tech_lists_prereqs() -> void:
	var f = setup_facade(13)
	var help = f.widget_help({"type": IDs.WidgetType.TECH_NODE, "tech_id": "iron_working"})
	assert_true("bronze_working" in help, "iron_working help text should list its prereq 'bronze_working'")

# ── Display-gating queries ──────────────────────────────────────────────────────

func test_end_turn_state_ready_when_no_pending_orders() -> void:
	# Fresh setup has no units, so no idle units to prompt about.
	assert_eq(setup_facade(14).get_end_turn_state(), 0,
		"End turn state should be 0 (ready) when no idle units exist")

func test_flyout_menu_nonempty_on_owned_unit_tile() -> void:
	var f = setup_facade(15)
	var gs = f.get_state()
	_unit(f, gs.players[0].id, "warrior", 4, 4)
	gs.current_player_id = gs.players[0].id
	assert_true(f.get_flyout_menu(4, 4).size() > 0,
		"Flyout menu should have at least one item on a tile with the player's unit")

# ── Unit-mission commands ───────────────────────────────────────────────────────

func test_unit_mission_commands_accepted_by_facade() -> void:
	var f = setup_facade(16)
	var gs = f.get_state()
	var pid = gs.players[0].id
	var uid = _unit(f, pid, "warrior", 2, 2)
	gs.current_player_id = pid

	assert_true(f.apply_command(Commands.unit_fortify(pid, uid)), "unit_fortify should be accepted")
	assert_true(gs.get_unit(uid).is_fortified, "Unit should be fortified after unit_fortify")

	assert_true(f.apply_command(Commands.unit_wake(pid, uid)), "unit_wake should be accepted")
	assert_false(gs.get_unit(uid).is_fortified, "Unit should not be fortified after unit_wake")

	assert_true(f.apply_command(Commands.mission_skip_turn(pid, uid)), "mission_skip_turn should be accepted")
	assert_true(gs.get_unit(uid).has_moved, "Unit should have has_moved set after skip")

# ── Additional controls (§3.1) ──────────────────────────────────────────────────

func test_new_advisor_controls_emit_screen_requested() -> void:
	var f = setup_facade(31)
	var gs = f.get_state()
	var pid = gs.current_player_id
	var ctrls = [
		IDs.ControlType.OPEN_RELIGION, IDs.ControlType.OPEN_CORPORATION,
		IDs.ControlType.OPEN_TURN_LOG, IDs.ControlType.OPEN_DOMESTIC_ADVISOR,
		IDs.ControlType.OPEN_VICTORY_PROGRESS, IDs.ControlType.OPEN_OPTIONS,
		IDs.ControlType.TOGGLE_SCORE,
	]
	watch_signals(f)
	for ctrl in ctrls:
		assert_true(f.apply_command(Commands.do_control(pid, ctrl)),
			"do_control %d should be accepted" % ctrl)
	assert_signal_emit_count(f, "screen_requested", ctrls.size(),
		"each new control should emit screen_requested once")

# ── Gift (§3.2) ─────────────────────────────────────────────────────────────────

func test_gift_transfers_unit_ownership() -> void:
	var f = setup_facade(32)
	var gs = f.get_state()
	var giver = gs.players[0].id
	var receiver = gs.players[1].id
	gs.current_player_id = giver
	var uid = _unit(f, giver, "warrior", 3, 3)
	assert_true(f.apply_command(Commands.unit_gift(giver, uid, receiver)),
		"unit_gift should be accepted")
	assert_eq(gs.get_unit(uid).owner_player_id, receiver,
		"Gifted unit should belong to the receiver")

func test_gift_to_self_is_rejected() -> void:
	var f = setup_facade(33)
	var gs = f.get_state()
	var giver = gs.players[0].id
	gs.current_player_id = giver
	var uid = _unit(f, giver, "warrior", 3, 3)
	assert_false(f.apply_command(Commands.unit_gift(giver, uid, giver)),
		"Gifting a unit to its own owner should be rejected")

# ── Additional unit missions (§3.3) ──────────────────────────────────────────────

func test_new_unit_missions_accepted_by_facade() -> void:
	# Flat-grassland fixture map so the moving missions have a clear path.
	var gs = make_gs(2, 34)
	var f = bare_facade(gs)
	var pid = gs.players[0].id
	gs.current_player_id = pid

	var s = make_unit(gs, "warrior", pid, 5, 5).id
	assert_true(f.apply_command(Commands.mission_sentry(pid, s)), "sentry accepted")
	assert_true(gs.get_unit(s).is_sentry, "sentry sets is_sentry")

	var h = make_unit(gs, "warrior", pid, 7, 7).id
	assert_true(f.apply_command(Commands.mission_heal(pid, h)), "heal accepted")
	assert_true(gs.get_unit(h).is_healing, "heal sets is_healing")

	var a = make_unit(gs, "warrior", pid, 9, 9).id
	assert_true(f.apply_command(Commands.mission_air_patrol(pid, a)), "air patrol accepted")
	assert_true(gs.get_unit(a).is_patrolling, "air/sea patrol sets is_patrolling")

	var mover = make_unit(gs, "warrior", pid, 2, 2).id
	var target = make_unit(gs, "warrior", pid, 2, 3).id
	assert_true(f.apply_command(Commands.mission_move_to_unit(pid, mover, target)),
		"move_to_unit accepted")

	var scout = make_unit(gs, "scout", pid, 12, 12).id
	assert_true(f.apply_command(Commands.mission_recon(pid, scout, 12, 13)),
		"recon accepted")

func test_sentry_unit_skipped_by_idle_cycle() -> void:
	var f = setup_facade(35)
	var gs = f.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = _unit(f, pid, "warrior", 4, 4)
	f.apply_command(Commands.mission_sentry(pid, u))
	f.cycle_idle_units(false)
	assert_eq(f.get_selection().head_unit(), -1,
		"A sentried unit should not be cycled to as an idle unit")
