class_name ShapeBody
extends RigidBody2D
## A Playground shape that draws itself.

enum Kind { BALL, BOX, TRIANGLE }

var kind := Kind.BALL
var radius := 24.0
var color := Color.WHITE
var points := PackedVector2Array()


func setup(new_kind: Kind, new_radius: float, new_color: Color, bounce: float) -> void:
	kind = new_kind
	radius = new_radius
	color = new_color
	var shape: Shape2D
	match kind:
		Kind.BALL:
			var circle := CircleShape2D.new()
			circle.radius = radius
			shape = circle
			mass = radius * radius * 0.01
		Kind.BOX:
			var rect := RectangleShape2D.new()
			rect.size = Vector2.ONE * radius * 1.7
			shape = rect
			points = PackedVector2Array([
				Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
			for i in points.size():
				points[i] *= radius * 0.85
			mass = radius * radius * 0.012
		Kind.TRIANGLE:
			for i in 3:
				points.append(Vector2.from_angle(-PI / 2 + TAU * i / 3) * radius * 1.15)
			var poly := ConvexPolygonShape2D.new()
			poly.points = points
			shape = poly
			mass = radius * radius * 0.008
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.6
	physics_material_override.bounce = bounce
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	can_sleep = true


func _draw() -> void:
	var edge := color.lightened(0.35)
	if kind == Kind.BALL:
		draw_circle(Vector2.ZERO, radius, color)
		draw_arc(Vector2.ZERO, radius - 1.5, 0, TAU, 32, edge, 3.0, true)
		# a spoke so you can see it spin
		draw_line(Vector2.ZERO, Vector2(radius * 0.8, 0), edge, 3.0, true)
	else:
		draw_colored_polygon(points, color)
		var loop := points.duplicate()
		loop.append(points[0])
		draw_polyline(loop, edge, 3.0, true)
