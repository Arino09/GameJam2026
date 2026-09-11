extends Node2D
## Empty top-down movement area with keyboard and simultaneous touch controls.

@onready var character: Node2D = $Character
@onready var controls: Node2D = $HUD/Controls
var buttons: Dictionary = {}


func _ready() -> void:
	_add_button("Left", &"move_left", "←")
	_add_button("Right", &"move_right", "→")
	_add_button("Up", &"move_up", "↑")
	_add_button("Down", &"move_down", "↓")
	_add_button("Attack", &"attack", "攻击", true)
	get_viewport().size_changed.connect(_layout)
	_layout()
	character.position = character.movement_bounds.get_center()


func _add_button(button_name: String, action: StringName, caption: String, large := false) -> void:
	var button := TouchScreenButton.new()
	button.name = button_name
	button.action = action
	button.texture_normal = load("res://assets/controls/attack.svg" if large else "res://assets/controls/direction.svg")
	button.texture_pressed = load("res://assets/controls/attack_pressed.svg" if large else "res://assets/controls/direction_pressed.svg")
	button.passby_press = not large
	var hit_shape := RectangleShape2D.new()
	var side := 100.0 if large else 64.0
	hit_shape.size = Vector2(side, side)
	button.shape = hit_shape
	controls.add_child(button)
	var label := Label.new()
	label.text = caption
	label.size = Vector2(side, side)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24 if large else 28)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	buttons[button_name] = button


func _layout() -> void:
	var size := get_viewport_rect().size
	buttons["Up"].position = Vector2(114, size.y - 222)
	buttons["Left"].position = Vector2(42, size.y - 150)
	buttons["Down"].position = Vector2(114, size.y - 150)
	buttons["Right"].position = Vector2(186, size.y - 150)
	buttons["Attack"].position = Vector2(size.x - 160, size.y - 184)
	# Bounds use the feet as origin and reserve space above for the character.
	character.movement_bounds = Rect2(85, 235, maxf(1, size.x - 170), maxf(1, size.y - 490))
	character.position = character.position.clamp(character.movement_bounds.position, character.movement_bounds.end)
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(28, 82, size.x - 56, size.y - 322), Color("23323c"))
	draw_rect(Rect2(28, 82, size.x - 56, size.y - 322), Color("455a65"), false, 2.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"attack"]:
			Input.action_release(action)
