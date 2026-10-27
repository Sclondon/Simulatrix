class_name Grass
extends Node3D
## A field of real 3D grass: tufts of tapered, curved blades drawn as one MultiMesh per square
## of `chunk` metres (squares off screen are not drawn), swayed in the vertex shader by gusts
## that roll across the field, pushed aside by up to eight pushers and flattened into trails
## that stand back up. It thins with distance and fades into the ground colour, and has a
## global quality (low, medium, high) for phones. No textures. Works in GL Compatibility.
##
##   Grass.field(self, Rect2(-45, -45, 90, 90))                      # a meadow, flat ground
##   Grass.field(self, rect, 1.0, {"mask": func(p: Vector2) -> float: return ..., "height": ...})
##   Grass.push(player)                                              # it bends the grass
##   Grass.set_quality(Grass.Quality.LOW)                            # rebuilds every field
##
## The field node must stay unrotated and unscaled at the origin: `area` is in world metres.

enum Quality { LOW, MEDIUM, HIGH }

const PUSHERS := &"grass_pushers"
const FIELDS := &"grass_fields"
const MAX_PUSHERS := 8

## Per quality: tufts per square metre at full density, blades in a tuft, segments in a blade,
## how far full density reaches, where the grass has gone entirely, the least share kept far
## off, and whether trails are drawn.
const PRESETS := {
	Quality.LOW: {"tufts": 2.6, "blades": 7, "segments": 2, "lod_near": 6.0, "fade_end": 34.0, "keep_min": 0.08, "trails": false},
	Quality.MEDIUM: {"tufts": 3.6, "blades": 9, "segments": 3, "lod_near": 8.0, "fade_end": 44.0, "keep_min": 0.06, "trails": true},
	Quality.HIGH: {"tufts": 5.0, "blades": 11, "segments": 4, "lod_near": 11.0, "fade_end": 58.0, "keep_min": 0.06, "trails": true},
}

## The quality every field builds at. Change it with set_quality() to rebuild fields already made.
static var quality: int = Quality.MEDIUM

# --- Placement -----------------------------------------------------------------------------
## The rectangle (world x, z) the field covers.
@export var area := Rect2(-20, -20, 40, 40)
## A multiplier on the quality's tuft density (1 a full meadow, 0.3 sparse).
@export_range(0.0, 2.0) var density := 1.0
## Optional: Vector2 world xz -> 0..1, the chance of a tuft there (0 keeps grass out).
var mask: Callable
## Optional: Vector2 world xz -> float, the ground height there (default flat at y = 0).
var height: Callable
@export var seed := 1
## Side of each drawn square, metres.
@export var chunk := 10.0
## Share of tufts that are a flower instead (0 for none).
@export_range(0.0, 1.0) var flowers := 0.03

# --- Look ----------------------------------------------------------------------------------
@export var blade_height := 0.55
@export var blade_width := 0.032
## How far blades lean out of their tuft at rest, radians.
@export var lean := 0.35
@export var ground := Color(0.2, 0.31, 0.1)
@export var body := Color(0.3, 0.47, 0.13)
@export var tip := Color(0.6, 0.72, 0.27)
@export var dry := Color(0.62, 0.58, 0.26)
## How much of the field is drier, yellower swaths (0..1).
@export_range(0.0, 1.0) var dryness := 0.35
@export var petals: Array[Color] = [Color(0.95, 0.94, 0.86), Color(0.98, 0.8, 0.25), Color(0.7, 0.55, 0.9)]
## 1 for hard cel bands (the house light), 0 for smooth light.
@export_range(0.0, 1.0) var banded := 1.0
@export var wrap := 0.2
## Light shining through blades seen against the sun.
@export var translucency := 0.25

