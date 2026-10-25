// The native gravity kernel. It mirrors src/sim/gravity_core_script.gd line by
// line (same steps, same decisions, same order of floating-point operations),
// so the two kernels agree; the GDScript file explains the physics.

#include "gravity_core.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>

using namespace godot;

namespace {

// Must match src/sim/gravity.gd and src/sim/units.gd.
constexpr int32_t RAILS = 0;
constexpr int32_t FREE = 1;
constexpr int32_t GHOST = 2;
constexpr int32_t GONE = 3;
constexpr int32_t ASLEEP = 0;
constexpr int32_t AWAKE = 1;
constexpr int32_t P_GONE = 2;
constexpr int64_t REACHED = 0;
constexpr int64_t EVENTS = 1;
constexpr int64_t BUDGET = 2;
constexpr int64_t ES = 12;
constexpr double ETA = 0.025;
constexpr double UNIT = 1.0 / 1099511627776.0;
constexpr int64_t MAX_LEVEL = 42;
constexpr int64_t PARTICLE_MAX_LEVEL = 16;
constexpr double WAKE_HILL = 3.0;
constexpr double WAKE_REACH = 0.5;
constexpr double SLEEP_FACTOR = 2.0;
constexpr double SLEEP_REACH = 0.75;
constexpr double SLEEP_HILL_SHARE = 0.4;
constexpr double WAKE_HILL_SHARE = 0.5;
constexpr double FRONT_WAKE_RATIO = 1e-6;
constexpr int64_t MAINTENANCE_STEPS = 64;
constexpr double RAILS_MAX_MASS = 0.01;
constexpr double MAX_CHECK_INTERVAL = 0.25;
constexpr int64_t SLEEP_CHECK_STEPS = 32;
constexpr double WAKE_TIDAL = 0.01;
constexpr double LN2 = 0.6931471805599453;
constexpr double PI = 3.1415926535897932384626433833;
constexpr double G = 4.0 * PI * PI;
constexpr double KEPLER_TOLERANCE = 1e-14;
constexpr int KEPLER_ITERATIONS = 64;
constexpr double APPROX_EPSILON = 0.00001; // Godot's CMP_EPSILON
const double INF = std::numeric_limits<double>::infinity();
const double NOT_A_NUMBER = std::numeric_limits<double>::quiet_NaN();

// Godot's MIN, MAX and CLAMP, so ties and order match GDScript exactly.
inline double minf(double a, double b) { return a < b ? a : b; }
inline double maxf(double a, double b) { return a > b ? a : b; }
inline double clampf(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline int64_t clampi(int64_t v, int64_t lo, int64_t hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double signf(double v) { return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0); }
inline int64_t floori(double v) { return (int64_t)std::floor(v); }

double step_size(int64_t level) { return UNIT * std::pow(2.0, (double)level); }

bool is_equal_approx(double a, double b) {
	if (a == b) {
		return true;
	}
	double tolerance = APPROX_EPSILON * std::fabs(a);
	if (tolerance < APPROX_EPSILON) {
		tolerance = APPROX_EPSILON;
	}
	return std::fabs(a - b) < tolerance;
}

double wrapf(double value, double min, double max) {
	double range = max - min;
	if (std::fabs(range) < APPROX_EPSILON) {
		return min;
	}
	double result = value - (range * std::floor((value - min) / range));
	if (is_equal_approx(result, max)) {
		return min;
	}
	return result;
}

double eccentric_anomaly(double mean_anomaly, double e) {
	double m = wrapf(mean_anomaly, -PI, PI);
	double anomaly = e < 0.8 ? m : PI * signf(m);
	for (int i = 0; i < KEPLER_ITERATIONS; i++) {
		double step = (anomaly - e * std::sin(anomaly) - m) / (1.0 - e * std::cos(anomaly));
		anomaly -= step;
		if (std::fabs(step) < KEPLER_TOLERANCE) {
			break;
		}
	}
	return anomaly;
}

double hyperbolic_anomaly(double mean_anomaly, double e) {
	double anomaly = 0.0;
	if (mean_anomaly != 0.0) {
		anomaly = signf(mean_anomaly) * std::log(2.0 * std::fabs(mean_anomaly) / e + 1.8);
	}
	for (int i = 0; i < KEPLER_ITERATIONS; i++) {
		double step = (e * std::sinh(anomaly) - anomaly - mean_anomaly) / (e * std::cosh(anomaly) - 1.0);
		anomaly -= step;
		if (std::fabs(step) < KEPLER_TOLERANCE * maxf(1.0, std::fabs(anomaly))) {
			break;
		}
	}
	return anomaly;
}

// Kepler.elements_from_state: false for a radial (degenerate) orbit.
bool elements_from_state(double rx, double ry, double rz, double vx, double vy, double vz, double mu, double t0, double out[ES]) {
	double r = std::sqrt(rx * rx + ry * ry + rz * rz);
	double v2 = vx * vx + vy * vy + vz * vz;
	double hx = ry * vz - rz * vy;
	double hy = rz * vx - rx * vz;
	double hz = rx * vy - ry * vx;
	double h = std::sqrt(hx * hx + hy * hy + hz * hz);
	if (r <= 0.0 || mu <= 0.0 || h <= 1e-9 * r * std::sqrt(v2 + mu / r)) {
		return false;
	}
	double energy = 0.5 * v2 - mu / r;
	if (std::fabs(energy) < 1e-12 * mu / r) {
		energy = -1e-12 * mu / r;
	}
	double a = -mu / (2.0 * energy);
	double ex = (vy * hz - vz * hy) / mu - rx / r;
	double ey = (vz * hx - vx * hz) / mu - ry / r;
	double ez = (vx * hy - vy * hx) / mu - rz / r;
	double e = std::sqrt(ex * ex + ey * ey + ez * ez);
	if (a > 0.0 && e >= 1.0) {
		e = 1.0 - 1e-12;
	} else if (a < 0.0 && e <= 1.0) {
		e = 1.0 + 1e-12;
	}
	double px = rx / r;
	double py = ry / r;
	double pz = rz / r;
	if (e > 1e-11) {
		px = ex / e;
		py = ey / e;
		pz = ez / e;
	}
	double qx = (hy * pz - hz * py) / h;
	double qy = (hz * px - hx * pz) / h;
	double qz = (hx * py - hy * px) / h;
	double size_p = std::fabs(a);
	double size_q = std::fabs(a) * std::sqrt(std::fabs(1.0 - e * e));
	double rp = rx * px + ry * py + rz * pz;
	double rq = rx * qx + ry * qy + rz * qz;
	double mean_anomaly;
	if (a > 0.0) {
		double anomaly = std::atan2(rq / size_q, rp / a + e);
		mean_anomaly = anomaly - e * std::sin(anomaly);
	} else {
		double anomaly = std::asinh(rq / size_q);
		mean_anomaly = e * std::sinh(anomaly) - anomaly;
	}
	out[0] = a;
	out[1] = e;
	out[2] = std::sqrt(mu / std::fabs(a * a * a));
	out[3] = mean_anomaly;
	out[4] = t0;
	out[5] = px * size_p;
	out[6] = py * size_p;
	out[7] = pz * size_p;
	out[8] = qx * size_q;
	out[9] = qy * size_q;
	out[10] = qz * size_q;
	out[11] = mu;
	return true;
}

// Kepler.state_from_element_set.
void state_from_element_set(const double *elements, double t, double out[6]) {
	double a = elements[0];
	double e = elements[1];
	double n = elements[2];
	double mean_anomaly = elements[3] + n * (t - elements[4]);
	double cp, cq, rate_p, rate_q;
	if (a > 0.0) {
		double anomaly = eccentric_anomaly(mean_anomaly, e);
		double c = std::cos(anomaly);
		double s = std::sin(anomaly);
		double rate = n / (1.0 - e * c);
		cp = c - e;
		cq = s;
		rate_p = -s * rate;
		rate_q = c * rate;
	} else {
		double anomaly = hyperbolic_anomaly(mean_anomaly, e);
		double ch = std::cosh(anomaly);
		double sh = std::sinh(anomaly);
		double rate = n / (e * ch - 1.0);
		cp = e - ch;
		cq = sh;
		rate_p = -sh * rate;
		rate_q = ch * rate;
	}
	for (int k = 0; k < 3; k++) {
		double p = elements[5 + k];
		double q = elements[8 + k];
		out[k] = cp * p + cq * q;
		out[k + 3] = rate_p * p + rate_q * q;
	}
}

// Closest approach of two points moving in straight lines over a step.
void closest(double d0x, double d0y, double d0z, double d1x, double d1y, double d1z, double &dist2, double &u) {
	double ex = d1x - d0x;
	double ey = d1y - d0y;
	double ez = d1z - d0z;
	double ee = ex * ex + ey * ey + ez * ez;
	u = 0.0;
	if (ee > 0.0) {
		u = clampf(-(d0x * ex + d0y * ey + d0z * ez) / ee, 0.0, 1.0);
	}
	double cx = d0x + u * ex;
	double cy = d0y + u * ey;
	double cz = d0z + u * ez;
	dist2 = cx * cx + cy * cy + cz * cz;
}

template <typename T>
void read_array(Object *o, const char *name, std::vector<double> &out) {
	T array = o->get(name);
	out.resize(array.size());
	if (array.size() > 0) {
		std::copy(array.ptr(), array.ptr() + array.size(), out.begin());
	}
}

void read_doubles(Object *o, const char *name, std::vector<double> &out) {
	PackedFloat64Array array = o->get(name);
	out.resize(array.size());
	if (array.size() > 0) {
		std::copy(array.ptr(), array.ptr() + array.size(), out.begin());
	}
}

void read_ints(Object *o, const char *name, std::vector<int32_t> &out) {
	PackedInt32Array array = o->get(name);
	out.resize(array.size());
	if (array.size() > 0) {
		std::copy(array.ptr(), array.ptr() + array.size(), out.begin());
	}
}

PackedFloat64Array to_packed(const std::vector<double> &v) {
	PackedFloat64Array array;
	array.resize(v.size());
	if (!v.empty()) {
		std::copy(v.begin(), v.end(), array.ptrw());
	}
	return array;
}

PackedInt32Array to_packed(const std::vector<int32_t> &v) {
	PackedInt32Array array;
	array.resize(v.size());
	if (!v.empty()) {
		std::copy(v.begin(), v.end(), array.ptrw());
	}
	return array;
}

bool contains(const std::vector<int32_t> &v, int32_t value) {
	return std::find(v.begin(), v.end(), value) != v.end();
}

int64_t now_usec() {
	return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

} // namespace

// --- State ------------------------------------------------------------------

void GravityState::load(Object *o) {
	time = o->get("time");
	level = o->get("level");
	level_up = o->get("level_up");
	step_count = o->get("step_count");
	g_scale = o->get("g_scale");
	collisions_enabled = o->get("collisions_enabled");
	acc_valid = o->get("acc_valid");
	pristine = o->get("pristine");
	rails_tau = o->get("rails_tau");
	read_doubles(o, "pos", pos);
	read_doubles(o, "vel", vel);
	read_doubles(o, "acc", acc);
	read_doubles(o, "mass", mass);
	read_doubles(o, "radius", radius);
	read_doubles(o, "hill", hill);
	read_doubles(o, "rail", rail);
	read_ints(o, "mode", mode);
	read_ints(o, "parent", parent);
	read_ints(o, "delta_body", delta_body);
	read_ints(o, "delta_front", delta_front);
	read_doubles(o, "delta_mass", delta_mass);
	read_doubles(o, "front_origin", front_origin);
	read_doubles(o, "front_time", front_time);
	read_doubles(o, "front_speed", front_speed);
	read_ints(o, "p_mode", p_mode);
	read_ints(o, "p_primary", p_primary);
	read_ints(o, "p_level", p_level);
	read_doubles(o, "p_elem", p_elem);
	read_doubles(o, "p_pos", p_pos);
	read_doubles(o, "p_vel", p_vel);
	read_doubles(o, "p_acc", p_acc);
	read_doubles(o, "p_last", p_last);
	read_doubles(o, "p_next", p_next);
	read_doubles(o, "p_radius", p_radius);
	read_doubles(o, "p_tau", p_tau);
	read_doubles(o, "view_pos", view_pos);
	read_doubles(o, "view_vel", view_vel);
	read_doubles(o, "p_view", p_view);
}

void GravityState::store(Object *o) const {
	o->set("time", time);
	o->set("level", level);
	o->set("level_up", level_up);
	o->set("step_count", step_count);
	o->set("acc_valid", acc_valid);
	o->set("pos", to_packed(pos));
	o->set("vel", to_packed(vel));
	o->set("acc", to_packed(acc));
	o->set("hill", to_packed(hill));
	o->set("rail", to_packed(rail));
	o->set("mode", to_packed(mode));
	o->set("parent", to_packed(parent));
	o->set("p_mode", to_packed(p_mode));
	o->set("p_primary", to_packed(p_primary));
	o->set("p_level", to_packed(p_level));
	o->set("p_elem", to_packed(p_elem));
	o->set("p_pos", to_packed(p_pos));
	o->set("p_vel", to_packed(p_vel));
	o->set("p_acc", to_packed(p_acc));
	o->set("p_last", to_packed(p_last));
	o->set("p_next", to_packed(p_next));
	o->set("p_tau", to_packed(p_tau));
}

void GravityState::store_view(Object *o) const {
	o->set("view_pos", to_packed(view_pos));
	o->set("view_vel", to_packed(view_vel));
	o->set("p_view", to_packed(p_view));
}

// --- Bindings ---------------------------------------------------------------

void GravityCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("advance", "state", "target", "max_steps", "max_usec"), &GravityCore::advance);
	ClassDB::bind_method(D_METHOD("preview", "state", "time"), &GravityCore::preview);
	ClassDB::bind_method(D_METHOD("field_at", "state", "points", "time"), &GravityCore::field_at);
	ClassDB::bind_method(D_METHOD("predict", "state", "bodies", "particles", "duration", "samples", "max_steps"), &GravityCore::predict);
	ClassDB::bind_method(D_METHOD("schedule_front", "state", "front"), &GravityCore::schedule_front);
}

