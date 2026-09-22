extends Node
## Project-owned Wwise bridge.
##
## The game only calls semantic keys. Audio designers edit the CSV and replace
## the Wwise event names without touching gameplay scripts. If the Wwise
## extension or a bank is unavailable, the game keeps running silently.

const CONFIG_PATH := "res://assets/Audio/audio_events.tsv"
const CONFIG_DELIMITER := "\t"
const BANK_ROOT := "res://assets/Audio/WwiseProject/TapTapJam26/GeneratedSoundBanks"
const WWISE_SINGLETON := &"Wwise"
const WWISE_EVENT_CLASS := "WwiseEvent"
# AkUtils.AkCallbackType / AkUtils.AkCurveInterpolation values (see
# docs/wwise-audio.md). Hardcoded instead of referencing the AkUtils class by
# name so this script still parses and runs (Wwise disabled, diagnostic only)
# when the Wwise GDExtension is not loaded.
const AK_END_OF_EVENT := 1
const AK_DURATION := 8
const AK_CURVE_LINEAR := 4
const INITIAL_SCENE_KEYS := {
	"res://scenes/login.tscn": "login",
	"res://scenes/main_menu.tscn": "camp",
	"res://scenes/tutorial_grass.tscn": "tutorial_grass",
	"res://scenes/tutorial_cave.tscn": "tutorial_cave",
	"res://scenes/forest.tscn": "forest",
}

var _rules: Dictionary = {}
var _wwise: Object
var _initialized := false
var _current_scene_path := ""
var _current_scene_key := ""
var _wired_buttons: Dictionary = {}
var _wwise_events: Dictionary = {}
var _diagnostics: Array[String] = []
var _warned: Dictionary = {}
var _table_loaded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_initialize.call_deferred()


func _process(_delta: float) -> void:
	if _initialized and _has_method("render_audio"):
		_wwise.call("render_audio")
	_track_scene()


func _unhandled_input(event: InputEvent) -> void:
	## Manual cross-platform smoke test: press F9 (in editor, a desktop build,
	## or a browser tab after a user-gesture click) to post the same
	## "test_play" Event as tools/wwise_play_test.gd and print the
	## AK_DURATION / AK_END_OF_EVENT callback results to stdout / the
	## browser console. No new InputMap action is added on purpose (see
	## docs/wwise-audio.md).
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_F9:
		return
	var posted := play_test_with_callback(_on_hotkey_test_callback)
	print("WWISE_HOTKEY_TEST posted=", posted)


func _on_hotkey_test_callback(info: Variant) -> void:
	if not (info is Dictionary):
		return
	var callback_type := int(info.get("callback_type", -1))
	if callback_type == AK_DURATION:
		print("WWISE_HOTKEY_TEST duration_ms=", float(info.get("fDuration", 0.0)))
	elif callback_type == AK_END_OF_EVENT:
		print("WWISE_HOTKEY_TEST end_of_event")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_scene_event()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _current_scene_key != "":
			_play_rule("scene_%s" % _current_scene_key, self)
	elif what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_CRASH:
		if _initialized and _has_method("shutdown"):
			_wwise.call("shutdown")
		_initialized = false


func play(keys: Variant, source: Node = self) -> bool:
	## Play the event assigned to a semantic table key. `keys` is a single
	## String or an Array of Strings tried in order; the first key that has
	## a row with a non-empty event wins. This lets audio add a specific
	## override row (e.g. "ui_button_StartButton") without any code change,
	## while a generic fallback row (e.g. "ui_button") still covers everyone
	## else.
	return _play_rule(_resolve_key(keys), source)


func stop(keys: Variant, source: Node = self) -> bool:
	## Post the optional Stop Event paired with a semantic table key (same
	## String/Array fallback rules as play()). If the rule has no dedicated
	## stop_event, stop the row's own play Event on this node/game object
	## instead of doing nothing.
	var key := _resolve_key(keys)
	if key.is_empty():
		return false
	var rule: Dictionary = _rules.get(key, {})
	var stop_event := str(rule.get("stop_event", "")).strip_edges()
	if not stop_event.is_empty():
		return _post_event(stop_event, source, key + ":stop")
	var event := str(rule.get("event", "")).strip_edges()
	if event.is_empty():
		return false
	return _stop_event(event, source, key + ":stop")


