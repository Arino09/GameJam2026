extends Node2D
## 草坪、山洞共享教程逻辑；地形、出生点与物件分别保存在场景中。

const MAP_SIZE := Vector2(1344, 704)
const INTERACT_DISTANCE := 96.0
const ATTACK_DISTANCE := 120.0
@export_range(0, 1) var map_index := 0
@onready var elf: CharacterBody2D = $Elf
@onready var camera: Camera2D = $Elf/Camera2D
@onready var props: Node2D = $Props
@onready var hud: Control = $HUD/Interface
@onready var exit_area: Area2D = $Exit
var transitioning := false
var map_open := false
var save_elapsed := 0.0
var attack_cooldown := 0.0
var attack_flash := 0.0
var message_time := 0.0
var touch_id := -1
var touch_origin := Vector2.ZERO
var touch_end := Vector2.ZERO


func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280, 800)
	GameSession.entering_game = false
	elf.position = $Spawn.position
	if GameSession.has_save and GameSession.tutorial_stage == map_index:
		elf.position = GameSession.tutorial_position * MAP_SIZE
		elf.facing = GameSession.tutorial_facing
	# 包含边界和墙体检查，异常坐标只回退到本图安全出生点。
	if elf.test_move(elf.global_transform, Vector2.ZERO):
		elf.position = $Spawn.position
	hud.get_node("Title").text = "01  /  新手教程 · 草坪" if map_index == 0 else "02  /  新手教程 · 山洞"
	hud.get_node("ReturnToTitle").pressed.connect(return_to_title)
	hud.get_node("Overview").pressed.connect(func(): set_map_open(not map_open))
	hud.get_node("Action").pressed.connect(interact)
	hud.get_node("Attack").pressed.connect(attack)
	hud.get_node("Attack").visible = map_index == 1
	if map_index == 0:
		props.get_node("Guide").activated = GameSession.tutorial_guide_spoken
		for i in range(3):
			var chest: Node2D = props.get_node("Chest%d" % (i + 1))
			chest.activated = (GameSession.tutorial_chests & (1 << i)) != 0
			if chest.activated:
				chest.caption = "已开启"
	else:
		_update_boss()
	props.get_node("Portal").activated = map_index == 0 or GameSession.tutorial_boss_hits == 3
	camera.reset_smoothing()
	_refresh_objective()
	_show_message("WASD / 方向键移动，Shift 奔跑。靠近物件后按 E 互动。" if map_index == 0 else "靠近石像，按空格 / J 攻击。击败它后，从右侧出口返回营地。", 6.0)


func _process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	attack_flash = maxf(0.0, attack_flash - delta)
	message_time = maxf(0.0, message_time - delta)
	if message_time <= 0:
		hud.get_node("Message").text = ""
	if transitioning:
		return
	save_elapsed += delta
	if save_elapsed >= 3.0:
		save_elapsed = 0.0
		_save_progress()
	var target := _nearby_interaction()
	var action: Button = hud.get_node("Action")
	action.visible = map_index == 0 and not map_open
	action.disabled = target == null or map_open
	if target != null:
		action.text = "E  交谈" if target.kind == "guide" else "E  打开宝箱"
	else:
		action.text = "E  靠近后互动"
	hud.get_node("Attack").disabled = map_open or attack_cooldown > 0 or GameSession.tutorial_boss_hits >= 3
	hud.get_node("Attack").visible = map_index == 1 and not map_open
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if transitioning or map_open or not exit_area.overlaps_body(elf):
		return
	if map_index == 1 and GameSession.tutorial_boss_hits < 3:
		_show_message("出口尚未开启：靠近新手 Boss，按空格 / J 攻击。")
		return
	transitioning = true
	elf.movement_enabled = false
	_cancel_touch()
	call_deferred("_advance")


func _advance() -> void:
	# F6 单独运行场景也走同一条教程完成路径。
	GameSession.tutorial_stage = map_index
	var result := _save_progress()
	if result == OK:
		result = GameSession.advance_tutorial()
	if result != OK:
		transitioning = false
		elf.movement_enabled = true
		# 离开触发区，避免每一帧重试导致报错刷屏。
		elf.position.x = exit_area.position.x - 110
		_show_message("暂时无法切换地图或保存进度，请重试。", 8.0)


func _nearby_interaction() -> Node2D:
	if map_index != 0:
		return null
	var nearest: Node2D
	var distance := INTERACT_DISTANCE
	for prop: Node2D in props.get_children():
		if prop.kind not in ["guide", "chest"] or (prop.kind == "chest" and prop.activated):
			continue
		var current := elf.position.distance_to(prop.position)
		if current < distance:
			nearest = prop
			distance = current
	return nearest


func interact() -> void:
	if transitioning or map_open:
		return
	var target := _nearby_interaction()
	if target == null:
		return
	if target.kind == "guide":
		GameSession.tutorial_guide_spoken = true
		target.activated = true
		_show_message("向导：下方有三个宝箱，靠近按 E 打开。沿土路向右走，就能进入山洞。", 7.0)
	else:
		var index := int(target.get_meta("chest_index"))
		GameSession.tutorial_chests |= 1 << index
		target.activated = true
		target.caption = "已开启"
		_show_message("宝箱已开启。沿土路向右，前往山洞。", 4.0)
	_refresh_objective()
	_save_progress()


