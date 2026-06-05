# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends HBoxContainer

# Four HSliders for finance/research/culture/intel. Constrained to sum to 100.
# On any change emits Commands.set_sliders to the facade.

var _facade
var _sliders: Array = []   # [finance, research, culture, intel]
var _labels: Array = []
var _updating: bool = false

const SLIDER_NAMES: Array = ["Finance", "Research", "Culture", "Intel"]
const SliderMath = preload("res://src/api/slider_math.gd")

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

	var cur: Array = [
		int(_sliders[0].value),
		int(_sliders[1].value),
		int(_sliders[2].value),
		int(_sliders[3].value)
	]
	# Predictably take the difference from the other sliders so the four always
	# sum to exactly 100 (see slider_math.gd).
	var vals: Array = SliderMath.rebalance(cur, changed_idx, int(value))

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