Dictionary GravityCore::advance(Object *p_state, double p_target, int64_t p_max_steps, int64_t p_max_usec) {
	GravityState s;
	s.load(p_state);
	Dictionary result = run(s, p_target, p_max_steps, p_max_usec);
	s.store(p_state);
	return result;
}

void GravityCore::preview(Object *p_state, double p_time) {
	GravityState s;
	s.load(p_state);
	preview_state(s, p_time);
	s.store_view(p_state);
}

PackedFloat64Array GravityCore::field_at(Object *p_state, const PackedFloat64Array &p_points, double p_time) {
	GravityState s;
	s.load(p_state);
	build_delta_index(s);
	fronts_reach(s, p_time);
	PackedFloat64Array out;
	out.resize(p_points.size());
	int64_t count = p_points.size() / 3;
	const double *points = p_points.ptr();
	for (int64_t q = 0; q < count; q++) {
		int64_t b = q * 3;
		double a[4];
		pull_at(s, points[b], points[b + 1], points[b + 2], -1, false, 0.0, 0.0, 0.0, a);
		out.set(b, a[0]);
		out.set(b + 1, a[1]);
		out.set(b + 2, a[2]);
	}
	return out;
}

PackedFloat64Array GravityCore::predict(Object *p_state, const PackedInt32Array &p_bodies, const PackedInt32Array &p_particles,
		double p_duration, int64_t p_samples, int64_t p_max_steps) {
	GravityState s;
	s.load(p_state);
	s.collisions_enabled = false;
	s.acc_valid = false;
	int64_t body_count = p_bodies.size();
	int64_t tracked = body_count + p_particles.size();
	PackedFloat64Array out;
	out.resize(tracked * p_samples * 3);
	if (out.size() > 0) {
		std::fill(out.ptrw(), out.ptrw() + out.size(), NOT_A_NUMBER);
	}
	std::vector<uint8_t> stopped(tracked, 0);
	double start = s.time;
	int64_t samples = std::max<int64_t>(p_samples, 1);
	int64_t budget = std::max<int64_t>((int64_t)(p_max_steps / (double)samples), 4);
	double *o = out.size() > 0 ? out.ptrw() : nullptr;
	for (int64_t k = 0; k < p_samples; k++) {
		double target = start + p_duration * (k + 1) / p_samples;
		Dictionary result = run(s, target, budget, (int64_t)1 << 30);
		if ((int64_t)result["status"] == BUDGET) {
			target = s.time;
		}
		preview_state(s, target);
		for (int64_t q = 0; q < tracked; q++) {
			if (stopped[q]) {
				continue;
			}
			double x, y, z;
			int64_t skip = -1;
			if (q < body_count) {
				int64_t b = p_bodies[q] * 3;
				x = s.view_pos[b];
				y = s.view_pos[b + 1];
				z = s.view_pos[b + 2];
				skip = p_bodies[q];
			} else {
				int64_t p = p_particles[q - body_count];
				if (s.p_mode[p] == P_GONE) {
					stopped[q] = 1;
					continue;
				}
				x = s.p_view[p * 3];
				y = s.p_view[p * 3 + 1];
				z = s.p_view[p * 3 + 2];
			}
			if (touches_body(s, x, y, z, skip)) {
				stopped[q] = 1;
			}
			int64_t at = (q * p_samples + k) * 3;
			o[at] = x;
			o[at + 1] = y;
			o[at + 2] = z;
		}
	}
	return out;
}

