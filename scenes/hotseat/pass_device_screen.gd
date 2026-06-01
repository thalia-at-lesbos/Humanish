extends Control

# Full-screen overlay shown when a player's turn ends in hotseat mode.
# Prevents the outgoing player from seeing the incoming player's state.

var _facade
var _on_ok_callback     # Callable or FuncRef

onready var _label: Label = $VBox/Label
onready var _button: Button = $VBox/OKButton

func init(facade) -> void:
	_facade = facade
	visible = false

func show_for_player(player_name: String, player_id: int) -> void:
	if _label != null:
		_label.text = "Pass the device to\n" + player_name
	visible = true
	# Disable main input until OK is pressed
	get_tree().paused = false  # scene is not paused but input routing is blocked by visibility

func show_game_over(alliance_id: int, gs) -> void:
	if _label == null:
		return
	var winner_name: String = "Unknown"
	for p in gs.players:
		if p.alliance_id == alliance_id:
			winner_name = p.name
			break
	_label.text = "Game Over!\n" + winner_name + " wins!"
	if _button != null:
		_button.text = "Quit"
		if _button.is_connected("pressed", self, "_on_ok_pressed"):
			_button.disconnect("pressed", self, "_on_ok_pressed")
		_button.connect("pressed", get_tree(), "quit")
	visible = true

func _on_ok_pressed() -> void:
	visible = false
