class_name WeatherRig
extends Node3D
## The weather: the sky and the time of day (Daylight), clouds you can shape (fair-weather
## cumulus, a stratus deck, a thunderstorm with its anvil, high cirrus), rain with splashes and
## wet ground, settling snow, hail, branching lightning with its flash and the thunder after,
## and fog. Add one to a scene and set its exports; it drives the environment's sky, ambient and
## fog and aims the sun.
##
## Clouds are heaps of soft puffs (cloud.gdshader, one MultiMesh, sorted back to front) wrapping
## round the camera, over a cloud layer in the sky shader (sky.gdshader). Rain, snow and hail are
## placed on the GPU round the camera (precip.gdshader). Materials that should take the weather
## (wet, snow, wind) are given to register(): weathered() makes one for trees and rocks,
## ground_material() one for the ground.
## Ideas from Hemlock's Tower's weather (puff clouds, lightning) and Mariner's; made in The
## Simulatrix's weather labs (2026-10-27).

signal struck(at: Vector3)

const CLOUD := preload("res://weather/cloud.gdshader")
const PRECIP := preload("res://weather/precip.gdshader")
const WEATHERED := preload("res://weather/weathered.gdshader")
const GROUND := preload("res://weather/ground.gdshader")
enum Clouds { CUMULUS, STRATUS, STORM, CIRRUS, ALTOCUMULUS }
enum Precip { NONE, RAIN, SNOW, HAIL }
const QUALITY := [
	{puffs = 150, rain = 1500, snow = 1500},
	{puffs = 260, rain = 3000, snow = 3000},
	{puffs = 380, rain = 5000, snow = 5000},
]
const SOUND := 343.0 # m/s, for the thunder

@export_group("Time")
## The hour, 0..24.
@export_range(0.0, 24.0, 0.25) var hour := 16.5
## Hours that pass each second (0 holds the time).
@export_range(0.0, 2.0, 0.05) var day_speed := 0.0

@export_group("Clouds")
@export var cloud_type := Clouds.CUMULUS:
	set(v): cloud_type = v; _clouds_dirty = true
@export_range(0.0, 1.0, 0.05) var cover := 0.5:
	set(v): cover = v; _clouds_dirty = true
## Height of the cloud base, m.
@export_range(100.0, 4000.0, 50.0) var base := 1300.0:
	set(v): base = v; _clouds_dirty = true
@export_range(0.3, 2.0, 0.05) var thickness := 1.0:
	set(v): thickness = v; _clouds_dirty = true
@export_range(0.0, 4.0, 0.1) var cloud_speed := 1.0
## A sunset tint on the clouds' lit side (more is added near sunrise and sunset anyway).
@export_range(0.0, 1.0, 0.05) var warmth := 0.0
## Clouds wrap round a square this far each way from the camera, m.
@export var field := 7000.0:
	set(v): field = v; _clouds_dirty = true
## Where a storm's thunderhead stands, against this node (it stays put so it can be watched).
@export var storm_at := Vector3(-5000, 0, -9200)
## How big each puff is (1: as made); fewer, bigger lumps or many small ones.
@export_range(0.3, 2.5, 0.05) var puff_size := 1.0:
	set(v): puff_size = v; _clouds_dirty = true
## How opaque the clouds are, 0..1.
@export_range(0.1, 1.0, 0.05) var density := 1.0
## How soft and wispy their edges are (1: as made; less is crisp, more is misty).
@export_range(0.2, 3.0, 0.05) var softness := 1.0
## How dark the bellies get (1: as made).
@export_range(0.0, 2.0, 0.05) var belly := 1.0
## The silver lining: thin edges glowing toward the sun (1: as made).
@export_range(0.0, 3.0, 0.05) var lining := 1.0
## A colour over the clouds (white: none).
@export var cloud_tint := Color.WHITE
## How much of the flat cloud layer painted in the sky shows with the puffs (1: as made).
@export_range(0.0, 2.0, 0.05) var sky_layer := 1.0
## How dark the shadows the clouds drift over the ground are (1: as made).
@export_range(0.0, 2.0, 0.05) var cloud_shadows := 1.0
## Another seed lays the clouds out differently.
@export var cloud_seed := 0:
	set(v): cloud_seed = v; _clouds_dirty = true

@export_group("Precipitation")
@export var precip := Precip.NONE:
	set(v): precip = v; _precip_dirty = true
@export_range(0.05, 1.0, 0.05) var intensity := 0.7:
	set(v): intensity = v; _precip_dirty = true
## The ground gets wet and snow builds up (and both go again after).
@export var settle := true
## How fast the ground wets and the snow builds up (1: as made).
@export_range(0.0, 5.0, 0.05) var settle_rate := 1.0
## How fast wet ground dries (1: as made).
@export_range(0.0, 5.0, 0.05) var dry_rate := 1.0
## How fast lying snow melts (1: as made).
@export_range(0.0, 5.0, 0.05) var melt := 1.0
## How much of the wet ground gathers into puddles (1: as made, 0 none); registered grounds.
@export_range(0.0, 2.0, 0.05) var puddles := 1.0
## How fast rain, snow and hail fall (1: as made: rain ~9.5 m/s, snow ~1.1, hail ~16).
@export_range(0.2, 3.0, 0.05) var fall_speed := 1.0:
	set(v): fall_speed = v; _precip_dirty = true
