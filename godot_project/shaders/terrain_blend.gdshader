shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_lambert_wrap;

// Continuous-landscape terrain shader for the Babel quad-grid heightmap.
//
// Per-vertex biome weights are blended into a single surface so adjacent
// tiles of different biomes transition smoothly, with no seams or hard
// borders. Texture sampling switched from per-hex UVs (which made every
// hex restart its own circular UV island and produced visible Civ-6-style
// tile borders) to **world-space UVs** derived from the vertex's XZ
// position. The same pixel-art texture now tiles continuously across the
// whole map regardless of the underlying hex grid, so biome boundaries
// read as colour transitions only.
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

uniform sampler2D tex_plains   : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_forest   : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_hills    : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_mountain : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_ocean    : source_color, filter_nearest, repeat_enable;

// World-space UVs are derived from the vertex world XZ position divided
// by `tile_world_size`. Larger values stretch the ground texture over a
// wider area; smaller values tile it more tightly. 1.0 keeps the
// existing pixel-art tile reading as one full ground tile per world unit
// (≈ one hex radius), matching the previous on-screen scale.
uniform float tile_world_size : hint_range(0.25, 8.0) = 1.0;

varying vec2 world_uv;

void vertex() {
	// Use the XZ plane of the vertex in model space as the UV. The
	// terrain mesh sits at the world origin without per-instance
	// transforms, so model XZ == world XZ, and the texture tiles
	// continuously across the whole map.
	world_uv = VERTEX.xz / tile_world_size;
}

void fragment() {
	vec2 uv = world_uv;

	vec3 c_plains   = texture(tex_plains,   uv).rgb;
	vec3 c_forest   = texture(tex_forest,   uv).rgb;
	vec3 c_hills    = texture(tex_hills,    uv).rgb;
	vec3 c_mountain = texture(tex_mountain, uv).rgb;
	vec3 c_ocean    = texture(tex_ocean,    uv).rgb;

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
