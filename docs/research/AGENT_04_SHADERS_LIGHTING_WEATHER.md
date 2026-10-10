# AGENT 04: Shaders, Lighting and Weather

Target: Godot 4.7.2, GL Compatibility, 2D, 640x360 base resolution, pixel-perfect.
Scope: Fresnel lighthouse beam, rain + splashes, sea mist over cliffs, ocean waves + reflections, day/night grading (CanvasModulate + LUT), 2D lights, performance budget.

All shader code below is written for `shader_type canvas_item`, uses only features available in the Compatibility renderer (no compute, no SDFGI/glow dependence, no 3D hints), and is pixel-snapped: every pattern is evaluated on `floor(UV * rect_size)`, so a single logical pixel always has one value, and motion advances in whole-pixel steps.

---

## 0. Ground rules (read first)

### 0.1 Project settings that make these shaders correct

The shaders assume that one fragment == one logical pixel. That is only true when the viewport renders at 640x360 and is upscaled afterwards.

```ini
; project.godot (excerpt)
[display]
window/size/viewport_width=640
window/size/viewport_height=360
window/stretch/mode="viewport"          ; NOT "canvas_items": shaders must run at 640x360
window/stretch/scale_mode="integer"     ; 2x/3x/4x only, letterbox the rest

[rendering]
renderer/rendering_method="gl_compatibility"
textures/canvas_textures/default_texture_filter=0   ; Nearest
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true
environment/defaults/default_clear_color=Color(0.04, 0.05, 0.1, 1)

[shader_globals]
g_ambient={
"type": "color",
"value": Color(1, 1, 1, 1)
}
g_time_of_day={
"type": "float",
"value": 0.35
}
g_night={
"type": "float",
"value": 0.0
}
```

Rules every effect node obeys:

1. Effect `ColorRect`s sit at integer positions and have integer sizes (`position = position.floor()`).
2. `rect_size` is passed in as a uniform (the driver copies `size`). Never derive pixel size from `SCREEN_PIXEL_SIZE` for patterns, because a rect is not always the full screen.
3. Motion in a shader uses `floor(TIME * px_per_second)`, never a raw float offset. This is what removes sub-pixel shimmer.
4. Continuous brightness is converted to a few levels with a 4x4 Bayer threshold (`floor(v * levels + bayer) / levels`). Looks like hand-dithered pixel art, never like a smooth gradient.
5. `TIME` rolls over every 3600 s by default (`rendering/limits/time/time_rollover_secs`). Raise it to 86400 if hash-based patterns visibly "jump" once an hour.
6. `global uniform` values (`g_ambient`, `g_night`, `g_time_of_day`) are set from one place (the DayNight autoload, section 3) with `RenderingServer.global_shader_parameter_set`. Global shader parameters work in Compatibility.

### 0.2 Folder layout

```
res://shaders/common/pixel_common.gdshaderinc
res://shaders/lighthouse/fresnel_beam.gdshader
res://shaders/weather/rain_overlay.gdshader
res://shaders/weather/sea_mist.gdshader
res://shaders/ocean/ocean_waves.gdshader
res://shaders/ocean/ocean_glints.gdshader
res://shaders/grading/lut_grade.gdshader
res://scripts/fx/fresnel_beam.gd
res://scripts/fx/weather_director.gd
res://scripts/fx/day_night.gd            (autoload "DayNight")
res://scripts/fx/lut_grader.gd
res://scripts/fx/lamp_rig.gd
res://tools/bake_luts.gd                 (EditorScript)
```

### 0.3 Shared include

`#include` of `.gdshaderinc` files is supported in Godot 4 and costs nothing at runtime.

```glsl
// res://shaders/common/pixel_common.gdshaderinc
// No shader_type here. Included after shader_type in each shader.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 4x4 ordered-dither threshold in (0,1). p must be integer-valued pixel coords.
const float BAYER4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	return (BAYER4[x + y * 4] + 0.5) / 16.0;
}

// Quantise 0..1 value to `levels` steps with ordered dither.
float dither_q(float v, float levels, vec2 p) {
	return floor(clamp(v, 0.0, 1.0) * levels + bayer4(p)) / levels;
}

float vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 x) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(x);
		x = x * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}
```

---

## 1. Fresnel beam (`fresnel_beam.gdshader`)

### 1.1 Visual design

A real Fresnel lens throws a hard-cored beam with fine radial striations and a coloured fringe at the edges. We reproduce:

- Twin opposed beams (a 2-panel lens), or a single beam via `twin_beams`.
- Beam cross-section = gaussian core + soft shoulder + thin chromatic rim. Width grows with distance (the beam is not a perfect cylinder).
- Custom falloff: a `CurveTexture` (artist-drawn) multiplied by `pow(1 - t, falloff_power)`, plus a soft fade-in so the beam does not start with a hard edge at the lamp.
- Lens distortion: a barrel "bulge" that squeezes the beam near the lens and a slow heat-ripple that makes the edges breathe.
- Striations (hash streaks across the beam that change every 40 px along it).
- Dust motes: three drifting layers on pixel grids, visible only inside the beam, twinkling on/off. They move in whole pixels.
- Lamp bullseye: radial glow with stepped rings and a 1-px cross flare.
- Everything is quantised to `levels` brightness steps with Bayer dither, and rendered additively.

Beam angle is supplied by the driver (smooth sweep, section 1.3). Origin must be on a pixel centre (`x.5, y.5`); the driver guarantees this.

### 1.2 The shader

```glsl
// res://shaders/lighthouse/fresnel_beam.gdshader
shader_type canvas_item;
render_mode unshaded, blend_add;

#include "res://shaders/common/pixel_common.gdshaderinc"

group_uniforms geometry;
uniform vec2 rect_size = vec2(640.0, 360.0);
uniform vec2 origin_px = vec2(320.5, 120.5);   // rect-local, pixel centre
uniform float beam_angle = 0.0;                // radians, 0 = +x, clockwise on screen
uniform bool twin_beams = true;
uniform float beam_length : hint_range(16.0, 1200.0) = 420.0;
uniform float half_width_near : hint_range(0.5, 40.0) = 3.0;
uniform float half_width_far : hint_range(1.0, 200.0) = 30.0;

group_uniforms falloff;
uniform sampler2D falloff_curve : repeat_disable, filter_linear, hint_default_white;
uniform float falloff_power : hint_range(0.0, 6.0) = 1.4;
uniform float start_fade : hint_range(0.0, 120.0) = 14.0;

group_uniforms lens;
uniform float lens_radius : hint_range(0.0, 120.0) = 36.0;
uniform float ripple_amp : hint_range(0.0, 12.0) = 2.5;
uniform float ripple_freq : hint_range(0.0, 0.5) = 0.06;
uniform float ripple_speed : hint_range(0.0, 6.0) = 1.2;
uniform float streak_px : hint_range(1.0, 12.0) = 3.0;
uniform float fringe : hint_range(0.0, 1.0) = 0.35;

group_uniforms look;
uniform vec4 core_color : source_color = vec4(1.0, 0.94, 0.72, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform vec4 fringe_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;     // driver: night factor
uniform float mist_boost : hint_range(0.0, 2.0) = 0.0;    // driver: weather fog amount
uniform float levels : hint_range(2.0, 12.0, 1.0) = 6.0;
uniform float glow_radius : hint_range(2.0, 80.0) = 18.0;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.9;
uniform float spike_len : hint_range(1.0, 40.0) = 14.0;

group_uniforms motes;
uniform vec4 mote_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
uniform vec2 mote_drift = vec2(3.0, -2.0);     // px per second, layer 0
uniform float mote_density : hint_range(0.0, 1.0) = 0.22;
uniform float mote_gain : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

float motes(vec2 p, float lit) {
	float acc = 0.0;
	for (int L = 0; L < 3; L++) {
		float fl = float(L);
		float cs = 6.0 + fl * 4.0;                                  // cell size grows with layer
		vec2 drift = floor(TIME * mote_drift * (1.0 - fl * 0.28));  // whole pixels only
		vec2 q = (p - 0.5) + drift;                                 // integer-valued
		vec2 cell = floor(q / cs);
		vec2 f = q - cell * cs;
		vec2 h = vec2(hash12(cell + fl * 17.0), hash12(cell + fl * 17.0 + 9.7));
		vec2 mp = floor(h * cs);
		if (f.x == mp.x && f.y == mp.y) {
			float present = step(hash12(cell + 3.3 + fl), mote_density);
			float tw = 0.5 + 0.5 * sin(TIME * (1.5 + h.x * 2.5) + h.y * TAU);
			acc += present * step(0.35, tw) * (0.6 + 0.4 * tw);
		}
	}
	return clamp(acc, 0.0, 1.0) * smoothstep(0.04, 0.35, lit) * mote_gain;
}

void fragment() {
	vec2 p = floor(UV * rect_size) + 0.5;
	vec2 d = p - origin_px;
	float r = length(d);

	// Angular offset from the nearest beam axis.
	float da = atan(d.y, d.x) - beam_angle;
	if (twin_beams) {
		da = atan(sin(2.0 * da), cos(2.0 * da)) * 0.5;   // folds to +-90 degrees
	} else {
		da = atan(sin(da), cos(da));
	}
	float along = r * cos(da);
	float lateral = r * sin(da);
	float t = clamp(along / beam_length, 0.0, 1.0);
	float in_front = step(0.0, along) * step(along, beam_length);

	// Lens distortion: barrel squeeze near the lamp + slow edge ripple.
	float bulge = smoothstep(0.0, lens_radius, along);
	lateral *= mix(0.55, 1.0, bulge);
	lateral += sin(along * ripple_freq - TIME * ripple_speed) * ripple_amp * t;

	// Cross-section.
	float hw = mix(half_width_near, half_width_far, pow(t, 0.8));
	float x = abs(lateral) / hw;
	float core = exp(-x * x * 3.2);
	float shoulder = 0.35 * exp(-x * 1.7);
	float rd = (x - 1.0) * 4.0;
	float rim = fringe * exp(-rd * rd);

	// Fresnel striations.
	float streak = 0.78 + 0.22 * hash12(vec2(floor(lateral / streak_px), floor(along / 40.0)));

	// Falloff.
	float curve = texture(falloff_curve, vec2(t, 0.5)).r;
	float fall = curve * pow(1.0 - t, falloff_power) * smoothstep(0.0, start_fade, along);

	float v = ((core + shoulder) * streak + rim) * fall;
	v *= intensity * (1.0 + mist_boost) * in_front;

	// Lamp bullseye + cross flare (origin is a pixel centre, so |d| < 0.6 is a 1-px line).
	float glow = exp(-r / glow_radius) * glow_strength;
	float rings = 0.85 + 0.15 * step(0.5, fract(r / 3.0 - TIME * 0.6));
	float sx = exp(-abs(d.x) / spike_len) * step(abs(d.y), 0.6);
	float sy = exp(-abs(d.y) / spike_len) * step(abs(d.x), 0.6);
	v += (glow * rings + max(sx, sy) * 0.8) * intensity;

	float lvl = dither_q(v, levels, p);

	vec3 col = mix(edge_color.rgb, core_color.rgb, smoothstep(0.2, 0.9, lvl));
	col = mix(col, fringe_color.rgb, clamp(rim * fall * 2.0, 0.0, 1.0) * 0.6);
	vec3 outc = col * lvl;

	outc += mote_color.rgb * motes(p, lvl) * intensity;

	COLOR = vec4(outc, 1.0);
}
```

