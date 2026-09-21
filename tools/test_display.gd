extends SceneTree
## 检查真实场景在窗口缩放、设备切换和旋转后的视口与可点击区域。

var failures := 0
var profile: Node
var capture := false
const SCENES := ["login", "main_menu", "tutorial_grass", "tutorial_cave", "forest"]


func _initialize() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1


func _settle() -> void:
	for i in range(5):
		await process_frame


func _resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	await _settle()


func _check_scene_bounds(scene_name: String) -> void:
	var bounds := root.get_visible_rect()
	if scene_name == "login":
		for button in ["%StartButton", "%ContinueButton", "%SettingsButton", "%ExitButton"]:
			_check(bounds.encloses(current_scene.get_node(button).get_global_rect()), "Login button stays in viewport: " + button)
	elif scene_name == "main_menu":
		for button in current_scene.get_node("Navigation").find_children("*", "Button", true, false):
			_check(bounds.encloses(button.get_global_rect()), "Camp button stays in viewport: " + button.name)
	elif profile.mobile:
		var controls: Control = current_scene.get_node("MobileControls/Controls")
		_check(bounds.has_point(controls.joystick_center()), "Joystick stays in viewport")
		for kind in ["run", "action", "map", "return"]:
			_check(bounds.encloses(controls.button_rect(kind)), "Touch target stays in viewport: " + kind)


func _screenshot(name: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://build/qa/display_%s.png" % name) == OK, "Rendered " + name)


func _run() -> void:
	profile = root.get_node("InputProfile")
	var session := root.get_node("GameSession")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	session.progress_path = "res://build/qa/display_test_progress.cfg"
	if FileAccess.file_exists(session.progress_path):
		DirAccess.remove_absolute(session.progress_path)
	root.mode = Window.MODE_WINDOWED
	profile.set_mobile(false)
	for dimensions in [Vector2i(640, 360), Vector2i(1366, 768), Vector2i(2560, 1080), Vector2i(1024, 768)]:
		await _resize(dimensions)
		for scene_name in SCENES:
			change_scene_to_file("res://scenes/%s.tscn" % scene_name)
			await _settle()
			_check(root.get_visible_rect().size == Vector2(1280, 720), "Desktop 16:9 survives resize and scene change: %s %s" % [dimensions, scene_name])
			_check(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "Window supports fractional scaling")
			_check_scene_bounds(scene_name)
			if dimensions == Vector2i(1366, 768):
				await _screenshot("desktop_" + scene_name)
	profile.set_mobile(true)
	for dimensions in [Vector2i(844, 390), Vector2i(1024, 768), Vector2i(640, 360)]:
		await _resize(dimensions)
		for scene_name in SCENES:
			change_scene_to_file("res://scenes/%s.tscn" % scene_name)
			await _settle()
			var logical_size := root.get_visible_rect().size
			_check(logical_size.y == 720 and absf(logical_size.x / 720.0 - float(dimensions.x) / dimensions.y) < 0.002, "Mobile fits height and device aspect: %s %s" % [dimensions, scene_name])
			_check_scene_bounds(scene_name)
			if dimensions != Vector2i(640, 360):
				await _screenshot("mobile_%d_%s" % [dimensions.x, scene_name])
	var controls: Control = current_scene.get_node("MobileControls/Controls")
	controls.joystick_id = 1
	controls.player.touch_direction = Vector2.RIGHT
	controls.player.touch_running = true
	await _resize(Vector2i(390, 844))
	_check(paused and profile.get_node("OrientationOverlay/LandscapeHint").visible, "Portrait pauses gameplay and shows landscape prompt")
	_check(controls.joystick_id == -1 and controls.player.touch_direction == Vector2.ZERO and not controls.player.touch_running, "Rotation releases held touch inputs")
	await _screenshot("portrait")
	await _resize(Vector2i(844, 390))
	_check(not paused and not profile.get_node("OrientationOverlay/LandscapeHint").visible, "Landscape resumes gameplay and hides prompt")
	paused = true
	await _resize(Vector2i(390, 844))
	await _resize(Vector2i(844, 390))
	_check(paused, "Rotation preserves an existing pause")
	paused = false
	profile.set_mobile(false)
	await _settle()
	_check(root.get_visible_rect().size == Vector2(1280, 720), "Returning to desktop restores 16:9")
	change_scene_to_file("res://scenes/login.tscn")
	await _settle()
	if FileAccess.file_exists(session.progress_path):
		DirAccess.remove_absolute(session.progress_path)
	print("DISPLAY TESTS: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
