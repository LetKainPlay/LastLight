# AGENT 03 — Pixel Art Canvas, Palettes and Generation Pipeline

Project: **Last Light** (Het Laatste Licht) · Engine: Godot 4.7.2 · Scope: canvas spec, master palette + time-of-day ramps, AI asset prompt matrix, validation tooling.
Tone mandate: cozy, toy-over-tool, anti-enterprise. Every rule below exists to keep pixels honest, texels even, and the palette small enough to feel hand-painted.

---

## 0. TL;DR (the rules that must never break)

1. **Internal resolution 640x360.** Integer scale only: 2x=1280x720, 3x=1920x1080, 4x=2560x1440, 6x=3840x2160. Never fractional.
2. **One master palette, 48 indices (32 core + 16 extension).** Every authored pixel is one of these. Time of day is a *runtime remap* of the same 48 slots, never new art.
3. **World tile = 16x16. Prop grid = 8x8. Keeper = 28x44 (box 32x48).** One pixel = one texel = one screen pixel at 1x. No rotated sprites, no scaled sprites, no sub-pixel positions.
4. **Light comes from the upper-left (the sun) and from the lamp (radial, warm).** Side view, flat 2D, no top-down hybrids.
5. **Nothing is generated and shipped raw.** AI output is a *draft*; it is quantized to the master palette, cleaned, and must pass `validate_palette.py` before it enters `res://`.

---

## 1. Project mismatch: 320x180 vs 640x360 (FLAG)

`/home/claude/lastlight/project.godot` currently has `viewport_width=320`, `viewport_height=180`, `window_width_override=1280`, `window_height_override=720`, `stretch/mode="canvas_items"`. The brief targets **640x360**. At 320x180 a 1080p display is 6x and the art budget is a quarter of what the brief calls for ("high-detail"). This document assumes 640x360. Required changes (not applied by this agent):

```ini
[display]
window/size/viewport_width=640
window/size/viewport_height=360
window/size/window_width_override=1280      ; 2x for desktop dev; integer multiple of 640
window/size/window_height_override=720
window/stretch/mode="viewport"              ; render at 640x360 then scale the finished frame (true pixel art)
window/stretch/aspect="keep"                ; letterbox/pillarbox, never stretch non-uniformly
window/stretch/scale_mode="integer"         ; already set; keeps 2x/3x/4x/6x only
window/handheld/orientation=0

[rendering]
textures/canvas_textures/default_texture_filter=0                 ; Nearest (already set)
renderer/rendering_method="gl_compatibility"                      ; already set
2d/snap/snap_2d_transforms_to_pixel=true                          ; no subpixel jitter
2d/snap/snap_2d_vertices_to_pixel=true
anti_aliasing/quality/msaa_2d=0
environment/defaults/default_clear_color=Color(0.043, 0.055, 0.102, 1)   ; #0b0e1a (void)
```

Notes:
- `stretch/mode="canvas_items"` (current) re-rasterizes at window resolution; with Nearest it *mostly* works but text/Line2D/shaders render at output res and can break the pixel grid. `"viewport"` is the correct mode for this game: everything is drawn to a 640x360 buffer, then scaled by an integer factor.
- Camera: `Camera2D.position_smoothing_enabled=false` or smooth in code and `round()` the final position every frame. Never let the camera sit on a fractional coordinate.
- At 1080p the 640x360 buffer scales exactly 3x (no letterbox). 1440p = 4x (no letterbox). 4K = 6x (no letterbox). 1366x768 and 1600x900 get 2x with bars; this is intended.
- Fonts/UI must be bitmap or pixel-snapped fonts authored at the 640x360 grid (see section 3.6).

---

## 2. Canvas specification

### 2.1 Resolution and grid

| Item | Value |
|---|---|
| Base resolution | 640 x 360 (16:9) |
| Integer scales | 2x, 3x, 4x, 6x (and 5x on 3200x1800 if ever needed) |
| World tile | 16 x 16 px (640/16 = 40 cols; 360/16 = 22.5 rows, so screens are authored 40x23 with row 23 half-cropped, or 40x22 + 8px HUD strip) |
| Sub-tile / prop grid | 8 x 8 px (all props snap to 8) |
| Micro grid (decor, grass tufts) | 1 px free placement, but no sub-pixel |
| Max sprite sheet cell | 64x64 (keeper), 128x128 (large props), 256x256 (lens, hero set pieces) |
| Atlas pad | 1 px transparent gutter + 1 px edge-extrude per frame in atlases; Godot `texture_filter=nearest`, `Repeat=Disabled` for sprites |
| Import preset | Lossless, mipmaps OFF, filter OFF, no compression, `process/fix_alpha_border=true` |
| Allowed transforms | translate (integer), flip H. **Forbidden:** rotation, non-integer scale, skew on authored sprites. Rotating things (lens, beam, flag) are pre-rendered frame sequences or segmented sprites. |

### 2.2 Pixel-grid density rules ("detail budget")

- **Hand-painted look = consistent pixel size.** Every asset, including UI and VFX, uses the same 1-px grid. Mixed-resolution (a 2x-scaled sprite next to a 1x one) is a hard reject.
- **Cluster rule:** minimum shape width is 2 px for interior detail; 1 px only for outlines, specular glints, eyes, and rope/wire lines. No stray single pixels ("orphans") except deliberate glints (max 3 per sprite).
- **Line rules:** straight lines use consistent step patterns (1:1, 1:2, 2:1, 1:3). Avoid "jaggies" (a 1:2 step that becomes 1:1 mid-line). Curves use progressively longer runs (1,1,2,3 not 3,1,2,1).
- **Dither policy:** ordered 2x2 checker dither only, and only in skies, fog, beam falloff, and water depth. Never dither on the keeper or character-scale props. No noise dither.
- **Ramps per material:** 3 tones (shadow/base/light) at prop scale, 4-5 at set-piece scale (lighthouse tower, cliff). A hue shift of ~8-15 degrees per step: shadows lean cool/violet, lights lean warm/yellow.
- **Texture density by distance (parallax layers):**

| Layer | Detail | Colors per sprite | Outline |
|---|---|---|---|
| Sky | gradient bands + clouds | ramp of 8 (section 4.4) | none |
| Far sea / horizon | 1-px wave lines, 2-tone | 4 | none |
| Mid cliffs/islets | 3-tone masses, no interior outline | 5 | none (selout only) |
| Playfield (tiles, lighthouse, props) | full detail | 6-12 | selout (section 2.5) |
| Keeper and interactables | max detail | 8-12 | dark selout + 1-px rim light |
| Foreground (grass, rope, spray) | silhouette-heavy, 2-tone | 3 | solid `void`/`ink` |

- **Palette cap per asset:** <= 12 distinct indices (<= 16 for the lens and lighthouse hero art). The validator reports counts.
- **Silhouette first:** every prop must read as a flat `ink`-filled silhouette at 1x on a mid-grey. If it does not, simplify.

### 2.3 Tile and prop sizes

| Category | Size (px) | Notes |
|---|---|---|
| Terrain tile | 16x16 | autotile 47-blob or 16-tile "wang" set; seams checked with `check_seamless_tile` in Pixelorama |
| Terrain transitions (grass->rock->sand) | 16x16 | edge variants baked, no runtime blending |
| Water tile | 16x16 x 4-frame loop | surface only; depth via parallax rows |
| Small prop (lantern, bucket, shell) | 8x8 to 16x16 | |
| Medium prop (bench, crate, rowboat) | 24x16 to 48x32 | multiples of 8 |
| Large prop (windmill-sized, boat house) | 64x64 to 96x80 | |
| Lighthouse tower (exterior) | 96 wide x 232 tall max (fits 360 with sea + sky margin) | built from stacked 96x24 segments for modular upgrades |
| Lens (Fresnel, interior hero) | 160x160 canvas, 128 diameter | rotation as 16 pre-rendered frames (22.5 deg each), see 2.6 |
| Interior room background | 640x360 (single screen) | per-floor, composed from 16px tiles plus 8px props |
| UI icons | 16x16, 24x24 | same palette, `ui-*` indices |