# --- Wind and pushing ----------------------------------------------------------------------
@export var wind_dir := Vector2(1.0, 0.35)
@export var wind := 0.45
## Size of the gusts, metres, and how fast they roll, metres a second.
@export var gust_size := 16.0
@export var gust_speed := 5.0
@export var flutter := 0.1
## How far a pusher lays blades over, radians.
@export var push_bend := 1.25
## Seconds a trail takes to stand back up.
@export var recover := 8.0
## Metres per trail texel.
@export var trail_cell := 0.35

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec3 ground : source_color = vec3(0.2, 0.31, 0.1);
uniform vec3 body : source_color = vec3(0.3, 0.47, 0.13);
uniform vec3 tip : source_color = vec3(0.6, 0.72, 0.27);
uniform vec3 dry : source_color = vec3(0.62, 0.58, 0.26);
uniform float dryness = 0.35;
uniform vec3 petal_a : source_color = vec3(1.0);
uniform vec3 petal_b : source_color = vec3(1.0, 0.8, 0.2);
uniform vec3 petal_c : source_color = vec3(0.7, 0.5, 0.9);
uniform float banded = 1.0;
uniform float wrap = 0.2;
uniform float translucency = 0.25;
uniform float normal_up = 0.7;

uniform float blade_height = 0.55;
uniform float blade_width = 0.045;
uniform float head_size = 0.1;
uniform float lean = 0.35;

uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind = 0.45;
uniform float gust_size = 16.0;
uniform float gust_speed = 5.0;
uniform float flutter = 0.1;

uniform vec4 pushers[8];
uniform int pusher_count = 0;
uniform float push_bend = 1.25;
uniform sampler2D trail : filter_nearest, repeat_disable;
uniform vec4 trail_rect = vec4(0.0);
uniform float now = 0.0;
uniform float recover = 8.0;
uniform vec4 blasts[4];
uniform float blast_speed = 9.0;

uniform float lod_near = 10.0;
uniform float fade_end = 44.0;
uniform float keep_min = 0.1;

varying float v_t;
varying float v_gust;
varying float v_rnd;
varying float v_patch;
varying float v_far;
varying float v_head;
varying vec2 v_petal;
varying vec3 v_normal;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 whole = floor(p);
	vec2 part = fract(p);
	part = part * part * (3.0 - 2.0 * part);
	return mix(mix(hash(whole), hash(whole + vec2(1.0, 0.0)), part.x),
			mix(hash(whole + vec2(0.0, 1.0)), hash(whole + vec2(1.0, 1.0)), part.x), part.y);
}

// The share of tufts kept at a distance: all of them near, then falling as 1 / distance
// then none by fade_end. Grass.gd keeps the same sum to set how many each square draws.
float keep_at(float d) {
	float k = d <= lod_near ? 1.0 : max(lod_near / d, keep_min);
	return k * (1.0 - smoothstep(fade_end * 0.72, fade_end, d));
}

