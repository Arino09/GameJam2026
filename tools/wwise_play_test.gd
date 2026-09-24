extends SceneTree

## Run with: godot --path . --script tools/wwise_play_test.gd
## This is a developer smoke test; it is not referenced by any game scene.
##
## The Wwise project uses Auto-Defined SoundBanks, so the only way to prove
## the Play_Test event's loose media actually decoded (and not just that
## post() returned a playing ID) is to wait for the AK_DURATION callback and
## check its fDuration. See scripts/wwise_manager.gd (_get_wwise_event) and
## docs/wwise-audio.md for the full story of the "Media ... was not loaded
## for this source" bug this replaces.
##
## This script relaunches itself once as a child Godot process (see
## _run_parent()) purely so this outer process can capture the child's
## stdout/stderr as text and grep it for that "not loaded" error line --
## something a script cannot do to its own process's output. The documented
## command above still only starts one process from the caller's point of
## view.

const CHILD_MARKER := "wwise-play-test-child"
const MEDIA_ERROR_NEEDLE := "was not loaded for this source"
const WAIT_SECONDS := 5.0
const AK_DURATION_TYPE := 8
const AK_END_OF_EVENT_TYPE := 1

var _events_seen: Array = []


func _initialize() -> void:
	if CHILD_MARKER in OS.get_cmdline_user_args():
		await _run_child()
	else:
		_run_parent()


func _run_parent() -> void:
	var exe := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"--headless",
		"--path", project_path,
		"--script", "res://tools/wwise_play_test.gd",
		"--",
		CHILD_MARKER,
	])
	var output := []
	var exit_code := OS.execute(exe, args, output, true, false)
	var full_output := "\n".join(output)
	print(full_output)

	var media_error_seen := full_output.find(MEDIA_ERROR_NEEDLE) != -1
	var child_result := false
	for line in full_output.split("\n"):
		if line.begins_with("WWISE_PLAY_TEST_RESULT="):
			child_result = line.trim_prefix("WWISE_PLAY_TEST_RESULT=").strip_edges() == "true"

	var result := child_result and not media_error_seen
	print("WWISE_PLAY_TEST_CHILD_EXIT_CODE=", exit_code)
	print("WWISE_PLAY_TEST_MEDIA_ERROR_SEEN=", media_error_seen)
	print("WWISE_PLAY_TEST_RESULT=", result)
	quit(0 if result else 1)


func _run_child() -> void:
	await process_frame
	var manager := get_root().get_node_or_null("WwiseManager")
	if manager == null:
		printerr("WWISE_PLAY_TEST_RESULT=false (missing WwiseManager autoload)")
		print("WWISE_PLAY_TEST_RESULT=false")
		quit(2)
		return

	# Let WwiseManager's own deferred _initialize() (Wwise.init(), Init.bnk,
	# table load) finish before we post anything.
	await create_timer(1.0).timeout

	var node := Node.new()
	node.name = "WwisePlayTestNode"
	get_root().add_child(node)
	await process_frame

	var posted := false
	if manager.has_method("play_test_with_callback"):
		posted = manager.call("play_test_with_callback", Callable(self, "_on_wwise_callback"), node)
	else:
		printerr("WwiseManager has no play_test_with_callback(); cannot verify media decode.")

	var start_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < WAIT_SECONDS * 1000.0:
		await process_frame
		if _has_end_of_event() and _has_duration():
			break

	var duration_ms := _get_duration()
	var end_of_event := _has_end_of_event()
	var status: Dictionary = manager.call("get_status")
	var wwise_events: Dictionary = status.get("wwise_events", {})
	# Don't hardcode the event name here: the TSV's test_play row is free to
	# point at whatever real event exists in the Wwise project (it has been
	# renamed before). This test only ever posts one event, so any loaded
	# entry proves the auto-defined bank for that event decoded.
	var auto_bank_loaded := false
	for entry in wwise_events.values():
		if entry is Dictionary and bool(entry.get("is_auto_bank_loaded", false)):
			auto_bank_loaded = true
			break

	var result := posted and auto_bank_loaded and duration_ms > 0.0 and end_of_event

	print("WWISE_PLAY_TEST_POSTED=", posted)
	print("WWISE_PLAY_TEST_AUTO_BANK_LOADED=", auto_bank_loaded)
	print("WWISE_PLAY_TEST_DURATION_MS=", duration_ms)
	print("WWISE_PLAY_TEST_END_OF_EVENT=", end_of_event)
	print("WWISE_PLAY_TEST_STATUS=", status)
	print("WWISE_PLAY_TEST_RESULT=", result)
	quit(0 if result else 1)


func _on_wwise_callback(info) -> void:
	_events_seen.append(info)


func _get_duration() -> float:
	for info in _events_seen:
		if info is Dictionary and int(info.get("callback_type", -1)) == AK_DURATION_TYPE:
			return float(info.get("fDuration", 0.0))
	return 0.0


func _has_duration() -> bool:
	return _get_duration() > 0.0


func _has_end_of_event() -> bool:
	for info in _events_seen:
		if info is Dictionary and int(info.get("callback_type", -1)) == AK_END_OF_EVENT_TYPE:
			return true
	return false
