shader_type canvas_item;
// Smooth biome edge blending via Gaussian-style blur at tile boundaries.
// Applied to the baked terrain sprite — softens hard tile edges.

uniform float blend_radius : hint_range(0.0, 8.0) = 3.0;
uniform vec2 tile_size = vec2(32.0, 32.0);
uniform vec2 map_size_tiles = vec2(128.0, 128.0);

void fragment() {
    vec2 uv = UV;
    vec2 tex_size = vec2(map_size_tiles * tile_size);
    vec2 pixel_pos = uv * tex_size;
    
    // Distance to nearest tile edge
    vec2 tile_pos = mod(pixel_pos, tile_size);
    float dx = min(tile_pos.x, tile_size.x - tile_pos.x);
    float dy = min(tile_pos.y, tile_size.y - tile_pos.y);
    float edge_dist = min(dx, dy);
    
    if (edge_dist < blend_radius) {
        // Near a tile edge — sample a small box blur
        float weight_sum = 0.0;
        vec4 color_sum = vec4(0.0);
        float radius = blend_radius - edge_dist;
        
        for (float oy = -2.0; oy <= 2.0; oy += 1.0) {
            for (float ox = -2.0; ox <= 2.0; ox += 1.0) {
                vec2 offset = vec2(ox, oy) * radius * 0.5;
                vec2 sample_uv = uv + offset / tex_size;
                sample_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));
                float w = 1.0 / (1.0 + length(vec2(ox, oy)));
                color_sum += texture(TEXTURE, sample_uv) * w;
                weight_sum += w;
            }
        }
        COLOR = color_sum / weight_sum;
    } else {
        COLOR = texture(TEXTURE, uv);
    }
}
