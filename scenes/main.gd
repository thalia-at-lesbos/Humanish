extends Node

# Root scene. Bootstraps DataDB + SimFacade, wires all child systems,
# and routes SimFacade signals to the appropriate scene nodes.

var _facade
var _db

func _ready() -> void:
	_db = load("res://src/core/data_db.gd").new()
	if not _db.load_all():
		push_error("DataDB load failed: " + str(_db.get_errors()))
		return

	_facade = load("res://src/api/sim_facade.gd").new()
	_facade.connect("game_won", self, "_on_game_won")
	_facade.connect("player_turn_started", self, "_on_player_turn_started")
	_facade.connect("screen_requested", self, "_on_screen_requested")

	# Default 2-player tiny game for the prototype
	_facade.setup(_db, randi(), "tiny", "normal", "warlord",
		[
			{"name": "Player 1", "leader_id": "", "traits": [], "starting_gold": 100},
			{"name": "Player 2", "leader_id": "", "traits": [], "starting_gold": 100}
		],
		["last_standing", "dominance", "time"])

	var world_view = get_node_or_null("WorldView")
	if world_view != null:
		world_view.init(_facade)
		var fog = world_view.get_node_or_null("FogLayer")
		if fog != null:
			fog.init(_facade)

	# Wire HUD child panels
	var hud = get_node_or_null("HUD")
	if hud != null:
		if hud.has_method("init"):
			hud.init(_facade)
		_init_node("HUD/VBox/TurnScoreBar", [_facade])
		_init_node("HUD/VBox/ResearchBar", [_facade])
		_init_node("HUD/VBox/SliderPanel", [_facade])
		_init_node("HUD/VBox/SelectionPanel", [_facade, world_view])
		_init_node("HUD/VBox/MessageLog", [_facade])
		_init_node("HUD/VBox/EndTurnButton", [_facade])

	# Wire input router
	var input_router = get_node_or_null("InputRouter")
	if input_router != null:
		input_router.init(_facade, world_view)

	# Wire hotseat manager
	var hsm = get_node_or_null("HotseatManager")
	var pass_screen = get_node_or_null("PassDeviceScreen")
	if hsm != null:
		hsm.init(_facade, world_view)
		if pass_screen != null:
			if pass_screen.has_method("init"):
				pass_screen.init(_facade)
			hsm.set_pass_screen(pass_screen)
			var ok_btn = pass_screen.get_node_or_null("VBox/OKButton")
			if ok_btn != null:
				ok_btn.connect("pressed", pass_screen, "_on_ok_pressed")

func _init_node(path: String, args: Array) -> void:
	var node = get_node_or_null(path)
	if node != null and node.has_method("init"):
		node.callv("init", args)

func get_facade():
	return _facade

func _on_game_won(alliance_id: int) -> void:
	print("Game won by alliance: ", alliance_id)

func _on_player_turn_started(player_id: int) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(player_id)
	print("Turn started: ", p.name if p != null else str(player_id))

func _on_screen_requested(screen_id: int) -> void:
	match screen_id:
		IDs.ControlType.OPEN_CITY_SCREEN:
			var city_screen = get_node_or_null("CityScreen")
			if city_screen != null:
				var sel = _facade.get_selection()
				city_screen.show_city(sel.head_city())
		IDs.ControlType.OPEN_TECH:
			var tech = get_node_or_null("TechChooser")
			if tech != null:
				tech.show_screen()
		IDs.ControlType.OPEN_POLICY:
			var policy = get_node_or_null("PolicyScreen")
			if policy != null:
				policy.show_screen()
		IDs.ControlType.OPEN_DIPLOMACY:
			var diplo = get_node_or_null("DiplomacyScreen")
			if diplo != null:
				diplo.show_screen()
		IDs.ControlType.OPEN_SAVE_LOAD, IDs.ControlType.QUICK_SAVE, \
		IDs.ControlType.QUICK_LOAD:
			var sl = get_node_or_null("SaveLoadScreen")
			if sl != null:
				sl.show_screen()
		-1:  # close current screen
			pass
