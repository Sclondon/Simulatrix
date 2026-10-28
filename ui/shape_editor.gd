extends CanvasLayer
## The shape pad's big editing view: a card over everything (so a phone has room to draw), with
## the pad and its tools. Opened by ShapePad.open_editor(); Save keeps the sprite in ShapeStore
## and calls done(id), Cancel (or Esc) calls done("").
##
## While it is open it swallows touch events in _input, before the shell sees them, so a stroke
## never also turns the camera or pokes the sim underneath, and the panel never drag-scrolls.
## The mouse events Godot makes from those touches still reach the card's controls.

const C_DIM := Color(0, 0, 0, 0.62)
const C_CARD := Color("38383c")
const C_EDGE := Color("111113")
const C_HEAD := Color("2b2b2f")
const DIM_TEXT := Color("9a9aa3")
const PALETTE := ["ffffff", "ffd166", "ff8c42", "e4572e", "c9184a", "9d4edd", "4f86c6", "3de0c4", "6aa548",
	"3b2a1e", "7d6b5a", "111113"]
const TOOLS := ["shape", "brush", "erase"]
const TOOL_LABELS := ["Shape", "Brush", "Eraser"]

var pad := ShapePad.new()
var done: Callable
var edit_name := ""
var import_first := false
var host: Node

var root := Control.new()
var card := PanelContainer.new()
var body := BoxContainer.new()
var tools_scroll := ScrollContainer.new()
var name_edit := LineEdit.new()
var palette_row := HFlowContainer.new()
var import_box := VBoxContainer.new()
var import_from := HBoxContainer.new()
var trim_check := CheckBox.new()
var status := Label.new()
var _tool_buttons: Array[Button] = []
var _res_buttons: Array[Button] = []
var _out_buttons: Array[Button] = []
var _from_buttons: Array[Button] = []
var _source: Image # the last imported picture, to make again with other import settings
var _from := "alpha"
var _closed := false


func setup(h: Node, edit: String, on_done: Callable, imp: bool) -> void:
	host = h
	edit_name = edit
	done = on_done
	import_first = imp


func _ready() -> void:
	layer = 50
	if edit_name != "":
		var img := ShapeStore.image(edit_name)
		if img:
			pad.load_image(img)
			pad.mask = pad.is_mask()
			pad.feather = 0.0 # its soft edge is already in it
			pad._undo.clear()
		name_edit.text = edit_name
	else:
		name_edit.text = ShapeStore.unique_name("shape")
	add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _find_theme(host)
	var dim := ColorRect.new()
	dim.color = C_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	root.add_child(card)
	var s := StyleBoxFlat.new()
	s.bg_color = C_CARD
	s.border_color = C_EDGE
	s.set_border_width_all(1)
	s.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", s)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	col.add_child(_header())
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	pad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pad.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(pad)
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tools_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tools_scroll)
	tools_scroll.add_child(_tools())
	status.add_theme_color_override("font_color", DIM_TEXT)
	status.add_theme_font_size_override("font_size", 15)
	status.clip_text = true
	col.add_child(status)
	pad.changed.connect(_sync)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_sync()
	_tell("Draw round a shape: it fills when you let go. Mirror draws both halves.")
	if import_first:
		import_image()


static func _find_theme(n: Node) -> Theme:
	while n:
		if n is Control and (n as Control).theme:
			return (n as Control).theme
		n = n.get_parent()
	return null


# --- building -----------------------------------------------------------------------

func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = "SHAPE"
	t.add_theme_color_override("font_color", DIM_TEXT)
	row.add_child(t)
	name_edit.placeholder_text = "Name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(80, 42)
	row.add_child(name_edit)
	row.add_child(_button("Cancel", cancel))
	var save_b := _button("Save", save)
	save_b.custom_minimum_size.x = 84
	row.add_child(save_b)
	return row


func _tools() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_buttons = _segmented(box, "", TOOL_LABELS, func(i: int) -> void:
		pad.tool = TOOLS[i]
		_sync())
	var row := _flow()
	box.add_child(row)
	var mirror := CheckBox.new()
	mirror.text = "Mirror"
	mirror.button_pressed = pad.mirror
	mirror.custom_minimum_size = Vector2(110, 42)
	mirror.toggled.connect(func(on: bool) -> void:
		pad.mirror = on
		pad.queue_redraw())
	row.add_child(mirror)
	row.add_child(_button("Undo", func() -> void: pad.undo()))
	row.add_child(_button("Clear", func() -> void: pad.clear()))
	box.add_child(_bar("Brush", 1.0, 32.0, 1.0, pad.brush, "%d px", func(v: float) -> void: pad.brush = v))
	box.add_child(_bar("Soft edge", 0.0, 8.0, 0.5, pad.feather, "%.1f px", func(v: float) -> void:
		pad.feather = v
		pad._refresh(true)))
	_res_buttons = _segmented(box, "Pixels", ["64", "128", "256"], func(i: int) -> void:
		pad.set_res(ShapeStore.SIZES[i]))
	_out_buttons = _segmented(box, "Output", ["White mask", "Colour"], func(i: int) -> void:
		pad.mask = i == 0
		pad._refresh(true)
		_sync())
	palette_row = _flow()
	box.add_child(palette_row)
	for hex: String in PALETTE:
		var c := Color(hex)
		var b := Button.new()
		b.custom_minimum_size = Vector2(38, 38)
		for state in ["normal", "hover", "pressed"]:
			var st := StyleBoxFlat.new()
			st.bg_color = c
			st.border_color = Color.WHITE if state == "hover" else C_EDGE
			st.set_border_width_all(2)
			b.add_theme_stylebox_override(state, st)
		b.pressed.connect(func() -> void:
			pad.color = c
			_sync())
		palette_row.add_child(b)
	# how an imported picture becomes a sprite (shown after an import)
	import_box.add_theme_constant_override("separation", 6)
	box.add_child(import_box)
	_from_buttons = _segmented(import_box, "Imported image: shape from", ShapeStore.FROM_LABELS, func(i: int) -> void:
		_from = ShapeStore.FROM[i]
		_remake())
	trim_check.text = "Trim and fit"
	trim_check.button_pressed = true
	trim_check.custom_minimum_size = Vector2(150, 42)
	trim_check.toggled.connect(func(_on: bool) -> void: _remake())
	import_box.add_child(trim_check)
	import_box.hide()
	var files := _flow()
	box.add_child(files)
	files.add_child(_button("Import image...", import_image))
	return box


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	return f


