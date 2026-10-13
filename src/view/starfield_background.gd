class_name StarfieldBackground
extends Node2D
## Deep-space backdrop: dithered nebula bands and twinkling pixel stars.
##
## The nebula is rendered on a worker thread so changing the sky never stalls
## a frame; the old sky stays on screen until the new one is ready.

## Emitted when a requested sky has finished generating and is on screen.
signal sky_ready(sky_seed: int)

const SIZE: Vector2i = Vector2i(640, 360)
const STAR_COUNT: int = 280
## How many times per second the twinkling stars are redrawn.
const TWINKLE_RATE: float = 12.0

@export var sky_seed: int = 7

var _nebula: ImageTexture
var _stars: SkyGenerator.StarField = SkyGenerator.StarField.new()
var _time: float = 0.0
var _since_redraw: float = 0.0
var _task_id: int = -1
var _pending_seed: int = 0
var _pending_image: Image
var _ramps: Dictionary = {}


func _ready() -> void:
	_ramps = SkyGenerator.default_ramps()
	generate(sky_seed)


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Starts generating the sky for a seed. Calls while a sky is being generated
## are queued: the latest seed wins.
func generate(new_seed: int) -> void:
	sky_seed = new_seed
	if _task_id == -1:
		_start_task(new_seed)


## True while a sky is being generated in the background.
func is_generating() -> bool:
	return _task_id != -1


func _start_task(task_seed: int) -> void:
	_pending_seed = task_seed
	var ramps: Dictionary = _ramps
	_task_id = WorkerThreadPool.add_task(
		func() -> void: _pending_image = SkyGenerator.nebula_image(task_seed, SIZE, ramps),
		false,
		"Generate sky"
	)


func _process(delta: float) -> void:
	if _task_id != -1 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_finish_sky()

	_time += delta
	_since_redraw += delta
	if _since_redraw >= 1.0 / TWINKLE_RATE:
		_since_redraw = 0.0
		queue_redraw()


func _finish_sky() -> void:
	if _nebula == null:
		_nebula = ImageTexture.create_from_image(_pending_image)
	else:
		_nebula.update(_pending_image)
	_pending_image = null
	_stars = SkyGenerator.star_field(_pending_seed, SIZE, STAR_COUNT)
	queue_redraw()
	if sky_seed != _pending_seed:
		_start_task(sky_seed)
	else:
		sky_ready.emit(_pending_seed)


func _draw() -> void:
	if _nebula != null:
		draw_texture(_nebula, Vector2.ZERO)
	for i: int in _stars.size():
		var c: Color = _stars.color_at(i, _time)
		var p: Vector2 = _stars.positions[i]
		draw_rect(Rect2(p, Vector2.ONE), c)
		if _stars.crosses[i] == 1:
			var arm: Color = _stars.ramps[i * 3]
			draw_rect(Rect2(p + Vector2(-1, 0), Vector2.ONE), arm)
			draw_rect(Rect2(p + Vector2(1, 0), Vector2.ONE), arm)
			draw_rect(Rect2(p + Vector2(0, -1), Vector2.ONE), arm)
			draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), arm)
