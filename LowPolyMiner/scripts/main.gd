extends Node3D

const INVENTORY_CONTEXT_THROW := 0
const INVENTORY_ITEM_ICONS := {
	"stone": preload("res://assets/items/stone.png"),
	"coal": preload("res://assets/items/coal.png"),
	"copper": preload("res://assets/items/copper.png")
}
const INVENTORY_PANEL_TEXTURE := preload("res://assets/ui/inventory_panel.png")
const FOG_SETTINGS_PATH := "user://fog_settings.cfg"

var torch_count := 10
var inventory_items: Array[String] = ["hammer", "torch", "tablet", "dynamite", "", "", "", "", "", ""]
var player: MinerPlayer
var day_night_cycle: DayNightCycle
var cloud_layers: CloudLayers
var retro_fog: RetroFog
var atmospheric_mist: AtmosphericMist
var inventory_summary_label: Label
var message_label: Label
var tool_label: Label
var crosshair: Label
var help_label: Label
var inventory_panel: Control
var inventory_cells: Array[InventorySlot] = []
var inventory_slot_icons: Array[TextureRect] = []
var inventory_slot_labels: Array[Label] = []
var inventory_context_menu: PopupMenu
var inventory_context_slot := -1
var inventory_drag_source := -1
var time_label: Label
var cheat_panel: Control
var cheat_phase_label: Label
var fog_slider_rows: Array = []
var admin_mode := false
var admin_mode_button: Button
var admin_status_label: Label
var admin_badge: Label
var admin_block_menu: PopupMenu
var admin_target_grid := Vector3i.ZERO
var admin_has_paint_target := false
var map_dirty := false
var quickbar_slots: Array[ColorRect] = []
var quickbar_item_icons: Array[TextureRect] = []
var quickbar_item_labels: Array[Label] = []
var stone_material: StandardMaterial3D
var coal_material: StandardMaterial3D
var copper_material: StandardMaterial3D
var grass_material: StandardMaterial3D
var wood_material: StandardMaterial3D
var iron_material: StandardMaterial3D
var block_volume: Node3D
var crack_textures: Array = []
var mined_message_time := 0.0


func _ready() -> void:
	_create_materials()
	_create_environment()
	_build_cave()
	_create_player()
	_create_cloud_layers()
	_create_retro_fog()
	_create_atmospheric_mist()
	_create_ui()


func _process(delta: float) -> void:
	if mined_message_time > 0.0:
		mined_message_time -= delta
		message_label.modulate.a = clampf(mined_message_time * 2.5, 0.0, 1.0)
	if player != null and block_volume != null:
		block_volume.sync_around(player.global_position)
	if (
		player != null
		and help_label != null
		and not player.inventory_open
		and not player.cheat_menu_open
		and inventory_items[player.selected_slot] == "dynamite"
	):
		help_label.text = _control_hint(player.selected_slot)


func _create_materials() -> void:
	# Stone and grass span two blocks so painted cobbles/tufts do not stamp
	# on every cube. Ore stays one tile per block so each deposit still reads.
	stone_material = _block_material("res://assets/blocks/stone.png", 0.25)
	coal_material = _block_material("res://assets/blocks/coal.png", 0.5)
	copper_material = _block_material("res://assets/blocks/copper.png", 0.5)
	grass_material = _block_material("res://assets/blocks/grass.png", 0.25)
	wood_material = _material(Color("#8b5a2b"))
	iron_material = _material(Color("#aeb7b6"), 0.15)
	crack_textures = [
		load("res://assets/damage/cracks_77.png"),
		load("res://assets/damage/cracks_33.png"),
		load("res://assets/damage/cracks_01.png")
	]


func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#020304")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#354247")
	environment.ambient_light_energy = DayNightCycle.NIGHT_AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.90
	environment.adjustment_contrast = 1.16
	environment.adjustment_saturation = 0.82
	# RetroFog owns the texture-free depth treatment. Keeping engine fog disabled
	# prevents its smooth exponential pass from doubling the custom coefficient.
	environment.fog_enabled = false
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("#ffe0ad")
	sun.light_energy = 0.32
	sun.shadow_enabled = true
	# The volume is a 160-unit-deep shell. Short default cascades leave the
	# interior unshadowed, so daylight would still fill the whole mountain.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 240.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 2.0
	add_child(sun)

	# Skylight leaking through the opening only. Not a cave lamp: range stops
	# before it becomes general interior illumination.
	var entrance_fill := OmniLight3D.new()
	entrance_fill.name = "EntranceFill"
	entrance_fill.position = Vector3(0, 2.4, 11.0)
	entrance_fill.light_color = DayNightCycle.NIGHT_ENTRANCE_FILL_COLOR
	entrance_fill.light_energy = DayNightCycle.NIGHT_ENTRANCE_FILL_ENERGY
	entrance_fill.light_specular = 0.12
	entrance_fill.omni_range = 18.0
	entrance_fill.omni_attenuation = 1.65
	entrance_fill.shadow_enabled = false
	add_child(entrance_fill)

	day_night_cycle = DayNightCycle.new()
	day_night_cycle.phase_changed.connect(_on_time_phase_changed)
	add_child(day_night_cycle)
	day_night_cycle.setup(environment, sun, entrance_fill)


