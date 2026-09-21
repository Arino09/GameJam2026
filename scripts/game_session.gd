extends Node
## 登录页、营地和地图共用的本地进度与偏好设置。

const SAVE_PATH := "user://progress.cfg"
const SETTINGS_PATH := "user://settings.cfg"
var progress_path := SAVE_PATH
const MAP_SCENE := "res://scenes/forest.tscn"
const DEFAULT_POSITION := Vector2(780.0 / 1536.0, 310.0 / 1024.0)
const CAMP_SCENE := "res://scenes/main_menu.tscn"
const MENU_SCENE := "res://scenes/login.tscn"

var has_save := false
var saved_position := DEFAULT_POSITION
var saved_facing := "down"
var saved_facing_left := false
var volume := 0.8
var fullscreen := false
var entering_game := false


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
	var save := ConfigFile.new()
	if save.load(progress_path) != OK:
		return
	var version: int = save.get_value("progress", "version", 0)
	if version not in [1, 2]:
		return
	var position: Variant = save.get_value("progress", "position")
	if not position is Vector2 or not position.is_finite():
		return
	if position.x < 0.0 or position.x > 1.0 or position.y < 0.0 or position.y > 1.0:
		return
	# 旧地图的坐标不适用于森林；旧进度从森林安全出生点衔接。
	saved_position = position if version == 2 else DEFAULT_POSITION
	saved_facing_left = save.get_value("progress", "facing_left", false) == true
	var facing: String = str(save.get_value("progress", "facing", "left" if saved_facing_left else "down"))
	saved_facing = facing if facing in ["up", "down", "left", "right"] else "down"
	has_save = true


func start_game(resume: bool) -> Error:
	if entering_game:
		return ERR_BUSY
	if resume and not has_save:
		return ERR_FILE_NOT_FOUND
	var previous_position := saved_position
	var previous_facing := saved_facing_left
	var previous_direction := saved_facing
	if not resume:
		saved_position = DEFAULT_POSITION
		saved_facing_left = false
		saved_facing = "down"
		var save_result := save_progress(saved_position, saved_facing)
		if save_result != OK:
			saved_position = previous_position
			saved_facing_left = previous_facing
			saved_facing = previous_direction
			return save_result
	entering_game = true
	var result := get_tree().change_scene_to_file(CAMP_SCENE)
	if result != OK:
		entering_game = false
		saved_position = previous_position
		saved_facing_left = previous_facing
		saved_facing = previous_direction
	return result


func save_progress(position: Vector2, facing: String) -> Error:
	saved_position = position.clamp(Vector2.ZERO, Vector2.ONE)
	saved_facing = facing
	saved_facing_left = facing == "left"
	var save := ConfigFile.new()
	save.set_value("progress", "version", 2)
	save.set_value("progress", "facing", saved_facing)
	save.set_value("progress", "position", saved_position)
	save.set_value("progress", "facing_left", saved_facing_left)
	var result := save.save(progress_path)
	has_save = result == OK
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
