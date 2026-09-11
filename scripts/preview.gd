extends Node2D

@onready var character: Node2D = $Character
@onready var status: Label = $CanvasLayer/Status


func _ready() -> void:
	$CanvasLayer/Attack.pressed.connect(character.attack)
	$CanvasLayer/Flip.toggled.connect(_on_flip_toggled)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			character.attack()


func _process(_delta: float) -> void:
	var sprite: AnimatedSprite2D = character.sprite
	var action := "ATTACK" if sprite.animation == &"attack" else "IDLE"
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	status.text = "%s   /   %02d — %02d" % [action, sprite.frame + 1, count]


func _on_flip_toggled(flipped: bool) -> void:
	character.sprite.flip_h = flipped


func _draw() -> void:
	draw_circle(Vector2(480, 458), 176, Color("202c3e"))
	draw_line(Vector2(200, 510), Vector2(760, 510), Color("42536a"), 1.0)
	draw_ellipse_shadow()


func draw_ellipse_shadow() -> void:
	var points := PackedVector2Array()
	for i in range(64):
		var angle := TAU * i / 64.0
		points.append(Vector2(480, 510) + Vector2(cos(angle) * 67, sin(angle) * 10))
	draw_colored_polygon(points, Color(0.03, 0.05, 0.08, 0.6))