vec2 turn(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 own = INSTANCE_CUSTOM; // yaw, size, random, rank
	float yaw = own.x * TAU;
	bool head = COLOR.a > 0.75;
	float t = head ? 1.0 : UV.y;
	float side = head ? 0.0 : UV.x;
	vec2 off = turn(UV2, yaw) * (0.6 + 0.4 * own.y);
	vec3 base = root + vec3(off.x, 0.0, off.y);
	float rnd = fract(COLOR.b + own.z * 7.13);

	float d = length(CAMERA_POSITION_WORLD - root);
	float keep = keep_at(d);
	float shown = clamp((keep * 1.15 - own.w) / max(0.15 * keep, 0.0001), 0.0, 1.0);
	float wide = clamp(1.0 / max(keep, 0.01), 1.0, 3.0);

	// Lean out of the tuft, then wind: gusts rolling through in world space, and flutter.
	vec2 wd = normalize(wind_dir + vec2(0.0001));
	vec2 out_dir = length(off) > 0.001 ? normalize(off) : vec2(cos(yaw), sin(yaw));
	vec2 bend = out_dir * lean * (0.4 + rnd);
	vec2 g = root.xz / gust_size - wd * TIME * gust_speed / gust_size;
	float gust = noise(g) * 0.65 + noise(g * 2.3 + 7.0) * 0.35;
	gust = smoothstep(0.25, 0.85, gust);
	float sway = sin(TIME * (2.2 + rnd * 1.8) + rnd * 6.28 + dot(root.xz, wd) * 0.9);
	bend += wd * wind * (0.2 + 1.2 * gust + flutter * sway * (0.5 + gust) * 3.0);
	bend += vec2(-wd.y, wd.x) * flutter * wind * sin(TIME * 3.1 + rnd * 9.0);

	// Pushers lay the grass away from them.
	for (int i = 0; i < 8; i++) {
		if (i >= pusher_count) {
			break;
		}
		vec4 p = pushers[i];
		vec2 away = base.xz - p.xz;
		float dist = length(away);
		float close = (1.0 - smoothstep(p.w * 0.35, p.w, dist)) * (1.0 - smoothstep(1.2, 2.2, abs(p.y - root.y)));
		bend += away / max(dist, 0.001) * close * push_bend;
	}
	// Blasts: a ring of wind running out from a point (x, z, time it went off, strength).
	for (int i = 0; i < 4; i++) {
		vec4 b = blasts[i];
		float age = now - b.z;
		if (b.w <= 0.0 || age < 0.0 || age > 3.0) {
			continue;
		}
		vec2 away = root.xz - b.xy;
		float dist = length(away);
		float ring = exp(-pow((dist - age * blast_speed) / 1.8, 2.0));
		float fade = b.w * (1.0 - smoothstep(0.0, 3.0, age)) / (1.0 + dist * 0.06);
		bend += away / max(dist, 0.001) * ring * fade * 1.4;
	}
	// Trails: flattened where something walked, standing back up over `recover` seconds.
	float laid = 0.0;
	if (trail_rect.z > 0.0) {
		vec2 at = (root.xz - trail_rect.xy) / trail_rect.zw;
		if (at.x > 0.0 && at.y > 0.0 && at.x < 1.0 && at.y < 1.0) {
			float stamp = textureLod(trail, at, 0.0).r;
			laid = 1.0 - smoothstep(0.0, 1.0, (now - stamp) / recover);
			bend += out_dir * laid * 1.3;
		}
	}

	float angle = min(length(bend), 1.45);
	vec2 dir = length(bend) > 0.0001 ? normalize(bend) : out_dir;
	float h = blade_height * COLOR.g * (0.55 + 0.6 * own.y) * shown * (1.0 - 0.35 * laid);
	// A blade bends along an arc of its own length (so it shortens as it lays over).
	float a = max(angle, 0.0001);
	float across = h * (1.0 - cos(a * t)) / a;
	float up = h * sin(a * t) / a;
	vec2 sv = vec2(cos(yaw + COLOR.r * TAU), sin(yaw + COLOR.r * TAU));
	float w = blade_width * wide * (0.7 + 0.5 * own.y) * (1.0 - t * t * 0.85) * side;
	vec3 pos = base + vec3(dir.x * across, up, dir.y * across) + vec3(sv.x, 0.0, sv.y) * w;

	vec3 along = vec3(dir.x * sin(a * t), cos(a * t), dir.y * sin(a * t));
	vec3 face = normalize(cross(along, vec3(sv.x, 0.0, sv.y)));
	if (face.y < 0.0) {
		face = -face;
	}
	vec3 n = normalize(mix(face, vec3(0.0, 1.0, 0.0), normal_up));

	if (head) {
		float r = length(UV);
		vec3 petal = vec3(UV.x, 0.35 * r - 0.1, UV.y) * head_size * shown * (0.7 + 0.5 * own.y);
		pos += vec3(petal.x, petal.y, petal.z) + vec3(dir.x, 0.0, dir.y) * 0.02;
		n = vec3(0.0, 1.0, 0.0);
	}

	VERTEX = pos - root;
	NORMAL = n;
	v_normal = n;
	v_t = t;
	v_gust = gust;
	v_rnd = rnd;
	v_patch = smoothstep(0.35, 0.8, noise(root.xz * 0.07 + 3.0) * 0.7 + noise(root.xz * 0.23) * 0.3);
	v_far = smoothstep(fade_end * 0.55, fade_end, d);
	v_head = head ? 1.0 : 0.0;
	v_petal = UV;
}

