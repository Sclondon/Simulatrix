class_name Fire
extends Node3D
## A fire, drawn flat: tongues of flame cut out of noise that streams upwards,
## in three tones (a pale core, orange, dark red at the tips), with sparks
## going up from it, a little smoke, and a warm light that wavers. This node is
## at its foot.
##
##     add_child(Fire.torch())        # or candle(), brazier(), bonfire()
##
## or `Fire.new()` and set `size` (the height of the flame, in metres) and the
## rest. A fire is two draw calls (its flames; its sparks and smoke) and one
## light. Everything that moves in the flame is worked out in its shader; the
## sparks and smoke are moved here, a dozen or two of them, and drawn at once.

## How tall the flame is, in metres: 0.07 a candle, 0.3 a torch, 0.7 a brazier, 2 a bonfire.
@export var size := 0.3: set = _set_size
## How wide the fire is at its foot, as a share of its height.
@export var spread := 0.5: set = _set_spread
## How many tongues of flame it is made of (0: as many as suits its size and spread).
@export var tongues := 0: set = _set_tongues

@export_group("Colour")
## The colours, from the heart of the flame outwards.
@export var core := Color(1.0, 0.94, 0.62): set = _set_core
@export var body := Color(1.0, 0.56, 0.12): set = _set_body
@export var tip := Color(0.78, 0.16, 0.05): set = _set_tip
## Cut the flame into flat tones with hard edges. Off, they run into one another.
@export var banded := true: set = _set_banded
## How bright it all is: the flame, the sparks and the light together.
@export var intensity := 1.0: set = _set_intensity
## A faint haze of its own colour round the flame (0: none).
@export_range(0.0, 1.0) var halo := 0.22: set = _set_halo

@export_group("Motion")
## How fast the flame streams (1: as suits its size; a small flame is quicker).
@export var speed := 1.0: set = _set_speed
## How far it leans over (a draught), as a share of its height towards its own +X.
@export var lean := 0.0: set = _set_lean
## How torn the flame is: 1 a fire, 0.3 a candle flame, which barely stirs.
@export_range(0.0, 1.5) var ragged := 1.0: set = _set_ragged
## Sparks going up from it, and smoke.
@export var embers := true
@export var smoke := true

@export_group("Light")
@export var light := true: set = _set_light
@export var light_energy := 2.4
## How far the light reaches, in metres (0: as suits its size).
@export var light_range := 0.0: set = _set_light_range
@export var light_shadows := false: set = _set_light_shadows
## Where the light is, from the foot of the flame (it is put a little above the
## middle of the flame as well). A torch on a wall wants its light out from the wall.
@export var light_offset := Vector3.ZERO: set = _set_light_offset
## How much the light wavers, as a share of its strength. It wavers slowly:
## nothing in it comes round more than twice a second.
@export_range(0.0, 0.5) var flicker := 0.13

const MOTES := 24
const FLAME := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 core : source_color = vec3(1.0, 0.94, 0.62);
uniform vec3 body : source_color = vec3(1.0, 0.56, 0.12);
uniform vec3 tip : source_color = vec3(0.78, 0.16, 0.05);
uniform float banded = 1.0;
uniform float intensity = 1.0;
uniform float halo = 0.22;
// Seconds, from the script, already scaled by how fast this fire streams.
uniform float clock = 0.0;
uniform float lean = 0.0;
// How torn the flame is by the noise (a candle: hardly).
uniform float ragged = 1.0;

varying float seed;
varying float tall;

