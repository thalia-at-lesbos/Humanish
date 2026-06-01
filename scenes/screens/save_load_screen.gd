extends Control

# Save/Load screen. Saves to user://saves/ and loads from there.

const SAVE_DIR: String = "user://saves/"

var _facade

func init(facade) -> void:
	_facade = facade
	visible = false
	var dir: Directory = Directory.new()
	if not dir.dir_exists(SAVE_DIR):
		dir.make_dir(SAVE_DIR)

func show_screen() -> void:
	visible = true
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	yield(get_tree(), "idle_frame")

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 10
	vbox.margin_top = 10
	vbox.margin_right = -10
	vbox.margin_bottom = -10
	add_child(vbox)

	var title: Label = Label.new()
	title.text = "Save / Load"
	vbox.add_child(title)

	# Save button
	var save_btn: Button = Button.new()
	save_btn.text = "Quick Save"
	save_btn.connect("pressed", self, "_on_save")
	vbox.add_child(save_btn)

	# File list for loading
	var files_lbl: Label = Label.new()
	files_lbl.text = "Saved games:"
	vbox.add_child(files_lbl)

	var files: Array = _list_saves()
	if files.empty():
		var none_lbl: Label = Label.new()
		none_lbl.text = "  (no saves found)"
		vbox.add_child(none_lbl)
	else:
		for filename in files:
			var row: HBoxContainer = HBoxContainer.new()
			var name_lbl: Label = Label.new()
			name_lbl.text = filename
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var load_btn: Button = Button.new()
			load_btn.text = "Load"
			load_btn.connect("pressed", self, "_on_load", [filename])
			row.add_child(load_btn)
			vbox.add_child(row)

	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	vbox.add_child(close_btn)

func _on_save() -> void:
	if _facade == null:
		return
	var json_str: String = _facade.save()
	var gs = _facade.get_state()
	var filename: String = "turn" + str(gs.turn_number) + ".sav"
	var file: File = File.new()
	if file.open(SAVE_DIR + filename, File.WRITE) == OK:
		file.store_string(json_str)
		file.close()
	rebuild()

func _on_load(filename: String) -> void:
	if _facade == null:
		return
	var file: File = File.new()
	if file.open(SAVE_DIR + filename, File.READ) == OK:
		var json_str: String = file.get_as_text()
		file.close()
		_facade.load_save(json_str)
		_facade.get_dirty().mark_all()
	visible = false

func _on_close() -> void:
	visible = false

func _list_saves() -> Array:
	var files: Array = []
	var dir: Directory = Directory.new()
	if dir.open(SAVE_DIR) == OK:
		dir.list_dir_begin(true, true)
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".sav"):
				files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	return files
