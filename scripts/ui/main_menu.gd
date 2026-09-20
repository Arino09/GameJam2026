extends Control
## 营地入口遵循「程序美术」表 B7 草图，后续可接入美术与系统数据。

const INK := Color("293e38")
const MUTED := Color("77857b")
const PAPER := Color("f4f2eb")

@onready var navigation: Control = $Navigation
@onready var overlay: Control = $SystemOverlay
@onready var panel_title: Label = %PanelTitle
@onready var panel_content: Control = %PanelContent
@onready var close_button: Button = %CloseButton
@onready var volume: HSlider = %Volume
@onready var volume_value: Label = %VolumeValue
var active_system: StringName = &""
var return_focus: Button
var transitioning := false


func _ready() -> void:
	GameSession.entering_game = false
	_apply_theme()
	for button in get_tree().get_nodes_in_group("camp_entry"):
		button.pressed.connect(_open_system.bind(button.get_meta("system"), button))
	close_button.pressed.connect(_close_system)
	$SystemOverlay/Backdrop.pressed.connect(_close_system)
	$Navigation/Explore.pressed.connect(_explore)
	$Navigation/ReturnToLogin.pressed.connect(_return_to_login)
	volume.value = GameSession.volume * 100.0
	_update_volume_label(volume.value)
	volume.value_changed.connect(_set_volume)
	resized.connect(queue_redraw)
	$Navigation/Explore.grab_focus()


func _style(fill: Color, border: Color, width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


func _apply_theme() -> void:
	var menu_theme := Theme.new()
	menu_theme.default_font = preload("res://assets/fonts/ui_chinese.ttf")
	menu_theme.default_font_size = 18
	menu_theme.set_color("font_color", "Label", INK)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		menu_theme.set_color(state, "Button", INK)
	menu_theme.set_stylebox("normal", "Button", _style(Color("faf9f4"), Color("c7cec4")))
	menu_theme.set_stylebox("hover", "Button", _style(Color("e7ece1"), MUTED))
	menu_theme.set_stylebox("pressed", "Button", _style(Color("d5dfd0"), INK))
	menu_theme.set_stylebox("disabled", "Button", _style(Color("faf9f4"), Color("c7cec4")))
	menu_theme.set_color("font_disabled_color", "Button", MUTED)
	menu_theme.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), Color("71937d"), 2))
	menu_theme.set_stylebox("panel", "PanelContainer", _style(PAPER, Color("b8c4b8")))
	theme = menu_theme
	var explore: Button = $Navigation/Explore
	for state in ["normal", "hover", "pressed"]:
		var fill := INK if state == "normal" else Color("426253")
		explore.add_theme_stylebox_override(state, _style(fill, fill))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		explore.add_theme_color_override(state, PAPER)
	for slots in [%BackpackSlots, %EquipmentSlots]:
		for slot in slots.get_children():
			slot.add_theme_stylebox_override("panel", _style(Color("e9ede3"), Color("d1d9cd")))


func _open_system(system: StringName, source: Button) -> void:
	if transitioning:
		return
	var selected := panel_content.get_node_or_null(NodePath(system))
	if selected == null:
		return
	active_system = system
	return_focus = source
	panel_title.text = source.get_meta("title", source.text)
	for page in panel_content.get_children():
		page.visible = page == selected
	# 弹窗打开时，同时阻止键盘和指针对底层按钮的操作。
	for button in navigation.find_children("*", "Button", true, false):
		button.disabled = true
	overlay.show()
	close_button.grab_focus()


func _close_system() -> void:
	if active_system == &"Settings" and GameSession.save_settings() != OK:
		%SceneStatus.text = "音量已应用，但无法保存到本地。"
	overlay.hide()
	active_system = &""
	for button in navigation.find_children("*", "Button", true, false):
		button.disabled = false
	if is_instance_valid(return_focus):
		return_focus.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and overlay.visible:
		_close_system()
		get_viewport().set_input_as_handled()


func _explore() -> void:
	if transitioning or overlay.visible:
		return
	transitioning = true
	var error := get_tree().change_scene_to_file(GameSession.MAP_SCENE)
	if error != OK:
		transitioning = false
		%SceneStatus.text = "暂时无法出发，请重试。"


func _return_to_login() -> void:
	if transitioning or overlay.visible:
		return
	transitioning = true
	if get_tree().change_scene_to_file(GameSession.MENU_SCENE) != OK:
		transitioning = false
		%SceneStatus.text = "暂时无法返回，请重试。"


func _set_volume(value: float) -> void:
	GameSession.apply_volume(value / 100.0)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	volume_value.text = "%d%%" % roundi(value)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var ground := size.y * 0.73
	draw_line(Vector2(40, 108), Vector2(size.x - 40, 108), Color("d2d8ce"), 1.0)
	draw_line(Vector2(40, ground), Vector2(size.x - 40, ground), Color("c4cec1"), 1.0)
	draw_line(Vector2(40, size.y - 128), Vector2(size.x - 40, size.y - 128), Color("d2d8ce"), 1.0)
	var center := Vector2(size.x * 0.57, ground)
	var ellipse := PackedVector2Array()
	for i in range(64):
		var angle := TAU * i / 64.0
		ellipse.append(center + Vector2(cos(angle) * 110, sin(angle) * 12))
	draw_colored_polygon(ellipse, Color("e3e7dc"))