Notes:

- `blend_add` with alpha 1.0 adds `rgb` straight onto the framebuffer. Black pixels add nothing, so the rect can be big.
- `PI`/`TAU` are built-in constants in Godot 4 shaders; do not redefine them.
- If the beam must look like it passes through fog, the weather director raises `mist_boost`; the rim and core widen visually because `v` crosses more dither thresholds.
- Beam is in 2D screen plane. For a lighthouse seen from the side, the cleaner cozy cheat is to keep the beam as a long thin shaft (small angle range) and let the driver "foreshorten" it: lerp `half_width_far` and `beam_length` by `abs(cos(phase))` (driver does this with `foreshorten`).

### 1.3 GDScript driver

```gdscript
# res://scripts/fx/fresnel_beam.gd
class_name FresnelBeam
extends ColorRect
## Drives fresnel_beam.gdshader. Put this on a ColorRect that covers the sky/sea area
## (typically the whole 640x360 screen), material = ShaderMaterial(fresnel_beam.gdshader).

signal bearing_crossed(bearing_name: StringName)

@export var lamp_position := Vector2(320, 120)          ## rect-local px
@export var rotation_period := 18.0                     ## seconds per revolution
@export_range(0.0, 0.5) var clockwork_wobble := 0.10    ## speed varies slightly per revolution
@export var accel := 2.5                                ## higher = snappier speed change
@export var sweeping := true : set = set_sweeping
@export var foreshorten := 0.35                         ## 0 = flat 2D beam, 1 = shrinks when pointing at viewer
@export var base_length := 420.0
@export var base_far_width := 30.0
@export var spot_light: PointLight2D                    ## optional cone light that follows the beam
@export var bearings := {}                              ## { &"harbour": 1.2, &"reef": 4.0 } radians

var angle := 0.0
var _speed := 0.0
var _mat: ShaderMaterial
var _visibility := 1.0                                  ## 0..1, set by night factor

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = position.floor()
	_mat = material as ShaderMaterial
	assert(_mat != null, "FresnelBeam needs a ShaderMaterial")
	resized.connect(_push_static)
	_push_static()
	if spot_light and spot_light.texture == null:
		spot_light.texture = make_cone_texture(256, 0.20, true)

func set_sweeping(v: bool) -> void:
	sweeping = v                                        # speed eases to/from zero, no snap

func _push_static() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("origin_px", lamp_position.floor() + Vector2(0.5, 0.5))

func _process(delta: float) -> void:
	var prev := angle
	var base := TAU / maxf(rotation_period, 0.1)
	var target := 0.0
	if sweeping:
		target = base * (1.0 + clockwork_wobble * sin(angle * 2.0 + 0.7))
	_speed = lerpf(_speed, target, 1.0 - exp(-accel * delta))
	angle = wrapf(angle + _speed * delta, -PI, PI)

	# Foreshortening: when the axis points along the view direction the beam is short and wide.
	var facing := absf(cos(angle))                      # 1 = across screen, 0 = into/out of it
	var k := lerpf(1.0 - foreshorten, 1.0, facing)
	_mat.set_shader_parameter("beam_angle", angle)
	_mat.set_shader_parameter("beam_length", base_length * k)
	_mat.set_shader_parameter("half_width_far", base_far_width * lerpf(1.0, 1.6, 1.0 - facing) * foreshorten + base_far_width * (1.0 - foreshorten))
	_mat.set_shader_parameter("intensity", _visibility)

	if spot_light:
		spot_light.rotation = angle
		spot_light.energy = 0.9 * _visibility

	for key in bearings:
		var b: float = bearings[key]
		var a0 := wrapf(prev - b, -PI, PI)
		var a1 := wrapf(angle - b, -PI, PI)
		if a0 < 0.0 and a1 >= 0.0 and absf(a1 - a0) < PI:
			bearing_crossed.emit(key)

## Called by DayNight / WeatherDirector.
func set_visibility(night_factor: float, fog_amount: float) -> void:
	_visibility = clampf(night_factor, 0.0, 1.0) * 0.9 + 0.1   # faint ghost beam in daytime
	_mat.set_shader_parameter("mist_boost", fog_amount * 0.8)

## Procedural cone for the PointLight2D (points along +x, optionally twin-lobed). 5 stepped levels
## so the real light on the island also looks banded rather than smooth.
static func make_cone_texture(size := 256, half_angle := 0.20, twin := true) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var r := d.length() / (size * 0.5)
			var da := absf(angle_difference(0.0, d.angle()))
			if twin:
				da = minf(da, PI - da)
			var v := exp(-pow(da / half_angle, 2.0)) * clampf(1.0 - r, 0.0, 1.0)
			v = floorf(v * 5.0 + 0.5) / 5.0
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)
```

Scene setup:

```
World (Node2D)
 ├─ Sky, Sea, Island, Lighthouse (sprites, y-sorted)
 └─ BeamLayer (CanvasLayer, layer = 5, follow_viewport_enabled = false)
     └─ Beam (ColorRect, anchors off, position (0,0), size (640,360), script = fresnel_beam.gd,
              material = ShaderMaterial(fresnel_beam.gdshader),
              falloff_curve = CurveTexture (resource: start 1.0, shoulder 0.8, end 0.0))
 Lighthouse
 └─ BeamCone (PointLight2D, texture_scale 2.0, energy 0.9, color #ffe9b0,
              blend_mode = Add, shadow_enabled = false)   ← assigned to Beam.spot_light
```

If the camera scrolls, parent the ColorRect to a `CanvasLayer` and have the driver convert `lamp_position` from world to screen each frame (`get_viewport().get_canvas_transform() * lamp_world`, then `.floor()`); do it in `_process` and call `_push_static()`.

---

## 2. Weather and ocean shaders

Common conventions: effect rects are children of a `CanvasLayer`, size 640x360 at (0,0). `camera_px` is the integer camera top-left in world px, set by the `WeatherDirector` each frame, so world-anchored patterns (mist, waves, splashes) do not swim when the camera moves. Overlays on separate `CanvasLayer`s are not touched by the world's `CanvasModulate`, so they multiply by `g_ambient` themselves.

### 2.1 Rain with surface splashes (`rain_overlay.gdshader`)

Technique: three depth layers of 1-px slanted streaks. For a streak, the invariant along its path is `u = x - floor(y * slant)`, so each hash column `u` carries drops that fall in perfect pixel staircases. Time is shifted by `floor(TIME * speed)` so streaks step one row at a time. Splashes live on an 16x8 world grid (ellipse ratio 2:1 for a top-down tilt), 4 hand-written frames: dot, small ring, wide broken ring + droplets, fading broken ring. They only spawn where the optional mask says "surface" (water, rocks, wet boards) or inside a Y band.

