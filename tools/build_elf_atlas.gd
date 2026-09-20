extends SceneTree
## Deterministic engine import preparation, no creative changes to generated art.
## godot --headless --path . --script tools/build_elf_atlas.gd

func _initialize() -> void:
	var source := Image.load_from_file("res://assets/elf/elf_source.png")
	assert(source.get_size() == Vector2i(1024, 1536), "Expected a 4 × 4 source atlas")
	assert(source.detect_alpha() != Image.ALPHA_NONE, "Source must have real transparency")
	var atlas := Image.create(128, 192, false, Image.FORMAT_RGBA8)
	var directions := ["down", "left", "right", "up"]
	var resources := "[gd_resource type=\"SpriteFrames\" load_steps=18 format=3]\n\n"
	resources += "[ext_resource type=\"Texture2D\" path=\"res://assets/elf/elf_walk.png\" id=\"1\"]\n"
	for row in range(4):
		for col in range(4):
			var frame := source.get_region(Rect2i(col * 256, row * 384, 256, 384))
			# Discard only fractional-alpha fringe so native pixels stay crisp.
			for y in range(frame.get_height()):
				for x in range(frame.get_width()):
					var pixel := frame.get_pixel(x, y)
					pixel.a = 1.0 if pixel.a >= 0.5 else 0.0
					frame.set_pixel(x, y, pixel)
			var bounds := frame.get_used_rect()
			assert(bounds.has_area(), "Empty animation frame")
			var cropped := frame.get_region(bounds)
			# All 16 frames use the same 1:8 scale, not individual height fitting.
			cropped.resize(maxi(1, roundi(bounds.size.x / 8.0)), maxi(1, roundi(bounds.size.y / 8.0)), Image.INTERPOLATE_NEAREST)
			assert(cropped.get_width() <= 32 and cropped.get_height() <= 44)
			var anchor := Vector2i(col * 32 + (32 - cropped.get_width()) / 2, row * 48 + 44 - cropped.get_height())
			atlas.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), anchor)
			resources += "\n[sub_resource type=\"AtlasTexture\" id=\"%s_%d\"]\n" % [directions[row], col]
			resources += "atlas = ExtResource(\"1\")\nregion = Rect2(%d, %d, 32, 48)\n" % [col * 32, row * 48]
			print("Frame %s/%d: %s px, feet y=44" % [directions[row], col, cropped.get_size()])
	var animations: PackedStringArray = []
	for direction in directions:
		for moving in [false, true]:
			var frames: PackedStringArray = []
			for index in range(4 if moving else 1):
				frames.append('{"duration": 1.0, "texture": SubResource("%s_%d")}' % [direction, index])
			animations.append('{"frames": [%s], "loop": true, "name": &"%s_%s", "speed": 8.0}' % [", ".join(frames), "walk" if moving else "idle", direction])
	resources += "\n[resource]\nanimations = [%s]\n" % ",\n".join(animations)
	assert(atlas.save_png("res://assets/elf/elf_walk.png") == OK)
	var file := FileAccess.open("res://assets/elf/elf_frames.tres", FileAccess.WRITE)
	file.store_string(resources)
	file.close()
	print("PASS: native 128 × 192 atlas, sixteen 32 × 48 cells, four directions.")
	quit()