// (worked out in whole numbers: the same on every renderer, and no seams)
float hash(vec2 p) {
	ivec2 c = ivec2(round(p));
	uint h = uint(c.x) * 668265261u ^ (uint(c.y) * 374761393u);
	h ^= h >> 15u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) / 4294967295.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float cut(float value, float edge) {
	float pixel = max(fwidth(value), 0.0005);
	return smoothstep(edge - pixel, edge + pixel, value);
}

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	tall = INSTANCE_CUSTOM.y;
	// Each tongue is a card standing on its foot and turned about its upright
	// to face the camera. Looked down on, it tips back towards the eye, so
	// that it is not seen edge on.
	vec3 foot = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - foot);
	up = normalize(mix(up, INV_VIEW_MATRIX[1].xyz, smoothstep(0.55, 0.98, abs(dot(to_eye, up))) * 0.85));
	vec3 side = normalize(cross(up, to_eye) + vec3(0.00001, 0.0, 0.0));
	vec3 world = foot + side * VERTEX.x * length(MODEL_MATRIX[0].xyz) + up * VERTEX.y * length(MODEL_MATRIX[1].xyz);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = mat3(VIEW_MATRIX) * to_eye;
}

void fragment() {
	// Across the card from -0.5 to 0.5, and up it from 0 to 1.
	vec2 at = vec2(UV.x - 0.5, clamp(1.0 - UV.y, 0.0, 1.0));
	float t = clock + seed * 17.0;
	// The whole tongue wags, the top of it most.
	float wag = (vnoise(vec2(t * 0.8, seed * 91.0)) - 0.5) * 0.3 + (vnoise(vec2(t * 2.1, seed * 37.0 + 5.0)) - 0.5) * 0.1 + lean;
	at.x -= wag * at.y * at.y;
	// (and it snakes: each height of it is pushed its own way, and the push travels up)
	at.x += (vnoise(vec2(at.y * 2.6 - t * 1.3, seed * 13.0)) - 0.5) * 0.24 * at.y * ragged;
	// Noise streaming up through it: big licks, and small ones going faster.
	float big = vnoise(vec2(at.x * 4.2 + seed * 31.0, at.y * 2.6 * tall - t * 1.5));
	float fine = vnoise(vec2(at.x * 9.5 + seed * 57.0, at.y * 5.4 * tall - t * 2.7));
	float n = big * 0.65 + fine * 0.35;
	// The shape it is cut from: round at the foot, drawn in to a point at the top.
	float wide = 0.36 * (0.1 + 0.9 * pow(1.0 - at.y, 1.1)) * sqrt(smoothstep(-0.02, 0.16, at.y));
	float bell = 1.0 - abs(at.x) / max(wide, 0.0001);
	// How hot: hottest low down in the middle; the noise eats at it more the higher it is.
	float heat = bell * (1.1 - at.y * 0.55) + (n - 0.5) * (0.5 + at.y * 1.6) * ragged - at.y * 0.38;
	heat = min(heat, bell * 2.5 + 0.2);
	float flame;
	vec3 colour;
	if (banded > 0.5) {
		flame = cut(heat, 0.1);
		colour = mix(mix(tip, body, cut(heat, 0.34)), core, cut(heat, 0.72));
	} else {
		flame = smoothstep(0.02, 0.2, heat);
		colour = mix(mix(tip, body, smoothstep(0.1, 0.45, heat)), core, smoothstep(0.45, 0.85, heat));
	}
	// A haze round it.
	float from_middle = length(vec2(at.x * 2.4, (at.y - 0.3) * 1.5));
	float haze = (1.0 - smoothstep(0.0, 1.0, from_middle)) * halo;
	haze *= haze * 3.0 * (0.85 + 0.3 * big);
	ALBEDO = mix(body, colour, flame) * intensity;
	ALPHA = max(flame, haze);
}
"""

## Sparks and smoke: flat shapes turned to the camera. A spark is a small
## bright fleck that does not need lighting; a puff of smoke is a dark, ragged
## cloud in two tones that is lit by what is about, and thins to a ring.
const MOTE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 spark : source_color = vec3(1.0, 0.6, 0.15);
uniform vec3 hot : source_color = vec3(1.0, 0.94, 0.62);
uniform vec3 soot : source_color = vec3(0.2, 0.18, 0.17);
uniform float intensity = 1.0;
uniform float thickness = 0.22;

varying float age;
varying float seed;
varying float kind;

void vertex() {
	age = INSTANCE_CUSTOM.x;
	seed = INSTANCE_CUSTOM.y;
	kind = INSTANCE_CUSTOM.z;
	float big = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * big, INV_VIEW_MATRIX[1] * big, INV_VIEW_MATRIX[2] * big, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float cut(float value, float edge) {
	float pixel = max(fwidth(value), 0.0005);
	return smoothstep(edge - pixel, edge + pixel, value);
}

void fragment() {
	vec2 at = UV * 2.0 - 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (kind < 0.5) {
		// A spark: a diamond, pale while it is new, then orange, then gone.
		float fleck = cut(1.0 - (abs(at.x) + abs(at.y)), 0.0);
		ALBEDO = vec3(0.0);
		EMISSION = mix(hot, spark, smoothstep(0.0, 0.4, age)) * intensity * (1.0 - smoothstep(0.6, 1.0, age) * 0.6);
		ALPHA = fleck * (1.0 - smoothstep(0.75, 1.0, age));
	} else {
		float around = atan(at.y, at.x);
		float rim = 0.84 + 0.11 * sin(around * 5.0 + seed * 40.0) + 0.05 * sin(around * 9.0 - seed * 23.0);
		float from_middle = length(at) / rim;
		float cloud = cut(1.0 - from_middle, 0.0);
		ALBEDO = soot * mix(0.7, 1.0, cut(at.y - at.x * 0.4 + 0.25, 0.0));
		// (lit a little from below by the fire while it is new)
		EMISSION = spark * 0.12 * intensity * (1.0 - smoothstep(0.0, 0.3, age));
		ALPHA = cloud * thickness * smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(0.35, 1.0, age));
	}
}

void light() {
	DIFFUSE_LIGHT += clamp(ATTENUATION, 0.0, 1.0) * LIGHT_COLOR / PI * 0.7;
}
"""

