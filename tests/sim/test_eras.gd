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

# §1 Era system (provisional). Covers the derived player era, the age-table
# lookups, refresh/advancement queuing, era-scaled growth thresholds, and the
# facade surface (get_player_era + the era_advanced drain).

# ── Tech / unit / structure era mapping ───────────────────────────────────────

func test_era_of_tech_maps_to_age_index():
	var db = make_db()
	assert_eq(Eras.era_of_tech("agriculture", db), 0, "agriculture is Ancient")
	assert_eq(Eras.era_of_tech("alphabet", db), 1, "alphabet is Classical")
	assert_eq(Eras.era_of_tech("feudalism", db), 2, "feudalism is Medieval")
	assert_eq(Eras.era_of_tech("fusion", db), 6, "fusion is Future")

func test_era_of_unknown_tech_is_ancient():
	var db = make_db()
	assert_eq(Eras.era_of_tech("not_a_tech", db), 0, "unknown tech degrades to Ancient")

func test_era_of_unit_follows_required_tech():
	var db = make_db()
	# A no-tech starter sits in the Ancient era; a tech-gated unit inherits its
	# required tech's era (asserted against the tech mapping so it survives retuning).
	assert_eq(Eras.era_of_unit("warrior", db), 0, "warrior needs no tech -> Ancient")
	var u = db.get_unit("executive")
	if not u.empty():
		assert_eq(Eras.era_of_unit("executive", db),
			Eras.era_of_tech(str(u.get("tech_required", "")), db),
			"a tech-gated unit inherits its required tech's era")

func test_era_of_structure_uses_tag_or_tech():
	var db = make_db()
	# Granary carries no era tag, so it falls back to its tech (pottery → Ancient).
	assert_eq(Eras.era_of_structure("granary", db), 0, "granary falls back to pottery's era")

# ── Player era is the highest researched era ──────────────────────────────────

func test_player_era_is_max_over_techs():
	var gs = make_gs(1)
	var p = gs.players[0]
	assert_eq(Eras.player_era(p, gs.db), 0, "no techs -> Ancient")
	p.technologies = ["agriculture"]
	assert_eq(Eras.player_era(p, gs.db), 0, "Ancient tech keeps the player Ancient")
	p.technologies = ["agriculture", "alphabet"]
	assert_eq(Eras.player_era(p, gs.db), 1, "a Classical tech advances the player")
	# Order does not matter; the maximum wins.
	p.technologies = ["feudalism", "agriculture"]
	assert_eq(Eras.player_era(p, gs.db), 2, "max era over the set, regardless of order")

func test_player_era_null_is_ancient():
	var db = make_db()
	assert_eq(Eras.player_era(null, db), 0, "a null/wild player is Ancient")

# ── Age-table lookups ─────────────────────────────────────────────────────────

func test_age_table_lookups():
	var db = make_db()
	assert_eq(Eras.era_name(1, db), "Classical", "index 1 names Classical")
	assert_eq(Eras.era_id(2, db), "medieval", "index 2 is the medieval id")
	assert_eq(Eras.max_index(db), 6, "the shipped table tops out at Future (6)")

func test_growth_threshold_scale_rises_with_era():
	var db = make_db()
	assert_eq(Eras.growth_threshold_scale(0, db), 100, "Ancient growth is unscaled")
	assert_eq(Eras.growth_threshold_scale(2, db), 110, "Medieval slows growth")
	assert_eq(Eras.growth_threshold_scale(6, db), 130, "Future slows growth most")

# ── refresh() advancement queuing ─────────────────────────────────────────────

func test_refresh_queues_advance_on_increase():
	var gs = make_gs(1)
	var p = gs.players[0]
	p.technologies = ["alphabet"]   # Classical
	var gained = Eras.refresh(p, gs.db, gs)
	assert_eq(gained, 1, "advanced one era step")
	assert_eq(p.era, 1, "the cache is updated")
	assert_eq(gs.pending_era_advances.size(), 1, "an advancement was queued")
	assert_eq(int(gs.pending_era_advances[0]["to"]), 1, "queued the new era")

func test_refresh_is_idempotent():
	var gs = make_gs(1)
	var p = gs.players[0]
	p.technologies = ["alphabet"]
	Eras.refresh(p, gs.db, gs)
	gs.pending_era_advances = []
	var gained = Eras.refresh(p, gs.db, gs)   # no new tech
	assert_eq(gained, 0, "no further advance without a new era")
	assert_eq(gs.pending_era_advances.size(), 0, "nothing re-queued")

func test_refresh_without_gs_updates_cache_only():
	var gs = make_gs(1)
	var p = gs.players[0]
	p.technologies = ["feudalism"]
	var gained = Eras.refresh(p, gs.db)   # gs omitted
	assert_eq(gained, 2, "cache jumped to Medieval")
	assert_eq(p.era, 2, "cache set without a game state")

# ── Growth threshold honours the player's era ─────────────────────────────────

func test_settlement_growth_slows_in_later_era():
	# Same settlement, same food: a Medieval owner needs more food to grow than an
	# Ancient one (growth_threshold_scale 110 vs 100).
	var ancient_pop = _grow_under_techs([])
	var medieval_pop = _grow_under_techs(["feudalism"])
	assert_true(medieval_pop <= ancient_pop,
		"a later era never grows faster than Ancient for the same inputs")

# Run one growth step for a 1-pop city sitting on enough food to just clear the
# Ancient threshold, and report the resulting population.
func _grow_under_techs(techs):
	var gs = make_gs(1)
	var p = gs.players[0]
	p.technologies = techs.duplicate()
	var s = make_settlement(gs, p.id, 5, 5, 1)
	# Park a big food store right at the Ancient threshold (growth_base 20 * pop 1).
	s.food_store = 20
	TurnEngine._settlement_growth(gs, s, p)
	return s.population

# ── Facade surface ────────────────────────────────────────────────────────────

func test_setup_seeds_era_from_starting_techs():
	var f = setup_facade()
	var gs = f.get_state()
	var info = f.get_player_era(gs.players[0].id)
	assert_eq(int(info["index"]), Eras.player_era(gs.players[0], gs.db),
		"get_player_era reflects the live era")
	assert_true(info.has("name") and info.has("id"), "era info carries id + name")

func test_drain_era_advances_emits_signal_and_notifies():
	var gs = make_gs(2)
	var f = bare_facade(gs)
	f._notifications = []
	gs.pending_era_advances = [{"player_id": gs.players[0].id, "from": 0, "to": 1}]
	watch_signals(f)
	f._drain_era_advances()
	assert_signal_emitted(f, "era_advanced", "era_advanced fired")
	assert_eq(gs.pending_era_advances.size(), 0, "the queue is cleared after draining")
	assert_eq(f._notifications.size(), 1, "a notification was raised")

# ── Save/load round-trip ──────────────────────────────────────────────────────

func test_player_era_round_trips():
	var gs = make_gs(1)
	gs.players[0].era = 3
	var restored = Player.deserialize(gs.players[0].serialize())
	assert_eq(restored.era, 3, "Player.era survives serialize/deserialize")