func attack() -> void:
	if transitioning or map_open or map_index != 1 or attack_cooldown > 0 or GameSession.tutorial_boss_hits >= 3:
		return
	attack_cooldown = 0.45
	attack_flash = 0.18
	var boss: Node2D = props.get_node("Boss")
	if elf.position.distance_to(boss.position) > ATTACK_DISTANCE:
		_show_message("距离太远，靠近新手 Boss 再攻击。")
		return
	GameSession.tutorial_boss_hits += 1
	boss.flash = 0.2
	_update_boss()
	if GameSession.tutorial_boss_hits == 3:
		props.get_node("Portal").activated = true
		_show_message("新手 Boss 已击败！继续向右，从发光出口返回营地。", 6.0)
	_refresh_objective()
	_save_progress()


func _update_boss() -> void:
	var boss: Node2D = props.get_node("Boss")
	boss.hits = GameSession.tutorial_boss_hits
	boss.activated = boss.hits >= 3
	boss.caption = "已击败" if boss.activated else "新手 Boss"


func _refresh_objective() -> void:
	var objective := ""
	if map_index == 0:
		var count := 0
		for i in range(3):
			if GameSession.tutorial_chests & (1 << i):
				count += 1
		if not GameSession.tutorial_guide_spoken:
			objective = "靠近向导，按 E 交谈  ·  宝箱 %d/3  ·  山洞在右侧 →" % count
		elif count < 3:
			objective = "探索路边宝箱 %d/3  ·  沿土路向右进入山洞 →" % count
		else:
			objective = "宝箱 3/3  ·  沿土路向右进入山洞 →"
	else:
		objective = "靠近新手 Boss，按空格 / J 攻击  ·  %d/3" % GameSession.tutorial_boss_hits
		if GameSession.tutorial_boss_hits == 3:
			objective = "教程完成  ·  从右侧出口返回营地 →"
	hud.get_node("Objective").text = objective


func _show_message(text: String, duration := 3.0) -> void:
	hud.get_node("Message").text = text
	message_time = duration


func _save_progress() -> Error:
	if GameSession.tutorial_stage != map_index:
		return OK # 单独预览已完成的地图时不覆盖现有教程阶段。
	var result := GameSession.save_tutorial(elf.position, elf.facing)
	hud.get_node("SaveStatus").text = "进度保存失败，请重试" if result != OK else ""
	return result


func return_to_title() -> void:
	if transitioning or _save_progress() != OK:
		return
	transitioning = true
	elf.movement_enabled = false
	_cancel_touch()
	if get_tree().change_scene_to_file(GameSession.MENU_SCENE) != OK:
		transitioning = false
		elf.movement_enabled = not map_open
		_show_message("暂时无法返回标题，请重试。")


func set_map_open(value: bool) -> void:
	if transitioning:
		return
	map_open = value
	elf.movement_enabled = not value
	_cancel_touch()
	camera.zoom = Vector2(0.75, 0.75) if value else Vector2(2, 2)
	camera.position = MAP_SIZE / 2 - elf.position if value else Vector2(0, -35)
	hud.get_node("Overview").text = "M  关闭总览" if value else "M  地图总览"
	camera.reset_smoothing()


func _unhandled_key_input(event: InputEvent) -> void:
	var input_viewport := get_viewport()
	if event.is_action_pressed(&"ui_cancel"):
		if map_open:
			set_map_open(false)
		else:
			return_to_title()
	elif event.is_action_pressed(&"world_map"):
		set_map_open(not map_open)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				interact()
			KEY_SPACE, KEY_J:
				attack()
			_:
				return
	else:
		return
	input_viewport.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if transitioning or map_open:
		return
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x < 520 and event.position.y > 140 and touch_id < 0:
			touch_id = event.index
			touch_origin = event.position
			touch_end = event.position


func _input(event: InputEvent) -> void:
	# 已开始的拖动始终接收抬手事件，包括手指最后落在 HUD 按钮上。
	if touch_id < 0:
		return
	if event is InputEventScreenTouch and not event.pressed and event.index == touch_id:
		_cancel_touch()
	if event is InputEventScreenDrag and event.index == touch_id:
		touch_end = event.position
		elf.touch_direction = (touch_end - touch_origin) / 64.0


func _cancel_touch() -> void:
	touch_id = -1
	elf.touch_direction = Vector2.ZERO


func _draw() -> void:
	if attack_flash > 0 and not map_open:
		draw_arc(elf.position + Vector2(0, -25), 64, -PI * 0.8, PI * 0.5, 18, Color("fff0bc"), 5)
	if touch_id >= 0:
		var transform := get_canvas_transform().affine_inverse()
		var origin := transform * touch_origin
		var end := transform * touch_end
		draw_circle(origin, 32, Color(0.1, 0.2, 0.2, 0.4))
		draw_circle(origin + (end - origin).limit_length(25), 10, Color("e3ddbaaa"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(elf):
		if not transitioning:
			_save_progress()
		_cancel_touch()
		for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"sprint"]:
			Input.action_release(action)