## Raindrops: how thick (1: as made), how long the streaks are (m) and how many splash (0 none).
@export_range(0.2, 4.0, 0.05) var drop_size := 1.0:
	set(v): drop_size = v; _precip_dirty = true
@export_range(0.05, 3.0, 0.05) var rain_streak := 0.8:
	set(v): rain_streak = v; _precip_dirty = true
@export_range(0.0, 3.0, 0.05) var splashes := 1.0:
	set(v): splashes = v; _precip_dirty = true
## Snowflakes and hailstones: how big (1: as made), and how much flakes flutter and drift.
@export_range(0.2, 4.0, 0.05) var flake_size := 1.0:
	set(v): flake_size = v; _precip_dirty = true
@export_range(0.0, 4.0, 0.05) var flutter := 1.0:
	set(v): flutter = v; _precip_dirty = true
## Sprites to draw instead of the built-in shapes (white in the alpha is tinted; empty: built in):
## a raindrop streak (stretched along the fall, top of the picture up), a splash, a snowflake or
## hailstone (also used for bouncing hail).
@export var drop_texture: Texture2D:
	set(v): drop_texture = v; _precip_dirty = true
@export var splash_texture: Texture2D:
	set(v): splash_texture = v; _precip_dirty = true
@export var flake_texture: Texture2D:
	set(v): flake_texture = v; _precip_dirty = true

@export_group("Lightning")
## Strikes now and then by themselves.
@export var auto_storm := false
## How often, 0 (now and then) .. 1 (often).
@export_range(0.0, 1.0, 0.05) var strike_rate := 0.5
## How far from the camera strikes land when no place is given, m (min, max).
@export var strike_range := Vector2(450.0, 2600.0)
## Share of strikes that stay in the cloud (sheet lightning: a flicker through the cloud base,
## no bolt to the ground), 0..1.
@export_range(0.0, 1.0, 0.05) var in_cloud := 0.0
## How much a bolt forks (0.5: as made).
@export_range(0.0, 1.0, 0.05) var branching := 0.5
## How jagged its path is (0.16: as made).
@export_range(0.0, 0.5, 0.01) var jaggedness := 0.16
## How thick the bolt's core is, and how much glow round it (1: as made).
@export_range(0.2, 4.0, 0.05) var bolt_width := 1.0
@export_range(0.0, 3.0, 0.05) var bolt_glow := 1.0
## The colour of the glow round the core (the core is white).
@export var bolt_color := Color(0.55, 0.6, 1.0)
## How long a strike lasts (1: as made, about half a second).
@export_range(0.2, 4.0, 0.05) var bolt_time := 1.0
## Return strokes: how many times the bolt flickers back to full brightness (2: as made).
@export_range(1, 8) var strokes := 2
## How brightly the flash lights the land and the clouds (1: as made).
@export_range(0.0, 3.0, 0.05) var flash_light := 1.0

@export_group("Air")
## Wind speed, m/s: slants the rain, drifts the clouds, sways registered trees.
@export_range(0.0, 30.0, 0.5) var wind := 5.0:
	set(v): wind = v; _precip_dirty = true
## The bearing it blows from, degrees.
@export_range(0.0, 360.0, 1.0) var wind_from := 250.0:
	set(v): wind_from = v; _precip_dirty = true
@export_range(0.0, 1.0, 0.05) var fog := 0.08
## 0 low (phones), 1 medium, 2 high: how many cloud puffs and drops.
@export_range(0, 2) var quality := 1:
	set(v): quality = v; _clouds_dirty = true; _precip_dirty = true

@export_group("Scene")
## The light to aim as the sun (or moon); empty: one is made.
@export var sun: DirectionalLight3D
## The environment to drive; empty: the world's (a WorldEnvironment's).
@export var environment: Environment
## Draw the sky (Daylight's sky shader). Off: leave the environment's sky alone.
@export var own_sky := true

## How wet the ground is, and how deep the snow lies, 0..1.
var wet := 0.0
var snow_depth := 0.0
## Lightning strikes so far.
var bolts := 0
## The light now (Daylight.at(hour)), and how much cloud and rain take out of it, 0..1.
var day: Dictionary = {}
var dim := 0.0
## Ground height at (x, z) for lightning to strike; empty: this node's height.
var ground_height: Callable
var sky_material: ShaderMaterial

var _clouds_dirty := true
var _precip_dirty := true
var _registered: Array[ShaderMaterial] = []
var _cloud_mat: ShaderMaterial
var _cloud_mm: MultiMesh
var _fall: MultiMesh
var _splash: MultiMesh
var _fall_mat: ShaderMaterial
var _splash_mat: ShaderMaterial
var _bolt_mesh := ImmediateMesh.new()
var _bolt_mat := StandardMaterial3D.new()
var _bolt_light := OmniLight3D.new()
var _rng := RandomNumberGenerator.new()
var _clusters := PackedVector3Array()
var _p_cluster := PackedInt32Array()
var _p_off := PackedVector3Array()
var _p_size := PackedFloat32Array()
var _p_custom := PackedColorArray()
var _p_flat := PackedByteArray() # 1: cut flat at the cloud base (cumulus)
var _order := PackedInt32Array()
var _sort_in := 0
var _drift := Vector2.ZERO
var _sky_drift := Vector2.ZERO
var _bolt_paths: Array = []
var _bolt_t := 99.0
var _stroke_seed := 0.0
var _bolt_at := Vector3.ZERO
var _thunder := -1.0
var _thunder_km := 0.0
var _storm_timer := 3.0
var _flash := 0.0