```glsl
// res://shaders/weather/rain_overlay.gdshader
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/common/pixel_common.gdshaderinc"

global uniform vec4 g_ambient;

uniform vec2 rect_size = vec2(640.0, 360.0);
uniform vec2 camera_px = vec2(0.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.6;
uniform float slant : hint_range(-1.0, 1.0) = 0.25;        // px of x per px of y
uniform vec4 rain_color : source_color = vec4(0.66, 0.78, 0.92, 1.0);

group_uniforms splashes;
uniform float splash_density : hint_range(0.0, 1.0) = 0.7;
uniform bool use_splash_mask = false;
uniform sampler2D splash_mask : filter_nearest, repeat_disable, hint_default_white;
uniform vec4 mask_rect = vec4(0.0, 0.0, 640.0, 360.0);      // world rect the mask covers (x,y,w,h)
uniform vec2 splash_band = vec2(250.0, 350.0);              // fallback: world-y range
group_uniforms;

// Returns 0 or (local+1)/len, where larger = nearer the head of the streak.
float rain_layer(vec2 p, float len, float speed, float cell_h, float prob, float seed) {
	float u = p.x - floor(p.y * slant);
	float t = p.y - floor(TIME * speed + seed * 97.0);
	float cell = floor(t / cell_h);
	float local = t - cell * cell_h;
	if (local >= len) {
		return 0.0;
	}
	if (hash12(vec2(u, cell + seed * 131.0)) > prob) {
		return 0.0;
	}
	return (local + 1.0) / len;
}

float shade(float b) {
	return b > 0.0 ? mix(0.55, 1.0, step(0.8, b)) : 0.0;     // bright head, dimmer tail
}

float splash(vec2 pw) {
	const vec2 CS = vec2(16.0, 8.0);
	vec2 cell = floor(pw / CS);
	vec2 f = pw - cell * CS;
	float h0 = hash12(cell);
	float h1 = hash12(cell + 11.3);
	float h2 = hash12(cell + 27.9);
	float h3 = hash12(cell + 41.7);
	if (h2 > intensity * splash_density) {
		return 0.0;
	}
	vec2 cc = (cell + 0.5) * CS;
	float ok;
	if (use_splash_mask) {
		ok = texture(splash_mask, (cc - mask_rect.xy) / mask_rect.zw).r;
	} else {
		ok = step(splash_band.x, cc.y) * step(cc.y, splash_band.y);
	}
	if (ok < 0.5) {
		return 0.0;
	}
	float period = mix(0.9, 2.4, h1);
	float ph = fract(TIME / period + h0);
	const float LIFE = 0.28;
	if (ph > LIFE) {
		return 0.0;
	}
	float fr = floor(ph / LIFE * 4.0);                          // 0..3
	vec2 ctr = vec2(6.0 + floor(h3 * 4.0), 3.0 + floor(fract(h3 * 7.0) * 3.0));
	vec2 dd = f - ctr;
	float e = length(vec2(dd.x, dd.y * 2.0));                   // 2:1 ellipse
	float a = 0.0;
	if (fr < 0.5) {
		a = step(abs(dd.x) + abs(dd.y), 0.1);
	} else {
		float ring = step(abs(e - fr * 1.5), 0.75);
		float gap = fr > 1.5 ? step(0.35, hash12(pw + fr)) : 1.0;
		a = ring * gap * (1.0 - (fr - 1.0) * 0.28);
		if (fr < 2.5 && abs(dd.x) == fr && dd.y == -(fr + 1.0)) {
			a = 1.0;                                            // flung droplets
		}
	}
	return a;
}

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 pw = p + floor(camera_px);
	float I = intensity;

	float far_l  = shade(rain_layer(p, 3.0, 150.0, 44.0, 0.060 * I, 0.0));
	float mid_l  = shade(rain_layer(p, 5.0, 230.0, 38.0, 0.045 * I, 1.0));
	float near_l = shade(rain_layer(p, 9.0, 360.0, 64.0, 0.020 * I, 2.0));
	float spl = splash(pw);

	float a = max(max(far_l * 0.30, mid_l * 0.50), max(near_l * 0.80, spl * 0.90));
	vec3 col = mix(rain_color.rgb, vec3(1.0), step(0.85, max(near_l, spl)) * 0.5);
	col *= max(g_ambient.rgb, vec3(0.35));                      // never fully black at night
	COLOR = vec4(col, a * smoothstep(0.0, 0.05, I));
}
```

Usage: `WeatherDirector.rain` drives `intensity`. For splashes on the sea use a `splash_band` that covers the water Y range; for rocks/boardwalk, bake a 1-bit mask (white = splashable) at 1 px = 1 world px (or 1/2 scale; `filter_nearest`) and set `mask_rect` to the world rectangle it covers.

### 2.2 Sea mist rolling over cliffs (`sea_mist.gdshader`)

Technique: two fbm layers scrolling in whole pixels (wind) stretched horizontally, shaped by a vertical profile (dense at the sea, thinning upward with a noisy top), then dithered to 5 alpha levels. An optional cliff mask (alpha = rock) makes the mist thinner over rock and denser just below cliff edges ("spill"), which gives the look of fog pouring over the lip.

```glsl
// res://shaders/weather/sea_mist.gdshader
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/common/pixel_common.gdshaderinc"

global uniform vec4 g_ambient;

uniform vec2 rect_size = vec2(640.0, 360.0);
uniform vec2 camera_px = vec2(0.0);
uniform float parallax : hint_range(0.0, 1.5) = 1.0;
uniform vec2 wind = vec2(9.0, -0.8);                       // px per second
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float base_y = 300.0;                              // world y of the fog floor
uniform float thickness : hint_range(8.0, 400.0) = 140.0;
uniform float noise_scale : hint_range(8.0, 160.0) = 48.0;
uniform float levels : hint_range(2.0, 8.0, 1.0) = 5.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.8;
uniform vec4 mist_light : source_color = vec4(0.86, 0.90, 0.94, 1.0);
uniform vec4 mist_shadow : source_color = vec4(0.52, 0.60, 0.72, 1.0);

group_uniforms cliffs;
uniform bool use_cliff_mask = false;
uniform sampler2D cliff_mask : filter_nearest, repeat_disable, hint_default_black;
uniform vec4 mask_rect = vec4(0.0, 0.0, 640.0, 360.0);
uniform float rock_fog_mult : hint_range(0.0, 1.0) = 0.55;
uniform float spill_px : hint_range(2.0, 40.0) = 14.0;
uniform float spill_amount : hint_range(0.0, 1.0) = 0.6;
group_uniforms;

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 pw = p + floor(camera_px * parallax);
	vec2 sc = floor(wind * TIME);

	vec2 q1 = (pw - sc) / noise_scale;
	q1.x *= 0.5;                                            // long horizontal banks
	vec2 q2 = (pw + floor(wind * TIME * 0.6)) / (noise_scale * 0.6) + 31.0;
	q2.x *= 0.6;
	float n = fbm(q1) * 0.65 + fbm(q2) * 0.35;

	// Vertical profile: full density below base_y, noisy ceiling above.
	float rise = (base_y - pw.y) / (thickness * (0.5 + n));
	float prof = pw.y >= base_y ? 1.0 : 1.0 - smoothstep(0.0, 1.0, rise);

	float shape = smoothstep(0.35, 0.75, n + (density - 0.5) * 0.6);
	float d = shape * prof;

	if (use_cliff_mask) {
		vec2 muv = (pw - mask_rect.xy) / mask_rect.zw;
		float rock = texture(cliff_mask, muv).a;
		float above = texture(cliff_mask, muv - vec2(0.0, spill_px / mask_rect.w)).a;
		d += above * (1.0 - rock) * spill_amount * (0.5 + n);
		d *= mix(1.0, rock_fog_mult, rock);
	}

	float lvl = dither_q(d * density * 1.6, levels, p);
	vec3 col = mix(mist_shadow.rgb, mist_light.rgb, smoothstep(0.3, 0.9, n));
	col *= max(g_ambient.rgb, vec3(0.30));
	COLOR = vec4(col, lvl * max_alpha);
}
```

Usage notes:

- Put one instance **in front of the island but behind the beam** (z order) for the "mist over cliffs" band. A second instance with `parallax = 0.6`, lower `max_alpha`, higher `base_y` behind the cliffs gives depth.
- The cliff mask is a single-channel-alpha texture the artist exports from the cliff layer (`Image.fill`-style silhouette, nearest filtered). It does not need to be pixel-exact; it only biases density.
- Cost: 8 `vnoise` per pixel (2 fbm x 4 octaves) = 32 hashes; trivially cheap at 640x360 (230k px). If a low-end device struggles, drop to 3 octaves in the include (`for (int i=0;i<3...`).

