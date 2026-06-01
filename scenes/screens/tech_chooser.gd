extends Control

# Tech chooser screen. Lists researchable technologies with prereq info.
# Click an enabled tech → Commands.set_research, screen closes.

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

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	add_child(scroll)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Choose Research"
	vbox.add_child(title)

	# Group by age
	var ages: Dictionary = {}
	for tech_id in _facade._db.technologies:
		var tech: Dictionary = _facade._db.get_technology(tech_id)
		if p.has_tech(tech_id):
			continue  # already known
		var age: String = str(tech.get("age", "other"))
		if not ages.has(age):
			ages[age] = []
		ages[age].append(tech_id)

	for age in ages:
		var age_lbl: Label = Label.new()
		age_lbl.text = age.capitalize() + " Age"
		vbox.add_child(age_lbl)
		for tech_id in ages[age]:
			var can_research: bool = load("res://src/sim/research.gd").can_research(
				tech_id, p, _facade._db)
			var btn: Button = Button.new()
			var help: String = _facade.widget_help(
				{"type": IDs.WidgetType.TECH_NODE, "tech_id": tech_id})
			btn.text = tech_id + (" ✓" if can_research else " (locked)")
			btn.disabled = not can_research
			btn.hint_tooltip = help
			btn.connect("pressed", self, "_on_tech_selected", [tech_id])
			vbox.add_child(btn)

	var close_btn: Button = Button.new()
	close_btn.text = "Cancel"
	close_btn.connect("pressed", self, "_on_close")
	vbox.add_child(close_btn)

func _on_tech_selected(tech_id: String) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.set_research(gs.current_player_id, tech_id))
	visible = false

func _on_close() -> void:
	visible = false