func _build_cave() -> void:
	# Outdoor pad in front of the sculptable cube. z=8..16 meets the cube face.
	for x in range(-8, 9):
		for z in range(4, 9):
			_add_solid_block(Vector3(x * 2, -1, z * 2), grass_material if z > 5 else stone_material)

	block_volume = load("res://scripts/block_volume.gd").new()
	add_child(block_volume)
	block_volume.block_spawned.connect(_on_volume_block_spawned)
	block_volume.setup(stone_material, coal_material, copper_material, crack_textures)


func _on_volume_block_spawned(block: MineableBlock) -> void:
	block.break_requested.connect(_on_block_break_requested)


func _add_solid_block(pos: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	# Visuals overlap the 2-unit grid very slightly to prevent lighting or
	# floating-point hairlines, while collision shapes meet exactly edge to edge.
	box.size = Vector3.ONE * 2.02
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 2.0
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _create_player() -> void:
	player = MinerPlayer.new()
	player.position = Vector3(0, 0.05, 14)
	player.setup(wood_material, iron_material)
	player.selected_slot_changed.connect(_on_selected_slot_changed)
	player.inventory_toggled.connect(_on_inventory_toggled)
	player.cheat_menu_toggled.connect(_on_cheat_menu_toggled)
	player.torch_placement_requested.connect(_on_torch_placement_requested)
	player.dynamite_throw_requested.connect(_on_dynamite_throw_requested)
	player.dynamite_spent_requested.connect(_on_dynamite_spent)
	player.status_message_requested.connect(_show_message)
	player.dynamite_state_changed.connect(_on_dynamite_state_changed)
	player.admin_break_requested.connect(_on_admin_break_requested)
	player.admin_paint_menu_requested.connect(_on_admin_paint_menu_requested)
	add_child(player)


func _create_cloud_layers() -> void:
	cloud_layers = CloudLayers.new()
	add_child(cloud_layers)
	cloud_layers.setup(block_volume.get_visual_aabb())


func _create_retro_fog() -> void:
	retro_fog = RetroFog.new()
	add_child(retro_fog)
	retro_fog.setup(player.camera, day_night_cycle)
	retro_fog.set_mine_bounds(block_volume.get_visual_aabb())


func _create_atmospheric_mist() -> void:
	atmospheric_mist = AtmosphericMist.new()
	add_child(atmospheric_mist)
	atmospheric_mist.setup(player.camera, day_night_cycle)
	atmospheric_mist.set_mine_bounds(block_volume.get_visual_aabb())
	_load_fog_settings()


func _create_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	var panel := ColorRect.new()
	panel.position = Vector2(22, 20)
	panel.size = Vector2(250, 86)
	panel.color = Color(0.025, 0.035, 0.035, 0.82)
	ui.add_child(panel)

	inventory_summary_label = Label.new()
	inventory_summary_label.position = Vector2(42, 34)
	inventory_summary_label.text = "PACK  2/10"
	inventory_summary_label.add_theme_font_size_override("font_size", 22)
	inventory_summary_label.add_theme_color_override("font_color", Color("#ffd36a"))
	ui.add_child(inventory_summary_label)

	time_label = Label.new()
	time_label.position = Vector2(176, 38)
	time_label.text = "TIME  %s" % day_night_cycle.get_phase_name()
	time_label.add_theme_font_size_override("font_size", 13)
	time_label.add_theme_color_override("font_color", Color("#9ba9aa"))
	ui.add_child(time_label)

	tool_label = Label.new()
	tool_label.position = Vector2(42, 70)
	tool_label.text = "WOODEN PICKAXE"
	tool_label.add_theme_font_size_override("font_size", 15)
	tool_label.add_theme_color_override("font_color", Color("#c9d2cc"))
	ui.add_child(tool_label)

	crosshair = Label.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8, -17)
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	ui.add_child(crosshair)

	help_label = Label.new()
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.position = Vector2(24, -56)
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_color_override("font_color", Color(0.8, 0.86, 0.82, 0.8))
	ui.add_child(help_label)

	admin_badge = Label.new()
	admin_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	admin_badge.position = Vector2(-220, 24)
	admin_badge.size = Vector2(200, 28)
	admin_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	admin_badge.add_theme_font_size_override("font_size", 16)
	admin_badge.add_theme_color_override("font_color", Color("#ffb14a"))
	admin_badge.visible = false
	admin_badge.text = "ADMIN MODE"
	ui.add_child(admin_badge)

	admin_block_menu = PopupMenu.new()
	admin_block_menu.add_item("STONE", 0)
	admin_block_menu.add_item("COAL", 1)
	admin_block_menu.add_item("COPPER", 2)
	admin_block_menu.id_pressed.connect(_on_admin_block_chosen)
	admin_block_menu.popup_hide.connect(_on_admin_block_menu_closed)
	ui.add_child(admin_block_menu)

	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_CENTER)
	message_label.position = Vector2(-90, 46)
	message_label.size = Vector2(180, 30)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", Color("#ffd36a"))
	message_label.modulate.a = 0.0
	ui.add_child(message_label)
	_create_quickbar(ui)
	_create_inventory(ui)
	_create_cheat_menu(ui)
	_update_quickbar(0)


