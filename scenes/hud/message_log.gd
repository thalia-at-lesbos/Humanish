extends ScrollContainer

# Scrollable notification/event log. Populated from facade.get_notification_queue().
# Auto-scrolls to the bottom when new entries arrive.

var _facade
var _label: RichTextLabel
var _last_count: int = 0

func init(facade) -> void:
	_facade = facade
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.rect_min_size = Vector2(0, 80)
	add_child(_label)
	rebuild()

func rebuild() -> void:
	if _facade == null or _label == null:
		return
	var notifications: Array = _facade.get_notification_queue()
	if notifications.size() == _last_count:
		return
	_last_count = notifications.size()

	var text: String = ""
	# Show last 20 entries
	var start: int = max(0, notifications.size() - 20)
	for i in range(start, notifications.size()):
		var n: Dictionary = notifications[i]
		text += "[" + str(n.get("turn", 0)) + "] " + str(n.get("text", "")) + "\n"
	_label.text = text
	# Scroll to bottom
	scroll_vertical = int(_label.get_content_height())