void GravityCore::schedule_front(Object *p_state, int64_t p_front) {
	GravityState s;
	s.load(p_state);
	build_delta_index(s);
	for (int64_t p = 0; p < s.particles(); p++) {
		if (s.p_mode[p] != ASLEEP) {
			continue;
		}
		double arrival = significant_arrival(s, p, p_front);
		if (!std::isnan(arrival) && arrival < s.p_next[p]) {
			s.p_next[p] = maxf(arrival, s.time);
		}
	}
	p_state->set("p_next", to_packed(s.p_next));
}

// --- Steps ------------------------------------------------------------------

Dictionary GravityCore::run(GravityState &s, double p_target, int64_t p_max_steps, int64_t p_max_usec) {
	int64_t started = now_usec();
	PackedInt32Array collisions;
	PackedInt32Array impacts;
	PackedFloat64Array impact_data;
	int64_t status = REACHED;
	int64_t steps = 0;
	woken = 0;
	slept = 0;
	prepare(s);
	build_queue(s, p_target);
	while (true) {
		double h = step_size(s.level);
		if (s.time + h > p_target) {
			break;
		}
		step(s, h, collisions, impacts, impact_data);
		steps += 1;
		run_checks(s);
		if (s.step_count % MAINTENANCE_STEPS == 0 && maintain(s)) {
			refresh_accelerations(s);
		}
		if (!collisions.is_empty() || !impacts.is_empty()) {
			status = EVENTS;
			break;
		}
		if (steps >= p_max_steps || (steps % 8 == 0 && now_usec() - started > p_max_usec)) {
			if (s.time + step_size(s.level) <= p_target) {
				status = BUDGET;
			}
			break;
		}
	}
	Dictionary result;
	result["status"] = status;
	result["steps"] = steps;
	result["collisions"] = collisions;
	result["impacts"] = impacts;
	result["impact_data"] = impact_data;
	result["woken"] = woken;
	result["slept"] = slept;
	return result;
}

void GravityCore::preview_state(GravityState &s, double t) {
	int64_t n = s.n();
	int64_t count = s.particles();
	s.view_pos.resize(n * 3);
	s.view_vel.resize(n * 3);
	s.p_view.resize(count * 3);
	if (!s.pristine) {
		double delta = t - s.time;
		double half = 0.5 * delta * delta;
		for (int64_t i = 0; i < n; i++) {
			int64_t b = i * 3;
			if (s.mode[i] == FREE || s.mode[i] == GHOST) {
				for (int k = 0; k < 3; k++) {
					s.view_pos[b + k] = s.pos[b + k] + s.vel[b + k] * delta + s.acc[b + k] * half;
					s.view_vel[b + k] = s.vel[b + k] + s.acc[b + k] * delta;
				}
			} else if (s.mode[i] == GONE) {
				for (int k = 0; k < 3; k++) {
					s.view_pos[b + k] = s.pos[b + k];
					s.view_vel[b + k] = s.vel[b + k];
				}
			}
		}
		placed.assign(n, 0);
		for (int64_t i = 0; i < n; i++) {
			if (s.mode[i] == RAILS) {
				place_one(s, i, t, s.view_pos, s.view_vel);
			}
		}
	}
	const double *elements = s.p_elem.data();
	for (int64_t p = 0; p < count; p++) {
		int64_t b = p * 3;
		int32_t mode = s.p_mode[p];
		if (mode == AWAKE) {
			double since = t - s.p_last[p];
			double half_since = 0.5 * since * since;
			for (int k = 0; k < 3; k++) {
				s.p_view[b + k] = s.p_pos[b + k] + s.p_vel[b + k] * since + s.p_acc[b + k] * half_since;
			}
		} else if (mode == ASLEEP) {
			int64_t primary = s.p_primary[p];
			int64_t e_off = p * ES;
			double a = elements[e_off];
			double e = elements[e_off + 1];
			double anomaly_mean = elements[e_off + 3] + elements[e_off + 2] * (t - elements[e_off + 4]);
			double cp, cq;
			if (a > 0.0) {
				double anomaly = eccentric_anomaly(anomaly_mean, e);
				cp = std::cos(anomaly) - e;
				cq = std::sin(anomaly);
			} else {
				double anomaly = hyperbolic_anomaly(anomaly_mean, e);
				cp = e - std::cosh(anomaly);
				cq = std::sinh(anomaly);
			}
			int64_t pb = primary * 3;
			s.p_view[b] = s.view_pos[pb] + cp * elements[e_off + 5] + cq * elements[e_off + 8];
			s.p_view[b + 1] = s.view_pos[pb + 1] + cp * elements[e_off + 6] + cq * elements[e_off + 9];
			s.p_view[b + 2] = s.view_pos[pb + 2] + cp * elements[e_off + 7] + cq * elements[e_off + 10];
		}
	}
}

