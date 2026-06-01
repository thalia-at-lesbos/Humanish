extends Control

# Setup screen shown before the game starts.
# Collects player count, names, world size, seed, pace, difficulty, then
# calls facade.setup() and switches to the main game scene.

var _facade
var _db
var _on_start_callback  # FuncRef(facade, db) called when setup completes

var _player_rows: Array = []
var _world_size_btn: OptionButton
var _pace_btn: OptionButton
var _difficulty_btn: OptionButton
var _seed_edit: LineEdit
var _player_count_spin: SpinBox

func init(db, on_start) -> void:
	_db = db
	_on_start_callback = on_start
	_build_ui()

func _build_ui() -> void:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 40
	vbox.margin_top = 40
	vbox.margin_right = -40
	vbox.margin_bottom = -40
	add_child(vbox)

	var title: Label = Label.new()
	title.text = "New Game"
	vbox.add_child(title)

	# Player count
	var count_row: HBoxContainer = HBoxContainer.new()
	var count_lbl: Label = Label.new()
	count_lbl.text = "Players:"
	_player_count_spin = SpinBox.new()
	_player_count_spin.min_value = 2
	_player_count_spin.max_value = 4
	_player_count_spin.value = 2
	_player_count_spin.connect("value_changed", self, "_on_player_count_changed")
	count_row.add_child(count_lbl)
	count_row.add_child(_player_count_spin)
	vbox.add_child(count_row)

	# Player name + society rows (up to 4)
	var societies: Dictionary = _db.get_societies()
	var society_ids: Array = societies.keys()
	for i in range(4):
		var row: HBoxContainer = HBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = "Player " + str(i + 1) + ":"
		var edit: LineEdit = LineEdit.new()
		edit.text = "Player " + str(i + 1)
		edit.rect_min_size = Vector2(100, 0)
		var society_btn: OptionButton = OptionButton.new()
		society_btn.add_item("— No Society —")
		for sid in society_ids:
			society_btn.add_item(societies[sid].get("name", sid))
		row.add_child(lbl)
		row.add_child(edit)
		row.add_child(society_btn)
		_player_rows.append({"row": row, "name_edit": edit, "society_btn": society_btn,
				"society_ids": society_ids})
		vbox.add_child(row)
		row.visible = i < 2

	# World size
	var ws_row: HBoxContainer = HBoxContainer.new()
	var ws_lbl: Label = Label.new()
	ws_lbl.text = "World size:"
	_world_size_btn = OptionButton.new()
	for size_id in ["tiny", "small", "standard"]:
		_world_size_btn.add_item(size_id)
	ws_row.add_child(ws_lbl)
	ws_row.add_child(_world_size_btn)
	vbox.add_child(ws_row)

	# Pace
	var pace_row: HBoxContainer = HBoxContainer.new()
	var pace_lbl: Label = Label.new()
	pace_lbl.text = "Pace:"
	_pace_btn = OptionButton.new()
	for pace_id in ["quick", "normal", "epic"]:
		_pace_btn.add_item(pace_id)
	_pace_btn.select(1)
	pace_row.add_child(pace_lbl)
	pace_row.add_child(_pace_btn)
	vbox.add_child(pace_row)

	# Difficulty
	var diff_row: HBoxContainer = HBoxContainer.new()
	var diff_lbl: Label = Label.new()
	diff_lbl.text = "Difficulty:"
	_difficulty_btn = OptionButton.new()
	for diff_id in ["settler", "warlord", "prince", "emperor"]:
		_difficulty_btn.add_item(diff_id)
	_difficulty_btn.select(1)
	diff_row.add_child(diff_lbl)
	diff_row.add_child(_difficulty_btn)
	vbox.add_child(diff_row)

	# Seed
	var seed_row: HBoxContainer = HBoxContainer.new()
	var seed_lbl: Label = Label.new()
	seed_lbl.text = "Seed:"
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi())
	_seed_edit.rect_min_size = Vector2(100, 0)
	seed_row.add_child(seed_lbl)
	seed_row.add_child(_seed_edit)
	vbox.add_child(seed_row)

	# Start button
	var start_btn: Button = Button.new()
	start_btn.text = "Start Game"
	start_btn.connect("pressed", self, "_on_start_pressed")
	vbox.add_child(start_btn)

func _on_player_count_changed(value: float) -> void:
	var count: int = int(value)
	for i in range(_player_rows.size()):
		_player_rows[i]["row"].visible = i < count

func _on_start_pressed() -> void:
	var count: int = int(_player_count_spin.value)
	var player_configs: Array = []
	for i in range(count):
		var row_data: Dictionary = _player_rows[i]
		var society_btn: OptionButton = row_data["society_btn"]
		var society_idx: int = society_btn.selected - 1  # 0 = "No Society"
		var leader_id: String = ""
		var traits: Array = []
		var starting_gold: int = 100
		if society_idx >= 0:
			var sid: String = row_data["society_ids"][society_idx]
			var society: Dictionary = _db.get_society(sid)
			leader_id = society.get("leader_id", "")
			traits = society.get("traits", []).duplicate()
			starting_gold = int(society.get("starting_gold", 100))
		player_configs.append({
			"name": row_data["name_edit"].text,
			"leader_id": leader_id,
			"traits": traits,
			"starting_gold": starting_gold
		})

	var world_size_id: String = _world_size_btn.get_item_text(_world_size_btn.selected)
	var pace_id: String = _pace_btn.get_item_text(_pace_btn.selected)
	var difficulty_id: String = _difficulty_btn.get_item_text(_difficulty_btn.selected)
	var seed_val: int = int(_seed_edit.text) if _seed_edit.text.is_valid_integer() else randi()

	_facade = load("res://src/api/sim_facade.gd").new()
	_facade.setup(_db, seed_val, world_size_id, pace_id, difficulty_id,
		player_configs, ["last_standing", "dominance", "cultural", "time"])

	if _on_start_callback != null:
		_on_start_callback.call_func(_facade, _db)