### 2.3 Ocean waves with perspective crests (`ocean_waves.gdshader`)

Technique: a perspective wave coordinate `w = pow(dy, persp_exp) * wave_density - TIME * wave_speed` where `dy` is rows below the horizon. Crests are the rows where `fract(w) < dw/dy * 1px`, i.e. exactly one pixel thick regardless of distance; beyond the point where that exceeds ~0.45 the crest fades into horizon haze. Crests are broken into dashes (`seg`), a darker trough row sits right under each crest, and a base colour ramp is dithered into `steps` bands. The node is lit by 2D lights and tinted by `CanvasModulate` (no `unshaded`), so lamp light spills on the water.

```glsl
// res://shaders/ocean/ocean_waves.gdshader
shader_type canvas_item;

#include "res://shaders/common/pixel_common.gdshaderinc"

uniform vec2 rect_size = vec2(640.0, 360.0);
uniform vec2 camera_px = vec2(0.0);
uniform float horizon_y = 0.0;                    // rect-local row of the horizon (may be < 0)

group_uniforms palette;
uniform vec4 horizon_color : source_color = vec4(0.62, 0.74, 0.82, 1.0);
uniform vec4 mid_color : source_color = vec4(0.22, 0.43, 0.56, 1.0);
uniform vec4 deep_color : source_color = vec4(0.09, 0.20, 0.33, 1.0);
uniform vec4 crest_color : source_color = vec4(0.80, 0.92, 0.95, 1.0);
uniform vec4 trough_color : source_color = vec4(0.06, 0.14, 0.25, 1.0);
uniform float steps : hint_range(2.0, 8.0, 1.0) = 5.0;

group_uniforms waves;
uniform float wave_density : hint_range(0.05, 1.0) = 0.30;
uniform float persp_exp : hint_range(0.3, 1.0) = 0.65;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.22;
uniform float wobble : hint_range(0.0, 1.0) = 0.35;
uniform float crest_px : hint_range(1.0, 3.0, 1.0) = 1.0;
uniform float sparkle : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

vec3 ramp(float u) {
	vec3 c = mix(horizon_color.rgb, mid_color.rgb, smoothstep(0.0, 0.35, u));
	return mix(c, deep_color.rgb, smoothstep(0.30, 1.0, u));
}

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 pw = p + floor(camera_px);
	float dy = max(p.y - horizon_y, 0.0) + 1.0;
	float depth = clamp((p.y - horizon_y) / max(rect_size.y - horizon_y, 1.0), 0.0, 1.0);

	float w = pow(dy, persp_exp) * wave_density - TIME * wave_speed;
	w += sin(pw.x * 0.035 + TIME * 0.4 + dy * 0.05) * wobble;
	float dwdy = persp_exp * pow(dy, persp_exp - 1.0) * wave_density;
	float thick = dwdy * crest_px;
	float f = fract(w);

	float seg_len = mix(6.0, 22.0, depth);
	float seg = step(0.35, hash12(vec2(floor(pw.x / seg_len), floor(w))));
	float vis = step(thick, 0.45);
	float crest = step(f, thick) * seg * vis;
	float shade_row = step(thick, f) * step(f, thick * 2.0) * seg * vis;

	// Swell mottling makes the bands un-uniform before quantising.
	float n = vnoise(vec2(pw.x / 40.0, floor(w) * 1.7 + TIME * 0.05));
	float u = dither_q(depth + (n - 0.5) * 0.14, steps, p);

	vec3 col = ramp(u);
	col = mix(col, trough_color.rgb, shade_row * 0.55);
	col = mix(col, crest_color.rgb, crest * (0.55 + 0.45 * (1.0 - depth)));

	float sp = step(0.9985, hash12(pw + floor(TIME * 2.0) * 7.0)) * (1.0 - depth * 0.5) * sparkle;
	col = mix(col, crest_color.rgb, sp);

	COLOR = vec4(col, 1.0);
}
```

### 2.4 Reflections: glints + emissive mirror (`ocean_glints.gdshader`)

Separate additive, unshaded pass so reflections stay bright at night (the base water is darkened by `CanvasModulate`). Two systems:

1. **Analytic glints** (moon, lamp, windows): up to four sources `vec4(x, y_waterline, half_width, intensity)`. Under each source a column widens with distance, each pixel row is jittered sideways by a hash that changes `shimmer_rate` times per second, and a hash gate cuts it into dashes: the classic pixel-art moon path.
2. **Optional screen mirror** (`hint_screen_texture`): samples the screen above `reflect_line_y` flipped about that line, wobbled per row, keeps only pixels brighter than `emissive_threshold` (lamp, windows, moon, bright sky). One backbuffer copy per frame in Compatibility; leave off unless you need it.

```glsl
// res://shaders/ocean/ocean_glints.gdshader
shader_type canvas_item;
render_mode unshaded, blend_add;

#include "res://shaders/common/pixel_common.gdshaderinc"

uniform vec2 rect_size = vec2(640.0, 360.0);
uniform float horizon_y = 0.0;
uniform vec4 glints[4];                 // x, y (waterline below source, rect-local), half_width, intensity
uniform vec4 glint_colors[4];           // rgb used
uniform float wave_jitter : hint_range(0.0, 16.0) = 5.0;
uniform float shimmer_rate : hint_range(1.0, 12.0) = 5.0;

group_uniforms screen_mirror;
uniform bool use_screen_reflection = false;
uniform float reflect_line_y = 0.0;     // rect-local row to mirror about
uniform float emissive_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.6;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
group_uniforms;

void fragment() {
	vec2 p = floor(UV * rect_size) + 0.5;
	float depth = clamp((p.y - horizon_y) / max(rect_size.y - horizon_y, 1.0), 0.0, 1.0);
	float slot = floor(TIME * shimmer_rate);
	vec3 acc = vec3(0.0);

	for (int i = 0; i < 4; i++) {
		vec4 g = glints[i];
		float below = p.y - g.y;
		if (g.w <= 0.0 || below <= 0.0) {
			continue;
		}
		float jit = (hash12(vec2(p.y, slot + float(i) * 13.0)) - 0.5) * wave_jitter * (1.0 + below * 0.03);
		float dx = p.x - g.x + floor(jit);
		float wd = g.z * (0.7 + below * 0.014);
		float inside = exp(-(dx * dx) / (wd * wd));
		float fade = exp(-below * 0.011);
		float gate = hash12(vec2(p.y * 1.7 + float(i), slot * 0.5 + floor(p.x / 4.0)));
		float on = step(gate, inside * g.w * fade * 1.4);
		acc += glint_colors[i].rgb * on;
	}

	if (use_screen_reflection) {
		float dyl = p.y - reflect_line_y;
		if (dyl > 0.0) {
			float wob = floor(sin(p.y * 0.9 + TIME * 2.3) * (1.0 + depth * 3.0) + 0.5);
			vec2 suv = SCREEN_UV + vec2(wob, -2.0 * dyl) * SCREEN_PIXEL_SIZE;
			if (suv.y > 0.0 && suv.y < 1.0 && suv.x > 0.0 && suv.x < 1.0) {
				vec3 s = texture(screen_tex, suv).rgb;
				float lum = dot(s, vec3(0.299, 0.587, 0.114));
				float em = smoothstep(emissive_threshold, emissive_threshold + 0.2, lum);
				float brk = step(0.25, hash12(vec2(p.y, slot)));
				acc += s * em * reflect_strength * exp(-dyl * 0.008) * brk;
			}
		}
	}
	COLOR = vec4(acc, 1.0);
}
```

Driver for glints (put in `WeatherDirector` or a `SeaDirector`):

```gdscript
func set_glints(sea_rect: ColorRect, sources: Array[Dictionary]) -> void:
	# sources: [{ "pos": Vector2 (rect-local waterline), "width": 3.0, "power": 1.0, "color": Color }]
	var g := PackedVector4Array()
	var c := PackedVector4Array()
	for i in 4:
		if i < sources.size():
			var s: Dictionary = sources[i]
			var p: Vector2 = s["pos"].floor() + Vector2(0.5, 0.5)
			g.append(Vector4(p.x, p.y, s["width"], s["power"]))
			var col: Color = s["color"]
			c.append(Vector4(col.r, col.g, col.b, 1.0))
		else:
			g.append(Vector4.ZERO)
			c.append(Vector4.ZERO)
	var m := sea_rect.material as ShaderMaterial
	m.set_shader_parameter("glints", g)
	m.set_shader_parameter("glint_colors", c)
```

Source mapping: moon (`color #dfe8ff`, width 3, power rises with `DayNight.moon_light`), lamp (`#ffd890`, width 2, power = night factor), lit windows (`#ffb35c`, width 1.5).

### 2.5 Weather director and scene setup

