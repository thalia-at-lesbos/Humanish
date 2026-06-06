# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Unit tests for the pure wire protocol (src/net/net_protocol.gd). No sockets,
# scenes, or game state — just frame construction and parsing.

func test_make_wraps_version_type_payload() -> void:
	var frame: Dictionary = NetProtocol.make(NetProtocol.HELLO, {"name": "Ada"})
	assert_eq(int(frame["v"]), NetProtocol.VERSION, "version stamped")
	assert_eq(str(frame["t"]), NetProtocol.HELLO, "type carried")
	assert_eq(str(frame["d"]["name"]), "Ada", "payload carried")

func test_encode_decode_round_trip() -> void:
	var payload: Dictionary = {"player_id": 3, "snapshot": "{\"x\":1}", "active": true}
	var wire: String = NetProtocol.encode(NetProtocol.STATE, payload)
	var frame: Dictionary = NetProtocol.decode(wire)
	assert_false(frame.empty(), "decoded a non-empty frame")
	assert_eq(NetProtocol.type_of(frame), NetProtocol.STATE, "type survives round trip")
	var d: Dictionary = NetProtocol.data_of(frame)
	assert_eq(int(d["player_id"]), 3, "int field survives")
	assert_eq(str(d["snapshot"]), "{\"x\":1}", "embedded json string survives")
	assert_true(bool(d["active"]), "bool field survives")

func test_decode_rejects_malformed_json() -> void:
	assert_true(NetProtocol.decode("not json {").empty(), "garbage → empty frame")
	assert_true(NetProtocol.decode("[1,2,3]").empty(), "non-object root → empty frame")

func test_decode_rejects_version_mismatch() -> void:
	var wire: String = JSON.print({"v": NetProtocol.VERSION + 99, "t": NetProtocol.HELLO, "d": {}})
	assert_true(NetProtocol.decode(wire).empty(), "wrong protocol version → empty frame")

func test_decode_requires_nonempty_type() -> void:
	var wire: String = JSON.print({"v": NetProtocol.VERSION, "t": "", "d": {}})
	assert_true(NetProtocol.decode(wire).empty(), "empty type → empty frame")

func test_data_of_defaults_to_empty_dict() -> void:
	var wire: String = JSON.print({"v": NetProtocol.VERSION, "t": NetProtocol.BYE})
	var frame: Dictionary = NetProtocol.decode(wire)
	assert_false(frame.empty(), "missing payload still decodes")
	assert_eq(NetProtocol.data_of(frame).size(), 0, "missing payload → empty dict")