func get_scene_key() -> String:
	## The semantic key of the currently tracked scene (see _track_scene()),
	## e.g. "forest". Used by gameplay scripts to build per-scene fallback
	## keys such as "walk_<scene_key>" without hardcoding scene names.
	return _current_scene_key


func _resolve_key(keys: Variant) -> String:
	var key_list: Array = keys if keys is Array else [keys]
	for key: String in key_list:
		var rule: Dictionary = _rules.get(key, {})
		if not rule.is_empty() and not str(rule.get("event", "")).strip_edges().is_empty():
			return key
	return ""


func play_test(source: Node = self) -> bool:
	## Explicit smoke-test entry point for the Play_Test Event.
	return _play_rule("test_play", source)


func play_test_with_callback(callback: Callable, source: Node = self) -> bool:
	## Same as play_test(), but posts with an AK_END_OF_EVENT | AK_DURATION
	## callback so a caller (see tools/wwise_play_test.gd) can verify the
	## Auto-Defined SoundBank media actually decoded, instead of only
	## checking that post() returned a playing ID.
	var rule: Dictionary = _rules.get("test_play", {})
	if rule.is_empty():
		return false
	var event_name := str(rule.get("event", "")).strip_edges()
	if event_name.is_empty():
		return false
	if not _initialized or not is_instance_valid(_wwise):
		return false
	var event := _get_wwise_event(event_name)
	if event == null or not event.has_method("post_callback"):
		return false
	var target: Node = source if is_instance_valid(source) else self
	var flags: int = AK_END_OF_EVENT | AK_DURATION
	var playing_id: Variant = event.call("post_callback", target, flags, callback)
	if playing_id == null or int(playing_id) <= 0:
		_warn_once("post_failed:test_play_callback", "Wwise accepted no playing ID for test_play callback post.")
		return false
	return true


func get_status() -> Dictionary:
	var event_status: Dictionary = {}
	for cache_key: String in _wwise_events:
		var event: Object = _wwise_events[cache_key]
		event_status[cache_key] = {
			"is_auto_bank_loaded": bool(event.get("is_auto_bank_loaded")),
		}
	return {
		"wwise_available": is_instance_valid(_wwise),
		"initialized": _initialized,
		"platform": _platform_name(),
		"bank_root": _platform_bank_root(),
		"rule_count": _rules.size(),
		"table_loaded": _table_loaded,
		"wwise_events": event_status,
		"diagnostics": _diagnostics.duplicate(),
	}


func _initialize() -> void:
	_do_initialize()
	# Printed regardless of which path _do_initialize() took (missing
	# singleton, failed init, or success) so this line is always present at
	# startup as a quick cross-platform sanity check; see docs/wwise-audio.md.
	print(
		"WWISE_STATUS platform=%s initialized=%s rules=%d table_loaded=%s" % [
			_platform_name(), _initialized, _rules.size(), _table_loaded,
		]
	)


