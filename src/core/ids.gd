# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name IDs

# Movement domains
enum Domain { LAND = 0, SEA = 1, AIR = 2, IMMOBILE = 3 }

# Landform categories
enum Landform { FLAT = 0, HILL = 1, PEAK = 2, WATER = 3, DEEP_WATER = 4 }

# Output vector indices
enum Output { FOOD = 0, PRODUCTION = 1, COMMERCE = 2, COUNT = 3 }

# Unit tactical classifications
enum UnitClass { MELEE = 0, RANGED = 1, CAVALRY = 2, NAVAL = 3, AIR = 4, CIVILIAN = 5, SIEGE = 6 }

# Command types sent by players through the API
enum CommandType {
    FOUND_SETTLEMENT = 0,
    MOVE_STACK = 1,
    SET_SLIDERS = 2,
    SET_PRODUCTION = 3,
    SET_RESEARCH = 4,
    SET_POLICY = 5,
    END_TURN = 6,
    DECLARE_WAR = 7,
    MAKE_PEACE = 8,
    PROPOSE_TRADE = 9,
    ACCEPT_TRADE = 10,
    REJECT_TRADE = 11,
    RUSH_PRODUCTION = 12,
    ASSIGN_WORKERS = 13,
    PILLAGE = 14,
    BUILD_IMPROVEMENT = 15,
    SPREAD_BELIEF = 16,
    JOIN_SETTLEMENT = 17,
    # Unit commands (§3.2)
    UNIT_WAKE = 18,
    UNIT_SLEEP = 19,
    UNIT_FORTIFY = 20,
    UNIT_CANCEL_ORDERS = 21,
    UNIT_DISBAND = 22,
    UNIT_UPGRADE = 23,
    UNIT_PROMOTE = 24,
    # Unit missions (§3.3)
    MISSION_MOVE_TO = 25,
    MISSION_BUILD_ROAD = 26,
    MISSION_SKIP_TURN = 27,
    MISSION_PILLAGE = 28,
    MISSION_BOMBARD = 29,
    MISSION_AIRLIFT = 30,
    # UI controls (§3.1)
    DO_CONTROL = 31,
    # Tier 2 subsystems
    ASSIGN_SPECIALIST = 32,
    ESPIONAGE_MISSION = 33,
    LOAD_UNIT = 34,
    UNLOAD_UNIT = 35,
    SET_SUBORDINATION = 36,
    # Great Person actions (§14)
    GP_ACTION = 37,
    # Additional unit command (§3.2)
    UNIT_GIFT = 38,
    # Additional unit missions (§3.3)
    MISSION_SENTRY = 39,
    MISSION_HEAL = 40,
    MISSION_MOVE_TO_UNIT = 41,
    MISSION_RECON = 42,
    MISSION_AIR_PATROL = 43,
    MISSION_SEA_PATROL = 44,
    # City citizen management (§11 city screen): manual worked-tile locks and the
    # per-city automate-citizens toggle.
    SET_TILE_WORKED = 45,
    SET_CITIZEN_AUTOMATION = 46,
    # City conquest (§4.8): voluntarily disband/raze an owned city.
    DISBAND_CITY = 47,
    # State religion (§8): adopt/switch the player's empire-wide religion ("" = none).
    SET_STATE_RELIGION = 48,
    # Diplomatic assembly vote (§7.2): cast Yea/Nay/Abstain on the open proposal.
    CAST_VOTE = 49,
    # Nuclear strike (§5.7): launch a one-use nuke at a target tile (area effect).
    NUCLEAR_STRIKE = 50,
    # Clean radioactive fallout off a worker's tile (§5.7/§11).
    MISSION_CLEAN_FALLOUT = 51,
    # Conscript a military unit from a city's population (§6.4 Nationhood).
    DRAFT = 52,
    # Spread a religion to a city with a missionary unit (§8).
    SPREAD_BELIEF = 53,
    # Heal-until-recovered stances (§3.3): unit skips turns until full health,
    # then wakes idle. FORTIFY_UNTIL_HEALED also grants the fortify defence bonus.
    MISSION_SLEEP_UNTIL_HEALED = 54,
    MISSION_FORTIFY_UNTIL_HEALED = 55,
    # Explore mission (§3.3): recon/scout auto-moves toward unexplored territory.
    MISSION_EXPLORE = 56,
    # Remove an item from a city's production queue by index (§11 city screen).
    DEQUEUE_PRODUCTION = 57,
    # Diplomacy: propose a permanent alliance with another alliance (requires the
    # permanent_alliances optional rule to be active in GameState).
    PROPOSE_PERMANENT_ALLIANCE = 58,
    # Move an item in the city production queue to a new position (§11 city screen).
    MOVE_PRODUCTION_ITEM = 59,
    # Chop/clear a removable surface feature (forest/jungle) off a worker's tile
    # without placing an improvement; a felled forest yields production (§4.11).
    MISSION_CLEAR_FEATURE = 60,
    # Resolve a random-event choice popup (§9): commit the player's chosen branch.
    RESOLVE_EVENT = 61,
    # Spread a corporation to a city with an executive unit (§14.6).
    SPREAD_CORPORATION = 62,
    # Cancel an active persistent deal (§7) once its minimum duration has elapsed.
    CANCEL_DEAL = 63,
    # Release a tributary/vassal alliance back to independence (§7, the overlord's
    # half of vassalage; a vassal also breaks free automatically once strong again).
    FREE_VASSAL = 64,
    # Cancel a standing open-borders agreement with another player (§7). Either side
    # may revoke it; their territory then blocks the other's units again.
    CANCEL_OPEN_BORDERS = 65,
    # Spy-unit-on-tile espionage mission (§7.1): a spy standing on a foreign city
    # tile with full movement runs an espionage mission against that city.
    SPY_MISSION = 66,
    # Population rush ("whipping", §15.2): sacrifice citizens to finish the head
    # production item. Gated on a civic with the `pop_rush` flag (Slavery).
    RUSH_POPULATION = 67
}

