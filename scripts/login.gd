extends Control
## 四个入口对应「程序美术」需求表中的登录页草图。

@export var game_title := "游戏名称"

@onready var start_button: Button = %StartButton
@onready var continue_button: Button = %ContinueButton
@onready var settings_button: Button = %SettingsButton
@onready var exit_button: Button = %ExitButton
@onready var modal: Control = %Modal
@onready var modal_title: Label = %ModalTitle
@onready var modal_text: Label = %ModalText
@onready var settings_controls: VBoxContainer = %SettingsControls
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue
@onready var fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton

var modal_kind := ""
var previous_focus: Control
var changing_scene := false


func _ready() -> void:
	InputProfile.use_menu_layout()
	%GameTitle.text = game_title
	GameSession.entering_game = false
	GameSession.load_progress()
	continue_button.disabled = not GameSession.has_save
	%SaveStatus.text = "旅途已记录，随时继续" if GameSession.has_save else "尚无旅途记录 · 从这里开始"
	start_button.pressed.connect(_on_start_pressed)
	continue_button.pressed.connect(func(): _enter_game(true))
	settings_button.pressed.connect(func(): _open_modal("settings"))
	exit_button.pressed.connect(func(): _open_modal("exit"))
	cancel_button.pressed.connect(_close_modal)
	confirm_button.pressed.connect(_confirm_modal)
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	resized.connect(_fit_layout)
	_fit_layout()
	if GameSession.has_save:
		continue_button.grab_focus()
	else:
		start_button.grab_focus()
	# 使用短暂的淡入过渡，避免交互内容在指针下方移动。
	%Menu.modulate.a = 0.0
	create_tween().tween_property(%Menu, "modulate:a", 1.0, 0.3)


func _fit_layout() -> void:
	if changing_scene:
		return
	# 视口由 InputProfile 统一管理，这里只调整界面内部排版。
	var available_width := maxf(size.x, 160.0)
	var compact := size.y < 600.0
	%Menu.custom_minimum_size.x = minf(470.0, available_width - 64.0)
	%GameTitle.add_theme_font_size_override("font_size", 36 if available_width < 560.0 or compact else 60)
	%GameTitle.custom_minimum_size.y = 60.0 if compact else 85.0
	%Menu.get_node("Emblem").visible = not compact
	%Menu.get_node("Eyebrow").visible = not compact
	%Menu.get_node("Subtitle").visible = not compact
	%Menu.get_node("Spacer").custom_minimum_size.y = 12.0 if compact else 32.0
	%Menu.get_node("Buttons").add_theme_constant_override("separation", 8 if compact else 12)
	%SaveStatus.custom_minimum_size.y = 28.0 if compact else 42.0
	for button: Button in [start_button, continue_button, settings_button, exit_button]:
		button.custom_minimum_size.x = minf(330.0, available_width - 64.0)
		button.custom_minimum_size.y = 44.0 if compact else 58.0
	%ModalPanel.custom_minimum_size.x = minf(470.0, available_width - 32.0)
	%ModalPanel.get_node("Padding/Content").add_theme_constant_override("separation", 10 if compact else 22)
	for edge in ["left", "top", "right", "bottom"]:
		%ModalPanel.get_node("Padding").add_theme_constant_override("margin_" + edge, 4 if compact else 18)
	settings_controls.add_theme_constant_override("separation", 10 if compact else 18)
	settings_controls.get_node("Hint").visible = not compact
	modal_title.add_theme_font_size_override("font_size", 24 if compact else 30)
	$Footer.visible = not compact
	$Footer.text = "2026 · 游戏创作" if available_width < 560.0 else "2026 · 游戏创作     /     每一次出发，都有新的发现"


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal.visible:
			_close_modal()
		else:
			_open_modal("exit")
		get_viewport().set_input_as_handled()


func _on_start_pressed() -> void:
	if GameSession.has_save:
		_open_modal("new_game")
	else:
		_enter_game(false)


func _enter_game(resume: bool) -> void:
	if changing_scene:
		return
	changing_scene = true
	var result := GameSession.start_game(resume)
	if result != OK:
		changing_scene = false
		_fit_layout()
		_open_modal("error")
		modal_text.text = "场景暂时无法打开，请重试。"


func _open_modal(kind: String) -> void:
	modal_kind = kind
	previous_focus = get_viewport().gui_get_focus_owner()
	for button: Button in [start_button, continue_button, settings_button, exit_button]:
		button.focus_mode = Control.FOCUS_NONE
	settings_controls.visible = kind == "settings"
	cancel_button.visible = kind in ["new_game", "exit"] and not (kind == "exit" and OS.has_feature("web"))
	confirm_button.text = "完成" if kind == "settings" else "确定"
	match kind:
		"settings":
			modal_title.text = "设置"
			modal_text.text = "让旅途更合心意。"
			volume_slider.set_value_no_signal(GameSession.volume * 100.0)
			volume_value.text = "%d%%" % volume_slider.value
			fullscreen_toggle.set_pressed_no_signal(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
		"new_game":
			modal_title.text = "开始新的旅途？"
			modal_text.text = "开始游戏会替换当前的本地进度。"
			confirm_button.text = "开始游戏"
		"exit":
			modal_title.text = "暂别旅途"
			modal_text.text = "确定退出游戏？"
			confirm_button.text = "退出游戏"
			if OS.has_feature("web"):
				modal_text.text = "关闭此标签页即可退出游戏。"
				if GameSession.has_save:
					modal_text.text = "进度已保存在此浏览器中。\n" + modal_text.text
				confirm_button.text = "知道了"
		"error":
			modal_title.text = "暂时无法完成"
	modal.show()
	WwiseManager.play("modal_open", self)
	if kind == "settings":
		volume_slider.grab_focus()
	elif cancel_button.visible:
		cancel_button.grab_focus()
	else:
		confirm_button.grab_focus()


func _close_modal() -> void:
	var was_visible := modal.visible
	if modal_kind == "settings" and GameSession.save_settings() != OK:
		modal_kind = "error"
		settings_controls.hide()
		modal_text.text = "设置已应用，但无法保存到本地。"
		confirm_button.text = "知道了"
		return
	modal.hide()
	if was_visible:
		WwiseManager.play("modal_close", self)
	for button: Button in [start_button, continue_button, settings_button, exit_button]:
		button.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(previous_focus):
		previous_focus.grab_focus()


func _confirm_modal() -> void:
	match modal_kind:
		"new_game":
			_enter_game(false)
		"exit":
			if OS.has_feature("web"):
				_close_modal()
			else:
				get_tree().quit()
		_:
			_close_modal()


func _on_volume_changed(value: float) -> void:
	GameSession.apply_volume(value / 100.0)
	volume_value.text = "%d%%" % value


func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
