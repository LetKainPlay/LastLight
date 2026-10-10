extends SceneTree
## Headless project checks for Last Light.
## Run: godot --headless --path . --script res://tests/run_checks.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

const EXPECTED_VIEWPORT: Vector2i = Vector2i(640, 360)
const EXPECTED_WINDOW: Vector2i = Vector2i(1280, 720)
const PALETTE_PATH: String = "res://art/palette/lastlight.hex"
const MAX_PALETTE_COLORS: int = 32
const MAX_AUTOLOADS: int = 4
const SCAN_ROOTS: Array[String] = ["res://scenes", "res://scripts", "res://tests", "res://scenes"]
const SKIP_DIRS: Array[String] = ["res://addons", "res://.godot", "res://docs"]
const LINT_IGNORE_TAG: String = "# lint-ignore"
const FORBIDDEN_CLASS_SUFFIXES: Array[String] = ["Manager", "Handler", "Provider", "Factory"]

var _failures: int = 0
var _passes: int = 0
var _warnings: int = 0


func _init() -> void:
	print("== Last Light checks (Godot %s) ==" % Engine.get_version_info()["string"])
	_check_display_settings()
	_check_scene_loads()
	_check_typing_lint()
	_check_naming()
	_check_autoloads()
	_check_palette()
	print("== %d passed, %d failed, %d warnings ==" % [_passes, _failures, _warnings])
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------- reporting

func _pass(check: String) -> void:
	_passes += 1
	print("PASS %s" % check)


func _fail(check: String, reason: String) -> void:
	_failures += 1
	printerr("FAIL %s: %s" % [check, reason])


func _warn(check: String, reason: String) -> void:
	_warnings += 1
	print("WARN %s: %s" % [check, reason])


# ---------------------------------------------------------------- file helpers

func _collect_files(root: String, extension: String, out: Array[String]) -> void:
	if root in SKIP_DIRS:
		return
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path: String = root.path_join(entry)
			if dir.current_is_dir():
				_collect_files(path, extension, out)
			elif path.get_extension() == extension and path not in out:
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _files_under(roots: Array[String], extension: String) -> Array[String]:
	var out: Array[String] = []
	for root: String in roots:
		_collect_files(root, extension, out)
	out.sort()
	return out


# ---------------------------------------------------------------- 1. display

