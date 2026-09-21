extends SceneTree
## Run against a disposable save. -- --screenshots also captures both real maps.

var failures := 0
var session: Node
var capture := false


func _initialize() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _check(value: bool, text: String) -> void:
	print("PASS: " if value else "FAIL: ", text)
	if not value:
		failures += 1


func _frames(count := 5) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _walk(action: String, count: int) -> void:
	# Renew synthetic input each physics tick: opening a hidden render window can
	# issue focus-out, which correctly clears the game's currently held inputs.
	for i in range(count):
		Input.action_press(action)
		await physics_frame
	Input.action_release(action)
	await _frames(2)


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _screenshot(name: String) -> void:
	if not capture:
		return
	await _frames(3)
	# Static overviews may skip a frame when the test window is hidden.
	RenderingServer.force_draw(false)
	_check(root.get_texture().get_image().save_png("res://build/qa/%s.png" % name) == OK, "Screenshot " + name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	session = root.get_node("GameSession")
	session.progress_path = "res://build/qa/tutorial_test_progress.cfg"
	_check(session.start_game(false) == OK, "New game loads grass")
	await _frames()
	_check(session.tutorial_stage == 0 and current_scene.elf.position == Vector2(288, 288), "E6 spawn matches source")
	_check(current_scene.get_node("Props/Guide").position == Vector2(480, 224), "H5 guide matches source")
	_check(current_scene.get_node("Props/Chest3").position == Vector2(736, 416), "L8 chest matches source")
	_check(not current_scene.elf.test_move(current_scene.elf.global_transform, Vector2.ZERO), "Grass spawn is clear")
	await _screenshot("tutorial_grass_gameplay")
	var profile := root.get_node("InputProfile")
	profile.set_mobile(true)
	await _frames()
	var controls: Control = current_scene.mobile_controls
	var joystick: Vector2 = controls.joystick_center()
	var touch := InputEventScreenTouch.new()
	touch.index = 4
	touch.pressed = true
	touch.position = joystick
	root.push_input(touch, true)
	await _frames(2)
	var drag := InputEventScreenDrag.new()
	drag.index = 4
	drag.position = joystick + Vector2(64, 0)
	root.push_input(drag, true)
	await _frames(2)
	_check(current_scene.elf.touch_direction.x > 0, "Touch drag drives movement")
	touch.pressed = false
	touch.position = Vector2(1120, 750) # Release over the HUD button.
	root.push_input(touch, true)
	await _frames(2)
	_check(controls.joystick_id == -1 and current_scene.elf.touch_direction == Vector2.ZERO, "Touch release over HUD stops movement")
	profile.set_mobile(false)
	await _frames()
	current_scene.elf.position = Vector2(288, 288)
	# Walk from E6 to H5 and interact using the real keyboard input handler.
	await _walk("move_right", 75)
	await _key(KEY_E)
	_check(session.tutorial_guide_spoken, "Keyboard movement reaches guide and E talks")
	await _walk("move_down", 54)
	await _key(KEY_E)
	_check(session.tutorial_chests == 1, "E opens nearby first chest")
	await _key(KEY_E)
	_check(session.tutorial_chests == 1, "Opened chest cannot be collected twice")
	for i in range(1, 3):
		current_scene.elf.position = current_scene.get_node("Props/Chest%d" % (i + 1)).position - Vector2(0, 65)
		await _key(KEY_E)
	_check(session.tutorial_chests == 7, "All three source chests are reachable")
	current_scene.set_map_open(true)
	var still: Vector2 = current_scene.elf.position
	await _walk("move_right", 15)
	_check(current_scene.elf.position == still, "Overview pauses movement")
	await _screenshot("tutorial_grass_overview")
	await _key(KEY_ESCAPE)
	_check(not current_scene.map_open and current_scene.map_index == 0, "Esc first closes overview")
	current_scene.elf.position = Vector2(290, 288)
	await _walk("move_left", 100)
	_check(current_scene.elf.position.x > 134, "Left tree trunk blocks walking")
	current_scene.elf.position = Vector2(600, 95)
	await _walk("move_up", 60)
	_check(current_scene.elf.position.y >= 73, "Northern trees block walking")
	current_scene.elf.position = Vector2(800, 340)
	current_scene.elf.facing = "left"
	await _key(KEY_ESCAPE)
	_check(current_scene.scene_file_path == session.MENU_SCENE, "Esc saves tutorial and returns to title")
	current_scene.get_node("%ContinueButton").pressed.emit()
	await _frames()
	_check(current_scene.map_index == 0 and current_scene.elf.position == Vector2(800, 340) and current_scene.elf.facing == "left", "Continue resumes grass position and facing")
	_check(session.tutorial_chests == 7 and session.tutorial_guide_spoken, "Continue retains guide and chests")
	# A failed save must keep the player in grass.
	var good_path: String = session.progress_path
	session.progress_path = "res://build/qa/missing_directory/progress.cfg"
	current_scene.elf.position = Vector2(1280, 320)
	await _frames()
	_check(current_scene.map_index == 0 and session.tutorial_stage == 0, "Failed save prevents map transition")
	session.progress_path = good_path
	# Exercise the unobstructed road and automatic entrance crossing.
	current_scene.elf.position = Vector2(1150, 320)
	await _walk("move_right", 65)
	_check(current_scene.scene_file_path == session.TUTORIAL_SCENES[1] and session.tutorial_stage == 1, "Walk through grass portal enters cave")
	_check(not current_scene.elf.test_move(current_scene.elf.global_transform, Vector2.ZERO), "Cave spawn is clear")
	await _screenshot("tutorial_cave_gameplay")
	current_scene.elf.position = Vector2(600, 154)
	await _walk("move_up", 60)
	_check(current_scene.elf.position.y >= 137, "Cave stone walls block walking")
	current_scene.elf.position = Vector2(1280, 320)
	await _frames()
	_check(current_scene.map_index == 1 and session.tutorial_stage == 1, "Boss must be defeated before camp exit")
	current_scene.elf.position = Vector2(500, 320)
	await _key(KEY_SPACE)
	_check(session.tutorial_boss_hits == 0, "Attacks out of range do not hit boss")
	current_scene.elf.position = Vector2(848, 320)
	await _frames(30)
	await _screenshot("tutorial_boss_encounter")
	await _key(KEY_SPACE)
	_check(session.tutorial_boss_hits == 1, "Nearby attack damages boss")
	await _key(KEY_J)
	_check(session.tutorial_boss_hits == 1, "Attack cooldown prevents repeat damage")
	await _key(KEY_ESCAPE)
	current_scene.get_node("%ContinueButton").pressed.emit()
	await _frames()
	_check(current_scene.map_index == 1 and session.tutorial_boss_hits == 1, "Continue resumes cave and boss progress")
	for i in range(2):
		await _frames(30)
		await _key(KEY_J)
	_check(session.tutorial_boss_hits == 3 and current_scene.get_node("Props/Portal").activated, "Boss defeat unlocks exit")
	await _screenshot("tutorial_boss_complete")
	current_scene.set_map_open(true)
	await _screenshot("tutorial_cave_overview")
	current_scene.set_map_open(false)
	current_scene.elf.position = Vector2(1150, 320)
	await _walk("move_right", 65)
	_check(current_scene.scene_file_path == session.CAMP_SCENE and session.tutorial_stage == 2, "Cave exit completes tutorial and enters camp")
	_check(session.saved_position == session.DEFAULT_POSITION, "Tutorial never overwrites forest coordinates")
	await _screenshot("tutorial_complete_camp")
	# Legacy saves belong to players who already reached the camp.
	for version in [1, 2]:
		var save := ConfigFile.new()
		save.set_value("progress", "version", version)
		save.set_value("progress", "position", Vector2(0.5, 0.5))
		save.set_value("progress", "facing", "up")
		save.save(session.progress_path)
		session.load_progress()
		_check(session.has_save and session.tutorial_stage == 2, "Legacy version %d skips tutorial" % version)
		_check(session.saved_position == (session.DEFAULT_POSITION if version == 1 else Vector2(0.5, 0.5)), "Legacy position migration %d" % version)
	DirAccess.remove_absolute(session.progress_path)
	print("TUTORIAL TESTS: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