func _do_initialize() -> void:
	if not Engine.has_singleton(WWISE_SINGLETON):
		_warn_once("missing_singleton", "Wwise extension not found; audio bridge is disabled.")
		return
	_wwise = Engine.get_singleton(WWISE_SINGLETON)
	if not _has_method("init") or not _has_method("is_initialized"):
		_warn_once("bad_singleton", "Wwise singleton is missing the expected runtime API.")
		return
	# Set the project-owned path before init so the stock integration can find
	# Init.bnk during its own startup step. This also avoids relying on an
	# absolute authoring-machine path in Wwise Project Settings.
	if _has_method("set_banks_path"):
		_wwise.call("set_banks_path", _platform_bank_root() + "/")
	# Guard against AK_AlreadyInitialized: something else (e.g. the stock
	# Wwise runtime manager, if it is ever wired up as an autoload alongside
	# this one) may have already called init() before this node ran.
	if bool(_wwise.call("is_initialized")):
		_warn_once("already_initialized", "Wwise was already initialized before WwiseManager ran; skipping duplicate init() call.")
	else:
		_wwise.call("init")
	_initialized = bool(_wwise.call("is_initialized"))
	if not _initialized:
		_warn_once("init_failed", "Wwise initialization failed; the game will continue without Wwise audio.")
		return
	# Keep these explicit as a guard for older integration builds whose
	# ProjectSettings cache may still contain a stale path or language.
	if _has_method("set_banks_path"):
		_wwise.call("set_banks_path", _platform_bank_root() + "/")
	if _has_method("set_current_language"):
		_wwise.call("set_current_language", "SFX")
	# Every row in the audio table uses an Auto-Defined SoundBank, loaded on
	# demand per Event through WwiseEvent (see _get_wwise_event). Init.bnk is
	# the only bank loaded explicitly, and Wwise.init() already loaded it
	# above, so there is nothing left to pre-load here.


func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		_warn_once("config_missing", "Wwise audio table not found: %s" % CONFIG_PATH)
		return
	var header := file.get_csv_line(CONFIG_DELIMITER)
	if header.is_empty():
		_warn_once("config_empty", "Wwise audio table is empty: %s" % CONFIG_PATH)
		return
	if not header.is_empty():
		header[0] = str(header[0]).trim_prefix("\ufeff").strip_edges()
	var columns: Dictionary = {}
	for index in range(header.size()):
		columns[str(header[index]).strip_edges()] = index
	for line_number in range(2, 10000):
		if file.eof_reached():
			break
		var row := file.get_csv_line(CONFIG_DELIMITER)
		if row.size() == 1 and str(row[0]).strip_edges().is_empty():
			continue
		var key := _csv_value(row, columns, "key").strip_edges()
		if key.is_empty() or key.begins_with("#"):
			continue
		var rule := {
			"event": _csv_value(row, columns, "event").strip_edges(),
			"stop_event": _csv_value(row, columns, "stop_event").strip_edges(),
		}
		_rules[key] = rule
	_table_loaded = true
	if _rules.is_empty():
		_warn_once("config_no_rules", "Wwise audio table has no rows: %s" % CONFIG_PATH)


func _csv_value(row: PackedStringArray, columns: Dictionary, name: String) -> String:
	var index: int = int(columns.get(name, -1))
	return "" if index < 0 or index >= row.size() else str(row[index])


func _track_scene() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	var path := scene.scene_file_path
	if path.is_empty() or path == _current_scene_path:
		return
	_stop_scene_event()
	_current_scene_path = path
	_current_scene_key = str(scene.get_meta("wwise_scene_key", INITIAL_SCENE_KEYS.get(path, "")))
	_wired_buttons.clear()
	_wire_buttons(scene)
	if not _current_scene_key.is_empty():
		_play_rule("scene_%s" % _current_scene_key, self)


func _wire_buttons(scene: Node) -> void:
	for node in scene.find_children("*", "BaseButton", true, false):
		if not node.has_signal("pressed"):
			continue
		var id := node.get_instance_id()
		if _wired_buttons.has(id):
			continue
		_wired_buttons[id] = true
		node.pressed.connect(_on_button_pressed.bind(node))


func _on_button_pressed(button: BaseButton) -> void:
	play(["ui_button_" + button.name, "ui_button"], self)


func _stop_scene_event() -> void:
	if _current_scene_key.is_empty():
		return
	stop("scene_%s" % _current_scene_key, self)


func _play_rule(key: String, source: Node) -> bool:
	var rule: Dictionary = _rules.get(key, {})
	if rule.is_empty():
		return false
	var event := str(rule.get("event", "")).strip_edges()
	if event.is_empty():
		return false
	return _post_event(event, source, key)


