// 색채 상실: 그림을 흑백으로 보여 준다 (실제 색은 그대로 둔 채 보이는 것만).
// amount 1 = 완전 흑백, 0 = 원래 색
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c.rgb, vec3(g), amount), c.a);
}
