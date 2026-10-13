extends TestCase
## Units and Kepler orbits: constants, the solver, and positions and
## velocities that obey the laws of motion.


func test_speed_of_light_in_au_per_year() -> void:
	assert_almost_eq(Units.C, 63241.077, 0.001)
	assert_almost_eq(Units.light_time_seconds(1.0), 499.005, 0.001, "light from 1 AU")


func test_kepler_equation_is_solved() -> void:
	for e: float in [0.0, 0.1, 0.5, 0.9, 0.99]:
		for k: int in 37:
			var m: float = -PI + TAU * k / 36.0
			var anomaly: float = Kepler.eccentric_anomaly(m, e)
			var residual: float = wrapf(anomaly - e * sin(anomaly) - m, -PI, PI)
			assert_almost_eq(residual, 0.0, 1e-12, "e=%s M=%s" % [e, m])


func test_circular_orbit_at_one_au_takes_one_year() -> void:
	var n: float = Kepler.mean_motion(1.0, 1.0)
	assert_almost_eq(Kepler.period_years(1.0, 1.0), 1.0, 1e-12)
	var state: PackedFloat64Array = Kepler.state_from_elements(1.0, 0.0, 0.0, 0.0, 0.0, 0.0, n)
	assert_almost_eq(state[0], 1.0, 1e-12, "x")
	assert_almost_eq(state[1], 0.0, 1e-12, "y")
	assert_almost_eq(state[4], TAU, 1e-9, "speed 2π AU/yr")


func test_eccentric_orbit_obeys_vis_viva_and_keeps_angular_momentum() -> void:
	var a: float = 2.0
	var e: float = 0.6
	var n: float = Kepler.mean_motion(a, 1.0)
	var momentum: float = NAN
	for k: int in 12:
		var s: PackedFloat64Array = Kepler.state_from_elements(a, e, 0.3, 1.1, 0.7, TAU * k / 12.0, n)
		var r: float = sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2])
		var v2: float = s[3] * s[3] + s[4] * s[4] + s[5] * s[5]
		assert_almost_eq(v2, Units.G * (2.0 / r - 1.0 / a), 1e-9, "vis-viva at step %d" % k)
		var hx: float = s[1] * s[5] - s[2] * s[4]
		var hy: float = s[2] * s[3] - s[0] * s[5]
		var hz: float = s[0] * s[4] - s[1] * s[3]
		var h: float = sqrt(hx * hx + hy * hy + hz * hz)
		if is_nan(momentum):
			momentum = h
		assert_almost_eq(h, momentum, 1e-9, "angular momentum at step %d" % k)


func test_equator_frame_is_orthonormal_and_points_to_the_pole() -> void:
	# Earth's pole is the celestial pole: in ecliptic coordinates (0, sin ε, cos ε).
	var f: PackedFloat64Array = KeplerOrbit.equator_frame(0.0, 90.0)
	var eps: float = deg_to_rad(Units.OBLIQUITY_J2000_DEG)
	assert_almost_eq(f[6], 0.0, 1e-12)
	assert_almost_eq(f[7], sin(eps), 1e-12)
	assert_almost_eq(f[8], cos(eps), 1e-12)
	for pole: Vector2 in [Vector2(257.311, -15.175), Vector2(40.589, 83.537), Vector2(132.993, -6.163)]:
		var g: PackedFloat64Array = KeplerOrbit.equator_frame(pole.x, pole.y)
		for i: int in 3:
			for j: int in 3:
				var dot: float = g[i * 3] * g[j * 3] + g[i * 3 + 1] * g[j * 3 + 1] + g[i * 3 + 2] * g[j * 3 + 2]
				assert_almost_eq(dot, 1.0 if i == j else 0.0, 1e-12, "axes %d·%d for pole %s" % [i, j, pole])


func test_drifting_elements_stop_drifting_far_from_the_epoch() -> void:
	var orbit: KeplerOrbit = KeplerOrbit.from_mean_longitude(1.0, 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 36000.0)
	orbit.e_rate = 0.01
	var far: Dictionary = orbit.elements_at(1.0e9)
	assert_almost_eq(far["e"], 0.2 + 0.01 * KeplerOrbit.DRIFT_LIMIT_CENTURIES, 1e-12, "eccentricity frozen")
	var state: PackedFloat64Array = orbit.state_at(1.0e9)
	assert_false(is_nan(state[0]) or is_inf(state[0]), "still a valid position a billion years on")
