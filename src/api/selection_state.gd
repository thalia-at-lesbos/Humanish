class_name SelectionState
extends Reference

# Tracks the currently active subject (unit selection or city selection).
# This is a UI concern — not part of GameState — because it has no effect
# on simulation outcomes.

var selected_unit_ids: Array = []   # int IDs, ordered; head = [0]
var selected_city_id: int = -1
var city_screen_open: bool = false
var active_city_tab: int = 0        # 0=units 1=buildings 2=wonders

func select_unit(id: int, do_clear: bool = true, toggle: bool = false) -> void:
    if do_clear:
        selected_unit_ids.clear()
        selected_city_id = -1
    if toggle and id in selected_unit_ids:
        selected_unit_ids.erase(id)
    elif not id in selected_unit_ids:
        selected_unit_ids.append(id)

func select_city(id: int, raise_screen: bool = false) -> void:
    selected_unit_ids.clear()
    selected_city_id = id
    if raise_screen:
        city_screen_open = true

func clear() -> void:
    selected_unit_ids.clear()
    selected_city_id = -1
    city_screen_open = false

func head_unit() -> int:
    if selected_unit_ids.empty():
        return -1
    return selected_unit_ids[0]

func head_city() -> int:
    return selected_city_id
