class_name InventorySlot
extends ColorRect

signal item_drop_requested(source_index: int, target_index: int)
signal item_drag_started(source_index: int)
signal item_drag_finished

var slot_index := -1
var occupied := false
var drag_text := ""
var drag_texture: Texture2D
var is_drag_source := false


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not occupied:
		return null
	is_drag_source = true
	item_drag_started.emit(slot_index)
	var preview := ColorRect.new()
	preview.custom_minimum_size = Vector2(122, 70)
	preview.size = Vector2(122, 70)
	preview.color = Color(0.20, 0.16, 0.10, 0.94)
	if drag_texture != null:
		var icon := TextureRect.new()
		icon.position = Vector2(4, 3)
		icon.size = Vector2(64, 64)
		icon.texture = drag_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(icon)
	var label := Label.new()
	preview.add_child(label)
	label.position = Vector2(64, 0) if drag_texture != null else Vector2.ZERO
	label.size = Vector2(58, 70) if drag_texture != null else Vector2(122, 70)
	label.text = drag_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#f0d69c"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return {"source": slot_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("source") and int(data["source"]) != slot_index


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_drop_requested.emit(int(data["source"]), slot_index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_drag_source:
		is_drag_source = false
		item_drag_finished.emit()
