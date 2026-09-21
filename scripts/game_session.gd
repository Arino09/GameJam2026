extends Node
## 登录页、营地和地图共用的本地进度与偏好设置。

const SAVE_PATH := "user://progress.cfg"
const SETTINGS_PATH := "user://settings.cfg"
var progress_path := SAVE_PATH
const MAP_SCENE := "res://scenes/forest.tscn"
const DEFAULT_POSITION := Vector2(780.0 / 1536.0, 310.0 / 1024.0)
const CAMP_SCENE := "res://scenes/main_menu.tscn"
const MENU_SCENE := "res://scenes/login.tscn"
const TUTORIAL_SCENES := ["res://scenes/tutorial_grass.tscn", "res://scenes/tutorial_cave.tscn"]
const TUTORIAL_SPAWNS := [Vector2(288, 288), Vector2(96, 320)]
const TUTORIAL_SIZE := Vector2(1344, 704)

var has_save := false
var saved_position := DEFAULT_POSITION
var saved_facing := "down"
var saved_facing_left := false
var volume := 0.8
var fullscreen := false
var entering_game := false
var tutorial_stage := 2 # 0: 草坪，1: 山洞，2: 已完成；旧存档直接衔接营地。
var tutorial_position := TUTORIAL_SPAWNS[0] / TUTORIAL_SIZE
var tutorial_facing := "down"
var tutorial_guide_spoken := false
var tutorial_chests := 0
var tutorial_boss_hits := 0


func _ready() -> void:
	load_progress()
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		var stored_volume: Variant = settings.get_value("audio", "volume", 0.8)
		if (stored_volume is float or stored_volume is int) and is_finite(float(stored_volume)):
			volume = clampf(float(stored_volume), 0.0, 1.0)
		fullscreen = settings.get_value("display", "fullscreen", false) == true
	apply_volume(volume)
	# 浏览器需要用户主动操作才能进入全屏。
	if fullscreen and not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func load_progress() -> void:
	has_save = false
	saved_position = DEFAULT_POSITION
	saved_facing = "down"
	saved_facing_left = false
	tutorial_stage = 2
	tutorial_position = TUTORIAL_SPAWNS[0] / TUTORIAL_SIZE
	tutorial_facing = "down"
	tutorial_guide_spoken = false
	tutorial_chests = 0
	tutorial_boss_hits = 0
	var save := ConfigFile.new()
	if save.load(progress_path) != OK:
		return
	var version: int = save.get_value("progress", "version", 0)
	if version not in [1, 2, 3]:
		return
	var position: Variant = save.get_value("progress", "position")
	if not position is Vector2 or not position.is_finite():
		return
	if position.x < 0.0 or position.x > 1.0 or position.y < 0.0 or position.y > 1.0:
		return
	# 旧地图的坐标不适用于森林；旧进度从森林安全出生点衔接。
	saved_position = position if version >= 2 else DEFAULT_POSITION
	saved_facing_left = save.get_value("progress", "facing_left", false) == true
	var facing: String = str(save.get_value("progress", "facing", "left" if saved_facing_left else "down"))
	saved_facing = facing if facing in ["up", "down", "left", "right"] else "down"
	if version == 3:
		var stage: Variant = save.get_value("tutorial", "stage", 0)
		tutorial_stage = stage if stage is int and stage in [0, 1, 2] else 0
		var point: Variant = save.get_value("tutorial", "position")
		var spawn: Vector2 = TUTORIAL_SPAWNS[mini(tutorial_stage, 1)] / TUTORIAL_SIZE
		tutorial_position = point if point is Vector2 and point.is_finite() and Rect2(Vector2.ZERO, Vector2.ONE).has_point(point) else spawn
		tutorial_facing = str(save.get_value("tutorial", "facing", "down"))
		if tutorial_facing not in ["up", "down", "left", "right"]:
			tutorial_facing = "down"
		tutorial_guide_spoken = save.get_value("tutorial", "guide_spoken", false) == true
		var chests: Variant = save.get_value("tutorial", "chests", 0)
		tutorial_chests = clampi(chests, 0, 7) if chests is int else 0
		var hits: Variant = save.get_value("tutorial", "boss_hits", 0)
		tutorial_boss_hits = clampi(hits, 0, 3) if hits is int else 0
	has_save = true


