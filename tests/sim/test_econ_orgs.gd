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

# Economic organizations (§8 / §15.22): founded by a special person, spread only
# by the deliberate executive action — the reference has no organic spread.

func test_special_person_founds_econ_org() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.current_research_id = ""  # no research -> try econ org before gold
	var s = make_settlement(gs, 1, 5, 5, 5)
	TurnEngine._apply_special_person(gs, s)
	assert_ne(s.econ_org_id, "", "A special person seeds an economic organization")
	assert_true(gs.founded_econ_orgs.has(s.econ_org_id), "Org recorded as founded")

func test_no_organic_spread() -> void:
	# §15.22: corporations have NO passive spread channel — an adjacent city
	# never gains a franchise on its own, however many turns pass.
	var gs = make_gs()
	gs.get_player(1).treasury = 1000
	var s1 = make_settlement(gs, 1, 5, 5, 5)
	var s2 = make_settlement(gs, 1, 6, 5, 5)
	EconOrgs.found("civilized_jewelers", s1, gs)
	var h = hooks()
	for _i in range(20):
		TurnEngine.world_step(gs, h)
	assert_eq(s2.econ_org_id, "",
		"a corporation never spreads passively to an adjacent settlement")
	# The organic-channel data keys are gone from the table (dead-key hygiene).
	var org = gs.db.econ_orgs.get("civilized_jewelers", {})
	assert_false(org.has("spread_chance_base"), "organic spread_chance_base key removed")
	assert_false(org.has("spread_cost"), "organic spread_cost key removed")
	assert_eq(int(org.get("spread_base_cost", 0)), 50, "§29.17 spread_base_cost shipped")
	assert_eq(int(org.get("spread_factor", 0)), 200, "§29.17 spread_factor shipped")

# ── §14.6 corporation model: HQ, executive, resource-count output, maintenance ──

# Place a connected resource tile owned by `player_id` (resource + the improvement
# its connection requires, with the player granted the resource's tech).
func _give_resource(gs, player_id, x, y, res_id) -> void:
	var res = gs.db.get_resource(res_id)
	var tile = gs.map.get_tile(x, y)
	tile.owner_player_id = player_id
	tile.resource_id = res_id
	var imp = res.get("improvement_required", null)
	if imp != null and imp != "":
		tile.improvement_id = imp
	var tech = res.get("tech_required", null)
	if tech != null and tech != "":
		gs.get_player(player_id).technologies.append(tech)

func test_found_corporation_erects_hq_structure() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("cereal_mills", s, gs)
	assert_true(s.has_structure("cereal_mills_hq"),
		"Founding a corporation erects its HQ structure in the founding city")

func test_output_scales_with_accessible_input_instances() -> void:
	# §15.10: output = rate × input-resource INSTANCES / 100 (cereal_mills: food 75).
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("cereal_mills", s, gs)
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 0, 0],
		"No accessible inputs yields no corporation output")
	_give_resource(gs, 1, 1, 1, "wheat")
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 0, 0],
		"One instance truncates: 75 × 1 / 100 = 0 food (integer math)")
	_give_resource(gs, 1, 2, 1, "rice")
	assert_eq(EconOrgs.get_output_delta(gs, s), [1, 0, 0],
		"Two instances: 75 × 2 / 100 = 1 food")
	_give_resource(gs, 1, 3, 1, "corn")
	assert_eq(EconOrgs.get_output_delta(gs, s), [2, 0, 0],
		"Three instances: 75 × 3 / 100 = 2 food")
	_give_resource(gs, 1, 4, 1, "wheat")  # a SECOND wheat copy
	assert_eq(EconOrgs.get_output_delta(gs, s), [3, 0, 0],
		"Every connected copy counts — instances, not distinct resources")

func test_traded_resource_counts_as_accessible_input() -> void:
	# §7 deal plumbing: a resource received through an active recurring deal counts
	# as an accessible corporation input instance, exactly like one connected at home.
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("mining_inc", s, gs)  # production 100 per input instance
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 0, 0],
		"no inputs yet, so no corporation output")
	# Player 2 supplies iron to player 1 (the city owner / accepter) via a deal.
	gs.deals.append({
		"id": 1, "a_alliance": 1, "b_alliance": 2,
		"proposer_player_id": 2, "accepter_player_id": 1,
		"recurring": {"give": {"resources": ["iron"]}, "receive": {}},
		"start_turn": 0, "min_duration": 10
	})
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 1, 0],
		"a traded-in resource counts as an accessible input instance")
	# Ending the deal removes the access again.
	gs.deals.clear()
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 0, 0],
		"access lapses with the deal")

