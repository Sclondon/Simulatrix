class_name Sim
extends Node2D
## Base for every simulation. Main parks the sim at the top-left corner of the free
## play area (the space the top bar and control panel don't cover), calls resize()
## whenever that area changes, and forwards touches that start inside it.
## Mouse input arrives as touch index 0 (emulate_touch_from_mouse is on).

var size := Vector2(720, 720)


## How to play, shown by the ? button.
func help() -> String:
	return ""


## One short line shown as a toast when the sim opens.
func hint() -> String:
	return ""


## Describes the control panel. Each entry is a Dictionary:
##   {type = "slider", label, min, max, step, value, on: Callable(float), fmt = "%.1f"}
##   {type = "toggle", label, value, on: Callable(bool)}
##   {type = "choice", label, options: Array[String], value: int, on: Callable(int)}
##   {type = "button", label, on: Callable()}
func controls() -> Array:
	return []


func resize(new_size: Vector2) -> void:
	size = new_size


func touch_down(_index: int, _pos: Vector2) -> void:
	pass


func touch_move(_index: int, _pos: Vector2) -> void:
	pass


func touch_up(_index: int, _pos: Vector2) -> void:
	pass


func draw_backdrop(color: Color, grid: float = 48.0) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	var line := color.lightened(0.06)
	var x := fmod(size.x * 0.5, grid)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
		x += grid
	var y := fmod(size.y * 0.5, grid)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y += grid
