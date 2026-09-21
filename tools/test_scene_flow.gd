extends SceneTree
## Exercise the real scene buttons using a separate, disposable progress file.

var failures := 0
var session: Node


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1


func _settle() -> void:
	for i in range(5):
		await physics_frame
		await process_frame


func _press(path: String) -> void:
	current_scene.get_node(path).pressed.emit()
	await _settle()


func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await _settle()
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()


func _run() -> void:
	session = root.get_node("GameSession")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	session.progress_path = "res://build/qa/flow_test_progress.cfg"
	if FileAccess.file_exists(session.progress_path):
		DirAccess.remove_absolute(session.progress_path)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _settle()
	_check(current_scene.scene_file_path == session.MENU_SCENE, "Project starts at login")
	_check(current_scene.get_node("%ContinueButton").disabled, "No save disables Continue")
	await _press("%StartButton")
	_check(current_scene.scene_file_path == session.CAMP_SCENE, "Start opens main menu")
	_check(root.content_scale_size == Vector2i(960, 680), "Camp restores menu viewport")
	await _press("Navigation/Explore")
	_check(current_scene.scene_file_path == session.MAP_SCENE, "Explore opens forest")
	_check(root.content_scale_size == Vector2i(1280, 800), "Forest restores gameplay viewport")
	_check(current_scene.elf.position.is_equal_approx(current_scene.SPAWN), "New game uses forest spawn")
	current_scene.elf.position = Vector2(780, 380)
	current_scene.elf.facing = "up"
	current_scene.save_elapsed = 3.0
	await _settle()
	session.load_progress()
	_check((session.saved_position * current_scene.MAP_SIZE).is_equal_approx(Vector2(780, 380)) and session.saved_facing == "up", "Autosave records position and direction")
	current_scene.set_map_open(true)
	await _escape()
	_check(current_scene.scene_file_path == session.MAP_SCENE and not current_scene.map_open, "First Esc closes overview")
	await _escape()
	_check(current_scene.scene_file_path == session.CAMP_SCENE, "Second Esc returns to camp")
	await _press("Navigation/ReturnToLogin")
	_check(not current_scene.get_node("%ContinueButton").disabled, "Saved progress enables Continue")
	await _press("%ContinueButton")
	await _press("Navigation/Explore")
	_check(current_scene.elf.position.is_equal_approx(Vector2(780, 380)) and current_scene.elf.facing == "up", "Continue restores forest position and facing")
	await _press("HUD/Interface/ReturnToCamp")
	_check(current_scene.scene_file_path == session.CAMP_SCENE, "Return button opens camp")
	await _press("Navigation/ReturnToLogin")
	await _press("%StartButton")
	_check(current_scene.get_node("%Modal").visible, "New game confirms replacement")
	await _press("%CancelButton")
	_check(current_scene.scene_file_path == session.MENU_SCENE and not current_scene.get_node("%Modal").visible, "Cancel preserves current progress")
	await _press("%StartButton")
	await _press("%ConfirmButton")
	await _press("Navigation/Explore")
	_check(current_scene.elf.position.is_equal_approx(current_scene.SPAWN) and current_scene.elf.facing == "down", "Confirmed new game resets position and facing")
	await _press("HUD/Interface/ReturnToCamp")
	DirAccess.remove_absolute(session.progress_path)
	print("SCENE FLOW TESTS: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