func _create_quickbar(ui: CanvasLayer) -> void:
	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	title.position = Vector2(-146, 128)
	title.text = "FIELD RIG"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#a8b1ad"))
	ui.add_child(title)
	for index in range(4):
		var slot := ColorRect.new()
		slot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		slot.position = Vector2(-150, 154 + index * 68)
		slot.size = Vector2(126, 58)
		ui.add_child(slot)
		quickbar_slots.append(slot)
		var accent := ColorRect.new()
		accent.position = Vector2(0, 0)
		accent.size = Vector2(4, 58)
		accent.color = Color("#d39b4a")
		slot.add_child(accent)
		var key_label := Label.new()
		key_label.position = Vector2(12, 8)
		key_label.text = str(index + 1)
		key_label.add_theme_font_size_override("font_size", 20)
		key_label.add_theme_color_override("font_color", Color("#ffd792"))
		slot.add_child(key_label)
		var item_icon := TextureRect.new()
		item_icon.position = Vector2(32, 5)
		item_icon.size = Vector2(44, 48)
		item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_icon.visible = false
		slot.add_child(item_icon)
		quickbar_item_icons.append(item_icon)
		var item_label := Label.new()
		item_label.position = Vector2(40, 10)
		item_label.size = Vector2(78, 40)
		item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_label.add_theme_font_size_override("font_size", 14)
		item_label.add_theme_color_override("font_color", Color("#dbe0dc"))
		slot.add_child(item_label)
		quickbar_item_labels.append(item_label)


func _create_inventory(ui: CanvasLayer) -> void:
	inventory_panel = Control.new()
	inventory_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory_panel.visible = false
	ui.add_child(inventory_panel)
	var pack := Control.new()
	pack.set_anchors_preset(Control.PRESET_CENTER)
	pack.position = Vector2(-515, -393)
	pack.size = Vector2(1030, 786)
	inventory_panel.add_child(pack)
	var panel_art := TextureRect.new()
	panel_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_art.texture = INVENTORY_PANEL_TEXTURE
	panel_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pack.add_child(panel_art)
	var title := Label.new()
	title.position = Vector2(306, 65)
	title.size = Vector2(330, 54)
	title.text = "FIELD PACK"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#aaa789"))
	pack.add_child(title)
	var close_hint := Label.new()
	close_hint.position = Vector2(645, 65)
	close_hint.size = Vector2(108, 54)
	close_hint.text = "E  CLOSE"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 14)
	close_hint.add_theme_color_override("font_color", Color("#6f776b"))
	pack.add_child(close_hint)
	var item_hint := Label.new()
	item_hint.position = Vector2(316, 662)
	item_hint.size = Vector2(440, 70)
	item_hint.text = "DRAG ITEMS TO MOVE / SWAP    RIGHT CLICK MANAGE"
	item_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_hint.add_theme_font_size_override("font_size", 12)
	item_hint.add_theme_color_override("font_color", Color("#7a7c69"))
	pack.add_child(item_hint)
	for index in range(10):
		var slot := InventorySlot.new()
		var column := index % 5
		var row := index / 5
		slot.slot_index = index
		slot.position = Vector2(58 + column * 180, 220 + row * 182)
		slot.size = Vector2(176, 171)
		slot.color = Color(0, 0, 0, 0)
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.gui_input.connect(_on_inventory_slot_gui_input.bind(index))
		slot.item_drag_started.connect(_on_inventory_drag_started)
		slot.item_drag_finished.connect(_on_inventory_drag_finished)
		slot.item_drop_requested.connect(_on_inventory_item_dropped)
		pack.add_child(slot)
		inventory_cells.append(slot)
		var number := Label.new()
		number.position = Vector2(11, 8)
		number.text = "RIG %d" % (index + 1) if index < 4 else "%02d" % (index + 1)
		number.add_theme_font_size_override("font_size", 12)
		number.add_theme_color_override("font_color", Color("#777865"))
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(number)
		var item_icon := TextureRect.new()
		item_icon.position = Vector2(24, 15)
		item_icon.size = Vector2(128, 112)
		item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_icon.visible = false
		slot.add_child(item_icon)
		number.move_to_front()
		inventory_slot_icons.append(item_icon)
		var item := Label.new()
		item.position = Vector2(12, 54)
		item.size = Vector2(152, 64)
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_theme_font_size_override("font_size", 15)
		item.add_theme_color_override("font_color", Color("#c8c9b6"))
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.text = "EMPTY"
		slot.add_child(item)
		inventory_slot_labels.append(item)
	inventory_context_menu = PopupMenu.new()
	inventory_context_menu.add_item("THROW ITEM AWAY", INVENTORY_CONTEXT_THROW)
	inventory_context_menu.id_pressed.connect(_on_inventory_context_menu_selected)
	inventory_panel.add_child(inventory_context_menu)
	_update_inventory_labels()


