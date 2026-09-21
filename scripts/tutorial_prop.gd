@tool
extends Node2D
## 可替换的教程占位美术，脚下锚点与角色一致。

@export_enum("guide", "chest", "boss", "portal") var kind := "chest"
@export var caption := "":
	set(value):
		caption = value
		queue_redraw()
var activated := false
var hits := 0
var flash := 0.0
const FONT = preload("res://assets/fonts/ui_chinese.ttf")


func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 22 if kind != "boss" else 46, Color(0.04, 0.09, 0.1, 0.3))
	draw_set_transform(Vector2.ZERO)
	match kind:
		"guide":
			draw_rect(Rect2(-10, -34, 20, 31), Color("d7b76e"))
			draw_rect(Rect2(-7, -49, 14, 15), Color("e9c599"))
			draw_rect(Rect2(-12, -55, 24, 10), Color("446e63"))
			draw_rect(Rect2(-18, -47, 36, 5), Color("668c72"))
			draw_line(Vector2(18, -42), Vector2(18, 1), Color("805a39"), 4)
			draw_circle(Vector2(18, -46), 5, Color("c1e1b4"))
			draw_rect(Rect2(-9, -4, 7, 5), Color("394d43"))
			draw_rect(Rect2(3, -4, 7, 5), Color("394d43"))
		"chest":
			draw_rect(Rect2(-19, -25, 38, 25), Color("62462e"))
			draw_rect(Rect2(-17, -23, 34, 20), Color("b27f40"))
			draw_rect(Rect2(-19, -31 if activated else -29, 38, 9), Color("d8af5e"))
			if activated:
				draw_rect(Rect2(-16, -22, 32, 7), Color("302d2b"))
			else:
				draw_rect(Rect2(-4, -19, 8, 8), Color("f5dd8d"))
			for x in [-14, 10]:
				draw_rect(Rect2(x, -21, 4, 19), Color("dab965"))
		"boss":
			if activated:
				draw_rect(Rect2(-30, -17, 60, 17), Color("586775"))
				draw_circle(Vector2(0, -18), 6, Color("afd8cd"))
			else:
				var body := Color("72828b") if flash <= 0 else Color("f1e3b6")
				draw_rect(Rect2(-32, -67, 64, 50), body)
				draw_rect(Rect2(-22, -91, 44, 27), body.lightened(0.1))
				draw_rect(Rect2(-47, -61, 14, 42), body.darkened(0.15))
				draw_rect(Rect2(33, -61, 14, 42), body.darkened(0.15))
				draw_rect(Rect2(-26, -18, 19, 20), body.darkened(0.2))
				draw_rect(Rect2(7, -18, 19, 20), body.darkened(0.2))
				for x in [-13, 6]:
					draw_rect(Rect2(x, -80, 7, 5), Color("ffe0a1"))
				draw_colored_polygon(PackedVector2Array([Vector2(0, -58), Vector2(10, -43), Vector2(0, -30), Vector2(-10, -43)]), Color("a9ded0"))
				draw_rect(Rect2(-35, -108, 70, 5), Color("28313b"))
				draw_rect(Rect2(-35, -108, (3 - hits) * 70.0 / 3, 5), Color("dec28b"))
		"portal":
			draw_rect(Rect2(-26, -65, 52, 68), Color("353e40"))
			draw_rect(Rect2(-33, -62, 10, 66), Color("8e9690"))
			draw_rect(Rect2(23, -62, 10, 66), Color("8e9690"))
			draw_rect(Rect2(-28, -72, 56, 12), Color("a9ada0"))
			draw_rect(Rect2(-20, -57, 40, 56), Color("d8d5a0") if activated else Color("273837"))
			draw_line(Vector2(-11, -29), Vector2(10, -29), Color("f1e7bb"), 3)
			draw_line(Vector2(3, -36), Vector2(10, -29), Color("f1e7bb"), 3)
			draw_line(Vector2(3, -22), Vector2(10, -29), Color("f1e7bb"), 3)
	var label_y := 22.0
	var width := FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_rect(Rect2(-width / 2 - 6, label_y - 14, width + 12, 21), Color("243c38dd"))
	draw_string(FONT, Vector2(-width / 2, label_y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f4ead1"))
