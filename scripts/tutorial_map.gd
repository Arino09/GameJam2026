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
@onready var mobile_controls: Control = $MobileControls/Controls
var transitioning := false
var map_open := false
var save_elapsed := 0.0
var attack_cooldown := 0.0
var attack_flash := 0.0
var message_time := 0.0


func _ready() -> void:
	InputProfile.use_gameplay_layout()
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
	mobile_controls.player = elf
	mobile_controls.action_mode = "interact" if map_index == 0 else "attack"
	mobile_controls.return_caption = "返回标题"
	mobile_controls.interact_requested.connect(interact)
	mobile_controls.attack_requested.connect(attack)
	mobile_controls.map_requested.connect(func(): set_map_open(not map_open))
	mobile_controls.return_requested.connect(func(): set_map_open(false) if map_open else return_to_title())
	InputProfile.changed.connect(_fit_controls)
	hud.resized.connect(_fit_controls)
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
	_fit_controls()
	if InputProfile.mobile:
		_show_message("左侧摇杆移动，按住奔跑加速；靠近物件后轻点右侧互动。" if map_index == 0 else "靠近石像，轻点攻击。击败它后，从右侧出口返回营地。", 6.0)
	else:
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
	action.visible = map_index == 0 and not map_open and not InputProfile.mobile
	action.disabled = target == null or map_open
	if target != null:
		action.text = "E  交谈" if target.kind == "guide" else "E  打开宝箱"
	else:
		action.text = "E  靠近后互动"
	hud.get_node("Attack").disabled = map_open or attack_cooldown > 0 or GameSession.tutorial_boss_hits >= 3
	hud.get_node("Attack").visible = map_index == 1 and not map_open and not InputProfile.mobile
	mobile_controls.action_enabled = target != null if map_index == 0 else not hud.get_node("Attack").disabled
	mobile_controls.action_caption = ("交谈" if target.kind == "guide" else "开箱") if target != null else ("靠近互动" if map_index == 0 else "攻击")
	if InputProfile.mobile:
		hud.get_node("MessagePanel").visible = message_time > 0 and not map_open
		hud.get_node("Message").visible = message_time > 0 and not map_open
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if transitioning or map_open or not exit_area.overlaps_body(elf):
		return
	if map_index == 1 and GameSession.tutorial_boss_hits < 3:
		_show_message("出口尚未开启：靠近新手 Boss，轻点攻击。" if InputProfile.mobile else "出口尚未开启：靠近新手 Boss，按空格 / J 攻击。")
		return
	transitioning = true
	var portal_kind: String = props.get_node("Portal").kind
	WwiseManager.play(["enter_" + portal_kind, "enter"], self)
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
		mobile_controls.set_gameplay_enabled(true)
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
		WwiseManager.play(["interact_" + target.kind, "interact"], self)
		_show_message("向导：下方有三个宝箱，靠近后轻点开箱。沿土路向右进入山洞。" if InputProfile.mobile else "向导：下方有三个宝箱，靠近按 E 打开。沿土路向右走，就能进入山洞。", 7.0)
	else:
		var index := int(target.get_meta("chest_index"))
		GameSession.tutorial_chests |= 1 << index
		target.activated = true
		target.caption = "已开启"
		WwiseManager.play(["interact_" + target.kind, "interact"], self)
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
	WwiseManager.play(["hit_" + boss.kind, "hit"], self)
	boss.flash = 0.2
	_update_boss()
	if GameSession.tutorial_boss_hits == 3:
		props.get_node("Portal").activated = true
		WwiseManager.play(["defeat_" + boss.kind, "defeat"], self)
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
			objective = ("靠近向导，轻点交谈 · 宝箱 %d/3 · 山洞在右侧 →" if InputProfile.mobile else "靠近向导，按 E 交谈  ·  宝箱 %d/3  ·  山洞在右侧 →") % count
		elif count < 3:
			objective = "探索路边宝箱 %d/3  ·  沿土路向右进入山洞 →" % count
		else:
			objective = "宝箱 3/3  ·  沿土路向右进入山洞 →"
	else:
		objective = ("靠近新手 Boss，轻点攻击 · %d/3" if InputProfile.mobile else "靠近新手 Boss，按空格 / J 攻击  ·  %d/3") % GameSession.tutorial_boss_hits
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
		mobile_controls.set_gameplay_enabled(not map_open)
		_show_message("暂时无法返回标题，请重试。")


