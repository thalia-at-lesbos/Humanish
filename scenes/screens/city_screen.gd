extends Control

# Full-screen city view: outputs, the F/R/C/I commerce split, wellbeing and
# contentment, the worked tiles (resources used), current production with
# progress, a quick build chooser, and the building list.
# Opened via OPEN_CITY_SCREEN (selection panel / flyout "Open City").

var _facade
var _city_id: int = -1

func init(facade) -> void:
	_facade = facade
	visible = false

func show_city(city_id: int) -> void:
	if city_id < 0:
		return
	_city_id = city_id
	visible = true
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	yield(get_tree(), "idle_frame")
	if _facade == null or _city_id < 0 or not visible:
		return
	_build()

func _build() -> void:
	var gs = _facade.get_state()
	var db = _facade._db
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	var owner = gs.get_player(s.owner_player_id)
	var techs = owner.technologies if owner != null else []

	# Opaque backdrop so the map is not visible behind the screen.
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.10, 0.10, 0.13, 1.0)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.margin_left = 14
	scroll.margin_top = 14
	scroll.margin_right = -14
	scroll.margin_bottom = -14
	add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	_title(v, s.name + "   (pop " + str(s.population) + ")   @ " + str(s.x) + "," + str(s.y))
	if s.in_disorder:
		_line(v, "!! IN DISORDER — production is halted")

	# ── Output ────────────────────────────────────────────────────────────────
	_header(v, "Output")
	_line(v, "Food " + _sgn(s.output_food) + "    Production " + _sgn(s.output_production) \
		+ "    Commerce " + _sgn(s.output_commerce))
	if owner != null:
		var split = owner.split_commerce(s.output_commerce)
		_line(v, "Commerce split →  Finance " + str(split[0]) + "   Research " + str(split[1]) \
			+ "   Culture " + str(split[2]) + "   Intel " + str(split[3]))
	_line(v, "Food store: " + str(s.food_store) + "    Culture: " + str(s.culture_total) \
		+ " (border ring " + str(s.culture_ring) + ")")

	# ── Wellbeing & contentment ────────────────────────────────────────────────
	_header(v, "Wellbeing & Contentment")
	_line(v, "Wellbeing  +" + str(s.wellbeing_positive) + " / -" + str(s.wellbeing_negative) \
		+ "   (deficit " + str(s.wellbeing_deficit) + ")")
	_line(v, "Contentment  +" + str(s.positive_sentiment) + " / -" + str(s.negative_sentiment) \
		+ "   discontented " + str(s.discontented) + "/" + str(s.population))

	# ── Worked tiles / resources used ──────────────────────────────────────────
	_header(v, "Worked tiles (resources used)")
	if s.worked_tiles.empty():
		_line(v, "  (none yet — tiles are auto-assigned at the end of the turn)")
	else:
		for wt in s.worked_tiles:
			var tile = gs.map.get_tile(int(wt[0]), int(wt[1]))
			if tile == null:
				continue
			var out = TileOutput.compute(tile, db, techs)
			var desc = "  (" + str(tile.x) + "," + str(tile.y) + ") " + tile.terrain_id
			if tile.resource_id != "":
				desc += " + " + tile.resource_id
			if tile.improvement_id != "":
				desc += " [" + tile.improvement_id + "]"
			desc += "   → F" + str(out[0]) + " P" + str(out[1]) + " C" + str(out[2])
			_line(v, desc)

	# ── Current production ─────────────────────────────────────────────────────
	_header(v, "Production")
	if s.production_queue.empty():
		_line(v, "Currently building: (nothing queued)")
	else:
		var item = s.production_queue[0]
		var pace = db.get_pace(gs.pace_id)
		var cost = TurnEngine._item_cost(item, db, owner, pace)
		_line(v, "Building: " + str(item.get("id", "?")) + " (" + str(item.get("type", "")) \
			+ ")   " + str(s.production_store) + "/" + str(cost))
		for i in range(1, s.production_queue.size()):
			_line(v, "   next: " + str(s.production_queue[i].get("id", "?")))

	# ── Quick build chooser ────────────────────────────────────────────────────
	_header(v, "Add to production")
	var options = [
		["unit", "warrior"], ["unit", "worker"], ["unit", "settler"],
		["unit", "scout"], ["unit", "archer"],
		["structure", "granary"], ["structure", "barracks"],
		["structure", "library"], ["structure", "market"]
	]
	var grid := GridContainer.new()
	grid.columns = 3
	for opt in options:
		var btn := Button.new()
		btn.text = "+ " + opt[1]
		btn.connect("pressed", self, "_on_build", [opt[0], opt[1]])
		grid.add_child(btn)
	v.add_child(grid)

	# ── Buildings ──────────────────────────────────────────────────────────────
	_header(v, "Buildings")
	if s.structures.empty():
		_line(v, "  (none)")
	else:
		for st in s.structures:
			_line(v, "  - " + str(st))

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	v.add_child(close_btn)

func _on_build(itype: String, iid: String) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	var q = s.production_queue.duplicate(true)
	q.append({"type": itype, "id": iid})
	_facade.apply_command(Commands.set_production(s.owner_player_id, _city_id, q))
	rebuild()

func _on_close() -> void:
	visible = false

# ── Small UI helpers ───────────────────────────────────────────────────────────

func _title(parent, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)
	var sep := HSeparator.new()
	parent.add_child(sep)

func _header(parent, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var lbl := Label.new()
	lbl.text = "[ " + text + " ]"
	parent.add_child(lbl)

func _line(parent, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)

func _sgn(v: int) -> String:
	return ("+" + str(v)) if v >= 0 else str(v)