void fragment() {
	vec3 lush = mix(body, dry, v_patch * dryness);
	vec3 top = mix(tip, mix(tip, dry, 0.6), v_patch * dryness);
	vec3 col = mix(ground, lush, smoothstep(0.0, 0.55, v_t));
	col = mix(col, top, smoothstep(0.5, 1.0, v_t));
	col *= 0.86 + 0.28 * v_rnd;
	col = mix(col, top * 1.1, v_gust * v_t * 0.35);
	if (v_head > 0.5) {
		vec3 petal = v_rnd < 0.45 ? petal_a : (v_rnd < 0.75 ? petal_b : petal_c);
		col = mix(vec3(0.95, 0.72, 0.15), petal, smoothstep(0.18, 0.32, length(v_petal)));
	}
	ALBEDO = mix(col, ground, v_far);
	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

float cut(float value, float edge) {
	float pixel = max(fwidth(value), 0.0005);
	return smoothstep(edge - pixel, edge + pixel, value);
}

void light() {
	float reach = clamp(ATTENUATION, 0.0, 1.0);
	float towards = dot(NORMAL, LIGHT);
	float hard = cut((towards + wrap) / (1.0 + wrap) * smoothstep(0.15, 0.6, reach), 0.04) * reach;
	float soft = clamp(towards, 0.0, 1.0) * reach;
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * translucency * v_t * reach;
	DIFFUSE_LIGHT += (mix(soft, hard, banded) + through) * LIGHT_COLOR / PI;
}
"""

static var _shader: Shader
static var _meshes := {}

var _chunks: Array = []
var _materials: Array[ShaderMaterial] = []
var _preset: Dictionary
var _now := 0.0
var _trail: Image
var _trail_tex: ImageTexture
var _trail_dirty := false
var _trail_wait := 0.0
var _stamped := {}
var _instances := 0
var _blasts := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
var _next_blast := 0


## Makes a field over `area` (world x, z) under `parent` and builds it. `settings` sets any
## property by name: "mask" and "height" (callables), "seed", "flowers", colours, wind...
static func field(parent: Node, area_xz: Rect2, density_scale := 1.0, settings := {}) -> Grass:
	var made := Grass.new()
	made.area = area_xz
	made.density = density_scale
	for key: String in settings:
		made.set(key, settings[key])
	parent.add_child(made)
	made.build()
	return made


## Lets `node` push the grass aside (and leave a trail). `radius` in metres.
static func push(node: Node3D, radius := 0.7) -> void:
	node.set_meta(&"grass_radius", radius)
	node.add_to_group(PUSHERS)


static func unpush(node: Node3D) -> void:
	node.remove_from_group(PUSHERS)


## A gust that bursts out from `at` in a ring (an explosion, a downdraught, a spell), laying
## the grass of every field over as it passes. Up to four at once; `strength` about 0.5..2.
static func blast(at: Vector3, strength := 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for made in tree.get_nodes_in_group(FIELDS):
			var f := made as Grass
			f._blasts[f._next_blast] = Vector4(at.x, at.z, f._now, strength)
			f._next_blast = (f._next_blast + 1) % 4


## Sets the quality for every field from now on and rebuilds those already made.
static func set_quality(level: int) -> void:
	quality = clampi(level, Quality.LOW, Quality.HIGH)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for made in tree.get_nodes_in_group(FIELDS):
			(made as Grass).build()


## Tufts in the field, how many are drawn this frame, and their triangles.
func counts() -> Vector3i:
	var drawn := 0
	var triangles := 0
	for c: Dictionary in _chunks:
		for mmi: MultiMeshInstance3D in c.parts:
			if mmi.visible:
				drawn += mmi.multimesh.visible_instance_count
				triangles += mmi.multimesh.visible_instance_count * mmi.multimesh.mesh.surface_get_array_index_len(0) / 3
	return Vector3i(_instances, drawn, triangles)


func _ready() -> void:
	add_to_group(FIELDS)


## (Re)builds the field from its settings at the current quality.
func build() -> void:
	for c: Dictionary in _chunks:
		for mmi: Node in c.parts:
			mmi.queue_free()
	_chunks.clear()
	_instances = 0
	_preset = PRESETS[quality]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var blade_mat := _material()
	var flower_mat := _material()
	flower_mat.set_shader_parameter(&"normal_up", 0.5)
	_materials = [blade_mat, flower_mat]
	_make_trail()
	apply_settings()
	var tuft := _tuft_mesh(_preset.blades, _preset.segments)
	var tuft_far := _tuft_mesh(_preset.blades, 1)
	var bloom := _flower_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var per_m2: float = _preset.tufts * density
	if per_m2 <= 0.0:
		return
	var step := 1.0 / sqrt(per_m2)
	var nx := ceili(area.size.x / chunk)
	var nz := ceili(area.size.y / chunk)
	for cz in nz:
		for cx in nx:
			var rect := Rect2(area.position + Vector2(cx, cz) * chunk, Vector2(chunk, chunk)).intersection(area)
			var blades: Array = []
			var blooms: Array = []
			var low := INF
			var high := -INF
			var gx := floori(rect.position.x / step)
			var gz := floori(rect.position.y / step)
			while gz * step < rect.end.y:
				var x := gx
				while x * step < rect.end.x:
					var p := Vector2((x + rng.randf()) * step, (gz + rng.randf()) * step)
					x += 1
					if not rect.has_point(p):
						continue
					var chance := 1.0
					if mask.is_valid():
						chance = mask.call(p)
					if chance <= 0.0 or rng.randf() >= chance:
						continue
					var y := 0.0
					if height.is_valid():
						y = height.call(p)
					low = minf(low, y)
					high = maxf(high, y)
					var one := [p.x, y, p.y, rng.randf(), rng.randf(), rng.randf()]
					if rng.randf() < flowers:
						blooms.append(one)
					else:
						blades.append(one)
				gz += 1
			if blades.is_empty() and blooms.is_empty():
				continue
			var box := AABB(Vector3(rect.position.x - 1.5, low - 0.5, rect.position.y - 1.5),
					Vector3(rect.size.x + 3.0, high - low + 1.0 + blade_height * 2.5, rect.size.y + 3.0))
			var parts: Array = []
			for kind in 2:
				var list: Array = blades if kind == 0 else blooms
				if list.is_empty():
					continue
				_shuffle(list, rng)
				parts.append(_part(list, tuft if kind == 0 else bloom, _materials[kind], box))
				_instances += list.size()
			_chunks.append({"rect": rect, "low": low, "high": high, "parts": parts, "grass": parts[0] if not blades.is_empty() else null, "meshes": [tuft, tuft_far]})


## Pushes the exported colours, wind and lighting settings to the materials (call after
## changing them on a built field).
func apply_settings() -> void:
	for m in _materials:
		m.set_shader_parameter(&"ground", ground)
		m.set_shader_parameter(&"body", body)
		m.set_shader_parameter(&"tip", tip)
		m.set_shader_parameter(&"dry", dry)
		m.set_shader_parameter(&"dryness", dryness)
		for i in 3:
			m.set_shader_parameter(["petal_a", "petal_b", "petal_c"][i], petals[i % petals.size()] if petals.size() > 0 else Color.WHITE)
		m.set_shader_parameter(&"banded", banded)
		m.set_shader_parameter(&"wrap", wrap)
		m.set_shader_parameter(&"translucency", translucency)
		m.set_shader_parameter(&"blade_height", blade_height)
		m.set_shader_parameter(&"blade_width", blade_width)
		m.set_shader_parameter(&"lean", lean)
		m.set_shader_parameter(&"wind_dir", wind_dir)
		m.set_shader_parameter(&"wind", wind)
		m.set_shader_parameter(&"gust_size", gust_size)
		m.set_shader_parameter(&"gust_speed", gust_speed)
		m.set_shader_parameter(&"flutter", flutter)
		m.set_shader_parameter(&"push_bend", push_bend)
		m.set_shader_parameter(&"recover", recover)
		m.set_shader_parameter(&"lod_near", _preset.lod_near)
		m.set_shader_parameter(&"fade_end", _preset.fade_end)
		m.set_shader_parameter(&"keep_min", _preset.keep_min)
		m.set_shader_parameter(&"trail", _trail_tex)
		m.set_shader_parameter(&"trail_rect", Vector4(area.position.x, area.position.y, area.size.x, area.size.y) if _preset.trails else Vector4.ZERO)


func _process(delta: float) -> void:
	if _chunks.is_empty():
		return
	_now += delta
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var eye := camera.global_position
		for c: Dictionary in _chunks:
			var rect: Rect2 = c.rect
			var near := Vector3(clampf(eye.x, rect.position.x, rect.end.x), clampf(eye.y, c.low, c.high), clampf(eye.z, rect.position.y, rect.end.y))
			var dist := eye.distance_to(near)
			var share := minf(_keep(dist) * 1.15, 1.0)
			# Far squares draw each blade as one triangle.
			if c.grass != null:
				var wanted: Mesh = c.meshes[1 if dist > _preset.lod_near * 1.5 else 0]
				if c.grass.multimesh.mesh != wanted:
					c.grass.multimesh.mesh = wanted
			for mmi: MultiMeshInstance3D in c.parts:
				var count := ceili(mmi.multimesh.instance_count * share)
				mmi.visible = count > 0
				mmi.multimesh.visible_instance_count = count
	# The nearest pushers to the camera (or to the field) go to the shader.
	var found: Array = []
	for node in get_tree().get_nodes_in_group(PUSHERS):
		if node is Node3D and node.is_inside_tree():
			found.append(node)
	if camera != null and found.size() > MAX_PUSHERS:
		var eye := camera.global_position
		found.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(eye) < b.global_position.distance_squared_to(eye))
	var packed := PackedVector4Array()
	packed.resize(MAX_PUSHERS)
	var n := mini(found.size(), MAX_PUSHERS)
	for i in n:
		var node: Node3D = found[i]
		var at := node.global_position
		var radius: float = node.get_meta(&"grass_radius", 0.7)
		packed[i] = Vector4(at.x, at.y, at.z, radius)
		if _trail != null:
			_stamp(node, at, radius)
	for m in _materials:
		m.set_shader_parameter(&"pushers", packed)
		m.set_shader_parameter(&"pusher_count", n)
		m.set_shader_parameter(&"blasts", _blasts)
		m.set_shader_parameter(&"now", _now)
	_trail_wait -= delta
	if _trail_dirty and _trail_wait <= 0.0:
		_trail_tex.update(_trail)
		_trail_dirty = false
		_trail_wait = 1.0 / 15.0


func _keep(d: float) -> float:
	var near: float = _preset.lod_near
	var k := 1.0 if d <= near else maxf(near / d, _preset.keep_min)
	var end: float = _preset.fade_end
	return k * (1.0 - smoothstep(end * 0.72, end, d))


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


func _make_trail() -> void:
	_trail = null
	_stamped.clear()
	var w := 1
	var h := 1
	if _preset.trails:
		w = clampi(ceili(area.size.x / trail_cell), 1, 1024)
		h = clampi(ceili(area.size.y / trail_cell), 1, 1024)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RF)
	image.fill(Color(-10000.0, 0, 0))
	_trail_tex = ImageTexture.create_from_image(image)
	if _preset.trails:
		_trail = image


func _stamp(node: Node3D, at: Vector3, radius: float) -> void:
	var p := Vector2(at.x, at.z)
	var last: Vector2 = _stamped.get(node.get_instance_id(), Vector2(INF, INF))
	if last.distance_to(p) < trail_cell * 0.5:
		return
	var floor_y := 0.0
	if height.is_valid():
		floor_y = height.call(p)
	if absf(at.y - floor_y) > 0.6:
		return
	_stamped[node.get_instance_id()] = p
	var size := Vector2(_trail.get_width(), _trail.get_height())
	var centre := (p - area.position) / area.size * size
	var r := radius * 0.55 / area.size.x * size.x
	for y in range(floori(centre.y - r), ceili(centre.y + r) + 1):
		for x in range(floori(centre.x - r), ceili(centre.x + r) + 1):
			if x < 0 or y < 0 or x >= size.x or y >= size.y:
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(centre) <= r:
				_trail.set_pixel(x, y, Color(_now, 0, 0))
	_trail_dirty = true


func _part(list: Array, mesh: Mesh, material: ShaderMaterial, box: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	var buffer := PackedFloat32Array()
	buffer.resize(list.size() * 16)
	var count := float(list.size())
	for i in list.size():
		var one: Array = list[i]
		var o := i * 16
		buffer[o] = 1.0
		buffer[o + 3] = one[0]
		buffer[o + 5] = 1.0
		buffer[o + 7] = one[1]
		buffer[o + 10] = 1.0
		buffer[o + 11] = one[2]
		buffer[o + 12] = one[3]
		buffer[o + 13] = one[4]
		buffer[o + 14] = one[5]
		buffer[o + 15] = (i + 0.5) / count
	mm.buffer = buffer
	mm.custom_aabb = box
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep: Variant = list[i]
		list[i] = list[j]
		list[j] = keep


## A tuft: `count` blades of `segments` each. UV is (side, height along the blade), UV2 the
## blade's foot in the tuft, COLOR (turn, height, random, 0). The shader builds the rest.
static func _tuft_mesh(count: int, segments: int) -> ArrayMesh:
	var key := "tuft %d %d" % [count, segments]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	for b in count:
		var r := 0.24 * sqrt(rng.randf())
		var angle := rng.randf() * TAU
		var foot := Vector2(cos(angle), sin(angle)) * r
		var tall := clampf(rng.randf_range(0.6, 1.0) * (1.0 - 0.35 * r / 0.24) + 0.15, 0.3, 1.0)
		var colour := Color(rng.randf(), tall, rng.randf(), 0.0)
		var first := verts.size()
		for k in segments:
			var t := float(k) / segments
			for side: float in [-1.0, 1.0]:
				verts.append(Vector3(foot.x, t * 0.5, foot.y))
				uv.append(Vector2(side, t))
				uv2.append(foot)
				colours.append(colour)
		verts.append(Vector3(foot.x, 0.5, foot.y))
		uv.append(Vector2(0.0, 1.0))
		uv2.append(foot)
		colours.append(colour)
		for k in segments - 1:
			var a := first + k * 2
			index.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		var last := first + (segments - 1) * 2
		index.append_array([last, last + 1, last + 2])
	var mesh := _mesh(verts, uv, uv2, colours, index)
	_meshes[key] = mesh
	return mesh


## A flower: a thin stalk and a five-petalled head (COLOR alpha 1, UV the petal's plane).
static func _flower_mesh() -> ArrayMesh:
	if _meshes.has("flower"):
		return _meshes["flower"]
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	var stalk := Color(0.0, 1.0, 0.5, 0.0)
	for k in 2:
		for side: float in [-0.35, 0.35]:
			verts.append(Vector3(0, k * 0.25, 0))
			uv.append(Vector2(side, k * 0.5))
			uv2.append(Vector2.ZERO)
			colours.append(stalk)
	verts.append(Vector3(0, 0.5, 0))
	uv.append(Vector2(0, 1))
	uv2.append(Vector2.ZERO)
	colours.append(stalk)
	index.append_array([0, 1, 2, 1, 3, 2, 2, 3, 4])
	var centre := verts.size()
	var head := Color(0.0, 1.0, 0.5, 1.0)
	verts.append(Vector3(0, 0.5, 0))
	uv.append(Vector2.ZERO)
	uv2.append(Vector2.ZERO)
	colours.append(head)
	for i in 10:
		var r := 1.0 if i % 2 == 0 else 0.4
		var a := TAU * i / 10.0
		verts.append(Vector3(0, 0.5, 0))
		uv.append(Vector2(cos(a), sin(a)) * r)
		uv2.append(Vector2.ZERO)
		colours.append(head)
	for i in 10:
		index.append_array([centre, centre + 1 + i, centre + 1 + (i + 1) % 10])
	var mesh := _mesh(verts, uv, uv2, colours, index)
	_meshes["flower"] = mesh
	return mesh


static func _mesh(verts: PackedVector3Array, uv: PackedVector2Array, uv2: PackedVector2Array, colours: PackedColorArray, index: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 3, 4))
	return mesh
