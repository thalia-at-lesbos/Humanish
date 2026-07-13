# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name TraitEffects

# Reads the gameplay effects carried by a player's leader traits (§4, B4) —
# the PolicyEffects analogue for `data/leaders_traits.json` "traits" entries.
# Two production-speed carriers exist (the reference trait model):
#   • `double_production_structures`: [structure ids] — the trait builds each
#     listed structure at double speed (+`trait_double_production_pct`, 100).
#   • `unit_production_modifiers`: {unit id: +%} — per-unit build-speed
#     percentages where the reference magnitude is not a flat double
#     (Imperialistic settler +50, Expansive worker +25).
# Both stack additively into the §4.3 percent chain via production_pct().

# Sum a numeric trait key across the player's traits. Absent keys contribute 0.
static func sum_int(player: Player, db: DataDB, key: String) -> int:
	var total: int = 0
	if player == null:
		return 0
	for trait_id in player.traits:
		total += int(db.get_trait(trait_id).get(key, 0))
	return total

# The summed +% production-speed modifier the player's traits grant toward the
# queued item (a `{type, id}` production-queue entry). Structures collect the
# flat double from `double_production_structures`; units the per-id percent
# from `unit_production_modifiers`. Anything else (projects) gets nothing.
static func production_pct(player: Player, db: DataDB, item: Dictionary) -> int:
	if player == null:
		return 0
	var itype: String = str(item.get("type", "unit"))
	var iid: String = str(item.get("id", ""))
	var pct: int = 0
	for trait_id in player.traits:
		var t: Dictionary = db.get_trait(trait_id)
		if itype == "structure":
			if iid in t.get("double_production_structures", []):
				pct += db.get_constant("trait_double_production_pct", 100)
		elif itype == "unit":
			pct += int(t.get("unit_production_modifiers", {}).get(iid, 0))
	return pct
