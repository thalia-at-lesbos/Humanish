class_name Hooks

# Override-hook seam per §3 and §13.11.
# If a hook handles a phase, the built-in logic is skipped.
# This lets content packs or mods replace any rule.
#
# Hooks are registered as callables: func(game_state, args) -> bool
# Return true = handled (skip built-in), false = let built-in run.

var _hooks: Dictionary = {}  # IDs.Phase -> Array of callables (FuncRefs in GDScript 3)

# Register a hook for a specific phase.
# handler_object: the object that owns the handler method
# method_name: method name on handler_object
func register(phase: int, handler_object: Object, method_name: String) -> void:
	if not _hooks.has(phase):
		_hooks[phase] = []
	_hooks[phase].append(funcref(handler_object, method_name))

func unregister_all(phase: int) -> void:
	_hooks.erase(phase)

# Run hooks for a phase. Returns true if any hook handled it.
func run(phase: int, game_state, args: Dictionary = {}) -> bool:
	if not _hooks.has(phase):
		return false
	for hook in _hooks[phase]:
		if hook.call_func(game_state, args):
			return true
	return false
