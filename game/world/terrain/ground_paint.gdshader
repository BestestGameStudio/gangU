shader_type canvas_item;
// No `unshaded`: it opts a canvas shader out of CanvasModulate, so the day-night tint skipped the ground.
render_mode blend_mix;
// Painted overworld ground: one quad over the whole field, no tiles.
// `types` holds one texel per 64 px lattice point (DualGrid.T as R*255);
// the shader samples it at a noise-warped position with bilinear weights per
// type, so boundaries are smooth organic curves instead of grid steps. Each
// type is a small palette picked by clumpy noise (grass/dirt/sand) or a
// voronoi slab pattern (sandstone/stone/cobble), snapped to 2 px art pixels
// like the painted pieces. The void outside the field shows a rock face
// below the grass edge. Presentation only: OverworldGround keeps the data.

uniform sampler2D types : filter_nearest;
uniform vec2 lattice_origin;   // world position of texel (0, 0)'s lattice point
uniform float cell = 64.0;
uniform float art_px = 2.0;
uniform sampler2D relief : filter_linear, repeat_disable;
uniform vec2 relief_origin;
uniform float relief_cell = 32.0;
uniform float warp_amount = 70.0;

const int GRASS = 0;
const int DIRT = 1;
const int SAND = 2;
const int SANDSTONE = 3;
const int STONE = 4;
const int CLIFF = 5;
const int COBBLE = 6;

const vec3 GRASS_P[6] = vec3[6](vec3(35.0, 72.0, 48.0), vec3(44.0, 88.0, 56.0), vec3(53.0, 102.0, 52.0), vec3(66.0, 118.0, 58.0), vec3(79.0, 133.0, 57.0), vec3(98.0, 150.0, 62.0));
const vec3 DIRT_P[5] = vec3[5](vec3(62.0, 49.0, 39.0), vec3(79.0, 63.0, 48.0), vec3(98.0, 80.0, 57.0), vec3(119.0, 98.0, 70.0), vec3(140.0, 118.0, 85.0));
const vec3 SAND_P[5] = vec3[5](vec3(150.0, 118.0, 72.0), vec3(176.0, 142.0, 90.0), vec3(196.0, 162.0, 104.0), vec3(214.0, 182.0, 122.0), vec3(228.0, 200.0, 142.0));
const vec3 SSTONE_P[5] = vec3[5](vec3(158.0, 118.0, 78.0), vec3(181.0, 140.0, 94.0), vec3(201.0, 160.0, 110.0), vec3(219.0, 180.0, 128.0), vec3(234.0, 200.0, 150.0));
const vec3 STONE_P[6] = vec3[6](vec3(38.0, 42.0, 53.0), vec3(59.0, 65.0, 82.0), vec3(77.0, 85.0, 104.0), vec3(95.0, 104.0, 126.0), vec3(122.0, 131.0, 153.0), vec3(149.0, 157.0, 176.0));
const vec3 COBBLE_P[5] = vec3[5](vec3(70.0, 64.0, 60.0), vec3(92.0, 86.0, 80.0), vec3(114.0, 107.0, 98.0), vec3(136.0, 129.0, 118.0), vec3(160.0, 152.0, 140.0));
const vec3 CLIFF_P[6] = vec3[6](vec3(37.0, 28.0, 27.0), vec3(53.0, 40.0, 38.0), vec3(74.0, 55.0, 50.0), vec3(94.0, 71.0, 64.0), vec3(117.0, 90.0, 78.0), vec3(142.0, 112.0, 95.0));
const vec3 VOID_C = vec3(9.0, 11.0, 10.0);
const vec3 ROCK_C = vec3(88.0, 82.0, 88.0); // flat rock under the cliff face (#820), same as OverworldCliffRock

varying vec2 world;

