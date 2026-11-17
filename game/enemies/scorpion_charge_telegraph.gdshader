shader_type canvas_item;
render_mode unshaded;
uniform vec2 lane_size = vec2(248.0,48.0);
uniform float progress : hint_range(0.0,1.0) = 0.0;
varying vec2 local_pixel;
void vertex() {
	local_pixel = VERTEX;
}
void fragment() {
	vec2 p = floor(local_pixel + vec2(0.0,lane_size.y*0.5));
	float d = min(min(p.y,lane_size.y-1.0-p.y),lane_size.x-1.0-p.x);
	float edge = 0.0;
	if (d < 1.0) { edge = 178.0; }
	else if (d < 2.0) { edge = 108.0; }
	else if (d < 3.0) { edge = 62.0; }
	else if (d < 4.0) { edge = 32.0; }
	else if (d < 5.0) { edge = 14.0; }
	else if (d < 6.0) { edge = 4.0; }
	float reach = lane_size.x*clamp(progress,0.0,1.0);
	float fill = p.x < reach ? floor(112.0*pow(1.0-p.x/max(1.0,reach),0.8)+0.5) : 0.0;
	float alpha = floor(edge+fill*(1.0-edge/255.0)+0.5)/255.0;
	COLOR = vec4(vec3(237.0,69.0,74.0)/255.0,alpha);
}