# Win condition types
enum WinType { LAST_STANDING = 0, DOMINANCE = 1, ENDGAME_PROJECT = 2, CULTURAL = 3, DIPLOMATIC = 4, TIME = 5 }

# Independently-invalidated display regions (§2 of ui design)
enum DirtyRegion { WORLD = 0, HUD_GROUPS = 1, DATA_PANES = 2, FULL_SCREENS = 3, ALL = 4 }

# Widget type tags for {type, data1, data2} uniform dispatch (§4)
enum WidgetType {
    UNIT_LIST = 0, CITY_SCROLLER = 1, TRAIN_UNIT = 2, CONSTRUCT_BUILDING = 3,
    CREATE_PROJECT = 4, RUSH_PRODUCTION = 5, CHANGE_SPECIALIST = 6,
    RESEARCH = 7, TECH_NODE = 8, CHANGE_SLIDER = 9,
    ACTION = 10, GENERIC_BUTTON = 11, CLOSE_SCREEN = 12,
    CONTACT_LEADER = 13, CANCEL_DEAL = 14, DIPLOMACY_RESPONSE = 15,
    UNIT_MODEL = 16, FLAG = 17, MINIMAP_HIGHLIGHT = 18,
    HELP_MAINTENANCE = 19, HELP_DEFENSE = 20, HELP_WELLBEING = 21,
    HELP_CONTENTMENT = 22, HELP_PRODUCTION = 23, HELP_CULTURE = 24,
    HELP_FINANCE = 25, HELP_PROMOTION = 26,
    ENCYCLOPEDIA = 27, BACK = 28, FORWARD = 29,
    SCRIPTABLE = 30
}

# Map-targeting modes: changes what a tile-click means (§5)
enum InterfaceMode {
    SELECTION = 0, PLACE_PING = 1, PLACE_SIGN = 2,
    GO_TO = 3, GO_TO_ALL = 4, ROUTE_TO = 5,
    RANGED_ATTACK = 6, AREA_BOMBARD = 7, PARADROP = 8, AIRLIFT = 9
}

# Popup kinds for the serialized dialog queue (§6)
enum PopupType {
    TEXT_NOTICE = 0, MAIN_MENU = 1, CONFIRM = 2, DECLARE_WAR_CONFIRM = 3,
    LOAD_UNIT = 4, CHOOSE_TECH = 5, RAZE_CITY = 6, CHOOSE_PRODUCTION = 7,
    CHANGE_POLICY = 8, CHOOSE_ELECTION = 9, ALARM = 10, DEAL_CANCELLED = 11,
    DIPLOMACY = 12, FOUND_BELIEF = 13, EVENT = 14, GAME_DETAILS = 15
}

