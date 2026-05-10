shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Shared "wind sway" shader for trees, grass and other static
// foliage billboards. The vertex pass nudges the *top* of the quad
// horizontally with a sin wave, so anything anchored near UV.y == 1
// stays planted while UV.y == 0 (top of texture, top of plant) sways.
//
// One ShaderMaterial instance is shared across thousands of billboards.
// Per-plant variation comes from the world-space VERTEX position, not
// from per-instance uniforms, so we keep this fully GPU-instancing
// friendly (and also cheap when used as a Sprite3D material_override).

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wind_strength : hint_range(0.0, 0.2) = 0.04;
uniform float wind_speed : hint_range(0.0, 5.0) = 0.7;
uniform float wind_jitter : hint_range(0.0, 4.0) = 0.4;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	// Sprite3D / QuadMesh both give us UV.y == 0 at the top of the
	// texture and UV.y == 1 at the bottom. We want a "rooted" sway:
	// strong at top, none at bottom. pow > 1 makes the bend feel like
	// a soft pendulum instead of a uniform shake.
	float sway_factor = pow(1.0 - UV.y, 1.5);

	// Per-plant phase from world position so neighbouring plants are
	// out of sync. Cheap and deterministic — no per-instance uniform.
	float phase = NODE_POSITION_WORLD.x * wind_jitter
		+ NODE_POSITION_WORLD.z * wind_jitter * 0.8;
	float wave = sin(TIME * wind_speed + phase);
	VERTEX.x += wave * wind_strength * sway_factor;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < alpha_cutoff) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a * tint.a;
}