### 2.4 Keeper sprite spec

The Keeper is a chunky, cozy "toy" proportion: large head, short limbs, oilskin coat, wool cap, readable at 1x.

| Property | Value |
|---|---|
| Frame cell | **32 x 48** (feet baseline at y=44, 4 px bottom margin for squash) |
| Actual body box | 24x40 min to 28x44 default, 32x48 max (with raised arms or lantern swing) |
| Head | 12-14 px tall (about 1/3 of 40-44), 12-13 px wide, 3 px ear/cap overhang allowed |
| Body proportion | 3-heads tall ("toy"), shoulders 14 px wide, legs 8-10 px, arms 8-10 px |
| Eyes | 1 px wide x 2 px tall, `void`; no whites at 1x. Blink = 1 px row |
| Mouth | 1 px optional on emotes only |
| Facing | Side view, authored **facing right**; left = flip H at runtime (asymmetric items - lantern in left hand - are mirrored too; accepted) |
| Extra directions | `climb` (back view, stairs/ladder), `front` (idle-at-window, 3/4 front, only 2 sheets) |
| Anchor | bottom-center of the feet (x=16, y=44) |
| Outline | Selout (section 2.5): darkened outer line using `ink` on lit side and `void` on shadow side |
| Palette (keeper-specific, <=14) | `void`, `ink`, `skin`, `signal-coral`(cheeks, scarf), `lamp-gold` (oilskin), `lamp-amber` (oilskin shade), `oak`, `driftwood`, `dusk-stone`, `slate`, `fog`, `salt`, `chalk`, `lighthouse-red` (cap) |
| Light | upper-left key light + 1-px warm rim on the lamp side when indoors |

#### Animation frame table (Keeper, 32x48 cells)

| Animation | Frames | FPS | Loop | Notes |
|---|---|---|---|---|
| idle | 4 | 6 | yes | breathing: 1 px chest rise; blink on frame 3 |
| idle-lantern | 4 | 6 | yes | lantern sway 1 px |
| walk | 6 | 10 | yes | contact/down/passing/contact/down/passing; 1 px body bob |
| run (rush to stairs) | 6 | 14 | yes | 2 px lean |
| climb (stairs/ladder) | 6 | 8 | yes | back view |
| interact-reach | 4 | 10 | no | hand to object |
| work-polish (lens) | 6 | 8 | yes | cloth wipe arc |
| work-fuel/oil | 6 | 8 | yes | |
| carry (walk w/ crate) | 6 | 9 | yes | 2 px lower bob |
| sit / rest | 4 + 2 loop | 5 | yes | cocoa mug steam is a separate FX sprite |
| sleep | 2 | 2 | yes | Zs separate FX |
| look-out (telescope/window) | 4 | 8 | no -> hold | |
| react-happy | 6 | 10 | no | hop 3 px |
| react-startle (storm) | 4 | 12 | no | |
| shiver (storm/night cold) | 2 | 12 | yes | 1 px jitter on X only |
| pet / feed (gull, cat) | 6 | 8 | yes | |
| **Total unique frames** | ~80 | | | right-facing only; ~4 KB each uncompressed at RGBA = ~320 KB |

Frame timing in Godot: use `AnimatedSprite2D`/`AnimationPlayer` with explicit per-frame durations; never interpolate position within a walk cycle between integer pixels.

### 2.5 Outline and selective-outline (selout) rules

1. **Outer outline: 1 px**, never 2, on everything in the playfield and keeper layer. Background layers use no outline.
2. **Selout, not black-out.** The outer outline takes the *darkest ramp color of the material it borders*, not `void`:
   - lit side (upper-left): outline = 1 step darker than the shadow tone of that material (e.g., on `salt` walls use `slate`).
   - shadow side (lower-right): outline = `ink` or `void`.
   - where a sprite overlaps a background of the same material, drop the outline on that edge.
3. **Inner lines:** only for form separations (arm vs. torso, window frames); use the shadow tone, not the outline color. Max 1 px.
4. **No outline on light sources/glows** (lamp, beam, window light, fire): emissive things are outlined by *contrast* instead.
5. **Keeper rim light:** 1-px `beam-halo` or `lamp-white` on the edge facing the lamp when in the lamp room; replaces the outline on that edge.
6. **Corners:** do not leave "doubled" corner pixels (L-shaped 2-px corners are fine; 3-px blobs are not). Clean with `clean_isolated_pixels`.
7. **Contact shadows:** 1-px `ink` at 50 percent dither under props on ground tiles; no soft blobs.
8. **Water/foam edges:** foam = `foam` / `chalk` 1-px highlights with no outline.

### 2.6 Animation rules for non-character assets

| Asset | Frames | FPS | Notes |
|---|---|---|---|
| Water surface tile | 4 | 3 | offset-shift loop, seamless |
| Wave crest sprite | 6 | 6 | |
| Beam sweep | not frames: **a pre-rendered 640x360-aligned cone sprite rotated by 16-step LUT**; uses `beam-halo`/`lamp-white` with 2x2 dither falloff. No rotation property: swap 16-32 frames (11.25 or 22.5 deg per frame) |
| Fresnel lens rotation | 16 | 8 (idle) -> 16 (storm) | 22.5 deg per frame; looped |
| Flame / lantern flicker | 4 | 8 | irregular durations: 2,1,2,3 ticks |
| Gull fly | 6 | 8 | |
| Rain streaks | 3 variants | scrolling | integer scroll of a tiled 128x128 layer, 2 layers parallax at 3 px and 5 px/frame |
| Fog | 2 big layers | scroll 0.25 px/frame via integer accumulator | |
| Window glow flicker | 3 | 4 | |
| Flag / pennant | 4 | 6 | |

---

## 3. Authoring rules and tooling

### 3.1 Light model (universal)
- **Key light: upper-left, ~45 degrees**, so highlights sit top-left and shadows bottom-right on every prop and tile. Sun position does not move in-game visually; time of day changes *color*, not light direction (cheap, consistent, cozy).
- **Lamp light:** radial, warm (`lamp-gold` / `lamp-white`), rendered as palette-quantized glow rings (3 steps + dither), not alpha gradients.
- **Ambient/bounce:** shadows lean `dusk-stone` / `night-violet`; never pure black except `void` for contact.
- **Sea/sky reflection:** underside of eaves and cliff bottoms pick up 1 px of `sea-glass`.

### 3.2 Side-view consistency
- Pure orthographic side view; ground plane is a horizontal strip; objects have no visible top face except stylized "ledges" 2-3 px tall.
- Doors/windows face the viewer; interiors show a cutaway back wall.
- Horizon line at y = 150 for exterior day scenes (fixed so sea parallax stays consistent).
- Objects on the ground sit with the bottom row on the baseline (anchor bottom-center).
- Perspective cheats: tower slightly narrower toward top (1 px per 24 px) but no vanishing-point skew.

### 3.3 Required export formats
- PNG-8 or PNG-32 RGBA, binary alpha only (0 or 255). No semi-transparent pixels. No color profile / gamma chunk (strip `gAMA`, `iCCP`, `sRGB`).
- Spritesheets: horizontal strip per animation, cell-aligned, naming `keeper_walk_6f_32x48.png`.
- Aseprite JSON or Pixelorama `export_aseprite_json` alongside; tags per animation.

### 3.4 Naming convention
`<category>_<name>_<variant>_<frames>f_<w>x<h>.png`, e.g. `prop_lantern_lit_4f_16x16.png`, `tile_grass_edge_n_16x16.png`, `char_keeper_walk_6f_32x48.png`.

