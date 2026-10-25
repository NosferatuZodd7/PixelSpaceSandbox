// The habitable zone of every star at once: where the starlight a planet
// gets (the sum over the stars of L / d², in units of what the Earth gets)
// lies between the outer and inner limits Astro uses (0.53 and 1.1). With one
// star it is a ring; with two it bends and joins as the light adds up.
// Filled with ordered dithering and outlined with a one-pixel edge. Draw a
// rect over the screen; coordinates are the canvas item's local pixels.
shader_type canvas_item;
render_mode unshaded;

uniform int star_count = 0;
// Where each star is (screen pixels) and how bright it looks (L☉).
uniform vec2 stars[8];
uniform float luminosity[8];
// Pixels per AU.
uniform float scale = 100.0;
uniform float flux_inner = 1.1;
uniform float flux_outer = 0.53;
uniform vec4 color : source_color;
uniform vec4 edge_color : source_color;
// Share of pixels filled inside the zone (0..1).
uniform float density = 0.25;

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
	float flux = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= star_count) {
			break;
		}
		vec2 d = (local - stars[i]) / scale;
		flux += luminosity[i] / max(dot(d, d), 1e-12);
	}
	// How much the light changes from one pixel to the next.
	float step = fwidth(flux);
	if (flux < flux_outer || flux > flux_inner) {
		discard;
	}
	if (flux - flux_outer < step || flux_inner - flux < step) {
		COLOR = edge_color;
	} else {
		if (bayer(FRAGCOORD.xy) >= density) {
			discard;
		}
		COLOR = color;
	}
}