func test_research_channel_scales_with_instances() -> void:
	# aluminum_co: research 300 per coal instance, routed via settlement_channel.
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("aluminum_co", s, gs)
	assert_eq(EconOrgs.settlement_channel(gs, s, "research"), 0,
		"no coal, no research output")
	_give_resource(gs, 1, 1, 1, "coal")
	assert_eq(EconOrgs.settlement_channel(gs, s, "research"), 3,
		"one coal instance: 300 × 1 / 100 = 3 research")
	_give_resource(gs, 1, 2, 1, "coal")
	assert_eq(EconOrgs.settlement_channel(gs, s, "research"), 6,
		"two coal instances: 300 × 2 / 100 = 6 research")

func test_culture_channel_feeds_settlement_culture() -> void:
	# sids_sushi: food 50 + culture 200 per seafood/rice instance.
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("sids_sushi", s, gs)
	_give_resource(gs, 1, 1, 1, "fish")
	_give_resource(gs, 1, 2, 1, "rice")
	assert_eq(EconOrgs.get_output_delta(gs, s), [1, 0, 0],
		"two instances: 50 × 2 / 100 = 1 food (culture is not a yield column)")
	assert_eq(EconOrgs.settlement_channel(gs, s, "culture"), 4,
		"two instances: 200 × 2 / 100 = 4 culture")
	var before: int = s.culture_total
	TurnEngine._settlement_culture(gs, s, p)
	assert_eq(s.culture_total - before, 4,
		"the corporation culture channel accrues in _settlement_culture")

func test_gold_channel_flows_into_gold_income() -> void:
	# civilized_jewelers: gold 100 per instance — raw gold, outside the commerce split.
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("civilized_jewelers", s, gs)
	_give_resource(gs, 1, 1, 1, "gold")
	_give_resource(gs, 1, 2, 1, "silver")
	_give_resource(gs, 1, 3, 1, "gems")
	assert_eq(EconOrgs.settlement_channel(gs, s, "gold"), 3,
		"three instances: 100 × 3 / 100 = 3 gold")
	# gold_income = jewelers gold channel (3) + HQ gold (4 per franchise × 1 city).
	assert_eq(TurnEngine.gold_income(gs, p), 7,
		"corporation gold and HQ franchise gold both land in gold_income")

func test_produced_resource_granted_while_org_operates() -> void:
	# §15.10: standard_ethanol provides Oil to the owner of any member city.
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	assert_false(EconOrgs.accessible_resources(gs, 1).has("oil"),
		"no oil access before the corporation exists")
	EconOrgs.found("standard_ethanol", s, gs)
	assert_true(EconOrgs.accessible_resources(gs, 1).has("oil"),
		"a member city's owner gains the produced resource")
	p.policies["economic"] = "state_property"  # corporations_disabled
	assert_false(EconOrgs.accessible_resources(gs, 1).has("oil"),
		"a banning civic suspends the produced-resource grant")
	p.policies.erase("economic")
	s.econ_org_id = ""
	assert_false(EconOrgs.accessible_resources(gs, 1).has("oil"),
		"the grant disappears with the last member city")

func test_produced_resource_counts_as_input_instance() -> void:
	# aluminum_co's produced Aluminum feeds creative_constructions' input list.
	var gs = make_gs()
	var s1 = make_settlement(gs, 1, 5, 5, 5)
	var s2 = make_settlement(gs, 1, 9, 9, 5)
	EconOrgs.found("aluminum_co", s1, gs)          # produces aluminum
	EconOrgs.found("creative_constructions", s2, gs)
	_give_resource(gs, 1, 1, 1, "stone")
	# creative_constructions sees 2 instances: the stone tile + the produced aluminum.
	assert_eq(EconOrgs.get_output_delta(gs, s2), [0, 1, 0],
		"produced aluminum counts as an input instance: production 50 × 2 / 100 = 1")
	assert_eq(EconOrgs.settlement_channel(gs, s2, "culture"), 6,
		"culture 300 × 2 / 100 = 6")