```gdscript
# res://scripts/fx/weather_director.gd
class_name WeatherDirector
extends Node
## Smoothly blends target weather into shader parameters. One node, no per-frame allocation.

@export var rain_rect: ColorRect
@export var mist_rects: Array[ColorRect] = []
@export var sea_rects: Array[ColorRect] = []        # ocean_waves + ocean_glints rects
@export var beam: FresnelBeam
@export var camera: Camera2D

@export_range(0.0, 1.0) var target_rain := 0.0
@export_range(0.0, 1.0) var target_fog := 0.25
@export var target_wind := Vector2(9.0, -0.8)        # px/s, drives mist scroll + rain slant
@export var blend_rate := 0.35                       # per second; weather changes over ~6 s

var rain := 0.0
var fog := 0.0
var wind := Vector2(9.0, -0.8)

func _process(delta: float) -> void:
	var k := 1.0 - exp(-blend_rate * delta)
	rain = lerpf(rain, target_rain, k)
	fog = lerpf(fog, target_fog, k)
	wind = wind.lerp(target_wind, k)

	var cam := Vector2.ZERO
	if camera:
		cam = camera.get_screen_center_position() - Vector2(320, 180)
		cam = cam.floor()                              # integer camera -> no subpixel swimming

	if rain_rect:
		rain_rect.visible = rain > 0.01
		var m := rain_rect.material as ShaderMaterial
		m.set_shader_parameter("intensity", rain)
		m.set_shader_parameter("slant", clampf(wind.x / 36.0, -0.6, 0.6))
		m.set_shader_parameter("camera_px", cam)
	for r in mist_rects:
		var mm := r.material as ShaderMaterial
		mm.set_shader_parameter("density", clampf(fog + rain * 0.25, 0.0, 1.0))
		mm.set_shader_parameter("wind", wind)
		mm.set_shader_parameter("camera_px", cam)
	for r in sea_rects:
		(r.material as ShaderMaterial).set_shader_parameter("camera_px", cam)
	if beam:
		beam.set_visibility(RenderingServer.global_shader_parameter_get("g_night"), maxf(fog, rain * 0.6))
```

Scene tree (layers back to front):

```
Main (Node2D)
 ├─ DayNightModulate (CanvasModulate)                     ← color set by DayNight autoload
 ├─ World (Node2D, y_sort_enabled)
 │   ├─ SkyRect          (ColorRect / Sprite2D sky, unlit)
 │   ├─ SeaWaves         (ColorRect 640x(360-horizon), ShaderMaterial ocean_waves)   z = -20
 │   ├─ SeaGlints        (ColorRect same rect,       ShaderMaterial ocean_glints)    z = -19  (unshaded additive)
 │   ├─ Island, Cliffs, Lighthouse, Cottage, Props
 │   ├─ MistBack         (ColorRect, sea_mist parallax 0.6, max_alpha 0.35)          z = -5
 │   └─ MistFront        (ColorRect, sea_mist parallax 1.0, cliff mask on)           z = +20
 ├─ BeamLayer  (CanvasLayer 5)  → Beam (ColorRect fresnel_beam)
 ├─ RainLayer  (CanvasLayer 8)  → Rain (ColorRect rain_overlay)
 ├─ GradeLayer (CanvasLayer 10) → LutGrade (ColorRect lut_grade)   ← optional, section 3.4
 ├─ UILayer    (CanvasLayer 20)
 └─ WeatherDirector (Node, exports wired to the rects above)
```

Weather presets (suggested, tuned for cozy):

| Preset | rain | fog | wind (px/s) | beam mist_boost |
|---|---|---|---|---|
| Clear | 0.0 | 0.15 | (6, -0.5) | 0.12 |
| Haze | 0.0 | 0.55 | (4, -0.3) | 0.44 |
| Drizzle | 0.3 | 0.40 | (10, -0.8) | 0.32 |
| Rain | 0.65 | 0.35 | (16, -1.0) | 0.28 |
| Storm | 1.0 | 0.25 | (30, -2.0) | 0.20 |
| Fog bank | 0.0 | 1.0 | (3, 0.0) | 0.80 |

---

## 3. Day/night grading

### 3.1 Model: astronomy first, colour second

`time_of_day` is a float in [0,1): 0.0 = midnight, 0.25 = 06:00, 0.5 = noon. The sun's elevation is computed from latitude and the date's declination, so sunrise time shifts with the seasons and twilight is long at high latitude (a northern island: long blue hours, perfect for a lighthouse). Colour grading is looked up by **sun elevation in degrees**, not by clock time:

```
sin(elev) = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(H),   H = (tod - 0.5) * TAU
decl      = 23.44 deg * sin(TAU * (284 + day_of_year) / 365)
```

Moon: hour angle `H_m = H + phase * TAU` (phase 0 = new, 0.5 = full). Moonlight strength = `max(sin(elev_m), 0) * (0.5 - 0.5 cos(phase * TAU))`. This lifts the night floor on full-moon nights so the sea stays readable.

Elevation anchors (degrees) with the ambient `CanvasModulate` colours. Dawn and dusk differ only between -6 and +20 deg; below and above they are identical, so switching sides at midnight/noon never pops.

| Elev | Phase | Dawn colour | Dusk colour |
|---|---|---|---|
| -18 | astronomical night | `#2b3a6b` | `#2b3a6b` |
| -12 | nautical twilight | `#36457a` | `#36457a` |
| -6 | civil twilight (blue hour) | `#6a5a92` | `#7a4f82` |
| +1 | sunrise / sunset | `#f2a079` | `#ee7f62` |
| +8 | golden hour | `#ffd2a0` | `#ffc07a` |
| +20 | morning / afternoon | `#fff0dc` | `#ffe6c4` |
| +40 | day | `#ffffff` | `#ffffff` |

Why not darker night: CanvasModulate multiplies. Anything below roughly `(0.15, 0.20, 0.38)` crushes pixel-art shading (sprite shadows go to black). Keep the floor blue, and let lights carry the drama.

### 3.2 The `DayNight` autoload

Register as autoload `DayNight` (`res://scripts/fx/day_night.gd`).

```gdscript
# res://scripts/fx/day_night.gd
extends Node
## Owns time_of_day. Computes sun/moon, grading colour, and pushes global shader params.

signal tick(time_of_day: float)
signal dusk_started
signal dawn_started

@export var seconds_per_day := 720.0                  # 12 real minutes = one day
@export_range(0.0, 1.0) var time_of_day := 0.32 : set = set_time_of_day
@export var latitude_deg := 54.0
@export_range(1, 365) var day_of_year := 172
@export_range(0.0, 1.0) var moon_phase := 0.5
@export var paused := false
@export var modulate_node: CanvasModulate

var sun_elev_deg := 0.0
var moon_light := 0.0                                 # 0..1
var night_factor := 0.0                               # 0 day .. 1 full night
var ambient := Color.WHITE

var _dawn: Gradient
var _dusk: Gradient
var _was_night := false

const ELEV_MIN := -18.0
const ELEV_MAX := 40.0
const ANCHORS := [-18.0, -12.0, -6.0, 1.0, 8.0, 20.0, 40.0]
const DAWN := ["2b3a6b", "36457a", "6a5a92", "f2a079", "ffd2a0", "fff0dc", "ffffff"]
const DUSK := ["2b3a6b", "36457a", "7a4f82", "ee7f62", "ffc07a", "ffe6c4", "ffffff"]

func _ready() -> void:
	_dawn = _make_gradient(DAWN)
	_dusk = _make_gradient(DUSK)
	_update()

func _make_gradient(hexes: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in hexes.size():
		offs.append(remap(ANCHORS[i], ELEV_MIN, ELEV_MAX, 0.0, 1.0))
		cols.append(Color.html(hexes[i]))
	g.offsets = offs
	g.colors = cols
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	g.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_OKLAB   # perceptually smooth twilight
	return g

func set_time_of_day(v: float) -> void:
	time_of_day = fposmod(v, 1.0)
	if is_inside_tree():
		_update()

func _process(delta: float) -> void:
	if paused:
		return
	set_time_of_day(time_of_day + delta / seconds_per_day)

## Hours helper for UI / gameplay: 0..24.
func hour() -> float:
	return time_of_day * 24.0

func _sin_elev(tod: float, extra_phase := 0.0) -> float:
	var lat := deg_to_rad(latitude_deg)
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + day_of_year) / 365.0)
	var h := (tod - 0.5) * TAU + extra_phase * TAU
	return sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(h)

func _update() -> void:
	var s := _sin_elev(time_of_day)
	sun_elev_deg = rad_to_deg(asin(clampf(s, -1.0, 1.0)))
	var m := _sin_elev(time_of_day, moon_phase)
	var illum := 0.5 - 0.5 * cos(moon_phase * TAU)
	moon_light = maxf(m, 0.0) * illum

	var t := remap(clampf(sun_elev_deg, ELEV_MIN, ELEV_MAX), ELEV_MIN, ELEV_MAX, 0.0, 1.0)
	var morning := time_of_day < 0.5
	var c: Color = (_dawn if morning else _dusk).sample(t)

	# Moonlit nights: lift the floor slightly toward silver-blue.
	var night_k := 1.0 - smoothstep(-8.0, 2.0, sun_elev_deg)
	c = c.lerp(c + Color(0.05, 0.07, 0.10, 0.0), moon_light * night_k)
	c.a = 1.0

	night_factor = night_k
	ambient = c
	if modulate_node:
		modulate_node.color = c
	RenderingServer.global_shader_parameter_set("g_ambient", c)
	RenderingServer.global_shader_parameter_set("g_time_of_day", time_of_day)
	RenderingServer.global_shader_parameter_set("g_night", night_factor)

	var is_night := night_factor > 0.5
	if is_night and not _was_night:
		dusk_started.emit()
	elif not is_night and _was_night:
		dawn_started.emit()
	_was_night = is_night
	tick.emit(time_of_day)
```

