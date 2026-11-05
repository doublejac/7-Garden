// 백화증 안내의 흰 백합: fade(0~1)가 커질수록 꽃잎 가장자리부터 하얗게 바래며 흩어짐.
// 꽃 가운데(center)에서 먼 곳(꽃잎 끝·줄기 끝)부터 사라지고, 사라지는 경계는 하얗게 빛나며 알갱이처럼 부서짐.
// 배경이 검정이라 사라진 자리는 검정으로 칠함.
shader_type canvas_item;

uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.512, 0.494);   // 수술(꽃술)이 모이는 곳
uniform float reach = 0.37;          // 가운데에서 가장 먼 그림(꽃잎 끝·줄기 끝)까지 거리 (UV)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float flower = smoothstep(0.12, 0.45, dot(c, vec3(0.333)));     // 꽃(밝은 곳)만. 검은 배경·후광엔 효과 없음
	float r = distance(UV, center) / reach;                       // 0 = 꽃 가운데, 1 = 가장 바깥
	float n = vnoise(UV * 9.0) * 0.6 + vnoise(UV * 31.0) * 0.4;
	float v = r + (n - 0.5) * 0.3;
	float t = 1.1 - fade * 1.1;                                   // 이 값보다 바깥은 흩어짐
	float grain = (hash(floor(UV * 420.0)) - 0.5) * 0.06;         // 부서지는 알갱이
	float gone = step(t, v + grain);
	float edge = smoothstep(t - 0.12, t, v) * (1.0 - gone);       // 흩어지기 직전 띠: 하얗게 바램
	vec3 col = mix(c, vec3(1.0), edge * 0.85 * flower);
	// 흩어진 자리엔 꽃의 윤곽만 아주 희미하게 남음 (배경은 원래 검정 그대로)
	col = mix(col, c * mix(1.0, 0.1, flower), gone);
	col *= mix(1.0 - fade * 0.85, 1.0, flower);                  // 꽃 주위 은은한 빛도 꽃과 함께 사그라짐
	float dust = gone * flower * step(0.985, hash(floor(UV * 260.0) + floor(TIME * 2.0))) * smoothstep(t + 0.25, t, v) * 0.5;
	COLOR = vec4(col + vec3(dust), COLOR.a);
}