# Global/UI-level command vocabulary bound to buttons and hotkeys (§3.1)
enum ControlType {
    CENTER_ON_SELECTION = 0, SELECT_ALL_TYPE = 1, NEXT_CITY = 2, PREV_CITY = 3,
    NEXT_UNIT = 4, PREV_UNIT = 5, NEXT_IDLE_UNIT = 6, NEXT_IDLE_WORKER = 7,
    END_TURN = 8, FORCE_END_TURN = 9,
    TOGGLE_GRID = 10, TOGGLE_YIELDS = 11, TOGGLE_RESOURCES = 12,
    OPEN_TECH = 13, OPEN_POLICY = 14, OPEN_DIPLOMACY = 15, OPEN_FINANCE = 16,
    OPEN_MILITARY = 17, OPEN_ESPIONAGE = 18, OPEN_ENCYCLOPEDIA = 19,
    OPEN_CITY_SCREEN = 20, OPEN_SAVE_LOAD = 21,
    QUICK_SAVE = 22, QUICK_LOAD = 23,
    OPEN_MENU = 24,
    # Score display toggle and additional advisor/info screens (§3.1)
    TOGGLE_SCORE = 25, OPEN_RELIGION = 26, OPEN_CORPORATION = 27,
    OPEN_TURN_LOG = 28, OPEN_DOMESTIC_ADVISOR = 29,
    OPEN_VICTORY_PROGRESS = 30, OPEN_OPTIONS = 31,
    TOGGLE_MINIMAP = 32,
    TOGGLE_FOG = 33
}

# Direct, immediate unit orders (§3.2)
enum UnitCmd {
    WAKE = 0, SLEEP = 1, FORTIFY = 2, CANCEL_ORDERS = 3,
    DISBAND = 4, UPGRADE = 5, PROMOTE = 6, AUTOMATE = 7, STOP_AUTOMATE = 8,
    GIFT = 9
}

# Queued unit missions executed over subsequent turns (§3.3)
enum UnitMission {
    MOVE_TO = 0, ROUTE_TO = 1, SKIP_TURN = 2, PILLAGE = 3,
    FOUND_SETTLEMENT = 4, BUILD_IMPROVEMENT = 5, BUILD_ROAD = 6,
    RANGED_ATTACK = 7, BOMBARD = 8, AIRLIFT = 9, PARADROP = 10,
    SENTRY = 11, HEAL = 12, MOVE_TO_UNIT = 13, RECON = 14,
    AIR_PATROL = 15, SEA_PATROL = 16, CLEAN_FALLOUT = 17,
    SLEEP_UNTIL_HEALED = 18, FORTIFY_UNTIL_HEALED = 19,
    EXPLORE = 20, CLEAR_FEATURE = 21
}

# Phase flags for hooks
enum Phase {
    WORLD_RESOLVE_TRADES = 0,
    WORLD_ADVANCE_ALLIANCES = 1,
    WORLD_TILE_UPKEEP = 2,
    WORLD_SPAWN_WILD = 3,
    WORLD_ENVIRONMENTAL = 4,
    WORLD_ASSIGN_SITES = 5,
    WORLD_ASSEMBLY = 6,
    WORLD_INCREMENT_TURN = 7,
    WORLD_ACTIVATE_PLAYER = 8,
    WORLD_CHECK_WIN = 9,
    PLAYER_BOOKKEEPING = 10,
    PLAYER_ASSIGN_WORKERS = 11,
    PLAYER_TREASURY = 12,
    PLAYER_RESEARCH = 13,
    PLAYER_INTELLIGENCE = 14,
    PLAYER_SETTLEMENTS = 15,
    PLAYER_TICK_STATES = 16,
    PLAYER_VALIDATE_POLICIES = 17,
    PLAYER_EVENTS = 18,
    SETTLEMENT_GROWTH = 19,
    SETTLEMENT_PRODUCTION = 20,
    SETTLEMENT_CULTURE = 21,
    SETTLEMENT_BELIEFS = 22,
    SETTLEMENT_DECAY = 23,
    SETTLEMENT_SPECIALISTS = 24,
    SETTLEMENT_MAINTENANCE = 25,
    # Cultural revolt / city flipping (§4.9), evaluated after the owner's
    # settlements run their per-turn step.
    PLAYER_CULTURE_REVOLT = 26,
    # Multi-turn quest tracking (§4): arm eligible quests and re-evaluate active ones,
    # run right after the random-event phase in the player step.
    PLAYER_QUESTS = 27
}