Usage: set `DayNight.modulate_node` to the scene's `CanvasModulate` (the world canvas). Overlay `CanvasLayer`s read `g_ambient` themselves (rain, mist shaders already do).

Test that `CanvasModulate` behaves as expected with `unshaded` nodes in your 4.7.2 build: drop a sprite with `CanvasItemMaterial.light_mode = LIGHT_MODE_UNSHADED` in a scene at night. If it is tinted, move emissive things (windows glow, glints, beam) to a separate `CanvasLayer` that has no `CanvasModulate`. The shaders above are written so either outcome works.

### 3.3 Why CanvasModulate gradients first, LUT second

- CanvasModulate is one multiply, free, and works on lit sprites, the island, TileMaps, everything in the world canvas.
- It can only darken/tint. It cannot desaturate, add warm highlights while keeping cool shadows (split toning), or lift blacks. Dusk with magenta in the sky, teal in the shadows requires a LUT.
- Ship CanvasModulate for gameplay readability, then the LUT pass on top for mood. If the LUT is disabled (low settings), the game still looks right.

### 3.4 LUT grading shader (`lut_grade.gdshader`)

Format: a **16^3 strip**: `256x16` PNG, 16 slices laid left to right, each slice 16x16. Red varies along x inside a slice, green along y (top = green 1.0 is *not* assumed; the shader uses the baked orientation: y = green, increasing downward = increasing green; the bake script in 3.6 matches), blue chooses the slice. Import settings: Filter = **Linear**, Mipmaps = off, Compress = Lossless, sRGB (in Compatibility the framebuffer is sRGB-encoded, so no conversion is needed).

The shader blends two LUTs (`lut_a`, `lut_b` with `lut_mix`) so the grade slides continuously between keyframes, then adds an optional night desaturation and a 1-step dithered vignette.

```glsl
// res://shaders/grading/lut_grade.gdshader
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/common/pixel_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D lut_a : source_color, filter_linear, repeat_disable, hint_default_white;
uniform sampler2D lut_b : source_color, filter_linear, repeat_disable, hint_default_white;
uniform float lut_mix : hint_range(0.0, 1.0) = 0.0;
uniform float lut_strength : hint_range(0.0, 1.0) = 1.0;
uniform float lut_size = 16.0;
uniform vec2 rect_size = vec2(640.0, 360.0);

uniform float night_desat : hint_range(0.0, 1.0) = 0.0;     // driver: night_factor * 0.25
uniform float vignette : hint_range(0.0, 1.0) = 0.25;
uniform float vignette_levels : hint_range(2.0, 8.0, 1.0) = 4.0;

vec3 lut_lookup(sampler2D lut, vec3 c) {
	float n = lut_size;
	float b = clamp(c.b, 0.0, 1.0) * (n - 1.0);
	float s0 = floor(b);
	float s1 = min(s0 + 1.0, n - 1.0);
	float fb = b - s0;
	// Half-texel inset on r and g so linear filtering never bleeds across slices.
	float rx = clamp(c.r, 0.0, 1.0) * (n - 1.0) + 0.5;
	float gy = (clamp(c.g, 0.0, 1.0) * (n - 1.0) + 0.5) / n;
	vec2 uv0 = vec2((s0 * n + rx) / (n * n), gy);
	vec2 uv1 = vec2((s1 * n + rx) / (n * n), gy);
	return mix(texture(lut, uv0).rgb, texture(lut, uv1).rgb, fb);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec3 graded = mix(lut_lookup(lut_a, src), lut_lookup(lut_b, src), lut_mix);
	vec3 col = mix(src, graded, lut_strength);

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma) * vec3(0.92, 0.98, 1.08), night_desat);

	vec2 p = floor(UV * rect_size);
	vec2 q = (p / rect_size - 0.5) * vec2(1.0, 0.8);
	float v = smoothstep(0.25, 0.75, length(q));
	float vq = dither_q(v, vignette_levels, p);
	col *= 1.0 - vq * vignette;

	COLOR = vec4(col, 1.0);
}
```

Placement: a `ColorRect` 640x360 on a `CanvasLayer` **below** the UI layer so UI text is not graded. `hint_screen_texture` triggers a backbuffer copy; one full-screen pass costs ~1 copy + 230k fragments x 4 texture reads (~0.2 ms on integrated GPUs).

### 3.5 LUT driver (`lut_grader.gd`)

Keyframe LUTs in elevation order, separately for dawn and dusk side. The night, blue-hour, golden and day LUTs are shared; only sunrise/sunset are separate, so there is no pop at midnight.

```gdscript
# res://scripts/fx/lut_grader.gd
class_name LutGrader
extends ColorRect

## Elevation anchors for the LUT keyframes (degrees). Must match LUT order below.
const ANCHORS := [-18.0, -6.0, 1.0, 10.0, 35.0]

@export var dawn_luts: Array[Texture2D] = []    # [night, blue_hour, sunrise, golden, day]
@export var dusk_luts: Array[Texture2D] = []    # [night, blue_hour, sunset,  golden, day]
@export var night_desat_max := 0.22

var _mat: ShaderMaterial

func _ready() -> void:
	_mat = material as ShaderMaterial
	_mat.set_shader_parameter("rect_size", size)
	assert(dawn_luts.size() == ANCHORS.size() and dusk_luts.size() == ANCHORS.size())
	DayNight.tick.connect(_on_tick)
	_on_tick(DayNight.time_of_day)

func _on_tick(tod: float) -> void:
	var e := clampf(DayNight.sun_elev_deg, ANCHORS[0], ANCHORS[-1])
	var set_ := dawn_luts if tod < 0.5 else dusk_luts
	var i := 0
	while i < ANCHORS.size() - 2 and e > ANCHORS[i + 1]:
		i += 1
	var t := inverse_lerp(ANCHORS[i], ANCHORS[i + 1], e)
	t = t * t * (3.0 - 2.0 * t)                        # smoothstep: no visible keyframe corners
	_mat.set_shader_parameter("lut_a", set_[i])
	_mat.set_shader_parameter("lut_b", set_[i + 1])
	_mat.set_shader_parameter("lut_mix", t)
	_mat.set_shader_parameter("night_desat", DayNight.night_factor * night_desat_max)
```

If the project later wants weather-dependent grades (overcast = less saturated), multiply `lut_strength` by a weather uniform or add a third LUT; do not multiply the LUT count (days x weathers).

### 3.6 LUT generation notes

**Option A: bake from code (recommended, reproducible).** Grade parameters (lift/gamma/gain/saturation/split-tone) per keyframe live in a script; PNGs are build artifacts.

