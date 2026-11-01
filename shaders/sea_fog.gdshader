// sea_fog.gdshader – 화면 가장자리에 천천히 흐르는 바다 안개 (해무). strength 0이면 안 보임.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 fog_color : source_color = vec4(0.63, 0.67, 0.73, 1.0);
uniform float speed = 0.03;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}

void fragment() {
	float d = length((UV - 0.5) * vec2(1.6, 1.0));
	float edge = smoothstep(0.3, 0.95, d);
	float n = fbm(UV * 4.0 + vec2(TIME * speed, TIME * speed * 0.5));
	COLOR = vec4(fog_color.rgb, clamp(edge * (0.55 + 0.9 * n), 0.0, 1.0) * strength);
}
