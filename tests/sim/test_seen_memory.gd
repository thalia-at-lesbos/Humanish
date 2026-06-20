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

# §fog — persistent per-player fog-of-war memory (SeenMemory + GameState
# serialization). Seeing a tile records its last-seen snapshot; moving out of
# sight retains the LAST-SEEN values even after the live tile changes; a
# never-seen tile has no memory; memory survives a save/load round-trip with int
# ids intact and a stable state hash.

func _commit(gs, pid):
	# Snapshot the player's current visibility into their memory, the way the turn
	# pipeline does at end of player_step.
	SeenMemory.commit_visible(gs, pid, TurnEngine.player_visible_set(gs, pid))

func test_seeing_a_tile_records_its_snapshot() -> void:
	var gs = make_gs(1, 7, 20, 20)
	var pid = gs.players[0].id
	make_unit(gs, "warrior", pid, 5, 5)
	# Give the standing tile some distinctive state to remember.
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "plains"
	t.improvement_id = "farm"
	t.owner_player_id = pid

	_commit(gs, pid)

	assert_true(SeenMemory.has_seen(gs, pid, 5, 5), "Standing tile is seen")
	var snap = SeenMemory.snapshot(gs, pid, 5, 5)
	assert_eq(snap.get("terrain_id"), "plains", "Remembers terrain")
	assert_eq(snap.get("improvement_id"), "farm", "Remembers improvement")
	assert_eq(int(snap.get("owner_player_id")), pid, "Remembers border owner")

func test_never_seen_tile_has_no_memory() -> void:
	var gs = make_gs(1, 7, 20, 20)
	var pid = gs.players[0].id
	make_unit(gs, "warrior", pid, 5, 5)
	_commit(gs, pid)
	# A far corner the lone warrior cannot see.
	assert_false(SeenMemory.has_seen(gs, pid, 19, 19), "Unseen far tile has no memory")
	assert_true(SeenMemory.snapshot(gs, pid, 19, 19).empty(), "…and an empty snapshot")

func test_last_seen_retained_after_live_tile_changes_out_of_sight() -> void:
	var gs = make_gs(1, 7, 20, 20)
	var pid = gs.players[0].id
	var u = make_unit(gs, "warrior", pid, 5, 5)
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "plains"
	t.improvement_id = "farm"
	t.owner_player_id = pid

	# See it, then walk far away (out of sight) without re-committing.
	_commit(gs, pid)
	u.x = 18
	u.y = 18

	# The LIVE tile mutates out of the player's sight: terrain razed, road built,
	# border lost.
	t.terrain_id = "desert"
	t.improvement_id = "road"
	t.owner_player_id = -1

	# Re-commit the new (distant) visibility; (5,5) is no longer visible, so its
	# snapshot is NOT overwritten and keeps the last-seen values.
	_commit(gs, pid)

	var snap = SeenMemory.snapshot(gs, pid, 5, 5)
	assert_eq(snap.get("terrain_id"), "plains", "Out-of-sight tile keeps last-seen terrain")
	assert_eq(snap.get("improvement_id"), "farm", "…and last-seen improvement")
	assert_eq(int(snap.get("owner_player_id")), pid, "…and last-seen border owner")

func test_remembered_settlement_owner_recorded() -> void:
	var gs = make_gs(2, 7, 20, 20)
	var observer = gs.players[0].id
	var rival = gs.players[1].id
	# Observer's scout next to a rival city, so it falls in sight.
	make_unit(gs, "warrior", observer, 5, 5)
	make_settlement(gs, rival, 6, 5)

	_commit(gs, observer)
	var snap = SeenMemory.snapshot(gs, observer, 6, 5)
	assert_false(snap.empty(), "Rival city tile is remembered")
	assert_eq(int(snap.get("settlement_owner")), rival, "Remembers the city's owner")

	# A tile with no settlement records the NO_SETTLEMENT sentinel.
	var bare = SeenMemory.snapshot(gs, observer, 5, 5)
	assert_eq(int(bare.get("settlement_owner")), SeenMemory.NO_SETTLEMENT,
		"Tile with no settlement records the sentinel")

func test_memory_survives_save_load_roundtrip_with_int_ids() -> void:
	var gs = make_gs(2, 7, 20, 20)
	var observer = gs.players[0].id
	var rival = gs.players[1].id
	make_unit(gs, "warrior", observer, 5, 5)
	var t = gs.map.get_tile(5, 5)
	t.owner_player_id = observer
	make_settlement(gs, rival, 6, 5)
	_commit(gs, observer)

	var json = JSON.print(gs.serialize())
	var parsed = JSON.parse(json).result
	var gs2 = GameState.deserialize(parsed, gs.db)

	# Player-id key coerced back to int: an int lookup must still find the memory.
	assert_true(gs2.seen_memory.has(observer),
		"Memory keyed by int player id survives load (no float/string key drift)")
	var snap = SeenMemory.snapshot(gs2, observer, 6, 5)
	assert_false(snap.empty(), "Tile snapshot survives load")
	# Snapshot int fields coerced back to int.
	assert_eq(typeof(snap.get("owner_player_id")), TYPE_INT, "owner_player_id is int after load")
	assert_eq(typeof(snap.get("settlement_owner")), TYPE_INT, "settlement_owner is int after load")
	assert_eq(int(snap.get("settlement_owner")), rival, "Remembered city owner intact after load")
	var bsnap = SeenMemory.snapshot(gs2, observer, 5, 5)
	assert_eq(int(bsnap.get("owner_player_id")), observer, "Remembered border owner intact after load")

func test_memory_save_load_state_hash_stable() -> void:
	# Mirror the determinism discipline: a save → load → save round-trip must
	# produce byte-identical JSON (so state_hash is stable) with memory present.
	var gs = make_gs(2, 7, 20, 20)
	var observer = gs.players[0].id
	make_unit(gs, "warrior", observer, 5, 5)
	gs.map.get_tile(5, 5).owner_player_id = observer
	_commit(gs, observer)

	var json1 = JSON.print(gs.serialize())
	var gs2 = GameState.deserialize(JSON.parse(json1).result, gs.db)
	var json2 = JSON.print(gs2.serialize())
	assert_eq(json1.hash(), json2.hash(),
		"Save→load→save JSON hash is stable with seen memory present")

func test_ai_player_skips_memory_in_pipeline() -> void:
	# AIs read full state and render no fog, so player_step does not build memory
	# for them (bounding save size).
	var gs = make_gs(1, 7, 20, 20)
	var pid = gs.players[0].id
	gs.players[0].is_ai = true
	make_unit(gs, "warrior", pid, 5, 5)
	gs.current_player_id = pid
	TurnEngine.player_step(gs, pid, hooks())
	assert_false(gs.seen_memory.has(pid), "AI player accrues no fog memory")

func test_human_player_step_commits_memory() -> void:
	var gs = make_gs(1, 7, 20, 20)
	var pid = gs.players[0].id   # not AI by default
	make_unit(gs, "warrior", pid, 5, 5)
	gs.current_player_id = pid
	TurnEngine.player_step(gs, pid, hooks())
	assert_true(gs.seen_memory.has(pid), "Human player step commits fog memory")
	assert_true(SeenMemory.has_seen(gs, pid, 5, 5), "…including the unit's tile")