void GravityCore::prepare(GravityState &s) {
	int64_t n = s.n();
	if ((int64_t)s.hill.size() != n) {
		s.hill.assign(n, INF);
	}
	if (s.p_next.size() != s.p_mode.size()) {
		size_t old = s.p_next.size();
		s.p_next.resize(s.p_mode.size());
		for (size_t p = old; p < s.p_mode.size(); p++) {
			s.p_next[p] = s.time;
		}
	}
	build_delta_index(s);
	if (!s.acc_valid) {
		maintain(s);
		refresh_accelerations(s);
		s.acc_valid = true;
	}
	for (int64_t p = 0; p < s.particles(); p++) {
		if (s.p_mode[p] == AWAKE && s.p_level[p] < 0) {
			lower_level(s, start_particle(s, p));
		}
	}
	if (s.level < 0) {
		refresh_accelerations(s);
	}
}

void GravityCore::refresh_accelerations(GravityState &s) {
	place_rails(s, s.time);
	double tau = body_forces(s, s.time);
	int64_t n3 = s.n() * 3;
	for (int64_t k = 0; k < n3; k++) {
		s.acc[k] = new_acc[k];
	}
	choose_level(s, minf(tau, particle_tau(s)), s.level < 0);
}

void GravityCore::step(GravityState &s, double h, PackedInt32Array &collisions, PackedInt32Array &impacts,
		PackedFloat64Array &impact_data) {
	int64_t n = s.n();
	double *pos = s.pos.data();
	double *vel = s.vel.data();
	double *acc = s.acc.data();
	prev = s.pos;
	double half = 0.5 * h * h;
	for (int64_t i = 0; i < n; i++) {
		int32_t m = s.mode[i];
		if (m == FREE || m == GHOST) {
			int64_t b = i * 3;
			pos[b] += vel[b] * h + acc[b] * half;
			pos[b + 1] += vel[b + 1] * h + acc[b + 1] * half;
			pos[b + 2] += vel[b + 2] * h + acc[b + 2] * half;
		}
	}
	double t1 = s.time + h;
	place_rails(s, t1);
	double tau = body_forces(s, t1);
	double half_h = 0.5 * h;
	for (int64_t i = 0; i < n; i++) {
		int32_t m = s.mode[i];
		if (m == FREE || m == GHOST) {
			int64_t b = i * 3;
			for (int k = 0; k < 3; k++) {
				vel[b + k] += (acc[b + k] + new_acc[b + k]) * half_h;
				acc[b + k] = new_acc[b + k];
			}
		}
	}
	s.time = t1;
	s.step_count += 1;
	if (s.collisions_enabled) {
		sweep_bodies(s, collisions);
	}
	tau = minf(tau, step_particles(s, h, impacts, impact_data));
	choose_level(s, tau, false);
}

void GravityCore::choose_level(GravityState &s, double tau, bool reset) {
	int64_t want = MAX_LEVEL;
	if (tau > 0.0 && tau < INF) {
		want = clampi(floori(std::log(ETA * tau / UNIT) / LN2), 0, MAX_LEVEL);
	}
	if (reset || want < s.level) {
		s.level = want;
		s.level_up = 0;
	} else if (want > s.level) {
		s.level_up += 1;
		if (s.level_up >= 4) {
			s.level += 1;
			s.level_up = 0;
		}
	} else {
		s.level_up = 0;
	}
}

void GravityCore::lower_level(GravityState &s, double tau) {
	if (tau > 0.0 && tau < INF) {
		int64_t want = clampi(floori(std::log(ETA * tau / UNIT) / LN2), 0, MAX_LEVEL);
		if (want < s.level) {
			s.level = want;
			s.level_up = 0;
		}
	}
}

double GravityCore::particle_tau(const GravityState &s) const {
	double tau = INF;
	for (int64_t p = 0; p < s.particles(); p++) {
		if (s.p_mode[p] == AWAKE) {
			tau = minf(tau, s.p_tau[p]);
		}
	}
	return tau;
}

// --- Forces -----------------------------------------------------------------

void GravityCore::build_delta_index(const GravityState &s) {
	int64_t n = s.n();
	delta_start.assign(n + 1, 0);
	int64_t count = s.delta_body.size();
	for (int64_t d = 0; d < count; d++) {
		delta_start[s.delta_body[d] + 1] += 1;
	}
	for (int64_t i = 0; i < n; i++) {
		delta_start[i + 1] += delta_start[i];
	}
	sorted_front.resize(count);
	sorted_mass.resize(count);
	std::vector<int32_t> fill = delta_start;
	for (int64_t d = 0; d < count; d++) {
		int32_t at = fill[s.delta_body[d]];
		fill[s.delta_body[d]] += 1;
		sorted_front[at] = s.delta_front[d];
		sorted_mass[at] = s.delta_mass[d];
	}
}

void GravityCore::fronts_reach(const GravityState &s, double t) {
	int64_t count = s.front_time.size();
	reach2.resize(count);
	for (int64_t f = 0; f < count; f++) {
		double speed = s.front_speed[f];
		if (std::isinf(speed)) {
			reach2[f] = INF;
		} else {
			double reach = maxf(0.0, (t - s.front_time[f]) * speed);
			reach2[f] = reach * reach;
		}
	}
}

int64_t GravityCore::mask_at(const GravityState &s, double x, double y, double z) const {
	int64_t mask = 0;
	const double *origin = s.front_origin.data();
	for (size_t f = 0; f < reach2.size(); f++) {
		double dx = x - origin[f * 3];
		double dy = y - origin[f * 3 + 1];
		double dz = z - origin[f * 3 + 2];
		if (dx * dx + dy * dy + dz * dz <= reach2[f]) {
			mask |= (int64_t)1 << f;
		}
	}
	return mask;
}

double GravityCore::felt_mass(const GravityState &s, int64_t j, int64_t mask) const {
	double m = s.mass[j];
	for (int32_t d = delta_start[j]; d < delta_start[j + 1]; d++) {
		if (mask & ((int64_t)1 << sorted_front[d])) {
			m += sorted_mass[d];
		}
	}
	return m;
}