func _create_cheat_menu(ui: CanvasLayer) -> void:
	cheat_panel = ColorRect.new()
	cheat_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	cheat_panel.color = Color(0.005, 0.008, 0.009, 0.82)
	cheat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	cheat_panel.visible = false
	ui.add_child(cheat_panel)
	var card := ColorRect.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = Vector2(-330, -320)
	card.size = Vector2(660, 640)
	card.color = Color("#12191b")
	cheat_panel.add_child(card)
	var title := Label.new()
	title.position = Vector2(24, 16)
	title.text = "TIME TEST  /  ADMIN"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#e5c98f"))
	card.add_child(title)
	var tabs := TabContainer.new()
	tabs.position = Vector2(20, 52)
	tabs.size = Vector2(620, 568)
	card.add_child(tabs)

	var time_page := Control.new()
	time_page.name = "TimeAdmin"
	time_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(time_page)
	tabs.set_tab_title(0, "TIME / ADMIN")
	var explanation := Label.new()
	explanation.position = Vector2(14, 10)
	explanation.text = "7 MINUTE CYCLE    DAY 3/7    DUSK 1/7    NIGHT 2/7    TWILIGHT 1/7"
	explanation.add_theme_font_size_override("font_size", 13)
	explanation.add_theme_color_override("font_color", Color("#899693"))
	time_page.add_child(explanation)
	cheat_phase_label = Label.new()
	cheat_phase_label.position = Vector2(14, 36)
	cheat_phase_label.text = "CURRENT  %s" % day_night_cycle.get_phase_name()
	cheat_phase_label.add_theme_font_size_override("font_size", 18)
	cheat_phase_label.add_theme_color_override("font_color", Color("#d9e0dc"))
	time_page.add_child(cheat_phase_label)
	var phase_names := ["DAY  /  MAXIMUM", "DUSK  /  MIDPOINT", "NIGHT", "TWILIGHT  /  MIDPOINT"]
	for index in range(4):
		var button := Button.new()
		button.position = Vector2(14 + (index % 2) * 290, 76 + (index / 2) * 58)
		button.size = Vector2(276, 50)
		button.text = phase_names[index]
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_set_time_phase.bind(index))
		time_page.add_child(button)
	admin_status_label = Label.new()
	admin_status_label.position = Vector2(14, 202)
	admin_status_label.add_theme_font_size_override("font_size", 16)
	admin_status_label.add_theme_color_override("font_color", Color("#d9e0dc"))
	time_page.add_child(admin_status_label)
	admin_mode_button = Button.new()
	admin_mode_button.position = Vector2(14, 236)
	admin_mode_button.size = Vector2(276, 46)
	admin_mode_button.add_theme_font_size_override("font_size", 15)
	admin_mode_button.pressed.connect(_toggle_admin_mode)
	time_page.add_child(admin_mode_button)
	var save_button := Button.new()
	save_button.position = Vector2(304, 236)
	save_button.size = Vector2(276, 46)
	save_button.text = "SAVE MAP"
	save_button.add_theme_font_size_override("font_size", 15)
	save_button.pressed.connect(_save_sculpted_volume)
	time_page.add_child(save_button)
	var reset_button := Button.new()
	reset_button.position = Vector2(14, 292)
	reset_button.size = Vector2(566, 46)
	reset_button.text = "RESET  STONE CUBE"
	reset_button.add_theme_font_size_override("font_size", 15)
	reset_button.pressed.connect(_reset_sculpted_volume)
	time_page.add_child(reset_button)
	var close_hint := Label.new()
	close_hint.position = Vector2(14, 352)
	close_hint.text = "ADMIN  LEFT CLICK DELETE    RIGHT CLICK SET BLOCK    Y OR ESC  CLOSE"
	close_hint.add_theme_font_size_override("font_size", 13)
	close_hint.add_theme_color_override("font_color", Color("#899693"))
	time_page.add_child(close_hint)

	var fog_page := Control.new()
	fog_page.name = "Fog"
	fog_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fog_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(fog_page)
	tabs.set_tab_title(1, "FOG")
	var fog_scroll := ScrollContainer.new()
	fog_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_scroll.offset_left = 8
	fog_scroll.offset_top = 8
	fog_scroll.offset_right = -8
	fog_scroll.offset_bottom = -58
	fog_page.add_child(fog_scroll)
	var fog_list := VBoxContainer.new()
	fog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fog_list.add_theme_constant_override("separation", 8)
	fog_scroll.add_child(fog_list)
	var fog_note := Label.new()
	fog_note.text = "SLIDERS APPLY LIVE    SAVE KEEPS THEM AS STANDARD    USE TIME TAB TO COMPARE PHASES"
	fog_note.add_theme_font_size_override("font_size", 12)
	fog_note.add_theme_color_override("font_color", Color("#899693"))
	fog_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fog_list.add_child(fog_note)
	_add_fog_slider(fog_list, "MIST OPACITY", "opacity", 0.0, 1.0, 0.01, true)
	_add_fog_slider(fog_list, "MIST AMBIENT", "ambient", 0.0, 0.40, 0.01, true)
	_add_fog_slider(fog_list, "MIST DENSITY", "density", 0.0, 2.0, 0.01, true)
	_add_fog_slider(fog_list, "MIST CONTRAST", "contrast", 0.0, 1.0, 0.01, true)
	_add_fog_slider(fog_list, "MIST SCALE", "scale", 4.0, 28.0, 0.1, true)
	_add_fog_slider(fog_list, "MIST SPEED", "speed", 0.0, 0.80, 0.01, true)
	_add_fog_slider(fog_list, "MIST NEAR", "near_amount", 0.0, 1.0, 0.01, true)
	_add_fog_slider(fog_list, "MIST FAR", "far_amount", 0.0, 1.5, 0.01, true)
	_add_fog_slider(fog_list, "DAY MIST MULT", "day_mul", 0.0, 2.0, 0.01, true)
	_add_fog_slider(fog_list, "NIGHT MIST MULT", "night_mul", 0.0, 2.0, 0.01, true)
	_add_fog_slider(fog_list, "SPECKLE DENSITY", "speckle_density", 0.0, 1.0, 0.01, true)
	_add_fog_slider(fog_list, "SPECKLE BRIGHT", "speckle_brightness", 0.0, 1.5, 0.01, true)
	_add_fog_slider(fog_list, "RETRO DAY INTENSITY", "day_intensity", 0.0, 1.0, 0.01, false)
	_add_fog_slider(fog_list, "RETRO NIGHT INTENSITY", "night_intensity", 0.0, 1.0, 0.01, false)
	_add_fog_slider(fog_list, "RETRO DUSK/TWILIGHT", "transition_intensity", 0.0, 1.0, 0.01, false)
	var fog_buttons := HBoxContainer.new()
	fog_buttons.add_theme_constant_override("separation", 12)
	fog_page.add_child(fog_buttons)
	fog_buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fog_buttons.offset_left = 14
	fog_buttons.offset_right = -14
	fog_buttons.offset_top = -50
	fog_buttons.offset_bottom = -10
	var save_fog := Button.new()
	save_fog.text = "SAVE FOG"
	save_fog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_fog.custom_minimum_size = Vector2(0, 40)
	save_fog.pressed.connect(_save_fog_settings)
	fog_buttons.add_child(save_fog)
	var reset_fog := Button.new()
	reset_fog.text = "RESET FOG"
	reset_fog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_fog.custom_minimum_size = Vector2(0, 40)
	reset_fog.pressed.connect(_reset_fog_settings)
	fog_buttons.add_child(reset_fog)
	_refresh_admin_labels()


