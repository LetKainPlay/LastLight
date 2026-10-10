# AGENT 07 - Pixel-Perfect Camera, Character Controller, Multi-Tier Scene Structure

Last Light, Godot 4.7.2, GDScript 2.0 (static typing), GL Compatibility, target canvas 640x360, integer scale only.

Scope: (A) shimmer-free camera and viewport architecture, (B) the keeper's controller with footstep cadence and a faked spiral staircase, (C) the location/scene structure of the whole island.

Conventions used in every snippet below:

- `res://` paths follow section C.5. The existing `res://scenes/main.tscn` stays where `project.godot` points.
- Y is down. Floors are "feet lines": a character's origin is its feet.
- Everything that ends up on screen sits on the 640x360 game-pixel grid. Nothing is ever rotated or scaled to a non-integer factor.
- Verify-before-trust items are marked `VERIFY` and are covered by the Pixel Lab test in A.9.

---

## A. Pixel-perfect rendering and camera

### A.1 Where shimmer comes from

Three separate artefacts get lumped together as "shimmer". They have different causes and different cures.

| Artefact | Cause | Cure |
|---|---|---|
| Pixel crawl (texels alternate 2px / 3px wide at 3x) | A node sits at a fractional position and is rasterised on a finer grid than the art | Positions are integers in game pixels, or the fractional part is a whole number of screen pixels (A.3) |
| Stair-step stutter (camera moves in visible 3-screen-pixel jumps) | Camera forced to integer game pixels, so slow pans advance in whole-pixel steps | Sub-pixel remainder: move the *picture*, not the world (A.3) |
| Parallax slide-and-snap (far layers slowly slide, then jump back) | Layers with scroll scale < 1 rounded in the same viewport as layers at 1.0 | One SubViewport band per parallax depth, each with its own remainder (A.4) |
| Player jitter against background | Player is pixel-snapped, camera is not | Camera aims at the rounded player position, dead zone, settle (A.5) |
| Frame-rate beat (judder on 144 Hz) | Physics at 60 Hz, camera at display rate | Physics interpolation on, camera reads the interpolated transform (A.2, A.5) |

### A.2 `project.godot` settings

Replace the `[display]` and `[rendering]` sections and add the others. Window default stays 2x of the canvas (1280x720); 3x (1920x1080) is a one-line change.

```ini
[application]
config/name="Het Laatste Licht"
run/main_scene="res://scenes/main.tscn"
config/icon="res://icon.svg"
config/features=PackedStringArray("4.7", "GL Compatibility")

[autoload]
Events="*res://core/events.gd"
Router="*res://core/router.gd"

[display]
window/size/viewport_width=640
window/size/viewport_height=360
window/size/window_width_override=1280
window/size/window_height_override=720
window/size/resizable=true
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
window/vsync/vsync_mode=1
window/handheld/orientation=0

[physics]
common/physics_ticks_per_second=60
common/physics_interpolation=true
2d/default_gravity=900.0

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=false
anti_aliasing/quality/msaa_2d=0
environment/defaults/default_clear_color=Color(0.05, 0.06, 0.1, 1)

[layer_names]
2d_physics/layer_1="world"
2d_physics/layer_2="player"
2d_physics/layer_3="interact"
2d_physics/layer_4="gates"
```

Why each setting:

- `stretch/mode="canvas_items"` with `scale_mode="integer"`: the root window is a 640x360 *coordinate space* that is rendered at exactly N times that in real pixels. A 1366x768 laptop gets 2x with black bars, never 2.13x. This is what makes the remainder technique (A.3) land on whole screen pixels.
- `default_texture_filter=0` (Nearest) globally. The SubViewport and the display `TextureRect` also set nearest explicitly (belt and braces; per-node overrides win).
- `snap_2d_transforms_to_pixel=true`: node transforms are snapped to the render target's pixel grid at draw time. Inside our 641x361 SubViewports that is the *game* pixel grid, which is what we want. `snap_2d_vertices_to_pixel` stays off: it also snaps polygon/line vertices and visibly deforms small Line2D/Polygon2D art; we only need transform snapping. `VERIFY` in the Pixel Lab that snapping applies per SubViewport at its own resolution (it is a per-`Viewport` property: `Viewport.snap_2d_transforms_to_pixel`; we set it in code too).
- `physics_interpolation=true`: bodies are interpolated between 60 Hz ticks for rendering. Combined with `get_global_transform_interpolated()` in the camera rig (A.5), a 144 Hz monitor shows smooth motion. The snap setting then quantises the interpolated result to a pixel. Interpolation never changes physics state.
- Do not use `Camera2D.position_smoothing_*`, `limit_smoothed`, `zoom != 1`, or `rotation_smoothing`. Our rig owns smoothing so that float scroll and the integer/remainder split stay in one place.

### A.3 canvas_items vs viewport mode vs SubViewport upscaling: the exact trade-offs

| | `canvas_items` + integer | `viewport` + integer | **SubViewport upscale (chosen)** |
|---|---|---|---|
| What renders at game resolution | Nothing. Whole scene renders at window resolution, coordinates are scaled | The entire window content renders at 640x360, then is nearest-upscaled | Only the world (in bands). UI and overlays render at window resolution |
| Pixel grid consistency | Weak. Any non-integer position, rotation, scale, particle, Light2D falloff or shader noise lands on a finer grid than the art ("mixels") | Perfect. One grid, enforced by rasteriser | Perfect inside the world, because the world is genuinely 641x361 |
| Sub-pixel camera glide | Yes, but it exposes pixel crawl (texels 2px/3px) unless every sprite is hand-rounded | No. Camera moves in whole game pixels. Nothing finer exists | **Yes, and crawl-free.** Display offset is quantised to whole screen pixels, so every texel stays exactly N px wide |
| Sub-pixel parallax | Same crawl problem | No | Yes, one band per depth (A.4) |
| Rotated/scaled sprites | Smooth at window res (breaks the style) | Pixelated like the rest (consistent) | Pixelated like the rest (consistent) |
| UI and text crispness | Crisp at window res | Blocky: text is also 640x360 pixels | Choice: HUD in the root viewport at window res, or in a band for fully blocky UI |
| Shader/Light2D behaviour | Runs at window res (soft lights, high-res banding) | Runs at game res (chunky, desirable) | Runs at game res inside each band. Lights do not cross bands |
| Mouse/input mapping | Free | Free | Manual (helper in A.4: `PixelView.screen_to_world`) |
| Extra cost | none | none | 4 render targets of 641x361 (about 0.9 MB each), 4 quad draws. Negligible on GL Compatibility |
| Failure modes | Crawl; fractional scaling smears | Camera judder at slow speeds; full-screen filters impossible at hi-res | Needs discipline: world content must live in a band |

Decision: keep project stretch on `canvas_items`/integer (so the root is a clean integer-scaled canvas for UI, fades and the display quads) and render the world through SubViewports. That gives mixel-free art, free sub-pixel scrolling, and crisp UI text.

The sub-pixel remainder technique, precisely:

1. Rig keeps a float scroll `S` (top-left of the view in world pixels).
2. Per band: `s = (S - anchor) * band_scale + anchor`, `whole = floor(s)`, `rem = s - whole` (0 <= rem < 1).
3. The band's camera sits at exactly `whole` (integer). The world is drawn at integer positions.
4. The band's SubViewport is 1 pixel larger than the screen (641x361) so there is always one spare column/row.
5. The display `TextureRect` is positioned at `-rem`, with `rem` quantised to `k / scale` where `scale` is the integer window scale. One game pixel is `scale` screen pixels, so the offset is a whole number of screen pixels: texels remain exactly `scale` px wide, and the picture glides in steps of one *screen* pixel instead of one game pixel.
6. A clipping `Control` crops the extra row/column.

Net effect: the camera moves at screen-pixel resolution (3x finer at 3x), the art never crawls.

### A.4 `PixelView`: the band compositor

Bands (back to front): `sky` (0.05), `far` (0.25), `main` (1.0), `fore` (1.35). Scales above 1.0 give foreground grass/rocks that move faster than the stage. Locations place content into bands by naming child nodes `Sky`, `Far`, `Fore` (everything else stays in the main band). The `main` band is where actors, colliders, tilemaps and Light2D live.

`res://render/pixel_view.gd`:

```gdscript
class_name PixelView
extends Control
## Composites parallax "bands", each a 641x361 SubViewport, onto the 640x360
## canvas with a per-band sub-pixel remainder. Add as full-rect Control in Main.

const VIEW_SIZE: Vector2i = Vector2i(640, 360)
const BAND_SIZE: Vector2i = Vector2i(641, 361)

class Band:
	var id: StringName
	var node_name: StringName   # child of Location that gets adopted
	var scroll_scale: float
	var viewport: SubViewport
	var camera: Camera2D
	var content: Node2D
	var display: TextureRect

## id, location child name, scroll scale, transparent background
const BAND_DEFS: Array = [
	[&"sky", &"Sky", 0.05, false],
	[&"far", &"Far", 0.25, true],
	[&"main", &"Main", 1.0, true],
	[&"fore", &"Fore", 1.35, true],
]

var bands: Array[Band] = []
var _frame: Control
var _scale: float = 1.0
var _main: Band
var _scroll: Vector2 = Vector2.ZERO
var _anchor: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.clip_contents = true
	_frame.size = Vector2(VIEW_SIZE)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	for def: Array in BAND_DEFS:
		var b: Band = _build_band(def[0], def[1], def[2], def[3])
		bands.append(b)
		if b.id == &"main":
			_main = b
	get_window().size_changed.connect(_refresh_scale)
	_refresh_scale()


func _build_band(id: StringName, node_name: StringName, scroll_scale: float, transparent: bool) -> Band:
	var b := Band.new()
	b.id = id
	b.node_name = node_name
	b.scroll_scale = scroll_scale

	var vp := SubViewport.new()
	vp.name = String(id).capitalize() + "Viewport"
	vp.size = BAND_SIZE
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.audio_listener_enable_2d = false
	vp.physics_object_picking = false
	vp.snap_2d_transforms_to_pixel = true
	vp.snap_2d_vertices_to_pixel = false
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var cam := Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT   # top-left == position, always integer
	cam.position_smoothing_enabled = false
	cam.ignore_rotation = true
	vp.add_child(cam)

	var content := Node2D.new()
	content.name = "Content"
	vp.add_child(content)

	var tr := TextureRect.new()
	tr.name = String(id).capitalize() + "Display"
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = Vector2(BAND_SIZE)
	_frame.add_child(tr)

	b.viewport = vp
	b.camera = cam
	b.content = content
	b.display = tr
	return b


## Integer screen scale as the engine will apply it (scale_mode = integer).
func _refresh_scale() -> void:
	var w: Vector2i = get_window().size
	_scale = float(maxi(1, mini(floori(float(w.x) / VIEW_SIZE.x), floori(float(w.y) / VIEW_SIZE.y))))


func screen_scale() -> float:
	return _scale


## Called once per frame by PixelCameraRig. `scroll` is the float top-left of
## the view in world pixels; `anchor` is the parallax origin (room's left/top).
func present(scroll: Vector2, anchor: Vector2) -> void:
	_scroll = scroll
	_anchor = anchor
	for b: Band in bands:
		var s: Vector2 = (scroll - anchor) * b.scroll_scale + anchor
		var whole: Vector2 = s.floor()
		var rem: Vector2 = ((s - whole) * _scale).round() / _scale   # whole screen pixels
		b.camera.position = whole
		b.display.position = -rem


## Moves a Location into the bands. The Location root itself stays in the main
## band; its Sky/Far/Fore children are re-parented into their own bands.
## Requirement: Location root and those children sit at (0, 0).
func mount(location: Node2D) -> void:
	unmount()
	_main.content.add_child(location)
	for b: Band in bands:
		if b == _main:
			continue
		var n: Node = location.get_node_or_null(NodePath(String(b.node_name)))
		if n != null:
			n.reparent(b.content, false)   # keep local transform


func unmount() -> void:
	for b: Band in bands:
		for c: Node in b.content.get_children():
			b.content.remove_child(c)
			c.queue_free()


func main_content() -> Node2D:
	return _main.content


## Mouse (or any screen-space point in 640x360 canvas units) to main-band world.
func screen_to_world(canvas_pos: Vector2) -> Vector2:
	var s: Vector2 = (_scroll - _anchor) * _main.scroll_scale + _anchor
	return canvas_pos + s
```

Notes:

- `Main`-band `scroll_scale` is exactly 1.0 so `screen_to_world` is exact. If you ever change that, change the helper.
- Input (keyboard/gamepad) does not care about SubViewports; only mouse does. The game is keyboard/pad first. `gui_disable_input=true` keeps bands from consuming GUI events.
- Light2D: `Light2D` nodes only light CanvasItems in the same viewport. Beam/glow that must overlap the sea (Far band) is faked with an additive sprite in `Far` or `Fore`, not a real Light2D.
- Sky as the opaque bottom band means `transparent_bg=false` for it only. Windows in the tower walls are real transparent holes in the main band, so the Far/Sky bands show through for free.
- Blend effects across bands (fog, vignette) go in the root viewport as a `CanvasLayer` over `PixelView`, at window resolution; keep them smooth gradients, not banded shapes.

### A.5 `PixelCameraRig`: smoothing, dead zone, bounds, settle

The rig is a plain `Node`. It owns the float scroll, never positions a camera itself, and calls `PixelView.present()` once per frame.

`res://render/pixel_camera_rig.gd`:

```gdscript
class_name PixelCameraRig
extends Node
## Float scroll + dead zone + look-ahead + settle. Quantisation happens in PixelView.

const VIEW: Vector2 = Vector2(640.0, 360.0)

@export var view: PixelView
@export var target: Node2D
@export_group("Follow")
@export var half_life: float = 0.14            ## seconds for the camera to cover half the remaining gap
@export var deadzone: Vector2 = Vector2(36.0, 24.0)
@export var look_ahead: float = 18.0
@export var look_half_life: float = 0.45
@export var torso_offset: Vector2 = Vector2(0.0, -14.0)
@export_group("Settle")
@export var settle_delay: float = 0.7          ## idle seconds before re-centring on the target
@export var settle_half_life: float = 0.5

var bounds: Rect2 = Rect2(Vector2.ZERO, VIEW)
var _scroll: Vector2 = Vector2.ZERO
var _prev_p: Vector2 = Vector2.ZERO
var _look: float = 0.0
var _still: float = 0.0
var _bounds_tween: Tween
var _shake: int = 0
var _shake_time: float = 0.0


func _ready() -> void:
	process_priority = 100        # after Player and everything else
	process_callback = Node.PROCESS_CALLBACK_IDLE if false else 0   # keep default; documented intent only


func _process(delta: float) -> void:
	if view == null or target == null:
		return
	var p: Vector2 = _target_point()
	var moved: bool = p.distance_squared_to(_prev_p) > 0.0001
	_prev_p = p
	_still = 0.0 if moved else _still + delta

	var dir: float = 0.0
	if target.has_method(&"get_look_dir"):
		dir = float(target.call(&"get_look_dir"))
	_look = lerpf(_look, dir * look_ahead, _alpha(look_half_life, delta))

	var focus: Vector2 = p + Vector2(_look, 0.0)
	var centre: Vector2 = _scroll + VIEW * 0.5
	var d: Vector2 = focus - centre
	var goal: Vector2 = _scroll + Vector2(_dead(d.x, deadzone.x), _dead(d.y, deadzone.y))
	var hl: float = half_life
	if _still > settle_delay:
		goal = focus - VIEW * 0.5
		hl = settle_half_life
	goal = _clamp_scroll(goal)

	var gap: Vector2 = goal - _scroll
	if gap.length_squared() < 0.0004:
		_scroll = goal
	else:
		_scroll += gap * _alpha(hl, delta)
	_scroll = _clamp_scroll(_scroll)

	view.present(_scroll + _shake_offset(delta), bounds.position)


func _target_point() -> Vector2:
	# Interpolated transform removes the 60 Hz physics beat on high-refresh displays.
	var o: Vector2 = target.get_global_transform_interpolated().origin
	return (o + torso_offset).round()    # aim at the rounded point the sprite is drawn at


static func _alpha(half: float, delta: float) -> float:
	return 1.0 - pow(0.5, delta / maxf(half, 0.0001))


static func _dead(d: float, zone: float) -> float:
	return signf(d) * maxf(absf(d) - zone, 0.0)


func _clamp_scroll(s: Vector2) -> Vector2:
	return Vector2(
		_clamp_axis(s.x, bounds.position.x, bounds.size.x, VIEW.x),
		_clamp_axis(s.y, bounds.position.y, bounds.size.y, VIEW.y))


static func _clamp_axis(v: float, lo: float, size: float, view_len: float) -> float:
	if size <= view_len:
		return floorf(lo + (size - view_len) * 0.5)   # small room: lock centred, integer
	return clampf(v, lo, lo + size - view_len)


## Instant placement (room entry, teleports).
func snap_to_target() -> void:
	if target == null:
		return
	_scroll = _clamp_scroll(_target_point() - VIEW * 0.5)
	_look = 0.0
	_still = 0.0
	_prev_p = _target_point()
	if view != null:
		view.present(_scroll, bounds.position)


## Change room limits. glide > 0 tweens the rect so storey changes pan, not cut.
func set_bounds(rect: Rect2, glide: float = 0.0) -> void:
	if _bounds_tween != null and _bounds_tween.is_valid():
		_bounds_tween.kill()
	if glide <= 0.0:
		bounds = rect
		return
	_bounds_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bounds_tween.tween_property(self, "bounds", rect, glide)


## Cosy shake: whole-pixel, low frequency. amount in game pixels (1 or 2 is plenty).
func shake(amount: int, seconds: float) -> void:
	_shake = amount
	_shake_time = seconds


func _shake_offset(delta: float) -> Vector2:
	if _shake_time <= 0.0:
		return Vector2.ZERO
	_shake_time -= delta
	if Engine.get_process_frames() % 3 != 0:
		return Vector2.ZERO
	return Vector2(randi_range(-_shake, _shake), randi_range(-_shake, _shake))
```