double GravityCore::body_forces(GravityState &s, double t) {
	int64_t n = s.n();
	new_acc.assign(n * 3, 0.0);
	fronts_reach(s, t);
	const double *pos = s.pos.data();
	const double *vel = s.vel.data();
	const double *mass = s.mass.data();
	const double *radius = s.radius.data();
	const int32_t *mode = s.mode.data();
	double g = G * s.g_scale;
	bool soften = !s.collisions_enabled;
	bool simple = s.delta_body.empty();
	double tau2 = INF;
	for (int64_t i = 0; i < n; i++) {
		int32_t mi = mode[i];
		if (mi != FREE && mi != GHOST) {
			continue;
		}
		int64_t bi = i * 3;
		double xi = pos[bi];
		double yi = pos[bi + 1];
		double zi = pos[bi + 2];
		int64_t mask = simple ? 0 : mask_at(s, xi, yi, zi);
		double ax = 0.0;
		double ay = 0.0;
		double az = 0.0;
		for (int64_t j = 0; j < n; j++) {
			if (j == i) {
				continue;
			}
			int32_t mj = mode[j];
			if (mj == GONE || (mi == GHOST && mj == GHOST)) {
				continue;
			}
			double m = simple ? mass[j] : felt_mass(s, j, mask);
			if (m == 0.0) {
				continue;
			}
			int64_t bj = j * 3;
			double dx = pos[bj] - xi;
			double dy = pos[bj + 1] - yi;
			double dz = pos[bj + 2] - zi;
			double r2 = dx * dx + dy * dy + dz * dz;
			if (soften || mi == GHOST) {
				double soft = radius[i] + radius[j];
				r2 += soft * soft;
			}
			double r = std::sqrt(r2);
			double f = g * m / (r2 * r);
			ax += f * dx;
			ay += f * dy;
			az += f * dz;
			if (mi == FREE && mj != GHOST) {
				double orbit2 = r2 * r / (g * (m + maxf(mass[i], 0.0)));
				if (orbit2 < tau2) {
					tau2 = orbit2;
				}
				double dvx = vel[bj] - vel[bi];
				double dvy = vel[bj + 1] - vel[bi + 1];
				double dvz = vel[bj + 2] - vel[bi + 2];
				double v2 = dvx * dvx + dvy * dvy + dvz * dvz;
				if (v2 > 0.0 && r2 / v2 < tau2) {
					tau2 = r2 / v2;
				}
			}
		}
		new_acc[bi] = ax;
		new_acc[bi + 1] = ay;
		new_acc[bi + 2] = az;
	}
	return std::sqrt(tau2);
}

void GravityCore::pull_at(const GravityState &s, double x, double y, double z, int64_t skip, bool soften, double vx,
		double vy, double vz, double out[4]) const {
	int64_t n = s.n();
	const double *pos = s.pos.data();
	const double *vel = s.vel.data();
	double g = G * s.g_scale;
	bool simple = s.delta_body.empty();
	int64_t mask = simple ? 0 : mask_at(s, x, y, z);
	double ax = 0.0;
	double ay = 0.0;
	double az = 0.0;
	double tau2 = INF;
	for (int64_t j = 0; j < n; j++) {
		if (j == skip || s.mode[j] == GONE) {
			continue;
		}
		double m = simple ? s.mass[j] : felt_mass(s, j, mask);
		if (m == 0.0) {
			continue;
		}
		int64_t bj = j * 3;
		double dx = pos[bj] - x;
		double dy = pos[bj + 1] - y;
		double dz = pos[bj + 2] - z;
		double r2 = dx * dx + dy * dy + dz * dz;
		if (soften) {
			r2 += s.radius[j] * s.radius[j];
		}
		double r = std::sqrt(r2);
		double f = g * m / (r2 * r);
		ax += f * dx;
		ay += f * dy;
		az += f * dz;
		if (s.mode[j] != GHOST) {
			double orbit2 = r2 * r / (g * m);
			if (orbit2 < tau2) {
				tau2 = orbit2;
			}
			double dvx = vel[bj] - vx;
			double dvy = vel[bj + 1] - vy;
			double dvz = vel[bj + 2] - vz;
			double v2 = dvx * dvx + dvy * dvy + dvz * dvz;
			if (v2 > 0.0 && r2 / v2 < tau2) {
				tau2 = r2 / v2;
			}
		}
	}
	out[0] = ax;
	out[1] = ay;
	out[2] = az;
	out[3] = std::sqrt(tau2);
}

void GravityCore::place_rails(GravityState &s, double t) {
	int64_t n = s.n();
	placed.assign(n, 0);
	for (int64_t i = 0; i < n; i++) {
		if (s.mode[i] == RAILS) {
			place_one(s, i, t, s.pos, s.vel);
		}
	}
}

void GravityCore::place_one(GravityState &s, int64_t i, double t, std::vector<double> &positions, std::vector<double> &velocities) {
	if (placed[i] == 1) {
		return;
	}
	placed[i] = 1;
	int64_t p = s.parent[i];
	if (p >= 0 && s.mode[p] == RAILS) {
		place_one(s, p, t, positions, velocities);
	}
	double state[6];
	state_from_element_set(s.rail.data() + i * ES, t, state);
	int64_t b = i * 3;
	for (int k = 0; k < 3; k++) {
		positions[b + k] = (p >= 0 ? positions[p * 3 + k] : 0.0) + state[k];
		velocities[b + k] = (p >= 0 ? velocities[p * 3 + k] : 0.0) + state[k + 3];
	}
}

// --- Collisions -------------------------------------------------------------

void GravityCore::sweep_bodies(GravityState &s, PackedInt32Array &collisions) {
	int64_t n = s.n();
	const double *pos = s.pos.data();
	std::vector<uint8_t> hit(n, 0);
	for (int64_t i = 0; i < n; i++) {
		if (s.mode[i] != FREE || hit[i] == 1) {
			continue;
		}
		int64_t bi = i * 3;
		for (int64_t j = 0; j < n; j++) {
			if (j == i || hit[j] == 1) {
				continue;
			}
			int32_t mj = s.mode[j];
			if (mj == GHOST || mj == GONE || (mj == FREE && j < i)) {
				continue;
			}
			int64_t bj = j * 3;
			double reach = s.radius[i] + s.radius[j];
			double d1x = pos[bi] - pos[bj];
			double d1y = pos[bi + 1] - pos[bj + 1];
			double d1z = pos[bi + 2] - pos[bj + 2];
			double d0x = prev[bi] - prev[bj];
			double d0y = prev[bi + 1] - prev[bj + 1];
			double d0z = prev[bi + 2] - prev[bj + 2];
			double gap = std::sqrt(minf(d0x * d0x + d0y * d0y + d0z * d0z, d1x * d1x + d1y * d1y + d1z * d1z));
			double moved = std::sqrt((d1x - d0x) * (d1x - d0x) + (d1y - d0y) * (d1y - d0y) + (d1z - d0z) * (d1z - d0z));
			if (gap - moved > reach) {
				continue;
			}
			double dist2, u;
			closest(d0x, d0y, d0z, d1x, d1y, d1z, dist2, u);
			if (dist2 < reach * reach) {
				collisions.push_back(i);
				collisions.push_back(j);
				hit[i] = 1;
				hit[j] = 1;
				break;
			}
		}
	}
}

bool GravityCore::touches_body(const GravityState &s, double x, double y, double z, int64_t skip) const {
	for (int64_t j = 0; j < s.n(); j++) {
		if (j == skip || s.mode[j] == GONE || s.mode[j] == GHOST) {
			continue;
		}
		int64_t b = j * 3;
		double dx = x - s.view_pos[b];
		double dy = y - s.view_pos[b + 1];
		double dz = z - s.view_pos[b + 2];
		if (dx * dx + dy * dy + dz * dz < s.radius[j] * s.radius[j]) {
			return true;
		}
	}
	return false;
}

// --- Particles --------------------------------------------------------------

double GravityCore::start_particle(GravityState &s, int64_t p) {
	fronts_reach(s, s.time);
	int64_t b = p * 3;
	double pull[4];
	pull_at(s, s.p_pos[b], s.p_pos[b + 1], s.p_pos[b + 2], -1, !s.collisions_enabled, s.p_vel[b], s.p_vel[b + 1],
			s.p_vel[b + 2], pull);
	s.p_acc[b] = pull[0];
	s.p_acc[b + 1] = pull[1];
	s.p_acc[b + 2] = pull[2];
	s.p_tau[p] = pull[3];
	s.p_last[p] = s.time;
	s.p_level[p] = 0;
	s.p_next[p] = s.time + SLEEP_CHECK_STEPS * ETA * pull[3];
	return pull[3];
}