## Seconds until the last strike's thunder is heard (below 0: heard), and how far it struck, km.
func thunder_in() -> float:
	return _thunder


func thunder_km() -> float:
	return _thunder_km


## The flash of the last strike now, 0..1.
func flash() -> float:
	return _flash


## The way the wind blows to, on the ground (x, z).
func wind_dir() -> Vector2:
	var toward := deg_to_rad(wind_from + 180.0)
	return Vector2(sin(toward), cos(toward))


## The sky's colours now, for water and anything else that reflects the sky.
func horizon_color() -> Color:
	var c: Variant = sky_material.get_shader_parameter("horizon") if sky_material else null
	return c if c is Color else Color(0.66, 0.8, 0.94)


func zenith_color() -> Color:
	var c: Variant = sky_material.get_shader_parameter("zenith") if sky_material else null
	return c if c is Color else Color(0.13, 0.36, 0.78)


## Keeps a material's weather uniforms set every frame: wet, snow, raining, wind, wind_dir,
## zenith, horizon and the cloud shadows (uniforms it lacks are skipped).
func register(mat: ShaderMaterial) -> void:
	if not _registered.has(mat):
		_registered.append(mat)


## A material for trees, rocks and posts that sways in the wind, darkens when wet and takes
## snow on top (registered). `uv2`: sway by UV2.y (LeafyTree); else by height over `height`.
func weathered(uv2 := false, height := 10.0, tint := Color.WHITE, sways := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WEATHERED
	m.set_shader_parameter("use_uv2", 1.0 if uv2 else 0.0)
	m.set_shader_parameter("tree_height", height)
	m.set_shader_parameter("tint", tint)
	if not sways:
		m.set_meta("still", true)
	register(m)
	return m


## A material for the ground that gets wet, puddled, snowy and cloud-shadowed (registered).
func ground_material(colour_a := Color(0.16, 0.26, 0.09), colour_b := Color(0.32, 0.38, 0.14)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND
	m.set_shader_parameter("noise_tex", Daylight.cloud_noise())
	m.set_shader_parameter("colour_a", colour_a)
	m.set_shader_parameter("colour_b", colour_b)
	register(m)
	return m


## Where the rain splashes and the hail bounces: a height map (heights in metres in the red
## channel, e.g. an Image in FORMAT_RF or RH) over `rect` (x, z, width, depth). Without one,
## they land on this node's height.
func set_ground(heights: Texture2D, rect: Rect2) -> void:
	for m in [_fall_mat, _splash_mat]:
		m.set_shader_parameter("use_ground_map", heights != null)
		m.set_shader_parameter("ground_map", heights)
		m.set_shader_parameter("ground_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


## Re-applies every setting now (they are otherwise applied on the next frame).
func refresh() -> void:
	_make_clouds()
	_setup_precip()


## Clears the wet and the snow at once.
func dry() -> void:
	wet = 0.0
	snow_depth = 0.0


func _ready() -> void:
	_rng.seed = 11
	if environment == null and is_inside_tree():
		environment = get_world_3d().environment
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.shadow_enabled = true
		add_child(sun)
	sky_material = Daylight.make_sky_material()
	if own_sky and environment:
		var sky := Sky.new()
		sky.sky_material = sky_material
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if environment:
		environment.fog_enabled = true
		environment.fog_sky_affect = 0.15
	_build_clouds()
	_build_precip()
	_build_bolt()
	_make_clouds()
	_setup_precip()


func _build_clouds() -> void:
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = CLOUD
	_cloud_mat.set_shader_parameter("noise_tex", Daylight.cloud_noise())
	_cloud_mat.set_shader_parameter("fade_far", 14000.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _cloud_mat
	_cloud_mm = MultiMesh.new()
	_cloud_mm.transform_format = MultiMesh.TRANSFORM_3D
	_cloud_mm.use_custom_data = true
	_cloud_mm.mesh = quad
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _cloud_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 20000.0
	mmi.top_level = true
	add_child(mmi)


func _puff(cluster: int, off: Vector3, size: float, up: float, dark: float, squash := 1.0, flat := false) -> void:
	_p_flat.append(1 if flat else 0)
	_p_cluster.append(cluster)
	_p_off.append(off)
	_p_size.append(size * puff_size)
	_p_custom.append(Color(clampf(up, 0.0, 1.0), dark, _rng.randf(), squash))


## A heap of puffs: a flat base and a domed top, narrower as it rises.
func _heap(cluster: int, w: float, h: float, count: int, dark: float) -> void:
	for j in count:
		var t := pow(_rng.randf(), 1.3) if j > 2 else 0.0
		var rr := w * 0.5 * (1.0 - t * 0.55)
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * rr
		var size := _rng.randf_range(0.26, 0.4) * w * (1.0 - 0.3 * t)
		var y := t * h + size * 0.35
		_puff(cluster, Vector3(cos(a) * d, y, sin(a) * d), size, t, dark, 1.0 if t > 0.25 else 0.8, true)


## Lays the clouds out again for the type, cover, base and thickness.
func _make_clouds() -> void:
	_clouds_dirty = false
	if _cloud_mm == null:
		return
	_rng.seed = 100 + cloud_type + cloud_seed * 7919
	_clusters.clear()
	_p_cluster.clear(); _p_off.clear(); _p_size.clear(); _p_custom.clear(); _p_flat.clear()
	var cap: int = QUALITY[quality].puffs
	var y0 := global_position.y + base
	match cloud_type:
		Clouds.CUMULUS: # separate heaps, more and bigger with cover
			var n := roundi(cover * 64.0)
			for i in n:
				var c := _clusters.size()
				_clusters.append(Vector3(_rng.randf_range(-field, field), y0, _rng.randf_range(-field, field)))
				var w := _rng.randf_range(550.0, 1100.0) * (0.7 + 0.6 * cover)
				_heap(c, w, w * 0.5 * thickness, clampi(int(cap / maxf(n, 1)), 5, 12), 0.15 + 0.35 * cover)
		Clouds.STRATUS: # a low, flat deck of wide puffs
			var n := roundi(cover * 34.0) + 6
			for i in n:
				var c := _clusters.size()
				_clusters.append(Vector3(_rng.randf_range(-field, field), y0, _rng.randf_range(-field, field)))
				for j in clampi(cap / n, 3, 8):
					var a := _rng.randf() * TAU
					var d := _rng.randf() * 1400.0
					_puff(c, Vector3(cos(a) * d, _rng.randf_range(0.0, 120.0) * thickness, sin(a) * d),
						_rng.randf_range(650.0, 1100.0), _rng.randf_range(0.3, 0.8), 0.35, 0.45)
		Clouds.STORM: # one cumulonimbus, a tower to an anvil, ragged scud under it, heaps round it
			var c := 0
			_clusters.append(global_position + storm_at + Vector3(0, base, 0))
			var top := 4800.0 * thickness
			var tower := int(cap * 0.38)
			for j in tower:
				var t := float(j) / tower
				var rr := lerpf(1300.0, 750.0, sin(t * PI * 0.5)) * (0.8 + 0.2 * cover)
				var a := _rng.randf() * TAU
				var d := sqrt(_rng.randf()) * rr
				_puff(c, Vector3(cos(a) * d, t * top + 300.0, sin(a) * d), _rng.randf_range(650.0, 950.0), t * 0.9, 0.85, 1.0, true)
			var anvil := int(cap * 0.3)
			for j in anvil:
				var a := _rng.randf() * TAU
				var d := sqrt(_rng.randf()) * 4200.0 * (0.7 + 0.3 * cover)
				# The anvil spreads downwind
				var off := Vector3(cos(a) * d, top + _rng.randf_range(-250.0, 350.0), sin(a) * d * 0.7) + Vector3(-1200.0, 0, 600.0)
				_puff(c, off, _rng.randf_range(900.0, 1500.0), 0.85 + _rng.randf() * 0.15, 0.2, 0.42)
			for j in int(cap * 0.08):
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(600.0, 2600.0)
				_puff(c, Vector3(cos(a) * d, -_rng.randf_range(80.0, 300.0), sin(a) * d), _rng.randf_range(350.0, 650.0), 0.0, 0.7, 0.45)
			var left := cap - _p_off.size()
			var heaps := roundi(cover * 14.0)
			for i in heaps:
				var k := _clusters.size()
				_clusters.append(Vector3(_rng.randf_range(-field, field), y0, _rng.randf_range(-field, field)))
				var w := _rng.randf_range(500.0, 1000.0)
				_heap(k, w, w * 0.6 * thickness, clampi(left / maxi(heaps, 1), 4, 10), 0.6)
		Clouds.ALTOCUMULUS: # a mackerel sky: rafts of small, flattish puffs in rows
			var n := roundi(cover * 40.0) + 4
			for i in n:
				var c := _clusters.size()
				_clusters.append(Vector3(_rng.randf_range(-field, field), y0, _rng.randf_range(-field, field)))
				var rows := _rng.randf_range(-0.4, 0.4)
				var per := clampi(cap / n, 4, 14)
				for j in per:
					var along := _rng.randf_range(-1.0, 1.0) * 1300.0
					var across := (floorf(_rng.randf() * 4.0) - 1.5) * 330.0 + _rng.randf_range(-60.0, 60.0)
					var off := Vector3(along * cos(rows) - across * sin(rows), _rng.randf_range(0.0, 90.0) * thickness,
						along * sin(rows) + across * cos(rows))
					_puff(c, off, _rng.randf_range(200.0, 340.0), _rng.randf_range(0.4, 1.0), 0.15, 0.55)
		_: # Cirrus: only in the sky layer
			pass
	var n := mini(_p_off.size(), cap)
	_cloud_mm.instance_count = n
	_order.resize(n)
	for i in n:
		_order[i] = i
	_sort_in = 0


func _build_precip() -> void:
	_fall_mat = ShaderMaterial.new()
	_fall_mat.shader = PRECIP
	_splash_mat = ShaderMaterial.new()
	_splash_mat.shader = PRECIP
	for m in [_fall_mat, _splash_mat]:
		m.set_shader_parameter("ground_y", global_position.y)
	_fall = _drops(_fall_mat)
	_splash = _drops(_splash_mat)


## A MultiMesh of quads that the precip shader places itself (from INSTANCE_ID, round the camera).
func _drops(mat: ShaderMaterial) -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.custom_aabb = AABB(Vector3.ONE * -50000.0, Vector3.ONE * 100000.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.top_level = true
	add_child(mmi)
	return mm


## Sets the rain, snow or hail up for the kind, intensity and wind.
func _setup_precip() -> void:
	_precip_dirty = false
	if _fall == null:
		return
	var w := wind_dir() * wind
	var q: Dictionary = QUALITY[quality]
	_fall.instance_count = 0
	_splash.instance_count = 0
	if precip == Precip.NONE:
		return
	var fall: Vector3
	var count := 0
	match precip:
		Precip.RAIN: # ~9 m/s streaks, slanted by the wind
			fall = Vector3(w.x * 0.7, -9.5 * fall_speed, w.y * 0.7)
			count = int(q.rain * intensity)
			_fall_mat.set_shader_parameter("kind", 0)
			_fall_mat.set_shader_parameter("width", 0.012 * drop_size)
			_fall_mat.set_shader_parameter("streak", rain_streak)
			_fall_mat.set_shader_parameter("box", Vector3(40, 40, 40))
			_fall_mat.set_shader_parameter("tint", Color(0.8, 0.84, 0.92, 0.6))
		Precip.SNOW: # slow, drifting, tumbling
			fall = Vector3(w.x * 0.45, -1.1 * fall_speed, w.y * 0.45)
			count = int(q.snow * intensity)
			_fall_mat.set_shader_parameter("kind", 1)
			_fall_mat.set_shader_parameter("width", 0.06 * flake_size)
			_fall_mat.set_shader_parameter("box", Vector3(26, 26, 26))
			_fall_mat.set_shader_parameter("tint", Color(1, 1, 1, 0.95))
		Precip.HAIL: # fast pellets
			fall = Vector3(w.x * 0.4, -16.0 * fall_speed, w.y * 0.4)
			count = int(q.rain * intensity * 0.35)
			_fall_mat.set_shader_parameter("kind", 2)
			_fall_mat.set_shader_parameter("width", 0.03 * flake_size)
			_fall_mat.set_shader_parameter("box", Vector3(36, 36, 36))
			_fall_mat.set_shader_parameter("tint", Color(0.95, 0.97, 1.0, 0.95))
	_fall_mat.set_shader_parameter("fall_dir", fall.normalized())
	_fall_mat.set_shader_parameter("speed", fall.length())
	_fall_mat.set_shader_parameter("flutter", flutter)
	_sprite(_fall_mat, drop_texture if precip == Precip.RAIN else flake_texture)
	_sprite(_splash_mat, splash_texture if precip == Precip.RAIN else flake_texture)
	_fall.instance_count = maxi(count, 30)
	if precip == Precip.RAIN and splashes > 0.0:
		# Crowns where the drops land, and rings in the puddles (the ground's shader)
		_splash_mat.set_shader_parameter("kind", 3)
		_splash_mat.set_shader_parameter("width", 0.12 * sqrt(drop_size))
		_splash_mat.set_shader_parameter("rate", 3.5)
		_splash_mat.set_shader_parameter("box", Vector3(30, 30, 30))
		_splash_mat.set_shader_parameter("tint", Color(0.82, 0.86, 0.92, 0.75))
		_splash.instance_count = maxi(int(q.rain * intensity * 0.3 * splashes), 20)
	elif precip == Precip.HAIL and splashes > 0.0:
		# Hailstones bouncing
		_splash_mat.set_shader_parameter("kind", 4)
		_splash_mat.set_shader_parameter("width", 0.03 * flake_size)
		_splash_mat.set_shader_parameter("rate", 1.6)
		_splash_mat.set_shader_parameter("box", Vector3(26, 26, 26))
		_splash_mat.set_shader_parameter("tint", Color(0.95, 0.97, 1.0, 0.95))
		_splash.instance_count = maxi(int(q.rain * intensity * 0.15 * splashes), 20)


func _sprite(mat: ShaderMaterial, tex: Texture2D) -> void:
	mat.set_shader_parameter("use_sprite", tex != null)
	mat.set_shader_parameter("sprite_tex", tex)


func _build_bolt() -> void:
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.vertex_color_use_as_albedo = true
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.disable_fog = true
	# Soft across the ribbon: clear at the edges, full in the middle
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 1
	_bolt_mat.albedo_texture = tex
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20000.0
	mi.top_level = true
	add_child(mi)
	_bolt_light.light_color = Color(0.8, 0.82, 1.0)
	_bolt_light.omni_range = 4000.0
	_bolt_light.omni_attenuation = 0.6
	_bolt_light.light_energy = 0.0
	_bolt_light.top_level = true
	add_child(_bolt_light)


# --- lightning ---------------------------------------------------------------

func _ground_at(x: float, z: float) -> float:
	return ground_height.call(x, z) if ground_height.is_valid() else global_position.y


## Lightning from the cloud base to the ground: at `at`, or somewhere in front of the camera
## (`strike_range` away). `sheet`: it stays in the cloud instead, a flicker crawling through the
## cloud base over `at` (no bolt to the ground, no `struck`); null: `in_cloud` decides.
func strike(at: Variant = null, sheet: Variant = null) -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else global_position
	var in_sky: bool = sheet if sheet is bool else _rng.randf() < in_cloud
	var target: Vector3
	if at is Vector3:
		target = at
	else:
		var fwd := -cam.global_basis.z if cam else Vector3.FORWARD
		var ang := atan2(fwd.x, fwd.z) + _rng.randf_range(-0.6, 0.6)
		var d := _rng.randf_range(strike_range.x, maxf(strike_range.y, strike_range.x))
		target = Vector3(eye.x + sin(ang) * d, 0, eye.z + cos(ang) * d)
	target.y = _ground_at(target.x, target.z)
	var cloud_y := maxf(global_position.y + base, target.y + 300.0)
	_bolt_paths.clear()
	var rough := jaggedness
	if in_sky:
		# A crawler: forks spreading sideways through the cloud base
		var c := Vector3(target.x, cloud_y + 150.0, target.z)
		var a := _rng.randf() * TAU
		var reach := _rng.randf_range(700.0, 1500.0)
		var dir := Vector3(cos(a), 0.0, sin(a)) * reach
		var main := _jag(c - dir, c + dir, 7, rough * 1.2)
		_bolt_paths.append({pts = main, w = 0.7, b = 0.7})
		_branch(main, 0.5, 2, cloud_y - 150.0, true)
		target = c
	else:
		var top := target + Vector3(_rng.randf_range(-400.0, 400.0), 0, _rng.randf_range(-400.0, 400.0))
		top.y = cloud_y
		var main := _jag(top, target, 8, rough)
		_bolt_paths.append({pts = main, w = 1.0, b = 1.0})
		_branch(main, 0.55, 2, target.y, false)
	_bolt_at = target
	_bolt_t = 0.0
	_stroke_seed = _rng.randf()
	bolts += 1
	var dist := eye.distance_to(target)
	_thunder = dist / SOUND
	_thunder_km = dist / 1000.0
	_bolt_light.global_position = target + Vector3(0, 200 if not in_sky else -100, 0)
	if not in_sky:
		struck.emit(target)


## Forks off a path; `sideways` (in-cloud) forks spread level instead of reaching down.
func _branch(path: PackedVector3Array, bright: float, depth: int, ground_y: float, sideways: bool) -> void:
	if depth <= 0:
		return
	var chance := branching * 0.14
	for i in range(3, path.size() - 6):
		if _rng.randf() > chance:
			continue
		var start := path[i]
		var end: Vector3
		if sideways:
			var reach := _rng.randf_range(250.0, 700.0)
			var a := _rng.randf() * TAU
			end = start + Vector3(cos(a) * reach, _rng.randf_range(-120.0, 60.0), sin(a) * reach)
		else:
			var drop := (start.y - ground_y) * _rng.randf_range(0.15, 0.45)
			end = start + Vector3(_rng.randf_range(-0.8, 0.8) * drop, -drop, _rng.randf_range(-0.8, 0.8) * drop)
		var b := _jag(start, end, 6, jaggedness * 1.25)
		_bolt_paths.append({pts = b, w = 0.5 * bright, b = bright})
		_branch(b, bright * 0.55, depth - 1, ground_y, sideways)


## A jagged line by midpoint displacement: each pass splits every segment and nudges the middle.
func _jag(a: Vector3, b: Vector3, passes: int, rough: float) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	for p in passes:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var len := p0.distance_to(p1)
			var mid := (p0 + p1) * 0.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)) * len * rough
			next.append(p0)
			next.append(mid)
		next.append(pts[pts.size() - 1])
		pts = next
	return pts


## How bright the bolt is `t` seconds after it struck: `strokes` return strokes (each a bright
## flash then a dim gap), then it fades; all stretched by `bolt_time`.
func _bolt_brightness(t: float) -> float:
	t /= maxf(bolt_time, 0.05)
	var period := 0.135
	var end := strokes * period
	if t < end:
		var k := floori(t / period)
		var on := fmod(t, period) < 0.07
		# Later strokes a little weaker, and each a touch different
		var jitter := 1.0 if k == 0 else 0.9 + 0.1 * sin(_stroke_seed * 40.0 + k * 2.3)
		return (maxf(1.0 - 0.1 * k, 0.4) * jitter) if on else (0.15 + 0.05 * k)
	if t < end + 0.23:
		return 0.75 * (1.0 - (t - end) / 0.23)
	return 0.0


func _draw_bolt(bright: float, cam: Vector3) -> void:
	_bolt_mesh.clear_surfaces()
	if bright <= 0.0:
		return
	var dist := cam.distance_to(_bolt_at)
	# Wider when far, so it reads at any distance; a soft glow round a white core
	var core := clampf(dist * 0.0018, 0.25, 6.0) * bolt_width
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _bolt_mat)
	for pass_i in 2:
		var glow := pass_i == 0
		if glow and bolt_glow <= 0.0:
			continue
		for path in _bolt_paths:
			var pts: PackedVector3Array = path.pts
			# Ribbons with soft edges (the material's texture fades across them), joined at the
			# corners: each point's side faces the camera across the line through its neighbours
			var w: float = core * path.w * (8.0 * sqrt(bolt_glow) if glow else 1.6)
			var gc := bolt_color
			gc.a = minf(0.3 * bolt_glow, 0.95) * bright * path.b
			var col := gc if glow else Color(1, 1, 1, bright * path.b)
			var n := pts.size()
			var sides := PackedVector3Array()
			sides.resize(n)
			for i in n:
				var along := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
				sides[i] = along.cross(cam - pts[i]).normalized() * w
			_bolt_mesh.surface_set_color(col)
			for i in n - 1:
				var a0 := pts[i] - sides[i]
				var a1 := pts[i] + sides[i]
				var b0 := pts[i + 1] - sides[i + 1]
				var b1 := pts[i + 1] + sides[i + 1]
				for v in [[a0, 0.0], [a1, 1.0], [b1, 1.0], [a0, 0.0], [b1, 1.0], [b0, 0.0]]:
					_bolt_mesh.surface_set_uv(Vector2(v[1], 0.5))
					_bolt_mesh.surface_add_vertex(v[0])
	_bolt_mesh.surface_end()


# --- running -----------------------------------------------------------------

func _process(delta: float) -> void:
	if _clouds_dirty:
		_make_clouds()
	if _precip_dirty:
		_setup_precip()
	var cam_node := get_viewport().get_camera_3d()
	var cam := cam_node.global_position if cam_node else global_position
	hour = fposmod(hour + delta * day_speed, 24.0)
	var wv := wind_dir()
	var dt := minf(delta, 0.1)

	# Light: clouds and rain take the brightness out of the day
	day = Daylight.at(hour)
	var dim_target: float = [cover * 0.25, 0.45 + 0.5 * cover, 0.55 + 0.4 * cover, cover * 0.1, cover * 0.18][cloud_type] * (0.3 + 0.7 * density)
	if precip != Precip.NONE:
		dim_target = maxf(dim_target, 0.35 + 0.4 * intensity)
	dim = lerpf(dim, clampf(dim_target, 0.0, 0.95), clampf(dt * 2.0, 0.0, 1.0))
	if environment:
		Daylight.apply(day, sky_material, environment, sun, dim)

	# Lightning
	if auto_storm:
		_storm_timer -= dt
		if _storm_timer <= 0.0:
			strike()
			_storm_timer = lerpf(14.0, 1.5, strike_rate) * _rng.randf_range(0.4, 1.4)
	_bolt_t += dt
	var bright := _bolt_brightness(_bolt_t)
	_draw_bolt(bright, cam)
	_flash = maxf(bright, _flash - dt * 4.0)
	var near_flash := _flash * clampf(1.6 - cam.distance_to(_bolt_at) / 3000.0, 0.25, 1.0)
	near_flash *= flash_light
	_bolt_light.light_energy = _flash * 6.0 * flash_light
	_bolt_light.light_color = Color.WHITE.lerp(bolt_color, 0.45)
	if environment:
		environment.ambient_light_energy = 0.9 + near_flash * 2.5
	if _thunder > 0.0:
		_thunder -= dt

	# Sky layer
	_sky_drift += wv * (0.0008 + wind * 0.00015) * cloud_speed * dt
	var hor := horizon_color()
	var zen := zenith_color()
	sky_material.set_shader_parameter("cloud_offset", _sky_drift)
	sky_material.set_shader_parameter("flash", near_flash * 0.35)
	var layer := 0.0
	match cloud_type:
		Clouds.CUMULUS:
			layer = cover * 0.3
			sky_material.set_shader_parameter("cloud_scale", 2.2)
			sky_material.set_shader_parameter("cloud_stretch", Vector2(1, 2.5))
		Clouds.STRATUS:
			layer = 0.55 + cover * 0.45
			sky_material.set_shader_parameter("cloud_scale", 0.6)
			sky_material.set_shader_parameter("cloud_stretch", Vector2(1, 1))
		Clouds.STORM:
			layer = 0.5 + cover * 0.3
			sky_material.set_shader_parameter("cloud_scale", 0.8)
			sky_material.set_shader_parameter("cloud_stretch", Vector2(1, 1))
		Clouds.CIRRUS:
			layer = cover * 0.85
			sky_material.set_shader_parameter("cloud_scale", 2.6)
			sky_material.set_shader_parameter("cloud_stretch", Vector2(1, 5))
		Clouds.ALTOCUMULUS:
			layer = cover * 0.45
			sky_material.set_shader_parameter("cloud_scale", 3.2)
			sky_material.set_shader_parameter("cloud_stretch", Vector2(1, 1.6))
	sky_material.set_shader_parameter("cloud_cover", clampf(layer * sky_layer, 0.0, 1.0))
	if environment:
		var fog_d := 0.00006 + fog * fog * 0.006
		if precip != Precip.NONE:
			fog_d += intensity * (0.0012 if precip != Precip.SNOW else 0.003)
		environment.fog_density = fog_d

	# Cloud puffs
	_drift += wv * (2.0 + wind) * 6.0 * cloud_speed * dt
	var amb := environment.ambient_light_color if environment else Color(0.5, 0.55, 0.65)
	_cloud_mat.set_shader_parameter("light_dir", day.light_dir)
	_cloud_mat.set_shader_parameter("light_color", day.light_color)
	_cloud_mat.set_shader_parameter("light_energy", day.light_energy * (1.0 - dim * 0.5) * 0.85 + 0.1)
	_cloud_mat.set_shader_parameter("ambient", amb * (0.55 + 0.25 * (1.0 - day.night)))
	_cloud_mat.set_shader_parameter("horizon", hor)
	_cloud_mat.set_shader_parameter("warmth", clampf(warmth + smoothstep(0.35, 0.05, day.sun_dir.y) * (1.0 - day.night) * 0.6, 0.0, 1.0))
	_cloud_mat.set_shader_parameter("flash", _flash)
	_cloud_mat.set_shader_parameter("gloom", dim if cloud_type != Clouds.CUMULUS else dim * 0.5)
	_cloud_mat.set_shader_parameter("flash_pos", Vector3(_bolt_at.x, global_position.y + base + 300.0, _bolt_at.z))
	_cloud_mat.set_shader_parameter("flash_light", flash_light)
	_cloud_mat.set_shader_parameter("opacity", density)
	_cloud_mat.set_shader_parameter("softness", softness)
	_cloud_mat.set_shader_parameter("belly", belly)
	_cloud_mat.set_shader_parameter("lining", lining)
	_cloud_mat.set_shader_parameter("tint", cloud_tint)
	_place_puffs(cam)

	# What the rain and snow leave behind
	var raining := intensity if precip == Precip.RAIN else (intensity * 0.4 if precip == Precip.HAIL else 0.0)
	if settle:
		if raining > 0.0:
			wet = minf(wet + raining * dt * 0.08 * settle_rate, 1.0)
		else:
			wet = maxf(wet - dt * (0.004 + 0.012 * (1.0 - day.night) * (1.0 - dim)) * dry_rate, 0.0)
		if precip == Precip.SNOW or precip == Precip.HAIL:
			snow_depth = minf(snow_depth + intensity * dt * (0.03 if precip == Precip.SNOW else 0.012) * settle_rate, 1.0)
		else:
			snow_depth = maxf(snow_depth - dt * (0.002 + 0.006 * (1.0 - day.night) + raining * 0.02) * melt, 0.0)
	else:
		wet = 0.0
		snow_depth = 0.0
	for m in _registered:
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("snow", snow_depth)
		m.set_shader_parameter("raining", raining)
		m.set_shader_parameter("zenith", zen)
		m.set_shader_parameter("horizon", hor)
		m.set_shader_parameter("shadow_amount", cover * (1.0 - dim) * (1.0 - day.night) * cloud_shadows
			* [0.9, 0.0, 0.0, 0.0, 0.5][cloud_type])
		m.set_shader_parameter("puddles", puddles)
		m.set_shader_parameter("shadow_cover", cover * 0.6)
		m.set_shader_parameter("shadow_offset", _drift / 8000.0)
		m.set_shader_parameter("wind", 0.0 if m.has_meta("still") else wind)
		m.set_shader_parameter("wind_dir", wv)


## Moves every puff with the wind (wrapping round the field), and every few frames sorts them
## back to front from the camera so the soft edges blend the right way.
func _place_puffs(cam: Vector3) -> void:
	var n := _cloud_mm.instance_count
	if n == 0:
		return
	var centres := PackedVector3Array()
	centres.resize(_clusters.size())
	for c in _clusters.size():
		var k := _clusters[c]
		if cloud_type == Clouds.STORM and c == 0:
			# The thunderstorm stays where it is, so it can be watched
			centres[c] = k
			continue
		var x := fposmod(k.x + _drift.x - cam.x + field, field * 2.0) - field + cam.x
		var z := fposmod(k.z + _drift.y - cam.z + field, field * 2.0) - field + cam.z
		centres[c] = Vector3(x, k.y, z)
	var pos := PackedVector3Array()
	pos.resize(n)
	for i in n:
		pos[i] = centres[_p_cluster[i]] + _p_off[i]
	_sort_in -= 1
	if _sort_in <= 0:
		_sort_in = 8
		var d := PackedFloat32Array()
		d.resize(n)
		for i in n:
			d[i] = pos[i].distance_squared_to(cam)
		var idx := Array(_order)
		idx.sort_custom(func(a: int, b: int) -> bool: return d[a] > d[b])
		_order = PackedInt32Array(idx)
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	for slot in n:
		var i := _order[slot]
		var p := pos[i]
		var s := _p_size[i]
		var c := _p_custom[i]
		var o := slot * 16
		buf[o] = s; buf[o + 3] = p.x
		# The basis Y column is free (the shader billboards): it carries the flat base height
		buf[o + 5] = centres[_p_cluster[i]].y if _p_flat[i] else -100000.0; buf[o + 7] = p.y
		buf[o + 10] = s; buf[o + 11] = p.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
	_cloud_mm.buffer = buf