func test_maintenance_scales_per_resource_instance() -> void:
	# §15.10: maintenance_per_resource 100 = 1 gold per input instance per franchise.
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("civilized_jewelers", s, gs)
	assert_eq(EconOrgs.maintenance_for(gs, gs.db, p), 0,
		"no accessible inputs, no maintenance")
	_give_resource(gs, 1, 1, 1, "gold")
	_give_resource(gs, 1, 2, 1, "silver")
	_give_resource(gs, 1, 3, 1, "gems")
	assert_eq(EconOrgs.maintenance_for(gs, gs.db, p), 3,
		"one franchise × 3 instances × 100 / 100 = 3 gold")
	var s2 = make_settlement(gs, 1, 9, 9, 5)
	EconOrgs.spread_to("civilized_jewelers", s2, gs)
	assert_eq(EconOrgs.maintenance_for(gs, gs.db, p), 6,
		"a second franchise doubles the charge")
	p.policies["economic"] = "free_market"  # -50% corporation maintenance
	assert_eq(EconOrgs.maintenance_for(gs, gs.db, p), 3,
		"Free Market halves corporation maintenance")

func test_hq_pays_founder_per_franchise() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("cereal_mills", s, gs)
	assert_eq(EconOrgs.hq_gold_for(gs, gs.db, p), 4,
		"The HQ pays the founder 4 gold per franchise, inputs or none")
	var s2 = make_settlement(gs, 1, 9, 9, 5)
	EconOrgs.spread_to("cereal_mills", s2, gs)
	assert_eq(EconOrgs.hq_gold_for(gs, gs.db, p), 8,
		"Every member city worldwide is a paying franchise")

func test_banning_civic_disables_corporations() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("mining_inc", s, gs)
	_give_resource(gs, 1, 1, 1, "iron")
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 1, 0],
		"the corporation produces before the ban")
	p.policies["economic"] = "state_property"  # corporations_disabled
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 0, 0],
		"A state-property economy yields no corporation output")
	assert_eq(EconOrgs.maintenance_for(gs, gs.db, p), 0,
		"A banning civic charges no corporation maintenance")

# ── §15.22 executive spread: cost formula, success roll, eligibility ──────────

# Standard executive-spread scaffold: player 1 founds civilized_jewelers in s1
# and has an executive standing on s2 (a second city at 10,10). Returns
# [gs, p, s2, exe]. Gold access (an input resource) is given unless withheld.
func _spread_setup(with_resource = true, s2_owner = 1):
	var gs = make_gs()
	var p = gs.get_player(1)
	p.treasury = 200
	gs.current_player_id = 1
	var s1 = make_settlement(gs, 1, 5, 5, 5)
	var s2 = make_settlement(gs, s2_owner, 10, 10, 5)
	EconOrgs.found("civilized_jewelers", s1, gs)  # player 1 owns the corporation
	if with_resource:
		_give_resource(gs, s2_owner, 1, 1, "gold")  # the target CITY owner's access
	var exe = make_unit(gs, "executive", 1, 10, 10)
	return [gs, p, s2, exe]

func test_executive_spread_cost_scales_with_inflation() -> void:
	# §15.22 step 1: cost = spread_base_cost × (100 + inflation) / 100, truncating.
	var gs = make_gs()
	var s = make_settlement(gs, 1, 10, 10, 5)
	EconOrgs.found("civilized_jewelers", make_settlement(gs, 1, 5, 5, 5), gs)
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s, 1, 0), 50,
		"zero inflation: the bare base cost 50")
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s, 1, 20), 60,
		"20% inflation: 50 × 120 / 100 = 60")
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s, 1, 7), 53,
		"7% inflation truncates: 50 × 107 / 100 = 53")

func test_executive_spread_cost_foreign_doubles_vassal_exempt() -> void:
	# §15.22 step 2: ×2 into a foreign city; a vassal's city prices as domestic.
	var gs = make_gs()
	EconOrgs.found("civilized_jewelers", make_settlement(gs, 1, 5, 5, 5), gs)
	var s2 = make_settlement(gs, 2, 10, 10, 5)  # player 2 = alliance 2, foreign
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s2, 1, 0), 100,
		"a foreign non-vassal city doubles the cost: 50 × 2 = 100")
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s2, 1, 20), 120,
		"inflation applies before the foreign doubling: 60 × 2 = 120")
	gs.get_alliance(2).is_subordinate_to = 1
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s2, 1, 0), 50,
		"a vassal's city is not foreign-priced")