func _on_block_break_requested(block: MineableBlock) -> void:
	var empty_slot := inventory_items.find("")
	if empty_slot < 0:
		block.reject_break()
		_show_message("FIELD PACK FULL")
		return
	inventory_items[empty_slot] = block.block_type
	var grid := block.grid_pos
	block.complete_break()
	if block_volume != null:
		block_volume.remove_voxel(grid)
		map_dirty = block_volume.dirty
	_update_inventory_labels()
	_refresh_admin_labels()
	_show_message("+1 %s" % block.block_type.to_upper())


func _on_admin_break_requested(block: MineableBlock) -> void:
	if not admin_mode or block_volume == null:
		return
	var grid := block.grid_pos
	block.complete_break()
	block_volume.remove_voxel(grid)
	map_dirty = block_volume.dirty
	_refresh_admin_labels()
	_show_message("REMOVED")


func _on_admin_paint_menu_requested(block: MineableBlock) -> void:
	if not admin_mode or not is_instance_valid(block):
		return
	admin_target_grid = block.grid_pos
	admin_has_paint_target = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var mouse := Vector2i(get_viewport().get_mouse_position())
	admin_block_menu.position = mouse
	admin_block_menu.popup()


func _on_admin_block_chosen(id: int) -> void:
	if not admin_has_paint_target or block_volume == null:
		return
	var type_names: Array[String] = ["stone", "coal", "copper"]
	if id < 0 or id >= type_names.size():
		return
	var type_name := type_names[id]
	var painted: String = block_volume.set_voxel_type(admin_target_grid, type_name)
	admin_has_paint_target = false
	if painted != "":
		map_dirty = block_volume.dirty
		_refresh_admin_labels()
		_show_message("SET  %s" % painted.to_upper())
	else:
		_show_message("COULD NOT SET BLOCK")