Behaviour contract:

- Dead zone: the player walks freely inside a 72x48 box; nothing moves, so zero relative shimmer while ambling. When the box edge is pushed, the camera glides with half-life 0.14 s.
- Look-ahead: slow bias in the facing direction.
- Settle: stand still 0.7 s and the camera drifts to centre on the keeper. This is the cosy "breathe" and costs nothing.
- `bounds` can be a `Rect2` smaller than the view (small rooms): the camera locks centred on an integer pixel.
- The `_target_point().round()` is what removes player-vs-background sawtooth while the camera is pushing: camera and sprite follow the same integer sequence; smoothing only changes *when* the scroll arrives, not where the player is drawn relative to the camera for more than a fraction of a pixel.
- Remove the leftover `process_callback` line when pasting; it is a no-op kept out of the engineering path. (Idle callback is the default.)

### A.6 Parallax inside bands

There is no `ParallaxBackground`/`Parallax2D` in this design. The band *is* the parallax layer. Inside a band, extra differential motion is time-driven and stepped to whole game pixels (never `position += speed * delta` on floats):

```gdscript
class_name StepDrift
extends Node2D
## Drifts in whole game pixels at `speed` px/s. Wraps at `wrap_width`. Add under Far/Sky bands.
@export var speed: float = 3.0
@export var wrap_width: int = 0   ## texture width in px, 0 = no wrap
var _t: float = 0.0
var _origin: float

func _ready() -> void:
	_origin = position.x

func _process(delta: float) -> void:
	_t += delta * speed
	var off: float = floorf(_t)
	position.x = _origin - (fposmod(off, float(wrap_width)) if wrap_width > 0 else off)
```

Tiling backgrounds wider than the view (sea band, cloud band): author the texture `(640 + wrap_width)` wide and `StepDrift.wrap_width` = its repeating unit; or use `Sprite2D` with `texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED` and `region_rect` snapped to integers.

Recommended layer usage per location:

| Band | Scale | Typical content |
|---|---|---|
| Sky | 0.05 | Gradient, stars (dither), moon, slow cloud strip (StepDrift 1-2 px/s) |
| Far | 0.25 | Horizon line, distant sea rows, far islet, gulls (small paths, integer steps) |
| Main | 1.00 | Terrain, tower, props, actors, Light2D |
| Fore | 1.35 | Tall grass, rocks, rope, rails. Never covers the keeper for long; keep sparse |

### A.7 Art/asset rules that keep the grid honest

- Even-sized sprites or `centered = false`. A 15x15 centred `Sprite2D` sits on a half-pixel; rounding then flips by +-1 px unpredictably. Prefer `centered = false` and place by feet pixel with an integer `offset`.
- No `rotation`, no `scale` other than +-1 on sprites (flip with `flip_h`, or `scale.x = -1`; both are exact). Swinging things (lantern chain, flag) are frame animations or `Skew`-free sprite swaps.
- Tweens and AnimationPlayer tracks that move sprites in sub-pixel values are fine for the world (snapped by the viewport), but prefer integer keyframes for hand-authored motion so the snapped result is the designed one.
- Atlas padding: import atlases with 1px transparent extrusion off and `region_filter_clip_enabled = true` on region sprites, otherwise neighbours bleed at texture edges.
- Particles: `GPUParticles2D` positions are floats. Use `CPUParticles2D` with small counts and integer-sized textures, or snap with `snap_2d_transforms_to_pixel` (already on); do not scale particle textures over life.
- Text: dialogue/UI in the root viewport uses a pixel font at its native size multiples. World-space signs are baked art.

### A.8 Main scene wiring

`res://scenes/main.tscn`:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scenes/main.gd" id="1_main"]
[ext_resource type="Script" path="res://render/pixel_view.gd" id="2_view"]
[ext_resource type="Script" path="res://render/pixel_camera_rig.gd" id="3_rig"]

[node name="Main" type="Node"]
script = ExtResource("1_main")

[node name="PixelView" type="Control" parent="."]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("2_view")

[node name="PixelCameraRig" type="Node" parent="."]
script = ExtResource("3_rig")

[node name="Overlay" type="CanvasLayer" parent="."]
layer = 10

