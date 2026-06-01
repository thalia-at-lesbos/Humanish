extends Node

# Manages pass-and-play hotseat flow. Subscribes to facade.player_turn_started
# to show the PassDeviceScreen and rebuild fog for the incoming player.

var _facade
var _world_view
var _pass_screen    # PassDeviceScreen node

func init(facade, world_view) -> void:
	_facade = facade
	_world_view = world_view
	_facade.connect("player_turn_started", self, "_on_player_turn_started")
	_facade.connect("game_won", self, "_on_game_won")

func set_pass_screen(screen) -> void:
	_pass_screen = screen

func _on_player_turn_started(player_id: int) -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(player_id)
	var player_name: String = p.name if p != null else "Player"

	# Rebuild fog for the new active player
	if _world_view != null:
		var fog = _world_view.get_node_or_null("FogLayer")
		if fog != null:
			fog.rebuild(player_id)

	# Show pass-device overlay
	if _pass_screen != null and _pass_screen.has_method("show_for_player"):
		_pass_screen.show_for_player(player_name, player_id)

func _on_game_won(alliance_id: int) -> void:
	if _pass_screen != null and _pass_screen.has_method("show_game_over"):
		_pass_screen.show_game_over(alliance_id, _facade.get_state())
