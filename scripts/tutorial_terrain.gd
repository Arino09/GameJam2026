@tool
extends Node2D
## 每个字符对应需求表的一格（64 世界像素）；两张地图保留原始格位。

const CELL := 64
@export var cave := false
@export var rows: PackedStringArray = []:
	set(value):
		rows = value
		queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var obstacles := StaticBody2D.new()
	obstacles.name = "Obstacles"
	add_child(obstacles)
	for y in rows.size():
		var x := 0
		while x < rows[y].length():
			if rows[y][x] not in ["#", "T", "t"]:
				x += 1
				continue
			var start := x
			while x < rows[y].length() and rows[y][x] in ["#", "T", "t"]:
				x += 1
			_block(obstacles, Rect2(start * CELL, y * CELL, (x - start) * CELL, CELL))
	# 出入口同样有外边界，玩家不能从地图边缘走出场景。
	_block(obstacles, Rect2(-32, -32, 1408, 32))
	_block(obstacles, Rect2(-32, 704, 1408, 32))
	_block(obstacles, Rect2(-32, 0, 32, 704))
	_block(obstacles, Rect2(1344, 0, 32, 704))


func _block(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)


func _draw() -> void:
	for y in rows.size():
		for x in rows[y].length():
			var origin := Vector2(x, y) * CELL
			var tile := rows[y][x]
			var salt := x * 13 + y * 31
			var ground := Color("444d58") if cave else Color("76955b")
			if tile == ".":
				ground = Color("917c64") if cave else Color("c3ac7d")
			elif tile == "P":
				ground = Color("c7b78a")
			draw_rect(Rect2(origin, Vector2(CELL, CELL)), ground.lightened((salt % 3) * 0.015))
			for i in range(7):
				var p := origin + Vector2((salt * 7 + i * 19) % 58 + 3, (salt * 11 + i * 23) % 58 + 3)
				if not cave and tile == "g":
					draw_line(p, p + Vector2(-2, -4), Color("516f43"), 2)
					draw_line(p, p + Vector2(3, -5), Color("98b778"), 2)
				elif tile != "#":
					draw_rect(Rect2(p, Vector2(4, 2)), ground.darkened(0.13))
			if tile == "#":
				if cave:
					_stone_wall(origin, salt)
				else:
					_tree(origin, salt)
			elif tile == "t":
				_tree(origin, salt)
			elif tile == "T":
				draw_rect(Rect2(origin, Vector2(CELL, CELL)), Color("5e4331"))
				for i in range(5):
					var p := origin + Vector2(8 + i * 12, (salt + i * 7) % 18)
					draw_line(p, p + Vector2(-3, 40), Color("936a42"), 3)
			elif cave and tile == "s":
				draw_line(origin + Vector2(2, 30), origin + Vector2(59, 30), Color("373f48"), 2)
				draw_line(origin + Vector2(24 + salt % 12, 0), origin + Vector2(24 + salt % 12, 30), Color("373f48"), 2)
				if salt % 9 == 0:
					draw_colored_polygon(PackedVector2Array([origin + Vector2(42, 41), origin + Vector2(46, 25), origin + Vector2(52, 42)]), Color("90b6b0"))
	# 土路上下沿用短石块收边，保持两行宽的直线路径。
	for x in range(3, 19):
		var top := 4 * CELL
		draw_rect(Rect2(x * CELL + 4, top, 12, 3), Color("d6c598") if not cave else Color("a9977a"))
		draw_rect(Rect2(x * CELL + 28, (6 if not cave else 7) * CELL - 3, 10, 3), Color("8c805f"))


func _tree(p: Vector2, salt: int) -> void:
	draw_rect(Rect2(p, Vector2(64, 64)), Color("243d32"))
	draw_rect(Rect2(p + Vector2(26, 29), Vector2(13, 35)), Color("705539"))
	draw_rect(Rect2(p + Vector2(30, 29), Vector2(4, 34)), Color("ac8453"))
	var crown := PackedVector2Array([Vector2(4, 20), Vector2(16, 20), Vector2(16, 10), Vector2(28, 10), Vector2(28, 3), Vector2(45, 3), Vector2(45, 13), Vector2(57, 13), Vector2(57, 28), Vector2(63, 28), Vector2(63, 45), Vector2(48, 45), Vector2(48, 53), Vector2(15, 53), Vector2(15, 44), Vector2(4, 44)])
	for i in crown.size():
		crown[i] += p
	draw_colored_polygon(crown, Color("365c41").lightened((salt % 3) * 0.03))
	draw_rect(Rect2(p + Vector2(19, 15), Vector2(24, 9)), Color("568154"))
	draw_rect(Rect2(p + Vector2(11, 28), Vector2(14, 8)), Color("52794d"))
	draw_rect(Rect2(p + Vector2(40, 34), Vector2(15, 7)), Color("2c4c37"))


func _stone_wall(p: Vector2, salt: int) -> void:
	draw_rect(Rect2(p, Vector2(64, 64)), Color("232b35"))
	for i in range(2):
		var offset := Vector2(3 + (salt + i) % 4, i * 30 + 3)
		draw_rect(Rect2(p + offset, Vector2(56, 26)), Color("56616a").darkened((salt % 3) * 0.06))
		draw_rect(Rect2(p + offset, Vector2(54, 3)), Color("75818a"))
		draw_rect(Rect2(p + offset + Vector2(0, 23), Vector2(55, 3)), Color("323c48"))
	if salt % 7 == 0:
		draw_rect(Rect2(p + Vector2(14, 15), Vector2(18, 4)), Color("709189"))
