extends HBoxContainer

# Four HSliders for finance/research/culture/intel. Constrained to sum to 100.
# On any change emits Commands.set_sliders to the facade.

var _facade
var _sliders: Array = []   # [finance, research, culture, intel]
var _labels: Array = []
var _updating: bool = false

const SLIDER_NAMES: Array = ["Finance", "Research", "Culture", "Intel"]

func init(facade) -> void:
	_facade = facade
	_build_ui()
	rebuild()

func _build_ui() -> void:
	for i in range(4):
		var vbox: VBoxContainer = VBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = SLIDER_NAMES[i] + ": 0%"
		lbl.align = Label.ALIGN_CENTER
		_labels.append(lbl)
		vbox.add_child(lbl)

		var slider: HSlider = HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 10
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.connect("value_changed", self, "_on_slider_changed", [i])
		_sliders.append(slider)
		vbox.add_child(slider)

		add_child(vbox)

func rebuild() -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		return
	_updating = true
	_sliders[0].value = p.slider_finance
	_sliders[1].value = p.slider_research
	_sliders[2].value = p.slider_culture
	_sliders[3].value = p.slider_intel
	_update_labels()
	_updating = false

func _on_slider_changed(value: float, changed_idx: int) -> void:
	if _updating or _facade == null:
		return
	_updating = true

	var vals: Array = [
		int(_sliders[0].value),
		int(_sliders[1].value),
		int(_sliders[2].value),
		int(_sliders[3].value)
	]
	vals[changed_idx] = int(value)

	# Distribute remainder among the other sliders proportionally
	var total: int = 0
	for v in vals:
		total += v
	var diff: int = total - 100
	if diff != 0:
		# Adjust the first other slider that can absorb it
		for i in range(4):
			if i == changed_idx:
				continue
			var new_val: int = vals[i] - diff
			if new_val >= 0 and new_val <= 100:
				vals[i] = new_val
				break

	# Ensure sum == 100 (clamp residual onto last flexible slot)
	var sum: int = 0
	for v in vals:
		sum += v
	if sum != 100:
		for i in range(4):
			if i == changed_idx:
				continue
			vals[i] = max(0, vals[i] + (100 - sum))
			break

	for i in range(4):
		_sliders[i].value = vals[i]
	_update_labels()
	_updating = false

	var gs = _facade.get_state()
	_facade.apply_command(
		Commands.set_sliders(gs.current_player_id, vals[0], vals[1], vals[2], vals[3]))

func _update_labels() -> void:
	var names: Array = SLIDER_NAMES
	for i in range(4):
		_labels[i].text = names[i] + ": " + str(int(_sliders[i].value)) + "%"
