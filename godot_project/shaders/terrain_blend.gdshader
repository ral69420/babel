shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_lambert_wrap;

// Per-vertex biome weights blended into a single terrain surface so
// adjacent hexes of different biomes transition smoothly (no seams,
// no hard borders).
//
// Weight encoding (vertex COLOR + ocean fallback):
//   COLOR.r = plains weight
//   COLOR.g = forest weight
//   COLOR.b = hills  weight
//   COLOR.a = mountain weight
//   ocean   = max(0, 1 - r - g - b - a)
//
// Each centre vertex of a hex carries (1,0,0,0) for its biome (or 0000
// for ocean). Corners shared by 3 hexes carry the average of the three
// touching biomes, so vertex-colour interpolation across triangles is
// continuous → no visible seam.

uniform sampler2D tex_plains   : source_color, filter_nearest, repeat_disable;
uniform sampler2D tex_forest   : source_color, filter_nearest, repeat_disable;
uniform sampler2D tex_hills    : source_color, filter_nearest, repeat_disable;
uniform sampler2D tex_mountain : source_color, filter_nearest, repeat_disable;
uniform sampler2D tex_ocean    : source_color, filter_nearest, repeat_disable;

void fragment() {
	vec3 c_plains   = texture(tex_plains,   UV).rgb;
	vec3 c_forest   = texture(tex_forest,   UV).rgb;
	vec3 c_hills    = texture(tex_hills,    UV).rgb;
	vec3 c_mountain = texture(tex_mountain, UV).rgb;
	vec3 c_ocean    = texture(tex_ocean,    UV).rgb;

	float w_plains   = COLOR.r;
	float w_forest   = COLOR.g;
	float w_hills    = COLOR.b;
	float w_mountain = COLOR.a;
	float w_ocean    = max(0.0, 1.0 - w_plains - w_forest - w_hills - w_mountain);

	vec3 result = c_plains   * w_plains
	            + c_forest   * w_forest
	            + c_hills    * w_hills
	            + c_mountain * w_mountain
	            + c_ocean    * w_ocean;

	ALBEDO = result;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
