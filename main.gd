extends Control
## The Simulatrix shell: a menu of simulations, a top bar, and a control panel that
## docks to the right in landscape and along the bottom in portrait. The UI is built
## in code; each sim describes its own controls (see sims/sim.gd).

const SIMS := [
	{title = "Playground", blurb = "Drop, pour and fling a pile of shapes.",
		color = Color("ff5fa2"), script = preload("res://sims/playground.gd")},
	{title = "Chaos Pendulum", blurb = "A double pendulum that never swings the same way twice.",
		color = Color("7aa2ff"), script = preload("res://sims/pendulum.gd")},
	{title = "Cloth", blurb = "Pull, billow, slice and tear a sheet of fabric.",
		color = Color("3de0c4"), script = preload("res://sims/cloth.gd")},
	{title = "Gravity Well", blurb = "Fling planets into orbit around a star.",
		color = Color("ffd166"), script = preload("res://sims/orbits.gd")},
	{title = "Ripple Tank", blurb = "Make waves and watch them interfere.",
		color = Color("5ec8ff"), script = preload("res://sims/waves.gd")},
]
const TOP_H := 72.0
const TEXT := Color("dfe5f5")
const DIM_TEXT := Color("8d97b3")

var current := -1
var sim: Sim
var area := Rect2()
var panel_open := true
var active := {} # touch indices that began inside the sim area
var toast_time := 0.0
var time := 0.0

var sim_layer := Node2D.new()
var top_bar := PanelContainer.new()
var title_label := Label.new()
var controls_btn := Button.new()
var panel := PanelContainer.new()
var panel_box := VBoxContainer.new()
var menu := ScrollContainer.new()
var menu_grid := HFlowContainer.new()
var cards: Array[Button] = []
var help_layer := Control.new()
var help_panel := PanelContainer.new()
var help_title := Label.new()
var help_label := Label.new()
var toast := Label.new()


func _ready() -> void:
	theme = _make_theme()
	add_child(sim_layer)
	_build_top_bar()
	_build_panel()
	_build_menu()
	_build_help()
	_build_toast()
	resized.connect(_layout)
	show_menu()


# --- building the UI ---------------------------------------------------------

func _build_top_bar() -> void:
	add_child(top_bar)
	var margin := _margin(10, 8)
	top_bar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	row.add_child(_button("Menu", show_menu))
	row.add_child(_button(" < ", func() -> void: open_sim(current - 1)))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	title_label.add_theme_font_size_override("font_size", 28)
	row.add_child(title_label)
	row.add_child(_button(" > ", func() -> void: open_sim(current + 1)))
	row.add_child(_button(" ? ", show_help))
	controls_btn.toggle_mode = true
	controls_btn.button_pressed = panel_open
	controls_btn.text = "Controls"
	controls_btn.custom_minimum_size.y = 52
	controls_btn.toggled.connect(func(on: bool) -> void:
		panel_open = on
		_layout())
	row.add_child(controls_btn)


func _build_panel() -> void:
	add_child(panel)
	var margin := _margin(16, 12)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	# keep the controls clear of the scrollbar
	var inner := MarginContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("margin_right", 14)
	scroll.add_child(inner)
	panel_box.add_theme_constant_override("separation", 14)
	inner.add_child(panel_box)


func _build_menu() -> void:
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	menu.add_child(center)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	center.add_child(spacer)
	var title := Label.new()
	title.text = "THE SIMULATRIX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("3de0c4"))
	title.add_theme_color_override("font_shadow_color", Color("ff5fa2"))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	center.add_child(title)
	var sub := Label.new()
	sub.text = "A pocket physics lab. Pick a simulation and poke at it."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", DIM_TEXT)
	center.add_child(sub)
	menu_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	menu_grid.add_theme_constant_override("h_separation", 18)
	menu_grid.add_theme_constant_override("v_separation", 18)
	center.add_child(menu_grid)
	for i in SIMS.size():
		var card := _card(SIMS[i])
		card.pressed.connect(open_sim.bind(i))
		cards.append(card)
		menu_grid.add_child(card)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 24
	center.add_child(spacer2)


func _card(info: Dictionary) -> Button:
	var card := Button.new()
	var accent: Color = info.color
	card.add_theme_stylebox_override("normal", _box(Color("141a2a"), accent.darkened(0.35), 3, 16))
	card.add_theme_stylebox_override("hover", _box(Color("1b2338"), accent, 3, 16))
	card.add_theme_stylebox_override("pressed", _box(accent.darkened(0.6), accent, 3, 16))
	card.add_theme_stylebox_override("hover_pressed", _box(accent.darkened(0.6), accent, 3, 16))
	var margin := _margin(20, 16)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)
	var name_label := Label.new()
	name_label.text = info.title
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", accent)
	box.add_child(name_label)
	var blurb := Label.new()
	blurb.text = info.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override("font_color", DIM_TEXT)
	box.add_child(blurb)
	return card


