extends Control
## 三张地图共用的多点触控控制器，摇杆、奔跑与动作各自持有手指 ID。

signal interact_requested
signal attack_requested
signal map_requested
signal return_requested

const RADIUS := 68.0
const DEAD_ZONE := 0.16
const FONT = preload("res://assets/fonts/ui_chinese.ttf")
var player: CharacterBody2D
var action_mode := "none"
var action_caption := "互动"
var action_enabled := true
var return_caption := "返回营地"
var gameplay_enabled := true
var joystick_id := -1
var run_id := -1
var stick := Vector2.ZERO
var _buttons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InputProfile.changed.connect(_update_profile)
	resized.connect(cancel_touch)
	_update_profile()


func _update_profile() -> void:
	cancel_touch()
	visible = InputProfile.mobile


func joystick_center() -> Vector2:
	return Vector2(124, size.y - 124)


func button_rect(kind: String) -> Rect2:
	match kind:
		"run": return Rect2(size.x - 260, size.y - 119, 98, 88)
		"action": return Rect2(size.x - 142, size.y - 151, 112, 120)
		"map": return Rect2(size.x - 310, 22, 136, 62)
		"return": return Rect2(size.x - 158, 22, 136, 62)
	return Rect2()


func set_gameplay_enabled(value: bool) -> void:
	if gameplay_enabled != value:
		cancel_touch()
	gameplay_enabled = value
	queue_redraw()


func cancel_touch() -> void:
	joystick_id = -1
	run_id = -1
	_buttons.clear()
	stick = Vector2.ZERO
	if is_instance_valid(player):
		player.touch_direction = Vector2.ZERO
		player.touch_running = false
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or not is_instance_valid(player):
		return
	# 不让虚拟控制的触屏转鼠标事件点穿到游戏中的普通按钮。
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		# 返回按钮可能立即切换场景，需要在派发动作前消费事件。
		get_viewport().set_input_as_handled()
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not event.pressed or event.canceled:
			_release(event.index, point, event.canceled)
		elif gameplay_enabled and joystick_id < 0 and point.distance_to(joystick_center()) <= RADIUS + 30:
			joystick_id = event.index
			_move_stick(point)
		else:
			for kind in ["map", "return", "run", "action"]:
				if not button_rect(kind).has_point(point):
					continue
				if kind in ["run", "action"] and not gameplay_enabled:
					break
				if kind == "action" and (action_mode == "none" or not action_enabled):
					break
				if kind == "run":
					if run_id < 0:
						run_id = event.index
						player.touch_running = true
				else:
					_buttons[event.index] = kind
				break
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.index == joystick_id:
			_move_stick(point)
		elif event.index == run_id and not button_rect("run").grow(20).has_point(point):
			run_id = -1
			player.touch_running = false
		elif _buttons.has(event.index) and not button_rect(_buttons[event.index]).has_point(point):
			_buttons.erase(event.index)


func _move_stick(point: Vector2) -> void:
	stick = ((point - joystick_center()) / RADIUS).limit_length()
	var strength := stick.length()
	player.touch_direction = Vector2.ZERO if strength < DEAD_ZONE else stick.normalized() * inverse_lerp(DEAD_ZONE, 1.0, strength)
	queue_redraw()


func _release(index: int, point: Vector2, canceled: bool) -> void:
	if index == joystick_id:
		joystick_id = -1
		stick = Vector2.ZERO
		player.touch_direction = Vector2.ZERO
	if index == run_id:
		run_id = -1
		player.touch_running = false
	if _buttons.has(index):
		var kind: String = _buttons[index]
		_buttons.erase(index)
		if not canceled and button_rect(kind).has_point(point):
			match kind:
				"map": map_requested.emit()
				"return": return_requested.emit()
				"action":
					if gameplay_enabled and action_enabled:
						if action_mode == "interact": interact_requested.emit()
						elif action_mode == "attack": attack_requested.emit()
	queue_redraw()


func _draw() -> void:
	_draw_button("map", "地图" if gameplay_enabled else "收起地图", true)
	_draw_button("return", return_caption if gameplay_enabled else "关闭地图", true)
	if not gameplay_enabled:
		return
	var center := joystick_center()
	draw_circle(center, RADIUS + 13, Color("152d2bd9"))
	draw_arc(center, RADIUS + 13, 0, TAU, 64, Color("d8cfaa99"), 2, true)
	draw_circle(center, RADIUS, Color("617b624d"))
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_circle(center + direction * (RADIUS - 9), 3, Color("d8cfaa99"))
	draw_circle(center + stick * RADIUS * 0.7, 28, Color("ebdfb8e6"))
	_centered_text(Rect2(center.x - 90, center.y + 88, 180, 28), "移动", 19, Color("efe8cf"))
	_draw_button("run", "奔跑" if run_id < 0 else "奔跑中", true)
	if action_mode != "none":
		_draw_button("action", action_caption, action_enabled)


func _draw_button(kind: String, caption: String, enabled: bool) -> void:
	var rect := button_rect(kind)
	var held := (kind == "run" and run_id >= 0) or kind in _buttons.values()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("53745bf2") if held else Color("152d2be8")
	box.border_color = Color("d3c797") if enabled else Color("79867680")
	box.set_border_width_all(2)
	box.set_corner_radius_all(18)
	draw_style_box(box, rect)
	_centered_text(rect, caption, 21, Color("f2e8c7") if enabled else Color("8c9a88"))


func _centered_text(rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(FONT, Vector2(rect.get_center().x - width / 2, rect.get_center().y + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		cancel_touch()


func _exit_tree() -> void:
	cancel_touch()
