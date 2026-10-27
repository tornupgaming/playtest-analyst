@tool
extends RichTextLabel
## A unified diff in monospace, added lines green and removed lines red, at a size that
## reads in a 1080p screen recording. The ---/+++ header is left out: the file is
## shown above it.

const COLORS := {"+": Color("7ee787"), "-": Color("ff7b72"), "@": Color("79c0ff")}
const CONTEXT := Color("c9d1d9")
const BACKGROUNDS := {"+": Color(0.18, 0.63, 0.26, 0.22), "-": Color(0.97, 0.32, 0.29, 0.22)}


func _init() -> void:
	selection_enabled = true
	context_menu_enabled = true
	var font: Font
	var size := 17
	if Engine.is_editor_hint():
		font = EditorInterface.get_editor_theme().get_font("source", "EditorFonts")
		size = roundi(size * EditorInterface.get_editor_scale())
	else:
		font = SystemFont.new()
		font.font_names = ["JetBrains Mono", "DejaVu Sans Mono", "monospace"]
	add_theme_font_override("mono_font", font)
	add_theme_font_size_override("mono_font_size", size)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("0d1117")
	panel.set_content_margin_all(10)
	add_theme_stylebox_override("normal", panel)


func show_diff(diff: String) -> void:
	clear()
	push_mono()
	for line in diff.strip_edges(false, true).split("\n"):
		if line.begins_with("--- ") or line.begins_with("+++ "):
			continue
		var kind := line.left(1)
		if BACKGROUNDS.has(kind):
			push_bgcolor(BACKGROUNDS[kind])
		push_color(COLORS.get(kind, CONTEXT))
		add_text(line + "\n")
		pop()
		if BACKGROUNDS.has(kind):
			pop()
	pop()
