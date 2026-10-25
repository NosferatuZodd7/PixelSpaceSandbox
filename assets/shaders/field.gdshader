// A dithered map over the screen of what up to 16 sources add up to, as
// d is the distance in AU: mode 0, the gravity field (the sum of M / d²),
// one band per tenfold change, from faint to bright; mode 1, temperature: how warm a
// planet would be there from every star's light (278.6 K × the sum of
// L / d² to the power 1/4, for an albedo of 0.3), in colour bands from ice
// to lava. Draw a rect over the screen; coordinates are the canvas item's
// local pixels.
shader_type canvas_item;
render_mode unshaded;

uniform int mode = 0;
uniform int count = 0;
// Where each source is (screen pixels) and how strong (M☉ or L☉).
uniform vec2 sources[16];
uniform float strength[16];
// Pixels per AU.
uniform float scale = 100.0;
// Gravity: faint to bright. Temperature: below 150 K, 150 to 250, 250 to
// 320, 320 to 500, above 500.
uniform vec4 band_0 : source_color;
uniform vec4 band_1 : source_color;
uniform vec4 band_2 : source_color;
uniform vec4 band_3 : source_color;
uniform vec4 band_4 : source_color;
// Share of pixels filled.
uniform float density = 0.3;

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
	float total = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) {
			break;
		}
		vec2 d = (local - sources[i]) / scale;
		total += strength[i] / max(dot(d, d), 1e-12);
	}
	int band;
	float fill = density;
	if (mode == 0) {
		// One band per tenfold change of the pull, from a thousandth of the
		// Sun's at 1 AU (faint, sparse) to ten times it and more (bright).
		float decade = floor(log(max(total, 1e-30)) / log(10.0));
		if (decade < -3.0) {
			discard;
		}
		band = int(clamp(decade + 3.0, 0.0, 4.0));
		fill = density * (0.2 + 0.2 * float(band));
	} else {
		float kelvin = 278.6 * pow(total * 0.7, 0.25);
		band = kelvin < 150.0 ? 0 : kelvin < 250.0 ? 1 : kelvin < 320.0 ? 2 : kelvin < 500.0 ? 3 : 4;
		if (total <= 0.0) {
			discard;
		}
	}
	if (bayer(FRAGCOORD.xy) >= fill) {
		discard;
	}
	COLOR = band == 0 ? band_0 : band == 1 ? band_1 : band == 2 ? band_2 : band == 3 ? band_3 : band_4;
}