[node name="Hud" type="Control" parent="Overlay"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2

[node name="Curtain" type="CanvasLayer" parent="."]
layer = 100

[node name="Fade" type="ColorRect" parent="Curtain"]
modulate = Color(1, 1, 1, 0)
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
color = Color(0.03, 0.04, 0.07, 1)
```

`res://scenes/main.gd`:

```gdscript
extends Node

const PLAYER_SCENE: PackedScene = preload("res://actors/player/player.tscn")
const START_LOCATION: String = "res://world/tower_exterior/tower_exterior.tscn"

@onready var _view: PixelView = $PixelView
@onready var _rig: PixelCameraRig = $PixelCameraRig
@onready var _fade: ColorRect = $Curtain/Fade


func _ready() -> void:
	Controls.install()
	var player: Player = PLAYER_SCENE.instantiate() as Player
	_rig.view = _view
	_rig.target = player
	Router.setup(_view, _rig, player, _fade)
	Router.go(START_LOCATION, &"start", true)
```

### A.9 Pixel Lab: prove it, do not trust it

`res://debug/pixel_lab.tscn` (Node2D, run with F6): a 1-px black/white vertical-stripe sprite in the main band, an 8-px-period tile in `Far`, and a rig scroll driven at 0.31 px/frame. Press `P` to dump the grab and assert uniform run lengths.

```gdscript
extends Node

## Run lengths of identical columns in the final frame must be multiples of the integer
## screen scale. Any 1..scale-1 length run means crawl.
func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_P:
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var scale_i: int = maxi(1, mini(img.get_width() / 640, img.get_height() / 360))
		var y: int = img.get_height() / 2
		var run: int = 1
		var bad: int = 0
		for x: int in range(1, img.get_width()):
			if img.get_pixel(x, y).is_equal_approx(img.get_pixel(x - 1, y)):
				run += 1
			else:
				if run % scale_i != 0:
					bad += 1
				run = 1
		print("scale=%d  bad_runs=%d  (expect 0)" % [scale_i, bad])
```

Also manual checks: (1) hold left at 144 Hz (`Engine.max_fps = 144`) and watch the lamp-post edge; (2) slowly pan with a gamepad stick at 5-20 px/s: motion must be smooth, not 3-px steps; (3) resize window to 1366x768: scale 2 with bars, art unchanged.

---

## B. Character controller

### B.1 Design intent

- Weighty but kind: a keeper carrying a lamp, not a platformer hero. No jump. Ground speed 54 px/s (about 3 character-heights per second at a 32 px figure).
- Acceleration ramp 0.14 s to full speed, quicker stop than start, brisk but smooth turn-around.
- Footfalls are events driven by *distance travelled*, not by animation timers. The walk animation is slaved to the same distance, so feet never slide and footsteps always line up with contact frames.
- First step after standing is shorter (5 px) than steady stride (14 px): a visible "push-off".
- Surface-aware: wood, stone, gravel, grass, wet planks, stone stairs, metal grating.
- Stairs are an analytic state, not physics: exact, tread-quantised, and a footfall per tread.

### B.2 Input map and collision layers

`res://core/controls.gd` (not an autoload; a static helper called once from `Main`. Swap for Project Settings entries when bindings are final):

```gdscript
class_name Controls
extends RefCounted

static func install() -> void:
	_bind(&"move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_bind(&"move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_bind(&"move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_bind(&"move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_bind(&"interact", [KEY_E, KEY_ENTER, KEY_SPACE], [JOY_BUTTON_A], JOY_AXIS_INVALID, 0.0)


static func _bind(action: StringName, keys: Array[int], buttons: Array[int], axis: JoyAxis, axis_sign: float) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for k: int in keys:
		var ek := InputEventKey.new()
		ek.physical_keycode = k as Key
		InputMap.action_add_event(action, ek)
	for b: int in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b as JoyButton
		InputMap.action_add_event(action, jb)
	if axis != JOY_AXIS_INVALID:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis
		jm.axis_value = axis_sign
		InputMap.action_add_event(action, jm)
```

Layers: 1 world (terrain, walls, one-way landings), 2 player body, 3 interact (portals, switches), 4 gates (stair gates, camera zones, surface zones).

### B.3 Events bus (tiny, on purpose)

`res://core/events.gd` (autoload `Events`). Audio, particles and camera subscribe; gameplay code never calls them directly.

```gdscript
extends Node

## foot: 0 left, 1 right. weight: 0.5 soft shuffle .. 1.0 firm step. world_pos is feet.
signal footstep(surface: StringName, foot: int, weight: float, world_pos: Vector2)
signal landed(surface: StringName, impact: float, world_pos: Vector2)
signal stair_entered(run_name: StringName)
signal stair_left(run_name: StringName)
signal location_changed(path: String, spawn: StringName)
```

### B.4 `Player`

Scene `res://actors/player/player.tscn`:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://actors/player/player.gd" id="1_player"]
[ext_resource type="SpriteFrames" path="res://data/spriteframes/keeper.tres" id="2_frames"]
[ext_resource type="Shader" path="res://render/depth_shade.gdshader" id="3_shade"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_shade"]
shader = ExtResource("3_shade")
shader_parameter/shade = 0.0

[sub_resource type="RectangleShape2D" id="RectangleShape2D_body"]
size = Vector2(8, 24)

[sub_resource type="RectangleShape2D" id="RectangleShape2D_sensor"]
size = Vector2(6, 20)

[node name="Player" type="CharacterBody2D"]
collision_layer = 2
collision_mask = 1
floor_snap_length = 5.0
floor_max_angle = 0.8
script = ExtResource("1_player")

[node name="Body" type="CollisionShape2D" parent="."]
position = Vector2(0, -12)
shape = SubResource("RectangleShape2D_body")

[node name="Sprite" type="AnimatedSprite2D" parent="."]
material = SubResource("ShaderMaterial_shade")
texture_filter = 1
sprite_frames = ExtResource("2_frames")
animation = &"idle"
centered = false
offset = Vector2(-16, -32)

[node name="Sensor" type="Area2D" parent="."]
collision_layer = 0
collision_mask = 12

[node name="Shape" type="CollisionShape2D" parent="Sensor"]
position = Vector2(0, -10)
shape = SubResource("RectangleShape2D_sensor")
```

`SpriteFrames` contract for the art pipeline: 32x32 frames, feet on the bottom row, origin at bottom-centre (`offset = (-16, -32)`). Animations: `idle` (looping, slow breathe, 4-6 frames), `walk` (6 frames: frames 0 and 3 are the contact poses, i.e. frame `foot*3 + 0` is "foot just landed"), `stair` (same 6-frame layout, 2:1 tread cadence), `turn` optional. Back-plane variants are handled by `depth_shade.gdshader` (below) or, if art prefers palette purity, by duplicate `walk_back`/`stair_back` animations (the script switches on `_plane`).

`res://render/depth_shade.gdshader` (quantised so the sprite stays in-palette-ish):

```glsl
shader_type canvas_item;
render_mode unshaded;

uniform float shade : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shade_color : source_color = vec4(0.10, 0.12, 0.22, 1.0);
uniform float steps = 3.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float s = floor(shade * steps + 0.5) / steps;
	COLOR = vec4(mix(c.rgb, shade_color.rgb, s * 0.5), c.a);
}
```

`res://actors/player/player.gd`:

```gdscript
class_name Player
extends CharacterBody2D
## The keeper. Ground walking with stride-locked animation, plus a stair state
## that follows StairRun nodes analytically (see world/common/stair_run.gd).

enum State { GROUND, STAIR, LOCKED }

@export_group("Walk")
@export var walk_speed: float = 54.0
@export var accel: float = 380.0           ## px/s^2, speeding up
@export var decel: float = 560.0           ## stopping
@export var turn_accel: float = 720.0      ## reversing against current velocity
@export var gravity: float = 900.0
@export var max_fall: float = 320.0
@export_group("Stride")
@export var stride_len: float = 14.0       ## px between footfalls at steady pace
@export var first_step_len: float = 5.0    ## shorter push-off from standstill
@export var idle_delay: float = 0.08       ## seconds below threshold before idle pose
@export_group("Stairs")
@export var stair_speed: float = 38.0
@export var stair_rise_speed: float = 90.0 ## px/s the feet ease up each riser
@export var shade_speed: float = 6.0       ## depth-shade fade speed (1/s)

var state: State = State.GROUND
var facing: int = 1
var plane: int = StairRun.Plane.FRONT

var _sprite: AnimatedSprite2D
var _sensor: Area2D
var _mat: ShaderMaterial
var _foot: int = 0
var _stride_to_next: float = 0.0
var _stride_total: float = 0.0
var _moving: bool = false
var _idle_t: float = 0.0
var _was_on_floor: bool = false
var _fall_speed: float = 0.0
var _surface: StringName = &"stone"
var _stair: StairRun
var _stair_idx: int = -1
var _shade: float = 0.0
var _shade_target: float = 0.0
var _zone_surface: StringName = &""


func _ready() -> void:
	_sprite = $Sprite
	_sensor = $Sensor
	_mat = _sprite.material as ShaderMaterial
	_sensor.area_entered.connect(_on_sensor_area_entered)
	_sensor.area_exited.connect(_on_sensor_area_exited)
	_sprite.play(&"idle")


func get_look_dir() -> float:
	return float(facing)


func lock() -> void:
	state = State.LOCKED
	velocity = Vector2.ZERO
	_set_idle()


func unlock() -> void:
	if state == State.LOCKED:
		state = State.GROUND


func teleport(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	reset_physics_interpolation()          # no smear across the cut
	_moving = false
	_stair = null
	_apply_plane(StairRun.Plane.FRONT, true)
	set_collision_mask_value(1, true)
	state = State.GROUND


func _physics_process(delta: float) -> void:
	match state:
		State.GROUND:
			_tick_ground(delta)
		State.STAIR:
			_tick_stair(delta)
		State.LOCKED:
			pass
	_update_shade(delta)


# --- Ground -----------------------------------------------------------------

func _tick_ground(delta: float) -> void:
	var dir: float = Input.get_axis(&"move_left", &"move_right")
	var a: float = decel
	if dir != 0.0:
		var reversing: bool = signf(velocity.x) == -signf(dir) and absf(velocity.x) > 8.0
		a = turn_accel if reversing else accel
		facing = 1 if dir > 0.0 else -1
	velocity.x = move_toward(velocity.x, dir * walk_speed, a * delta)
	velocity.y = minf(velocity.y + gravity * delta, max_fall)

	_fall_speed = velocity.y
	move_and_slide()

	var on_floor: bool = is_on_floor()
	if on_floor:
		_surface = _surface_under()
	if on_floor and not _was_on_floor and _fall_speed > 140.0:
		Events.landed.emit(_surface, clampf(_fall_speed / max_fall, 0.0, 1.0), global_position)
	_was_on_floor = on_floor

	# Real displacement (zero when pressed against a wall -> no phantom footsteps).
	var dist: float = absf(get_real_velocity().x) * delta
	if on_floor and dist > 0.01:
		_advance_stride(dist)
	else:
		_note_still(delta)

	_sprite.flip_h = facing < 0
	if dir == 0.0 and absf(velocity.x) < 1.0:
		_note_still(delta)

	_try_enter_stair(dir)


## Distance-locked walk cycle. Footfall fires exactly when the contact frame shows.
func _advance_stride(dist: float) -> void:
	if not _moving:
		_moving = true
		_idle_t = 0.0
		_stride_total = first_step_len
		_stride_to_next = first_step_len
		_foot = 1 - _foot            # alternate which foot starts each walk
		_sprite.animation = &"walk"
		_sprite.stop()
	_idle_t = 0.0
	var remaining: float = dist
	while remaining >= _stride_to_next:
		remaining -= _stride_to_next
		_stride_total = stride_len
		_stride_to_next = stride_len
		_foot = 1 - _foot
		Events.footstep.emit(_surface, _foot, _step_weight(), global_position)
	_stride_to_next -= remaining
	var t: float = 1.0 - _stride_to_next / _stride_total          # 0 right after contact .. 1 next contact
	_sprite.frame = _foot * 3 + clampi(floori(t * 3.0), 0, 2)


func _note_still(delta: float) -> void:
	if not _moving:
		return
	_idle_t += delta
	if _idle_t >= idle_delay:
		_set_idle()


func _set_idle() -> void:
	_moving = false
	_sprite.animation = &"idle"
	_sprite.play()


func _step_weight() -> float:
	return clampf(0.55 + 0.45 * absf(velocity.x) / walk_speed, 0.5, 1.0)


func _surface_under() -> StringName:
	if _zone_surface != &"":
		return _zone_surface
	for i: int in get_slide_collision_count():
		var c: KinematicCollision2D = get_slide_collision(i)
		if c.get_normal().dot(Vector2.UP) < 0.7:
			continue
		var col: Object = c.get_collider()
		if col is TileMapLayer:
			var layer: TileMapLayer = col as TileMapLayer
			var cell: Vector2i = layer.get_coords_for_body_rid(c.get_collider_rid())
			var data: TileData = layer.get_cell_tile_data(cell)
			if data != null:
				var s: Variant = data.get_custom_data("surface")
				if s is String and not (s as String).is_empty():
					return StringName(s as String)
		elif col is Node and (col as Node).has_meta(&"surface"):
			return StringName(str((col as Node).get_meta(&"surface")))
	return _surface


# Area2D 'surface zones' (kitchen rug, wet pier planks) override the probe.
func _on_sensor_area_entered(a: Area2D) -> void:
	if a.has_meta(&"surface"):
		_zone_surface = StringName(str(a.get_meta(&"surface")))


func _on_sensor_area_exited(a: Area2D) -> void:
	if a.has_meta(&"surface") and _zone_surface == StringName(str(a.get_meta(&"surface"))):
		_zone_surface = &""


# --- Stairs -----------------------------------------------------------------

func _try_enter_stair(dir: float) -> void:
	if dir == 0.0 or not is_on_floor():
		return
	for a: Area2D in _sensor.get_overlapping_areas():
		var gate: StairGate = a as StairGate
		if gate == null:
			continue
		var along: float = dir * float(gate.run.ascend_dir)
		# Foot gate: walking up-slope enters. Head gate: walking down-slope enters.
		if (gate.end == StairGate.End.FOOT and along > 0.0) or (gate.end == StairGate.End.HEAD and along < 0.0):
			_begin_stair(gate.run)
			return


func _begin_stair(run: StairRun) -> void:
	state = State.STAIR
	_stair = run
	_stair_idx = run.index_at(global_position.x)
	set_collision_mask_value(1, false)
	velocity = Vector2(clampf(velocity.x, -stair_speed, stair_speed), 0.0)
	_moving = true
	_foot = 0
	_surface = run.surface
	_apply_plane(run.plane, false)
	_sprite.animation = &"stair"
	_sprite.stop()
	Events.stair_entered.emit(run.name)


func _tick_stair(delta: float) -> void:
	var run: StairRun = _stair
	var dir: float = Input.get_axis(&"move_left", &"move_right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
	velocity.x = move_toward(velocity.x, dir * stair_speed, accel * delta)
	global_position.x += velocity.x * delta

	var lx: float = (global_position.x - run.global_position.x) * float(run.ascend_dir)
	var along: float = dir * float(run.ascend_dir)
	if lx <= 0.0 and along < 0.0:
		_leave_stair(run.foot_floor_y())
		return
	if lx >= run.length() and along > 0.0:
		_leave_stair(run.head_floor_y())
		return
	lx = clampf(lx, 0.0, run.length())
	global_position.x = run.global_position.x + lx * float(run.ascend_dir)

	# Feet ease onto each tread; the sprite is pixel-snapped by the viewport.
	global_position.y = move_toward(global_position.y, run.floor_y(global_position.x), stair_rise_speed * delta)

	var idx: int = run.index_at(global_position.x)
	if idx != _stair_idx:
		_stair_idx = idx
		_foot = 1 - _foot
		Events.footstep.emit(run.surface, _foot, 0.85, global_position)

	# Frame from progress through the current tread (3 frames per tread).
	var t: float = fposmod(lx, float(run.tread)) / float(run.tread)
	if run.ascend_dir * facing < 0:
		t = 1.0 - t                       # descending plays the cycle in the visual direction of travel
	_sprite.frame = _foot * 3 + clampi(floori(t * 3.0), 0, 2)
	_sprite.flip_h = facing < 0


func _leave_stair(floor_y: float) -> void:
	var name_out: StringName = _stair.name
	global_position.y = floor_y
	velocity.y = 0.0
	set_collision_mask_value(1, true)
	_stair = null
	state = State.GROUND
	_moving = false
	_was_on_floor = true
	_set_idle()
	Events.stair_left.emit(name_out)


# --- Depth plane (front / back of the spiral) -------------------------------

func _apply_plane(p: int, instant: bool) -> void:
	plane = p
	z_index = Z.ACTOR_BACK if p == StairRun.Plane.BACK else Z.ACTOR
	_shade_target = 1.0 if p == StairRun.Plane.BACK else 0.0
	if instant:
		_shade = _shade_target
		_mat.set_shader_parameter(&"shade", _shade)


func _update_shade(delta: float) -> void:
	if not is_equal_approx(_shade, _shade_target):
		_shade = move_toward(_shade, _shade_target, shade_speed * delta)
		_mat.set_shader_parameter(&"shade", _shade)
```

Behaviour notes:

- **Cadence numbers.** At 54 px/s and a 14 px stride, steady cadence is 3.86 footfalls/s (a relaxed walk). Stairs: 38 px/s over an 8 px tread is 4.75 footfalls/s, deliberately a touch busier because a climb is effortful and short.
- **No ground-plane ambiguity at seams.** `_surface_under()` only trusts collisions with a near-upward normal, so a wall brush never changes the footstep material.
- **Stair exit y.** `StairRun.foot_floor_y()` / `head_floor_y()` return the exact landing heights; `move_and_slide` resumes with `floor_snap_length` catching any residual 1-2 px error. Author landing colliders so their top surface is exactly those Y values (the `StairRun` configuration warning checks parent alignment).
- **Physics interpolation.** Setting `global_position` directly in `_physics_process` is interpolated like any other motion. After a teleport or a plane swap that moves position discontinuously call `reset_physics_interpolation()` (done in `teleport()`).
- **Back-plane z.** The plane only affects draw order and shade. Collision never uses it (world mask is off during stairs).

### B.5 `StairRun` and gates: the faked spiral

#### Concept: why this reads as a spiral in a side view

A tower interior cutaway is a 2D slice. A spiral is faked by three cues stacked together:

1. **Alternating flights with a turning landing.** Flight 1 climbs left to right in the *front* plane. At the right wall there is a short landing. Flight 2 climbs right to left in the *back* plane. The brain reads "went around the back".
2. **Occlusion.** The central newel column sits at `Z.COLUMN`, between the planes. The back-plane keeper is hidden behind it for a few frames while crossing; the front-plane keeper walks in front. At each wall turn, a foreground buttress (`Z.BUTTRESS`) hides the keeper completely for 6-10 frames while the plane swaps. This hidden swap is what removes any visual seam.
3. **Depth cues.** Back-plane stair art is two palette steps darker with less contrast; the back-plane keeper is shaded (shader above or `*_back` animations); walking direction reverses naturally; a small back-flight handrail is partly hidden by the column.

Tiered landings carry the *place* feeling: each landing is its own small composition (window with a sea slice via the Far band, a coat hook, a lantern oil shelf, a barometer, a cat on the sill). The landing is where interactions and storey transitions live, so the staircase is a sequence of tiny rooms joined by flights, not a repeated tile.

Geometry (tower interior 304 px wide, storey pitch 240 px = two flights):

```
x: 168                                                        472
   |<------------------- 304 interior ------------------------->|
   |                                                            |
   |  [wall pier]                                    [wall pier]|   <- Z.BUTTRESS (foreground)
   |  ____                                        ____          |
   | | L2 |  <-- landing (32px) --- back flight top  | L1 |       |
   | |____|            \  \  \  \  \  \  \  \  \ ___|____|      |
   |        \  \  \  \  \  \  \  \  \  back flight (30 treads    |
   |  ___________________________________________  right->left)  |
   |  front flight (30 treads, left->right):   __/__/__/__/__    |
   |  foot at x=200, head at x=440                               |
```

Numbers per flight: `tread = 8`, `riser = 4`, `steps = 30` gives run 240 px and rise 120 px; a clean 2:1 pixel-art slope (every tread edge is a perfect 2-px-per-1-px diagonal). Two flights = 240 px = one storey. Landings are 32 px (168..200 left, 440..472 right) and hold the buttress.

Per-storey layout (world coordinates, Y down; floor lines at multiples of 240):

| Storey | Floor Y | Purpose | Stair connects |
|---|---|---|---|
| F0 | 0 | Entry, store, boat gear | Front flight up |
| F1 | -240 | Kitchen, table, stove | Back flight up |
| F2 | -480 | Bedroom, desk, window with sea | Front flight up |
| F3 | -720 | Watch room, logbook, workshop | Back flight up |
| F4 | -960 | Lantern room (via short ladder, see B.6) | |

#### `z_layers.gd`

`res://world/common/z_layers.gd`:

```gdscript
class_name Z
extends RefCounted
## Absolute z_index values inside the main band. Use these constants, never literals.

const BACKWALL: int = -40
const PROPS_BACK: int = -30
const STAIR_BACK: int = -22      ## back-flight art + its handrail
const ACTOR_BACK: int = -20      ## keeper on the back flight
const COLUMN: int = -10          ## central newel: hides the back plane, sits behind front plane
const TERRAIN: int = 0           ## floors, walls (TileMapLayer)
const STAIR_FRONT: int = 5
const ACTOR: int = 10            ## keeper on the ground and front flight, NPCs, boat
const PROPS_FRONT: int = 20      ## things the keeper walks behind: table front, railing, curtains
const BUTTRESS: int = 30         ## wall piers at the turning landings
const FX: int = 40               ## steam, dust motes, lantern glow sprites
```

Because `ACTOR_BACK` (-20) < `COLUMN` (-10) < `TERRAIN` (0) < `ACTOR` (10), the back-plane keeper is hidden by the column *and* by any terrain/wall tiles in front of the back stair. Author the back flight's handrail at `STAIR_BACK`.

#### `stair_run.gd`

`res://world/common/stair_run.gd`:

```gdscript
@tool
class_name StairRun
extends Node2D
## One flight of stairs. Node origin = foot of the flight at the lower floor level.
## The flight climbs toward +x when ascend_dir = 1, toward -x when -1.
## Place as a sibling of the stair art; it owns only logic and two entry gates.

enum Plane { FRONT, BACK }

@export var plane: Plane = Plane.FRONT
@export_enum("Left", "Right") var ascend_toward: int = 1:
	set(v):
		ascend_toward = v
		ascend_dir = 1 if v == 1 else -1
@export var steps: int = 30
@export var tread: int = 8
@export var riser: int = 4
@export var surface: StringName = &"stone_stair"
@export var gate_depth: float = 12.0

var ascend_dir: int = 1


func _ready() -> void:
	ascend_dir = 1 if ascend_toward == 1 else -1
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_make_gate(StairGate.End.FOOT)
	_make_gate(StairGate.End.HEAD)


func length() -> float:
	return float(steps * tread)


func total_rise() -> float:
	return float(steps * riser)


## Floor height at the bottom landing (y of the node origin).
func foot_floor_y() -> float:
	return global_position.y


## Floor height at the top landing.
func head_floor_y() -> float:
	return global_position.y - total_rise()


func index_at(global_x: float) -> int:
	var lx: float = (global_x - global_position.x) * float(ascend_dir)
	return clampi(floori(lx / float(tread)), 0, steps - 1)


## Stepped tread-top height at global x (feet sit here).
func floor_y(global_x: float) -> float:
	return global_position.y - float(index_at(global_x) + 1) * float(riser)


func head_global_x() -> float:
	return global_position.x + length() * float(ascend_dir)


func _make_gate(end: StairGate.End) -> void:
	var g := StairGate.new()
	g.run = self
	g.end = end
	g.collision_layer = 8          # layer 4 'gates'
	g.collision_mask = 0
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(gate_depth, 20.0)
	cs.shape = r
	g.add_child(cs)
	# Foot gate straddles lx in [-gate_depth, 0]; head gate straddles [length, length + gate_depth].
	var lx: float = -gate_depth * 0.5 if end == StairGate.End.FOOT else length() + gate_depth * 0.5
	var y_off: float = -10.0 if end == StairGate.End.FOOT else -total_rise() - 10.0
	g.position = Vector2(lx * float(ascend_dir), y_off)
	add_child(g)


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if tread < 1 or riser < 1 or steps < 1:
		w.append("tread, riser and steps must be >= 1.")
	if roundf(global_position.x) != global_position.x or roundf(global_position.y) != global_position.y:
		w.append("Place the foot on integer pixels.")
	return w


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i: int in steps:
		var x0: float = float(i * tread) * float(ascend_dir)
		var x1: float = float((i + 1) * tread) * float(ascend_dir)
		var y: float = -float((i + 1) * riser)
		pts.append(Vector2(x0, y))
		pts.append(Vector2(x1, y))
	draw_polyline(pts, Color(1.0, 0.8, 0.3, 0.9), 1.0)
```

`res://world/common/stair_gate.gd`:

```gdscript
class_name StairGate
extends Area2D

enum End { FOOT, HEAD }

var run: StairRun
var end: End = End.FOOT
```

How a flight is assembled in a scene:

```
StairF0_Front (Node2D, StairRun script)  plane=FRONT  ascend_toward=Right  steps=30 position=(200, 0)
  +-- Art (Sprite2D / TileMapLayer)     z_index = Z.STAIR_FRONT   (stepped stair silhouette, 240x120)
  +-- Rail (Sprite2D)                   z_index = Z.PROPS_FRONT
StairF0_Back (Node2D, StairRun script)  plane=BACK   ascend_toward=Left   steps=30 position=(440, -120)
  +-- Art                               z_index = Z.STAIR_BACK   (darker palette)
  +-- Rail                              z_index = Z.STAIR_BACK
```

Sequence of one full storey (right-hand climbing):

1. Keeper on F0 floor walks right into `StairF0_Front` foot gate, holding right. `_begin_stair`: mask off, plane FRONT.
2. 30 treads, 30 footfalls with the tread cadence. Head reached at x=440, y=-120, onto the right landing.
3. State GROUND on the landing (landing collider top at y=-120). Keeper keeps walking right into the **buttress** (`Z.BUTTRESS`): sprite disappears behind it, for the width of the pier (16 px about 0.4 s).
4. `StairF0_Back` foot gate sits right at the buttress, with `ascend_toward=Left`. Reversing direction (press left) while hidden enters the flight: plane BACK, shade fades in under cover over 0.17 s.
5. Keeper emerges walking left up the back flight, shaded, behind the column, to x=200, y=-240: the F1 floor/landing (left wall pier hides the next swap if another front flight continues; on F1 the kitchen door sits there instead).
6. Descent is the exact reverse via the head gates.

The ambiguity "player walks into buttress and can't turn" is resolved by designing the turn landing as a 32-px walkable bay: the buttress overlaps only the outer half of it, the player can stand fully visible at the inner half, and walking into the outer half fades them behind the pier. The foot gate of the next flight is in the hidden half.

Camera in the shaft: the storey `CameraZone` (C.4) glides `bounds` as the keeper changes storey; the rig's dead zone keeps the lateral view still while climbing.

### B.6 Ladder to the lantern room (vertical variant)

The final climb is a short vertical ladder, not stairs, for pacing: the big staircase gets you home, the ladder gets you to *the light*. `LadderRun` is a trimmed `StairRun`: `tread` replaced by `rung_gap = 6`, x locked, input on `move_up/move_down`, footstep surface `metal_ladder`, animation `climb` (2 frames hand-over-hand per rung). Implement as a third `Player` state `LADDER` copying `_tick_stair` with axes swapped; omitted here as it follows the same pattern and is gated by an identical `StairGate`-like `LadderGate`.

---

## C. Multi-tier scene structure

### C.1 Overview and transitions

```
                          SEA EXPANSE  (open water, rowing)
                              ^
                              | boat (Portal kind=BOAT, fade)
                              |
 TOWER EXTERIOR  <----------> BOATHOUSE + PIER
 (cliff, grass, door)        (workshop, pier, rowboat)
      |
      | door (Portal, fade)
      v
 TOWER INTERIOR  (one continuous vertical location, camera zones per storey)
   F4 Lantern room   (ladder)
   F3 Watch room
   F2 Bedroom        } living quarters
   F1 Kitchen        }
   F0 Entry / store   -- door -->
```

| Transition | Mechanism | Feel |
|---|---|---|
| Exterior door <-> interior F0 | `Portal` + `Router.go`, stepped fade (5 steps of 50 ms), spawn marker `from_exterior` | A real threshold; you hear the latch |
| Exterior path <-> boathouse | `Portal` (edge of scene, walk off, no interaction), fade | Walk the cliff path; wooden planks begin |
| Pier <-> sea | Boat interaction: keeper lock, rowing intro, `Router.go(sea)` | Slow, deliberate, no skip |
| Floor <-> floor | None. Same scene, stairs + camera zones | Continuous, the staircase is the transition |
| Interior F4 gallery door | `Portal` to exterior at `lantern_gallery` spawn | Brief view of the beam from outside |

Rule: **transitions only where physical thresholds exist**. Never a load between two places you could walk between.

### C.2 `Location` base, `Portal`, `CameraZone`

`res://world/common/location.gd`:

```gdscript
class_name Location
extends Node2D
## Root of every place. Child nodes named Sky / Far / Fore are adopted by PixelView bands.

@export var bounds: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)   ## default camera limits
@export var anchor_to_bounds: bool = true
@export var ambience: StringName = &""
@export var music: StringName = &""
@export var interior: bool = false                          ## muffles weather, changes reverb

@onready var actors: Node2D = $Actors
@onready var spawns: Node = $Spawns


func get_spawn(id: StringName) -> Vector2:
	var m: Node2D = spawns.get_node_or_null(NodePath(String(id))) as Node2D
	if m == null:
		push_warning("Spawn '%s' missing in %s" % [id, name])
		m = spawns.get_child(0) as Node2D
	return m.global_position.round()


func get_spawn_facing(id: StringName) -> int:
	var m: Node = spawns.get_node_or_null(NodePath(String(id)))
	return int(m.get_meta(&"facing", 1)) if m != null else 1
```

`res://world/common/portal.gd`:

```gdscript
class_name Portal
extends Area2D
## Threshold to another Location. Walk-through or press interact.

@export_file("*.tscn") var target: String
@export var spawn: StringName = &"default"
@export var needs_interact: bool = true
@export var locked: bool = false

signal prompt_changed(visible: bool)

var _inside: bool = false


func _ready() -> void:
	collision_layer = 4          # interact
	collision_mask = 2           # player
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(body: Node2D) -> void:
	if not body is Player:
		return
	_inside = true
	if needs_interact:
		prompt_changed.emit(true)
	elif not locked:
		Router.go(target, spawn)


func _on_exit(body: Node2D) -> void:
	if body is Player:
		_inside = false
		prompt_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if _inside and needs_interact and not locked and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		Router.go(target, spawn)
```

`res://world/common/camera_zone.gd`:

```gdscript
class_name CameraZone
extends Area2D
## Entering swaps the camera limits. Use one per storey / pier section.

@export var limits: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)
@export var glide: float = 0.6


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(func(b: Node2D) -> void:
		if b is Player:
			Router.rig.set_bounds(limits, glide))
```

### C.3 `Router` (autoload)

`res://core/router.gd`:

```gdscript
extends Node
## Owns location swaps. Small scenes, so a plain load() is fine; switch to
## ResourceLoader.load_threaded_request if a location grows past a few MB.

const FADE_STEPS: int = 5
const FADE_STEP_TIME: float = 0.05

var view: PixelView
var rig: PixelCameraRig
var player: Player
var current: Location
var current_path: String = ""

var _fade: ColorRect
var _busy: bool = false


func setup(v: PixelView, r: PixelCameraRig, p: Player, fade_rect: ColorRect) -> void:
	view = v
	rig = r
	player = p
	_fade = fade_rect


func go(path: String, spawn: StringName = &"default", instant: bool = false) -> void:
	if _busy or path.is_empty():
		return
	_busy = true
	if player.is_inside_tree():
		player.lock()
	if not instant:
		await _stepped_fade(true)
	_swap(path, spawn)
	await get_tree().process_frame            # let _ready()s run before the camera snaps
	rig.snap_to_target()
	if not instant:
		await _stepped_fade(false)
	player.unlock()
	_busy = false


func _swap(path: String, spawn: StringName) -> void:
	if player.get_parent() != null:
		player.get_parent().remove_child(player)    # keep the keeper alive across the cut
	view.unmount()
	var scene: PackedScene = load(path) as PackedScene
	var loc: Location = scene.instantiate() as Location
	view.mount(loc)
	loc.actors.add_child(player)
	player.teleport(loc.get_spawn(spawn))
	player._sprite.flip_h = loc.get_spawn_facing(spawn) < 0
	player.facing = loc.get_spawn_facing(spawn)
	rig.set_bounds(loc.bounds, 0.0)
	rig.bounds = loc.bounds
	current = loc
	current_path = path
	Events.location_changed.emit(path, spawn)


## Stepped alpha reads as a chunky pixel fade rather than a smooth modern one.
func _stepped_fade(to_black: bool) -> void:
	for i: int in range(FADE_STEPS + 1):
		var k: float = float(i) / float(FADE_STEPS)
		_fade.modulate.a = k if to_black else 1.0 - k
		await get_tree().create_timer(FADE_STEP_TIME).timeout
```

The `Player` accesses `_sprite` here for a flip; if you prefer encapsulation, add `Player.face(dir: int)` and call that instead.

State persistence (lamp lit, oil, lens cleaned, boat position) belongs in a plain `Resource` held by whichever system the game-state agent defines. Locations read it in `_ready`. The Router stays state-free.

### C.4 Scene trees

Common skeleton (every `Location`):

```
Location (Node2D, location.gd)          position (0,0)
+-- Sky (Node2D)                        -> adopted by sky band
+-- Far (Node2D)                        -> adopted by far band
+-- Terrain (TileMapLayer)              z = Z.TERRAIN, physics layer 1, custom data 'surface'
+-- BackWall (TileMapLayer)             z = Z.BACKWALL
+-- Props (Node2D)                      back/front props, each with explicit z from Z
+-- Actors (Node2D)                     keeper + NPCs are added here at runtime
+-- Triggers (Node2D)                   Portal, CameraZone, surface zones
+-- Spawns (Node2D)                     Marker2D children named by spawn id (meta 'facing')
+-- Lights (Node2D)                     Light2D, additive glow sprites
+-- Fore (Node2D)                       -> adopted by fore band
```

All `Node2D` containers sit at (0,0). Bands rely on that.

#### C.4.1 Tower exterior

```
TowerExterior (Location)                bounds = Rect2(0, 0, 1280, 360)
+-- Sky (Node2D)
|   +-- Gradient (Sprite2D)             640x360 dithered dusk gradient
|   +-- Stars (Sprite2D)                twinkle via AnimatedSprite2D, 2 frames, 1 Hz
|   +-- Moon (Sprite2D)
|   +-- Clouds (StepDrift)              speed 1.5 px/s, wrap_width 320
+-- Far (Node2D)
|   +-- Horizon (Sprite2D)              horizon line, distant sea rows
|   +-- SeaFar (StepDrift)              speed 2 px/s, wrap_width 64
|   +-- Islet (Sprite2D)
|   +-- Gulls (Node2D)                  AnimatedSprite2D on integer paths
+-- Terrain (TileMapLayer)              cliff top, path, grass, rocks (physics layer 1)
+-- Tower (Node2D)                      pre-composed tower sprite (outer wall, gallery, lantern cap)
|   +-- Facade (Sprite2D)               z = Z.PROPS_BACK
|   +-- Door (Node2D)                   door sprite + Portal -> tower_interior @ from_exterior
|   +-- LanternGlow (Sprite2D)          additive, z = Z.FX
|   +-- BeamPivot (Node2D)              beam sprite, frame-stepped sweep (8 frames), not rotated
+-- Props (Node2D)                      fence, bench, washing line, lamp post
+-- Actors (Node2D)
+-- Triggers (Node2D)
|   +-- PathToBoathouse (Portal)        needs_interact=false, at right edge, spawn = from_cliff
|   +-- GalleryReturn (Marker2D)        spawn 'lantern_gallery'
+-- Spawns (Node2D)
|   +-- start, from_interior, from_boathouse
+-- Lights (Node2D)                     PointLight2D at the lantern, warm, energy 0.9
+-- Fore (Node2D)
    +-- Grass (Sprite2D / tiles)        tall grass in front
    +-- Rocks (Sprite2D)
```

Beam: a rotating Sprite2D breaks the grid. Author the sweep as 8-16 pre-rendered frames of the beam on a shared atlas and switch frames (`AnimatedSprite2D`), additive blend. The light cone on clouds is a sky-band additive overlay driven by the same frame index.

#### C.4.2 Tower interior (living quarters + lantern room)

```
TowerInterior (Location)               interior=true, bounds = Rect2(0, -1210, 640, 1450)
+-- Sky / Far                          sky + sea slice visible through windows
+-- ShellWall (Sprite2D / TileMapLayer) outer stone shell, windows are transparent holes
+-- BackWall (TileMapLayer)            interior wall plaster per storey, z = Z.BACKWALL
+-- Column (Sprite2D)                  central newel, 28px wide full-height, z = Z.COLUMN
+-- Storeys (Node2D)
|   +-- F0_Entry (Node2D)              Floor collider top at y=0
|   |   +-- Terrain / Props / Interactables
|   +-- F1_Kitchen (Node2D)            y=-240 (stove, table, kettle: cooking minigame spot)
|   +-- F2_Bedroom (Node2D)            y=-480 (bed, desk, window, plant)
|   +-- F3_Watch (Node2D)              y=-720 (logbook, radio, workshop bench)
|   +-- F4_Lantern (Node2D)            y=-960 (lens, clockwork, oil lamp, gallery door)
+-- Stairs (Node2D)
|   +-- Flight_F0_Front (StairRun)     pos (200, 0)      Right   FRONT
|   +-- Flight_F0_Back  (StairRun)     pos (440, -120)   Left    BACK
|   +-- Flight_F1_Front (StairRun)     pos (200, -240)   Right   FRONT
|   +-- Flight_F1_Back  (StairRun)     pos (440, -360)   Left    BACK
|   +-- Flight_F2_Front (StairRun)     pos (200, -480)   Right   FRONT
|   +-- Flight_F2_Back  (StairRun)     pos (440, -600)   Left    BACK
|   +-- Flight_F3_Front (StairRun)     pos (200, -720)   Right   FRONT
|   +-- Flight_F3_Back  (StairRun)     pos (440, -840)   Left    BACK
|   +-- Ladder_F4 (LadderRun)          pos (320, -840) .. (320, -960)
|   +-- Buttresses (Node2D)            wall piers at x 168..184 and 456..472, z = Z.BUTTRESS
+-- Actors (Node2D)
+-- Triggers (Node2D)
|   +-- ZoneF0 .. ZoneF4 (CameraZone)  limits Rect2(0, floor-250, 640, 360), glide 0.6
|   +-- DoorOut (Portal)               -> tower_exterior @ from_interior
|   +-- GalleryDoor (Portal)           -> tower_exterior @ lantern_gallery
+-- Spawns (Node2D)
|   +-- from_exterior, from_gallery, bed
+-- Lights (Node2D)                    per-room warm PointLight2D, flicker via stepped Tween
+-- Fore (Node2D)                      curtains, hanging pots, ropes (sparse)
```

Stair flights alternate F0 front, F0 back, F1 front, F1 back... so the helix is continuous: each *storey* is two flights, with front flights at even half-storeys and back flights at odd. Feet y at the foot of a back flight equals the head floor of the previous front flight; coordinates above follow this chain.

Lantern room (F4) specifics: smaller diameter (decrease interior to 240 px by sprite art; `bounds` at that storey is `Rect2(200, -1210, 240, 360)`, narrower than the view so the rig locks it centred), glass lens with shader-free frame animation, the oil/wick interactions, and the gallery door out. Living quarters (F1+F2) are cosy density zones: more props, rugs (surface zone `wood_rug`), warm lights. F0 keeps the sparse "working base" feel.

#### C.4.3 Boathouse and pier

```
Boathouse (Location)                   bounds = Rect2(0, 0, 960, 360)
+-- Sky / Far                          shared sky + horizon, sea rows visible beyond pier end
+-- Terrain (TileMapLayer)             shore stones, planks (custom data 'surface' = wood_wet / wood / gravel)
+-- BackWall (TileMapLayer)            boathouse interior wall, z = Z.BACKWALL
+-- Boathouse (Node2D)                 building shell, open front; roof is a Fore element when inside
|   +-- Interior (Node2D)              workbench, nets, oil barrels
|   +-- Roof (Sprite2D)                z = Z.PROPS_FRONT; fades out when keeper enters (modulate step)
+-- Pier (Node2D)
|   +-- Planks (TileMapLayer)          walkable, collision layer 1
|   +-- Posts (Sprite2D)               z = Z.PROPS_FRONT on alternate posts
|   +-- WaterBelow (Node2D)            tidal sprite rows, StepDrift, z = Z.PROPS_BACK
|   +-- Rowboat (Node2D)               moored; interact -> sea
+-- Actors / Triggers / Spawns / Lights
|   +-- Triggers: PathToExterior (Portal), BoatBoard (Portal, needs_interact, target = sea @ boat_start)
+-- Fore (Node2D)                      reeds, rope coils, mooring lines
```

The roof fade: a one-shot `Area2D` toggling the roof sprite's alpha in 4 steps (same stepped fade as the Router) when the keeper enters the boathouse bounds.

#### C.4.4 Sea expanse

```
SeaExpanse (Location)                  bounds = Rect2(0, 0, 4096, 360) (rowing scrolls horizontally)
+-- Sky (Node2D)                       time-of-day gradient, clouds (StepDrift)
+-- Far (Node2D)                       horizon, far swell rows (sea_bands shader), distant lighthouse beam (frame stepped)
+-- WaterMid (Node2D)                  mid swell rows, z = Z.PROPS_BACK
+-- Boat (Node2D, boat.gd)             player-controlled: rowing speed, stepped bob
|   +-- Hull (AnimatedSprite2D)        4 frames rowing stroke
|   +-- Keeper (AnimatedSprite2D)      seated keeper layered in the boat
|   +-- Lantern (Sprite2D)             hung lantern, additive glow, Light2D
+-- Hazards (Node2D)                   buoys, rocks, flotsam (small Area2D)
+-- Actors / Triggers / Spawns         boat_start, boat_return
+-- Lights (Node2D)                    boat lantern + moon glow
+-- Fore (Node2D)                      near-water spray rows, z = Z.FX
```

Bob/wave stepping rule: boat Y = base + `round(sin(t * 1.6) * 1.5)`. Never feed floats to the sprite position; 1-px steps read as gentle swell at this resolution.

`res://render/sea_bands.gdshader` (step-quantised wave rows; the whole thing stays on the game grid):

```glsl
shader_type canvas_item;

uniform sampler2D wave_tex : filter_nearest, repeat_enable;
uniform float row_h = 4.0;           // rows in game px
uniform float speed = 6.0;           // px/s
uniform float amp = 1.0;             // px

void fragment() {
	vec2 px = UV / TEXTURE_PIXEL_SIZE;                 // texel coords
	float row = floor(px.y / row_h);
	float dir = (mod(row, 2.0) < 1.0) ? 1.0 : -1.0;
	float shift = floor(TIME * speed * (0.5 + 0.1 * row) * dir);   // whole texels
	vec2 uv = vec2((px.x + shift) * TEXTURE_PIXEL_SIZE.x, UV.y);
	COLOR = texture(TEXTURE, uv);
}
```

`res://actors/boat/boat.gd` (minimal; same accel logic as the keeper, scroll speed):

```gdscript
class_name Boat
extends Node2D

@export var max_speed: float = 30.0
@export var accel: float = 18.0
@export var drag: float = 10.0
@export var base_y: float = 252.0

var speed: float = 0.0
var _t: float = 0.0
var _x: float = 0.0


func _process(delta: float) -> void:
	var dir: float = Input.get_axis(&"move_left", &"move_right")
	speed = move_toward(speed, dir * max_speed, (accel if dir != 0.0 else drag) * delta)
	_x += speed * delta
	_t += delta
	global_position = Vector2(roundf(_x), base_y + roundf(sin(_t * 1.6) * 1.5))
```

(The boat is `target` for the camera rig in the sea location; set `Router.rig.target = boat` on enter. It implements `get_look_dir()` if look-ahead is wanted.)

### C.5 Folder layout under `res://`

```
res://
|-- project.godot
|-- icon.svg
|-- scenes/
|   |-- main.tscn                    entry (existing path)
|   `-- main.gd
|-- core/                            autoloads and tiny statics only
|   |-- events.gd
|   |-- router.gd
|   `-- controls.gd
|-- render/
|   |-- pixel_view.gd
|   |-- pixel_camera_rig.gd
|   |-- step_drift.gd
|   |-- depth_shade.gdshader
|   `-- sea_bands.gdshader
|-- actors/
|   |-- player/
|   |   |-- player.tscn
|   |   `-- player.gd
|   `-- boat/
|       |-- boat.tscn
|       `-- boat.gd
|-- world/
|   |-- common/
|   |   |-- location.gd
|   |   |-- portal.gd
|   |   |-- camera_zone.gd
|   |   |-- stair_run.gd
|   |   |-- stair_gate.gd
|   |   `-- z_layers.gd
|   |-- tower_exterior/
|   |   |-- tower_exterior.tscn
|   |   `-- tower_exterior_tiles.tres
|   |-- tower_interior/
|   |   |-- tower_interior.tscn
|   |   |-- storeys/                 f0_entry.tscn ... f4_lantern.tscn (instanced into Storeys)
|   |   `-- stairs/                  flight_front.tscn, flight_back.tscn (pre-wired StairRun + art)
|   |-- boathouse/
|   |   `-- boathouse.tscn
|   `-- sea/
|       `-- sea_expanse.tscn
|-- art/
|   |-- characters/                  keeper.png (+ .aseprite source outside res:// or in /art/src)
|   |-- tiles/                       tower_exterior.png, tower_interior.png, pier.png
|   |-- props/
|   |-- backgrounds/                 sky_*.png, sea_*.png, far_*.png
|   |-- fx/                          beam_frames.png, glow.png, spray.png
|   `-- ui/
|-- data/
|   |-- spriteframes/keeper.tres
|   `-- tilesets/                    *.tres with physics layer + custom data 'surface'
|-- audio/
|   |-- sfx/steps/                   wood_*.ogg, stone_*.ogg, gravel_*.ogg, stone_stair_*.ogg ...
|   `-- music/
`-- debug/
    `-- pixel_lab.tscn
```

Conventions: one folder per place under `world/`, shared logic in `world/common/`; art is never inside code folders; tiles' `surface` custom data string must match filenames in `audio/sfx/steps/<surface>_NN.ogg`, so the audio agent can resolve footsteps by naming alone.

### C.6 Z-order and parallax summary

Cross-band order is fixed by `PixelView` child order: Sky, Far, Main, Fore (back to front). Inside the main band use only the `Z` constants.

| Z (main band) | Constant | Examples |
|---|---|---|
| -40 | BACKWALL | plaster wall, cliff face, boathouse back wall |
| -30 | PROPS_BACK | back shelves, boat shed rafters, tower facade (exterior) |
| -22 | STAIR_BACK | back flights and their railings |
| -20 | ACTOR_BACK | keeper on a back flight |
| -10 | COLUMN | central newel |
| 0 | TERRAIN | floors, walls, pier planks |
| 5 | STAIR_FRONT | front flights |
| 10 | ACTOR | keeper, NPCs, boat |
| 20 | PROPS_FRONT | table fronts, rails, roof of boathouse, pier posts |
| 30 | BUTTRESS | wall piers at turning landings |
| 40 | FX | dust motes, steam, additive glow sprites |

Parallax scales: Sky 0.05, Far 0.25, Main 1.00, Fore 1.35. Locations can override by editing `BAND_DEFS`; interior locations normally have almost nothing in Sky/Far except what is seen through windows. Keep `Fore` sparse: it moves faster than the stage, so anything large there fights the keeper for attention.

### C.7 Hard rules (checklist for reviews)

1. All world content lives under a `Location` in a band; nothing parented to the root viewport except UI and the fade.
2. Locations and band containers at (0,0); everything else integer-positioned. Use `Marker2D` + `round()` for spawns (done in `get_spawn`).
3. No rotation or non-unit scale on world sprites. Beams and swinging objects are frame sequences.
4. Camera: only `PixelCameraRig`. No `Camera2D` smoothing, limits, or zoom anywhere.
5. Parallax only through bands. Time-driven drift only through `StepDrift` or whole-texel shader shifts.
6. Footsteps are emitted exclusively via `Events.footstep` from `Player`. Audio and FX listen; they do not poll.
7. Transition via `Router.go` and only at physical thresholds. No loading screens, no black holds longer than 0.5 s in total.
8. Run Pixel Lab after any change to render code, project stretch settings, or Godot version.
9. If `VERIFY` items fail on 4.7.2 (snap behaviour per SubViewport, `reset_physics_interpolation`, `get_global_transform_interpolated`), the fallbacks are: round sprite positions manually in a `PixelSnap` helper, round the camera target before use, and set `Engine.physics_jitter_fix = 0`. The architecture is unchanged.
