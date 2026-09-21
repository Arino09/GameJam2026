extends SceneTree
## 使用独立存档，验证设备分流、多指操作、取消输入和触屏场景流程。

const Profile = preload("res://scripts/input_profile.gd")
var failures := 0
var session: Node
var profile: Node
var capture := false


func _initialize() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1


func _frames(count := 5) -> void:
	for i in range(count):
		await process_frame


func _touch(index: int, position: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	# parse_input_event 接收窗口坐标，缩放后须由逻辑触点换算。
	event.position = root.get_final_transform() * position
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	await _frames(2)


func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = root.get_final_transform() * position
	Input.parse_input_event(event)
	await _frames(3)


func _tap(position: Vector2, index := 2) -> void:
	await _touch(index, position, true)
	await _touch(index, position, false)
	await _frames()


func _screenshot(name: String) -> void:
	if not capture:
		return
	await _frames(3)
	RenderingServer.force_draw(false)
	_check(root.get_texture().get_image().save_png("res://build/qa/%s.png" % name) == OK, "Screenshot " + name)


func _run() -> void:
	for info in [
		{"user_agent": "Mozilla/5.0 (Linux; Android 15) Chrome Mobile", "platform": "Linux armv8l"},
		{"user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS)"},
		{"user_agent": "Mozilla/5.0 (iPad; CPU OS)"},
		{"user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) Safari", "platform": "MacIntel", "touch_points": 5},
		{"user_agent": "reduced user agent", "mobile_hint": true},
	]:
		_check(Profile.detect_mobile("Web", info), "Mobile browser: " + str(info["user_agent"]))
	for info in [
		{"user_agent": "Mozilla/5.0 (Windows NT 10.0) Chrome", "platform": "Win32", "touch_points": 10},
		{"user_agent": "Mozilla/5.0 (Macintosh) Safari", "platform": "MacIntel", "touch_points": 0},
		{"user_agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox"},
		{},
	]:
		_check(not Profile.detect_mobile("Web", info), "Desktop or unavailable browser data stays on PC controls")
	_check(Profile.detect_mobile("Android", {}) and Profile.detect_mobile("iOS", {}), "Native mobile platforms")
	_check(not Profile.detect_mobile("Windows", {}), "Native desktop")
	session = root.get_node("GameSession")
	profile = root.get_node("InputProfile")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	session.progress_path = "res://build/qa/mobile_test_progress.cfg"
	if FileAccess.file_exists(session.progress_path):
		DirAccess.remove_absolute(session.progress_path)
	profile.set_mobile(true)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	change_scene_to_file(session.MENU_SCENE)
	await _frames(24)
	await _screenshot("mobile_login")
	await _tap(current_scene.get_node("%StartButton").get_global_rect().get_center(), 0)
	_check(current_scene.scene_file_path == session.TUTORIAL_SCENES[0], "Touch on title starts new game with mobile controls")
	var controls: Control = current_scene.mobile_controls
	var player: CharacterBody2D = current_scene.elf
	_check(controls.visible and not current_scene.hud.get_node("Overview").visible, "Mobile touch controls replace PC buttons")
	_check(not current_scene.hud.get_node("Objective").text.contains("按 E"), "Mobile objective has touch instructions")
	await _screenshot("mobile_grass")
	var center: Vector2 = controls.joystick_center()
	await _touch(0, center, true)
	await _drag(0, center + Vector2(3, 0))
	_check(player.touch_direction == Vector2.ZERO, "Joystick dead zone prevents drift")
	player.position = Vector2(650, 310)
	await _drag(0, center + Vector2(200, 200))
	_check(player.touch_direction.length() <= 1.001, "Diagonal touch speed stays normalized")
	_check(player.velocity.length() > 0, "Joystick moves the real character")
	await _touch(1, controls.button_rect("run").get_center(), true)
	_check(player.touch_running and player.velocity.length() > player.move_speed, "Second finger enables sprint while moving")
	await _touch(1, controls.button_rect("run").get_center(), false)
	_check(not player.touch_running and controls.joystick_id == 0 and player.touch_direction.length() > 0, "Releasing sprint preserves movement finger")
	await _touch(0, controls.button_rect("action").get_center(), false)
	_check(player.touch_direction == Vector2.ZERO and controls.joystick_id == -1, "Release outside joystick stops movement")
	player.position = Vector2(480, 290)
	await _frames()
	await _tap(controls.button_rect("action").get_center())
	_check(session.tutorial_guide_spoken, "Touch action talks to guide")
	player.position = Vector2(480, 351)
	await _frames()
	await _tap(controls.button_rect("action").get_center())
	_check(session.tutorial_chests == 1, "Touch action opens chest without changing existing loot rules")
	await _touch(0, center, true)
	await _drag(0, center + Vector2(68, 0))
	await _touch(1, controls.button_rect("run").get_center(), true)
	await _tap(controls.button_rect("map").get_center(), 3)
	_check(current_scene.map_open and not player.movement_enabled, "Third finger opens overview")
	_check(player.touch_direction == Vector2.ZERO and not player.touch_running, "Overview clears movement and sprint")
	await _screenshot("mobile_overview")
	await _tap(controls.button_rect("return").get_center(), 3)
	_check(not current_scene.map_open and current_scene.map_index == 0, "Mobile back first closes overview")
	await _touch(0, center, false)
	await _touch(1, controls.button_rect("run").get_center(), false)
	await _touch(0, center, true)
	await _drag(0, center + Vector2(68, 0))
	await _touch(0, center, false, true)
	_check(player.touch_direction == Vector2.ZERO, "Canceled touch releases joystick")
	await _touch(0, center, true)
	await _drag(0, center + Vector2(68, 0))
	await _touch(1, controls.button_rect("run").get_center(), true)
	controls.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(player.touch_direction == Vector2.ZERO and not player.touch_running, "Focus loss clears all touch holds")
	# 浏览器横竖屏变化：只等待 process_frame，兼容竖屏提示暂停场景的策略。
	root.size = Vector2i(390, 844)
	await _frames()
	_check(player.touch_direction == Vector2.ZERO and not player.touch_running, "Rotation does not retain movement")
	await _screenshot("mobile_portrait")
	root.size = Vector2i(844, 390)
	await _frames()
	_check(not paused, "Returning to landscape resumes play")
	_check(controls.button_rect("action").end.x < controls.size.x, "Action target fits narrow landscape screen")
	await _screenshot("mobile_landscape")
	# 不依赖键盘完成教程战斗与地图返回。
	player.position = Vector2(1280, 320)
	await _frames(8)
	_check(current_scene.map_index == 1, "Mobile movement can enter cave")
	controls = current_scene.mobile_controls
	player = current_scene.elf
	player.position = Vector2(848, 320)
	await _frames()
	center = controls.joystick_center()
	await _touch(0, center, true)
	await _drag(0, center + Vector2(0, 15))
	await _tap(controls.button_rect("action").get_center())
	_check(session.tutorial_boss_hits == 1 and controls.joystick_id == 0, "Attack finger works while movement finger remains held")
	await _touch(0, center, false)
	await _tap(controls.button_rect("action").get_center())
	_check(session.tutorial_boss_hits == 1, "Touch attacks respect cooldown")
	for i in range(2):
		await _frames(32)
		await _tap(controls.button_rect("action").get_center())
	_check(session.tutorial_boss_hits == 3, "Touch attacks complete tutorial boss")
	if session.tutorial_boss_hits != 3:
		quit(1)
		return
	await _screenshot("mobile_cave")
	player.position = Vector2(1280, 320)
	await _frames(8)
	_check(current_scene.scene_file_path == session.CAMP_SCENE, "Mobile tutorial reaches camp")
	await _screenshot("mobile_camp")
	# 标准菜单 Button 通过引擎的触屏转鼠标接收轻点。
	var had_settings := FileAccess.file_exists(session.SETTINGS_PATH)
	var original_settings := FileAccess.get_file_as_bytes(session.SETTINGS_PATH) if had_settings else PackedByteArray()
	await _tap(current_scene.get_node("Navigation/TopSystems/Settings").get_global_rect().get_center(), 0)
	_check(current_scene.get_node("SystemOverlay").visible, "Touch opens camp settings")
	await _tap(current_scene.get_node("%CloseButton").get_global_rect().get_center(), 0)
	_check(not current_scene.get_node("SystemOverlay").visible, "Touch closes menu modal")
	if had_settings:
		var settings_file := FileAccess.open(session.SETTINGS_PATH, FileAccess.WRITE)
		settings_file.store_buffer(original_settings)
		settings_file.close()
	else:
		DirAccess.remove_absolute(session.SETTINGS_PATH)
	await _tap(current_scene.get_node("Navigation/Explore").get_global_rect().get_center(), 0)
	_check(current_scene.scene_file_path == session.MAP_SCENE, "Touch menu starts forest exploration")
	controls = current_scene.mobile_controls
	_check(controls.visible and controls.action_mode == "none", "Forest shares joystick and sprint without tutorial attack")
	await _screenshot("mobile_forest")
	await _tap(controls.button_rect("return").get_center())
	_check(current_scene.scene_file_path == session.CAMP_SCENE, "Touch returns from forest to camp")
	profile.set_mobile(false)
	change_scene_to_file(session.MAP_SCENE)
	await _frames()
	_check(not current_scene.mobile_controls.visible, "Desktop hides touch overlay")
	Input.action_press("move_down")
	await _frames(6)
	_check(current_scene.elf.velocity.y > 0, "PC keyboard movement remains available")
	Input.action_release("move_down")
	await _screenshot("pc_forest_controls")
	DirAccess.remove_absolute(session.progress_path)
	print("MOBILE CONTROL TESTS: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
