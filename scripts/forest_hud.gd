extends Control
## Compact exploration HUD and an optional full-map view, no animation preview UI.

const INK := Color("142c2be8")
const EDGE := Color("8b9d7880")
const CREAM := Color("efebd5")
var world: Node2D
var touch_id := -1
var touch_origin := Vector2.ZERO
var touch_end := Vector2.ZERO
var font: Font


func _ready() -> void:
	font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if not is_instance_valid(world):
		return
	var viewport := size
	# Restrained translucent title block, with map art visible across the screen.
	_panel(Rect2(16, 16, 148, 53))
	draw_rect(Rect2(16, 16, 2, 53), Color("cabd8b"))
	draw_string(font, Vector2(29, 37), "月隐林地", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, CREAM)
	draw_string(font, Vector2(30, 57), "M O O N V E I L", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("b4c6aa"))
	_panel(Rect2(viewport.x - 114, 16, 98, 29))
	draw_string(font, Vector2(viewport.x - 102, 35), "M  ·  地图", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CREAM)
	var hint := "WASD / 方向键 移动    Shift 奔跑    M 地图"
	if DisplayServer.is_touchscreen_available():
		hint = "拖动左侧屏幕移动    轻触右上角查看地图"
	var width := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 26
	_panel(Rect2((viewport.x - width) / 2, viewport.y - 36, width, 23))
	draw_string(font, Vector2((viewport.x - width) / 2 + 13, viewport.y - 20), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c8d2be"))
	if touch_id >= 0 and not world.map_open:
		draw_circle(touch_origin, 28, Color(0.08, 0.2, 0.18, 0.45))
		draw_arc(touch_origin, 28, 0, TAU, 24, Color(0.85, 0.9, 0.8, 0.45), 1)
		draw_circle(touch_origin + (touch_end - touch_origin).limit_length(24), 10, Color(0.85, 0.9, 0.8, 0.7))
	if world.map_open:
		_draw_map(viewport)


func _draw_map(viewport: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport), Color(0.025, 0.06, 0.055, 0.91))
	var available := viewport - Vector2(64, 108)
	var scale_factor: float = minf(available.x / world.MAP_SIZE.x, available.y / world.MAP_SIZE.y)
	var map_size: Vector2 = world.MAP_SIZE * scale_factor
	var map_rect := Rect2((viewport - map_size) / 2 + Vector2(0, 4), map_size)
	_panel(map_rect.grow(5))
	draw_texture_rect(world.MAP_TEXTURE, map_rect, false)
	var marker: Vector2 = map_rect.position + world.elf.position * scale_factor
	draw_circle(marker, 5, Color("292337"))
	draw_circle(marker, 3, Color("f5dfac"))
	draw_arc(marker, 8 + sin(world.elapsed * 3), 0, TAU, 24, Color("fff0bd"), 1)
	draw_string(font, Vector2(map_rect.position.x, map_rect.position.y - 19), "月隐林地  /  地图", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, CREAM)
	draw_string(font, Vector2(map_rect.position.x, map_rect.end.y + 27), "金色标记 · 你的位置      M / Esc / 点击关闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c8d2be"))


func _panel(rect: Rect2) -> void:
	draw_rect(rect, INK)
	draw_rect(rect, EDGE, false, 1)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(world):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pointer: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if world.map_open or Rect2(size.x - 114, 16, 98, 29).has_point(pointer):
			world.set_map_open(not world.map_open)
			get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		var pointer: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed and world.map_open:
			world.set_map_open(false)
			get_viewport().set_input_as_handled()
		elif event.pressed and Rect2(size.x - 114, 16, 98, 29).has_point(pointer):
			world.set_map_open(true)
			get_viewport().set_input_as_handled()
		elif event.pressed and pointer.x < size.x / 2 and touch_id < 0:
			touch_id = event.index
			touch_origin = pointer
			touch_end = pointer
		elif not event.pressed and event.index == touch_id:
			cancel_touch()
	if event is InputEventScreenDrag and event.index == touch_id:
		touch_end = get_global_transform_with_canvas().affine_inverse() * event.position
		world.elf.touch_direction = (touch_end - touch_origin) / 28.0


func cancel_touch() -> void:
	touch_id = -1
	if is_instance_valid(world):
		world.elf.touch_direction = Vector2.ZERO
