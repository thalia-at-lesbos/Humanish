extends HBoxContainer

var _facade
var _label: Label

func init(facade) -> void:
	_facade = facade
	_label = Label.new()
	add_child(_label)
	rebuild()

func rebuild() -> void:
	if _facade == null or _label == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	var score_str: String = str(p.score) if p != null else "0"
	var who: String = p.name if p != null else "—"
	# turn_number is 0-based internally; show it 1-based for players.
	_label.text = "Turn: " + str(gs.turn_number + 1) + "/" + str(gs.max_turns) + \
		"   " + who + "   Score: " + score_str
