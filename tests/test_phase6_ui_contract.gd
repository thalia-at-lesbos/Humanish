extends "res://addons/gut/test.gd"

# Phase 6A: UI contract — dirty flags, selection, interface mode, popup queue,
# widget help text, display-gating queries, and new unit commands.

func _make_facade(sv = 1234):
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, sv, "tiny", "normal", "warlord",
		[
			{"name": "Alice", "leader_id": "", "traits": [], "starting_gold": 50},
			{"name": "Bob",   "leader_id": "", "traits": [], "starting_gold": 50}
		],
		["last_standing", "time"])
	return facade

func _place_unit(facade, player_id, unit_type, x, y):
	var gs = facade.get_state()
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = unit_type
	u.owner_player_id = player_id
	u.x = x; u.y = y
	var udata = facade._db.get_unit(unit_type)
	u.base_strength = int(udata.get("base_strength", 10))
	u.health = 100
	u.movement_total = int(udata.get("movement", 200))
	u.movement_left = u.movement_total
	gs.units.append(u)
	return u.id

func _place_city(facade, player_id, x, y):
	var gs = facade.get_state()
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id()
	s.name = "TestCity"
	s.owner_player_id = player_id
	s.x = x; s.y = y
	s.population = 2
	gs.settlements.append(s)
	return s.id

# ── Dirty flags ───────────────────────────────────────────────────────────────

func test_dirty_flags_set_by_move_stack() -> void:
	var f = _make_facade(1)
	var gs = f.get_state()
	var uid = _place_unit(f, gs.players[0].id, "warrior", 2, 2)
	gs.current_player_id = gs.players[0].id
	f.apply_command(Commands.move_stack(gs.players[0].id, 2, 2, 3, 2))
	assert_true(f.get_dirty().is_dirty(IDs.DirtyRegion.WORLD),
		"move_stack must dirty the WORLD region")

func test_dirty_flags_set_by_set_sliders() -> void:
	var f = _make_facade(2)
	var gs = f.get_state()
	gs.current_player_id = gs.players[0].id
	f.apply_command(Commands.set_sliders(gs.players[0].id, 50, 30, 10, 10))
	assert_true(f.get_dirty().is_dirty(IDs.DirtyRegion.HUD_GROUPS),
		"set_sliders must dirty HUD_GROUPS")

func test_dirty_flags_clear_after_read() -> void:
	var f = _make_facade(3)
	var gs = f.get_state()
	gs.current_player_id = gs.players[0].id
	f.apply_command(Commands.set_sliders(gs.players[0].id, 50, 30, 10, 10))
	var dirty = f.get_dirty()
	assert_true(dirty.is_dirty(IDs.DirtyRegion.HUD_GROUPS),
		"Flag should be dirty before clearing")
	dirty.clear(IDs.DirtyRegion.HUD_GROUPS)
	assert_false(dirty.is_dirty(IDs.DirtyRegion.HUD_GROUPS),
		"Flag should be clear after clear()")

# ── Selection ─────────────────────────────────────────────────────────────────

func test_select_unit_updates_selection_state() -> void:
	var f = _make_facade(4)
	var gs = f.get_state()
	var uid = _place_unit(f, gs.players[0].id, "warrior", 3, 3)
	f.select_unit(uid)
	assert_eq(f.get_selection().head_unit(), uid,
		"head_unit should equal the selected unit id")

func test_select_city_updates_selection_state() -> void:
	var f = _make_facade(5)
	var gs = f.get_state()
	var cid = _place_city(f, gs.players[0].id, 5, 5)
	f.select_city(cid)
	assert_eq(f.get_selection().head_city(), cid,
		"head_city should equal the selected city id")

func test_cycle_idle_units_visits_all_idle() -> void:
	var f = _make_facade(6)
	var gs = f.get_state()
	var pid = gs.players[0].id
	var uid1 = _place_unit(f, pid, "warrior", 2, 2)
	var uid2 = _place_unit(f, pid, "warrior", 4, 4)
	gs.current_player_id = pid
	f.cycle_idle_units()
	var first = f.get_selection().head_unit()
	f.cycle_idle_units()
	var second = f.get_selection().head_unit()
	assert_true(first != second,
		"Cycling twice should select a different idle unit")
	assert_true(first == uid1 or first == uid2,
		"First cycled unit must be one of the idle units")

# ── Capability queries ────────────────────────────────────────────────────────

