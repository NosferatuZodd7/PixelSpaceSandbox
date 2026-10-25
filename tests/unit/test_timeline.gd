extends TestCase
## The timeline: snapshots of the whole system, taken every few seconds of
## play and before every change the player makes; going back to any of
## them, and undoing the last change. Going back and running again gives
## exactly the same future.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
const START: float = 26.81


static func _simulation() -> Simulation:
	var system: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	var simulation: Simulation = Simulation.new(system, SimClock.load_default(START))
	simulation.max_usec_per_frame = 1 << 30
	simulation.timeline = Timeline.new()
	return simulation


static func _star() -> CelestialBody:
	var star: CelestialBody = CelestialBody.new()
	star.id = &"new_star"
	star.name_key = "PLACED_STAR"
	star.name_number = 1
	star.kind = CelestialBody.Kind.STAR
	star.mass = 1.0
	star.radius = Units.au_from_km(695700.0)
	star.luminosity = 1.0
	star.temperature = 5772.0
	return star


static func _run(simulation: Simulation, frames: int) -> void:
	for frame: int in frames:
		simulation.advance(1.0 / 60.0)


func test_restoring_a_snapshot_and_running_again_gives_the_same_state() -> void:
	var simulation: Simulation = _simulation()
	simulation.place_body(_star(), 0.0, 4.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	simulation.clock.use_preset("5")
	_run(simulation, 20)
	var snapshot: Dictionary = simulation.snapshot("SNAPSHOT_AUTO")
	_run(simulation, 60)
	var pos: PackedFloat64Array = simulation.state.pos.duplicate()
	var vel: PackedFloat64Array = simulation.state.vel.duplicate()
	var time: float = simulation.state.time
	var p_view: PackedFloat64Array = simulation.state.p_view.duplicate()
	simulation.restore(snapshot)
	assert_eq(simulation.clock.time, float(snapshot["time"]), "back at the snapshot's moment")
	_run(simulation, 60)
	assert_eq(simulation.state.time, time, "the same steps")
	assert_true(simulation.state.pos == pos, "the same positions")
	assert_true(simulation.state.vel == vel, "the same velocities")
	assert_true(simulation.state.p_view == p_view, "the same small bodies")


func test_undo_takes_back_the_last_change() -> void:
	var simulation: Simulation = _simulation()
	var bodies: int = simulation.system.size()
	simulation.clock.paused = true
	simulation.place_body(_star(), 0.0, 4.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	assert_eq(simulation.timeline.snapshots.size(), 1, "a snapshot before the change")
	assert_eq(simulation.system.size(), bodies + 1)
	assert_true(simulation.timeline.undo(simulation), "it can be undone")
	assert_eq(simulation.system.size(), bodies, "the star is gone")
	assert_true(simulation.fronts.is_empty(), "and its news never left")
	assert_true(simulation.is_pristine(), "the Solar System is untouched again")
	assert_false(simulation.timeline.undo(simulation), "nothing more to undo")


func test_merged_bodies_come_back_as_they_were() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var earth: int = simulation.system.index_of(&"earth")
	var mass: float = simulation.system.body(earth).mass
	simulation.timeline.record(simulation, "SNAPSHOT_AUTO")
	simulation.merge(earth, simulation.system.index_of(&"mars"), "FRONT_MERGED")
	assert_ne(simulation.system.body(earth).mass, mass)
	simulation.restore(simulation.timeline.snapshots[0])
	assert_eq(simulation.system.body(earth).mass, mass, "the Earth's own mass again")
	assert_true(simulation.is_present(simulation.system.index_of(&"mars")), "and Mars back")


func test_snapshots_are_taken_as_time_runs_and_kept_to_a_number() -> void:
	var simulation: Simulation = _simulation()
	var timeline: Timeline = simulation.timeline
	timeline.max_snapshots = 3
	for second: int in 50:
		timeline.tick(simulation, 1.0)
	assert_eq(timeline.snapshots.size(), 3, "every %s seconds of play, the newest kept" % Timeline.EVERY_SECONDS)
	simulation.clock.paused = true
	var count: int = timeline.snapshots.size()
	timeline.tick(simulation, 60.0)
	assert_eq(timeline.snapshots.size(), count, "none while paused")


func test_rewinding_drops_what_came_after() -> void:
	var simulation: Simulation = _simulation()
	var timeline: Timeline = simulation.timeline
	simulation.clock.use_preset("6")
	for k: int in 3:
		timeline.record(simulation, "SNAPSHOT_AUTO")
		_run(simulation, 10)
	var first: float = float(timeline.snapshots[0]["time"])
	timeline.rewind(simulation, 0)
	assert_eq(simulation.clock.time, first, "back to the first")
	assert_eq(timeline.snapshots.size(), 1, "the later ones are gone, the first is kept")
