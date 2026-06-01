extends Control

var _db
var _menu_box: VBoxContainer
var _setup_screen

func _ready() -> void:
	_db = load("res://src/core/data_db.gd").new()
	if not _db.load_all():
		push_error("DataDB load failed: " + str(_db.get_errors()))
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.08, 0.08, 0.10)
	add_child(bg)

	_menu_box = VBoxContainer.new()
	_menu_box.anchor_left = 0.35
	_menu_box.anchor_top = 0.3
	_menu_box.anchor_right = 0.65
	_menu_box.anchor_bottom = 0.75
	_menu_box.add_constant_override("separation", 16)
	add_child(_menu_box)

	var title := Label.new()
	title.text = "HUMANISH"
	title.align = Label.ALIGN_CENTER
	_menu_box.add_child(title)

	var spacer := Control.new()
	spacer.rect_min_size = Vector2(0, 24)
	_menu_box.add_child(spacer)

	var new_game_btn := Button.new()
	new_game_btn.text = "New Game"
	new_game_btn.connect("pressed", self, "_on_new_game_pressed")
	_menu_box.add_child(new_game_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.connect("pressed", self, "_on_exit_pressed")
	_menu_box.add_child(exit_btn)

func _on_new_game_pressed() -> void:
	_menu_box.visible = false
	_setup_screen = load("res://scenes/setup/setup_screen.gd").new()
	_setup_screen.anchor_right = 1.0
	_setup_screen.anchor_bottom = 1.0
	add_child(_setup_screen)
	_setup_screen.init(_db, funcref(self, "_on_setup_complete"))

func _on_setup_complete(facade, db) -> void:
	var main_scene = load("res://scenes/main.tscn").instance()
	main_scene.init_with_facade(facade, db)
	get_tree().get_root().add_child(main_scene)
	get_tree().current_scene = main_scene
	queue_free()

func _on_exit_pressed() -> void:
	get_tree().quit()