void vertex() {
	world = VERTEX;
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

int type_at(ivec2 i) {
	ivec2 size = textureSize(types, 0);
	i = clamp(i, ivec2(0), size - 1);
	return int(texelFetch(types, i, 0).r * 255.0 + 0.5);
}

// Bilinear weight per type at world position w: the winning type, the runner
// up and the margin between them (0 = right on the boundary).
void classify(vec2 w, out int top, out int second, out float margin) {
	vec2 l = (w - lattice_origin) / cell;
	ivec2 i0 = ivec2(floor(l));
	vec2 f = fract(l);
	float acc[7];
	for (int t = 0; t < 7; t++) {
		acc[t] = 0.0;
	}
	acc[type_at(i0)] += (1.0 - f.x) * (1.0 - f.y);
	acc[type_at(i0 + ivec2(1, 0))] += f.x * (1.0 - f.y);
	acc[type_at(i0 + ivec2(0, 1))] += (1.0 - f.x) * f.y;
	acc[type_at(i0 + ivec2(1, 1))] += f.x * f.y;
	top = 0;
	second = 0;
	float best = -1.0;
	float next = -1.0;
	for (int t = 0; t < 7; t++) {
		if (acc[t] > best) {
			next = best;
			second = top;
			best = acc[t];
			top = t;
		} else if (acc[t] > next) {
			next = acc[t];
			second = t;
		}
	}
	margin = best - max(next, 0.0);
}

vec2 warped(vec2 w) {
	vec2 q = w / 120.0;
	return w + (vec2(fbm(q), fbm(q + 17.3)) - 0.5) * warp_amount;
}

// (nearest distance, second distance, cell id)
vec3 voronoi(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(ip + g), hash(ip + g + 31.7)) * 0.8 + 0.1;
			float d = length(g + o - fp);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash(ip + g + 7.1);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2, id);
}

// Slab floors: voronoi stones, a mortar gap, lit top edge, dark bottom edge.
vec3 slabs(vec2 w, float size, float squash, float gap, int kind, float tone) {
	vec2 s = vec2(1.0, squash) / size;
	vec3 v = voronoi(w * s);
	float up = voronoi((w - vec2(0.0, art_px)) * s).z;
	float down = voronoi((w + vec2(0.0, art_px)) * s).z;
	int k = int(clamp(v.z * 2.2 + tone * 1.6, 0.0, 3.0)) + 1;
	vec3 c;
	vec3 mortar;
	if (kind == SANDSTONE) {
		c = SSTONE_P[k];
		mortar = SSTONE_P[0] * 0.8;
	} else if (kind == STONE) {
		c = STONE_P[k];
		mortar = STONE_P[0];
	} else {
		c = COBBLE_P[k];
		mortar = DIRT_P[0];
	}
	if (v.y - v.x < gap) {
		return mortar;
	}
	if (up != v.z) {
		c = (kind == SANDSTONE) ? SSTONE_P[4] : (kind == STONE ? STONE_P[5] : COBBLE_P[4]);
	} else if (down != v.z) {
		c *= 0.62;
	}
	return c;
}

vec3 paint(int t, vec2 w, float tone) {
	if (t == GRASS) {
		return GRASS_P[int(clamp(tone, 0.0, 0.999) * 6.0)];
	} else if (t == DIRT) {
		// Packed earth with pebbles: a lit pixel over a shaded one.
		float g = hash(w + 3.7);
		if (g > 0.985) {
			return DIRT_P[4];
		}
		if (hash(w - vec2(0.0, art_px) + 3.7) > 0.985) {
			return DIRT_P[0];
		}
		return DIRT_P[int(clamp(tone * 0.8 + vnoise(w / 9.0) * 0.25, 0.0, 0.999) * 4.0) + (g < 0.08 ? 0 : 1) - 1 + 1];
	} else if (t == SAND) {
		// Wind ripples: thin lit bands that wobble.
		float ripple = sin(w.y * 0.35 + fbm(w / 60.0) * 9.0 + w.x * 0.04);
		int k = int(clamp(tone, 0.0, 0.999) * 4.0) + 1;
		return ripple > 0.93 ? SAND_P[4] : (ripple < -0.95 ? SAND_P[k - 1] : SAND_P[k]);
	} else if (t == SANDSTONE) {
		return slabs(w, 26.0, 1.4, 0.07, SANDSTONE, tone);
	} else if (t == STONE) {
		return slabs(w, 18.0, 1.5, 0.09, STONE, tone);
	} else if (t == COBBLE) {
		return slabs(w, 10.0, 1.2, 0.12, COBBLE, tone);
	}
	return VOID_C;
}

