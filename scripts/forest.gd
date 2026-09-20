extends Node2D
## Single background Sprite2D; all walk blocking is authored polygon geometry.

const TILE_SIZE := 32
const MAP_SIZE := Vector2(1536, 1024)
const SPAWN := Vector2(780, 310)
const MAP_TEXTURE: Texture2D = preload("res://assets/maps/moonveil_forest.png")
var map_open := false
var debug_grid := false
var elapsed := 0.0
var motes: Array[Vector3] = []
@onready var elf: CharacterBody2D = $Elf
@onready var camera: Camera2D = $Elf/Camera2D
@onready var hud: Control = $HUD/Interface


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260920
	for index in range(42):
		motes.append(Vector3(rng.randf_range(200, 1390), rng.randf_range(100, 960), rng.randf_range(0, TAU)))
	hud.world = self
	get_viewport().size_changed.connect(_resize_hud)
	_resize_hud()
	camera.reset_smoothing()


func _resize_hud() -> void:
	hud.size = get_viewport_rect().size / 2.0


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	hud.queue_redraw()
	$HUD/Interface/Location.text = location_name()
	$HUD/Interface/Location.visible = not map_open


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"world_map"):
		set_map_open(not map_open)
	elif event.is_action_pressed(&"reset_position"):
		reset_player()
	elif event.is_action_pressed(&"debug_grid"):
		debug_grid = not debug_grid
	elif event.is_action_pressed(&"ui_cancel") and map_open:
		set_map_open(false)


func set_map_open(value: bool) -> void:
	map_open = value
	elf.movement_enabled = not value
	elf.touch_direction = Vector2.ZERO
	hud.cancel_touch()


func reset_player() -> void:
	set_map_open(false)
	elf.position = SPAWN
	elf.velocity = Vector2.ZERO
	elf.facing = "down"
	elf.walk_phase = 0.0
	camera.reset_smoothing()


func location_name() -> String:
	if elf.position.x > 1145:
		return "溪光木桥"
	if elf.position.x < 530:
		return "旧日回廊"
	if elf.position.y < 285:
		return "月门祭坛"
	if elf.position.y > 735:
		return "南境林径"
	return "星纹岔路"


func _draw() -> void:
	# Sparse ambient pollen; the environment itself remains one flattened sprite.
	for mote in motes:
		var drift := Vector2(sin(elapsed * 0.35 + mote.z) * 7, cos(elapsed * 0.25 + mote.z) * 5)
		var opacity := 0.18 + 0.3 * maxf(0.0, sin(elapsed * 0.9 + mote.z))
		draw_rect(Rect2((Vector2(mote.x, mote.y) + drift).round(), Vector2.ONE), Color(0.9, 0.95, 0.67, opacity))
	if debug_grid:
		for x in range(0, int(MAP_SIZE.x) + 1, TILE_SIZE):
			draw_line(Vector2(x, 0), Vector2(x, MAP_SIZE.y), Color(1, 1, 1, 0.18))
		for y in range(0, int(MAP_SIZE.y) + 1, TILE_SIZE):
			draw_line(Vector2(0, y), Vector2(MAP_SIZE.x, y), Color(1, 1, 1, 0.18))
		for shape in $Obstacles.get_children():
			if shape is CollisionPolygon2D:
				draw_colored_polygon(shape.polygon, Color(0.9, 0.25, 0.4, 0.25))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(elf):
		for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"sprint"]:
			Input.action_release(action)
		elf.touch_direction = Vector2.ZERO
		hud.cancel_touch()