func _on_admin_block_menu_closed() -> void:
	if player != null and not player.inventory_open and not player.cheat_menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_admin_mode() -> void:
	admin_mode = not admin_mode
	if player != null:
		player.admin_mode = admin_mode
	if admin_badge != null:
		admin_badge.visible = admin_mode
	_refresh_admin_labels()
	if not player.cheat_menu_open:
		help_label.text = _control_hint(player.selected_slot)
	_show_message("ADMIN MODE" if admin_mode else "PLAYER MODE")


func _save_sculpted_volume() -> void:
	if block_volume == null:
		return
	if block_volume.save_to_disk():
		map_dirty = false
		_refresh_admin_labels()
		_show_message("MAP SAVED")
	else:
		_show_message("SAVE FAILED")


func _reset_sculpted_volume() -> void:
	if block_volume == null:
		return
	block_volume.reset_to_solid_stone()
	map_dirty = block_volume.dirty
	_refresh_admin_labels()
	_show_message("STONE CUBE RESET")


func _add_fog_slider(
	parent: VBoxContainer,
	title: String,
	key: String,
	min_value: float,
	max_value: float,
	step: float,
	is_mist: bool
) -> void:
	var start := _fog_tune_value(key, is_mist)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = "%s   %.2f" % [title, start]
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#d9e0dc"))
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = start
	slider.custom_minimum_size = Vector2(540, 18)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(
		func(value: float) -> void:
			label.text = "%s   %.2f" % [title, value]
			if is_mist:
				if atmospheric_mist != null:
					atmospheric_mist.set_tune_value(key, value)
			elif retro_fog != null:
				retro_fog.set_tune_value(key, value)
	)
	row.add_child(slider)
	parent.add_child(row)
	fog_slider_rows.append({
		"slider": slider,
		"label": label,
		"title": title,
		"key": key,
		"mist": is_mist
	})


func _fog_tune_value(key: String, is_mist: bool) -> float:
	if is_mist:
		if atmospheric_mist == null:
			return 0.0
		return atmospheric_mist.get_tune_value(key)
	if retro_fog == null:
		return 0.0
	return retro_fog.get_tune_value(key)


func _sync_fog_sliders() -> void:
	for row: Dictionary in fog_slider_rows:
		var is_mist: bool = row["mist"]
		var key: String = row["key"]
		var value := _fog_tune_value(key, is_mist)
		var slider: HSlider = row["slider"]
		var label: Label = row["label"]
		var title: String = row["title"]
		slider.set_value_no_signal(value)
		label.text = "%s   %.2f" % [title, value]


func _load_fog_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FOG_SETTINGS_PATH) != OK:
		return
	if retro_fog != null:
		retro_fog.load_config(cfg)
	if atmospheric_mist != null:
		atmospheric_mist.load_config(cfg)


func _save_fog_settings() -> void:
	var cfg := ConfigFile.new()
	if retro_fog != null:
		retro_fog.store_config(cfg)
	if atmospheric_mist != null:
		atmospheric_mist.store_config(cfg)
	if cfg.save(FOG_SETTINGS_PATH) == OK:
		_show_message("FOG SAVED")
	else:
		_show_message("FOG SAVE FAILED")


func _reset_fog_settings() -> void:
	if retro_fog != null:
		retro_fog.reset_tune()
	if atmospheric_mist != null:
		atmospheric_mist.reset_tune()
	_sync_fog_sliders()
	_show_message("FOG RESET")


func _refresh_admin_labels() -> void:
	if admin_mode_button != null:
		admin_mode_button.text = "ADMIN  ON" if admin_mode else "ENTER  ADMIN"
	if admin_status_label != null:
		var mode := "ADMIN MODE" if admin_mode else "PLAYER MODE"
		var save_state := "UNSAVED" if map_dirty else "SAVED"
		admin_status_label.text = "%s    MAP  %s" % [mode, save_state]
	if admin_badge != null:
		admin_badge.visible = admin_mode
		if map_dirty:
			admin_badge.text = "ADMIN  ·  UNSAVED"
		else:
			admin_badge.text = "ADMIN MODE"


