# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

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
