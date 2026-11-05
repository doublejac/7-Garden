// 그림책 그림: 종이 위에 물감으로 칠한 것처럼 보이게.
// - blend_mul: 종이 위에 곱하기로 얹어서, 종이 결·얼룩·제본선 그늘이 그림 속까지 그대로 비침
// - 그림의 바탕색(paper)으로 나눠서, 바탕 부분은 정확히 흰색(=종이 그대로)이 됨 → 사각 테두리가 사라짐
// - 가장자리는 물감이 번진 것처럼 들쭉날쭉하게 흐려짐 (그림이 끝까지 칠해진 쪽도 자연스럽게)
shader_type canvas_item;
render_mode blend_mul;

uniform vec4 paper : source_color = vec4(0.992, 0.945, 0.875, 1.0);  // 그림 파일의 종이 바탕색
uniform float feather = 0.07;      // 가장자리 번짐 폭 (그림 폭 기준)
uniform float aspect = 0.7464;     // 높이 / 너비
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 c = clamp(t.rgb / paper.rgb, 0.0, 1.0);
	// modulate(찢긴 장의 바램)는 물감 부분에만. 종이 부분은 아래 종이의 바램이 그대로 비침
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c *= mix(COLOR.rgb, vec3(1.0), smoothstep(0.82, 1.0, lum));
	// 가장자리: 붓 자국처럼 들쭉날쭉한 경계 (흐릿한 번짐 대신 또렷하게), 경계 안쪽은 물감이 살짝 옅음
	vec2 q = vec2(UV.x, UV.y * aspect);
	float d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y) * aspect);
	float n = vnoise(q * 7.0) * 0.6 + vnoise(q * 24.0) * 0.28 + vnoise(q * 80.0) * 0.12;
	float edge = feather * (0.45 + (n - 0.5) * 1.1);
	float m = smoothstep(edge - 0.004, edge + 0.006, d);
	float wash = smoothstep(edge, edge + feather * 0.8, d);
	c = mix(mix(vec3(1.0), c, 0.72), c, wash);
	COLOR = vec4(mix(vec3(1.0), c, m), 1.0);
}