func _build_help() -> void:
	add_child(help_layer)
	help_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			help_layer.hide())
	help_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_layer.add_child(center)
	center.add_child(help_panel)
	var margin := _margin(28, 24)
	help_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)
	help_title.add_theme_font_size_override("font_size", 34)
	box.add_child(help_title)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help_label)
	var ok := _button("Got it", func() -> void: help_layer.hide())
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.custom_minimum_size.x = 160
	box.add_child(ok)
	help_layer.hide()


func _build_toast() -> void:
	add_child(toast)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bg := _box(Color(0.05, 0.06, 0.1, 0.85), Color(1, 1, 1, 0.15), 1, 14)
	bg.content_margin_left = 20
	bg.content_margin_right = 20
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	toast.add_theme_stylebox_override("normal", bg)
	toast.hide()


func _build_controls() -> void:
	for child in panel_box.get_children():
		child.free()
	var accent: Color = SIMS[current].color
	var flow: HFlowContainer = null # consecutive toggles and buttons share a row
	for spec: Dictionary in sim.controls():
		match spec.type:
			"slider":
				flow = null
				panel_box.add_child(_slider_row(spec, accent))
			"choice":
				flow = null
				panel_box.add_child(_choice_row(spec, accent))
			"toggle", "button":
				if not flow:
					flow = HFlowContainer.new()
					flow.add_theme_constant_override("h_separation", 10)
					flow.add_theme_constant_override("v_separation", 10)
					panel_box.add_child(flow)
				var b := Button.new()
				b.text = spec.label
				b.custom_minimum_size = Vector2(96, 52)
				if spec.type == "toggle":
					b.toggle_mode = true
					b.button_pressed = spec.value
					b.add_theme_stylebox_override("pressed", _box(accent.darkened(0.55), accent, 2))
					b.add_theme_stylebox_override("hover_pressed", _box(accent.darkened(0.5), accent, 2))
					b.toggled.connect(spec.on)
				else:
					b.pressed.connect(spec.on)
				flow.add_child(b)