func _on_selected_slot_changed(slot: int) -> void:
	_update_quickbar(slot)


func _on_inventory_toggled(is_open: bool) -> void:
	inventory_panel.visible = is_open
	if not is_open:
		inventory_context_menu.hide()
		inventory_context_slot = -1
		inventory_drag_source = -1
		_update_inventory_cell_styles()
	crosshair.visible = not is_open
	if is_open and admin_block_menu != null:
		admin_block_menu.hide()
	help_label.text = "E  CLOSE FIELD PACK" if is_open else _control_hint(player.selected_slot)


func _on_inventory_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		inventory_drag_source = -1
		_update_inventory_cell_styles()
		if inventory_items[slot_index].is_empty():
			inventory_context_menu.hide()
			inventory_context_slot = -1
			return
		inventory_context_slot = slot_index
		inventory_context_menu.position = Vector2i(get_viewport().get_mouse_position())
		inventory_context_menu.popup()

func _on_inventory_drag_started(source_index: int) -> void:
	inventory_context_menu.hide()
	inventory_context_slot = -1
	inventory_drag_source = source_index
	_update_inventory_cell_styles()


func _on_inventory_drag_finished() -> void:
	inventory_drag_source = -1
	_update_inventory_cell_styles()


func _on_inventory_item_dropped(source_index: int, target_index: int) -> void:
	if source_index < 0 or source_index >= inventory_items.size():
		return
	if target_index < 0 or target_index >= inventory_items.size() or source_index == target_index:
		return
	var moved_item := inventory_items[source_index]
	inventory_items[source_index] = inventory_items[target_index]
	inventory_items[target_index] = moved_item
	inventory_drag_source = -1
	_update_inventory_labels()


func _on_inventory_context_menu_selected(id: int) -> void:
	if id != INVENTORY_CONTEXT_THROW or inventory_context_slot < 0:
		return
	var item_id := inventory_items[inventory_context_slot]
	if item_id.is_empty():
		return
	inventory_items[inventory_context_slot] = ""
	if item_id == "torch":
		torch_count = 0
		_update_torch_labels()
	else:
		if item_id == "dynamite" and player != null:
			player.clear_dynamite_state()
		_update_inventory_labels()
	inventory_context_slot = -1


func _on_cheat_menu_toggled(is_open: bool) -> void:
	cheat_panel.visible = is_open
	if is_open:
		_sync_fog_sliders()
	crosshair.visible = not is_open
	if is_open and admin_block_menu != null:
		admin_block_menu.hide()
	help_label.text = "TIME PRESETS AND ADMIN    Y  CLOSE" if is_open else _control_hint(player.selected_slot)


func _set_time_phase(phase: int) -> void:
	day_night_cycle.set_phase(phase)


func _on_time_phase_changed(_phase: int, phase_name: String) -> void:
	if time_label != null:
		time_label.text = "TIME  %s" % phase_name
	if cheat_phase_label != null:
		cheat_phase_label.text = "CURRENT  %s" % phase_name


func _on_dynamite_throw_requested(origin: Vector3, velocity: Vector3, fuse_left: float) -> void:
	if inventory_items.find("dynamite") < 0:
		return
	var stick = load("res://scripts/thrown_dynamite.gd").new()
	add_child(stick)
	stick.setup(origin, velocity, fuse_left, block_volume)
	_free_inventory_item("dynamite")
	_update_inventory_labels()
	_show_message("DYNAMITE THROWN")


func _on_dynamite_spent() -> void:
	if inventory_items.find("dynamite") < 0:
		return
	_free_inventory_item("dynamite")
	_update_inventory_labels()


func _on_dynamite_state_changed() -> void:
	if player == null or help_label == null:
		return
	if player.inventory_open or player.cheat_menu_open:
		return
	if inventory_items[player.selected_slot] == "dynamite":
		help_label.text = _control_hint(player.selected_slot)
		tool_label.text = _equipped_item_name("dynamite")


func _on_torch_placement_requested(surface_position: Vector3, surface_normal: Vector3) -> void:
	if torch_count <= 0:
		_show_message("NO TORCHES")
		return
	var torch := PlacedTorch.new()
	add_child(torch)
	torch.setup(surface_position, surface_normal, wood_material)
	torch_count -= 1
	if torch_count == 0:
		_free_inventory_item("torch")
	_update_torch_labels()
	_show_message("TORCH PLACED")