func _button(text: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(72, 42)
	b.pressed.connect(on)
	return b


func _segmented(parent: Control, title: String, options: Array, on: Callable) -> Array[Button]:
	if title != "":
		var l := Label.new()
		l.text = title
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", DIM_TEXT)
		parent.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	parent.add_child(row)
	var group := ButtonGroup.new()
	var out: Array[Button] = []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(func() -> void: on.call(i))
		row.add_child(b)
		out.append(b)
	return out


func _bar(label: String, lo: float, hi: float, step: float, value: float, fmt: String, on: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	row.add_child(l)
	var bar := ValueBar.new()
	bar.min_value = lo
	bar.max_value = hi
	bar.step = step
	bar.value = value
	bar.fmt = fmt
	bar.custom_minimum_size.y = 40
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.value_changed.connect(on)
	row.add_child(bar)
	return row


## Fits the card to the screen: the pad on top on an upright screen, beside the tools lying down.
func _layout() -> void:
	if not is_inside_tree():
		return
	var vs := root.get_viewport_rect().size
	var margin := 8.0 if minf(vs.x, vs.y) < 600.0 else 24.0
	var r := Rect2(Vector2(margin, margin), vs - Vector2(margin, margin) * 2.0)
	var upright := vs.y > vs.x * 1.05
	body.vertical = upright
	var side := 0.0
	if upright:
		side = minf(r.size.x - 20.0, r.size.y - 420.0)
	else:
		side = minf(r.size.y - 110.0, r.size.x * 0.56)
	side = maxf(side, 160.0)
	pad.custom_minimum_size = Vector2(side, side)
	if upright:
		r.size.x = minf(r.size.x, maxf(side + 20.0, 420.0))
	else:
		r.size.x = minf(r.size.x, side + 470.0)
	r.position.x = (vs.x - r.size.x) * 0.5
	card.position = r.position
	card.size = r.size
	card.custom_minimum_size = Vector2.ZERO


func _sync() -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(TOOLS[i] == pad.tool)
	for i in _res_buttons.size():
		_res_buttons[i].set_pressed_no_signal(ShapeStore.SIZES[i] == pad.res)
	for i in _out_buttons.size():
		_out_buttons[i].set_pressed_no_signal((i == 0) == pad.mask)
	for i in _from_buttons.size():
		_from_buttons[i].set_pressed_no_signal(ShapeStore.FROM[i] == _from)
	palette_row.visible = not pad.mask


# --- import, save, close --------------------------------------------------------

func import_image() -> void:
	_tell("Pick a PNG, JPEG, WebP or SVG...")
	ShapeStore.pick_image(func(img: Image, file: String) -> void:
		if _closed:
			return
		take_import(img, file))


## Puts an imported picture on the pad, made into a sprite by the import settings.
func take_import(img: Image, file := "") -> void:
	_source = img
	_from = ShapeStore.guess_from(img)
	pad.mask = _from != "colour"
	import_box.show()
	if file != "" and (name_edit.text == "" or name_edit.text.begins_with("shape")):
		name_edit.text = ShapeStore.unique_name(file.get_basename())
	_remake()
	_tell("Imported %s (%d x %d)" % [file if file != "" else "an image", img.get_width(), img.get_height()])


func _remake() -> void:
	if _source == null:
		return
	pad.mask = _from != "colour"
	pad.load_image(ShapeStore.prepare(_source, _from, trim_check.button_pressed, pad.res), true)
	_sync()


func save() -> void:
	if pad.is_empty():
		_tell("Draw something first")
		return
	var name := ShapeStore.clean_name(name_edit.text)
	if edit_name == "" and ShapeStore.has(name):
		name = ShapeStore.unique_name(name)
	var id := ShapeStore.save(name, pad.result())
	_close(id)


func cancel() -> void:
	_close("")


func _close(id: String) -> void:
	if _closed:
		return
	_closed = true
	queue_free()
	if done.is_valid():
		done.call(id)


func _tell(text: String) -> void:
	status.text = text


func _input(event: InputEvent) -> void:
	if _closed:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancel()
