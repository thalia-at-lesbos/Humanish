extends Reference

# Loads key→ControlType bindings from data/hotkeys.json.
# Keys in the JSON are scancode integers (as strings).
# Format: {"scancode": {"shift": bool, "ctrl": bool, "action": ControlType int}}

var _bindings: Dictionary = {}   # key: "scancode_shift_ctrl" → ControlType int

func load_bindings() -> void:
	var file: File = File.new()
	if file.open("res://data/hotkeys.json", File.READ) != OK:
		push_warning("hotkeys.json not found; using empty hotkey map")
		return
	var text: String = file.get_as_text()
	file.close()
	var result = JSON.parse(text)
	if result.error != OK:
		push_warning("hotkeys.json parse error")
		return
	var data: Dictionary = result.result
	for scancode_str in data:
		var entry: Dictionary = data[scancode_str]
		var shift: bool = bool(entry.get("shift", false))
		var ctrl: bool = bool(entry.get("ctrl", false))
		var action: int = int(entry.get("action", -1))
		if action >= 0:
			var key: String = scancode_str + "_" + str(shift) + "_" + str(ctrl)
			_bindings[key] = action

func lookup(scancode: int, shift: bool, ctrl: bool) -> int:
	var key: String = str(scancode) + "_" + str(shift) + "_" + str(ctrl)
	return _bindings.get(key, -1)
