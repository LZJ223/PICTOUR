// 关卡层表面和空气共用 LightOccluder2D 的 SDF，保证遮挡边界一致。
// 从实体内部沿入射光方向寻找表面，避免最近边法线在中轴线上突变成三角亮斑。
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

float night_visibility(vec2 origin, vec2 light, float epsilon) {
	vec2 ray = light - origin;
	float total = length(ray);
	vec2 direction = ray / max(total, epsilon);
	float traveled = epsilon * 2.0;
	for (int i = 0; i < 64; i++) {
		if (traveled >= total - epsilon) { return 1.0; }
		float distance_to_surface = texture_sdf(origin + direction * traveled);
		if (distance_to_surface < epsilon * 0.5) { return 0.0; }
		traveled += max(distance_to_surface * 0.9, epsilon);
	}
	// 步数不足时不能当成已经抵达光源，以免细长遮挡物漏光。
	return 0.0;
}