func _check_display_settings() -> void:
	var name: String = "display"
	var problems: Array[String] = []

	var vp: Vector2i = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)))
	if vp != EXPECTED_VIEWPORT:
		problems.append("viewport is %s, expected %s" % [vp, EXPECTED_VIEWPORT])

	var win: Vector2i = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
		int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)))
	if win != EXPECTED_WINDOW:
		problems.append("window override is %s, expected %s" % [win, EXPECTED_WINDOW])
	elif win.x % vp.x != 0 or win.y % vp.y != 0:
		problems.append("window override %s is not an integer multiple of viewport" % win)

	var mode: String = str(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	if mode != "canvas_items":
		problems.append("stretch mode is '%s', expected 'canvas_items'" % mode)

	var aspect: String = str(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	if aspect != "keep":
		problems.append("stretch aspect is '%s', expected 'keep'" % aspect)

	var scale_mode: String = str(ProjectSettings.get_setting("display/window/stretch/scale_mode", ""))
	if scale_mode != "integer":
		problems.append("stretch scale_mode is '%s', expected 'integer'" % scale_mode)

	var filter: int = int(ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", -1))
	if filter != 0:
		problems.append("default_texture_filter is %d, expected 0 (Nearest)" % filter)

	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	if renderer != "gl_compatibility":
		problems.append("renderer is '%s', expected 'gl_compatibility'" % renderer)

	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene == "" or not ResourceLoader.exists(main_scene):
		problems.append("main scene '%s' missing" % main_scene)

	# Recommended, warn only (the editor may not have written them yet).
	if not bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)):
		_warn(name, "rendering/2d/snap/snap_2d_transforms_to_pixel is off")
	if int(ProjectSettings.get_setting("debug/gdscript/warnings/untyped_declaration", 0)) < 2:
		_warn(name, "debug/gdscript/warnings/untyped_declaration is not set to Error (2)")

	if problems.is_empty():
		_pass(name)
	else:
		for p: String in problems:
			_fail(name, p)


# ---------------------------------------------------------------- 2. scene load

func _check_scene_loads() -> void:
	var scenes: Array[String] = _files_under(["res://scenes"], "tscn")
	if scenes.is_empty():
		_fail("scene_load", "no .tscn files found under res://scenes")
		return
	var bad: int = 0
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail("scene_load", "%s did not load as PackedScene" % path)
			bad += 1
			continue
		if not packed.can_instantiate():
			_fail("scene_load", "%s cannot instantiate" % path)
			bad += 1
			continue
		var node: Node = packed.instantiate()
		if node == null:
			_fail("scene_load", "%s instantiate() returned null" % path)
			bad += 1
			continue
		node.free()
	if bad == 0:
		_pass("scene_load (%d scenes)" % scenes.size())


# ---------------------------------------------------------------- 3. typing lint

# var x = 1          -> untyped
# var x := 1         -> ok
# var x: int = 1     -> ok
# var x: int         -> ok
var _re_var: RegEx = null
var _re_func: RegEx = null
var _re_for: RegEx = null


func _compile_regexes() -> void:
	_re_var = RegEx.new()
	_re_var.compile("^\\s*(?:@\\w+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?var\\s+(\\w+)\\s*(=|$)")
	_re_func = RegEx.new()
	_re_func.compile("^\\s*(?:static\\s+)?func\\s+(\\w+)\\s*\\((.*)\\)\\s*(->\\s*[\\w\\.\\[\\], ]+)?\\s*:")
	_re_for = RegEx.new()
	_re_for.compile("^\\s*for\\s+(\\w+)\\s+in\\s")


func _check_typing_lint() -> void:
	_compile_regexes()
	var scripts: Array[String] = _files_under(["res://scenes", "res://scripts", "res://tests"], "gd")
	var issues: int = 0
	for path: String in scripts:
		var text: String = FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = text.split("\n")
		for i: int in lines.size():
			var line: String = lines[i]
			if line.contains(LINT_IGNORE_TAG):
				continue
			var code: String = _strip_comment(line)
			if code.strip_edges() == "":
				continue
			var problem: String = _lint_line(code)
			if problem != "":
				issues += 1
				_fail("typing", "%s:%d %s | %s" % [path, i + 1, problem, line.strip_edges()])
	if issues == 0:
		_pass("typing (%d scripts)" % scripts.size())


func _strip_comment(line: String) -> String:
	# Good enough: ignores '#' inside quotes by walking the string.
	var in_quote: String = ""
	for i: int in line.length():
		var c: String = line[i]
		if in_quote != "":
			if c == in_quote and (i == 0 or line[i - 1] != "\\"):
				in_quote = ""
		elif c == "\"" or c == "'":
			in_quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _lint_line(code: String) -> String:
	var m: RegExMatch = _re_var.search(code)
	if m != null:
		# 'var x = ...' or bare 'var x'  -> no ':' type
		return "untyped var '%s' (use 'var %s: Type' or ':=' with obvious type)" % [m.get_string(1), m.get_string(1)]

	m = _re_func.search(code)
	if m != null:
		var fname: String = m.get_string(1)
		if m.get_string(3) == "":
			return "func '%s' missing '-> ReturnType'" % fname
		var params: String = m.get_string(2).strip_edges()
		if params != "":
			for p: String in _split_params(params):
				var pn: String = p.strip_edges()
				if pn == "" or pn.begins_with("..."):
					continue
				if not pn.contains(":"):
					return "func '%s' parameter '%s' has no type" % [fname, pn]
	return ""


func _split_params(params: String) -> PackedStringArray:
	# Split on commas that are not inside (), [], {}.
	var out: PackedStringArray = PackedStringArray()
	var depth: int = 0
	var current: String = ""
	for ch: String in params:
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(current)
			current = ""
		else:
			current += ch
	if current != "":
		out.append(current)
	return out


# ---------------------------------------------------------------- 4. naming

func _check_naming() -> void:
	var problems: int = 0
	var all_files: Array[String] = []
	for ext: String in ["gd", "tscn", "tres", "gdshader", "png", "ogg", "wav"]:
		all_files.append_array(_files_under(["res://scenes", "res://scripts", "res://resources", "res://art", "res://audio", "res://shaders", "res://tests"], ext))
	for path: String in all_files:
		var base: String = path.get_file().get_basename()
		if base != base.to_snake_case() and not base.begins_with("_"):
			_fail("naming", "%s is not snake_case" % path)
			problems += 1

	for path: String in _files_under(["res://scenes", "res://scripts"], "gd"):
		var text: String = FileAccess.get_file_as_string(path)
		for line: String in text.split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("class_name "):
				var cname: String = t.trim_prefix("class_name ").split(" ")[0]
				for suffix: String in FORBIDDEN_CLASS_SUFFIXES:
					if cname.ends_with(suffix):
						_fail("naming", "%s: class_name '%s' ends with '%s' (see CLAUDE.md section 7)" % [path, cname, suffix])
						problems += 1
	if problems == 0:
		_pass("naming")


# ---------------------------------------------------------------- 5. autoloads

func _check_autoloads() -> void:
	var count: int = 0
	for prop: Dictionary in ProjectSettings.get_property_list():
		var pname: String = str(prop["name"])
		if pname.begins_with("autoload/"):
			count += 1
	if count > MAX_AUTOLOADS:
		_fail("autoloads", "%d autoloads, max is %d" % [count, MAX_AUTOLOADS])
	else:
		_pass("autoloads (%d)" % count)


# ---------------------------------------------------------------- 6. palette

func _load_palette() -> Dictionary:
	# Returns { Color8-packed int : true }
	var palette: Dictionary = {}
	if not FileAccess.file_exists(PALETTE_PATH):
		return palette
	var text: String = FileAccess.get_file_as_string(PALETTE_PATH)
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#") and line.length() != 7:
			continue
		if not line.begins_with("#"):
			line = "#" + line
		if line.length() != 7 or not line.substr(1).is_valid_hex_number():
			continue
		var col: Color = Color.html(line)
		palette[_pack(col.r8, col.g8, col.b8)] = true
	return palette


func _pack(r: int, g: int, b: int) -> int:
	return (r << 16) | (g << 8) | b


func _check_palette() -> void:
	var pngs: Array[String] = _files_under(["res://art"], "png")
	if not FileAccess.file_exists(PALETTE_PATH):
		_fail("palette", "%s missing" % PALETTE_PATH)
		return
	var palette: Dictionary = _load_palette()
	if palette.is_empty():
		_fail("palette", "%s has no valid colors" % PALETTE_PATH)
		return
	if palette.size() > MAX_PALETTE_COLORS:
		_fail("palette", "%d colors, max is %d" % [palette.size(), MAX_PALETTE_COLORS])
		return
	if pngs.is_empty():
		_warn("palette", "no PNGs under res://art yet; palette file only checked")
		_pass("palette (%d colors, no art yet)" % palette.size())
		return

	var bad_files: int = 0
	for path: String in pngs:
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null or img.is_empty():
			_fail("palette", "%s could not be read" % path)
			bad_files += 1
			continue
		img.convert(Image.FORMAT_RGBA8)
		var data: PackedByteArray = img.get_data()
		var offenders: Dictionary = {}
		var i: int = 0
		var n: int = data.size()
		while i < n:
			if data[i + 3] != 0:
				if data[i + 3] != 255:
					offenders["semi-transparent pixel"] = true
				var key: int = _pack(data[i], data[i + 1], data[i + 2])
				if not palette.has(key):
					offenders["#%06x" % key] = true
			i += 4
		if not offenders.is_empty():
			bad_files += 1
			var shown: Array[String] = []
			for k: String in offenders.keys():
				shown.append(k)
				if shown.size() >= 5:
					break
			_fail("palette", "%s uses colors outside palette: %s%s" % [
				path, ", ".join(shown), " ..." if offenders.size() > 5 else ""])
	if bad_files == 0:
		_pass("palette (%d PNGs, %d colors)" % [pngs.size(), palette.size()])
