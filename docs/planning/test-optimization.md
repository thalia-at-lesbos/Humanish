---
title: "Test Suite Optimization"
role: planning
summary: >
  Targeted refactors for the GUT test suite that reduce computational load while
  preserving coverage and abstraction. The suite runs 915+ tests across 71 files
  in two CI phases; the heaviest patterns are unnecessary DataDB re-parsing,
  redundant map generation via setup_facade, and duplicated per-test iteration
  over the default grassland map.
audience:
  - Developers and coding agents maintaining the test suite
  - Reviewers evaluating performance versus coverage trade-offs
key_files:
  - tests/support/sim_fixture.gd   # shared scaffolding (all changes land here)
  - tests/sim/test_combat.gd        # _rng() duplication, setup_facade use
  - tests/sim/test_worker_actions.gd # redundant all_tiles() loops, all_techs pattern
  - tests/api/test_facade.gd        # setup_facade → bare_facade candidates
  - tests/api/test_player_ai.gd     # redundant loops, personality test cost
  - tests/sim/test_eras.gd          # make_db() calls, setup_facade use
  - tests/scenes/test_tech_chooser.gd # setup_facade candidates
  - src/core/data_db.gd             # add deep-copy constructor or clone method
sections:
  "1": "Cached DataDB template — avoid JSON re-parse on every make_gs()"
  "2": "Replace setup_facade with bare_facade where no real map is needed"
  "3": "Remove redundant all_tiles() → grassland iteration"
  "4": "Add all_techs() helper to sim_fixture"
  "5": "Reduce default map size in make_gs()"
  "6": "Consolidate duplicated _rng() into sim_fixture"
  "7": "Trim AI personality test turn count"
  "8": "Merge duplicate private helpers in test_player_ai"
editorial_rule: >
  This document governs the test-optimization branch. Edit freely with user
  consent; each section corresponds to one commit. Coverage may not regress:
  every modified test must still pass the full `./run_tests.sh` sequence.
---

# Test Suite Optimization

## 1. Cached DataDB template

**Problem:** `make_gs()` calls `make_db()` → `load_all()` which parses ~20 JSON
files from disk. With 915+ tests across 71 files, many creating their own
`GameState`, the same JSON files are parsed hundreds of times per `./run_tests.sh`.

**Solution:** Store a one-time-loaded `DataDB` template in `sim_fixture.gd`:

```gdscript
var _template_db = null

func make_db():
    if _template_db == null:
        _template_db = load("res://src/core/data_db.gd").new()
        _template_db.load_all()
    var copy = load("res://src/core/data_db.gd").new()
    for prop in _template_db.get_property_list():
        if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and typeof(_template_db.get(prop.name)) == TYPE_DICTIONARY:
            copy.set(prop.name, _template_db.get(prop.name).duplicate(true))
    return copy
```

Tests that mutate `gs.db` (e.g. injecting unit types for flanking/withdrawal
tests) still get an independent dictionary via `duplicate(true)`.

---

## 2. Replace setup_facade with bare_facade where possible

**Problem:** `setup_facade()` triggers `SimFacade.setup()` → `MapGen.generate()`,
which procedurally builds a full map. ~25 calls in the suite do not need a real
map — they test founding, research, palace logic, or UI scaffolding.

**Candidates** (all can use `make_gs()` + `bare_facade()` + manual unit placement):

| File | Test methods |
|---|---|
| `tests/api/test_facade.gd` | `test_found_settlement_creates_settlement`, `test_found_settlement_too_close_fails`, `test_first_city_is_founded_with_a_palace`, `test_only_the_first_city_gets_a_palace`, `test_set_research_command` (lines 30–136) |
| `tests/sim/test_eras.gd` | `test_setup_seeds_era_from_starting_techs` (line 133) |
| `tests/scenes/test_tech_chooser.gd` | All 5 tests (lines 22–78) — UI state only |
| `tests/scenes/test_save_load_screen.gd` | All 10 tests — UI scaffolding only |
| `tests/sim/test_combat.gd` | `test_unit_can_attack_adjacent_enemy` (line 197) — immediately overwrites all terrain to grassland anyway |

