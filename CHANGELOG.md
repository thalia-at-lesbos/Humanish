# Changelog

All notable changes to Humanish are recorded here. Versions follow
[semantic versioning](https://semver.org).

## [0.5.0] - 2026-06-09

### Added
- **Three-phase AI overhaul.** Phase A — difficulty handicap (`ai_bonus`) wired
  to AI production and research (§2.2). Phase B — competent deterministic
  `PlayerAI` brain: role-ranked production, four-pass unit playbook, settler
  city-site scoring, worker automation, recon exploration (§B1–B7). Phase C —
  trait-driven strategic focus (`expand`/`military`/`economy`/`science` axes)
  layered on top (§C1–C5). Phase D — AI tuning, per-turn cost audit, and
  documentation (§D1–D3).
- **Diplomatic victory.** UN / Apostolic Palace elections with a two-candidate
  runoff; the rival candidate must be a non-defiant full member (§7.3).
- **Worker chop/clear orders.** Explicit forest and jungle removal (chop)
  with tech bonus and border-based scaling (§4.11).
- **City health and growth display.** The city screen now shows health and
  growth status.
- **Production queue editing.** Up/down reorder buttons; duplicate-item
  prevention.
- **Leader selection.** Pick a leader for your society in the New Game menu.
- **Left-button click-and-drag** pans the map; middle-click drag also pans.
- **City produce-nothing.** Cities can explicitly choose to produce nothing.
- **Base unit availability.** City build chooser always offers warrior,
  settler, and worker.
- **Difficulty per-city handicaps.** Growth, health, and happiness modifiers
  per difficulty, limited to human players (§2.2).
- **Trait health.** Leader/society trait health (Expansive +2) wired into
  wellbeing.
- **Feature health.** Worked-tile feature health wired into wellbeing (§4.6).

### Changed
- Difficulty city handicaps apply to human players only (§2.2).
- Diplomatic victory comes solely from the assembly UN election (§10).

### Fixed
- Peace-clause trade notification and bare\_facade null hooks.
- City build chooser missing base units (warrior/settler/worker).
- AI workers now automate construction (resources, then roads, then sleep).
- Work boat gated by tech and coastal access; water units in general.
- Resource-bound worker improvements require a visible resource.
- Moving a worker cancels its in-progress improvement build.
- Worker improvement builds complete over time.
- City health/growth display now visible.
- Middle-click panning was unreliable on some setups.

## [0.4.4] - 2026-06-09

### Added
- **Wild-forces overhaul.** Barbarians, raider camps, and wildlife now spawn
  with a Civilization IV: Beyond the Sword–derived model tuned per difficulty
  and game pace, keeping early turns calm and scaling threat with the world.
- **Wild animals.** Wolves, panthers, and bears roam unexplored land, hunt
  lone or unfortified units, and stay out of cities. They grant limited combat
  experience and no promotions.
- **Naval raiders.** Sea-domain wild forces patrol open water and attack
  coastal shipping once any civilization can sail.
- **Worker improvement actions.** Workers show a "Build" button for every
  improvement valid on their current tile, with full landform, tech, river,
  and feature validation.
- **Scout Explore mission.** Recon units can be set to auto-explore; they
  wander toward unseen tiles, avoid combat, skip the idle-unit cycle, and stop
  (with an alert) when an enemy comes into view.
- **Heal stances.** New "Sleep Until Healed" and "Fortify Until Healed" orders
  hold an injured unit in place until it recovers, then wake it automatically.
- **Minimap.** A fog-aware minimap in the lower-right shows explored terrain
  and your settlements; it can be toggled from the Options screen.
- **Permanent alliances.** An optional new-game rule lets allied civilizations
  form unbreakable alliances; the diplomacy screen offers the action when both
  sides are at peace.
- **Production queue editing.** Click a queued item in the City screen to
  remove it.
- **Larger games.** Setup now offers all six world sizes (Duel through Huge)
  and removes the four-player cap; the suggested player count scales with the
  chosen world size and is shown the moment the screen opens.
- **Debug builds** gain a "Toggle Fog of War" button on the Options screen.

### Changed
- **Diplomacy screen** now lists only civilizations you have actually met.
  Contact is made when either side sights the other's unit, city, or border,
  and is permanent once established.
- **Capitals can no longer be disbanded** — the Disband action is both hidden
  and rejected for the city holding your palace.
- Advisor and info screens have a consistent bottom Close/Cancel button,
  including the tech chooser.

### Fixed
- Maps now wrap correctly east–west; routes and fog reveal across the map seam.
  Island maps keep a hard geographic edge.
- Zooming now keeps the point under the cursor fixed instead of drifting.
- Wild units can no longer stack onto a city tile after winning a fight, and
  can damage but never destroy a capital.
- A confirming flash now marks the destination tile when you issue a move.
- Wild units read as "Wild …"/"Bandit …" in the tile readout instead of a
  broken owner label.
- City growth now posts a "grew to population N" notification each turn.
- Losing a unit in combat — including to wild forces — now always posts a
  notification.
- Resumed saved games stay in sync: alliance and intel data is no longer
  mismatched after a load, fixing a determinism break.
