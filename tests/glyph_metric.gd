extends Node
## Throwaway: measure the REAL rendered extent of Label3D text against the
## `_text_extent` estimate rig_builder uses to size sign plates.

func _ready() -> void:
	var samples := [
		["FIRE HOSE REEL", 12], ["MUSTER STATION B", 12], ["FIREPOINT 4", 12],
		["DB-4", 12], ["EYE PROTECTION\nMUST BE WORN", 11], ["MUSTER STATION B", 30],
		["LIFEBOAT 1", 30], ["WWWWWW", 12], ["iiiiii", 12], ["MMMM", 20],
		["NO SMOKING", 12], ["SALTLINE", 40],
	]
	var f: Font = ThemeDB.fallback_font
	print("fallback font: ", f, "  name=", f.get_font_name() if f else "<null>")
	print("%-30s %5s | %8s %8s | %8s %8s | %6s" % ["text", "fs", "est_w", "real_w", "est_h", "real_h", "w_ratio"])
	for s in samples:
		var text: String = s[0]
		var fs: int = s[1]
		var l := Label3D.new()
		l.text = text
		l.font_size = fs
		l.pixel_size = 0.01
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)
		await get_tree().process_frame
		var ab: AABB = l.get_aabb()
		var est: Vector2 = _text_extent(text, fs)
		print("%-30s %5d | %8.4f %8.4f | %8.4f %8.4f | %6.3f" % [
			text.replace("\n", "\\n"), fs, est.x, ab.size.x, est.y, ab.size.y,
			(ab.size.x / est.x) if est.x > 0.0 else -1.0])
		# glyph advance implied
		var lines: PackedStringArray = text.split("\n")
		var mc: int = 1
		for ln in lines:
			mc = maxi(mc, ln.length())
		print("        implied advance=%.4f em   implied line-height=%.4f em" % [
			ab.size.x / (mc * fs * 0.01), ab.size.y / (lines.size() * fs * 0.01)])
		l.queue_free()
	# What does Font.get_string_size say?
	for s in [["FIRE HOSE REEL", 12], ["MUSTER STATION B", 12]]:
		var sz: Vector2 = f.get_string_size(s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, s[1])
		print("get_string_size(%s,%d) = %s -> %.4f m ; height(%d)=%.2f" % [
			s[0], s[1], str(sz), sz.x * 0.01, s[1], f.get_height(s[1])])
	get_tree().quit()

static func _text_extent(text: String, font_size: int) -> Vector2:
	var lines: PackedStringArray = text.split("\n")
	var max_chars: int = 1
	for ln in lines:
		max_chars = maxi(max_chars, ln.length())
	var fpx: float = float(font_size) * 0.01
	return Vector2(max_chars * fpx * 0.58, lines.size() * fpx * 1.35)
