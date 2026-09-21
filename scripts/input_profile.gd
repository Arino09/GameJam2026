extends Node
## 区分运行平台与控制方式：Web 也可能运行在手机、平板或桌面电脑上。

signal changed

const DESKTOP_SIZE := Vector2i(1280, 720)
const MOBILE_HEIGHT := 720

var mobile := false
var _orientation_hint: ColorRect
var _paused_for_orientation := false
var _window_size := Vector2i.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var browser_info: Dictionary = {}
	if OS.has_feature("web"):
		var result: Variant = JavaScriptBridge.eval("""
			JSON.stringify({
				user_agent: navigator.userAgent || '',
				platform: navigator.platform || '',
				touch_points: navigator.maxTouchPoints || 0,
				mobile_hint: !!(navigator.userAgentData && navigator.userAgentData.mobile)
			})
		""")
		if result is String:
			var parsed: Variant = JSON.parse_string(result)
			if parsed is Dictionary:
				browser_info = parsed
	mobile = detect_mobile(OS.get_name(), browser_info)
	# 便于在桌面编辑器中验证触控布局，不写入玩家偏好或存档。
	if OS.is_debug_build() and "--mobile-controls" in OS.get_cmdline_user_args():
		mobile = true
	_apply_input_mode()
	_create_orientation_hint()
	get_window().size_changed.connect(_fit_layout)
	_fit_layout()
	if mobile and OS.has_feature("web"):
		# 浏览器通常仅允许全屏时锁定方向；不支持时由横屏提示兜底。
		JavaScriptBridge.eval("""
			(() => {
				const lockLandscape = () => {
					if (document.fullscreenElement && screen.orientation && screen.orientation.lock) {
						screen.orientation.lock('landscape').catch(() => {});
					}
				};
				document.addEventListener('fullscreenchange', lockLandscape);
				lockLandscape();
			})();
		""")


static func detect_mobile(platform_name: String, browser_info: Dictionary) -> bool:
	if platform_name in ["Android", "iOS"]:
		return true
	if platform_name != "Web":
		return false
	var user_agent := str(browser_info.get("user_agent", "")).to_lower()
	for token in ["android", "iphone", "ipad", "ipod", "mobile", "iemobile"]:
		if token in user_agent:
			return true
	if browser_info.get("mobile_hint", false) == true:
		return true
	# iPad 的桌面浏览模式使用 Macintosh UA，仍提供多点触控能力。
	return str(browser_info.get("platform", "")) == "MacIntel" and int(browser_info.get("touch_points", 0)) > 1


func set_mobile(value: bool) -> void:
	if mobile == value:
		return
	mobile = value
	_apply_input_mode()
	_fit_layout()
	changed.emit()


func _apply_input_mode() -> void:
	# 菜单、设置等标准 Control 按钮需要此项才能接收触屏轻点。
	# 游戏摇杆/动作自行处理多指输入，并屏蔽对应的模拟鼠标事件。
	Input.emulate_mouse_from_touch = true
	if OS.get_name() in ["Android", "iOS"]:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)


func use_gameplay_layout() -> void:
	_fit_layout()


func use_menu_layout() -> void:
	_fit_layout()


func _process(_delta: float) -> void:
	# 固定逻辑视口时，物理窗口变化未必触发 Viewport.size_changed。
	# 同时跟踪实际窗口尺寸，覆盖浏览器地址栏、全屏和设备旋转。
	if get_window().size != _window_size:
		_fit_layout()


func _fit_layout() -> void:
	var window := get_window()
	_window_size = window.size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	window.min_size = Vector2i(320, 180)
	var target := DESKTOP_SIZE
	if mobile:
		var aspect := float(window.size.x) / maxf(window.size.y, 1.0)
		# 高度固定，宽度随设备变化；竖屏期间只展示提示并暂停游戏。
		target = Vector2i(maxi(1, roundi(MOBILE_HEIGHT * aspect)), MOBILE_HEIGHT)
	if window.content_scale_size != target:
		window.content_scale_size = target
	var portrait := mobile and window.size.x < window.size.y
	if is_instance_valid(_orientation_hint):
		_orientation_hint.visible = portrait
	if portrait and not get_tree().paused:
		_paused_for_orientation = true
		get_tree().paused = true
	elif not portrait and _paused_for_orientation:
		_paused_for_orientation = false
		get_tree().paused = false


func _create_orientation_hint() -> void:
	var layer := CanvasLayer.new()
	layer.name = "OrientationOverlay"
	layer.layer = 100
	add_child(layer)
	_orientation_hint = ColorRect.new()
	_orientation_hint.name = "LandscapeHint"
	_orientation_hint.color = Color("102722")
	layer.add_child(_orientation_hint)
	_orientation_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "请横屏游玩\n\n旋转设备后继续"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 28)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orientation_hint.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _input(_event: InputEvent) -> void:
	if is_instance_valid(_orientation_hint) and _orientation_hint.visible:
		get_viewport().set_input_as_handled()
