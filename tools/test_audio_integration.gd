extends SceneTree

class FakeWwise:
	extends RefCounted
	var calls: Array = []
	func set_game_object_output_bus_volume(emitter: Node, listener: Node, value: float) -> bool:
		calls.append([emitter.get_instance_id(), listener.get_instance_id(), value])
		return true

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func _run() -> void:
	await process_frame
	var manager := root.get_node("WwiseManager")
	var runtime := root.get_node("WwiseRuntimeManager")
	check(not runtime._owns_lifecycle, "Stock autoload defers lifecycle to project bridge")
	check(manager._table_loaded and manager._rules.size() == 25, "All 25 TSV rules load")
	check(manager._resolve_key(["walk_forest", "walk"]) == "", "Empty placeholders stay silent")
	if not Engine.has_singleton("Wwise"):
		check(not manager._initialized, "Missing extension degrades without initialization")
	elif OS.get_name() == "Linux":
		check(not manager._initialized, "Missing Linux bank degrades without initialization")
	# Exercise real bridge/settings code with a recording API, without needing
	# a platform bank or claiming this proves audible output.
	var backend := FakeWwise.new()
	manager._wwise = backend
	manager._initialized = true
	manager._owns_lifecycle = false
	var emitter := Node.new()
	root.add_child(emitter)
	manager._apply_emitter_volume(emitter)
	var session := root.get_node("GameSession")
	session.apply_volume(0.25)
	check(is_equal_approx(backend.calls[-1][2], 0.25), "Settings update active Wwise emitter gain")
	session.apply_volume(0.0)
	check(is_zero_approx(backend.calls[-1][2]), "Mute sets Wwise emitter gain to zero")
	var second := Node.new()
	root.add_child(second)
	manager._apply_emitter_volume(second)
	check(is_zero_approx(backend.calls[-1][2]), "New emitters inherit mute before posting")
	emitter.free()
	session.apply_volume(1.0)
	check(manager._emitters.size() == 1, "Scene-freed emitters are pruned safely")
	check(is_equal_approx(backend.calls[-1][2], 1.0), "Unmute updates surviving emitter")
	second.free()
	manager._initialized = false
	manager._wwise = null
	print("AUDIO INTEGRATION TESTS: %d failure(s)" % failures)
	quit(1 if failures else 0)
