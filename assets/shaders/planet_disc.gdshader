// A spinning pixel planet: the body's surface map wrapped on a sphere, lit
// from the star's direction, with a dithered terminator. Draw it with
// draw_texture_rect(surface_map, rect) on an odd-sized square rect so the
// disc is centred on a pixel. Only palette colours come out: the map's, or
// night_color.
shader_type canvas_item;
render_mode unshaded;

// Direction towards the star on screen (x right, y down), unit length.
uniform vec2 light_dir = vec2(1.0, 0.0);
// How much light also comes from the viewer's side (0 = edge-on).
uniform float light_height = 0.2;
// Longitude offset of the surface, in turns (0..1).
uniform float spin = 0.0;
// Stars glow on their own and are not shaded.
uniform bool lit = true;
uniform vec4 night_color : source_color;
// Width of the dithered band at the terminator.
uniform float terminator_width = 0.35;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	return (BAYER[y * 4 + x] + 0.5) / 16.0;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float rr = dot(p, p);
	if (rr > 1.0) {
		discard;
	}
	float z = sqrt(1.0 - rr);
	float longitude = atan(p.x, z) / 6.2831853 + spin;
	float latitude = asin(clamp(p.y, -1.0, 1.0)) / 3.14159265 + 0.5;
	vec4 surface = texture(TEXTURE, vec2(fract(longitude), latitude));
	if (lit) {
		vec3 light = normalize(vec3(light_dir, light_height));
		float shade = dot(vec3(p, z), light);
		if (shade < (bayer(FRAGCOORD.xy) - 0.5) * terminator_width) {
			surface = night_color;
		}
	}
	COLOR = vec4(surface.rgb, 1.0);
}