```gdscript
# res://tools/bake_luts.gd   (File > Run as EditorScript)
@tool
extends EditorScript

const N := 16

# lift, gamma, gain are Colors (rgb); sat is a float; shadow_tint / highlight_tint are Colors; split is 0..1.
const KEYS := {
	"night":      {"lift": Color(0.00, 0.01, 0.04), "gamma": Color(1.05, 1.0, 0.92), "gain": Color(0.80, 0.90, 1.10), "sat": 0.80, "sh": Color(0.20, 0.30, 0.70), "hi": Color(0.50, 0.65, 1.00), "split": 0.15},
	"blue_hour":  {"lift": Color(0.01, 0.01, 0.04), "gamma": Color(1.02, 1.0, 0.95), "gain": Color(0.95, 0.95, 1.08), "sat": 0.95, "sh": Color(0.25, 0.30, 0.65), "hi": Color(1.00, 0.70, 0.75), "split": 0.25},
	"sunrise":    {"lift": Color(0.02, 0.01, 0.03), "gamma": Color(1.00, 1.0, 1.00), "gain": Color(1.10, 0.98, 0.88), "sat": 1.10, "sh": Color(0.30, 0.35, 0.65), "hi": Color(1.00, 0.72, 0.50), "split": 0.30},
	"sunset":     {"lift": Color(0.02, 0.01, 0.03), "gamma": Color(1.00, 1.0, 1.00), "gain": Color(1.12, 0.94, 0.84), "sat": 1.15, "sh": Color(0.35, 0.30, 0.60), "hi": Color(1.00, 0.62, 0.42), "split": 0.32},
	"golden":     {"lift": Color(0.01, 0.01, 0.02), "gamma": Color(1.00, 1.0, 1.00), "gain": Color(1.06, 1.00, 0.92), "sat": 1.08, "sh": Color(0.35, 0.42, 0.60), "hi": Color(1.00, 0.82, 0.58), "split": 0.20},
	"day":        {"lift": Color(0.00, 0.00, 0.00), "gamma": Color(1.00, 1.0, 1.00), "gain": Color(1.00, 1.00, 1.00), "sat": 1.00, "sh": Color(0.40, 0.50, 0.60), "hi": Color(1.00, 0.95, 0.85), "split": 0.05},
}

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/luts")
	for key in KEYS:
		var img := Image.create_empty(N * N, N, false, Image.FORMAT_RGB8)
		var p: Dictionary = KEYS[key]
		for b in N:
			for g in N:
				for r in N:
					var c := Color(r / float(N - 1), g / float(N - 1), b / float(N - 1))
					img.set_pixel(b * N + r, g, _grade(c, p))
		img.save_png("res://assets/luts/lut_%s.png" % key)
	print("LUTs baked.")
	EditorInterface.get_resource_filesystem().scan()

func _grade(c: Color, p: Dictionary) -> Color:
	var lift: Color = p["lift"]
	var gamma: Color = p["gamma"]
	var gain: Color = p["gain"]
	var v := Vector3(c.r, c.g, c.b)
	v = v * Vector3(gain.r, gain.g, gain.b) + Vector3(lift.r, lift.g, lift.b)
	v = Vector3(maxf(v.x, 0.0), maxf(v.y, 0.0), maxf(v.z, 0.0))
	v = Vector3(pow(v.x, 1.0 / gamma.r), pow(v.y, 1.0 / gamma.g), pow(v.z, 1.0 / gamma.b))
	var l := v.x * 0.299 + v.y * 0.587 + v.z * 0.114
	var sat: float = p["sat"]
	v = Vector3(l, l, l).lerp(v, sat)
	# Split toning: shadows toward `sh`, highlights toward `hi`.
	var sh: Color = p["sh"]
	var hi: Color = p["hi"]
	var split: float = p["split"]
	var w := smoothstep(0.0, 1.0, l)
	var tone := Vector3(sh.r, sh.g, sh.b).lerp(Vector3(hi.r, hi.g, hi.b), w)
	v = v.lerp(v * tone * 1.6, split)
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))
```

Bake checklist:

1. Always bake an **identity** LUT first (all params neutral) and verify the game looks unchanged with `lut_strength = 1`. If the image is shifted or flipped, the orientation convention (red in x, green in y, blue slice) is mismatched.
2. 16^3 is enough because the palette is limited; smooth ramps are not the goal. Use 32^3 (1024x32) only if you see banding on large sky gradients; change `lut_size` and `N` together.
3. LUT PNGs: Filter Linear, no mipmaps, no compression, "Process > Fix Alpha Border" off. Do not let the importer pack them into an atlas.
4. **Do not** grade through a LUT built from screenshots of a different palette: the project's art uses a fixed palette, so test the ramps on the real palette swatches. Keep an `lut_test.png` of the palette to eyeball each keyframe.
5. Artist alternative: apply the target look to an identity strip in Aseprite/Krita/Photoshop with adjustment layers (curves, colour balance, selective colour) and export as PNG. Only use adjustments that are per-pixel colour operations (no blur, no vignette, no layer masks), or the strip is no longer a valid LUT.
6. Hue keeps the cozy rules: warm highlights, cool shadows, lifted blacks (`lift` > 0), no pure black, no pure white at night.

---

## 4. 2D lights: lamp and window glow

### 4.1 Compatibility-renderer facts that shape the setup

- In the Compatibility renderer, each lit canvas item is drawn once per overlapping light (multi-pass). Cost = lit items x overlapping lights. This is why light count and overlap are the budget, not light "size".
- 2D shadows use a per-light shadow map render (extra passes per shadow-casting light). Keep one shadow-casting light (the lamp), maybe two.
- Use `Add` blend mode on all lights. `Sub` and `Mix` work but make cozy glow harder to control.
- Lights are not affected by the `CanvasModulate` multiply (they add on top of it), which is exactly what we want: ambient dark, lights bright.
- Glow/bloom: do not depend on `WorldEnvironment` glow in Compatibility for the core look. Fake bloom with additive sprites (below).

### 4.2 Banded light textures (pixel-art light)

Smooth radial light textures look wrong in pixel art. Stepped textures produce concentric bands that read as hand-painted.

```gdscript
# in res://scripts/fx/lamp_rig.gd (static helper)
static func make_banded_light(size := 256, bands := 5, power := 1.6) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in bands:
		var v := pow(1.0 - float(i) / bands, power)
		offs.append(float(i) / bands)
		cols.append(Color(v, v, v, 1.0))
	offs.append(1.0)
	cols.append(Color(0, 0, 0, 1))
	g.offsets = offs
	g.colors = cols
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
```

Because the texture is generated at 256x256, set `texture_scale` so that on screen 1 texel == 1 logical px only when you want exactness; for lights, any scale is fine, since the bands are the aliasing. Keep `texture_filter = Nearest` (project default).

### 4.3 Lamp rig

```gdscript
# res://scripts/fx/lamp_rig.gd
class_name LampRig
extends Node2D
## Lighthouse lantern: warm key light, flicker in whole steps, additive halo sprite, shadow caster.

@export var key_light: PointLight2D                 # shadow_enabled = true
@export var halo: Sprite2D                          # additive halo, CanvasItemMaterial blend_mode = Add
@export var warm := Color("ffcf86")
@export var flicker_hz := 7.0
@export var flicker_amount := 0.06                  # quantised to 4 steps
@export var base_energy := 1.4

var _acc := 0.0
var _step := 0

func _ready() -> void:
	if key_light.texture == null:
		key_light.texture = make_banded_light(256, 5)
	key_light.color = warm
	key_light.blend_mode = Light2D.BLEND_MODE_ADD
	key_light.shadow_enabled = true
	key_light.shadow_filter = Light2D.SHADOW_FILTER_NONE   # crisp pixel shadows
	DayNight.tick.connect(_on_tick)
	_on_tick(DayNight.time_of_day)

func _process(delta: float) -> void:
	_acc += delta * flicker_hz
	if _acc >= 1.0:
		_acc = fmod(_acc, 1.0)
		_step = randi_range(0, 3)                      # 4 discrete flicker states = no smooth wobble
	var night := DayNight.night_factor
	var e := base_energy * night * (1.0 - flicker_amount * (_step / 3.0))
	key_light.energy = e
	if halo:
		halo.modulate.a = clampf(night * 1.1, 0.0, 1.0) * (1.0 - flicker_amount * (_step / 3.0))

func _on_tick(_t: float) -> void:
	key_light.visible = DayNight.night_factor > 0.02   # cull the light entirely by day
	if halo:
		halo.visible = key_light.visible

static func make_banded_light(size := 256, bands := 5, power := 1.6) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in bands:
		var v := pow(1.0 - float(i) / bands, power)
		offs.append(float(i) / bands)
		cols.append(Color(v, v, v, 1.0))
	offs.append(1.0)
	cols.append(Color(0, 0, 0, 1))
	g.offsets = offs
	g.colors = cols
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
```

Node setup for the lantern room (tower top):

```
Lantern (Node2D, script = lamp_rig.gd)
 ├─ KeyLight (PointLight2D)
 │    texture = (generated), texture_scale = 1.6 (≈ 200 px radius), energy 1.4,
 │    color #ffcf86, blend_mode Add, range_z_min/max = -1024..1024,
 │    range_item_cull_mask = layers 1 (world) only,
 │    shadow_enabled = true, shadow_filter = None, shadow_item_cull_mask = 2 (occluder layer)
 ├─ Halo (Sprite2D)
 │    texture = 48x48 hand-painted additive halo (4 bands), material = CanvasItemMaterial(blend Add, light_mode Unshaded)
 └─ Occluder (LightOccluder2D)  (on the tower mass, NOT on the lantern glass)
```

Shadow tips: tower silhouette is the only occluder; cliffs and props do not cast shadows (they are lit as flat pixel art). Use `occluder_light_mask` bits so decorative objects never enter shadow passes.

### 4.4 Window glow

Windows are the cheapest cosy detail; implement each as (a) an emissive sprite (unlit, always bright), (b) a small additive halo, and (c) one shared "spill" light per building, not per window.

```gdscript
# attach to a building root; windows are Sprite2D children in group "window_glow"
extends Node2D

@export var spill: PointLight2D                     # one per building, energy 0.9, scale ~0.55, color #ffb35c
@export var window_sprites: Array[Sprite2D] = []    # emissive window sprites
@export var on_after_night := 0.45                  # windows switch on at 45% night
@export var stagger := 0.12                         # per-window offset so they don't turn on together

func _ready() -> void:
	if spill.texture == null:
		spill.texture = LampRig.make_banded_light(128, 4)
	DayNight.tick.connect(_on_tick)
	_on_tick(0.0)

func _on_tick(_t: float) -> void:
	var n := DayNight.night_factor
	var any := false
	for i in window_sprites.size():
		var thr := on_after_night + stagger * (hash(i + get_instance_id()) % 100) / 100.0
		var on := n > thr
		window_sprites[i].visible = on
		any = any or on
	spill.visible = any
	spill.energy = lerpf(0.0, 0.9, clampf((n - on_after_night) / 0.4, 0.0, 1.0))
```

