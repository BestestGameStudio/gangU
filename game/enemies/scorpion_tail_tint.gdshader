shader_type canvas_item;
uniform sampler2D tail_mask : filter_nearest, repeat_disable;
uniform vec2 mask_cell = vec2(0.0);
uniform float warning_strength : hint_range(0.0,1.0) = 0.0;
varying vec4 sprite_tint;
void vertex() { sprite_tint = COLOR; }
void fragment() {
 vec4 ink = texture(TEXTURE,UV);
 vec2 pixel = mod(floor(UV / TEXTURE_PIXEL_SIZE),vec2(128.0));
 float mask = texture(tail_mask,(mask_cell*128.0+pixel+0.5)/vec2(1024.0,256.0)).a;
 float light = max(ink.r,max(ink.g,ink.b));
 vec3 red = vec3(0.30+0.70*light,0.035+0.09*light,0.025+0.07*light);
 COLOR = sprite_tint * vec4(mix(ink.rgb,red,mask*warning_strength),ink.a);
}