double GravityCore::step_particles(GravityState &s, double h, PackedInt32Array &impacts, PackedFloat64Array &impact_data) {
	int64_t count = s.particles();
	if (count == 0) {
		return INF;
	}
	int64_t n = s.n();
	double t1 = s.time;
	double tau_min = INF;
	bool soften = !s.collisions_enabled;
	const double *pos = s.pos.data();
	const double *vel = s.vel.data();
	for (int64_t p = 0; p < count; p++) {
		if (s.p_mode[p] != AWAKE) {
			continue;
		}
		int64_t level = s.p_level[p];
		if ((s.step_count & (((int64_t)1 << level) - 1)) != 0) {
			tau_min = minf(tau_min, s.p_tau[p]);
			continue;
		}
		double big_h = t1 - s.p_last[p];
		int64_t b = p * 3;
		double x0 = s.p_pos[b];
		double y0 = s.p_pos[b + 1];
		double z0 = s.p_pos[b + 2];
		double half = 0.5 * big_h * big_h;
		double x = x0 + s.p_vel[b] * big_h + s.p_acc[b] * half;
		double y = y0 + s.p_vel[b + 1] * big_h + s.p_acc[b + 1] * half;
		double z = z0 + s.p_vel[b + 2] * big_h + s.p_acc[b + 2] * half;
		if (s.collisions_enabled) {
			int64_t hit = -1;
			double hit_u = 0.0;
			for (int64_t j = 0; j < n; j++) {
				int32_t mj = s.mode[j];
				if (mj == GONE || mj == GHOST) {
					continue;
				}
				int64_t bj = j * 3;
				double reach = s.radius[j] + s.p_radius[p];
				double d1x = x - pos[bj];
				double d1y = y - pos[bj + 1];
				double d1z = z - pos[bj + 2];
				double d0x = x0 - (pos[bj] - vel[bj] * big_h);
				double d0y = y0 - (pos[bj + 1] - vel[bj + 1] * big_h);
				double d0z = z0 - (pos[bj + 2] - vel[bj + 2] * big_h);
				double gap = std::sqrt(minf(d0x * d0x + d0y * d0y + d0z * d0z, d1x * d1x + d1y * d1y + d1z * d1z));
				double moved = std::sqrt((d1x - d0x) * (d1x - d0x) + (d1y - d0y) * (d1y - d0y) + (d1z - d0z) * (d1z - d0z));
				if (gap - moved > reach) {
					continue;
				}
				double dist2, u;
				closest(d0x, d0y, d0z, d1x, d1y, d1z, dist2, u);
				if (dist2 < reach * reach) {
					hit = j;
					hit_u = u;
					break;
				}
			}
			if (hit >= 0) {
				int64_t bj = hit * 3;
				double nx = x0 + (x - x0) * hit_u - (pos[bj] - vel[bj] * big_h * (1.0 - hit_u));
				double ny = y0 + (y - y0) * hit_u - (pos[bj + 1] - vel[bj + 1] * big_h * (1.0 - hit_u));
				double nz = z0 + (z - z0) * hit_u - (pos[bj + 2] - vel[bj + 2] * big_h * (1.0 - hit_u));
				double length = maxf(std::sqrt(nx * nx + ny * ny + nz * nz), 1e-300);
				double dvx = s.p_vel[b] - vel[bj];
				double dvy = s.p_vel[b + 1] - vel[bj + 1];
				double dvz = s.p_vel[b + 2] - vel[bj + 2];
				s.p_mode[p] = P_GONE;
				s.p_pos[b] = x;
				s.p_pos[b + 1] = y;
				s.p_pos[b + 2] = z;
				impacts.push_back(p);
				impacts.push_back(hit);
				impact_data.push_back(t1 - big_h * (1.0 - hit_u));
				impact_data.push_back(std::sqrt(dvx * dvx + dvy * dvy + dvz * dvz));
				impact_data.push_back(nx / length);
				impact_data.push_back(ny / length);
				impact_data.push_back(nz / length);
				continue;
			}
		}
		double vx = s.p_vel[b] + s.p_acc[b] * big_h;
		double vy = s.p_vel[b + 1] + s.p_acc[b + 1] * big_h;
		double vz = s.p_vel[b + 2] + s.p_acc[b + 2] * big_h;
		double pull[4];
		pull_at(s, x, y, z, -1, soften, vx, vy, vz, pull);
		double half_h = 0.5 * big_h;
		s.p_vel[b] += (s.p_acc[b] + pull[0]) * half_h;
		s.p_vel[b + 1] += (s.p_acc[b + 1] + pull[1]) * half_h;
		s.p_vel[b + 2] += (s.p_acc[b + 2] + pull[2]) * half_h;
		s.p_pos[b] = x;
		s.p_pos[b + 1] = y;
		s.p_pos[b + 2] = z;
		s.p_acc[b] = pull[0];
		s.p_acc[b + 1] = pull[1];
		s.p_acc[b + 2] = pull[2];
		s.p_last[p] = t1;
		double tau = pull[3];
		s.p_tau[p] = tau;
		int64_t want = PARTICLE_MAX_LEVEL;
		if (tau < INF) {
			want = clampi(floori(std::log(ETA * tau / h) / LN2), 0, PARTICLE_MAX_LEVEL);
		}
		if (want < level) {
			level = want;
		} else if (want > level && (s.step_count & (((int64_t)1 << (level + 1)) - 1)) == 0) {
			level += 1;
		}
		s.p_level[p] = (int32_t)level;
		tau_min = minf(tau_min, tau);
		if (t1 >= s.p_next[p]) {
			if (!try_sleep(s, p)) {
				s.p_next[p] = t1 + SLEEP_CHECK_STEPS * step_size(s.level) * (double)((int64_t)1 << level);
			}
		}
	}
	return tau_min;
}

bool GravityCore::try_sleep(GravityState &s, int64_t p) {
	if (!s.delta_body.empty()) {
		return false;
	}
	int64_t b = p * 3;
	double x = s.p_pos[b];
	double y = s.p_pos[b + 1];
	double z = s.p_pos[b + 2];
	int64_t primary = primary_for(s, x, y, z);
	if (primary < 0) {
		return false;
	}
	int64_t pb = primary * 3;
	double rx = x - s.pos[pb];
	double ry = y - s.pos[pb + 1];
	double rz = z - s.pos[pb + 2];
	double r_primary = std::sqrt(rx * rx + ry * ry + rz * rz);
	double g = G * s.g_scale;
	double mu = g * s.mass[primary];
	double elements[ES];
	if (!elements_from_state(rx, ry, rz, s.p_vel[b] - s.vel[pb], s.p_vel[b + 1] - s.vel[pb + 1], s.p_vel[b + 2] - s.vel[pb + 2],
				mu, s.time, elements)) {
		return false;
	}
	if (elements[0] <= 0.0 || elements[1] > 0.98) {
		return false;
	}
	if (elements[0] * (1.0 - elements[1]) < 3.0 * s.radius[primary]) {
		return false;
	}
	if (s.hill[primary] < INF && elements[0] * (1.0 + elements[1]) > SLEEP_HILL_SHARE * s.hill[primary]) {
		return false;
	}
	std::vector<int32_t> up = ancestors(s, primary);
	for (int64_t j = 0; j < s.n(); j++) {
		if (j == primary || s.mode[j] == GONE || s.mode[j] == GHOST || contains(up, (int32_t)j)) {
			continue;
		}
		double zone = wake_zone(s, j, primary, r_primary);
		int64_t bj = j * 3;
		double ex = s.pos[bj] - s.pos[pb];
		double ey = s.pos[bj + 1] - s.pos[pb + 1];
		double ez = s.pos[bj + 2] - s.pos[pb + 2];
		double limit = maxf(minf(SLEEP_FACTOR * zone, SLEEP_REACH * std::sqrt(ex * ex + ey * ey + ez * ez)), zone);
		double dx = s.pos[bj] - x;
		double dy = s.pos[bj + 1] - y;
		double dz = s.pos[bj + 2] - z;
		if (std::sqrt(dx * dx + dy * dy + dz * dz) < limit) {
			return false;
		}
	}
	for (int64_t k = 0; k < ES; k++) {
		s.p_elem[p * ES + k] = elements[k];
	}
	s.p_mode[p] = ASLEEP;
	s.p_primary[p] = (int32_t)primary;
	s.p_last[p] = s.time;
	s.p_next[p] = s.time;
	slept += 1;
	return true;
}