static var _flame_shader: Shader
static var _mote_shader: Shader

var _flames: MultiMeshInstance3D
var _motes: MultiMeshInstance3D
var _lamp: OmniLight3D
var _flame_material: ShaderMaterial
var _mote_material: ShaderMaterial
var _time := 0.0
var _clock := 0.0
## Each spark or puff: where, which way it is going, how big, how old (1:
## spent), a number of its own, and which it is (0: spark, 1: smoke).
var _at := PackedVector3Array()
var _going := PackedVector3Array()
var _big := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _kind := PackedFloat32Array()
var _next := 0
var _spark_due := 0.0
var _smoke_due := 0.0


## A candle flame: no sparks, no smoke, a small light.
static func candle() -> Fire:
	var fire := _make(0.07, 0.42, 0.7, 3.0, false, false)
	fire.ragged = 0.3
	fire.flicker = 0.07
	return fire

## A torch on a wall or in a hand.
static func torch() -> Fire:
	return _make(0.3, 0.5, 2.4, 9.0, true, true)

## A bowl of fire on a stand.
static func brazier() -> Fire:
	return _make(0.7, 0.8, 3.2, 12.0, true, true)

## A big fire on the ground.
static func bonfire() -> Fire:
	return _make(2.0, 0.85, 5.0, 20.0, true, true)


static func _make(tall: float, wide: float, energy: float, reach: float, sparks: bool, smokes: bool) -> Fire:
	var fire := Fire.new()
	fire.size = tall
	fire.spread = wide
	fire.light_energy = energy
	fire.light_range = reach
	fire.embers = sparks
	fire.smoke = smokes
	return fire


func _ready() -> void:
	# (no two fires in step)
	_time = randf() * 50.0
	_clock = randf() * 50.0
	_build()


func _process(delta: float) -> void:
	_time += delta
	# (a small flame streams faster than a big one: about as the root of its height)
	_clock += delta * speed * 1.15 / pow(maxf(size, 0.02), 0.4)
	_flame_material.set_shader_parameter(&"clock", _clock)
	# Three slow wavers that never quite line up.
	var waver := 0.55 * sin(_time * 2.9) + 0.3 * sin(_time * 5.3 + 1.0) + 0.15 * sin(_time * 11.7 + 2.0)
	if _lamp:
		_lamp.light_energy = light_energy * intensity * (1.0 + flicker * waver)
	_flames.scale = Vector3(1.0, 1.0 + 0.35 * flicker * waver, 1.0)
	_move_motes(delta)


