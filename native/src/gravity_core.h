// The native gravity kernel: the same algorithm as
// src/sim/gravity_core_script.gd (the reference), function by function and in
// the same order of operations, so both give the same results. See that file
// for what each part does and why.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// An NBodyState copied into plain vectors for the duration of one call.
struct GravityState {
	double time = 0.0;
	int64_t level = -1;
	int64_t level_up = 0;
	int64_t step_count = 0;
	double g_scale = 1.0;
	bool collisions_enabled = true;
	bool acc_valid = false;
	bool pristine = false;
	double rails_tau = 0.0;

	std::vector<double> pos, vel, acc, mass, radius, hill, rail;
	std::vector<int32_t> mode, parent;
	std::vector<int32_t> delta_body, delta_front;
	std::vector<double> delta_mass;
	std::vector<double> front_origin, front_time, front_speed;
	std::vector<int32_t> p_mode, p_primary, p_level;
	std::vector<double> p_elem, p_pos, p_vel, p_acc, p_last, p_next, p_radius, p_tau;
	std::vector<double> view_pos, view_vel, p_view;

	int64_t n() const { return (int64_t)mass.size(); }
	int64_t particles() const { return (int64_t)p_mode.size(); }

	void load(Object *p_object);
	void store(Object *p_object) const;
	void store_view(Object *p_object) const;
};

class GravityCore : public RefCounted {
	GDCLASS(GravityCore, RefCounted)

public:
	Dictionary advance(Object *p_state, double p_target, int64_t p_max_steps, int64_t p_max_usec);
	void preview(Object *p_state, double p_time);
	PackedFloat64Array field_at(Object *p_state, const PackedFloat64Array &p_points, double p_time);
	PackedFloat64Array predict(Object *p_state, const PackedInt32Array &p_bodies, const PackedInt32Array &p_particles,
			double p_duration, int64_t p_samples, int64_t p_max_steps);
	void schedule_front(Object *p_state, int64_t p_front);

protected:
	static void _bind_methods();

private:
	std::vector<int32_t> delta_start;
	std::vector<int32_t> sorted_front;
	std::vector<double> sorted_mass;
	std::vector<double> reach2;
	std::vector<double> new_acc;
	std::vector<double> prev;
	std::vector<uint8_t> placed;
	std::vector<int32_t> queue;
	size_t queue_head = 0;
	double queue_limit = 0.0;
	int64_t woken = 0;
	int64_t slept = 0;

	Dictionary run(GravityState &s, double p_target, int64_t p_max_steps, int64_t p_max_usec);
	void preview_state(GravityState &s, double t);

	void prepare(GravityState &s);
	void refresh_accelerations(GravityState &s);
	void step(GravityState &s, double h, PackedInt32Array &collisions, PackedInt32Array &impacts,
			PackedFloat64Array &impact_data);
	void choose_level(GravityState &s, double tau, bool reset);
	void lower_level(GravityState &s, double tau);
	double particle_tau(const GravityState &s) const;

	void build_delta_index(const GravityState &s);
	void fronts_reach(const GravityState &s, double t);
	int64_t mask_at(const GravityState &s, double x, double y, double z) const;
	double felt_mass(const GravityState &s, int64_t j, int64_t mask) const;
	double body_forces(GravityState &s, double t);
	void pull_at(const GravityState &s, double x, double y, double z, int64_t skip, bool soften, double vx, double vy,
			double vz, double out[4]) const;
	void place_rails(GravityState &s, double t);
	void place_one(GravityState &s, int64_t i, double t, std::vector<double> &positions, std::vector<double> &velocities);

	void sweep_bodies(GravityState &s, PackedInt32Array &collisions);
	bool touches_body(const GravityState &s, double x, double y, double z, int64_t skip) const;

	double start_particle(GravityState &s, int64_t p);
	double step_particles(GravityState &s, double h, PackedInt32Array &impacts, PackedFloat64Array &impact_data);
	bool try_sleep(GravityState &s, int64_t p);
	int64_t primary_for(const GravityState &s, double x, double y, double z) const;
	void build_queue(const GravityState &s, double t_target);
	void run_checks(GravityState &s);
	void enqueue(const GravityState &s, int32_t p);
	bool check_asleep(GravityState &s, int64_t p);
	double significant_arrival(const GravityState &s, int64_t p, int64_t f) const;
	double significant_arrival_at(const GravityState &s, int64_t f, double x, double y, double z, double r_primary,
			int64_t primary) const;
	void wake(GravityState &s, int64_t p);

	bool maintain(GravityState &s);
	double orbit_tau(const GravityState &s, int64_t i, int64_t p) const;
	bool disturbed(const GravityState &s, int64_t i, int64_t p) const;
};

} // namespace godot