int64_t GravityCore::primary_for(const GravityState &s, double x, double y, double z) const {
	int64_t best = -1;
	double best_hill = INF;
	double best_pull = 0.0;
	for (int64_t j = 0; j < s.n(); j++) {
		if (s.mode[j] == GONE || s.mode[j] == GHOST || s.mass[j] <= 0.0) {
			continue;
		}
		int64_t b = j * 3;
		double dx = x - s.pos[b];
		double dy = y - s.pos[b + 1];
		double dz = z - s.pos[b + 2];
		double d2 = dx * dx + dy * dy + dz * dz;
		double hill = s.hill[j];
		if (hill < INF) {
			if (d2 < hill * hill && hill < best_hill) {
				best = j;
				best_hill = hill;
			}
		} else if (best_hill == INF) {
			double pull = s.mass[j] / maxf(d2, 1e-300);
			if (pull > best_pull) {
				best = j;
				best_pull = pull;
			}
		}
	}
	return best;
}

void GravityCore::build_queue(const GravityState &s, double t_target) {
	queue.clear();
	queue_head = 0;
	queue_limit = t_target;
	if (s.pristine) {
		return;
	}
	for (int64_t p = 0; p < s.particles(); p++) {
		if (s.p_mode[p] == ASLEEP && s.p_next[p] <= t_target) {
			queue.push_back((int32_t)p);
		}
	}
	const std::vector<double> &next = s.p_next;
	std::stable_sort(queue.begin(), queue.end(), [&next](int32_t a, int32_t b) {
		return next[a] < next[b] || (next[a] == next[b] && a < b);
	});
}

void GravityCore::run_checks(GravityState &s) {
	while (queue_head < queue.size()) {
		int32_t p = queue[queue_head];
		if (s.p_next[p] > s.time) {
			return;
		}
		queue_head += 1;
		if (s.p_mode[p] != ASLEEP) {
			continue;
		}
		if (check_asleep(s, p)) {
			wake(s, p);
		} else if (s.p_next[p] <= queue_limit) {
			enqueue(s, p);
		}
	}
}

void GravityCore::enqueue(const GravityState &s, int32_t p) {
	size_t at = queue.size();
	while (at > queue_head && s.p_next[queue[at - 1]] > s.p_next[p]) {
		at -= 1;
	}
	queue.insert(queue.begin() + at, p);
}

bool GravityCore::check_asleep(GravityState &s, int64_t p) {
	int64_t primary = s.p_primary[p];
	if (primary < 0 || s.mode[primary] == GONE || s.mode[primary] == GHOST) {
		return true;
	}
	double rel[6];
	state_from_element_set(s.p_elem.data() + p * ES, s.time, rel);
	int64_t pb = primary * 3;
	double x = s.pos[pb] + rel[0];
	double y = s.pos[pb + 1] + rel[1];
	double z = s.pos[pb + 2] + rel[2];
	double vx = s.vel[pb] + rel[3];
	double vy = s.vel[pb + 1] + rel[4];
	double vz = s.vel[pb + 2] + rel[5];
	double r_primary = std::sqrt(rel[0] * rel[0] + rel[1] * rel[1] + rel[2] * rel[2]);
	if (r_primary < 3.0 * s.radius[primary]) {
		return true;
	}
	if (s.hill[primary] < INF && r_primary > WAKE_HILL_SHARE * s.hill[primary]) {
		return true;
	}
	std::vector<int32_t> up = ancestors(s, primary);
	double soonest = MAX_CHECK_INTERVAL;
	for (int64_t j = 0; j < s.n(); j++) {
		if (j == primary || s.mode[j] == GONE || s.mode[j] == GHOST || contains(up, (int32_t)j)) {
			continue;
		}
		double zone = wake_zone(s, j, primary, r_primary);
		int64_t b = j * 3;
		double dx = x - s.pos[b];
		double dy = y - s.pos[b + 1];
		double dz = z - s.pos[b + 2];
		double distance = std::sqrt(dx * dx + dy * dy + dz * dz);
		if (distance < zone) {
			return true;
		}
		double dvx = vx - s.vel[b];
		double dvy = vy - s.vel[b + 1];
		double dvz = vz - s.vel[b + 2];
		double closing = 2.0 * std::sqrt(dvx * dvx + dvy * dvy + dvz * dvz) + 0.1;
		soonest = minf(soonest, 0.5 * (distance - zone) / closing);
	}
	for (int64_t f = 0; f < (int64_t)s.front_time.size(); f++) {
		double arrival = significant_arrival_at(s, f, x, y, z, r_primary, primary);
		if (std::isnan(arrival)) {
			continue;
		}
		if (arrival > s.p_last[p] && arrival <= s.time) {
			return true;
		}
		if (arrival > s.time) {
			soonest = minf(soonest, arrival - s.time);
		}
	}
	s.p_last[p] = s.time;
	s.p_next[p] = s.time + maxf(soonest, step_size(s.level));
	return false;
}

double GravityCore::wake_zone(const GravityState &s, int64_t j, int64_t primary, double r_primary) const {
	double zone;
	int64_t up = s.parent[j];
	if (s.hill[j] < INF && up >= 0) {
		int64_t bj = j * 3;
		int64_t bu = up * 3;
		double dx = s.pos[bj] - s.pos[bu];
		double dy = s.pos[bj + 1] - s.pos[bu + 1];
		double dz = s.pos[bj + 2] - s.pos[bu + 2];
		zone = maxf(minf(WAKE_HILL * s.hill[j], WAKE_REACH * std::sqrt(dx * dx + dy * dy + dz * dz)), s.hill[j]);
	} else {
		zone = r_primary * std::pow(2.0 * s.mass[j] / (WAKE_TIDAL * maxf(s.mass[primary], 1e-300)), 1.0 / 3.0);
	}
	return maxf(zone, 3.0 * s.radius[j]);
}

std::vector<int32_t> GravityCore::ancestors(const GravityState &s, int64_t primary) const {
	std::vector<int32_t> found;
	int32_t up = s.parent[primary];
	while (up >= 0 && found.size() < 8) {
		found.push_back(up);
		up = s.parent[up];
	}
	return found;
}

double GravityCore::significant_arrival(const GravityState &s, int64_t p, int64_t f) const {
	int64_t primary = s.p_primary[p];
	if (primary < 0) {
		return NOT_A_NUMBER;
	}
	double rel[6];
	state_from_element_set(s.p_elem.data() + p * ES, s.time, rel);
	int64_t pb = primary * 3;
	double r_primary = std::sqrt(rel[0] * rel[0] + rel[1] * rel[1] + rel[2] * rel[2]);
	return significant_arrival_at(s, f, s.pos[pb] + rel[0], s.pos[pb + 1] + rel[1], s.pos[pb + 2] + rel[2], r_primary, primary);
}