func _post_event(event_name: String, source: Node, diagnostic_key: String) -> bool:
	if not _initialized or not is_instance_valid(_wwise):
		return false
	var event := _get_wwise_event(event_name)
	if event == null:
		return false
	var target: Node = source if is_instance_valid(source) else self
	var playing_id: Variant = event.call("post", target)
	# A valid playing ID proves Wwise accepted the event. It does not prove that
	# a physical output device is audible, so diagnostics deliberately say post.
	if playing_id == null or int(playing_id) <= 0:
		_warn_once("post_failed:" + diagnostic_key, "Wwise accepted no playing ID for event %s (rule %s)." % [event_name, diagnostic_key])
		return false
	return true


func _stop_event(event_name: String, source: Node, diagnostic_key: String) -> bool:
	if not _initialized or not is_instance_valid(_wwise):
		return false
	var event := _get_wwise_event(event_name)
	if event == null:
		return false
	if not event.has_method("stop"):
		_warn_once("stop_missing:" + diagnostic_key, "WwiseEvent has no stop method (rule %s)." % diagnostic_key)
		return false
	var target: Node = source if is_instance_valid(source) else self
	event.call("stop", target, 0, AK_CURVE_LINEAR)
	return true


func _get_wwise_event(event_name: String) -> Object:
	## Returns a cached WwiseEvent Resource for event_name, creating it the
	## first time it is needed.
	##
	## The Wwise project uses Auto-Defined SoundBanks (one bank per Event,
	## named after the Event, plus loose .wem media files). The stock
	## Wwise.load_bank()/post_event() path loads the Event bank's structure
	## but never the loose media, because load_bank() always loads with the
	## "User" bank type; every post then logs
	## "Media <id> was not loaded for this source" and nothing is heard.
	## The Wwise plugin wiki says to use the WwiseEvent resource type for
	## Auto-Defined SoundBanks instead: it knows how to prepare/load an
	## Event's own bank (type "Event") including its media. See
	## docs/wwise-audio.md for the full writeup.
	if _wwise_events.has(event_name):
		return _wwise_events[event_name]
	if not ClassDB.class_exists(WWISE_EVENT_CLASS):
		_warn_once("wwise_event_class_missing", "WwiseEvent class not found; the Wwise GDExtension may be missing or out of date.")
		return null
	if not _has_method("get_id_from_string"):
		_warn_once("get_id_from_string_missing", "Wwise singleton has no get_id_from_string method; cannot resolve event IDs.")
		return null
	var event: Object = ClassDB.instantiate(WWISE_EVENT_CLASS)
	if event == null:
		_warn_once("wwise_event_instantiate_failed", "Failed to instantiate a WwiseEvent for %s." % event_name)
		return null
	var event_id: int = int(_wwise.call("get_id_from_string", event_name))
	event.set("name", event_name)
	event.set("id", event_id)
	event.set("is_in_user_defined_sound_bank", false)
	# Auto-Defined SoundBanks name the per-event bank after the event itself,
	# so the bank's ShortID hash equals the event's ShortID.
	event.set("bank_id", event_id)
	if event.has_method("_on_post_resource_init"):
		# WwiseEvent normally runs this hook when Godot loads it from a
		# .tres resource file. Building it with ClassDB.instantiate()
		# skips that, so call it explicitly -- this is what actually
		# starts the async Auto-Defined bank/media prepare and eventually
		# flips is_auto_bank_loaded to true. Without it, post() still
		# returns a playing ID but the engine logs "Media ... was not
		# loaded for this source" and nothing plays.
		event.call("_on_post_resource_init")
	_wwise_events[event_name] = event
	return event


func _has_method(method_name: StringName) -> bool:
	return is_instance_valid(_wwise) and _wwise.has_method(method_name)


func _platform_name() -> String:
	if OS.has_feature("web"):
		return "Web"
	match OS.get_name():
		"Windows": return "Windows"
		"macOS": return "Mac"
		"Android": return "Android"
		"iOS": return "iOS"
		"Linux": return "Linux"
	return OS.get_name()


func _platform_bank_root() -> String:
	return BANK_ROOT.path_join(_platform_name())


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	_diagnostics.append(message)
	push_warning(message)
