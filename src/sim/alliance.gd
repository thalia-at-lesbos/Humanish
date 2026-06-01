class_name Alliance
extends Reference

var id: int = 0
var member_player_ids: Array = []  # Array of player IDs

# War: set of alliance IDs we are at war with
var at_war_with: Array = []

# Contacts: set of alliance IDs we have met
var contacts: Array = []

# Subordination
var is_subordinate_to: int = -1  # alliance_id, -1 = independent
var tributaries: Array = []      # alliance IDs that are our tributaries

# Shared research: additional research points accumulated by alliance members
var shared_research_store: int = 0

# War fatigue per war (alliance_id -> int anger points accumulated)
var war_fatigue: Dictionary = {}

# Active trade offers from this alliance: Array of trade Dictionaries
var pending_trades: Array = []

func is_at_war_with(other_alliance_id: int) -> bool:
	return other_alliance_id in at_war_with

func has_contact_with(other_alliance_id: int) -> bool:
	return other_alliance_id in contacts

func add_member(player_id: int) -> void:
	if not player_id in member_player_ids:
		member_player_ids.append(player_id)

func serialize() -> Dictionary:
	return {
		"id": id,
		"member_player_ids": member_player_ids.duplicate(),
		"at_war_with": at_war_with.duplicate(),
		"contacts": contacts.duplicate(),
		"is_subordinate_to": is_subordinate_to,
		"tributaries": tributaries.duplicate(),
		"shared_research_store": shared_research_store,
		"war_fatigue": war_fatigue.duplicate(),
		"pending_trades": pending_trades.duplicate(true)
	}

static func deserialize(d: Dictionary):
	var a = load("res://src/sim/alliance.gd").new()
	a.id = int(d["id"])
	a.member_player_ids = d.get("member_player_ids", []).duplicate()
	a.at_war_with = d.get("at_war_with", []).duplicate()
	a.contacts = d.get("contacts", []).duplicate()
	a.is_subordinate_to = int(d.get("is_subordinate_to", -1))
	a.tributaries = d.get("tributaries", []).duplicate()
	a.shared_research_store = int(d.get("shared_research_store", 0))
	a.war_fatigue = d.get("war_fatigue", {}).duplicate()
	a.pending_trades = d.get("pending_trades", []).duplicate(true)
	return a