Window sprite: 2-3 colour pixel pairs (`#ffd890`, `#ffb35c`, `#d9823a`) with a frame darker than the glass; add a 1-px lighter "mullion" cross. Halo sprite behind it (additive, 1-bit alpha dithered) only 3-4 px beyond the window.

Colour roles (keep the palette tight):

| Source | Light colour | Energy | texture_scale | Shadows |
|---|---|---|---|---|
| Lantern key | `#ffcf86` | 1.4 | 1.6 | yes (1 caster) |
| Beam cone | `#ffe9b0` | 0.9 | 2.0 | no |
| Cottage spill | `#ffb35c` | 0.9 | 0.55 | no |
| Window slit (extra) | `#ffb35c` | 0.5 | 0.25 | no |
| Moon (ambient only) | via CanvasModulate | n/a | n/a | none; no light node |
| Lantern/torch props | `#ff9a52` | 0.7 | 0.35 | no |

The moon and sun are never `DirectionalLight2D` here. Ambient colour from `DayNight` does their job. This avoids a full-screen light pass.

---

## 5. Performance budget (GL Compatibility, 640x360)

Target: 60 FPS on integrated GPUs and Steam Deck class hardware; headroom on 2015-era laptops. Frame time 16.6 ms; GPU budget for everything in this document: **3.0 ms**. CPU budget for all effect scripts: **0.25 ms** (they set a few uniforms; nothing allocates per frame except `PackedVector4Array` in `set_glints`, which should be rebuilt only on change).

### 5.1 Pixel counts

The viewport renders at 640x360 = 230,400 px. A full-screen pass is cheap; texture-read count and pass count matter more than ALU.

| Pass | Passes | Per-pixel cost | Estimate (iGPU) | Notes |
|---|---|---|---|---|
| World sprites + tilemap | n/a | n/a | engine baseline | batch; no per-sprite shaders |
| Sea waves | 1 | ~1 noise, 2 pow, 1 hash | 0.15 ms | rect covers sea only (~35% of screen) |
| Sea glints | 1 | loop 4, 1 hash each | 0.10 ms | additive; optional screen mirror +0.10 ms |
| Mist (2 rects) | 2 | 2 fbm = 8 vnoise | 0.45 ms | the heaviest; drop to 3 octaves for low |
| Beam | 1 | 3 mote loops, 1 texture | 0.25 ms | restrict rect to beam area if possible |
| Rain | 1 | 3 layers, 1 splash | 0.15 ms | `visible = false` when intensity < 0.01 |
| LUT grade | 1 | 8 texture reads + screen copy | 0.25 ms | one backbuffer copy |
| 2D lights | multi-pass | see below | 0.5-1.0 ms | the real cost center |
| **Total** | | | **~2-2.5 ms** | leaves room for the engine |

These are planning estimates for desktop iGPU class; measure on the target device with a frame-time overlay before tuning.

### 5.2 Lights: hard limits

- **Max 6 lights overlapping any lit sprite**. Typical scene: lantern + beam cone + cottage spill + 1-2 props = 4.
- **Max 1 shadow-casting light** (lantern). Shadow map cost scales with occluder vertices: keep tower occluder to ~12 vertices.
- Cull lights when irrelevant: `visible = false` by day and when off-screen (use a `VisibleOnScreenNotifier2D` for props). Culled lights cost 0.
- Use `range_item_cull_mask` so lights only touch the layers that should be lit (e.g. skip UI, sky, water glints). Water is lit, so the lamp reflects on the sea; sky is not.
- Do **not** light particles, the rain overlay or the beam rect. Give those nodes `light_mask = 0` or use `unshaded`.
- Keep `texture_scale` modest; area covered matters more than texture resolution, but a 256 px texture on a 640 px screen can still touch most items. Window spill lights at scale 0.25-0.55 touch only the building.
- Height / normal maps: skip. Pixel-art sprites have no authored normals; flat lighting looks correct and avoids the extra texture per item.

### 5.3 Shader hygiene for Compatibility

- Use `hint_screen_texture` at most twice (LUT, optional glint mirror). Each distinct screen-texture user can trigger a backbuffer copy.
- No `discard` in the beam (blending already hides black); `discard` defeats early-z but the 2D renderer does not use it anyway. It simply doesn't help here.
- Branches on uniforms (`use_cliff_mask`, `use_splash_mask`, `use_screen_reflection`) are coherent across the rect, so they are fine.
- No dynamic loops with non-constant bounds. All loops are `for (int i = 0; i < 3 or 4; i++)`.
- No `textureLod`, no derivatives (`dFdx`), no `texelFetch` on 3D. Everything is available in GLES3 / WebGL2 builds.
- Array uniforms (`glints[4]`) are OK in Compatibility; if a driver rejects them, replace with four `uniform vec4 glint0..3`.
- Avoid `mediump` surprises on mobile GPUs: coordinates are small integers (< 4096) and `TIME` rolls over at 3600 s, so highp precision is adequate. If you ever target mobile, add `precision highp float;` in the shader.
- A `ColorRect` is cheaper than a `Sprite2D` plus texture for a procedural shader (no texture binding, no atlas).

### 5.4 Quality tiers

| Setting | High | Medium | Low |
|---|---|---|---|
| Mist octaves | 4 | 3 | 2 + only front rect |
| Mist rects | 2 | 2 | 1 |
| Beam motes layers | 3 | 2 | 1 |
| Rain layers | 3 + splashes | 3, no splashes | 2 |
| LUT grade | on | on, no vignette | off (CanvasModulate only) |
| Shadows | lantern | lantern | none |
| Screen mirror | optional on | off | off |
| Overlapping light max | 6 | 4 | 3 |

Implement as a `FxQuality` enum on a settings autoload that the `WeatherDirector`, `LutGrader` and `LampRig` read; swap the octave count via two shader variants or a `const int OCTAVES` set with `#define` in a `.gdshaderinc` per tier.

### 5.5 Pixel-perfect validation checklist

1. Run the game at 640x360 window, integer scale 1x, take a screenshot, and zoom in: every effect pixel must align to the same grid as the sprites (no half-intensity edges on streaks, no blurred beam edge).
2. Pause the game (`get_tree().paused`), shaders keep running on `TIME`. Confirm no sub-pixel creep: step two frames of the screenshot and diff; moving elements shift by integers only.
3. Move the camera by 1 px with arrow keys while rain/mist/waves are visible: world-anchored patterns must move exactly 1 px; screen-anchored rain must stay put.
4. Cycle `time_of_day` 0 -> 1 at 100x speed: ambient colour should be continuous (no pop at 0.0/0.5), the lantern turns on at dusk, windows come on staggered, glints appear with the moon, rain/mist tint follows `g_ambient`.
5. Toggle each effect individually and read the Profiler: GPU time per canvas item, not just total.
6. Test Windows/Intel UHD, Steam Deck, and a web export (WebGL2 via Compatibility) before declaring any effect final. Report any shader compile error in the Output panel: the usual causes are a missing `global uniform` entry in Project Settings, or a `#include` path typo.

---

## 6. Quick-reference: parameters to expose to designers

| System | Parameter | Meaning / range |
|---|---|---|
| Beam | `rotation_period` | 12-30 s per revolution; 18 feels calm |
| Beam | `beam_length`, `half_width_far` | 300-500 px, 20-40 px |
| Beam | `levels` | 5-7 steps; 4 reads as retro-chunky |
| Beam | `mote_density` | 0.15-0.30 |
| Rain | `intensity` | 0-1; 0.3 drizzle, 0.65 rain, 1.0 storm |
| Rain | `slant` | wind.x / 36 clamped |
| Mist | `density` | 0-1; 0.5 haze, 1.0 fog bank |
| Mist | `base_y`, `thickness` | world y of fog floor, 100-200 px |
| Waves | `wave_density` | 0.2-0.4; lower = sparser, larger swells |
| Waves | `wave_speed` | 0.15-0.35 for calm sea |
| Glints | `wave_jitter`, `shimmer_rate` | 4-8 px, 4-6 Hz |
| DayNight | `seconds_per_day` | 480-900 s; 720 default |
| DayNight | `latitude_deg`, `day_of_year` | 54 / 172 gives long summer dusks |
| Lights | `flicker_hz`, `flicker_amount` | 6-8 Hz, 0.04-0.08 |

Fallback if any `global uniform` fails to load: replace `g_ambient` with a per-shader `uniform vec4 g_ambient_local : source_color = vec4(1.0);` and push from `DayNight` through `get_tree().call_group("ambient_tinted", "set_ambient", c)`. The rest of the pipeline is unchanged.
