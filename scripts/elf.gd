extends CharacterBody2D
## 128 px source frames rendered at 1:1 screen pixels by the 2x camera.
## World height remains ~60 px (just under two 32 px map cells).

@export var move_speed := 112.0
@export var run_speed := 176.0
var facing := "down"
var movement_enabled := true
var touch_direction := Vector2.ZERO
var touch_running := false
var walk_phase := 0.0
var _audio_movement_key := ""
const WALK_CYCLE_DISTANCE := 64.0
const RUN_CYCLE_DISTANCE := 80.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Phase is advanced by actual travel, not a second independent animation clock.
	sprite.pause()


func _exit_tree() -> void:
	if not _audio_movement_key.is_empty():
		WwiseManager.stop([_audio_movement_key + "_" + WwiseManager.get_scene_key(), _audio_movement_key], self)
		_audio_movement_key = ""


func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO
	if movement_enabled:
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if touch_direction.length_squared() > 0.01:
			direction = touch_direction.limit_length()
	var running := Input.is_action_pressed(&"sprint") or touch_running
	velocity = direction * (run_speed if running else move_speed)
	var previous := position
	move_and_slide()
	if direction != Vector2.ZERO:
		var horizontal := absf(direction.x) > absf(direction.y)
		if absf(absf(direction.x) - absf(direction.y)) < 0.05:
			horizontal = facing == "left" or facing == "right"
		if horizontal:
			facing = "right" if direction.x > 0.0 else "left"
		else:
			facing = "down" if direction.y > 0.0 else "up"
	var travel := position.distance_to(previous)
	var moving := travel > 0.001
	var movement_key := "run" if moving and running else ("walk" if moving else "")
	if movement_key != _audio_movement_key:
		if not _audio_movement_key.is_empty():
			WwiseManager.stop([_audio_movement_key + "_" + WwiseManager.get_scene_key(), _audio_movement_key], self)
		_audio_movement_key = movement_key
		if not movement_key.is_empty():
			WwiseManager.play([movement_key + "_" + WwiseManager.get_scene_key(), movement_key], self)
	if moving:
		walk_phase = fposmod(walk_phase + travel / (RUN_CYCLE_DISTANCE if running else WALK_CYCLE_DISTANCE), 1.0)
	var animation := StringName(("walk_" if moving else "idle_") + facing)
	if sprite.animation != animation:
		sprite.animation = animation
	var phase_frame := walk_phase * 8.0 if moving else 0.0
	sprite.set_frame_and_progress(int(phase_frame), fposmod(phase_frame, 1.0))
	# Half a world pixel is exactly one screen pixel with the 2x camera.
	sprite.position = (position * 2.0).round() / 2.0 - position
	queue_redraw()


func _draw() -> void:
	var offset := (position * 2.0).round() / 2.0 - position
	draw_rect(Rect2(Vector2(-9, -2) + offset, Vector2(18, 4)), Color(0.07, 0.11, 0.13, 0.24))
	draw_rect(Rect2(Vector2(-6, -3) + offset, Vector2(12, 6)), Color(0.07, 0.11, 0.13, 0.19))