## The height of the card a tongue of flame is drawn on: the flame itself
## reaches about four fifths of the way up it.
func _reach() -> float:
	return size * 1.3


func _build() -> void:
	for child in [_flames, _motes, _lamp]:
		if child:
			child.queue_free()
	_lamp = null
	if _flame_shader == null:
		_flame_shader = Shader.new()
		_flame_shader.code = FLAME
		_mote_shader = Shader.new()
		_mote_shader.code = MOTE

	_flame_material = ShaderMaterial.new()
	_flame_material.shader = _flame_shader
	var card := QuadMesh.new()
	card.center_offset = Vector3(0.0, 0.5, 0.0)
	card.material = _flame_material
	_flames = MultiMeshInstance3D.new()
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = card
	var count := tongues
	if count <= 0:
		# (a narrow flame is one tongue; a wide fire needs several to fill it)
		count = clampi(roundi(spread * 5.0 + size * 1.5 - 1.6), 1, 8)
	mesh.instance_count = count
	var foot := size * spread
	var random := RandomNumberGenerator.new()
	random.seed = hash(get_path()) if is_inside_tree() else 1
	for i in count:
		# The first stands in the middle, full height; the rest round it, shorter.
		var round := i * 2.4 + random.randf() * 0.6
		var out := 0.0 if i == 0 else foot * 0.45 * sqrt(float(i) / count)
		var tall := 1.0 if i == 0 else random.randf_range(0.6, 0.88)
		# (a tongue is always the same shape: `spread` sets how many there are
		# and how far apart they stand, not how fat each is)
		var basis := Basis.from_scale(Vector3(_reach() * tall * 0.8, _reach() * tall, 1.0))
		mesh.set_instance_transform(i, Transform3D(basis, Vector3(cos(round) * out, 0.0, sin(round) * out)))
		mesh.set_instance_custom_data(i, Color(random.randf(), 1.0, 0.0, 0.0))
	_flames.multimesh = mesh
	_flames.extra_cull_margin = _reach()
	add_child(_flames)

	_mote_material = ShaderMaterial.new()
	_mote_material.shader = _mote_shader
	var disc := QuadMesh.new()
	disc.material = _mote_material
	_motes = MultiMeshInstance3D.new()
	_motes.top_level = true
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.extra_cull_margin = 16384.0
	_motes.multimesh = MultiMesh.new()
	_motes.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_motes.multimesh.use_custom_data = true
	_motes.multimesh.mesh = disc
	_motes.multimesh.instance_count = MOTES
	_at.resize(MOTES)
	_going.resize(MOTES)
	_big.resize(MOTES)
	_age.resize(MOTES)
	_life.resize(MOTES)
	_seed.resize(MOTES)
	_kind.resize(MOTES)
	_age.fill(1.0)
	for i in MOTES:
		_motes.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	add_child(_motes)
	_motes.global_transform = Transform3D.IDENTITY

	if light:
		_lamp = OmniLight3D.new()
		_lamp.omni_attenuation = 1.3
		add_child(_lamp)
	_dress()


## Passes the settings on to what is drawn.
func _dress() -> void:
	if _flame_material == null:
		return
	for setting: StringName in [&"core", &"body", &"tip", &"intensity", &"halo", &"lean", &"ragged"]:
		_flame_material.set_shader_parameter(setting, get(setting))
	_flame_material.set_shader_parameter(&"banded", 1.0 if banded else 0.0)
	_mote_material.set_shader_parameter(&"spark", body)
	_mote_material.set_shader_parameter(&"hot", core)
	_mote_material.set_shader_parameter(&"intensity", intensity)
	if _lamp:
		# (the colour of the body of the flame, a little towards its core)
		_lamp.light_color = body.lerp(core, 0.3)
		_lamp.omni_range = light_range if light_range > 0.0 else 4.0 + 10.0 * sqrt(size)
		_lamp.shadow_enabled = light_shadows
		_lamp.position = Vector3(0.0, size * 0.55, 0.0) + light_offset


