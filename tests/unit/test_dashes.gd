extends TestCase
## Dashed lines (orbits, paths, rings) keep the same dashes on screen at any
## zoom, and only the part near the screen is cut into dashes, however long
## the line: an open orbit after its star is gone reaches far past the screen.

const SCREEN: Rect2 = Rect2(0, 0, 640, 360)


func test_dashes_follow_a_line_across_the_screen() -> void:
	var segments: PackedVector2Array = SpaceView.dash_segments(
		PackedVector2Array([Vector2(0, 100), Vector2(60, 100)]), false, 0.0, SCREEN
	)
	assert_eq(segments.size(), 20, "ten dashes of 3 px every 6 px")
	assert_eq(segments[0], Vector2(0, 100))
	assert_eq(segments[1], Vector2(3, 100))
	assert_eq(segments[2], Vector2(6, 100))


func test_a_huge_line_is_cut_only_near_the_screen() -> void:
	var started: int = Time.get_ticks_msec()
	var segments: PackedVector2Array = SpaceView.dash_segments(
		PackedVector2Array([Vector2(-1e9, 100), Vector2(1e9, 100)]), false, 0.0, SCREEN
	)
	var took: int = Time.get_ticks_msec() - started
	assert_true(took < 100, "done at once (%d ms)" % took)
	assert_true(segments.size() < 400, "only the dashes near the screen: %d points" % segments.size())
	assert_true(segments.size() > 150, "and those are there")


func test_the_pattern_stays_put_when_a_line_starts_off_screen() -> void:
	# The same line, once from its start and once from 1,000 px before it:
	# the dashes on screen land in the same places.
	var near: PackedVector2Array = SpaceView.dash_segments(
		PackedVector2Array([Vector2(-12, 100), Vector2(100, 100)]), false, 0.0, SCREEN
	)
	var far: PackedVector2Array = SpaceView.dash_segments(
		PackedVector2Array([Vector2(-1212, 100), Vector2(100, 100)]), false, 0.0, SCREEN
	)
	assert_eq(far.slice(far.size() - 6), near.slice(near.size() - 6), "the same last dashes")
