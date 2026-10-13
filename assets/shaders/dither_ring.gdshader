// A ring (or disc, or halo) filled with ordered dithering in one palette
// colour: the habitable zone, star glows and planetary rings. Draw any rect
// that covers it; coordinates are the canvas item's local pixels.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 center = vec2(0.0);
uniform float inner_radius = 0.0;
uniform float outer_radius = 10.0;
// Ellipse: radius along y is multiplied by this (1 = circle), after rotating.
uniform float flatten = 1.0;
uniform float rotation = 0.0;
uniform vec4 color : source_color;
// Share of pixels filled at the inner and outer edge (0..1).
uniform float density_inner = 0.5;
uniform float density_outer = 0.5;
// Optional solid one-pixel outline in another colour.
uniform bool edges = false;
uniform vec4 edge_color : source_color;
// 0: whole ring; 1: only the half with positive y (after rotating); -1: the other half.
uniform int half_side = 0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

varying vec2 local;

float bayer(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	return (BAYER[y * 4 + x] + 0.5) / 16.0;
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 d = local - center;
	float c = cos(-rotation);
	float s = sin(-rotation);
	vec2 q = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
	if (half_side != 0 && q.y * float(half_side) < 0.0) {
		discard;
	}
	q.y /= max(flatten, 0.001);
	float r = length(q);
	if (r < inner_radius || r > outer_radius) {
		discard;
	}
	if (edges && (r < inner_radius + 1.0 || r > outer_radius - 1.0)) {
		COLOR = edge_color;
	} else {
		float t = (r - inner_radius) / max(outer_radius - inner_radius, 0.001);
		if (bayer(FRAGCOORD.xy) >= mix(density_inner, density_outer, t)) {
			discard;
		}
		COLOR = color;
	}
}
