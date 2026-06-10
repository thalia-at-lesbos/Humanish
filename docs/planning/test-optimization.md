---
title: "Test Suite Optimization"
role: planning
summary: >
  Three vetted refactors for the GUT test suite that cut computational load
  without regressing coverage. The suite runs ~833 test methods across 71 files
  in two CI phases; the heaviest *avoidable* cost is repeated DataDB JSON
  re-parsing on every game state, followed by needless full map generation via
  setup_facade and a scattering of no-op per-tile grassland resets. A larger
  grab-bag of micro-optimizations was assessed and dropped — see "Rejected
  items" for why (aliasing risk, base-class constraints, coverage loss, and
  out-of-bounds breakage).
audience:
  - Developers and coding agents maintaining the test suite
  - Reviewers evaluating performance versus coverage trade-offs
key_files:
  - tests/support/sim_fixture.gd     # shared scaffolding; §1 lands here
  - src/core/data_db.gd              # the table holder §1 caches/copies
  - tests/api/test_facade.gd         # §2 bare_facade candidates; §3 no-op loops
  - tests/sim/test_eras.gd           # §2 bare_facade candidate
  - tests/scenes/test_tech_chooser.gd     # §2 bare_facade candidates (UI state)
  - tests/scenes/test_save_load_screen.gd # §2 bare_facade candidates (UI scaffolding)
  - tests/sim/test_combat.gd         # §2 candidate; overwrites terrain anyway
  - tests/api/test_player_ai.gd      # §3 no-op grassland loops
  - tests/sim/test_worker_actions.gd # §3 no-op grassland loops
sections:
  "1": "Cached DataDB template — avoid JSON re-parse on every make_gs()"
  "2": "Replace setup_facade with bare_facade where no real map is needed"
  "3": "Remove redundant all_tiles() → grassland resets"
  "Rejected items": "Assessed-and-dropped optimizations and the reason each was cut"
  "Execution": "Branch, ordering, and the verification gate"
editorial_rule: >
  This document governs the test/suite-optimization branch. Edit freely with
  user consent; each numbered section corresponds to one commit. Coverage may
  not regress: every modified test must still pass the full `./run_tests.sh`
  sequence, and each change must be justified by a measured before/after.
---

# Test Suite Optimization

Scope: implement §1–§3 only. Each is independent of the others and lands as its
own commit. Quantify the win — capture `time ./run_tests.sh` before the branch
and after each commit; if a change shows no measurable improvement, drop it
rather than carry complexity for its own sake.

---

## 1. Cached DataDB template

**Problem:** `make_gs()` calls `make_db()` → `DataDB.load_all()`, which opens and
`JSON.parse`s ~23 files from `data/` and then runs `_validate()`. Almost every
test builds at least one `GameState`, so the same tables are re-parsed and
re-validated hundreds of times across a single `./run_tests.sh`. This is the
largest *avoidable* repeated cost in the suite.

**Constraint that shapes the design:** a non-trivial number of suites mutate
`gs.db` in-place to set up a scenario — e.g. `test_combat.gd` injects
`gs.db.units["raider_horse"]`/`["coward"]`/`["test_catapult"]` and
`gs.db.structures["test_bastion"]`; `test_nuclear`, `test_culture_revolt`,
`test_naval_raiders`, and `test_trade_routes` poke `gs.db.constants`/
`difficulties`. **The cache cannot be shared by reference** — each state needs an
independent copy so one test's injection can't leak into another.

**Solution sketch:** keep a single parsed template in `sim_fixture.gd` and hand
every caller a deep copy of its tables.

```gdscript
var _template_db = null

func make_db():
    if _template_db == null:
        _template_db = load("res://src/core/data_db.gd").new()
        _template_db.load_all()
    var copy = load("res://src/core/data_db.gd").new()
    for prop in _template_db.get_property_list():
        if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE \
                and typeof(_template_db.get(prop.name)) == TYPE_DICTIONARY:
            copy.set(prop.name, _template_db.get(prop.name).duplicate(true))
    return copy
```

Notes / pitfalls to handle while implementing:
- **Deep copy is mandatory** (`duplicate(true)`), not shallow — the injection
  sites above mutate nested dictionaries (`db.difficulties["warlord"][...]`), so
  a one-level copy would still alias the template.
- The reflection filter copies only `TYPE_DICTIONARY` script variables, so the
  `_errors: Array` field is intentionally skipped and the copy never runs
  `load_all()`/`_validate()`. That means `copy.get_errors()` is always `[]`.
  Confirm no fixture-based test reads `get_errors()` (data-validation lives in
  `tests/core/test_data_db.gd`, which builds its own `DataDB` directly and is
  unaffected). Add a short comment on the helper saying so.
- **Measure parse-vs-duplicate.** Deep-duplicating 23 tables per call is itself
  not free; the win is real only if it beats file IO + `JSON.parse` +
  `_validate`. Expected to be a clear net positive, but record the numbers. If
  the duplicate cost dominates for the large tables, a fallback is to copy
  lazily / share read-only tables and deep-copy only on first mutation — but
  that is more machinery and only worth it if the simple version disappoints.
- **Determinism gate is the safety net.** A key-type or aliasing regression in
  the copy surfaces in `tests/integration`
  (`test_playthrough_save_load_determinism_midgame`); run it explicitly.

---

## 2. Replace setup_facade with bare_facade where no real map is needed

**Problem:** `setup_facade()` runs the full new-game path — `SimFacade.setup()` →
`MapGen.generate()` — procedurally building and painting a whole map. A number
of tests pay that cost while exercising founding, research, palace logic, or
pure UI scaffolding that never touches generated terrain.

