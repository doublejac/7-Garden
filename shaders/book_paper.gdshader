// 그림책 종이: 종이 결(잔 얼룩·알갱이), 제본선 쪽 그늘, 가장자리 살짝 어두움.
// spine_side: 1 = 제본선이 왼쪽(오른쪽 쪽), -1 = 제본선이 오른쪽(왼쪽 쪽)
// overlay = true면 종이는 그리지 않고 그늘만 (그림·글 위에 덮어 제본선 쪽이 휘어 보이게)
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.99, 0.94, 0.87, 1.0);
uniform float spine_side = 1.0;
uniform bool overlay = false;
uniform float age : hint_range(0.0, 1.0) = 0.0;    // 누렇게 바램 (찢긴 장)
uniform vec2 size_px = vec2(590.0, 640.0);
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
	float d = spine_side > 0.0 ? UV.x : 1.0 - UV.x;          // 제본선에서 거리 (0~1)
	float spine = 1.0 - smoothstep(0.0, 0.14, d);            // 제본선 근처 그늘
	float outer = 1.0 - smoothstep(0.0, 0.025, 1.0 - d);     // 바깥 가장자리
	float tb = 1.0 - smoothstep(0.0, 0.02, min(UV.y, 1.0 - UV.y));
	if (overlay) {
		COLOR = vec4(0.18, 0.14, 0.1, spine * spine * 0.42);
	} else {
		vec2 px = UV * size_px;
		float grain = (hash(floor(px)) - 0.5) * 0.035;
		float cloud = (vnoise(px / 70.0) * 0.6 + vnoise(px / 23.0) * 0.4 - 0.5) * 0.05;
		vec3 c = base_color.rgb + grain + cloud;
		c = mix(c, c * vec3(0.93, 0.85, 0.7), age * (0.55 + 0.45 * vnoise(px / 120.0)));
		c *= 1.0 - spine * 0.16 - outer * 0.07 - tb * 0.05;
		COLOR = vec4(c, 1.0);
	}
}
