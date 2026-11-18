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
float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.57 + vnoise(p * 2.03 + 5.1) * 0.29 + vnoise(p * 4.01 + 9.7) * 0.14;
}

const vec3 GRASS_P[6] = vec3[6](vec3(35.0,72.0,48.0),vec3(44.0,88.0,56.0),vec3(53.0,102.0,52.0),vec3(66.0,118.0,58.0),vec3(79.0,133.0,57.0),vec3(98.0,150.0,62.0));
// SpriteU uses this palette entry for the grass fill inside the bevel.
const vec3 GRASS_FILL = vec3(82.0, 139.0, 62.0) / 255.0;

void fragment() {
	vec4 local = texture(TEXTURE, UV);
	if (distance(local.rgb, GRASS_FILL) < 0.004) {
		vec2 w = (floor(world / 2.0) + 0.5) * 2.0;
		w += elevation * vec2(173.0, -97.0);
		float tone = fbm(w / 240.0) * 0.72 + vnoise(w / 26.0) * 0.2 + (hash(w) - 0.5) * 0.1 + 0.04;
		vec3 grass = GRASS_P[int(clamp(tone, 0.0, 0.999) * 6.0)] / 255.0;
		local.rgb = grass * (vec3(1.01, 1.04, 0.97) + (elevation - 1.0) * vec3(0.07, 0.09, 0.03));
	}
	COLOR = local * tint;
}
