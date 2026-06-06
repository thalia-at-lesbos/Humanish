# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://scenes/screens/info_screen.gd"

# About screen (§11 session/meta): a read-only panel showing the game title,
# version, copyright and license. Reachable from both the start menu and the
# in-game pause menu. Needs no game state, so it accepts a null facade.

func init(facade = null) -> void:
	_title = "About"
	.init(facade)

func _populate(vbox) -> void:
	_add_line(vbox, ProjectSettings.get_setting("application/config/name"))
	_add_line(vbox, "Version " + str(ProjectSettings.get_setting("application/config/version")))
	_add_line(vbox, "")
	_add_line(vbox, "A turn-based 4X strategy game.")
	_add_line(vbox, "Copyright (C) 2026 thalia-at-lesbos")
	_add_line(vbox, "")
	_add_line(vbox, "Licensed under the GNU General Public License,")
	_add_line(vbox, "version 3 or (at your option) any later version.")
	_add_line(vbox, "This program comes with ABSOLUTELY NO WARRANTY.")
	_add_line(vbox, "See the LICENSE file for the full text.")