func _move_motes(delta: float) -> void:
	var foot := size * spread
	var top := global_position + global_basis.y * size * 0.55
	if embers and size >= 0.15:
		_spark_due -= delta
		if _spark_due <= 0.0:
			# (a torch throws one every half second or so; a bonfire several a second)
			_spark_due = randf_range(0.5, 1.5) * 0.28 / sqrt(size)
			var out := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			_emit(top + out * foot * 0.3, out * 0.25 * sqrt(size) + Vector3.UP * randf_range(1.0, 2.2) * sqrt(size),
					randf_range(0.012, 0.024) * (0.6 + 0.7 * sqrt(size)), randf_range(0.7, 1.5), 0.0)
	if smoke and size >= 0.15:
		_smoke_due -= delta
		if _smoke_due <= 0.0:
			_smoke_due = randf_range(0.35, 0.6)
			var out := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			_emit(global_position + global_basis.y * size * 0.95 + out * foot * 0.15, out * 0.08 + Vector3.UP * randf_range(0.5, 0.8) * sqrt(size),
					randf_range(0.5, 0.8) * size * maxf(spread, 0.5), randf_range(1.6, 2.4), 1.0)
	var mesh := _motes.multimesh
	for i in MOTES:
		if _age[i] >= 1.0:
			continue
		_age[i] = minf(_age[i] + delta / _life[i], 1.0)
		if _age[i] >= 1.0:
			mesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), _at[i]))
			continue
		var age := _age[i]
		var grown := _big[i]
		if _kind[i] < 0.5:
			# A spark wanders as it rises, and slows.
			_going[i] += Vector3(sin(_time * 7.0 + _seed[i] * 40.0), 0.0, cos(_time * 6.0 + _seed[i] * 23.0)) * delta * 1.2 * sqrt(size)
			_going[i] *= exp(-0.9 * delta)
		else:
			# Smoke swells as it goes up, and drifts off the way the fire leans.
			_going[i].x += lean * delta * 0.6
			grown *= 0.45 + 0.9 * age
		_at[i] += _going[i] * delta
		mesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * grown), _at[i]))
		mesh.set_instance_custom_data(i, Color(age, _seed[i], _kind[i], 0.0))


func _emit(at: Vector3, going: Vector3, big: float, life: float, kind: float) -> void:
	var i := _next
	_next = (_next + 1) % MOTES
	_at[i] = at
	_going[i] = going
	_big[i] = big
	_age[i] = 0.0
	_life[i] = life
	_seed[i] = randf()
	_kind[i] = kind


# --- Settings ---

func _rebuild() -> void:
	if is_inside_tree():
		_build()

func _set_size(value: float) -> void:
	size = value
	_rebuild()

func _set_spread(value: float) -> void:
	spread = value
	_rebuild()

func _set_tongues(value: int) -> void:
	tongues = value
	_rebuild()

func _set_light(value: bool) -> void:
	light = value
	_rebuild()

func _set_core(value: Color) -> void:
	core = value
	_dress()

func _set_body(value: Color) -> void:
	body = value
	_dress()

func _set_tip(value: Color) -> void:
	tip = value
	_dress()

func _set_banded(value: bool) -> void:
	banded = value
	_dress()

func _set_intensity(value: float) -> void:
	intensity = value
	_dress()

func _set_halo(value: float) -> void:
	halo = value
	_dress()

func _set_speed(value: float) -> void:
	speed = value

func _set_ragged(value: float) -> void:
	ragged = value
	_dress()

func _set_lean(value: float) -> void:
	lean = value
	_dress()

func _set_light_range(value: float) -> void:
	light_range = value
	_dress()

func _set_light_shadows(value: bool) -> void:
	light_shadows = value
	_dress()

func _set_light_offset(value: Vector3) -> void:
	light_offset = value
	_dress()
