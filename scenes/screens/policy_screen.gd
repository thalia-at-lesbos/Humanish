extends Control

# Policy screen: per-category policy selection with transition penalty info.

var _facade

func init(facade) -> void:
	_facade = facade
	visible = false

func show_screen() -> void:
	visible = true
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	yield(get_tree(), "idle_frame")

	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		return

	# Opaque backdrop so the map is not visible behind the screen.
	var bg: ColorRect = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.10, 0.10, 0.13, 1.0)
	add_child(bg)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	add_child(scroll)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Policies"
	vbox.add_child(title)

	if p.transition_turns > 0:
		var trans_lbl: Label = Label.new()
		trans_lbl.text = "Transition penalty: " + str(p.transition_turns) + " turns remaining"
		vbox.add_child(trans_lbl)

	# Collect categories
	var categories: Dictionary = {}
	for pol_id in _facade._db.policies.get("policies", {}):
		var pol: Dictionary = _facade._db.policies["policies"][pol_id]
		var cat: String = str(pol.get("category", "other"))
		if not categories.has(cat):
			categories[cat] = []
		categories[cat].append(pol_id)

	for cat in categories:
		var cat_lbl: Label = Label.new()
		cat_lbl.text = cat.capitalize()
		vbox.add_child(cat_lbl)
		for pol_id in categories[cat]:
			var pol: Dictionary = _facade._db.policies["policies"][pol_id]
			var is_current: bool = p.policies.get(cat, "") == pol_id
			var tech_req = pol.get("tech_required", null)
			var unlocked: bool = tech_req == null or tech_req == "" or p.has_tech(str(tech_req))

			var btn: Button = Button.new()
			btn.text = ("► " if is_current else "  ") + pol_id
			btn.disabled = not unlocked
			btn.connect("pressed", self, "_on_policy_selected", [cat, pol_id])
			vbox.add_child(btn)

	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	vbox.add_child(close_btn)

func _on_policy_selected(cat: String, pol_id: String) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.set_policy(gs.current_player_id, cat, pol_id))
	rebuild()

func _on_close() -> void:
	visible = false
