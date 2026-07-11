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

# Beliefs (§8): founding requires a settlement to host the holy site, and an
# adopted belief contributes to a city's contentment.

func test_player_founds_belief_when_eligible() -> void:
	var gs = make_gs()
	make_settlement(gs, 1, 5, 5)
	# Eligibility is tech-gated: grant a founding tech (meditation → buddhism).
	var p = gs.get_player(1)
	p.technologies.append("meditation")
	Eras.refresh(p, gs.db)
	var founded = Beliefs.try_found(1, gs, gs.rng)
	assert_ne(founded, "", "A player with a settlement founds an eligible belief")
	assert_eq(gs.founded_beliefs.get(founded, -1), 1, "Founder recorded")
	assert_eq(gs.get_settlement_at(5, 5).belief_id, founded, "Settlement becomes the holy site")

func test_no_belief_founded_without_settlement() -> void:
	var gs = make_gs()
	var founded = Beliefs.try_found(1, gs, gs.rng)
	assert_eq(founded, "", "No belief is founded without a settlement to host it")
	assert_true(gs.founded_beliefs.empty(), "No belief recorded as founded")

func test_belief_adds_happiness() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	var base_pos: int = s.positive_sentiment
	s.belief_id = "buddhism"  # happiness_bonus: 1
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	assert_gt(s.positive_sentiment, base_pos, "An adopted belief raises positive sentiment")
