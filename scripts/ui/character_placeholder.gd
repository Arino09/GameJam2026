@tool
extends Control
## 后续用角色美术替换此占位图形，保留装备入口的点击区域。


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size.x / 2.0
	var fill := Color("d4ddcf")
	var line := Color("9cab9b")
	draw_circle(Vector2(center, 50), 30, fill)
	draw_arc(Vector2(center, 50), 30, 0, TAU, 48, line, 1.5, true)
	var body := PackedVector2Array([
		Vector2(center - 39, 94), Vector2(center + 39, 94),
		Vector2(center + 54, 172), Vector2(center + 25, 177),
		Vector2(center + 22, 229), Vector2(center + 4, 229),
		Vector2(center, 180), Vector2(center - 4, 229),
		Vector2(center - 22, 229), Vector2(center - 25, 177),
		Vector2(center - 54, 172), Vector2(center - 39, 94),
	])
	draw_colored_polygon(body, fill)
	draw_polyline(body, line, 1.5, true)
