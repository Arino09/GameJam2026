extends Node2D
## Reusable character. Call attack(); the non-looping animation returns to idle.

signal attack_finished

@export var movement_enabled := false
@export var move_speed := 230.0
var movement_bounds := Rect2(0, 0, 960, 680)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_update_swing_mask)
	sprite.animation_changed.connect(_update_swing_mask)
	sprite.play(&"idle")


func _physics_process(delta: float) -> void:
	if not movement_enabled:
		return
	if Input.is_action_just_pressed(&"attack"):
		attack()
	# Movement runs independently so it cannot interrupt the attack animation.
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if not is_zero_approx(direction.x):
		sprite.flip_h = direction.x < 0.0
	position += direction * move_speed * delta
	position = position.clamp(movement_bounds.position, movement_bounds.end)


func attack() -> void:
	if sprite.animation == &"attack" and sprite.is_playing():
		return
	sprite.play(&"attack")


func _on_animation_finished() -> void:
	if sprite.animation == &"attack":
		sprite.play(&"idle")
		attack_finished.emit()


func _update_swing_mask() -> void:
	(sprite.material as ShaderMaterial).set_shader_parameter(
		&"wide_swing", sprite.animation == &"attack" and sprite.frame == 5
	)
	(sprite.material as ShaderMaterial).set_shader_parameter(
		&"recovery_pose", sprite.animation == &"attack" and sprite.frame == 6
	)
