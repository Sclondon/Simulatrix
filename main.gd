extends Control
## The Simulatrix shell, laid out like a desktop editor: a menu bar, a tab for the open
## sim, a Simulations browser docked left (landscape only), the viewport, a Properties
## panel docked right in landscape and along the bottom in portrait, and a status bar.
## The UI is built in code; each sim describes its own controls (see sims/sim.gd).

## One list, with like sims side by side: bodies and cloth; gravity; fields and light;
## waves and water; air and plants; sand; fire and effects; then the tools.
var SIMS := [
	{title = "Playground", blurb = "Rigid bodies: drop, pour and fling shapes.",
		color = Color("ff5fa2"), script = preload("res://sims/playground.gd")},
	{title = "Chaos Pendulum", blurb = "Double pendulum, RK4, three ghosts 0.001 rad apart.",
		color = Color("7aa2ff"), script = preload("res://sims/pendulum.gd")},
	{title = "Cloth", blurb = "Verlet cloth that billows, cuts and tears.",
		color = Color("3de0c4"), script = preload("res://sims/cloth.gd")},
	{title = "Gravity Well", blurb = "Inverse-square orbits, merging collisions.",
		color = Color("ffd166"), script = preload("res://sims/orbits.gd")},
	{title = "Orbits 3D", blurb = "Launch satellites round Atlas's Earth and Moon by hand.",
		color = Color("5fd7ff"), script = preload("res://sims/orbits3d.gd")},
	{title = "Charge Field", blurb = "Coulomb field, contours and field lines.",
		color = Color("ff6b6b"), script = preload("res://sims/field.gd")},
	{title = "Light Bench", blurb = "2D ray tracing through prisms, lenses, mirrors.",
		color = Color("c38bff"), script = preload("res://sims/optics.gd")},
	{title = "Ripple Tank", blurb = "Wave interference and the double slit.",
		color = Color("5ec8ff"), script = preload("res://sims/waves.gd")},
	{title = "Fluid", blurb = "Particle fluid drawn as metaballs.",
		color = Color("4aa8ff"), script = preload("res://sims/fluid.gd")},
	{title = "Pond", blurb = "Stones, splashes and wakes in clear water.",
		color = Color("4fc3d9"), script = preload("res://sims/vfx/pond.gd")},
	{title = "Ocean", blurb = "Wind-driven Gerstner sea with whitecaps and things that float.",
		color = Color("3a8fd8"), script = preload("res://sims/vfx/ocean.gd")},
	{title = "Weather Lab", blurb = "Shape clouds, make rain, snow, hail and lightning.",
		color = Color("9fb4d8"), script = preload("res://sims/vfx/weather.gd")},
	{title = "Wind", blurb = "One wind field moving grass, trees, leaves and a flag.",
		color = Color("b8e0ff"), script = preload("res://sims/vfx/wind.gd")},
	{title = "Grass", blurb = "Real 3D blades: part them, roll a ball through, blast them flat.",
		color = Color("8fd14f"), script = preload("res://sims/vfx/grass.gd")},
	{title = "Tree Lab", blurb = "Grow pines, broadleaf and painted trees from code, then bend every setting.",
		color = Color("7ccf5a"), script = preload("res://sims/vfx/trees.gd")},
	{title = "Falling Sand", blurb = "Cellular automaton: sand, water, fire, lava.",
		color = Color("e8b86a"), script = preload("res://sims/sand.gd")},
	{title = "Sand", blurb = "Draw, paint and pour sand while the wind blows.",
		color = Color("e2b46b"), script = preload("res://sims/vfx/sand3d.gd")},
	{title = "Fire", blurb = "Candle to bonfire, any colour, lit at night.",
		color = Color("ff8a3d"), script = preload("res://sims/vfx/fire.gd")},
	{title = "Particle Editor", blurb = "Layer emitters into effects, Unity / Godot style, and export them as Godot scenes.",
		color = Color("ff9f43"), script = preload("res://sims/vfx/particles.gd")},
	{title = "Texture Lab", blurb = "Procedural noise and material textures on the GPU: tile, preview in 3D, save PNG.",
		color = Color("9f8cff"), script = preload("res://sims/vfx/texture_lab.gd")},
	{title = "Shader Lab", blurb = "Write Godot shaders live: presets, errors by line, uniforms as properties.",
		color = Color("f07ad6"), script = preload("res://sims/vfx/shader_lab.gd")},
]

