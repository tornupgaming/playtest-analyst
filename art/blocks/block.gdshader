shader_type spatial;
// A toy block in the Kenney Platformer Kit style, for any axis-aligned box:
// a top colour with a soft checker, sides that darken with depth, an optional
// scalloped lip of the top colour hanging over the sides, optional planks,
// and rounded-looking edges from a bent normal. The box's size comes from
// the instance parameter `box_size`; the mesh is a BoxMesh of that size.

instance uniform vec3 box_size = vec3(1.0);

uniform vec3 top_color : source_color = vec3(0.38, 0.8, 0.55);
uniform vec3 top_color_alt : source_color = vec3(0.45, 0.85, 0.6);
uniform vec3 side_top : source_color = vec3(0.95, 0.6, 0.42);
uniform vec3 side_bottom : source_color = vec3(0.69, 0.38, 0.26);
uniform vec3 lip_color : source_color = vec3(0.38, 0.8, 0.55);
uniform float lip_depth = 0.0;       // 0 for no lip
uniform float checker_size = 2.0;    // 0 for a plain top
uniform float plank_width = 0.0;     // 0 for no planks
uniform float band_depth = 1.6;      // strata on the sides, 0 for none
uniform float bevel = 0.14;
uniform float gradient_depth = 3.0;  // how far down the sides darken
uniform float leaves = 0.0;          // 0..1, leafy dappling for hedges

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 h = box_size * 0.5;
	vec3 n = local_normal;
	float from_top = h.y - local_pos.y;
	vec3 col;

	if (n.y > 0.5) {
		float c = 0.0;
		if (checker_size > 0.0) {
			c = mod(floor(world_pos.x / checker_size) + floor(world_pos.z / checker_size), 2.0);
		}
		col = mix(top_color, top_color_alt, c);
		col *= 0.94 + 0.12 * noise(world_pos.xz * 0.35);
		if (plank_width > 0.0) {
			float along = box_size.x > box_size.z ? world_pos.z : world_pos.x;
			float seam = smoothstep(0.04, 0.0, abs(fract(along / plank_width) - 0.5) - 0.46);
			col *= 1.0 - 0.25 * seam;
		}
	} else if (n.y < -0.5) {
		col = side_bottom * 0.75;
	} else {
		float u = abs(n.x) > 0.5 ? world_pos.z : world_pos.x;
		col = mix(side_top, side_bottom, clamp(from_top / gradient_depth, 0.0, 1.0));
		if (band_depth > 0.0) {
			float wave = 0.18 * sin(u * 1.1) + 0.1 * sin(u * 2.7 + 1.0);
			float band = step(0.55, fract((from_top + wave) / band_depth));
			col *= 1.0 - 0.07 * band;
		}
		if (plank_width > 0.0) {
			float seam = smoothstep(0.04, 0.0, abs(fract(u / plank_width) - 0.5) - 0.46);
			col *= 1.0 - 0.3 * seam;
		}
		if (lip_depth > 0.0) {
			float t = fract(u / 0.7);
			float scallop = lip_depth * (0.45 + 0.55 * sqrt(max(0.0, 1.0 - pow(2.0 * t - 1.0, 2.0))));
			float lip = smoothstep(scallop + 0.02, scallop - 0.02, from_top);
			col = mix(col, lip_color * mix(1.0, 0.82, from_top / scallop), lip);
		}
	}

	if (leaves > 0.0) {
		vec2 q = abs(n.x) > 0.5 ? world_pos.zy : (abs(n.z) > 0.5 ? world_pos.xy : world_pos.xz);
		float leaf = noise(q * 2.2) * 0.6 + noise(q * 5.0) * 0.4;
		col *= 1.0 - leaves * smoothstep(0.45, 0.75, leaf);
		col *= 1.0 + leaves * 0.6 * smoothstep(0.8, 0.95, noise(q * 3.1 + 7.0));
	}

	// Rounded edges: bend the normal towards whichever face edges are near.
	vec3 dist = h - abs(local_pos);
	vec3 bend = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		if (abs(n[i]) < 0.5 && dist[i] < bevel) {
			bend[i] = sign(local_pos[i]) * (1.0 - dist[i] / bevel);
		}
	}
	vec3 bent = normalize(n + bend * 0.9);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bent, 0.0)).xyz);
	// A light rim where top meets side, like the kit's bevelled blocks.
	if (n.y > 0.5) {
		float edge = 1.0 - clamp(min(dist.x, dist.z) / bevel, 0.0, 1.0);
		col = mix(col, col * 1.12, edge);
	}

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
