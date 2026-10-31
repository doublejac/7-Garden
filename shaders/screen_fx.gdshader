// 화면 전체 연출: 색채 상실(채도), 시야 상실(비네트).
// 화면 맨 위 CanvasLayer의 ColorRect에 씌운다.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float saturation : hint_range(0.0, 1.0) = 1.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(g), c.rgb, saturation);
	float d = distance(SCREEN_UV, vec2(0.5));
	col *= 1.0 - vignette * smoothstep(0.35, 0.75, d);
	COLOR = vec4(col, 1.0);
}