### 3.5 Godot import settings (applies to all art)
`compress/mode=Lossless`, `mipmaps/generate=false`, `process/fix_alpha_border=true`, `process/premult_alpha=false`, `detect_3d/compress_to=Disabled`. Project default texture filter Nearest. Sprite2D `centered=false` + integer positions; use `region_filter_clip_enabled` for atlas region sprites to prevent bleed.

### 3.6 Fonts / UI pixel grid
Bitmap font at 8 px (body) and 16 px (title) with 1-px outline from `ui-ink`; text colors `ui-parchment` on `ui-ink` panels with `ui-brass` trims. Panels are 9-slice with 8 px corners. All UI uses indices 45-47 plus the neutral ramp; UI never recolors with the time-of-day shift (see locked indices, section 4.3), so it stays legible at night.

---

## 4. Master palette

### 4.1 Design principles
- 32 **core** colors cover world art; 16 **extension** colors cover sky, FX and UI. Total 48. Authoring tools load all 48; most assets use 6-12.
- Ramps run **cool shadows -> warm lights** with hue shift. Greens lean blue in shadow and yellow in light; rocks lean violet in shadow and sand in light.
- Saturation peaks in the mids and is reduced at both ends to keep it calm and "gouache" cozy.
- The lighthouse's red and the lamp's gold are the only fully saturated hues; they are the visual "hearth" of every screen.
- WCAG-style check: text pairs `ui-parchment` (#f4e6c8) on `ui-ink` (#3a2a22) = contrast about 11.1:1; `ui-brass` on `ui-ink` = about 5.6:1.

### 4.2 Full table (index, name, hex, group, role)

Index is the 0-based position in the .hex/.gpl files and in the Godot palette-shift LUT (row = index).

| Idx | Hex idx | Name | Hex | Group | Role |
|---|---|---|---|---|---|
| 0 | 0x00 | void | `#0b0e1a` | ink | deepest outline, contact shadow, eyes |
| 1 | 0x01 | ink | `#1a2036` | ink | standard dark outline / text |
| 2 | 0x02 | dusk-stone | `#2c3554` | ink | cool shadow, night walls |
| 3 | 0x03 | slate | `#4a5578` | ink | stone midtone shadow |
| 4 | 0x04 | mist | `#7d8bab` | ink | stone midtone |
| 5 | 0x05 | fog | `#b4bfd6` | ink | stone light, fog |
| 6 | 0x06 | salt | `#e9e4d4` | light | lighthouse white (base) |
| 7 | 0x07 | chalk | `#fffaf0` | light | lighthouse white highlight, foam, specular |
| 8 | 0x08 | deep-sea | `#16304f` | sea | deep water, night ocean |
| 9 | 0x09 | tide | `#1f4b73` | sea | water shadow |
| 10 | 0x0A | swell | `#2f739a` | sea | water base |
| 11 | 0x0B | shallows | `#52a2b8` | sea | water light |
| 12 | 0x0C | sea-glass | `#94d0d0` | sea | water highlight, lens glass tint |
| 13 | 0x0D | pine-shadow | `#1b3a33` | flora | foliage shadow |
| 14 | 0x0E | fir | `#2c5a3e` | flora | foliage dark |
| 15 | 0x0F | moss | `#4f8040` | flora | foliage mid |
| 16 | 0x10 | meadow | `#86a94c` | flora | grass base |
| 17 | 0x11 | sungrass | `#c2cf6e` | flora | grass light |
| 18 | 0x12 | basalt | `#2b2530` | rock | rock darkest |
| 19 | 0x13 | cliff | `#4d4048` | rock | rock shadow |
| 20 | 0x14 | granite | `#7a655e` | rock | rock base |
| 21 | 0x15 | sandstone | `#a98c78` | rock | rock light, path |
| 22 | 0x16 | dune | `#d4b896` | rock | sand, rope, light stone |
| 23 | 0x17 | brick-dark | `#5a1f2e` | red | lighthouse red shadow, roof |
| 24 | 0x18 | lighthouse-red | `#a03a3a` | red | lighthouse stripe base |
| 25 | 0x19 | signal-coral | `#d9684f` | red | red highlight, scarf, blush |
| 26 | 0x1A | driftwood | `#5e3a2c` | wood | wood shadow |
| 27 | 0x1B | oak | `#94603a` | wood | wood base |
| 28 | 0x1C | lamp-amber | `#c8802c` | lamp | flame shadow, oilskin shade |
| 29 | 0x1D | lamp-gold | `#f2b441` | lamp | lamp, oilskin, windows (lit) |
| 30 | 0x1E | lamp-white | `#ffe69a` | lamp | lamp core, brightest warm |
| 31 | 0x1F | skin | `#e8b394` | skin | keeper skin |
| 32 | 0x20 | sky-blue | `#5a9ad0` | sky | noon sky mid-top |
| 33 | 0x21 | sky-light | `#86bde6` | sky | noon sky mid |
| 34 | 0x22 | sky-pale | `#b8dcf0` | sky | noon sky low |
| 35 | 0x23 | horizon-haze | `#e0f0f4` | sky | horizon band |
| 36 | 0x24 | cloud-shade | `#9fb4cc` | sky | cloud underside |
| 37 | 0x25 | dawn-pink | `#e6a0a0` | sky | dawn clouds, cheeks |
| 38 | 0x26 | mauve | `#c07a9a` | sky | dusk clouds |
| 39 | 0x27 | dusk-violet | `#6a5a9a` | sky | twilight sky |
| 40 | 0x28 | night-violet | `#3b3470` | sky | night sky lows, shadow tint |
| 41 | 0x29 | sunset-orange | `#ff9a5c` | sky | sunset glow |
| 42 | 0x2A | beam-halo | `#fff4c8` | fx | beam core halo |
| 43 | 0x2B | foam | `#dff6f0` | fx | wave foam, spray |
| 44 | 0x2C | ember | `#ff6a3d` | fx | fire, embers, warning |
| 45 | 0x2D | ui-ink | `#3a2a22` | ui | UI dark |
| 46 | 0x2E | ui-parchment | `#f4e6c8` | ui | UI light |
| 47 | 0x2F | ui-brass | `#c9a15a` | ui | UI accent |

### 4.3 Locked (emissive / UI) indices
These indices are **not** remapped by time-of-day shift (they keep their master hex in every time slot), because they emit light or must stay readable: `lamp-amber`(28), `lamp-gold`(29), `lamp-white`(30), `signal-coral`(25), `beam-halo`(42), `ember`(44), `ui-ink`(45), `ui-parchment`(46), `ui-brass`(47). At night the *world* gets darker around them, which is what makes the lamp feel warm. Everything else is remapped.

### 4.4 Palette-shift method (runtime)
All art is authored with master indices (rendered as master hex). At runtime a post-process canvas shader (or per-CanvasItem shader on the world layers) maps each master color to the time-of-day color via a 48x1 LUT texture (`palette_lut_<time>.png`, Nearest). Cross-fades between times = lerp between two LUT rows on the GPU (every on-screen pixel stays one flat color). UI layer is excluded via a separate CanvasLayer.

Per-time parameters (generated shifts below use exactly this recipe):
`out = lerp(rgb, tint, strength)` where `tint = lerp(shadowTint, highlightTint, luma(rgb))`, after multiplying HSV value by `gain` and saturation by `sat`.

| Time | Shadow tint | Highlight tint | Strength | Value gain | Sat mult | Mood |
|---|---|---|---|---|---|---|
| Dawn | `#3b3a6e` | `#ffb8a0` | 0.3 | 0.92 | 0.92 | cool lavender shadows, peach highlights, soft |
| High Noon | `#2a3f6a` | `#fffbe8` | 0.0 | 1.0 | 1.0 | identity (master palette), clean and bright |
| Storm | `#2e3a50` | `#a8b6c4` | 0.45 | 0.78 | 0.6 | desaturated slate, heavy, low contrast |
| Golden | `#5a2d3a` | `#ffc15a` | 0.34 | 0.98 | 1.08 | amber highlights, plum shadows, long warm light |
| Twilight | `#22204e` | `#c07aa0` | 0.5 | 0.72 | 0.82 | violet-magenta, lamp becomes the hero |
| Midnight | `#080c24` | `#6f86c8` | 0.62 | 0.5 | 0.7 | deep indigo, minimal contrast, lamp + stars only |

### 4.5 Time-of-day palette table (all 48 slots)

Columns are the six remapped palettes. No two slots merge in any time (verified: 48 distinct colors per time).

| Idx | Name | High Noon | Dawn | Golden Hour | Overcast Storm | Twilight | Midnight |
|---|---|---|---|---|---|---|---|
| 0 | void | `#0b0e1a` | `#1d1d33` | `#281b25` | `#1f2532` | `#1a1833` | `#0b0f21` |
| 1 | ink | `#1a2036` | `#2b2c46` | `#352938` | `#2c3342` | `#262340` | `#14182d` |
| 2 | dusk-stone | `#2c3554` | `#3c3d5a` | `#453a4c` | `#3a4253` | `#342e4e` | `#1d233c` |
| 3 | slate | `#4a5578` | `#575773` | `#5f5565` | `#4f5769` | `#494060` | `#2b334f` |
| 4 | mist | `#7d8bab` | `#848197` | `#8c8388` | `#70798a` | `#6c5d7b` | `#424d6e` |
| 5 | fog | `#b4bfd6` | `#b3aab6` | `#bbafa6` | `#919aa7` | `#8f7893` | `#59658b` |
| 6 | salt | `#e9e4d4` | `#dcc6b8` | `#e7cfa5` | `#aaafb1` | `#ab8b99` | `#6a779b` |
| 7 | chalk | `#fffaf0` | `#f0d8cb` | `#fbe2b9` | `#b8bdc1` | `#ba97a7` | `#7481a9` |
| 8 | deep-sea | `#16304f` | `#2d3957` | `#343649` | `#323e4f` | `#2a2b4b` | `#182037` |
| 9 | tide | `#1f4b73` | `#3a4e6f` | `#3d4b61` | `#3f5063` | `#373a5b` | `#212c47` |
| 10 | swell | `#2f739a` | `#4d6d8a` | `#4e6c7c` | `#51697b` | `#494e6f` | `#2e3e5d` |
| 11 | shallows | `#52a2b8` | `#6e91a0` | `#6f9491` | `#698391` | `#636681` | `#3f5374` |
| 12 | sea-glass | `#94d0d0` | `#a1b4b2` | `#a6bca3` | `#899ea5` | `#877d91` | `#55698c` |
| 13 | pine-shadow | `#1b3a33` | `#303e45` | `#3a3f37` | `#313e46` | `#2c2e42` | `#192235` |
| 14 | fir | `#2c5a3e` | `#42574f` | `#4a593e` | `#405253` | `#3c3e4c` | `#243043` |
| 15 | moss | `#4f8040` | `#617554` | `#68783f` | `#576a62` | `#545254` | `#334153` |
| 16 | meadow | `#86a94c` | `#8e9560` | `#969b47` | `#768474` | `#736861` | `#475568` |
| 17 | sungrass | `#c2cf6e` | `#bdb478` | `#c7bc5e` | `#959e8c` | `#957d75` | `#5c697f` |
| 18 | basalt | `#2b2530` | `#373042` | `#432e34` | `#303441` | `#2d253f` | `#171b2f` |
| 19 | cliff | `#4d4048` | `#534554` | `#5f4545` | `#444752` | `#42344c` | `#24283f` |
| 20 | granite | `#7a655e` | `#786365` | `#856454` | `#606067` | `#5d485c` | `#363b54` |
| 21 | sandstone | `#a98c78` | `#a08379` | `#ac8565` | `#7c7b7e` | `#7b5e6d` | `#494f6a` |
| 22 | dune | `#d4b896` | `#c5a590` | `#d1aa7a` | `#989795` | `#97757f` | `#5c6481` |
| 23 | brick-dark | `#5a1f2e` | `#562f44` | `#632931` | `#453b48` | `#3f2742` | `#211e33` |
| 24 | lighthouse-red | `#a03a3a` | `#8b4850` | `#983f37` | `#6a565f` | `#633a4f` | `#373047` |
| 25 | signal-coral | `#d9684f` | `#d9684f` | `#d9684f` | `#d9684f` | `#d9684f` | `#d9684f` |
| 26 | driftwood | `#5e3a2c` | `#5d4244` | `#6a4030` | `#4b474d` | `#473344` | `#27283b` |
| 27 | oak | `#94603a` | `#896151` | `#955f39` | `#6b6362` | `#674852` | `#3b3c50` |
| 28 | lamp-amber | `#c8802c` | `#c8802c` | `#c8802c` | `#c8802c` | `#c8802c` | `#c8802c` |
| 29 | lamp-gold | `#f2b441` | `#f2b441` | `#f2b441` | `#f2b441` | `#f2b441` | `#f2b441` |
| 30 | lamp-white | `#ffe69a` | `#ffe69a` | `#ffe69a` | `#ffe69a` | `#ffe69a` | `#ffe69a` |
| 31 | skin | `#e8b394` | `#d2a390` | `#dea577` | `#a19998` | `#9f7580` | `#606482` |
| 32 | sky-blue | `#5a9ad0` | `#738daf` | `#728da0` | `#6f859b` | `#666489` | `#415377` |
| 33 | sky-light | `#86bde6` | `#97a8c0` | `#98abb0` | `#859aac` | `#7f7797` | `#51638a` |
| 34 | sky-pale | `#b8dcf0` | `#bcc0c8` | `#c2c7b8` | `#9babb7` | `#9986a0` | `#617299` |
| 35 | horizon-haze | `#e0f0f4` | `#dacfcc` | `#e3d9bc` | `#abb6bd` | `#ac90a5` | `#6c7ca3` |
| 36 | cloud-shade | `#9fb4cc` | `#a3a1af` | `#aaa59f` | `#8792a0` | `#84728d` | `#526084` |
| 37 | dawn-pink | `#e6a0a0` | `#ce9696` | `#da967f` | `#9d9198` | `#9a6d81` | `#5c5e7e` |
| 38 | mauve | `#c07a9a` | `#ad788e` | `#b9767b` | `#857989` | `#815977` | `#4c4c6d` |
| 39 | dusk-violet | `#6a5a9a` | `#6f5d8a` | `#765a7c` | `#60617a` | `#59466e` | `#34395b` |
| 40 | night-violet | `#3b3470` | `#483f6d` | `#4f395f` | `#444760` | `#3c3159` | `#222643` |
| 41 | sunset-orange | `#ff9a5c` | `#dd936f` | `#e98f4e` | `#a7938a` | `#a26c6e` | `#605d75` |
| 42 | beam-halo | `#fff4c8` | `#fff4c8` | `#fff4c8` | `#fff4c8` | `#fff4c8` | `#fff4c8` |
| 43 | foam | `#dff6f0` | `#dad4ca` | `#e3deb9` | `#acb8bd` | `#ad93a4` | `#6d7ea4` |
| 44 | ember | `#ff6a3d` | `#ff6a3d` | `#ff6a3d` | `#ff6a3d` | `#ff6a3d` | `#ff6a3d` |
| 45 | ui-ink | `#3a2a22` | `#3a2a22` | `#3a2a22` | `#3a2a22` | `#3a2a22` | `#3a2a22` |
| 46 | ui-parchment | `#f4e6c8` | `#f4e6c8` | `#f4e6c8` | `#f4e6c8` | `#f4e6c8` | `#f4e6c8` |
| 47 | ui-brass | `#c9a15a` | `#c9a15a` | `#c9a15a` | `#c9a15a` | `#c9a15a` | `#c9a15a` |

### 4.6 Sky ramps (8-band gradients, top to bottom)

Skies are drawn as 8 horizontal bands with 2x2 ordered dither on each band boundary (a 4-row dither zone), sampled from these ramps rather than the 48-slot remap, so each time gets a purpose-built gradient. These 48 sky colors are *additional* to the master palette: they are **runtime-only background fill colors** and are generated by a shader, not stored in sprite PNGs. Validator exempts `bg_sky_*` filenames (use `--free-size` and a per-time palette).

| Time | Band 0 (zenith) | 1 | 2 | 3 | 4 | 5 | 6 | 7 (horizon) |
|---|---|---|---|---|---|---|---|---|
| Dawn | `#2e2a5e` | `#4a4580` | `#7a5a96` | `#b0709a` | `#e08a9a` | `#f5a890` | `#fcc8a0` | `#fde6c0` |
| High Noon | `#3a74b8` | `#4f8ccc` | `#66a2dc` | `#86bde6` | `#a4d0ee` | `#c0e0f2` | `#d8eef4` | `#eef8f6` |
| Storm | `#2e3846` | `#3b4756` | `#4a5868` | `#5c6c7c` | `#70808e` | `#869498` | `#9ca8aa` | `#b2bcba` |
| Golden | `#3c5a94` | `#5a78a8` | `#8a8ca8` | `#c0929a` | `#e8a070` | `#f6b45a` | `#fcc86a` | `#fee49a` |
| Twilight | `#14123c` | `#1f1c52` | `#2e2868` | `#46387a` | `#6a4a88` | `#94608c` | `#c07a8c` | `#e49a84` |
| Midnight | `#04061a` | `#070b26` | `#0b1234` | `#111a46` | `#18235a` | `#223070` | `#2e3e82` | `#3d4f94` |

Celestial bodies and extras per time (all from master slots): sun disc `lamp-white` + `beam-halo` ring (dawn/golden low on horizon, noon high), moon `chalk` + `fog` crater pixels, stars `chalk`/`fog` single pixels (twinkle 2 frames at 1 fps, max 40 on screen, none at noon/storm), clouds `chalk`/`cloud-shade`/`mist` 3-tone, storm clouds `slate`/`dusk-stone`/`ink`.

### 4.7 Atmospheric overlay rules (no extra colors)
- **Fog / haze:** 2x2 dither of `horizon-haze` (day), `fog` (storm), `night-violet` (night) over far layers at 25/50/75 percent patterns; opacity is expressed by dither density, never alpha.
- **Rain:** 1x4 and 1x6 streaks, `fog` (day/storm) or `mist` (night), 2 px/frame diagonal at fixed 3:1 slope.
- **Lamp glow:** three concentric dithered rings: `lamp-white` core, `lamp-gold` mid, `lamp-amber` outer, each ring 8-16 px wide; plus beam cone with `beam-halo` and 2x2 falloff.
- **Windows at night:** `lamp-gold` rectangles with `lamp-white` top-left pixel; remain locked colors.
- **Water reflections:** vertical dashed 1-px lines of `sea-glass`/`lamp-gold` below the lamp, 2-frame shimmer.

---

## 5. Export blocks

### 5.1 `docs/lastlight_master.hex` (Lospec-style, one hex per line, index order)
```

0b0e1a
1a2036
2c3554
4a5578
7d8bab
b4bfd6
e9e4d4
fffaf0
16304f
1f4b73
2f739a
52a2b8
94d0d0
1b3a33
2c5a3e
4f8040
86a94c
c2cf6e
2b2530
4d4048
7a655e
a98c78
d4b896
5a1f2e
a03a3a
d9684f
5e3a2c
94603a
c8802c
f2b441
ffe69a
e8b394
5a9ad0
86bde6
b8dcf0
e0f0f4
9fb4cc
e6a0a0
c07a9a
6a5a9a
3b3470
ff9a5c
fff4c8
dff6f0
ff6a3d
3a2a22
f4e6c8
c9a15a
```

### 5.2 `lastlight_master.gpl` (GIMP/Aseprite/Krita/Pixelorama/LibreSprite)
```
GIMP Palette
Name: Last Light Master 48
Columns: 8
#
 11  14  26	00_void
 26  32  54	01_ink
 44  53  84	02_dusk-stone
 74  85 120	03_slate
125 139 171	04_mist
180 191 214	05_fog
233 228 212	06_salt
255 250 240	07_chalk
 22  48  79	08_deep-sea
 31  75 115	09_tide
 47 115 154	10_swell
 82 162 184	11_shallows
148 208 208	12_sea-glass
 27  58  51	13_pine-shadow
 44  90  62	14_fir
 79 128  64	15_moss
134 169  76	16_meadow
194 207 110	17_sungrass
 43  37  48	18_basalt
 77  64  72	19_cliff
122 101  94	20_granite
169 140 120	21_sandstone
212 184 150	22_dune
 90  31  46	23_brick-dark
160  58  58	24_lighthouse-red
217 104  79	25_signal-coral
 94  58  44	26_driftwood
148  96  58	27_oak
200 128  44	28_lamp-amber
242 180  65	29_lamp-gold
255 230 154	30_lamp-white
232 179 148	31_skin
 90 154 208	32_sky-blue
134 189 230	33_sky-light
184 220 240	34_sky-pale
224 240 244	35_horizon-haze
159 180 204	36_cloud-shade
230 160 160	37_dawn-pink
192 122 154	38_mauve
106  90 154	39_dusk-violet
 59  52 112	40_night-violet
255 154  92	41_sunset-orange
255 244 200	42_beam-halo
223 246 240	43_foam
255 106  61	44_ember
 58  42  34	45_ui-ink
244 230 200	46_ui-parchment
201 161  90	47_ui-brass
```

### 5.3 Godot palette LUT generation (48x1, one PNG per time)
Create the LUTs once with the Python snippet below (also runnable in CI). Output: `res://art/palettes/lut_<time>.png`, 48x1 RGBA, Nearest.

```python
#!/usr/bin/env python3
# tools/make_luts.py  -  usage: python3 tools/make_luts.py docs/lastlight_master.hex art/palettes
import sys, colorsys, pathlib
from PIL import Image
EMIS = {28,29,30,25,42,44,45,46,47}          # locked indices (section 4.3)
T = {  # shadow tint, highlight tint, strength, gain, sat
 "dawn":("3b3a6e","ffb8a0",0.30,0.92,0.92), "noon":("2a3f6a","fffbe8",0.00,1.00,1.00),
 "storm":("2e3a50","a8b6c4",0.45,0.78,0.60), "golden":("5a2d3a","ffc15a",0.34,0.98,1.08),
 "twilight":("22204e","c07aa0",0.50,0.72,0.82), "midnight":("080c24","6f86c8",0.62,0.50,0.70)}
rgb = lambda h: tuple(int(h[i:i+2],16) for i in (0,2,4))
luma = lambda c: (0.2126*c[0]+0.7152*c[1]+0.0722*c[2])/255
def shift(i, h, t):
    if i in EMIS: return rgb(h)
    sh, hi, s, g, sat = T[t]; c = rgb(h); l = luma(c)
    H, S, V = colorsys.rgb_to_hsv(*(x/255 for x in c))
    c = [x*255 for x in colorsys.hsv_to_rgb(H, min(1,S*sat), min(1,V*g))]
    tint = [a+(b-a)*l for a,b in zip(rgb(sh), rgb(hi))]
    return tuple(max(0,min(255,round(a+(b-a)*s))) for a,b in zip(c,tint))
pal = [l.strip() for l in open(sys.argv[1]) if len(l.strip())==6]
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
for t in T:
    im = Image.new("RGBA",(len(pal),1))
    for i,h in enumerate(pal): im.putpixel((i,0), shift(i,h,t)+(255,))
    im.save(out/f"lut_{t}.png")
print("ok", len(pal), "colors x", len(T), "times")
```

Locked slots (section 4.3) keep master values in every column of the table above; `signal-coral` is therefore identical across times.

Godot shader sketch (canvas_item, applied to a full-screen `ColorRect` with `hint_screen_texture` is **not** used because it would remap UI too; apply to the world CanvasLayer's `SubViewport` output instead, or per-sprite via material):

```glsl
shader_type canvas_item;
uniform sampler2D lut_a : filter_nearest;
uniform sampler2D lut_b : filter_nearest;
uniform sampler2D master : filter_nearest;   // 48x1 master palette
uniform float blend = 0.0;                   // 0..1 time cross-fade
uniform float tol = 0.004;
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    if (c.a < 0.5) discard;
    float idx = -1.0;
    for (int i = 0; i < 48; i++) {
        vec3 m = texelFetch(master, ivec2(i, 0), 0).rgb;
        if (all(lessThan(abs(c.rgb - m), vec3(tol)))) { idx = float(i); break; }
    }
    if (idx >= 0.0) {
        vec3 a = texelFetch(lut_a, ivec2(int(idx), 0), 0).rgb;
        vec3 b = texelFetch(lut_b, ivec2(int(idx), 0), 0).rgb;
        COLOR = vec4(mix(a, b, blend), 1.0);
    }
}
```
Performance note: a 48-iteration loop per pixel is fine at 640x360 (230k px). For mobile-class targets, pre-bake an index texture instead (R8, value = idx/255) at import time.

---

## 6. Asset generation prompt matrix (PixelLab / generative tools)

Generative tools do not output palette-true, grid-true pixels. The pipeline is: **generate -> quantize to master -> hand-clean -> validate -> import.** Generators are used for drafts, concept silhouettes, texture studies and animation keyframes; final assets are cleaned by hand in Aseprite/Pixelorama.

### 6.1 Global prompt schema
```
[STYLE] cozy hand-painted pixel art, {W}x{H} canvas, 1-pixel outline with selective outlining, limited palette (<=12 colors),
[VIEW] strict orthographic side view, flat 2D, no perspective, no top-down,
[LIGHT] light from upper-left, soft warm key, cool violet shadows, 3-tone shading + 1 highlight,
[SUBJECT] {subject description, material, color names from palette},
[PALETTE] use only these colors: {comma list of hex from master, 8-12},
[BG] transparent background (single flat #ff00ff key color if transparency unsupported),
[FRAME] centered, feet/base on bottom edge, 2px margin, {frames} frames if sprite sheet (equal cell size {cw}x{ch}),
[MOOD] cozy, storybook, toy-like, charming, weathered but tidy
```
Keep each prompt in this order; place constraints early (models weight early tokens).

### 6.2 Global negative constraints (append to every prompt / "negative prompt" field)
```
blurry, anti-aliased, smooth gradient, soft edges, photorealistic, 3D render, isometric, top-down, perspective, vanishing point,
dithering noise, film grain, jpeg artifacts, glow bloom, drop shadow, text, watermark, signature, UI, frame border,
mixed pixel sizes, upscaled pixels, half-pixels, semi-transparent pixels, harsh black outline everywhere, pure black #000000, pure white #ffffff,
neon colors, oversaturated, gradient background, cast shadow on ground, realistic proportions, anime, chibi big sparkle eyes,
asymmetric tiles, seams, cropped, extra limbs, duplicated objects, tilted camera, rotated, motion blur
```

### 6.3 Light angle and consistency block (paste verbatim)
```
LIGHT RULE: single key light from the upper-left at 45 degrees. Highlights on top-left edges, shadow on bottom-right edges.
Interior scenes: additional warm radial light from the lamp (gold #f2b441 / #ffe69a) - lit side faces the lamp.
SIDE-VIEW RULE: camera is level with the subject's midpoint, orthographic, no foreshortening of the top plane;
ground is a thin 2-3px ledge, objects rest on a flat baseline at the bottom of the canvas.
CONSISTENCY: same outline weight (1px), same shading steps (3 tones + highlight), same hue-shift direction
(shadows toward violet #2c3554, lights toward warm cream #e9e4d4) in every asset of the set.
```

### 6.4 Parameter presets (typical PixelLab-style fields)

| Parameter | Keeper | Lighthouse / large | Props | Tiles | Lens |
|---|---|---|---|---|---|
| Canvas | 32x48 | 96x232 (generate 128x256, crop) | 16x16 - 48x32 | 16x16 | 128x128 |
| Outline | single color outline | selective | selective | none/selective | selective |
| Shading | medium | detailed | basic/medium | basic | detailed |
| Detail | medium | high | low-medium | low | high |
| View | side | side | side | side | front (orthographic) |
| Direction | east (flip for west) | n/a | n/a | n/a | n/a |
| Seed policy | lock seed per character; reuse reference image | per set | per set | per set | per asset |
| Reference image | approved concept keeper sheet | master tower sheet | style reference prop sheet | tile reference sheet | lens reference |
| Colors | init image = palette swatch strip | same | same | same | same |

Always feed a **palette swatch strip image** (the 48 colors as 8x8 blocks in a 384x8 PNG) as a color reference/init when the tool supports "color reference" or "init image". Generate at the **exact target resolution** whenever the tool supports it; if it does not, generate at a multiple (4x/8x) and **nearest-neighbor downsample** with block-sampling (not bicubic).

### 6.5 Per-asset prompt templates

#### 6.5.1 Keeper (character)
```
cozy hand-painted pixel art character, 32x48 canvas, side view facing right, toy-like 3-head proportions, big round head with wool cap
(#a03a3a), tiny dot eyes (#0b0e1a), rosy cheeks (#d9684f), skin (#e8b394), yellow oilskin coat (#f2b441 with shade #c8802c), navy trousers (#2c3554),
brown boots (#5e3a2c), striped scarf, holding a small lantern in the left hand, 1px selective outline (#1a2036),
light from upper-left, cool violet shadows, 3 tones plus 1 highlight, transparent background, feet on bottom edge, centered,
{ANIMATION: idle 4 frames | walk 6 frames | ...}, sprite sheet with equal 32x48 cells
NEGATIVE: <global negative> + realistic anatomy, long legs, tall, fashion, detailed face, eyelashes, hair strands
```
Animation workflow: generate **idle keyframe** first; lock; for walk, use the tool's skeleton/pose animation with the keeper as reference, then hand-fix contact frames. Keep head position within +/-1 px between frames.

#### 6.5.2 Lighthouse (exterior segments)
```
cozy storybook pixel art lighthouse tower segment, 96x24 module, side view orthographic, whitewashed stone (#e9e4d4 base, #b4bfd6 shade,
#7d8bab deep shade, #fffaf0 highlight), curved tower wall rendered as vertical bands narrowing 1 px per 24 px, red painted stripe
(#a03a3a, shadow #5a1f2e, highlight #d9684f), mortar lines every 8 px, light from upper-left, 1px selective outline darker than local shade,
no perspective, transparent background, tileable vertically
VARIANTS: base-with-door | plain | window | stripe | gallery-balcony | lantern-room | roof-cap
```
Compose by stacking modules; verify column alignment at seams (left/right edges must match across variants). Lantern room: separate 96x72 piece with glass `sea-glass`/`chalk` panes and `lamp-white` glow when lit.

#### 6.5.3 Fresnel lens (interior hero)
```
pixel art Fresnel lighthouse lens, 128x128, front orthographic view, concentric brass rings (#c9a15a, #94603a shade, #ffe69a highlight),
glass prisms in sea-glass tones (#94d0d0, #52a2b8, #fffaf0 glints), central lamp core glowing (#fffaf0 -> #ffe69a -> #f2b441),
radial symmetry, 1px outline #3a2a22 selective, light from upper-left plus warm radial glow from center, transparent background
FRAMES: 16 rotation frames, 22.5 degrees step, identical silhouette, only prism highlights move
```
Prefer building the lens procedurally (ring math) and use the generator only for prism highlights. Rotation is faked via highlight shifts on a static silhouette; keeps pixels exact.

#### 6.5.4 Props
```
cozy pixel art prop, {W}x{H}, side view, {object}, {materials with hex}, 3 tones + 1 highlight, 1px selective outline,
light from upper-left, sits on a flat baseline at the bottom edge, transparent background, charming slightly oversized silhouette
```
Prop list and canvas sizes:

| Prop | Size | Key colors |
|---|---|---|
| Oil lantern (lit/unlit) | 16x16 | brass, lamp-gold, ink |
| Wooden crate / barrel | 16x16 / 16x24 | oak, driftwood, dune |
| Rowboat | 48x24 | brick-dark, oak, driftwood |
| Bench | 32x16 | oak, driftwood |
| Telescope on tripod | 24x32 | ui-brass, driftwood, mist |
| Cocoa mug | 8x8 | salt, driftwood, signal-coral |
| Rope coil | 16x8 | dune, sandstone |
| Cat / gull companion | 16x16 | salt/fog/granite |
| Oil can, brass polish, cloth | 8x8 | brass, fog |
| Potted plant, flowerbox | 16x16 | moss, meadow, signal-coral |
| Barometer, clock (indoor) | 16x16 | ui-brass, chalk |
| Logbook, quill, desk lamp | 16x8 to 24x16 | ui-parchment, ui-ink |

#### 6.5.5 Tiles
```
seamless 16x16 pixel art tile, {material}, orthographic side-view ground or wall tile, tileable on all four edges, 3 tones + 1 accent,
palette {hex list}, light from upper-left, no outline, no perspective, no unique focal object crossing edges, transparent only where autotile edge requires
SET: autotile 47-blob (top-left light), plus 4 random variants, plus top-edge grass lip and cliff face
```
Rules for tiles: edge pixels at x=0/x=15 must match opposite edge; check with Pixelorama `check_seamless_tile`. Never include light-direction-dependent shading that flips when tiled; light is baked top-left uniformly.

Tile families: grass, grass-edge, dirt path, cobble, sand, rock face, cliff top, wooden floor, stone floor (interior), wall plaster, wall stone, ladder, stairs (up/down), railing, window, door, roof tile, water surface, wave foam, shore.

#### 6.5.6 Backgrounds / skies
Skies are procedural (section 4.6). Generator may supply cloud sprites only:
```
pixel art cloud, {W}x{H}, flat side view, 3 tones (#fffaf0, #e0f0f4, #9fb4cc), puffy storybook shape, no outline, hard edges, transparent background
```

### 6.6 Variant matrix (what to generate per time-of-day)
Time of day is a palette remap, so **do not generate per-time variants** except for:
- Window glow (day: dark glass; night: `lamp-gold` fill) - 2 sprites.
- Lamp lit/unlit states.
- Wet-ground overlays (storm) - 1 tile overlay at 50 percent dither.

### 6.7 Prompt QA loop
1. Generate 4-8 candidates per asset at target size.
2. Quantize to master palette (nearest in OKLab, no dither) - Aseprite `Remap` or `tools/quantize.py` (below).
3. Clean: isolate-pixel removal, outline fix, ramp fix, selout pass.
4. Run validator. 5. Drop in a test scene against all 6 time palettes. 6. Approve.

### 6.8 Quantizer (draft cleanup)
```python
#!/usr/bin/env python3
# tools/quantize.py  -  usage: python3 tools/quantize.py in.png out.png [docs/lastlight_master.hex]
import sys, math
from PIL import Image
def srgb2lin(c): c/=255; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def oklab(r,g,b):
    r,g,b=map(srgb2lin,(r,g,b))
    l=(0.4122214708*r+0.5363325363*g+0.0514459929*b)**(1/3); m=(0.2119034982*r+0.6806995451*g+0.1073969566*b)**(1/3)
    s=(0.0883024619*r+0.2817188376*g+0.6299787005*b)**(1/3)
    return (0.2104542553*l+0.7936177850*m-0.0040720468*s, 1.9779984951*l-2.4285922050*m+0.4505937099*s, 0.0259040371*l+0.7827717662*m-0.8086757660*s)
pal=[tuple(int(l.strip()[i:i+2],16) for i in (0,2,4)) for l in open(sys.argv[3] if len(sys.argv)>3 else "docs/lastlight_master.hex") if len(l.strip())==6]
lab=[oklab(*c) for c in pal]
im=Image.open(sys.argv[1]).convert("RGBA"); px=im.load(); cache={}
for y in range(im.height):
    for x in range(im.width):
        r,g,b,a=px[x,y]
        if a<128: px[x,y]=(0,0,0,0); continue
        k=(r,g,b)
        if k not in cache:
            L=oklab(r,g,b); cache[k]=min(range(len(pal)),key=lambda i:sum((L[j]-lab[i][j])**2 for j in range(3)))
        px[x,y]=pal[cache[k]]+(255,)
im.save(sys.argv[2])
```

---

## 7. Validation

### 7.1 Checklist (per asset, before import)

- [ ] Exact canvas size per spec (tiles 16x16; keeper cells 32x48; modules multiples of 8)
- [ ] PNG, RGBA, **alpha is only 0 or 255**
- [ ] 100 percent of opaque pixels are in the 48-color master palette (validator exit 0)
- [ ] <= 12 distinct colors (<= 16 for hero art)
- [ ] No orphan pixels except <= 3 intentional glints
- [ ] 1-px outline, no doubled corners, selout applied; lit-side outline lighter than shadow-side
- [ ] Light from upper-left on all faces; shadows cool, lights warm
- [ ] Strict side view; baseline at bottom; anchor bottom-center
- [ ] Pixel size uniform (no 2x2 blocks pretending to be 1x1; check by 2x downsample test: result must not equal the original block pattern everywhere)
- [ ] Tiles: opposite edges match; 3x3 tiling shows no visible seam
- [ ] Animation frames: same canvas, same anchor, head within +/-1 px, silhouette changes per frame, loop is seamless
- [ ] Looks right under all six palettes (screenshot test scene) and at 3x/4x/6x
- [ ] Reads as a silhouette at 1x; feels cozy, not corporate (no hard-edged icon style, no flat-UI gloss)
- [ ] File name follows convention; Aseprite source committed to `art/src/`

### 7.2 Python validator (`tools/validate_palette.py`)
Dependencies: `pip install pillow`. Tested: returns exit code 1 and prints off-palette hex with counts. Needs `docs/lastlight_master.hex` (section 5.1).

```python

#!/usr/bin/env python3
"""Last Light palette conformance checker.
usage: python3 tools/validate_palette.py [--palette docs/lastlight_master.hex] [--tolerance 0] path_or_dir ...
Checks per PNG: (1) every opaque pixel is in the master palette, (2) alpha is binary (0 or 255),
(3) no isolated single-pixel orphans (optional --orphans), (4) dimensions are multiples of 8 (tiles) unless --free-size,
(5) no semi-transparent edges. Exit code 1 on any failure."""
import sys, argparse, pathlib
from PIL import Image

def load_palette(p):
    cols = set()
    for line in pathlib.Path(p).read_text().split():
        line = line.strip().lstrip("#")
        if len(line) == 6:
            cols.add(tuple(int(line[i:i+2], 16) for i in (0, 2, 4)))
    return cols

def near(c, pal, tol):
    return any(max(abs(c[i]-p[i]) for i in range(3)) <= tol for p in pal)

def check(path, pal, tol, orphans, free):
    im = Image.open(path).convert("RGBA"); w, h = im.size; px = im.load(); errs = []
    if not free and (w % 8 or h % 8): errs.append(f"size {w}x{h} not multiple of 8")
    bad = {}; semi = 0; opaque = set()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0: continue
            if a != 255: semi += 1; continue
            opaque.add((x, y))
            if (r, g, b) not in pal and not (tol and near((r, g, b), pal, tol)):
                bad[(r, g, b)] = bad.get((r, g, b), 0) + 1
    if semi: errs.append(f"{semi} semi-transparent pixels")
    if bad:
        top = sorted(bad.items(), key=lambda kv: -kv[1])[:6]
        errs.append("off-palette: " + ", ".join(f"#{r:02x}{g:02x}{b:02x} x{n}" for (r, g, b), n in top) + f" ({len(bad)} distinct)")
    if orphans:
        n = 0
        for (x, y) in opaque:
            if not any((x+dx, y+dy) in opaque for dx, dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1))): n += 1
        if n: errs.append(f"{n} orphan pixels")
    return errs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+"); ap.add_argument("--palette", default="docs/lastlight_master.hex")
    ap.add_argument("--tolerance", type=int, default=0); ap.add_argument("--orphans", action="store_true")
    ap.add_argument("--free-size", action="store_true")
    a = ap.parse_args(); pal = load_palette(a.palette); fails = 0; files = []
    for p in a.paths:
        p = pathlib.Path(p); files += sorted(p.rglob("*.png")) if p.is_dir() else [p]
    for f in files:
        e = check(f, pal, a.tolerance, a.orphans, a.free_size)
        print(("FAIL " if e else "ok   ") + str(f)); fails += bool(e)
        for m in e: print("     - " + m)
    print(f"{len(files)-fails}/{len(files)} passed"); sys.exit(1 if fails else 0)
main() if __name__ == "__main__" else None
```

CI usage:
```
python3 tools/validate_palette.py --orphans art/export
python3 tools/validate_palette.py --palette docs/lastlight_master.hex --tolerance 0 art/export/tiles
```
Use `--tolerance 0` for final assets. Use `--tolerance 6` only on raw generator drafts to see how far they are off.

### 7.3 GDScript editor validator (`res://tools/palette_validator.gd`)
Run from the editor (File > Run, `@tool` + `EditorScript`) to scan `res://art`. Loads the master palette from `res://art/palettes/lastlight_master.hex`.

```gdscript
@tool
extends EditorScript

const PALETTE_PATH := "res://art/palettes/lastlight_master.hex"
const ROOT := "res://art"

func _run() -> void:
    var pal := _load_palette()
    var files: Array[String] = []
    _collect(ROOT, files)
    var fails := 0
    for f in files:
        var errs := _check(f, pal)
        if errs.is_empty():
            print("ok    ", f)
        else:
            fails += 1
            push_warning("FAIL  %s" % f)
            for e in errs: print("      - ", e)
    print("%d/%d passed" % [files.size() - fails, files.size()])

func _load_palette() -> Dictionary:
    var d := {}
    for line in FileAccess.get_file_as_string(PALETTE_PATH).split("\n"):
        var s := line.strip_edges().trim_prefix("#")
        if s.length() == 6:
            d[Color.html(s).to_rgba32() | 0xff] = true  # normalise alpha to 255
    return d

func _collect(dir: String, out: Array[String]) -> void:
    var da := DirAccess.open(dir)
    if da == null: return
    for sub in da.get_directories():
        if sub.begins_with("."): continue
        _collect(dir.path_join(sub), out)
    for f in da.get_files():
        if f.ends_with(".png") and not f.begins_with("bg_sky_"):
            out.append(dir.path_join(f))

func _check(path: String, pal: Dictionary) -> Array[String]:
    var errs: Array[String] = []
    var img := Image.load_from_file(path)
    if img == null: return ["cannot load"]
    img.convert(Image.FORMAT_RGBA8)
    var w := img.get_width(); var h := img.get_height()
    if w % 8 != 0 or h % 8 != 0:
        errs.append("size %dx%d not multiple of 8" % [w, h])
    var bad := {}; var semi := 0; var distinct := {}
    for y in h:
        for x in w:
            var c := img.get_pixel(x, y)
            var a := int(round(c.a * 255.0))
            if a == 0: continue
            if a != 255: semi += 1; continue
            var key := c.to_rgba32() | 0xff
            distinct[key] = true
            if not pal.has(key):
                bad[key] = int(bad.get(key, 0)) + 1
    if semi > 0: errs.append("%d semi-transparent pixels" % semi)
    if not bad.is_empty(): errs.append("%d off-palette colors, e.g. #%s" % [bad.size(), Color.hex(bad.keys()[0]).to_html(false)])
    if distinct.size() > 16: errs.append("%d distinct colors (max 16)" % distinct.size())
    return errs
```
Note: `Color.to_rgba32()` returns 0xRRGGBBAA; OR-ing `0xff` sets alpha to 255 so palette and image keys compare equal.

### 7.4 In-game guard (debug builds)
At startup in debug builds, the loader may assert that every `Texture2D` in `res://art` was imported lossless, filter off, and that `ProjectSettings.get_setting("display/window/size/viewport_width") == 640`. Add a debug overlay (F3) drawing the 16-px grid and 8-px prop grid, plus a readout of `Engine.get_main_loop().root.content_scale_factor` / integer scale, to catch subpixel drift early.

### 7.5 Visual regression
Render each time-of-day screenshot (640x360 SubViewport capture, not window capture) for 3 reference scenes (exterior, lantern room, stairwell) and diff against stored PNGs with zero tolerance; any 1-px diff in non-animated regions fails. This catches accidental filtering, fractional camera positions and shader drift.

---

## 8. Open questions / risks for other agents

1. **Row 22.5:** 360/16 is fractional. Recommendation: author interiors as 40x22 tiles (352 px) + an 8-px band for sky/floor trim, or design the bottom 8 px as a deliberate HUD/ground strip. Level and UI agents should confirm.
2. **Left-hand lantern mirroring:** flip-H places the lantern in the right hand for left-facing. Accepted for toy-like charm; alternative is a drawn left sheet (+80 frames).
3. **Generator reliability:** current pixel-art generators drift in character proportion across animation frames; budget manual fixing at roughly 30 percent of frames. Keeper walk should be hand-authored from the idle keyframe.
4. **Palette-shift LUT shader** needs an index lookup; alternative is baking index maps at import (cheaper, preferred for mobile/web exports).
5. **Sky colors** (section 4.6) are outside the 48-color remap; if a strict "one palette" rule is wanted, quantize sky to the nearest of the 48 slots per time (loses smoothness; bands will look chunkier, which may still be charming).
6. **High-DPI 4K:** at 6x each source pixel is 6x6 screen px; ensure window/borderless fullscreen picks integer scale, and decide whether to show a thin `void` border or a decorative frame in the letterbox of non-16:9 monitors (recommended: decorative parchment/ocean frame texture, drawn at screen res outside the 640x360 viewport).

## 9. File manifest produced by this spec

| Path | Purpose |
|---|---|
| `docs/lastlight_master.hex` | master 48 palette, one hex per line (section 5.1) |
| `art/palettes/lastlight_master.gpl` | editor palette (section 5.2) |
| `art/palettes/lut_<time>.png` x6 | 48x1 palette-shift LUTs from `tools/make_luts.py` |
| `tools/validate_palette.py` | CI validator |
| `tools/quantize.py` | draft quantizer |
| `tools/palette_validator.gd` | in-editor validator |
