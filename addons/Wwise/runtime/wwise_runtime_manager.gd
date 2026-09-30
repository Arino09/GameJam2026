extends Node
## The editor automatically installs this autoload. The project bridge owns
## lifecycle when present; keep standalone use safe without the extension.

var suspend_on_focus_loss := false
var _wwise: Object
var _owns_lifecycle := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	suspend_on_focus_loss = ProjectSettings.get_setting("wwise/common_user_settings/suspend_audio_during_focus_loss", false)
	if get_node_or_null("/root/WwiseManager") != null:
		set_process(false)
		return
	if not Engine.has_singleton("Wwise"):
		set_process(false)
		return
	_wwise = Engine.get_singleton("Wwise")
	if not _wwise.call("is_initialized"):
		_wwise.call("init")
		_owns_lifecycle = bool(_wwise.call("is_initialized"))

func _process(_delta: float) -> void:
	if _owns_lifecycle:
		_wwise.call("render_audio")

func _notification(what: int) -> void:
	if not _owns_lifecycle:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or (suspend_on_focus_loss and what == NOTIFICATION_APPLICATION_FOCUS_OUT):
		pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED or (suspend_on_focus_loss and what == NOTIFICATION_APPLICATION_FOCUS_IN):
		resume()
	elif what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_CRASH:
		_wwise.call("shutdown")
		_owns_lifecycle = false

func pause() -> void:
	if _owns_lifecycle:
		_wwise.call("suspend", false)

func resume() -> void:
	if _owns_lifecycle:
		_wwise.call("wakeup_from_suspend")
