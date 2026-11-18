shader_type canvas_item;
render_mode blend_mix;
// Lighting only. Source tiles contain flat local colour, never painted shadows.
void fragment() {
	vec4 local = texture(TEXTURE, UV);
	vec4 c = COLOR;
	if (TEXTURE_PIXEL_SIZE.x > 0.0038 && TEXTURE_PIXEL_SIZE.x < 0.0040) {
		c.rgb *= mix(0.88, 0.56, floor(UV.y * 8.0) / 7.0);
	} else if (distance(local.rgb, vec3(136.0,111.0,88.0)/255.0) < 0.008) {
		c.rgb *= 0.92;
	}
	COLOR = c;
}