func test_executive_spread_cost_competition_surcharge() -> void:
	# §15.22 step 3: ×(100 + spread_factor)/100 = ×3 per competing incumbent
	# (sharing an input resource). Structurally faithful; vacuous in play under
	# one-corporation-per-city, where an incumbent blocks spread outright.
	var gs = make_gs()
	EconOrgs.found("civilized_jewelers", make_settlement(gs, 1, 5, 5, 5), gs)
	var s2 = make_settlement(gs, 1, 10, 10, 5)
	s2.econ_org_id = "mining_inc"  # shares gold+silver with civilized_jewelers
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s2, 1, 0), 150,
		"a competing incumbent triples the cost: 50 × 300 / 100 = 150")
	var s3 = make_settlement(gs, 2, 12, 12, 5)
	s3.econ_org_id = "mining_inc"
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s3, 1, 0), 300,
		"foreign + competing incumbent: 50 × 2 × 3 = 300")
	s2.econ_org_id = "cereal_mills"  # wheat/corn/rice — no shared input
	assert_eq(EconOrgs.executive_spread_cost(gs, "civilized_jewelers", s2, 1, 0), 50,
		"a non-competing incumbent adds no surcharge")

func test_executive_spread_chance_formula() -> void:
	# §15.22 success roll: strength 40, halved foreign, interpolated toward 100
	# by open corporation slots (7 corporations shipped). Worked §29.17 values.
	var gs = make_gs()
	EconOrgs.found("civilized_jewelers", make_settlement(gs, 1, 5, 5, 5), gs)
	assert_eq(EconOrgs.total_corporations(gs.db), 7, "seven corporations shipped")
	var own = make_settlement(gs, 1, 10, 10, 5)
	var foreign = make_settlement(gs, 2, 12, 12, 5)
	assert_eq(EconOrgs.executive_spread_chance(gs, "civilized_jewelers", own, 1), 100,
		"an empty own-team city is a guaranteed spread (exactly 100)")
	assert_eq(EconOrgs.executive_spread_chance(gs, "civilized_jewelers", foreign, 1), 100,
		"an empty foreign city is also guaranteed: 20 + 7×80/7 = 100")
	own.econ_org_id = "cereal_mills"
	assert_eq(EconOrgs.executive_spread_chance(gs, "civilized_jewelers", own, 1), 91,
		"own-team city with one incumbent: 40 + 6×60/7 = 91")
	foreign.econ_org_id = "cereal_mills"
	assert_eq(EconOrgs.executive_spread_chance(gs, "civilized_jewelers", foreign, 1), 88,
		"foreign city with one incumbent: 20 + 6×80/7 = 88")
	gs.get_alliance(2).is_subordinate_to = 1
	assert_eq(EconOrgs.executive_spread_chance(gs, "civilized_jewelers", foreign, 1), 91,
		"a vassal's city rolls at the domestic strength")

func test_executive_spread_empty_city_guaranteed_no_rng_draw() -> void:
	# Command path: an eligible (empty) city spreads with certainty and, per the
	# §15.5 no-pointless-draws discipline, without touching the shared RNG.
	var parts = _spread_setup()
	var gs = parts[0]; var p = parts[1]; var s2 = parts[2]; var exe = parts[3]
	var rng_before: String = JSON.print(gs.rng.get_state())
	var f = bare_facade(gs)
	var ok = f.apply_command(Commands.spread_corporation(1, exe.id, s2.id))
	assert_true(ok, "Executive spreads the player's corporation to the city on its tile")
	assert_eq(s2.econ_org_id, "civilized_jewelers", "The target city now hosts the corporation")
	assert_eq(p.treasury, 150, "Spreading charges the §15.22 cost (base 50, zero inflation)")
	assert_null(gs.get_unit(exe.id), "The executive is consumed on a successful spread")
	assert_eq(JSON.print(gs.rng.get_state()), rng_before,
		"a guaranteed spread makes no RNG draw (§15.5 no-pointless-draws)")

func test_executive_spread_command_cost_scales_with_inflation() -> void:
	# The command charges the live §15.1 inflation-scaled cost, not a flat fee.
	var parts = _spread_setup()
	var gs = parts[0]; var p = parts[1]; var s2 = parts[2]; var exe = parts[3]
	gs.turn_number = 190  # normal pace, offset -90 → eff 100 × 30% × prince 95% = 28
	assert_eq(TurnEngine.inflation_rate(gs), 28, "fixture inflation at turn 190 is 28%")
	var f = bare_facade(gs)
	assert_true(f.apply_command(Commands.spread_corporation(1, exe.id, s2.id)),
		"spread succeeds with inflation running")
	assert_eq(p.treasury, 200 - 64, "cost 50 × 128 / 100 = 64 charged")

