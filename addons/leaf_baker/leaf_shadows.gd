@tool
extends RefCounted

const Profile = preload("res://addons/leaf_baker/leaf_profile.gd")


static func build(size: Vector2, radii: PackedFloat32Array, profile: Profile) -> Dictionary:
	var short_side := minf(size.x, size.y)
	var noise_amplitude := minf(profile.shadow_wobble / profile.pixels_per_unit, short_side * 0.005)
	var margin := minf(short_side * 0.02, 2.0 / profile.pixels_per_unit + noise_amplitude)
	var left_limit := radii[0] + margin
	var right_limit := size.x - radii[1] - margin
	var gap := minf(size.x * 0.05, (right_limit - left_limit) * 0.30)
	var first := clampf(size.x * profile.deep_boundary_ratio, left_limit, right_limit - gap)
	var second := clampf(size.x * profile.light_boundary_ratio, first + gap, right_limit)
	# Both endpoints must also fit the straight part of the lower edge when
	# independently randomized bottom corners are larger than the top corners.
	var lower_span := size.x - radii[2] - radii[3] - margin * 2.0
	second = minf(second, first + lower_span * 0.85)
	noise_amplitude = minf(noise_amplitude, (second - first) * 0.20)
	var travel := clampf(profile.shadow_bend_ratio * short_side, -size.y * 0.8, size.y * 0.8)
	travel = clampf(travel, radii[3] + margin - first, size.x - radii[2] - margin - second)
	var wavelength := profile.shadow_wavelength / profile.pixels_per_unit
	var left := _curve(first, size.y, travel, noise_amplitude, wavelength, profile.seed + 4001, profile.pixels_per_unit)
	var right := _curve(second, size.y, travel, noise_amplitude, wavelength, profile.seed + 8009, profile.pixels_per_unit)
	return {"left": left, "right": right, "size": size, "travel": travel}


static func _curve(start: float, height: float, travel: float, amplitude: float, wavelength: float, seed_value: int, density: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := PackedFloat32Array()
	for index in range(ceili(height / wavelength) + 2):
		noise.append(rng.randf_range(-1.0, 1.0))
	# Center = (start + sign(travel) * radius, 0). This constraint makes
	# dx/dy = 0 exactly where the circle meets the horizontal upper surface.
	var radius := INF if absf(travel) < 0.000001 else (height * height + travel * travel) / (2.0 * absf(travel))
	var curve := {
		"start": start, "height": height, "travel": travel, "radius": radius,
		"amplitude": amplitude, "wavelength": wavelength, "noise": noise,
		"fade_length": minf(height * 0.25, wavelength * 2.0),
	}
	var steps := clampi(ceili(height / minf(3.0 / density, wavelength * 0.25)), 16, 16384)
	var points := PackedVector2Array()
	var slopes := PackedFloat32Array()
	for index in range(steps + 1):
		var y := height * float(index) / steps
		var value := value_and_slope(curve, y)
		points.append(Vector2(value.x, y))
		slopes.append(value.y)
	curve["points"] = points
	curve["slopes"] = slopes
	return curve


## Returns (x, dx/dy). Both the noise envelope and its derivative vanish
## at y=0; hand-drawn variation therefore preserves the vertical tangent.
static func value_and_slope(curve: Dictionary, y: float) -> Vector2:
	y = clampf(y, 0.0, curve.height)
	var x: float = curve.start
	var slope := 0.0
	var radius: float = curve.radius
	if is_finite(radius):
		var root := sqrt(maxf(0.000001, radius * radius - y * y))
		x += signf(curve.travel) * y * y / (radius + root)
		slope = signf(curve.travel) * y / root
	var wavelength: float = curve.wavelength
	var phase := y / wavelength
	var index := floori(phase)
	var fraction := phase - index
	var smooth := fraction * fraction * (3.0 - 2.0 * fraction)
	var samples: PackedFloat32Array = curve.noise
	var noise := lerpf(samples[index], samples[index + 1], smooth)
	var noise_slope := (samples[index + 1] - samples[index]) * 6.0 * fraction * (1.0 - fraction) / wavelength
	var fade_length: float = curve.fade_length
	var t := clampf(y / fade_length, 0.0, 1.0)
	var envelope := t * t * (3.0 - 2.0 * t)
	var envelope_slope := 6.0 * t * (1.0 - t) / fade_length if y < fade_length else 0.0
	var amplitude: float = curve.amplitude
	return Vector2(x + amplitude * envelope * noise, slope + amplitude * (envelope_slope * noise + envelope * noise_slope))


static func commands(curve: Dictionary, reverse: bool = false) -> String:
	var points: PackedVector2Array = curve.points
	var slopes: PackedFloat32Array = curve.slopes
	var parts := PackedStringArray()
	for step in range(points.size() - 1):
		var index := points.size() - 1 - step if reverse else step
		var next := index - 1 if reverse else index + 1
		var a := points[index]
		var b := points[next]
		var dy := (b.y - a.y) / 3.0
		var control_a := a + Vector2(slopes[index] * dy, dy)
		var control_b := b - Vector2(slopes[next] * dy, dy)
		parts.append("C %.6f %.6f %.6f %.6f %.6f %.6f" % [control_a.x, control_a.y, control_b.x, control_b.y, b.x, b.y])
	return " ".join(parts)


static func region_paths(shadow: Dictionary, padding: float) -> PackedStringArray:
	var height: float = shadow.size.y
	var left: Dictionary = shadow.left
	var right: Dictionary = shadow.right
	var left_bottom: float = left.points[-1].x
	var right_bottom: float = right.points[-1].x
	var deep := "M %.6f %.6f L %.6f %.6f L %.6f 0 %s L %.6f %.6f L %.6f %.6f Z" % [
		-padding, -padding, left.start, -padding, left.start, commands(left),
		left_bottom, height + padding, -padding, height + padding,
	]
	var light := "M %.6f %.6f L %.6f %.6f L %.6f 0 %s L %.6f %.6f L %.6f %.6f L %.6f %.6f %s L %.6f %.6f Z" % [
		left.start, -padding, right.start, -padding, right.start, commands(right),
		right_bottom, height + padding, left_bottom, height + padding, left_bottom, height,
		commands(left, true), left.start, -padding,
	]
	return PackedStringArray([deep, light])