**Note:** Movement tests that need pathfinding on varied terrain (e.g.
`test_move_stack_command_succeeds_on_open_map`) should keep `setup_facade`.

---

## 3. Remove redundant all_tiles() → grassland iteration

**Problem:** `make_gs()` already sets every tile's `terrain_id = "grassland"`.
~20 test functions repeat this full-map loop, touching 400 tiles to set them to
a value they already hold.

**Remove these loops** in:

- `tests/sim/test_worker_actions.gd` — lines 248, 394, 414
- `tests/api/test_player_ai.gd` — lines 239, 253, 265, 280
- `tests/api/test_facade.gd` — lines 143, 155, 174, 192

These functions use the default grassland map and do not change terrain before
the loop, so the reset is a no-op.

---

## 4. Add all_techs() helper to sim_fixture

**Problem:** 10 tests in `test_worker_actions.gd` write
`gs.db.technologies.keys().duplicate()` to grant the player every tech. This
creates a large array copy each time.

**Solution:** Add to `sim_fixture.gd`:

```gdscript
var _all_techs = null

func all_techs(db):
    if _all_techs == null:
        _all_techs = db.technologies.keys()
    return _all_techs
```

Replace `gs.db.technologies.keys().duplicate()` with `all_techs(gs.db)` in
all 10 sites.

---

## 5. Reduce default map size in make_gs()

**Problem:** Default `make_gs()` allocates a 20×20 map (400 tiles). The
majority of tests use only 2–5 tiles. The per-initialization loop that sets
every tile to grassland is pure overhead.

**Solution:** Change the default to 10×10 (100 tiles). Tests that need a larger
map pass explicit dimensions:

```gdscript
func make_gs(num_players = 2, seed_val = 42, w = 10, h = 10):
```

The few callers that rely on 20-wide coordinates (e.g. `test_best_city_site_avoids_low_yield_region`
which checks `t.x <= 10`, or `test_found_settlement_too_close_fails` which settles at
`x=20`) can pass `20, 20` explicitly.

---

## 6. Consolidate duplicated _rng() into sim_fixture

**Problem:** `test_combat.gd` and `test_rng.gd` each define their own `_rng()`
helper that duplicates the RNG creation pattern already in `make_gs()`.

**Solution:** Add to `sim_fixture.gd`:

```gdscript
func make_rng(seed_val):
    var r = load("res://src/core/rng.gd").new()
    r.init(seed_val)
    return r
```

Replace the two private `_rng()` definitions with the shared helper.

---

## 7. Trim AI personality test turn count

**Problem:** `test_contrasting_leaders_play_rounded_game()` runs 16 full
turns × 2 AI players (32 AI `take_turn` calls) on a `setup_facade("small")`
map — the single heaviest unit test by weight.

**Solution:** Reduce `PERSONALITY_TURNS` from 16 to 8. Both leaders
consistently found a city and garrison it within 6 turns; 8 provides a safety
margin while cutting ~50% of the test's runtime.

---

## 8. Merge duplicate private helpers in test_player_ai

**Problem:** `_run_full_turn_hash()` and `_run_units_world()` in
`test_player_ai.gd` share ~85% of their body (same `make_gs` + `ai_facade` +
`make_settlement` + `make_warrior` + `state_hash` pattern).

**Solution:** Factor into a single parameterized helper that accepts an
optional seed and variant flag:

```gdscript
func _run_ai_state(seed_val = 31337, with_worker = false):
    var gs = make_gs(1, seed_val)
    var f = ai_facade(gs)
    gs.current_player_id = 1
    make_settlement(gs, 1, 5, 5)
    make_warrior(gs, 1, 5, 5)
    if with_worker:
        make_unit(gs, "worker", 1, 11, 11)
    PlayerAI.manage_units(f, 1)
    return f.state_hash()
```

Both callers inline to `_run_ai_state()` and `_run_ai_state(31337, true)`.

---

## Execution order

The refactors are independent. Apply in the numbered order above and run
`./run_tests.sh` after each commit. The integration gate
(`test_playthrough_save_load_determinism_midgame`) must still pass — it is the
fastest check that no key-type coercion bug was introduced by the DataDB copy.
