shader_type canvas_item;
render_mode unshaded;

// The supplied JPEG has a baked black background. Key it at render time,
// preserving the original sheet and allowing the threshold to be adjusted.
uniform float black_cutoff : hint_range(0.0, 0.2) = 0.025;
uniform float edge_softness : hint_range(0.001, 0.2) = 0.055;
uniform bool wide_swing = false;
uniform bool recovery_pose = false;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float brightness = max(tex.r, max(tex.g, tex.b));
	float alpha = smoothstep(black_cutoff, black_cutoff + edge_softness, brightness);
	// The broad lower arc shares its rectangle with the next frame's wrench.
	// Keep the arc below it, while excluding that neighboring pose.
	if (wide_swing && UV.x > 1985.0 / 2520.0 && UV.y < 990.0 / 1280.0) {
		alpha = 0.0;
	}
	// Conversely, exclude the previous frame's arc from the recovery pose.
	if (recovery_pose && UV.x < 2035.0 / 2520.0 && UV.y > 990.0 / 1280.0) {
		alpha = 0.0;
	}
	COLOR = vec4(tex.rgb, tex.a * alpha);
}
