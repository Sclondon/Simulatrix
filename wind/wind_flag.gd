class_name WindFlag
extends Node3D
## A flag on a pole that shows a WindField's strength and heading at a glance: it turns
## (lagging) to the wind at its top, hangs limp in calm air, stands out as the wind rises and
## ripples faster in a stronger one (wind_flag.gdshader). This node is the pole's foot.

const FLAG := preload("res://wind/wind_flag.gdshader")

@export var field: WindField
@export var pole_height := 4.2
## The cloth's size, m.
@export var flag_size := Vector2(1.6, 1.0)
@export var colour_a := Color(0.95, 0.42, 0.12)
@export var colour_b := Color(0.96, 0.94, 0.9)

var _flag := Node3D.new()
var _mat := ShaderMaterial.new()
var _yaw := 0.0


func _ready() -> void:
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.06
	cyl.height = pole_height
	pole.mesh = cyl
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.82, 0.82, 0.8)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.4
	pole.material_override = pole_mat
	pole.position = Vector3.UP * pole_height * 0.5
	add_child(pole)
	var cloth := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.orientation = PlaneMesh.FACE_Z
	pl.size = flag_size
	pl.subdivide_width = 20
	pl.subdivide_depth = 8
	pl.center_offset = Vector3(flag_size.x * 0.5, -flag_size.y * 0.5, 0)
	cloth.mesh = pl
	_mat.shader = FLAG
	_mat.set_shader_parameter(&"flag_length", flag_size.x)
	_mat.set_shader_parameter(&"colour_a", colour_a)
	_mat.set_shader_parameter(&"colour_b", colour_b)
	cloth.material_override = _mat
	_flag.add_child(cloth)
	_flag.position = Vector3.UP * (pole_height - 0.05)
	add_child(_flag)


## The wind at the top of the pole (m/s).
func air() -> Vector3:
	if field == null:
		return Vector3.ZERO
	return field.sample(global_position + Vector3.UP * pole_height)


func _process(delta: float) -> void:
	if field == null:
		return
	field.step()
	var a := air()
	var flat := Vector2(a.x, a.z)
	if flat.length() > 0.3:
		_yaw = lerp_angle(_yaw, atan2(-flat.y, flat.x) - global_rotation.y, minf(delta * 3.0, 1.0))
	_flag.rotation.y = _yaw
	_mat.set_shader_parameter(&"strength", clampf(flat.length() / 12.0, 0.0, 1.0))