double GravityCore::significant_arrival_at(const GravityState &s, int64_t f, double x, double y, double z, double r_primary,
		int64_t primary) const {
	double own = s.mass[primary] / maxf(r_primary * r_primary, 1e-300);
	bool significant = false;
	for (size_t d = 0; d < s.delta_body.size(); d++) {
		if (s.delta_front[d] != f) {
			continue;
		}
		int64_t b = s.delta_body[d] * 3;
		double dx = x - s.pos[b];
		double dy = y - s.pos[b + 1];
		double dz = z - s.pos[b + 2];
		double d2 = maxf(dx * dx + dy * dy + dz * dz, 1e-300);
		if (std::fabs(s.delta_mass[d]) / d2 > FRONT_WAKE_RATIO * own) {
			significant = true;
			break;
		}
	}
	if (!significant) {
		return NOT_A_NUMBER;
	}
	double ox = x - s.front_origin[f * 3];
	double oy = y - s.front_origin[f * 3 + 1];
	double oz = z - s.front_origin[f * 3 + 2];
	double speed = s.front_speed[f];
	if (std::isinf(speed)) {
		return s.front_time[f];
	}
	return s.front_time[f] + std::sqrt(ox * ox + oy * oy + oz * oz) / speed;
}

void GravityCore::wake(GravityState &s, int64_t p) {
	int64_t primary = s.p_primary[p];
	int64_t b = p * 3;
	if (primary >= 0) {
		double rel[6];
		state_from_element_set(s.p_elem.data() + p * ES, s.time, rel);
		int64_t pb = primary * 3;
		for (int k = 0; k < 3; k++) {
			s.p_pos[b + k] = s.pos[pb + k] + rel[k];
			s.p_vel[b + k] = s.vel[pb + k] + rel[k + 3];
		}
	}
	s.p_mode[p] = AWAKE;
	lower_level(s, start_particle(s, p));
	woken += 1;
}

// --- Upkeep -----------------------------------------------------------------

bool GravityCore::maintain(GravityState &s) {
	int64_t n = s.n();
	std::vector<int32_t> order;
	for (int64_t i = 0; i < n; i++) {
		if (s.mode[i] == FREE || s.mode[i] == RAILS) {
			order.push_back((int32_t)i);
		}
	}
	const std::vector<double> &mass = s.mass;
	std::stable_sort(order.begin(), order.end(), [&mass](int32_t a, int32_t b) {
		return mass[a] > mass[b] || (mass[a] == mass[b] && a < b);
	});
	bool changed = false;
	for (size_t k = 0; k < order.size(); k++) {
		int64_t i = order[k];
		int64_t bi = i * 3;
		int64_t best = -1;
		double best_hill = INF;
		double best_pull = 0.0;
		for (size_t q = 0; q < k; q++) {
			int64_t j = order[q];
			int64_t bj = j * 3;
			double dx = s.pos[bi] - s.pos[bj];
			double dy = s.pos[bi + 1] - s.pos[bj + 1];
			double dz = s.pos[bi + 2] - s.pos[bj + 2];
			double d2 = dx * dx + dy * dy + dz * dz;
			double hill = s.hill[j];
			if (hill < INF) {
				if (d2 < hill * hill && hill < best_hill) {
					best = j;
					best_hill = hill;
				}
			} else if (best_hill == INF) {
				double pull = mass[j] / maxf(d2, 1e-300);
				if (pull > best_pull) {
					best = j;
					best_pull = pull;
				}
			}
		}
		if (s.mode[i] == RAILS) {
			int64_t rails_parent = s.parent[i];
			bool stays = s.rails_tau > 0.0 && best == rails_parent && orbit_tau(s, i, rails_parent) < 1.25 * s.rails_tau &&
					!disturbed(s, i, rails_parent);
			if (!stays) {
				s.mode[i] = FREE;
				changed = true;
			}
		}
		s.parent[i] = (int32_t)best;
		if (best >= 0) {
			int64_t bb = best * 3;
			double dx = s.pos[bi] - s.pos[bb];
			double dy = s.pos[bi + 1] - s.pos[bb + 1];
			double dz = s.pos[bi + 2] - s.pos[bb + 2];
			s.hill[i] = std::sqrt(dx * dx + dy * dy + dz * dz) * std::pow(mass[i] / (3.0 * maxf(mass[best], 1e-300)), 1.0 / 3.0);
		} else {
			s.hill[i] = INF;
		}
		if (s.mode[i] == FREE && s.rails_tau > 0.0 && best >= 0 && mass[i] < RAILS_MAX_MASS &&
				orbit_tau(s, i, best) < 0.8 * s.rails_tau && !disturbed(s, i, best)) {
			int64_t pb = best * 3;
			double mu = G * s.g_scale * (mass[best] + mass[i]);
			double elements[ES];
			if (elements_from_state(s.pos[bi] - s.pos[pb], s.pos[bi + 1] - s.pos[pb + 1], s.pos[bi + 2] - s.pos[pb + 2],
						s.vel[bi] - s.vel[pb], s.vel[bi + 1] - s.vel[pb + 1], s.vel[bi + 2] - s.vel[pb + 2], mu, s.time, elements)) {
				for (int64_t e = 0; e < ES; e++) {
					s.rail[i * ES + e] = elements[e];
				}
				s.mode[i] = RAILS;
				s.parent[i] = (int32_t)best;
				if (s.rail[i * ES + 1] > 0.95 || s.rail[i * ES] <= 0.0) {
					s.mode[i] = FREE;
				} else {
					changed = true;
				}
			}
		}
	}
	for (int64_t i = 0; i < n; i++) {
		if (s.mode[i] == GHOST || s.mode[i] == GONE) {
			s.hill[i] = 0.0;
		}
	}
	return changed;
}

double GravityCore::orbit_tau(const GravityState &s, int64_t i, int64_t p) const {
	int64_t bi = i * 3;
	int64_t bp = p * 3;
	double dx = s.pos[bi] - s.pos[bp];
	double dy = s.pos[bi + 1] - s.pos[bp + 1];
	double dz = s.pos[bi + 2] - s.pos[bp + 2];
	double d2 = dx * dx + dy * dy + dz * dz;
	return std::sqrt(d2 * std::sqrt(d2) / (G * s.g_scale * (s.mass[i] + s.mass[p])));
}

bool GravityCore::disturbed(const GravityState &s, int64_t i, int64_t p) const {
	double hill = s.hill[p];
	if (hill == INF) {
		return false;
	}
	int64_t bp = p * 3;
	for (int64_t j = 0; j < s.n(); j++) {
		if (j == i || j == p || s.mode[j] == GONE || s.mode[j] == GHOST || s.parent[j] == p) {
			continue;
		}
		if (s.mass[j] < 1e-3 * s.mass[i]) {
			continue;
		}
		int64_t bj = j * 3;
		double dx = s.pos[bj] - s.pos[bp];
		double dy = s.pos[bj + 1] - s.pos[bp + 1];
		double dz = s.pos[bj + 2] - s.pos[bp + 2];
		if (dx * dx + dy * dy + dz * dz < hill * hill) {
			return true;
		}
	}
	return false;
}
