extends VBoxContainer
## A sprite picker for a lab's properties (made by ShapePad.picker_controls): the lab's built-in
## sprites as thumbnails, then Custom: "+ Draw", "+ Import" and the user's saved sprites
## (ShapeStore). With a custom sprite picked: Edit, Export (to the asset library) and Delete.
## on_pick(id) is called with what was picked; a custom id is "user:<name>".

const C_INSET := Color("1f1f22")
const C_EDGE := Color("111113")
const C_ACCENT := Color("4f86c6")
const DIM_TEXT := Color("9a9aa3")
const THUMB := Vector2(68, 74)

var label_text := ""
var current := ""
var on_pick: Callable
var builtins: Array = []
var _group := ButtonGroup.new()
var _custom_flow := HFlowContainer.new()
var _actions := HFlowContainer.new()
var _confirm_delete := false


func _init(label: String, cur: String, pick: Callable, built: Array) -> void:
	label_text = label
	current = cur
	on_pick = pick
	builtins = built
	add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = label
	add_child(l)
	if not builtins.is_empty():
		var flow := _flow()
		add_child(flow)
		for b: Dictionary in builtins:
			flow.add_child(_thumb(b.id, b.label, b.get("tex")))
	var custom := Label.new()
	custom.text = "Custom"
	custom.add_theme_color_override("font_color", DIM_TEXT)
	custom.add_theme_font_size_override("font_size", 15)
	add_child(custom)
	_custom_flow = _flow()
	add_child(_custom_flow)
	_actions = _flow()
	add_child(_actions)
	_fill_custom()


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 4)
	return f


func _thumb(id: String, text: String, tex: Texture2D) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _group
	b.button_pressed = id == current
	b.custom_minimum_size = THUMB
	b.text = text
	b.clip_text = true
	b.tooltip_text = text
	b.add_theme_font_size_override("font_size", 13)
	if tex:
		b.icon = tex
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.set_meta("id", id)
	b.pressed.connect(func() -> void: pick(id))
	return b


func _action(text: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(on)
	return b


## Picks a sprite by id, as a tap on its thumbnail does.
func pick(id: String) -> void:
	current = id
	_confirm_delete = false
	for b in _all_thumbs():
		b.set_pressed_no_signal(b.get_meta("id") == id)
	_fill_actions()
	if on_pick.is_valid():
		on_pick.call(id)


func _all_thumbs() -> Array:
	var out := []
	for b in _group.get_buttons():
		if is_instance_valid(b) and b.has_meta("id"):
			out.append(b)
	return out


func _fill_custom() -> void:
	for c in _custom_flow.get_children():
		c.queue_free()
	var draw := _action("+ Draw", draw_new)
	draw.custom_minimum_size = THUMB
	_custom_flow.add_child(draw)
	var imp := _action("+ Import", import_new)
	imp.custom_minimum_size = THUMB
	_custom_flow.add_child(imp)
	for name in ShapeStore.names():
		var id := ShapeStore.id_of(name)
		_custom_flow.add_child(_thumb(id, name.capitalize(), ShapeStore.texture(id)))
	_fill_actions()


func _fill_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()
	if not ShapeStore.is_custom(current) or not ShapeStore.has(ShapeStore.name_of(current)):
		return
	var name := ShapeStore.name_of(current)
	_actions.add_child(_action("Edit", func() -> void: _open(name, false)))
	if Exporter.library_root() != "" or OS.has_feature("web"):
		_actions.add_child(_action("Export", func() -> void:
			var line := ShapeStore.export_to_library(name)
			_tell(line)))
	var del := _action("Sure?" if _confirm_delete else "Delete", func() -> void: _delete(name))
	_actions.add_child(del)


func _delete(name: String) -> void:
	if not _confirm_delete:
		_confirm_delete = true
		_fill_actions()
		return
	_confirm_delete = false
	ShapeStore.remove(name)
	_fill_custom()
	if current == ShapeStore.id_of(name) and not builtins.is_empty():
		pick(builtins[0].id)


## Opens the drawing view for a new sprite.
func draw_new() -> Node:
	return _open("", false)


## Asks for an image and opens it in the drawing view, to turn into a sprite.
func import_new() -> Node:
	return _open("", true)


func _open(edit: String, import_first: bool) -> Node:
	return ShapePad.open_editor(self, edit, func(id: String) -> void:
		if id == "" or not is_instance_valid(self):
			return
		current = id
		_fill_custom()
		pick(id), import_first)


## Shows a line in the status bar, through the sim that owns this panel if it can.
func _tell(line: String) -> void:
	var main := get_tree().current_scene
	for n in get_tree().root.get_children():
		if n.has_method("_say") and n is Control:
			main = n
	if main and main.has_method("_say"):
		main.call("_say", line, 6.0)
	else:
		print(line)
