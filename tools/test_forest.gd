extends SceneTree
## Native gameplay checks; add -- --screenshots with a graphics driver for QA PNGs.

var world: Node2D
var elf: CharacterBody2D
var failures: PackedStringArray = []
var capture := false


func _initialize() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa"))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error(message)


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame


func _walk(actions: Array, count: int) -> void:
	for action in actions:
		Input.action_press(action)
	await _frames(count)
	for action in actions:
		Input.action_release(action)
	await _frames(2)


func _place(point: Vector2) -> void:
	elf.position = point
	elf.velocity = Vector2.ZERO
	await _frames(3)


func _screenshot(name: String) -> void:
	if not capture:
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://build/qa/%s.png" % name)
	_check(result == OK, "Rendered screenshot: " + name)


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _record_walk() -> void:
	if not capture:
		return
	world.reset_player()
	await _frames(3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/qa/elf_v2/ingame"))
	Input.action_press(&"move_down")
	for index in range(32):
		await _frames(4)
		await RenderingServer.frame_post_draw
		var crop := root.get_texture().get_image().get_region(Rect2i(416, 272, 448, 448))
		crop.save_png("res://build/qa/elf_v2/ingame/%02d.png" % index)
	Input.action_release(&"move_down")
	await _frames(2)
	world.reset_player()


func _run() -> void:
	var session := root.get_node("GameSession")
	session.progress_path = "res://build/qa/forest_test_progress.cfg"
	session.saved_position = session.DEFAULT_POSITION
	session.saved_facing = "down"
	world = load("res://scenes/forest.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	elf = world.get_node("Elf")
	await _frames(5)
	_check(world.hud.has_method("cancel_touch"), "HUD script loads successfully")
	_check(world.get_node("MapImage") is Sprite2D, "Map uses one Sprite2D")
	_check(world.get_node("MapImage").texture.get_size() == Vector2(1536, 1024), "Map is 48 × 32 cells at 32 px")
	_check(world.find_children("*", "TileMap", true, false).is_empty() and world.find_children("*", "TileMapLayer", true, false).is_empty(), "No TileMap or TileMapLayer")
	_check(not FileAccess.file_exists("res://scenes/preview.tscn"), "Old animation preview removed")
	_check(not elf.test_move(elf.global_transform, Vector2.ZERO), "Spawn is clear")
	await _screenshot("forest_gameplay")
	var atlas: Image = load("res://assets/elf/v2/elf_atlas.png").get_image()
	_check(atlas.get_size() == Vector2i(1152, 512) and atlas.get_pixel(0, 0).a == 0.0, "High detail transparent elf atlas")
	_check(elf.sprite.scale * world.camera.zoom == Vector2.ONE, "Sprite pixels render 1:1 at default resolution")
	for facing in ["down", "left", "right", "up"]:
		var frames: SpriteFrames = elf.sprite.sprite_frames
		_check(frames.get_frame_count("walk_" + facing) == 8, "Eight walk frames: " + facing)
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		await _place(Vector2(780, 380))
		var start := elf.position
		await _walk([action], 24)
		_check(elf.position.distance_to(start) > 38, "Movement: " + action)
		_check(elf.sprite.animation == StringName("idle_" + action.trim_prefix("move_")), "Correct facing / idle after " + action)
	await _place(Vector2(780, 380))
	elf.walk_phase = 0.15
	Input.action_press(&"move_down")
	await _frames(10)
	var phase_before: float = elf.walk_phase
	Input.action_release(&"move_down")
	Input.action_press(&"move_right")
	await _frames(1)
	_check(elf.walk_phase > phase_before and elf.walk_phase - phase_before < 0.1 and elf.sprite.frame > 1, "Turning preserves the current stride instead of restarting at frame zero")
	Input.action_release(&"move_right")
	await _frames(2)
	phase_before = elf.walk_phase
	await _frames(12)
	_check(is_equal_approx(elf.walk_phase, phase_before), "Standing still does not advance the walk cycle")
	await _place(Vector2(780, 380))
	var start := elf.position
	await _walk(["move_down"], 24)
	var straight := elf.position.distance_to(start)
	await _place(start)
	await _walk(["move_down", "move_right"], 24)
	_check(absf(elf.position.distance_to(start) - straight) < 3, "Diagonal speed normalized")
	await _place(start)
	await _walk(["move_down", "sprint"], 24)
	_check(elf.position.distance_to(start) > straight * 1.4, "Sprint increases speed")
	await _place(Vector2(1110, 480))
	await _walk(["move_right"], 115)
	_check(elf.position.x > 1310, "Bridge crosses from west to east bank")
	await _walk(["move_left"], 115)
	_check(elf.position.x < 1130, "Bridge crosses from east to west bank")
	await _place(Vector2(1110, 480))
	await _walk(["move_right"], 58)
	await _screenshot("forest_bridge")
	await _walk(["move_up"], 60)
	print("Bridge railing contact: ", elf.position)
	_check(elf.position.y > 459, "Bridge upper railing blocks entry to water")
	await _place(Vector2(1100, 800))
	await _walk(["move_right"], 90)
	print("River bank contact: ", elf.position)
	var river: CollisionPolygon2D = world.get_node("Obstacles/RiverSouth")
	_check(not Geometry2D.is_point_in_polygon(elf.position + Vector2(0, -3), river.polygon) and elf.position.x < 1180, "River blocks walking through water while allowing sliding along bank")
	await _place(Vector2(780, 310))
	await _walk(["move_up"], 120)
	_check(elf.position.y > 180 and elf.position.y < 215, "Shrine approach open, stone arch blocks")
	await _place(Vector2(400, 399))
	await _walk(["move_up"], 60)
	_check(elf.position.y > 340, "Ruin wall collision")
	await _place(Vector2(770, 980))
	await _walk(["move_down"], 60)
	_check(elf.position.y < 1006, "South map boundary blocks exit")
	for point in [Vector2(780, 185), Vector2(780, 1000), Vector2(90, 500), Vector2(1500, 500)]:
		await _place(point)
		var center: Vector2 = world.camera.get_screen_center_position()
		var half_view: Vector2 = root.get_visible_rect().size / world.camera.zoom / 2.0
		_check(center.x >= half_view.x and center.x <= world.MAP_SIZE.x - half_view.x and center.y >= half_view.y and center.y <= world.MAP_SIZE.y - half_view.y, "Camera stays inside map at " + str(point))
	world.reset_player()
	await _frames(3)
	await _key(KEY_M)
	_check(world.map_open, "M key opens full map")
	start = elf.position
	await _walk(["move_down"], 12)
	_check(elf.position.is_equal_approx(start), "Map view pauses movement")
	await _screenshot("forest_overview")
	await _key(KEY_ESCAPE)
	_check(not world.map_open, "Esc key closes full map")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(1150, 60)
	root.push_input(click, true)
	await _frames(2)
	_check(world.map_open, "Map button hit test follows 2x HUD scaling")
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	root.push_input(click, true)
	world.set_map_open(false)
	await _walk(["move_down"], 12)
	_check(elf.position.y > start.y + 15, "Movement resumes after map closes")
	await _key(KEY_R)
	_check(elf.position.is_equal_approx(world.SPAWN), "R key resets spawn")
	await _key(KEY_F3)
	_check(world.debug_grid, "F3 toggles 32 px collision grid")
	await _screenshot("forest_collision_debug")
	world.debug_grid = false
	await _record_walk()
	await _screenshot("forest_gameplay")
	print("FOREST TESTS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