func _slider_row(spec: Dictionary, accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := Label.new()
	name_label.text = spec.label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := Label.new()
	var fmt: String = spec.get("fmt", "%.1f")
	value_label.text = fmt % spec.value
	value_label.add_theme_color_override("font_color", accent)
	head.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = spec.min
	slider.max_value = spec.max
	slider.step = spec.step
	slider.value = spec.value
	slider.custom_minimum_size.y = 44
	var fill := _box(accent, accent, 0, 4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var on: Callable = spec.on
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt % v
		on.call(v))
	box.add_child(slider)
	return box


func _choice_row(spec: Dictionary, accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = spec.label
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var group := ButtonGroup.new()
	var on: Callable = spec.on
	for i in spec.options.size():
		var b := Button.new()
		b.text = spec.options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == spec.value
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 52
		b.clip_text = true
		b.add_theme_stylebox_override("pressed", _box(accent.darkened(0.55), accent, 2))
		b.add_theme_stylebox_override("hover_pressed", _box(accent.darkened(0.5), accent, 2))
		b.pressed.connect(func() -> void: on.call(i))
		row.add_child(b)
	return box


# --- navigation --------------------------------------------------------------

func show_menu() -> void:
	_close_sim()
	current = -1
	menu.show()
	top_bar.hide()
	panel.hide()
	help_layer.hide()
	toast.hide()
	_layout()


func open_sim(index: int) -> void:
	_close_sim()
	current = wrapi(index, 0, SIMS.size())
	var info: Dictionary = SIMS[current]
	menu.hide()
	top_bar.show()
	help_layer.hide()
	title_label.text = info.title
	title_label.add_theme_color_override("font_color", info.color)
	_layout()
	sim = info.script.new()
	sim.size = area.size
	sim_layer.add_child(sim)
	_build_controls()
	_show_toast(sim.hint())


func show_help() -> void:
	if not sim:
		return
	help_title.text = SIMS[current].title
	help_title.add_theme_color_override("font_color", SIMS[current].color)
	help_label.text = sim.help()
	help_layer.show()
	_layout()


func _close_sim() -> void:
	for index in active:
		if sim:
			sim.touch_up(index, Vector2.ZERO)
	active.clear()
	if sim:
		sim.queue_free()
		sim = null


func _show_toast(text: String) -> void:
	toast.text = text
	toast_time = 4.0
	toast.modulate.a = 1.0
	toast.show()
	_layout()


# --- layout and input --------------------------------------------------------

func _layout() -> void:
	var vs := size
	var in_sim := current != -1
	var landscape := vs.x > vs.y * 1.1
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(vs.x, TOP_H)
	var show_panel := in_sim and panel_open
	panel.visible = show_panel
	controls_btn.set_pressed_no_signal(panel_open)
	if landscape:
		var w := clampf(vs.x * 0.3, 300.0, 400.0)
		panel.position = Vector2(vs.x - w, TOP_H)
		panel.size = Vector2(w, vs.y - TOP_H)
		area = Rect2(0, TOP_H, vs.x - (w if show_panel else 0.0), vs.y - TOP_H)
	else:
		var h := clampf(vs.y * 0.34, 240.0, 470.0)
		panel.position = Vector2(0, vs.y - h)
		panel.size = Vector2(vs.x, h)
		area = Rect2(0, TOP_H, vs.x, vs.y - TOP_H - (h if show_panel else 0.0))
	sim_layer.position = area.position
	if sim and not sim.size.is_equal_approx(area.size):
		sim.resize(area.size)

	var columns := 1 if vs.x < 760 else (2 if vs.x < 1180 else 3)
	menu_grid.custom_minimum_size.x = vs.x - 48.0
	var card_w := minf((vs.x - 48.0 - 18.0 * (columns - 1)) / columns, 560.0 if columns == 1 else 380.0)
	for card in cards:
		card.custom_minimum_size = Vector2(card_w, 136)

	help_panel.custom_minimum_size.x = minf(vs.x - 40.0, 640.0)

	var toast_w := minf(area.size.x - 32.0, 620.0)
	toast.custom_minimum_size.x = toast_w
	toast.size = Vector2(toast_w, 0)
	toast.reset_size()
	toast.position = Vector2(area.position.x + (area.size.x - toast_w) * 0.5,
		area.end.y - toast.size.y - 20.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if sim and not help_layer.visible and area.has_point(p):
				active[event.index] = true
				sim.touch_down(event.index, p - area.position)
				if toast_time > 0.5:
					toast_time = 0.5
		elif active.has(event.index):
			active.erase(event.index)
			if sim:
				sim.touch_up(event.index, p - area.position)
	elif event is InputEventScreenDrag:
		if sim and active.has(event.index):
			sim.touch_move(event.index, event.position - area.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if help_layer.visible:
					help_layer.hide()
				elif current != -1:
					show_menu()
			KEY_LEFT:
				if current != -1:
					open_sim(current - 1)
			KEY_RIGHT:
				if current != -1:
					open_sim(current + 1)


func _process(delta: float) -> void:
	time += delta
	if toast_time > 0.0:
		toast_time -= delta
		toast.modulate.a = clampf(toast_time / 0.5, 0.0, 1.0)
		if toast_time <= 0.0:
			toast.hide()
	if current == -1:
		queue_redraw()


func _draw() -> void:
	if current != -1:
		return
	# menu backdrop: slow orbiting dots in the sim colours
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b0d14"))
	var center := size * 0.5
	var reach := size.length() * 0.5
	for i in 48:
		var info: Dictionary = SIMS[i % SIMS.size()]
		var r := reach * (0.15 + 0.85 * fmod(i * 0.618, 1.0))
		var a := time * (0.05 + 0.25 * (1.0 - r / reach)) * (1 if i % 2 == 0 else -1) + i * 2.4
		var p := center + Vector2(cos(a), sin(a) * 0.6) * r
		draw_circle(p, 3.0 + (i % 4) * 2.0, Color(info.color, 0.18))


# --- theme -------------------------------------------------------------------

func _margin(h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	return m


func _button(text: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(52, 52)
	b.pressed.connect(on)
	return b


func _box(bg: Color, border: Color, border_w := 2, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


func _dot(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := Vector2.ONE * (diameter - 1) * 0.5
	var r := diameter * 0.5 - 1.0
	for y in diameter:
		for x in diameter:
			var d := Vector2(x, y).distance_to(c)
			var inside := clampf(r - d + 0.5, 0.0, 1.0)
			var rim := clampf(r - 3.0 - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.lerp(Color("0b0d14"), 1.0 - rim), inside))
	return ImageTexture.create_from_image(img)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)

	t.set_stylebox("normal", "Button", _box(Color("1b2133"), Color("2e3854")))
	t.set_stylebox("hover", "Button", _box(Color("232b42"), Color("3d4a6e")))
	t.set_stylebox("pressed", "Button", _box(Color("2c3a5e"), Color("7aa2ff")))
	t.set_stylebox("hover_pressed", "Button", _box(Color("2c3a5e"), Color("7aa2ff")))
	t.set_stylebox("disabled", "Button", _box(Color("15192a"), Color("20263a")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(state, "Button", TEXT)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", Color.WHITE)

	var panel_box_style := _box(Color(0.063, 0.075, 0.114), Color("252c42"), 0, 0)
	t.set_stylebox("panel", "PanelContainer", panel_box_style)

	var track := _box(Color("2a3350"), Color("2a3350"), 0, 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_icon("grabber", "HSlider", _dot(34, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot(34, Color("dfe5f5")))

	var bar := _box(Color("1b2133"), Color("1b2133"), 0, 6)
	bar.content_margin_left = 6
	bar.content_margin_right = 6
	var grab := _box(Color("3d4a6e"), Color("3d4a6e"), 0, 6)
	grab.content_margin_left = 6
	grab.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", bar)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	return t