func test_executive_spread_foreign_city_charges_double() -> void:
	var parts = _spread_setup(true, 2)  # target city owned by player 2
	var gs = parts[0]; var p = parts[1]; var s2 = parts[2]; var exe = parts[3]
	var f = bare_facade(gs)
	assert_true(f.apply_command(Commands.spread_corporation(1, exe.id, s2.id)),
		"an executive may spread into an eligible foreign city")
	assert_eq(s2.econ_org_id, "civilized_jewelers", "the foreign city gains the franchise")
	assert_eq(p.treasury, 100, "the foreign spread charged double: 50 × 2 = 100")

func test_executive_spread_requires_input_resource() -> void:
	# §15.22 eligibility: the target city must have one of the corporation's
	# input resources (owner-wide access in the Humanish collapse).
	var parts = _spread_setup(false)  # no gold/silver/gems anywhere
	var gs = parts[0]; var p = parts[1]; var s2 = parts[2]; var exe = parts[3]
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.spread_corporation(1, exe.id, s2.id)),
		"no input resource in reach of the city owner: spread refused")
	assert_eq(s2.econ_org_id, "", "the city stays free of the corporation")
	assert_eq(p.treasury, 200, "a refused spread charges nothing")
	assert_not_null(gs.get_unit(exe.id), "a refused spread keeps the executive")
	_give_resource(gs, 1, 1, 1, "gems")
	assert_true(f.apply_command(Commands.spread_corporation(1, exe.id, s2.id)),
		"the same spread succeeds once an input resource is accessible")

func test_executive_spread_blocked_by_incumbent() -> void:
	# One corporation per city: any incumbent — competing or not — blocks the
	# executive outright (the §15.22 surcharge/eviction collapse).
	var parts = _spread_setup()
	var gs = parts[0]; var p = parts[1]; var s2 = parts[2]; var exe = parts[3]
	s2.econ_org_id = "cereal_mills"
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.spread_corporation(1, exe.id, s2.id)),
		"a city already hosting a corporation refuses another")
	assert_eq(s2.econ_org_id, "cereal_mills", "the incumbent stays")
	assert_eq(p.treasury, 200, "a refused spread charges nothing")

func test_executive_spread_failure_still_charges() -> void:
	# §15.22: the cost is charged even on a failed roll. The sub-100 branch is
	# unreachable through the command under one-corporation-per-city (eligible
	# targets are empty ⇒ chance 100), so exercise attempt_executive_spread
	# directly against a competing incumbent (chance 91, cost 50×3 = 150).
	var gs = make_gs()
	var p = gs.get_player(1)
	EconOrgs.found("civilized_jewelers", make_settlement(gs, 1, 5, 5, 5), gs)
	var s2 = make_settlement(gs, 1, 10, 10, 5)
	var saw_success := false
	var saw_failure := false
	for seed_val in range(1, 81):
		gs.rng.init(seed_val)
		p.treasury = 1000
		s2.econ_org_id = "mining_inc"
		var r = EconOrgs.attempt_executive_spread(gs, "civilized_jewelers", s2, 1, 0)
		assert_eq(int(r["chance"]), 91, "one competing incumbent rolls at 91")
		assert_eq(p.treasury, 850, "cost 150 charged whether or not the roll succeeds")
		if bool(r["success"]):
			saw_success = true
			assert_eq(s2.econ_org_id, "civilized_jewelers",
				"a successful roll stamps the city")
		else:
			saw_failure = true
			assert_eq(s2.econ_org_id, "mining_inc",
				"a failed roll leaves the city as it was")
	assert_true(saw_success, "some seeds succeed at 91%")
	assert_true(saw_failure, "some seeds fail at 91% — and still paid")

func test_executive_spread_blocked_under_ban() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.treasury = 200
	gs.current_player_id = 1
	var s1 = make_settlement(gs, 1, 5, 5, 5)
	var s2 = make_settlement(gs, 1, 10, 10, 5)
	p.policies["economic"] = "state_property"
	EconOrgs.found("civilized_jewelers", s1, gs)
	_give_resource(gs, 1, 1, 1, "gold")
	var exe = make_unit(gs, "executive", 1, 10, 10)
	var f = bare_facade(gs)
	var ok = f.apply_command(Commands.spread_corporation(1, exe.id, s2.id))
	assert_false(ok, "An executive cannot spread a corporation under a banning civic")
	assert_eq(s2.econ_org_id, "", "The city stays free of the corporation")