func test_can_do_control_end_turn_allowed() -> void:
	var f = _make_facade(7)
	assert_true(f.can_do_control(IDs.ControlType.END_TURN),
		"END_TURN control should always be allowed")

func test_can_handle_action_move_blocked_by_mode() -> void:
	var f = _make_facade(8)
	var gs = f.get_state()
	var uid = _place_unit(f, gs.players[0].id, "warrior", 2, 2)
	f.select_unit(uid)
	f.enter_interface_mode(IDs.InterfaceMode.PLACE_PING)
	assert_false(f.can_handle_action(0, 3, 2),
		"Actions should be blocked in a non-SELECTION interface mode")

# ── Interface mode ────────────────────────────────────────────────────────────

func test_interface_mode_tile_validity_in_go_to_mode() -> void:
	var f = _make_facade(9)
	var gs = f.get_state()
	var uid = _place_unit(f, gs.players[0].id, "warrior", 2, 2)
	f.select_unit(uid)
	f.enter_interface_mode(IDs.InterfaceMode.GO_TO)
	assert_true(f.get_mode_tile_validity(3, 2) > 0,
		"Adjacent in-bounds tile should be valid in GO_TO mode")
	assert_eq(f.get_mode_tile_validity(-1, -1), 0,
		"Out-of-bounds tile should be invalid in GO_TO mode")

# ── Popup queue ───────────────────────────────────────────────────────────────

func test_popup_queue_serializes_and_pops_in_order() -> void:
	var f = _make_facade(10)
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
	var f = _make_facade(11)
	var gs = f.get_state()
	var uid = _place_unit(f, gs.players[0].id, "warrior", 2, 2)
	var help = f.widget_help({"type": IDs.WidgetType.UNIT_MODEL, "data1": uid})
	assert_true(help.length() > 0, "Unit widget help must be non-empty")
	assert_true("warrior" in help or "Strength" in help,
		"Unit help should describe the unit")

func test_widget_help_finance_breakdown_contains_numbers() -> void:
	var f = _make_facade(12)
	var gs = f.get_state()
	var help = f.widget_help({"type": IDs.WidgetType.HELP_FINANCE, "data1": gs.players[0].id})
	assert_true(help.length() > 0, "Finance help must be non-empty")
	assert_true("Treasury" in help or "Finance" in help,
		"Finance help should contain relevant keywords")

func test_widget_help_tech_lists_prereqs() -> void:
	var f = _make_facade(13)
	var help = f.widget_help({"type": IDs.WidgetType.TECH_NODE, "tech_id": "iron_working"})
	assert_true("mining" in help,
		"iron_working help text should list its prereq 'mining'")

# ── Display-gating queries ────────────────────────────────────────────────────

func test_end_turn_state_ready_when_no_pending_orders() -> void:
	var f = _make_facade(14)
	# Fresh setup has no units, so no idle units to prompt about
	assert_eq(f.get_end_turn_state(), 0,
		"End turn state should be 0 (ready) when no idle units exist")

func test_flyout_menu_nonempty_on_owned_unit_tile() -> void:
	var f = _make_facade(15)
	var gs = f.get_state()
	_place_unit(f, gs.players[0].id, "warrior", 4, 4)
	gs.current_player_id = gs.players[0].id
	var menu = f.get_flyout_menu(4, 4)
	assert_true(menu.size() > 0,
		"Flyout menu should have at least one item on a tile with the player's unit")

# ── New unit commands ─────────────────────────────────────────────────────────

func test_new_unit_commands_accepted_by_facade() -> void:
	var f = _make_facade(16)
	var gs = f.get_state()
	var pid = gs.players[0].id
	var uid = _place_unit(f, pid, "warrior", 2, 2)
	gs.current_player_id = pid

	var ok_fortify = f.apply_command(Commands.unit_fortify(pid, uid))
	assert_true(ok_fortify, "unit_fortify should be accepted")
	assert_true(gs.get_unit(uid).is_fortified, "Unit should be fortified after unit_fortify")

	var ok_wake = f.apply_command(Commands.unit_wake(pid, uid))
	assert_true(ok_wake, "unit_wake should be accepted")
	assert_false(gs.get_unit(uid).is_fortified, "Unit should not be fortified after unit_wake")

	var ok_skip = f.apply_command(Commands.mission_skip_turn(pid, uid))
	assert_true(ok_skip, "mission_skip_turn should be accepted")
	assert_true(gs.get_unit(uid).has_moved, "Unit should have has_moved set after skip")