const MENU_H := 44.0
const TAB_H := 38.0
const STATUS_H := 34.0
const HEAD_H := 30.0

# Palette: neutral greys with bevelled edges, after Aseprite's dark theme
const C_BACK := Color("1c1c1e")
const C_FACE := Color("38383c")
const C_FACE_HI := Color("46464b")
const C_FACE_LO := Color("2b2b2f")
const C_EDGE := Color("111113")
const C_LIGHT := Color("5c5c63")
const C_SHADE := Color("232326")
const C_INSET := Color("1f1f22")
const C_ACCENT := Color("4f86c6")
const C_ACCENT_HI := Color("6fa3de")
const TEXT := Color("e2e2e6")
const DIM_TEXT := Color("9a9aa3")

## Phones (a short side under 600 CSS px): the whole UI is scaled up, touch rows grow by `k`,
## the menu bar is pared down, and Properties becomes a bottom sheet (or a side panel lying down).
var compact := false
var k := 1.0
var sheet_tall := false

## Drag-to-scroll for the panels, so a drag that starts on a button or a value bar still scrolls.
var scrollers: Array[ScrollContainer] = []
var drag_scroll: ScrollContainer = null
var drag_index := -1
var drag_from := Vector2.ZERO
var drag_scroll_from := 0.0
var drag_scrolling := false
var drag_velocity := 0.0
var fling: ScrollContainer = null
var fling_velocity := 0.0

var current := -1
var sim: Sim
var area := Rect2()
var panel_open := true
var browser_open := true
var active := {} # touch indices that began inside the sim area
var folded := {} # section label -> true when folded, for the open sim
var message := ""
var message_time := 0.0
var status_tick := 0.0
var font: Font = preload("res://fonts/PixelifySans.ttf")

var sim_layer := Node2D.new()
var menu_bar := PanelContainer.new()
var sims_menu := MenuButton.new()
var view_menu := MenuButton.new()
var menu_title := Label.new()
var props_btn := Button.new()
var panel_scroll := ScrollContainer.new()
var tab_bar := PanelContainer.new()
var tab_title := Label.new()
var tab_swatch := ColorRect.new()
var tab_close := Button.new()
var browser := PanelContainer.new()
var browser_rows: Array[Button] = []
var panel := PanelContainer.new()
var panel_title := Label.new()
var panel_box := VBoxContainer.new()
var home := ScrollContainer.new()
var home_grid := GridContainer.new()
var status_bar := PanelContainer.new()
var status_left := Label.new()
var status_right := Label.new()
var help_layer := Control.new()
var help_panel := PanelContainer.new()
var help_title := Label.new()
var help_label := Label.new()


func _ready() -> void:
	compact = _short_side_css() < 600.0 or "--compact" in OS.get_cmdline_user_args()
	k = 1.3 if compact else 1.0
	_fit_scale()
	theme = _make_theme()
	add_child(sim_layer)
	_build_menu_bar()
	_build_tab_bar()
	_build_browser()
	_build_panel()
	_build_home()
	_build_status_bar()
	_build_help()
	resized.connect(_layout)
	show_menu()


## The shorter side of the window in CSS pixels (device pixels on the web are divided by the
## device pixel ratio).
func _short_side_css() -> float:
	var win := Vector2(DisplayServer.window_get_size())
	return minf(win.x, win.y) / maxf(DisplayServer.screen_get_scale(), 1.0)


## Scales everything up on small screens so that text and touch targets come out a usable size.
func _fit_scale() -> void:
	var f := clampf(560.0 / maxf(_short_side_css(), 1.0), 1.0, 1.6) if compact else 1.0
	if not is_equal_approx(get_window().content_scale_factor, f):
		get_window().content_scale_factor = f


# --- building the UI ---------------------------------------------------------

