// 沿入射方向找实体表面，避免最近边法线在物体中轴线形成三角亮斑。
vec3 night_entry_surface(vec2 origin, vec2 light, float epsilon, float max_depth) {
	vec2 direction = normalize(light - origin + vec2(0.000001));
	float traveled = 0.0;
	for (int i = 0; i < 24; i++) {
		vec2 point = origin + direction * traveled;
		float distance_to_surface = texture_sdf(point);
		if (distance_to_surface >= -epsilon) { return vec3(point, traveled); }
		traveled += max(-distance_to_surface * 0.9, epsilon);
		if (traveled > max_depth) { break; }
	}
	return vec3(origin, -1.0);
}
