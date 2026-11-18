shader_type canvas_item;
render_mode blend_mix;
// Each terrace samples its own grass field. Rock keeps the atlas shading.
uniform float elevation = 1.0;
varying vec2 world;
varying vec4 tint;

void vertex() {
	world = VERTEX;
	tint = COLOR;
}
#include "res://game/world/terrain/terrain_grass.gdshaderinc"

// SpriteU uses this palette entry for the grass fill inside the bevel.
const vec3 GRASS_FILL = vec3(82.0, 139.0, 62.0) / 255.0;

void fragment() {
	vec4 local = texture(TEXTURE, UV);
	if (distance(local.rgb, GRASS_FILL) < 0.004) {
		vec2 w = (floor(world / 2.0) + 0.5) * 2.0;
		local.rgb = elevation_grass(w, elevation) / 255.0;
	}
	COLOR = local * tint;
}