func set_map_open(value: bool) -> void:
	if transitioning:
		return
	if map_open == value:
		return
	map_open = value
	WwiseManager.play("map_open" if value else "map_close", self)
	elf.movement_enabled = not value
	_cancel_touch()
	mobile_controls.set_gameplay_enabled(not value)
	var overview_zoom := minf(get_viewport_rect().size.x / MAP_SIZE.x, get_viewport_rect().size.y / MAP_SIZE.y) * 0.92
	camera.zoom = Vector2.ONE * overview_zoom if value else Vector2(2, 2)
	camera.position = MAP_SIZE / 2 - elf.position if value else Vector2(0, -35)
	hud.get_node("Overview").text = "M  关闭总览" if value else "M  地图总览"
	camera.reset_smoothing()
	_fit_controls()


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


func _cancel_touch() -> void:
	mobile_controls.cancel_touch()
	if transitioning:
		mobile_controls.set_gameplay_enabled(false)


func _place_hud(node_name: String, rect: Rect2, font_size := 0) -> void:
	var control: Control = hud.get_node(node_name)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size
	if font_size > 0:
		control.add_theme_font_size_override("font_size", font_size)


func _fit_controls() -> void:
	if not is_node_ready():
		return
	var mobile := InputProfile.mobile
	var viewport := hud.size
	hud.get_node("ReturnToTitle").visible = not mobile
	hud.get_node("Overview").visible = not mobile
	hud.get_node("Controls").visible = not mobile
	hud.get_node("Controls").text = "WASD / 方向键 · 移动    Shift · 奔跑    E · 互动    Esc · 标题"
	hud.get_node("Objective").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if mobile:
		_place_hud("TitlePanel", Rect2(20, 22, viewport.x - 350, 62))
		_place_hud("Title", Rect2(30, 34, viewport.x - 370, 34), 22)
		hud.get_node("Title").text = "草坪 · 新手教程" if map_index == 0 else "山洞 · 新手教程"
		_place_hud("Objective", Rect2(24, 96, viewport.x - 48, 52), 20)
		_place_hud("MessagePanel", Rect2(20, 156, viewport.x - 40, 72))
		_place_hud("Message", Rect2(32, 162, viewport.x - 64, 60), 18)
		_place_hud("SaveStatus", Rect2(24, 234, viewport.x - 48, 32), 18)
	else:
		_place_hud("TitlePanel", Rect2(24, 20, 826, 96))
		_place_hud("Title", Rect2(44, 29, 776, 37), 24)
		hud.get_node("Title").text = "01  /  新手教程 · 草坪" if map_index == 0 else "02  /  新手教程 · 山洞"
		_place_hud("Objective", Rect2(44, 74, 786, 29), 19)
		_place_hud("MessagePanel", Rect2(24, viewport.y - 134, 852, 110))
		_place_hud("Message", Rect2(44, viewport.y - 127, 810, 59), 19)
		_place_hud("SaveStatus", Rect2(44, 122, 786, 34), 18)
		hud.get_node("MessagePanel").show()
		hud.get_node("Message").show()
	_refresh_objective()


func _draw() -> void:
	if attack_flash > 0 and not map_open:
		draw_arc(elf.position + Vector2(0, -25), 64, -PI * 0.8, PI * 0.5, 18, Color("fff0bc"), 5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(elf):
		if not transitioning:
			_save_progress()
		_cancel_touch()
		for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"sprint"]:
			Input.action_release(action)