**Solution sketch:** convert those to `make_gs()` + `bare_facade(gs)` +
explicit unit/settlement placement (the flat grassland map `make_gs` already
provides). `bare_facade` wires `_gs/_db/_dirty/_hooks` exactly as production
`setup()` does, so command handlers and the turn pipeline still work.

**Per file, the procedure is the same:**
1. Swap the `setup_facade(...)` call for `make_gs(num_players, seed)` + `bare_facade(gs)`.
2. Set `gs.current_player_id` and place whatever units/cities the test asserts on.
3. Run the test in isolation (`-gunit_test_name=…`) and confirm the **asserted
   count is unchanged** — a method that errors mid-way still reports green in
   GUT (see CLAUDE.md "Recurring debugging gotchas"), so the assert count is the
   real proof it still exercises what it did before.

**Candidates** (verify each still passes after conversion):

| File | Tests | Why a real map is unnecessary |
|---|---|---|
| `tests/api/test_facade.gd` | founding + palace + `set_research` group | founding/research logic only; placement is explicit |
| `tests/sim/test_eras.gd` | `test_setup_seeds_era_from_starting_techs` | reads starting-tech → era; no terrain |
| `tests/scenes/test_tech_chooser.gd` | all UI-state tests | UI scaffolding only |
| `tests/scenes/test_save_load_screen.gd` | all UI scaffolding tests | UI scaffolding only |
| `tests/sim/test_combat.gd` | `test_unit_can_attack_adjacent_enemy` | already overwrites the whole map to grassland (line ~199) |

**Explicitly keep `setup_facade`** for anything that needs generated/varied
terrain or pathfinding (e.g. `test_move_stack_command_succeeds_on_open_map`) —
converting those would change what they cover.

---

## 3. Remove redundant all_tiles() → grassland resets

**Problem:** `make_gs()` already sets every tile's `terrain_id = "grassland"`.
A handful of tests then repeat a full-map `for tile in gs.map.all_tiles(): tile.terrain_id = "grassland"` loop, re-writing 400 tiles to the value they
already hold. Pure overhead.

**Safety predicate (apply per loop, do not blanket-delete):** a loop is a
removable no-op **iff** (a) the state came straight from `make_gs()` with no
intervening terrain change before the loop, and (b) the loop body does nothing
but set `terrain_id = "grassland"`. Loops that set a *non*-grassland terrain, or
that run after the test has already customised terrain, must stay.

**Confirmed-removable sites** (line numbers as of this writing — match the
pattern, don't trust the numbers, since earlier edits already made the previous
plan's line refs stale):
- `tests/api/test_facade.gd` — the grassland-reset loops at ~143, 155, 174, 192.
- `tests/api/test_player_ai.gd` — ~239, 253, 265, 280.
- `tests/sim/test_worker_actions.gd` — ~356 (and sweep for the same pattern at
  ~502, 522; confirm each precedes any terrain customisation).

Do **not** assume every `all_tiles()` loop qualifies — `test_map_gen`,
`test_regions`, `test_influence`, `test_pathfinding`, and several others iterate
tiles to *read* or to set varied terrain; those are out of scope. Grep
`all_tiles()`, then hand-check each hit against the safety predicate.

Expected payoff here is small (≈8–10 loops × 400 tiles, one-time per test); it is
included as low-risk cleanup that rides along with §1/§2, not as a headline win.

---

## Rejected items

Assessed against the code and dropped. Recorded so they are not re-proposed:

- **Shared `all_techs()` cache** — the result is assigned to
  `player.technologies`; returning one cached array aliases it across tests, so
  any code appending a researched tech corrupts the cache. The `.duplicate()` it
  would remove is a cheap shallow copy of ~N id-strings. Risk ≫ benefit.
- **Shared `make_rng()` in `sim_fixture`** — `tests/core/test_rng.gd` extends
  `addons/gut/test.gd` directly (the pure-math-suite convention in CLAUDE.md),
  not `sim_fixture`, so it cannot call a fixture helper without violating that
  convention. Only `test_combat.gd` could use it; not worth a shared helper.
- **Trim AI personality test 16→8 turns** — this is a genuine coverage
  reduction (shrinks the "no early self-destruct" observation window), not a
  free optimization, and the saving was asserted, never measured. Left as-is.
- **Shrink default `make_gs()` map 20×20 → 10×10** — unsafe: ~356 unit/settlement
  placements across the suite sit at coordinate ≥11 (settlements at (14,14),
  (15,15), (17,17); units at (15,5), (17,17), …) and would fall off a 10×10 map,
  yielding null tiles and broken adjacency/sight/pathing. Tiny payoff (one
  one-time tile fill) against a large breakage surface.
- **Merge `_run_full_turn_hash()`/`_run_units_world()` in test_player_ai** — pure
  readability tidy with no runtime saving; out of scope for a performance pass.

---

## Execution

Branch: `test/suite-optimization`. The three refactors are independent; apply in
order, one commit each:

1. Capture baseline `time ./run_tests.sh`.
2. §1 cached DataDB template → run full suite + the determinism integration test;
   record the new time.
3. §2 bare_facade conversions → run each converted file in isolation (assert
   counts unchanged), then the full suite.
4. §3 no-op loop removal → full suite.

The integration gate (`test_playthrough_save_load_determinism_midgame`) must
still pass after §1 — it is the fastest check that the DataDB copy introduced no
key-type/aliasing regression. Drop any section that shows no measurable win.
