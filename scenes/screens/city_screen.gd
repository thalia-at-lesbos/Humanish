extends Control

# City screen: production queue, building list, breakdowns.
# Opened when a city is selected with raise_screen=true or OPEN_CITY_SCREEN fires.

var _facade
var _city_id: int = -1

func init(facade) -> void:
	_facade = facade
	visible = false

func show_city(city_id: int) -> void:
	_city_id = city_id
	visible = true
	rebuild()

func rebuild() -> void:
	if _facade == null or _city_id < 0:
		return
	for child in get_children():
		if child.name != "CloseButton":
			child.queue_free()
	yield(get_tree(), "idle_frame")
	_build_content()

func _build_content() -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 10
	vbox.margin_top = 10
	vbox.margin_right = -10
	vbox.margin_bottom = -50
	add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = s.name + " (pop " + str(s.population) + ")"
	vbox.add_child(title)

	# Breakdowns from TextGen
	var prod_help: String = _facade.widget_help(
		{"type": IDs.WidgetType.HELP_PRODUCTION, "data1": _city_id})
	var prod_lbl: Label = Label.new()
	prod_lbl.text = prod_help
	vbox.add_child(prod_lbl)

	var content_help: String = _facade.widget_help(
		{"type": IDs.WidgetType.HELP_CONTENTMENT, "data1": _city_id})
	var content_lbl: Label = Label.new()
	content_lbl.text = content_help
	vbox.add_child(content_lbl)

	# Production queue
	var queue_lbl: Label = Label.new()
	queue_lbl.text = "Production queue:"
	vbox.add_child(queue_lbl)
	if s.production_queue.empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "  (nothing queued)"
		vbox.add_child(empty_lbl)
	else:
		for item in s.production_queue:
			var item_lbl: Label = Label.new()
			item_lbl.text = "  • " + str(item.get("id", "?")) + " (" + str(item.get("type", "")) + ")"
			vbox.add_child(item_lbl)

	# Buildings
	var bld_lbl: Label = Label.new()
	bld_lbl.text = "Buildings:"
	vbox.add_child(bld_lbl)
	if s.structures.empty():
		var none_lbl: Label = Label.new()
		none_lbl.text = "  (none)"
		vbox.add_child(none_lbl)
	else:
		for struct_id in s.structures:
			var sl: Label = Label.new()
			sl.text = "  • " + str(struct_id)
			vbox.add_child(sl)

	# Close button at bottom
	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.anchor_top = 1.0
	close_btn.anchor_bottom = 1.0
	close_btn.margin_top = -40
	close_btn.margin_bottom = -8
	close_btn.margin_left = 8
	close_btn.margin_right = -8
	close_btn.connect("pressed", self, "_on_close")
	add_child(close_btn)

func _on_close() -> void:
	visible = false
