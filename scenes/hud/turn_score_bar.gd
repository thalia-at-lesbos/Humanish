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
	_label.text = "Turn: " + str(gs.turn_number) + "/" + str(gs.max_turns) + \
		"   Score: " + score_str