func start_game(resume: bool) -> Error:
	if entering_game:
		return ERR_BUSY
	if resume and not has_save:
		return ERR_FILE_NOT_FOUND
	var target: String = TUTORIAL_SCENES[tutorial_stage] if resume and tutorial_stage < 2 else CAMP_SCENE
	if not resume:
		target = TUTORIAL_SCENES[0]
	var scene := load(target) as PackedScene
	if scene == null:
		return ERR_FILE_NOT_FOUND
	if not resume:
		saved_position = DEFAULT_POSITION
		saved_facing_left = false
		saved_facing = "down"
		tutorial_stage = 0
		tutorial_position = TUTORIAL_SPAWNS[0] / TUTORIAL_SIZE
		tutorial_facing = "down"
		tutorial_guide_spoken = false
		tutorial_chests = 0
		tutorial_boss_hits = 0
		var save_result := save_progress(saved_position, saved_facing)
		if save_result != OK:
			load_progress()
			return save_result
	entering_game = true
	var result := get_tree().change_scene_to_packed(scene)
	if result != OK:
		entering_game = false
	return result


func save_progress(position: Vector2, facing: String) -> Error:
	saved_position = position.clamp(Vector2.ZERO, Vector2.ONE)
	saved_facing = facing
	saved_facing_left = facing == "left"
	var save := ConfigFile.new()
	save.set_value("progress", "version", 3)
	save.set_value("progress", "facing", saved_facing)
	save.set_value("progress", "position", saved_position)
	save.set_value("progress", "facing_left", saved_facing_left)
	save.set_value("tutorial", "stage", tutorial_stage)
	save.set_value("tutorial", "position", tutorial_position)
	save.set_value("tutorial", "facing", tutorial_facing)
	save.set_value("tutorial", "guide_spoken", tutorial_guide_spoken)
	save.set_value("tutorial", "chests", tutorial_chests)
	save.set_value("tutorial", "boss_hits", tutorial_boss_hits)
	var result := save.save(progress_path)
	has_save = result == OK
	return result


func save_tutorial(position: Vector2, facing: String) -> Error:
	tutorial_position = (position / TUTORIAL_SIZE).clamp(Vector2.ZERO, Vector2.ONE)
	tutorial_facing = facing
	return save_progress(saved_position, saved_facing)


func advance_tutorial() -> Error:
	if entering_game or tutorial_stage >= 2:
		return ERR_BUSY
	if tutorial_stage == 1 and tutorial_boss_hits < 3:
		return ERR_UNAUTHORIZED
	var next_stage := tutorial_stage + 1
	var target: String = TUTORIAL_SCENES[next_stage] if next_stage < 2 else CAMP_SCENE
	var scene := load(target) as PackedScene
	if scene == null:
		return ERR_FILE_NOT_FOUND
	var old_stage := tutorial_stage
	var old_position := tutorial_position
	var old_facing := tutorial_facing
	tutorial_stage = next_stage
	if next_stage < 2:
		tutorial_position = TUTORIAL_SPAWNS[next_stage] / TUTORIAL_SIZE
		tutorial_facing = "right"
	var result := save_progress(saved_position, saved_facing)
	if result == OK:
		entering_game = true
		result = get_tree().change_scene_to_packed(scene)
	if result != OK:
		entering_game = false
		tutorial_stage = old_stage
		tutorial_position = old_position
		tutorial_facing = old_facing
	return result


func apply_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_linear(0, volume)
	AudioServer.set_bus_mute(0, is_zero_approx(volume))


func save_settings() -> Error:
	fullscreen = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	var settings := ConfigFile.new()
	settings.set_value("audio", "volume", volume)
	settings.set_value("display", "fullscreen", fullscreen)
	return settings.save(SETTINGS_PATH)