// SpriteU atlas: eight variants per material, 64 art pixels each.
vec3 cliff_stone(vec2 w, float depth, int kind) {
	int row = kind == COBBLE ? 5 : clamp(kind, 0, 4);
	float column = floor(hash(vec2(floor(w.x / 128.0), 888.0)) * 8.0);
	vec2 texel = vec2(column * 64.0 + mod(floor(w.x / 2.0), 64.0),
		float(row) * 64.0 + mod(floor(w.y / 2.0), 64.0));
	vec3 rock = vec3(136.0,111.0,88.0);
	// Broad lower occlusion, not a black outline or repeated stone blobs.
	return rock * (depth > 108.0 ? 0.66 : (depth > 72.0 ? 0.72 : (depth > 36.0 ? 0.82 : 1.0)));
}

// R is the walkable top, G the wider foot of the cliff, B the cut stone stair.
vec3 paint_stairs(vec2 w, vec3 ground) {
	vec2 grid = (w - relief_origin) / relief_cell;
	vec2 size = vec2(textureSize(relief, 0));
	if (any(lessThan(grid, vec2(0.0))) || any(greaterThanEqual(grid, size))) { return ground; }
	vec3 tile = texture(relief, (floor(grid) + 0.5) / size).rgb;
	if (tile.b > 0.5) {
		float across = fract(grid.x);
		bool curb = (across < 0.12 && texture(relief, (floor(grid) + vec2(-0.5, 0.5)) / size).b < 0.5)
			|| (across > 0.88 && texture(relief, (floor(grid) + vec2(1.5, 0.5)) / size).b < 0.5);
		if (curb) { return mod(w.y, 24.0) < 3.0 ? COBBLE_P[0] : COBBLE_P[3]; }
		if (tile.g - tile.r < 0.25) { return slabs(w, 24.0, 1.4, 0.05, COBBLE, 0.57); }
		float tread = mod(w.y, 12.0);
		float joint = mod(w.x + floor(w.y / 12.0) * 19.0, 46.0);
		vec3 stone = mix(COBBLE_P[2], COBBLE_P[4], vnoise(w / 7.0));
		if (tread < 2.0) { return COBBLE_P[4] * 1.15; }
		if (tread >= 8.0) { return COBBLE_P[1] * 0.82; }
		return joint < 2.0 ? COBBLE_P[1] : stone;
	}
	return ground;
}

void fragment() {
	vec2 w = (floor(world / art_px) + 0.5) * art_px;   // one colour per art pixel
	// Calm, broad patches with a little grain, so tufts and pieces carry the detail.
	float tone = fbm(w / 240.0) * 0.72 + vnoise(w / 26.0) * 0.2 + (hash(w) - 0.5) * 0.1 + 0.04;
	int top;
	int second;
	float margin;
	classify(warped(w), top, second, margin);
	vec3 c;
	if (top == CLIFF) {
		// The existing coast footprint already extends south by 144px.
		// Fill its entire exposed face instead of a 44px strip plus grey apron.
		float depth = 192.0;
		int cap_type = GRASS;
		for (int k = 1; k <= 16; k++) {
			int t2;
			int s2;
			float m2;
			classify(warped(w - vec2(0.0, float(k) * 12.0)), t2, s2, m2);
			if (t2 != CLIFF) {
				depth = float(k) * 12.0;
				float low = depth - 12.0;
				float high = depth;
				for (int refine = 0; refine < 3; refine++) {
					float middle = (low + high) * 0.5;
					int tm; int sm; float mm;
					classify(warped(w - vec2(0.0, middle)), tm, sm, mm);
					if (tm == CLIFF) { low = middle; } else { high = middle; }
				}
				depth = floor(high / art_px) * art_px;
				cap_type = t2;
				break;
			}
		}
		c = cliff_stone(w, depth, cap_type);
		if (depth <= 12.0) { c = paint(cap_type, w, tone) * 0.84; }
	} else {
		c = paint(top, w, tone);
		if (margin < 0.1) {
			bool low = top == DIRT || top == SAND;
			if (low && (second == GRASS || second == COBBLE || second == STONE)) {
				c *= margin < 0.05 ? 0.66 : 0.82;          // shaded rim where the ground drops
			} else if (top == GRASS && second != GRASS && margin < 0.05) {
				c = GRASS_P[5];                             // lit grass lip
			} else if (top == SANDSTONE && second == SAND && margin < 0.06) {
				c *= 0.75;
			}
		}
	}
	COLOR = vec4(paint_stairs(w, c) / 255.0, 1.0);
}
