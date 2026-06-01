class_name Tile
extends Reference

var x: int = 0
var y: int = 0

# Data table IDs
var terrain_id: String = ""
var feature_id: String = ""
var resource_id: String = ""
var improvement_id: String = ""
var transport_id: String = ""

# Cultural influence: player_id (int) -> accumulated influence (int)
var influence: Dictionary = {}

# Derived from influence by influence.gd
var owner_player_id: int = -1  # -1 = unowned

# Environmental state
var pollution: int = 0

# Exploration: an undiscovered site that yields a reward when first entered (§9)
var has_discovery: bool = false

# Improvement construction progress (turns remaining)
var improvement_turns_left: int = 0

# Entrenchment per-unit is on the unit; this tracks tile-level fortification count
# (not part of base spec but used for improvement tracking)

func _init(px: int = 0, py: int = 0) -> void:
	x = px
	y = py

func serialize() -> Dictionary:
	return {
		"x": x, "y": y,
		"terrain_id": terrain_id,
		"feature_id": feature_id,
		"resource_id": resource_id,
		"improvement_id": improvement_id,
		"transport_id": transport_id,
		"influence": influence.duplicate(),
		"owner_player_id": owner_player_id,
		"pollution": pollution,
		"improvement_turns_left": improvement_turns_left,
		"has_discovery": has_discovery
	}

static func deserialize(d: Dictionary):
	var t = load("res://src/world/tile.gd").new(int(d["x"]), int(d["y"]))
	t.terrain_id = str(d.get("terrain_id", ""))
	t.feature_id = str(d.get("feature_id", ""))
	t.resource_id = str(d.get("resource_id", ""))
	t.improvement_id = str(d.get("improvement_id", ""))
	t.transport_id = str(d.get("transport_id", ""))
	var inf = d.get("influence", {})
	for k in inf:
		t.influence[int(k)] = int(inf[k])
	t.owner_player_id = int(d.get("owner_player_id", -1))
	t.pollution = int(d.get("pollution", 0))
	t.improvement_turns_left = int(d.get("improvement_turns_left", 0))
	t.has_discovery = bool(d.get("has_discovery", false))
	return t
