class_name ValueBar
extends Control
## A number property drawn as a bar that fills to its value with the number inside it.
## Made for touch inside a scrolling panel: it only takes a drag that starts sideways, so
## an up-and-down drag over it scrolls the panel instead; a tap sets the value where you
## tapped; a double tap puts the starting value back.

signal value_changed(value: float)

## True while any bar is being dragged sideways (the panel must not start scrolling then).
static var dragging_any := false

var min_value := 0.0
var max_value := 1.0
var step := 0.01
var value := 0.0
var default_value := 0.0
var fmt := "%.1f"
var fill := Color("4f86c6")
var well := Color("1f1f22")
var edge := Color("111113")

var _press := Vector2.ZERO
var _pressed := false
var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS # wheel and vertical drags reach the scroll panel
	default_value = value


func set_value(v: float, emit := true) -> void:
	if step > 0.0:
		v = snappedf(v - min_value, step) + min_value
	v = clampf(v, min_value, max_value)
	if is_equal_approx(v, value):
		return
	value = v
	queue_redraw()
	if emit:
		value_changed.emit(value)


func _value_at(x: float) -> float:
	return lerpf(min_value, max_value, clampf(x / maxf(size.x, 1.0), 0.0, 1.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click:
				set_value(default_value)
				_pressed = false
				accept_event()
				return
			_pressed = true
			_dragging = false
			dragging_any = false
			_press = event.position
		else:
			# A tap (or a click) that stayed put sets the value there. A release far away is
			# the panel taking the touch over for a scroll, so nothing changes.
			if _pressed and not _dragging and Rect2(Vector2.ZERO, size).has_point(event.position):
				set_value(_value_at(event.position.x))
			_pressed = false
			_dragging = false
			dragging_any = false
	elif event is InputEventMouseMotion and _pressed:
		var d: Vector2 = event.position - _press
		if not _dragging and absf(d.x) > 8.0 and absf(d.x) > absf(d.y):
			_dragging = true
			dragging_any = true
		if _dragging:
			set_value(_value_at(event.position.x))
			accept_event()


func is_dragging() -> bool:
	return _dragging


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, well)
	var t := inverse_lerp(min_value, max_value, value) if max_value != min_value else 0.0
	if t > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(t, 0.0, 1.0), r.size.y)), fill)
	draw_rect(r, edge, false, 1.0)
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()
	var text := fmt % value
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2((size.x - w) * 0.5, (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
