extends CanvasLayer

# HUD dispatcher: watches dirty flags each frame and drives per-panel rebuilds.
# Each panel is a child node that exposes a rebuild() method.

var _facade

func init(facade) -> void:
	_facade = facade

func _process(_delta: float) -> void:
	if _facade == null:
		return
	var d = _facade.get_dirty()

	if d.is_dirty(IDs.DirtyRegion.HUD_GROUPS):
		_rebuild_node("SelectionPanel")
		_rebuild_node("SliderPanel")
		_rebuild_node("ResearchBar")
		_rebuild_node("EndTurnButton")
		d.clear(IDs.DirtyRegion.HUD_GROUPS)

	if d.is_dirty(IDs.DirtyRegion.DATA_PANES):
		_rebuild_node("MessageLog")
		_rebuild_node("TurnScoreBar")
		d.clear(IDs.DirtyRegion.DATA_PANES)

func _rebuild_node(name: String) -> void:
	var node = get_node_or_null(name)
	if node != null and node.has_method("rebuild"):
		node.rebuild()
