class_name Timeline
extends RefCounted
## Snapshots of the whole system: one every EVERY_SECONDS of play while
## time runs, and one before every change the player makes (labelled with
## that change). The player can go back to any of them, or undo the last
## change; the oldest are dropped past max_snapshots.

const EVERY_SECONDS: float = 10.0
## The label of the snapshots taken as time runs.
const AUTO: String = "SNAPSHOT_AUTO"

## How many snapshots are kept (the quality profile will set it).
var max_snapshots: int = 30
## Oldest first: see Simulation.snapshot.
var snapshots: Array[Dictionary] = []

var _since: float = 0.0


func record(simulation: Simulation, label_key: String) -> void:
	snapshots.append(simulation.snapshot(label_key))
	while snapshots.size() > max_snapshots:
		snapshots.pop_front()
	_since = 0.0


## Counts real seconds of play; takes a snapshot every EVERY_SECONDS while
## time runs.
func tick(simulation: Simulation, real_seconds: float) -> void:
	if simulation.clock.paused:
		return
	_since += real_seconds
	if _since >= EVERY_SECONDS:
		record(simulation, AUTO)


## Goes back to a snapshot, keeping it and dropping the later ones.
func rewind(simulation: Simulation, index: int) -> void:
	if index < 0 or index >= snapshots.size():
		return
	simulation.restore(snapshots[index])
	snapshots.resize(index + 1)
	_since = 0.0


## Takes back the last change the player made: back to the snapshot taken
## just before it, which is used up. False when there is none.
func undo(simulation: Simulation) -> bool:
	for index: int in range(snapshots.size() - 1, -1, -1):
		if snapshots[index]["label_key"] != AUTO:
			simulation.restore(snapshots[index])
			snapshots.resize(index)
			_since = 0.0
			return true
	return false
