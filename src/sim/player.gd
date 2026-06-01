class_name Player
extends Reference

var id: int = 0
var name: String = ""
var leader_id: String = ""
var traits: Array = []        # Array of trait IDs

# Economy
var treasury: int = 0
var slider_finance: int = 40  # percentages, must sum to 100
var slider_research: int = 40
var slider_culture: int = 10
var slider_intel: int = 10

# Policy selections per category
var policies: Dictionary = {}  # category -> policy_id

# Research
var current_research_id: String = ""
var research_store: int = 0     # accumulated research points

# Technologies known
var technologies: Array = []    # Array of tech IDs

# Espionage accumulation per target alliance_id
var intel_points: Dictionary = {}   # alliance_id -> int

# Alliance membership
var alliance_id: int = -1

# Free early wins remaining (from difficulty)
var free_early_wins: int = 0

# Transition penalty turns remaining (from policy switch)
var transition_turns: int = 0

# Score cache (updated each turn)
var score: int = 0

# Is the player eliminated?
var is_eliminated: bool = false

# Active celebration turns
var celebration_turns: int = 0

func has_tech(tech_id: String) -> bool:
	return tech_id in technologies

func get_slider_sum() -> int:
	return slider_finance + slider_research + slider_culture + slider_intel

# Split a total commerce value according to sliders. Returns [finance, research, culture, intel].
func split_commerce(total_commerce: int) -> Array:
	var fin: int = Fixed.scale(total_commerce, slider_finance)
	var res: int = Fixed.scale(total_commerce, slider_research)
	var cul: int = Fixed.scale(total_commerce, slider_culture)
	var itl: int = total_commerce - fin - res - cul  # remainder goes to intel
	return [fin, res, cul, itl]

func serialize() -> Dictionary:
	return {
		"id": id, "name": name, "leader_id": leader_id, "traits": traits.duplicate(),
		"treasury": treasury,
		"slider_finance": slider_finance, "slider_research": slider_research,
		"slider_culture": slider_culture, "slider_intel": slider_intel,
		"policies": policies.duplicate(),
		"current_research_id": current_research_id,
		"research_store": research_store,
		"technologies": technologies.duplicate(),
		"intel_points": intel_points.duplicate(),
		"alliance_id": alliance_id,
		"free_early_wins": free_early_wins,
		"transition_turns": transition_turns,
		"score": score,
		"is_eliminated": is_eliminated,
		"celebration_turns": celebration_turns
	}

static func deserialize(d: Dictionary):
	var p = load("res://src/sim/player.gd").new()
	p.id = int(d["id"])
	p.name = str(d.get("name", ""))
	p.leader_id = str(d.get("leader_id", ""))
	p.traits = d.get("traits", []).duplicate()
	p.treasury = int(d.get("treasury", 0))
	p.slider_finance = int(d.get("slider_finance", 40))
	p.slider_research = int(d.get("slider_research", 40))
	p.slider_culture = int(d.get("slider_culture", 10))
	p.slider_intel = int(d.get("slider_intel", 10))
	p.policies = d.get("policies", {}).duplicate()
	p.current_research_id = str(d.get("current_research_id", ""))
	p.research_store = int(d.get("research_store", 0))
	p.technologies = d.get("technologies", []).duplicate()
	p.intel_points = d.get("intel_points", {}).duplicate()
	p.alliance_id = int(d.get("alliance_id", -1))
	p.free_early_wins = int(d.get("free_early_wins", 0))
	p.transition_turns = int(d.get("transition_turns", 0))
	p.score = int(d.get("score", 0))
	p.is_eliminated = bool(d.get("is_eliminated", false))
	p.celebration_turns = int(d.get("celebration_turns", 0))
	return p