func _update_quickbar(selected: int) -> void:
	for index in range(4):
		quickbar_slots[index].color = Color("#3a3328") if index == selected else Color("#101617")
		var item_id := inventory_items[index]
		var has_icon := _set_item_icon(quickbar_item_icons[index], item_id)
		var item_label := quickbar_item_labels[index]
		item_label.position = Vector2(76, 9) if has_icon else Vector2(40, 10)
		item_label.size = Vector2(48, 40) if has_icon else Vector2(78, 40)
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if has_icon else HORIZONTAL_ALIGNMENT_LEFT
		item_label.add_theme_font_size_override("font_size", 11 if has_icon else 14)
		item_label.text = _inventory_item_name(item_id, true)
	var selected_item := inventory_items[selected]
	tool_label.text = _equipped_item_name(selected_item)
	if not player.inventory_open and not player.cheat_menu_open:
		help_label.text = _control_hint(selected)
	player.set_selected_item(selected_item)


func _update_torch_labels() -> void:
	_update_inventory_labels()


func _update_inventory_labels() -> void:
	for index in range(inventory_slot_labels.size()):
		var item_id := inventory_items[index]
		var has_icon := _set_item_icon(inventory_slot_icons[index], item_id)
		var item_label := inventory_slot_labels[index]
		item_label.position = Vector2(12, 124) if has_icon else Vector2(12, 54)
		item_label.size = Vector2(152, 32) if has_icon else Vector2(152, 64)
		item_label.add_theme_font_size_override("font_size", 13 if has_icon else 16)
		item_label.text = _inventory_item_name(item_id, false)
		inventory_cells[index].occupied = not item_id.is_empty()
		inventory_cells[index].drag_text = item_label.text
		inventory_cells[index].drag_texture = inventory_slot_icons[index].texture if has_icon else null
	if inventory_summary_label != null:
		var occupied_slots := inventory_items.size() - inventory_items.count("")
		inventory_summary_label.text = "PACK  %d/10" % occupied_slots
	if not quickbar_item_labels.is_empty():
		_update_quickbar(player.selected_slot)
	_update_inventory_cell_styles()


func _update_inventory_cell_styles() -> void:
	for index in range(inventory_cells.size()):
		if index == inventory_drag_source:
			inventory_cells[index].color = Color(0.42, 0.31, 0.18, 0.48)
		else:
			inventory_cells[index].color = Color(0, 0, 0, 0)


func _free_inventory_item(item_id: String) -> void:
	var slot := inventory_items.find(item_id)
	if slot >= 0:
		inventory_items[slot] = ""


func _set_item_icon(icon: TextureRect, item_id: String) -> bool:
	var item_texture := INVENTORY_ITEM_ICONS.get(item_id) as Texture2D
	icon.texture = item_texture
	icon.visible = item_texture != null
	return icon.visible


func _inventory_item_name(item_id: String, compact: bool) -> String:
	match item_id:
		"hammer":
			return "HAMMER" if compact else "FIELD\nHAMMER"
		"tablet":
			return "TABLET" if compact else "FIELD\nTABLET"
		"dynamite":
			return "DYNAMITE" if compact else "DYNAMITE"
		"torch":
			return "TORCH  x%d" % torch_count if compact else "TORCH\nx%d" % torch_count
		"stone", "coal", "copper":
			return item_id.to_upper() if compact else "%s\nx1" % item_id.to_upper()
		_:
			return "EMPTY" if compact else "EMPTY"


func _equipped_item_name(item_id: String) -> String:
	match item_id:
		"hammer":
			return "FIELD HAMMER"
		"tablet":
			return "FIELD TABLET"
		"dynamite":
			if player != null and player.dynamite_lit:
				return "DYNAMITE  LIT"
			return "DYNAMITE"
		"torch":
			return "TORCH"
		"stone", "coal", "copper":
			return item_id.to_upper()
		_:
			return "EMPTY SLOT"


func _control_hint(selected: int) -> String:
	if admin_mode:
		return "ADMIN    LEFT CLICK  DELETE    RIGHT CLICK  SET BLOCK    Y  MENU"
	var action := "LEFT CLICK  REMOVE TORCH"
	match inventory_items[selected]:
		"hammer":
			action = "LEFT CLICK  MINE"
		"tablet":
			action = "LEFT CLICK  REMOVE TORCH"
		"dynamite":
			action = player.get_dynamite_action_hint()
		"torch":
			action = "RIGHT CLICK  PLACE TORCH    LEFT CLICK  REMOVE TORCH"
	return "WASD  MOVE    SPACE  TAP JUMP / HOLD CLIMB    1–4  FIELD RIG    E  PACK    Y  MENU    %s" % action


func _show_message(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	mined_message_time = 0.8


func _material(color: Color, metallic: float = 0.0, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture
	material.roughness = 0.9
	material.metallic = metallic
	if texture != null:
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _block_material(path: String, tile_scale: float = 0.5) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("Missing block texture: %s" % path)
	material.albedo_color = Color.WHITE
	material.albedo_texture = texture
	material.roughness = 0.92
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# World-space triplanar so adjacent cubes continue the same surface
	# instead of reprinting the full image on every face.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3(tile_scale, tile_scale, tile_scale)
	return material