func _build_menu_bar() -> void:
	add_child(menu_bar)
	menu_bar.add_theme_stylebox_override("panel", _bevel(C_FACE, C_LIGHT, C_SHADE, C_EDGE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	menu_bar.add_child(row)
	if compact:
		_build_compact_bar(row)
		return
	var logo := Label.new()
	logo.text = " SIMULATRIX "
	logo.add_theme_color_override("font_color", C_ACCENT_HI)
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(logo)

	sims_menu.text = "Sims"
	_style_menu(sims_menu)
	var popup := sims_menu.get_popup()
	for i in SIMS.size():
		popup.add_item(SIMS[i].title, i)
	popup.id_pressed.connect(open_sim)
	row.add_child(sims_menu)

	view_menu.text = "View"
	_style_menu(view_menu)
	var view := view_menu.get_popup()
	view.add_check_item("Simulations", 0)
	view.add_check_item("Properties", 1)
	view.add_separator()
	view.add_item("Reset sim", 2)
	view.add_item("Home", 3)
	view.about_to_popup.connect(func() -> void:
		view.set_item_checked(0, browser_open)
		view.set_item_checked(1, panel_open))
	view.id_pressed.connect(func(id: int) -> void:
		match id:
			0: browser_open = not browser_open
			1: panel_open = not panel_open
			2: if current != -1: open_sim(current)
			3: show_menu()
		_layout())
	row.add_child(view_menu)

	var help_menu := MenuButton.new()
	help_menu.text = "Help"
	_style_menu(help_menu)
	help_menu.get_popup().add_item("About this sim", 0)
	help_menu.get_popup().add_item("Viewport controls", 1)
	help_menu.get_popup().id_pressed.connect(func(id: int) -> void:
		if id == 0:
			show_help()
		else:
			_show_dialog("Viewport controls", "2D sims: touch or click inside the viewport to interact.\n\n"
				+ "VFX sims: drag to orbit, pinch or scroll to zoom, two-finger drag to pan. Pokeable sims have a "
				+ "Finger property: switch it to Poke to touch the scene instead of turning the camera.\n\n"
				+ "Keys: Left/Right step through sims, Esc closes the sim."))
	row.add_child(help_menu)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_tool_button("<", func() -> void: open_sim(current - 1 if current != -1 else SIMS.size() - 1)))
	row.add_child(_tool_button(">", func() -> void: open_sim(current + 1)))
	row.add_child(_tool_button("?", show_help))


## Phones: Sims (the list), the open sim's name, step buttons, help, and a Properties toggle.
func _build_compact_bar(row: HBoxContainer) -> void:
	row.add_theme_constant_override("separation", 4)
	row.add_child(_tool_button("Sims", show_menu))
	menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	menu_title.add_theme_font_size_override("font_size", 20)
	row.add_child(menu_title)
	for b in [_tool_button("<", func() -> void: open_sim(current - 1 if current != -1 else SIMS.size() - 1)),
			_tool_button(">", func() -> void: open_sim(current + 1)),
			_tool_button("?", show_help)]:
		b.custom_minimum_size.x = 44 * k
		row.add_child(b)
	props_btn.text = "Props"
	props_btn.toggle_mode = true
	props_btn.button_pressed = panel_open
	props_btn.custom_minimum_size = Vector2(0, 36 * k)
	props_btn.toggled.connect(func(on: bool) -> void:
		panel_open = on
		_layout())
	row.add_child(props_btn)


func _style_menu(m: MenuButton) -> void:
	m.flat = false
	m.custom_minimum_size = Vector2(72, MENU_H - 8)
	m.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	m.add_theme_stylebox_override("hover", _flat(C_FACE_HI))
	m.add_theme_stylebox_override("pressed", _flat(C_ACCENT))
	m.add_theme_stylebox_override("hover_pressed", _flat(C_ACCENT))


func _build_tab_bar() -> void:
	add_child(tab_bar)
	tab_bar.add_theme_stylebox_override("panel", _flat(C_FACE_LO, C_EDGE, 0, 0, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	tab_bar.add_child(row)
	var tab := PanelContainer.new()
	var tab_box := _bevel(C_FACE, C_LIGHT, C_FACE, C_EDGE)
	tab_box.content_margin_left = 12
	tab_box.content_margin_right = 4
	tab.add_theme_stylebox_override("panel", tab_box)
	row.add_child(tab)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	tab.add_child(inner)
	tab_swatch.custom_minimum_size = Vector2(12, 12)
	tab_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(tab_swatch)
	tab_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.add_child(tab_title)
	tab_close.text = "x"
	tab_close.custom_minimum_size = Vector2(32, 28)
	tab_close.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	tab_close.add_theme_stylebox_override("hover", _flat(C_FACE_HI))
	tab_close.add_theme_stylebox_override("pressed", _flat(C_ACCENT))
	tab_close.pressed.connect(show_menu)
	inner.add_child(tab_close)


func _build_browser() -> void:
	add_child(browser)
	browser.add_theme_stylebox_override("panel", _flat(C_FACE, C_EDGE, 0, 1, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	browser.add_child(box)
	box.add_child(_panel_header("SIMULATIONS"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	scrollers.append(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)
	browser_rows.resize(SIMS.size())
	for i in SIMS.size():
		var b := _list_row(SIMS[i])
		b.pressed.connect(open_sim.bind(i))
		browser_rows[i] = b
		list.add_child(b)


func _list_row(info: Dictionary) -> Button:
	var b := Button.new()
	b.text = info.title
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 36 * k
	b.icon = _swatch(info.color)
	b.add_theme_constant_override("icon_max_width", 10)
	b.add_theme_constant_override("h_separation", 10)
	var normal := StyleBoxEmpty.new()
	normal.content_margin_left = 14
	b.add_theme_stylebox_override("normal", normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		var s := _flat(C_FACE_HI if state == "hover" else C_ACCENT)
		s.content_margin_left = 14
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	return b


func _panel_header(text: String, label: Label = null) -> Control:
	var head := PanelContainer.new()
	var s := _flat(C_FACE_LO, C_EDGE, 0, 0, 1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	head.add_theme_stylebox_override("panel", s)
	head.custom_minimum_size.y = HEAD_H * k
	var l := label if label else Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", DIM_TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	head.add_child(l)
	return head


func _build_panel() -> void:
	add_child(panel)
	panel.add_theme_stylebox_override("panel", _flat(C_FACE, C_EDGE, 1, 0, 0, 1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var head := _panel_header("PROPERTIES", panel_title)
	box.add_child(head)
	# On a phone held upright the header is the sheet's handle: tap it to pull the sheet taller
	head.gui_input.connect(func(event: InputEvent) -> void:
		if compact and event is InputEventMouseButton and not event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT and size.y > size.x:
			sheet_tall = not sheet_tall
			_layout())
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(panel_scroll)
	scrollers.append(panel_scroll)
	var inner := _margin(10, 8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("margin_right", 16 if not compact else 22) # clear of the scrollbar
	panel_scroll.add_child(inner)
	panel_box.add_theme_constant_override("separation", 8)
	inner.add_child(panel_box)


func _build_home() -> void:
	add_child(home)
	home.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scrollers.append(home)
	var margin := _margin(24 if not compact else 12, 20 if not compact else 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = "The Simulatrix"
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Physics and VFX laboratory. Pick a simulation to open it; every one has its properties on the panel and notes under Help."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", DIM_TEXT)
	box.add_child(sub)
	# one list of every sim, in order (read across when it runs in two columns)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _bevel(C_FACE, C_LIGHT, C_SHADE, C_EDGE))
	box.add_child(frame)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	frame.add_child(inner)
	inner.add_child(_panel_header("SIMULATIONS  (%d)" % SIMS.size()))
	home_grid.add_theme_constant_override("h_separation", 0)
	home_grid.add_theme_constant_override("v_separation", 0)
	inner.add_child(home_grid)
	for i in SIMS.size():
		var row := _list_row(SIMS[i])
		row.toggle_mode = false
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.text = "%s\n%s" % [SIMS[i].title, SIMS[i].blurb]
		row.custom_minimum_size.y = 58 * k
		var line := _flat(Color(0, 0, 0, 0), C_SHADE, 0, 0, 1) # a rule between entries
		line.content_margin_left = 14
		line.content_margin_top = 6
		line.content_margin_bottom = 6
		row.add_theme_stylebox_override("normal", line)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.pressed.connect(open_sim.bind(i))
		home_grid.add_child(row)


func _build_status_bar() -> void:
	add_child(status_bar)
	var s := _flat(C_FACE, C_EDGE, 0, 0, 0, 0)
	s.border_width_top = 1
	s.content_margin_left = 10
	s.content_margin_right = 10
	status_bar.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	status_bar.add_child(row)
	status_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_left.clip_text = true
	status_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_left.add_theme_font_size_override("font_size", 17)
	row.add_child(status_left)
	status_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_right.add_theme_font_size_override("font_size", 17)
	status_right.add_theme_color_override("font_color", DIM_TEXT)
	row.add_child(status_right)


func _build_help() -> void:
	add_child(help_layer)
	help_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			help_layer.hide())
	help_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_layer.add_child(center)
	help_panel.add_theme_stylebox_override("panel", _bevel(C_FACE, C_LIGHT, C_SHADE, C_EDGE))
	center.add_child(help_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	help_panel.add_child(box)
	# title bar
	var bar := PanelContainer.new()
	var bar_style := _flat(C_ACCENT)
	bar_style.content_margin_left = 12
	bar.add_theme_stylebox_override("panel", bar_style)
	box.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	help_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_title.add_theme_color_override("font_color", Color.WHITE)
	bar_row.add_child(help_title)
	var x := Button.new()
	x.text = "x"
	x.custom_minimum_size = Vector2(40, 34)
	x.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	x.add_theme_stylebox_override("hover", _flat(C_ACCENT_HI))
	x.pressed.connect(help_layer.hide)
	bar_row.add_child(x)
	var body := _margin(20, 16)
	box.add_child(body)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	body.add_child(inner)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(help_label)
	var ok := _tool_button("OK", help_layer.hide)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.custom_minimum_size.x = 120
	inner.add_child(ok)
	help_layer.hide()


func _build_controls() -> void:
	for child in panel_box.get_children():
		child.free()
	var parent: VBoxContainer = panel_box
	var flow: HFlowContainer = null # consecutive toggles and buttons share a row
	for spec: Dictionary in sim.controls():
		if spec.type in ["toggle", "button"]:
			if not flow:
				flow = HFlowContainer.new()
				flow.add_theme_constant_override("h_separation", 6)
				flow.add_theme_constant_override("v_separation", 6)
				parent.add_child(flow)
			flow.add_child(_toggle(spec) if spec.type == "toggle" else _tool_button(spec.label, spec.on))
			continue
		flow = null
		match spec.type:
			"section":
				parent = _section(spec.label)
			"slider":
				parent.add_child(_slider_row(spec))
			"choice":
				parent.add_child(_choice_row(spec))
			"custom":
				parent.add_child(spec.node)


## A section: a header that folds away the rows under it.
func _section(text: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	panel_box.add_child(wrap)
	var head := Button.new()
	head.text = "v  " + text.to_upper()
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.custom_minimum_size.y = 30 * k
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", DIM_TEXT)
	var s := _flat(C_FACE_LO, C_EDGE, 0, 0, 1)
	s.content_margin_left = 8
	head.add_theme_stylebox_override("normal", s)
	head.add_theme_stylebox_override("hover", s)
	head.add_theme_stylebox_override("pressed", s)
	wrap.add_child(head)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	wrap.add_child(rows)
	# folds survive the panel being rebuilt (a sim emitting controls_changed)
	rows.visible = not folded.get(text, false)
	head.text = ("v  " if rows.visible else ">  ") + text.to_upper()
	head.pressed.connect(func() -> void:
		rows.visible = not rows.visible
		folded[text] = not rows.visible
		head.text = ("v  " if rows.visible else ">  ") + text.to_upper())
	return rows


## Label on the left, and a bar that fills to the value with the number inside it.
func _slider_row(spec: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = spec.label
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_stretch_ratio = 1.2
	row.add_child(name_label)
	var bar := ValueBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 40 * k
	bar.min_value = spec.min
	bar.max_value = spec.max
	bar.step = spec.step
	bar.value = spec.value
	bar.fill = C_ACCENT
	bar.well = C_INSET
	bar.edge = C_EDGE
	bar.fmt = spec.get("fmt", "%.1f")
	var unit: String = spec.get("unit", "")
	if unit != "":
		bar.fmt += " " + unit.replace("%", "%%")
	bar.value_changed.connect(spec.on)
	row.add_child(bar)
	return row


func _choice_row(spec: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = spec.label
	box.add_child(label)
	# Up to four options share one segmented row; more (a palette) wrap onto several
	var many: bool = spec.options.size() > 4
	var row: Container = HFlowContainer.new() if many else HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	box.add_child(row)
	var group := ButtonGroup.new()
	var on: Callable = spec.on
	var swatches: Array = spec.get("colors", [])
	for i in spec.options.size():
		var b := Button.new()
		b.text = spec.options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == spec.value
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(84 if many else 0, 42 * k)
		b.clip_text = not many
		if i < swatches.size():
			b.icon = _swatch(swatches[i])
			b.add_theme_constant_override("icon_max_width", 10)
		b.pressed.connect(func() -> void: on.call(i))
		row.add_child(b)
	return box


func _toggle(spec: Dictionary) -> Button:
	var b := CheckBox.new()
	b.text = spec.label
	b.button_pressed = spec.value
	b.custom_minimum_size = Vector2(130, 36 * k)
	b.toggled.connect(spec.on)
	return b


# --- navigation --------------------------------------------------------------

func show_menu() -> void:
	_close_sim()
	current = -1
	help_layer.hide()
	menu_title.text = ""
	for b in browser_rows:
		if b:
			b.set_pressed_no_signal(false)
	_say("Ready")
	_layout()


func open_sim(index: int) -> void:
	_close_sim()
	current = wrapi(index, 0, SIMS.size())
	var info: Dictionary = SIMS[current]
	help_layer.hide()
	tab_title.text = info.title
	menu_title.text = info.title
	tab_swatch.color = info.color
	for i in browser_rows.size():
		if browser_rows[i]:
			browser_rows[i].set_pressed_no_signal(i == current)
	_layout()
	folded.clear()
	sim = info.script.new()
	sim.size = area.size
	sim_layer.add_child(sim)
	sim.controls_changed.connect(func() -> void: _build_controls.call_deferred())
	_build_controls()
	_say(sim.hint(), 6.0)


func show_help() -> void:
	if not sim:
		return
	_show_dialog(SIMS[current].title, sim.help())


func _show_dialog(title: String, text: String) -> void:
	help_title.text = title
	help_label.text = text
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


## Shows a message in the status bar for a while.
func _say(text: String, seconds := 0.0) -> void:
	message = text
	message_time = seconds
	status_left.text = text


# --- layout and input --------------------------------------------------------

func _layout() -> void:
	_fit_scale()
	var vs := size
	var in_sim := current != -1
	var landscape := vs.x > vs.y * 1.1
	var menu_h := MENU_H * k
	var status_h := STATUS_H if not compact else 30.0
	menu_bar.position = Vector2.ZERO
	menu_bar.size = Vector2(vs.x, menu_h)
	status_bar.position = Vector2(0, vs.y - status_h)
	status_bar.size = Vector2(vs.x, status_h)
	var top := menu_h
	var bottom := vs.y - status_h
	var left := 0.0
	var right := vs.x

	var show_browser := landscape and browser_open and vs.x >= 980 and not compact
	browser.visible = show_browser
	if show_browser:
		var bw := clampf(vs.x * 0.17, 200.0, 260.0)
		browser.position = Vector2(0, top)
		browser.size = Vector2(bw, bottom - top)
		left = bw

	var show_panel := in_sim and panel_open
	panel.visible = show_panel
	if show_panel:
		if landscape:
			var w := clampf(vs.x * (0.36 if compact else 0.27), 300.0, 440.0 if compact else 400.0)
			panel.position = Vector2(vs.x - w, top)
			panel.size = Vector2(w, bottom - top)
			right -= w
		elif compact:
			# a bottom sheet: tap its header to pull it up taller or let it back down
			var h := (bottom - top) * (0.72 if sheet_tall else 0.44)
			panel.position = Vector2(0, bottom - h)
			panel.size = Vector2(vs.x, h)
			bottom -= h
		else:
			var h := clampf(vs.y * 0.36, 260.0, 520.0)
			panel.position = Vector2(0, bottom - h)
			panel.size = Vector2(vs.x, h)
			bottom -= h
	panel_title.text = "PROPERTIES" + ("  -  " + SIMS[current].title.to_upper() if in_sim and not compact else "")
	if compact and not landscape:
		panel_title.text += "      (tap: %s)" % ("lower" if sheet_tall else "taller")

	props_btn.visible = in_sim
	tab_bar.visible = in_sim and not compact
	if in_sim and not compact:
		tab_bar.position = Vector2(left, top)
		tab_bar.size = Vector2(right - left, TAB_H)
		top += TAB_H
	area = Rect2(left, top, right - left, bottom - top)
	sim_layer.position = area.position
	if sim and not sim.size.is_equal_approx(area.size):
		sim.resize(area.size)

	home.visible = not in_sim
	home.position = area.position
	home.size = area.size
	home_grid.columns = 2 if area.size.x >= 760 else 1

	help_panel.custom_minimum_size.x = minf(vs.x - 40.0, 620.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	# the touches that mouse emulation makes from _cancel_press() land far off screen
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and event.position.x < -1000.0:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_drag_scroll(event)
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if sim and not help_layer.visible and area.has_point(p):
				active[event.index] = true
				sim.touch_down(event.index, p - area.position)
		elif active.has(event.index):
			active.erase(event.index)
			if sim:
				sim.touch_up(event.index, p - area.position)
	elif event is InputEventScreenDrag:
		if sim and active.has(event.index):
			sim.touch_move(event.index, event.position - area.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return # the keys belong to whatever is being typed
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


## A finger (or the mouse) dragged up or down over a panel scrolls it, even when the drag
## starts on a button or a value bar: once it is clearly a scroll, the press is called off so
## nothing under the finger fires. Widgets in the group "keeps_drags" (curve editors...) keep theirs.
func _drag_scroll(event: InputEvent) -> void:
	var p: Vector2 = event.position
	if event is InputEventScreenTouch:
		if event.pressed:
			if drag_index != -1 or help_layer.visible or (sim and area.has_point(p)):
				return
			for n in get_tree().get_nodes_in_group("keeps_drags"):
				if n is Control and n.is_visible_in_tree() and n.get_global_rect().has_point(p):
					return
			for s in scrollers:
				if s.is_visible_in_tree() and s.get_global_rect().has_point(p):
					drag_scroll = s
					drag_index = event.index
					drag_from = p
					drag_scroll_from = s.scroll_vertical
					drag_scrolling = false
					drag_velocity = 0.0
					fling = null
					return
		elif event.index == drag_index:
			if drag_scrolling:
				fling = drag_scroll
				fling_velocity = drag_velocity
			drag_index = -1
			drag_scroll = null
			drag_scrolling = false
	elif event.index == drag_index and drag_scroll:
		var d := p - drag_from
		if not drag_scrolling and absf(d.y) > 12.0 and absf(d.y) > absf(d.x) and not ValueBar.dragging_any:
			drag_scrolling = true
			drag_from = p # no jump: scroll from here
			_cancel_press()
		if drag_scrolling:
			drag_scroll.scroll_vertical = int(drag_scroll_from - (p.y - drag_from.y))
			drag_velocity = -event.velocity.y


## Calls off the press a scroll began on, by letting the mouse button go far off screen.
func _cancel_press() -> void:
	# first slide off whatever was pressed (a button only fires if the pointer is still on it)...
	var m := InputEventMouseMotion.new()
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.position = Vector2(-10000, -10000)
	m.global_position = m.position
	Input.parse_input_event(m)
	# ...then let go there
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = Vector2(-10000, -10000)
	e.global_position = e.position
	Input.parse_input_event(e)


func _process(delta: float) -> void:
	if fling:
		fling.scroll_vertical = int(fling.scroll_vertical + fling_velocity * delta)
		fling_velocity *= pow(0.03, delta)
		if absf(fling_velocity) < 30.0:
			fling = null
	if message_time > 0.0:
		message_time -= delta
	status_tick -= delta
	if status_tick > 0.0:
		return
	status_tick = 0.25
	var line := message
	if sim and message_time <= 0.0:
		line = sim.status()
		if line == "":
			line = SIMS[current].blurb
	status_left.text = line
	var right := "%d fps" % Engine.get_frames_per_second()
	if compact and size.y > size.x:
		right = "" # no room beside the message on an upright phone
	elif sim and size.x > size.y:
		right = "%d x %d   %s" % [int(area.size.x), int(area.size.y), right]
	status_right.text = right


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BACK)
	if current != -1:
		return
	# the home page sits on a dim checkerboard, like an empty canvas
	var cell := 24.0
	var r := area
	var y := 0
	while y * cell < r.size.y:
		var x := y % 2
		while x * cell < r.size.x:
			draw_rect(Rect2(r.position + Vector2(x, y) * cell, Vector2(cell, cell)).intersection(r), Color("222225"))
			x += 2
		y += 1


# --- theme -------------------------------------------------------------------

func _margin(h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	return m


func _tool_button(text: String, on: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(40, 36 * k)
	b.pressed.connect(on)
	return b


## A flat box with optional 1px edges (left, top, right, bottom).
func _flat(bg: Color, edge := Color.BLACK, l := 0, t := 0, b := 0, r := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.border_width_left = l
	s.border_width_top = t
	s.border_width_bottom = b
	s.border_width_right = r
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## A square bevelled box: a dark outline, a light top-left edge and a shaded bottom-right.
func _bevel(face: Color, light: Color, shade: Color, outline: Color) -> StyleBoxTexture:
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 6:
			var c := face
			if x == 0 or y == 0 or x == 5 or y == 5:
				c = outline
			elif x == 1 or y == 1:
				c = light
			elif x == 4 or y == 4:
				c = shade
			img.set_pixel(x, y, c)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = 2
	s.texture_margin_top = 2
	s.texture_margin_right = 2
	s.texture_margin_bottom = 2
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


func _swatch(color: Color) -> ImageTexture:
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(C_EDGE)
	img.fill_rect(Rect2i(1, 1, 8, 8), color)
	return ImageTexture.create_from_image(img)


func _check(on: bool) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(C_EDGE)
	img.fill_rect(Rect2i(1, 1, 18, 18), C_INSET)
	if on:
		img.fill_rect(Rect2i(5, 5, 10, 10), C_ACCENT_HI)
	return ImageTexture.create_from_image(img)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)

	var normal := _bevel(C_FACE_HI, C_LIGHT, C_SHADE, C_EDGE)
	var hover := _bevel(Color("515157"), Color("6a6a72"), C_SHADE, C_EDGE)
	var pressed := _bevel(C_ACCENT, C_ACCENT_HI, Color("355f91"), C_EDGE)
	var disabled := _bevel(C_FACE_LO, C_FACE, C_SHADE, C_EDGE)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(state, "Button", TEXT)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM_TEXT)

	# Check boxes: flat rows with a square tick box
	var row := _flat(Color(0, 0, 0, 0))
	row.content_margin_left = 2
	for state in ["normal", "pressed", "hover", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", row if not state.begins_with("hover") else _flat(C_FACE_HI))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_icon("unchecked", "CheckBox", _check(false))
	t.set_icon("checked", "CheckBox", _check(true))
	t.set_constant("h_separation", "CheckBox", 8)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "CheckBox", TEXT)

	t.set_stylebox("panel", "PanelContainer", _flat(C_FACE))

	# Popup menus
	var pop := _bevel(C_FACE, C_LIGHT, C_SHADE, C_EDGE)
	pop.content_margin_top = 4
	pop.content_margin_bottom = 4
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", _flat(C_ACCENT))
	var sep := _flat(Color(0, 0, 0, 0), C_EDGE, 0, 0, 1)
	t.set_stylebox("labeled_separator_left", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", sep)
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_separator_color", "PopupMenu", DIM_TEXT)
	t.set_constant("v_separation", "PopupMenu", 14)
	t.set_constant("item_start_padding", "PopupMenu", 14)
	t.set_constant("item_end_padding", "PopupMenu", 24)
	t.set_font_size("font_size", "PopupMenu", 20)
	t.set_font_size("font_separator_size", "PopupMenu", 15)
	t.set_icon("checked", "PopupMenu", _check(true))
	t.set_icon("unchecked", "PopupMenu", _check(false))

	# Sliders: an inset well that fills with the accent; a thin handle
	var well := _flat(C_INSET, C_EDGE, 1, 1, 1, 1)
	well.content_margin_top = 16
	well.content_margin_bottom = 16
	var fill := _flat(C_ACCENT, C_EDGE, 1, 1, 1, 0)
	fill.content_margin_top = 16
	fill.content_margin_bottom = 16
	t.set_stylebox("slider", "HSlider", well)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := Image.create(2, 34, false, Image.FORMAT_RGBA8) # no handle: the fill edge is the value
	grab.fill(Color(0, 0, 0, 0))
	t.set_icon("grabber", "HSlider", ImageTexture.create_from_image(grab))
	t.set_icon("grabber_highlight", "HSlider", ImageTexture.create_from_image(grab))

	var bar := _flat(C_FACE_LO)
	bar.content_margin_left = 5
	bar.content_margin_right = 5
	var grabber := _flat(C_FACE_HI, C_EDGE, 1, 1, 1, 1)
	grabber.content_margin_left = 5
	grabber.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", bar)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(Color("5a5a62"), C_EDGE, 1, 1, 1, 1))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(C_ACCENT, C_EDGE, 1, 1, 1, 1))
	return t
