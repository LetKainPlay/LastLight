# AGENT 09: Nautical Authenticity and Diegetic UI

Project: **Last Light**. Godot 4.7.2, GDScript 2.0, static typing. Cozy, high-detail pixel art, one island lighthouse.

Scope: (A) what a 19th and early 20th century keeper really did all day, rewritten as stress-free mini-interactions; (B) a fully diegetic interface (no floating HUD) with specs, node trees, code and accessibility fallbacks.

Confidence markers used throughout:

- **[Solid]** well documented, safe to state in-game.
- **[Likely]** consistent across sources I know, but numbers vary by country and station; treat as design values.
- **[Verify]** I am not certain; confirm before putting it in a codex entry or marketing copy.

Guiding rule: *authentic texture, forgiving stakes.* Real keepers faced fire, poisoning, drowning and isolation. The game keeps the rituals, the objects, the vocabulary and the satisfaction, and removes the failure states that punish. Nothing in this document produces a fail screen, a timer bar or a red number.

---

## Part A. The Keeper's Day

### A0. Historical frame

| Period | What it means for the game |
|---|---|
| 1822-1823 | Augustin Fresnel's lens: first major installation at Cordouan, France, 1823. **[Solid]** |
| 1830s-1860s | Argand lamps with concentric wicks, colza or sperm oil, clockwork rotation. **[Solid]** |
| 1860s-1870s | US shifts from sperm oil toward lard oil; mineral oil (kerosene, "paraffin" in British usage) spreads in the 1870s-1880s. **[Likely]**, exact years differ by country. |
| 1880s-1890s | Mercury float baths for heavy rotating lenses become common. **[Likely]** |
| c. 1900-1910 | Incandescent oil vapor (IOV) burners with mantles replace wick lamps at many stations. **[Likely]** |
| 1900s-1930s | Electrification and automation begin; keepers slowly become rare. |

**Recommended default setting for the game:** a fictional island, c. 1895-1910, which lets every technology below coexist in one station (an upgrade path the player can slowly walk through). Do not name a real nation's lighthouse service. Use the neutral title "the Service" and "the Inspector".

### A1. A day's rhythm (compressed)

Real keepers lived by sunset and sunrise. The lamp was lit at sunset and extinguished at sunrise, and everything else was arranged around that. **[Solid]**

| Time | Real duty | Game beat |
|---|---|---|
| Sunrise | Extinguish lamp, draw linen curtains over the lantern glass, log it | "Dousing the Light" (A2 ritual 1) |
| Morning | Clean lens, polish brass, wash lantern panes, fill lamp reservoirs, trim spare wicks | Cleaning and tending interactions |
| Midday | Repairs, painting, stores, signals to passing vessels, meals, weather readings | Free time, crafting, island chores |
| Afternoon | Prepare lamp, wind clock, check oil, inspect | "Readying the Lamp" |
| Sunset | Remove curtains, light lamp, start clockwork | "Lighting Up" (headline ritual) |
| Night | Watches, wick trimming, winding, logbook, fog signal if needed | Night watch loop |

Why the curtains matter: sunlight passing through a Fresnel lens is concentrated to a hot focus and can scorch furniture or start a fire, so lenses were covered by curtains in daytime. **[Solid]** This is wonderful game material: the player's first sunrise task is *drawing the curtains*, a satisfying cloth-on-rail interaction that also teaches the lens is powerful.

### A2. Duties and their stress-free mini-interactions

For each duty: real practice, accuracy confidence, game translation, then a specific interaction spec. All interactions share these rules:

1. **No fail state.** The worst outcome is a slightly slower result or a gentle keeper's mutter ("Not quite. Again, then.").
2. **No timers visible.** Windows of time are conveyed by the world (light angle, bell strikes), never by a bar.
3. **One input verb per interaction** (hold, drag in a loop, click to the beat, tap-tap). Controller and keyboard parity.
4. **Skippable via "Ease" setting** which turns any interaction into a single press with the same animation. Never removes the reward.
5. **Tactile feedback:** audio first (cloth squeak, brass click), small particles second, UI text never.

#### A2.1 Fresnel lens orders

Fresnel lens sizes were classified in "orders" by the focal distance (distance from the lamp flame to the inner lens surface). Larger orders are bigger and stronger. Commonly quoted focal distances: **[Likely]**

| Order | Approx. focal distance | Typical use | Game use |
|---|---|---|---|
| Hyper-radial | ~1330 mm | Very big coastal/landfall lights (Chance Brothers design, 1880s) **[Verify date and exact figure]** | Late-game "grand" lens, wing of the unlock tree |
| Meso-radial | ~1000 mm | Between hyper-radial and 1st order **[Verify]** | Optional mid upgrade |
| 1st order | 920 mm | Major seacoast lights | Main late tier |
| 2nd order | 700 mm | Coastal | |
| 3rd order | 500 mm | Coastal / large harbor | |
| 3.5 order | 375 mm | **[Verify]** US-specific intermediate size | skip unless USA-flavored |
| 4th order | 250 mm | Harbors, bays | Starting tier candidate |
| 5th order | 187.5 mm | Harbors | |
| 6th order | 150 mm | Small harbors, lakes | Possible tutorial lens |

Other lens vocabulary:

- **Fixed vs revolving.** A fixed lens gives a steady beam all around. A revolving lens uses flash panels (bullseyes) that sweep, producing flashes; the *characteristic* (e.g. "flash every 10 seconds") identifies the light. **[Solid]**
- **Bullseye (bull's-eye).** The central round lens of a flash panel. **[Solid]**
- **Catadioptric prisms.** Rings above and below the main lens that bend light by reflection and refraction toward the horizon. **[Solid]**
- **Biform (bi-form) and "double" lenses.** A lens with two tiers of optic panels stacked, with two flames/burners, to give a more powerful or differently-patterned beam. Chance Brothers produced multi-tier optics; the term "biform" also appears in catalogs. **[Verify]** the exact usage; for the game treat "biform" as *"two-tier lens, two burners, stacked flash panels"* and flag it as a codex-level approximation. The same caution applies to **"hyper-radiant"** (a spelling variant that appears alongside "hyper-radial"). **[Verify]** which is right for the intended source; the commonly cited British term is *hyper-radial*.

**Game translation: "The Order of the Lens."** Tiers of lens as cozy progression. The player never "levels up a stat" in a menu. A new lens arrives crated by supply boat; unpacking it, assembling the brass pedestal, and placing prisms ring by ring is the upgrade. The beam's reach is seen from the sea in the telescope view, not in a number.

**Mini-interaction spec: "Setting a Prism Ring"**

- Input: drag a prism ring (crate) toward the pedestal; it snaps with a soft magnetic ease when within 24 px.
- Feedback: glass chime, a small rainbow caustic on the floor.
- Failure: if released off target, the ring floats back gently (no drop, no crack).
- Duration: ~6 s per ring, 4-12 rings per lens order.
- Ease mode: one-press auto-place, same chime.

#### A2.2 Lens cleaning (soft cloths, rouge, alcohol)

Practice: lens glass was dusted with a soft brush or feather duster, washed with a damp cloth, then polished with soft linen or chamois; alcohol (spirit) was used to cut grease and soot, and fine polishing powder (**rouge**, also called jeweler's rouge, or **tripoli**) for final shine. Keepers were cautioned against anything abrasive on the glass and against touching the lens with bare hands. Brass was polished with rottenstone or similar. **[Likely]**, specific compounds varied by service. Always keep the cleaning compound list "soft" in the game.

Soot (lampblack) buildup is real and was the daily enemy. **[Solid]**

**Game translation:** a calm circular wiping motion where the glass visibly clears and gains a shimmer. The satisfaction is the visual shine bloom, not scoring.

**Mini-interaction spec: "Polish the Lens"**

- Verbs: pick cloth (soft linen), dab alcohol from a small stoppered bottle (optional step, visual only), hold-and-circle with mouse or right stick over a prism.
- State per prism panel: `grime` 0.0..1.0. Wiping reduces grime by speed-independent amount (no penalty for being slow or fast).
- Shader: a mask texture of grime; wiping paints into the mask with soft brush.
- Rouge step (late): a pinch of red-brown powder on a clean cloth, a second light pass; the panel gets a tiny sparkle pixel pattern.
- Audio: squeaky-glass loop whose pitch rises as grime falls.
- No "missed spot" penalty. The keeper says one line when the last pane is clear.
- Ease: hold one button over a panel; it cleans over 1.5 s.

```gdscript
# lens_panel.gd -- soft, forgiving polish interaction
class_name LensPanel
extends Area2D

signal polished(panel: LensPanel)

@export var grime_mask: Image
@export_range(1, 32) var brush_radius: int = 10
@export_range(0.0, 1.0) var wipe_strength: float = 0.18

var _tex: ImageTexture
var _grime: float = 1.0 # 0 clean, 1 sooty
var _last_pos: Vector2 = Vector2.ZERO
var _wiping: bool = false

@onready var _sprite: Sprite2D = $Glass
@onready var _sfx: AudioStreamPlayer2D = $WipeSfx

func _ready() -> void:
	grime_mask = Image.create(64, 64, false, Image.FORMAT_R8)
	grime_mask.fill(Color(1, 1, 1, 1))
	_tex = ImageTexture.create_from_image(grime_mask)
	(_sprite.material as ShaderMaterial).set_shader_parameter("grime_mask", _tex)

func _input_event(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_wiping = (event as InputEventMouseButton).pressed
		_last_pos = to_local((event as InputEventMouseButton).position)
		if not _wiping:
			_sfx.stop()
	elif event is InputEventMouseMotion and _wiping:
		var p: Vector2 = to_local((event as InputEventMouseMotion).position)
		_wipe_segment(_last_pos, p)
		_last_pos = p

func _wipe_segment(a: Vector2, b: Vector2) -> void:
	var steps: int = maxi(1, int(a.distance_to(b) / 2.0))
	for i: int in steps + 1:
		var q: Vector2 = a.lerp(b, float(i) / float(steps))
		_stamp(Vector2i(q / 4.0 + Vector2(32, 32))) # mask is 64x64 over a 256 px panel
	_tex.update(grime_mask)
	if not _sfx.playing:
		_sfx.play()
	_sfx.pitch_scale = lerpf(0.8, 1.3, 1.0 - _grime)
	_recompute()

func _stamp(c: Vector2i) -> void:
	for y: int in range(-brush_radius / 4, brush_radius / 4 + 1):
		for x: int in range(-brush_radius / 4, brush_radius / 4 + 1):
			var px := Vector2i(c.x + x, c.y + y)
			if px.x < 0 or px.y < 0 or px.x >= 64 or px.y >= 64:
				continue
			var v: float = grime_mask.get_pixelv(px).r
			grime_mask.set_pixelv(px, Color(maxf(0.0, v - wipe_strength), 0, 0, 1))

func _recompute() -> void:
	var total: float = 0.0
	for y: int in 64:
		for x: int in 64:
			total += grime_mask.get_pixel(x, y).r
	_grime = total / 4096.0
	if _grime < 0.04:
		polished.emit(self)
```

Companion canvas_item shader sketch (grime darkens and desaturates the glass; clean glass gets a shimmer):

```glsl
shader_type canvas_item;
uniform sampler2D grime_mask : filter_linear, repeat_disable;
uniform vec4 soot_color : source_color = vec4(0.12, 0.10, 0.08, 1.0);
uniform float shimmer : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float g = texture(grime_mask, UV).r;
	vec3 col = mix(base.rgb, soot_color.rgb, g * 0.75);
	float sparkle = (1.0 - g) * shimmer * step(0.985, fract(sin(dot(floor(UV * 64.0), vec2(12.9898, 78.233))) * 43758.5453 + TIME * 0.5));
	COLOR = vec4(col + vec3(sparkle), base.a);
}
```

#### A2.3 Mercury float baths (and why a modern game should treat it gently)

Practice: from roughly the 1890s, large revolving lenses weighing a ton or more floated on a trough of liquid mercury so a single hand or small motor could rotate them smoothly with little friction. **[Likely]** A keeper skimmed and filtered the mercury occasionally, kept the trough covered, and watched the level. Mercury vapor and handling caused chronic poisoning in some keepers (tremors, mood change, "mad hatter" style symptoms); modern lighthouse conservation treats old mercury baths as hazardous. **[Solid]** that mercury is toxic; **[Verify]** the extent of documented keeper illness before citing a specific station.

**How to treat it in a cozy game (design decisions):**

1. **Never show harmful consequences.** No sickness meter, no keeper tremor, no spilled-mercury hazard.
2. **Reframe the player's action as observing and tidying, not handling.** The player never pours or touches liquid metal.
3. **Name it honestly in the codex, with a gentle note:** "Quicksilver. Old keepers swore by it and, we now know, paid for it. Your trough is sealed, and the lid stays on."
4. **Offer a safer-fiction alternative toggle?** Not needed. An oiled-bearing / roller-ring version is an authentic alternative (many lenses sat on roller bearings). The game can *start* with roller-ring lens bases and treat the sealed mercury float as a stately late-game "marvel", visible only as a silver glimmer under a glass inspection plate.

**Mini-interaction spec: "Check the Float"**

- Input: lift hinged brass inspection lid (click), look through a small glass window at a silvery level line.
- Needle-style level: a tiny brass pointer in a glass gauge reads "full" when the trough is good.
- If low: a note appears in the logbook ("float wants topping; ask the supply boat"). The *supply boat* supplies it. The player never decants the metal.
- Closing the lid: click, satisfying brass latch. Done.
- The lens then turns with a hushed, near-silent glide; this is the reward (a low rolling sound, no mechanical grind).
- Ease: not needed (already one click). Content-warning-style toggle: "Use roller-bearing base" swaps the visual with identical gameplay.

#### A2.4 Wick trimming

Practice: wick lamps (Argand type, 1780s, with a central draught and one to four concentric wicks) needed regular trimming so the flame stayed even, smokeless and bright. Wicks were trimmed square or lightly rounded with special scissors, charred crust removed, and heights adjusted by a rack-and-pinion knob. Trimming happened at lighting-up and again through the night, roughly every few hours (varied by station and wick count). **[Likely]**, no single universal interval.

Smoking flames meant soot on the lens, so trimming and cleaning are connected. **[Solid]**

**Game translation:** a lens-side lamp view with concentric wick rings; a flame wavering. Nudge each ring's height with a small mouse-wheel/trigger; the flame shape changes from lopsided to a clean, tall teardrop.

**Mini-interaction spec: "Trim the Wick"**

- Input: open lamp door (click). Mouse wheel (or LB/RB) over a wick ring to raise it; hold Shift-click (or A) to snip crust.
- Feedback: flame shape cycles through `smoky → ragged → even → bright` as the max difference between wick heights falls below a tolerance of 0.15 units.
- No overshoot penalty. Over-raising simply smokes a bit more; lowering it back is free.
- Sound: tiny scissor `snip`, soft hiss as flame steadies.
- Ease: one click does "trim all," animates all four scissors.

#### A2.5 Fuels: tallow, colza, lard, kerosene (paraffin) and the IOV burner

| Fuel | Era in the game | Character | Smell / look cue |
|---|---|---|---|
| Tallow candles and tallow | Oldest; pre-1800 and as emergency fallback | Smoky, soft, needs frequent snuffing | Greasy sheen; amber glow |
| Whale (sperm) oil | Early-mid 19th c., costly | Clean, bright **[Solid]** | Honey-coloured |
| Colza (rapeseed) oil | Common in Europe from the 1820s on **[Likely]** | Bright, slightly cooking-oil smell | Pale gold |
| Lard oil | US lights from about the 1860s-1870s **[Likely]** | Needed warming in cold weather so it flowed | White, congealing in cold |
| Mineral oil: kerosene (US) / paraffin (UK) | 1870s-1880s on **[Likely]** | Cheaper, very bright, brought fire risk | Clear, strong smell |
| Incandescent oil vapor (IOV) | c. 1900 on **[Likely]** | Oil vaporized under pressure, burned in a mantle for a white, intense light | Hissing blue-white flame |

"Colza" and "paraffin" are the right period names for their regions; the **glossary** (A5) pins the usage.

**Game translation: "Fuel Day."** Fuel arrives in labeled kegs; the player chooses what goes in the lamp reservoir according to what they have. Different fuels subtly change the flame color/grain, soot rate and smell; the economy is coziness, not scarcity.

**Mini-interaction spec: "Fill the Reservoir"**

- Input: pick a keg (click), tip a brass can, hold-click to pour; level rises in the reservoir glass.
- Auto-stops at the "full" line with a soft clink (can't overfill).
- Lard oil special beat (cold nights): warm the can on the stove for 3 s. Hold on stove; steam wisp; optional but pleasant. If skipped, the oil pours slowly, which is cozy-slow, not punishing.
- Spill rule: none. Small drips on the floor are only decorative and wipe away on their own by morning.

**IOV burner: "Light the Vapor Lamp"** (hand-pumped pressure, spirit pre-heat)

Real sequence **[Likely]** (details differ by maker such as Hood or Kitson; **[Verify]** model-specific steps): fill a small oil tank, pump to build pressure, pre-heat the vaporizer with a spirit (methylated spirit / alcohol) torch for a minute or two, open the oil valve, the vapor ignites in the mantle, adjust until a steady white glow. A cold mantle is fragile; a new mantle is burned in carefully (first burn turns the fabric to ash and leaves a fragile ceramic-like lattice).

Spec:

1. Pump the plunger (tap `Space` or left-right arrow alternately, or bobbing mouse wheel) 6-10 times. A pressure needle lives on a tiny brass gauge on the burner (diegetic).
2. Hold the spirit torch under the vaporizer cup for ~2 s of the animation (a progress is shown by the cup color going from steel to dull red).
3. Turn the valve (rotate mouse around the knob). A soft *pop*, a hiss, and the mantle blooms white.
4. If the pressure is too low or it is too cold, the flame simply flutters and gives a "wuff"; the player pumps once more. No explosions, no injury.
- Ease mode: one press runs the whole sequence with the same animation.

#### A2.6 Clockwork winding

Practice: first-order revolving lenses were turned by a clockwork driven by a heavy weight falling down a shaft in the tower. The keeper wound the weight back up with a crank, with intervals that depended on drop height and the lens' mass; often every few hours, with the rule that it should never run out during the night. A governor controlled speed. **[Likely]** Commonly cited winding intervals range from roughly 2 to 8 hours, with about 4 hours often quoted. **[Verify]** per station. For the game: "wind every watch", which means twice a night, plus once in the evening before lighting.

**Mini-interaction spec: "Wind the Clockwork"**

- Input: grasp the crank (click and hold), rotate circularly with the mouse or right stick. Each full turn lifts the weight by one visible tick.
- A ratchet pawl gives a satisfying *tick-tick-tick* that gets slightly quieter and faster as you near the top.
- A brass pointer on the weight shaft shows how far up it is (diegetic), and a bell tings softly at the top.
- If the player stops early, nothing bad happens; the lens simply makes a slightly longer rotation period (the beam cadence in the telescope slows by a tiny, forgiving amount, e.g. +10%).
- Ease: hold one button, crank turns itself.

#### A2.7 Logbook conventions

Practice: lights kept a daily journal, in ink, in fixed columns or running prose, entries signed or initialed; mistakes were struck through, never erased. **[Likely]** Typical items: date; lamp lit at sunset and extinguished at sunrise (with the times); weather (wind direction and force; sea; visibility; barometer, thermometer); vessels sighted (name, rig, direction); visitors; supplies received; repairs; fog signal start/end; illness or wrecks; inspections (the Inspector's visit and his remarks). Phrases in the style of "Lighted at sunset. Extinguished at sunrise. Wind NW, moderate. Clear." **[Solid]** style, **[Verify]** any official wording.

Wind force: the Beaufort scale (devised 1805; used by the Royal Navy from the 1830s). **[Solid]** Use "light air", "gentle breeze", "fresh breeze", "strong gale", etc.

**Mini-interaction spec: "Write Up the Log"**

- Input: pick up pen (hover/click on inkwell), then click the logbook. The game pre-writes today's entry from what actually happened (lamp times, weather from barometer, passing ships); the player chooses 1-3 optional phrases from a small stack of "remarks" cards (wooden tray beside the book), e.g. "Gulls restless." / "Tea with the supply-boat man." / "Fog thick towards dawn."
- Handwriting reveals line by line (code below), with a soft nib scratch.
- A signature flourish at the end of each day (the player's mark; customizable in character creation).
- Strike-through: if the player re-picks a remark, the earlier line gets a neat strike-through (authentic) rather than being deleted.
- No required fields; an empty day gets the auto entry plus "All well."

#### A2.8 Watch schedules

Practice: stations with several keepers divided the night into watches (e.g. sunset to midnight, midnight to sunrise), each keeper tending the light, trimming the wick, winding the clock, keeping the log and watching for vessels and fires. Rock and tower stations used three or four keepers; shore stations often one or two with family support. Typical 4-hour watch granularity (nautical watches: first watch 20:00-00:00, middle watch 00:00-04:00, morning watch 04:00-08:00). **[Likely]** for the nautical division; **[Verify]** per service.

**Game translation:** the player is the sole keeper, but the day's rhythm is expressed in bell strikes (ship's bell convention: one bell per half-hour of a four-hour watch, up to eight bells). **[Solid]** for ship's bell convention; lighthouses did not necessarily use it. We borrow it for the soundtrack of the hour.

**Mini-interaction spec: "Take the Watch"**

- Sit in the lantern-room chair. The screen is not blocked; the player may leave the chair any time. In the chair, the sea and sky pass at gently accelerated rate (watching the horizon with sipping tea).
- Each half-hour: a bell strike rings from the room's small brass bell (diegetic timekeeping).
- Optional "ship sighted" events appear in the telescope, never as pop-ups. A kettle whistles when tea is ready.
- Sleeping through the night is allowed by "Ease/Rest" and the island runs a short cozy cutscene (the beam sweeping across the sea). Morning arrives with a soft "The light held, Keeper."

### A3. A day, as a loop (design table)

| Phase | Mini-interactions | Typical duration (real) | Reward |
|---|---|---|---|
| Dawn | Douse light, draw curtains, log | 2 min | Sunrise cutscene, gull audio |
| Morning | Polish lens, polish brass, fill reservoirs | 5-8 min | Shine bloom, new log line |
| Midday | Garden, repairs, signal flags, tide walk | free | Items, letters |
| Dusk | Wind clock, light the lamp | 3-4 min | The headline beam moment |
| Night | Watch chair, trim, wind, log | 4-6 min | Ships, stars, weather |

### A4. Stress-removal toolbox

- Replace fail with *flavor*: dim lens means a dimmer beam on distant ships, not a game over.
- Use the "Keeper's Mutter": a single line of low-key dialogue as feedback.
- Offer "Ease" per mini-interaction (A2 rules).
- Log forgiveness: the logbook never records the player's failures, only the pleasant facts.
- Weather has moods but never danger. Storms are a spectacle: shutters, rain, waves; the lamp still shines.

### A5. Glossary

| Term | Meaning |
|---|---|
| Argand lamp | Lamp with a hollow circular wick and central air draught (1780s). Gives a bright, clean flame. |
| Aneroid barometer | Barometer using a sealed metal cell (Vidi, 1844); the brass dial type used in homes and stations. |
| Biform | Lens or optic with two tiers; **[Verify]** exact meaning per maker. |
| Bullseye | Central round lens of a flash panel. |
| Catadioptric | Using both reflection and refraction; the prisms above and below a Fresnel lens. |
| Characteristic | A light's identifying pattern: flashes, groups, occultations, colors. |
| Colza | Rapeseed oil used as lamp fuel. |
| Dioptric | Using only refraction; the central lens drum. |
| Fixed light | A steady light visible all around. |
| Flash panel | A rotating lens segment that makes a single flash per rotation. |
| Focal distance | Distance from flame to inner lens surface; defines lens order. |
| Governor | Fan or flyball mechanism regulating clockwork speed. |
| Hyper-radial | Largest standard lens size, ~1330 mm focal distance (British design). **[Verify]** |
| IOV | Incandescent oil vapor burner. |
| Journal / logbook | The station's daily record. |
| Lampblack | Soot. |
| Lantern room | Glazed room at the top of the tower holding the lens. |
| Mantle | Fragile ceramic-oxide hood glowing white when heated (Welsbach, 1880s). |
| Mercury float | Trough of liquid mercury floating the rotating lens. Toxic. |
| Meso-radial | Size between 1st order and hyper-radial. **[Verify]** |
| Occulting light | Light that is steady with brief eclipses. |
| Order (lens) | Size class of Fresnel lens, 1st (largest in the classic series) to 6th. |
| Paraffin | British name for kerosene. |
| Pedestal | Stand supporting the lens and clockwork. |
| Rouge | Fine iron-oxide polish powder. |
| Rottenstone | Soft abrasive for metal polishing. |
| Tripoli | Fine abrasive polishing earth. |
| Watch | A duty period, traditionally four hours. |

---

## Part B. Diegetic UI

### B0. Principles

1. **Zero floating HUD.** No health bars, minimap, quest arrows, tooltips pinned to the screen edge, or button prompts hanging in air.
2. **Every number lives on an object.** Time on a clock; pressure on a barometer; tide on a printed table; wind on a vane/log; supplies in the cupboard; tasks in the logbook.
3. **Objects are real places.** Each interface is a node in the world. The camera moves to it (a soft "lean in" zoom), the rest dims lightly, and Esc/B steps back.
4. **Input prompts are physical.** A small hand-lettered tag on the object, or the cursor itself changing to a hand/pen/cloth, instead of a glyph overlay. Controller glyphs only appear *in the logbook's margin* in the Controls page (see B7).
5. **Every interface has an idle look.** A barometer on the wall is already useful at a glance without being opened.
6. **Nothing is empty.** Unavailable objects are absent (no ghost slots). The tide table appears when the player first buys/receives one.

### B1. Interface inventory

| Info / action | Diegetic object | Where | Idle read | Open interaction |
|---|---|---|---|---|
| Weather trend | Brass aneroid barometer | Wall by the door | Needle position + "Fair / Change / Rain / Storm" engraved | Tap glass to nudge needle (real practice), see the red "set hand" |
| Time of day | Brass wall clock | Kitchen wall and lantern room | Hands + chime | Wind it (key) |
| Journal / tasks / save | Handwritten logbook | Oak desk | Closed book with ribbon marker | Page through; written entries serve as quest log and journal |
| Spotting ships, far objects | Brass telescope | Gallery window / lantern | Telescope on stand | Reticle view (B5) |
| Tides | Printed tide table | Pinned beside the desk | Rows of times | Finger-follow the day's row |
| Signals | Signal flag locker | Gallery hatch | Numbered pigeonholes | Pick and hoist flags |
| Inventory | Cupboard, trunk, workbench | Kitchen / workroom | Visible shelves | Click items directly |
| Settings | Maintenance chest "The Keeper's Notions" | Under the stairs | Small trunk | Cards inside (B7) |
| Pause | Steam from a mug, pocketwatch | Desk | Pause = close pocketwatch lid | `Esc` |

### B2. Scene structure

```
Main (Node)
└── World (Node2D)
    ├── Interiors (Node2D)
    │   ├── KitchenRoom (Node2D)
    │   │   ├── WallClock (Interactable) -> see B3
    │   │   ├── Barometer (Interactable) -> see B4
    │   │   └── TidePin (Interactable)
    │   ├── StudyRoom (Node2D)
    │   │   ├── OakDesk (Node2D)
    │   │   │   ├── Logbook (Interactable) -> see B6
    │   │   │   ├── Inkwell (Interactable)
    │   │   │   └── RemarksTray (Node2D)
    │   │   └── FlagLocker (Interactable)
    │   └── LanternRoom (Node2D)
    │       ├── Lens (Node2D)
    │       ├── ClockworkCrank (Interactable)
    │       └── Telescope (Interactable) -> see B5
    └── Camera (Camera2D, FocusCameraController.gd)
FocusLayer (CanvasLayer, layer = 10)   # holds only the *opened* object view, never a HUD
├── Dimmer (ColorRect, color alpha 0 -> 0.35)
└── ObjectView (Control, mouse_filter = STOP)
    └── (instanced object UI scene)
Autoloads: Clock, Weather, Tides, Journal, A11y
```

Principle: `FocusLayer` is empty during normal play. It only shows an object when the player has clicked it.

#### Interactable base

```gdscript
# interactable.gd
class_name Interactable
extends Area2D

signal opened(who: Interactable)
signal closed(who: Interactable)

@export var view_scene: PackedScene
@export var hint_text: String = ""                   # screen-reader + diegetic tag
@export var accessible_name: String = ""
@export var focus_zoom: float = 2.0
@export var focus_offset: Vector2 = Vector2.ZERO

var _view: Control

func _ready() -> void:
	input_pickable = true
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))

func _on_hover(h: bool) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if h else Input.CURSOR_ARROW)

func _input_event(_vp: Viewport, event: InputEvent, _i: int) -> void:
	if event.is_action_pressed("interact"):
		open()

func open() -> void:
	if _view != null or view_scene == null:
		return
	_view = view_scene.instantiate() as Control
	var layer: Control = get_tree().get_first_node_in_group("object_view") as Control
	layer.add_child(_view)
	if _view.has_signal("dismissed"):
		_view.connect("dismissed", close)
	opened.emit(self)
	get_tree().call_group("focus_camera", "focus_on", global_position + focus_offset, focus_zoom)

func close() -> void:
	if _view == null:
		return
	_view.queue_free()
	_view = null
	closed.emit(self)
	get_tree().call_group("focus_camera", "release")
```

### B3. Brass clock

**Interaction spec.** The clock is the only source of time. It is drawn as a pixel-art dial; hands are `Sprite2D`s rotated from the game clock. Chimes on the hour (kitchen) and a distinct ship's-bell ring in the lantern room. Clicking opens a larger view with the winding key hole. Winding: drag a key clockwise (a few turns); a spring rattle sound. If unwound for days, it merely loses a few minutes ("The clock is a quarter-hour behind; the sun knows better.") and the sun-based dusk remains the truth for lighting-up.

Node tree:

```
WallClock (Interactable)
├── Face (Sprite2D)
├── HourHand (Sprite2D, offset pivot)
├── MinuteHand (Sprite2D)
├── Pendulum (Sprite2D, AnimationPlayer swing)
├── ChimePlayer (AudioStreamPlayer2D)
└── ClockLabel (Node, accessibility_name set by script)
```

```gdscript
# wall_clock.gd
extends Interactable

@onready var _hour: Sprite2D = $HourHand
@onready var _minute: Sprite2D = $MinuteHand

var _last_hour: int = -1

func _process(_dt: float) -> void:
	var t: float = Clock.hours_of_day # 0.0..24.0
	_hour.rotation = TAU * fposmod(t, 12.0) / 12.0
	_minute.rotation = TAU * fposmod(t * 60.0, 60.0) / 60.0
	var h: int = int(t)
	if h != _last_hour:
		_last_hour = h
		$ChimePlayer.play()
	accessible_name = A11y.time_phrase(t) # e.g. "Clock: about half past four, afternoon"
```

### B4. Brass barometer (needle code)

**Idle read:** a brass aneroid dial. The outer ring has the traditional weather words engraved along the scale: "Stormy", "Rain", "Change", "Fair", "Very Dry". **[Solid]** that such wording was engraved on household barometers (the words were a rough guide; the real signal is the *trend*). The second, movable brass "set hand" marks the reading when last set, so the player compares the needle to it to see rising or falling.

**Open interaction ("Tap and Read"):**

1. Click the glass; the needle makes a tiny jump (real practice: tapping frees the mechanism).
2. Click-drag the small knob to set the brass hand to the needle.
3. Come back later; the gap between the two hands tells the trend. The logbook entry auto-records "Glass falling." or "Glass steady." Mild game effect: a falling glass means weather will turn, which the world telegraphs (clouds, gulls).

Never numeric: units (inches of mercury, or millibars) appear only in the engraved inner ring, small, not required to understand.

Needle behavior: spring-damper so it overshoots slightly and settles; micro jitter as aneroid cell breathes; tapping adds an impulse. Tuned to feel physical but silent-quiet.

Node tree:

```
Barometer (Interactable)
├── Dial (Sprite2D)                  # base art with engraved words
├── SetHand (Sprite2D)               # movable brass hand
├── Needle (Sprite2D, pivot at dial center)
├── GlassGlint (Sprite2D, additive)  # light sheen on glass
├── Tap (AudioStreamPlayer2D)
└── Hover (Control, focus_mode=ALL)  # accessibility_name set from script
```

```gdscript
# barometer.gd
class_name Barometer
extends Interactable

# Dial sweep: 270 degrees. Needle angle maps pressure 28.0 (stormy) .. 31.0 (very dry) inHg.
const P_MIN: float = 28.0
const P_MAX: float = 31.0
const ANGLE_MIN: float = deg_to_rad(-135.0)
const ANGLE_MAX: float = deg_to_rad(135.0)

@export var stiffness: float = 120.0     # spring constant
@export var damping: float = 11.0
@export var jitter: float = 0.0015       # radians of aneroid breath

var _angle: float = 0.0
var _velocity: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _t: float = 0.0
var _set_pressure: float = 29.9

@onready var _needle: Sprite2D = $Needle
@onready var _set_hand: Sprite2D = $SetHand
@onready var _tap: AudioStreamPlayer2D = $Tap

func _ready() -> void:
	super._ready()
	_noise.frequency = 0.6
	_angle = _pressure_to_angle(Weather.pressure_inhg)
	_set_hand.rotation = _pressure_to_angle(_set_pressure)
	hint_text = "Barometer"
	_refresh_accessibility()

func _pressure_to_angle(p: float) -> float:
	var f: float = clampf(inverse_lerp(P_MIN, P_MAX, p), 0.0, 1.0)
	return lerpf(ANGLE_MIN, ANGLE_MAX, f)

func _physics_process(dt: float) -> void:
	_t += dt
	var target: float = _pressure_to_angle(Weather.pressure_inhg)
	target += _noise.get_noise_1d(_t * 40.0) * jitter
	# critically-ish damped spring toward the target pressure angle
	var accel: float = stiffness * (target - _angle) - damping * _velocity
	_velocity += accel * dt
	_angle += _velocity * dt
	_needle.rotation = _angle
	# pixel-art: snap rendered rotation to 1/64 turn so the needle reads crisp
	_needle.rotation = snappedf(_angle, TAU / 64.0)

func tap_glass() -> void:
	_velocity += randf_range(-0.9, 0.9)  # tiny nudge, like a real tap
	_tap.play()
	_refresh_accessibility()

func set_hand_to_needle() -> void:
	_set_pressure = Weather.pressure_inhg
	var tw: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_set_hand, "rotation", _pressure_to_angle(_set_pressure), 0.35)
	_refresh_accessibility()

func trend() -> StringName:
	var d: float = Weather.pressure_inhg - _set_pressure
	if d <= -0.10: return &"falling"
	if d >= 0.10: return &"rising"
	return &"steady"

func _refresh_accessibility() -> void:
	accessible_name = "Barometer"
	var word: String = Weather.pressure_word() # "Fair", "Change", "Rain" ...
	accessible_description = "The needle points to %s. The glass is %s since you last set the brass hand." % [word, String(trend())]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT and _is_over_glass(m.position):
			tap_glass()
		elif m.button_index == MOUSE_BUTTON_RIGHT and _is_over_glass(m.position):
			set_hand_to_needle()

func _is_over_glass(p: Vector2) -> bool:
	return to_local(p).length() < 48.0
```

Note: `accessible_name` and `accessible_description` on non-Control nodes are not engine properties. The Godot accessibility properties (AccessKit, added around Godot 4.5) live on `Control`. **[Verify]** the exact property names in 4.7.2 (`accessibility_name`, `accessibility_description`, `accessibility_live` are my recollection). The Interactable base should therefore expose plain `String` fields as above and mirror them into a hidden-but-focusable `Control` child (see B8). Do not use these as-is on an `Area2D` without that mirror.

### B5. Telescope reticle

**Idle read:** a brass telescope on a tripod facing the sea; a small leather lens cap hangs. **Open:** screen goes to a circular vignette (the eyepiece); the world appears magnified; the reticle is thin crosshairs with tiny ticks (a stadia scale), engraved ring numbers optional.

**Interaction spec ("Look and Steady"):**

- Mouse or right stick pans the view across a limited arc (the telescope is on a pivot, not free).
- Hold `Steady` (Space or LT) to settle the slight breathing sway. Steady is *optional*; sway is gentle even when not steadied.
- Scroll to change magnification between 8x, 16x (two brass eyepieces). In pixel art, this is implemented as camera zoom with nearest-neighbor filtering.
- Targets in the scene (ships, birds, buoys, distant islands) carry `Spottable` info. Hovering the reticle over a target for 0.8 s "names" it by writing it into the logbook margin in the telescope's own small notebook: nothing pops up. The notebook is drawn on the eyepiece rim as a stylized handwritten line at the bottom edge ("Brig, two masts, heading NE").
- Release: Esc or right-click lowers the telescope.
- Accessibility: audio bell triplet when a target enters the center; reticle size/contrast adjustable (B8).

Node tree:

```
TelescopeView (Control, full rect)
├── SceneViewport (SubViewportContainer, stretch)
│   └── SubViewport
│       └── SpyCamera (Camera2D)
├── EyepieceMask (TextureRect)       # circular vignette, black outside
├── Reticle (Control, reticle.gd)    # draws crosshairs and ticks
├── RimNotebook (Label)              # handwritten spotted text
└── A11y (Control, focusable)
```

```gdscript
# reticle.gd
class_name TelescopeReticle
extends Control

signal target_named(target: Spottable)
signal dismissed

@export var pan_limit: Vector2 = Vector2(480.0, 160.0)   # world px from center
@export var sensitivity: float = 0.55
@export var sway_amount: float = 5.0                     # px at 8x
@export var steady_factor: float = 0.15
@export var dwell_to_name: float = 0.8
@export var line_color: Color = Color(0.92, 0.84, 0.62, 0.9)
@export var line_width: float = 1.0
@export var gap: float = 6.0

var aim: Vector2 = Vector2.ZERO
var magnification: int = 1       # 0 -> 8x, 1 -> 16x
var steady: bool = false

@onready var _cam: Camera2D = %SpyCamera
@onready var _notebook: Label = %RimNotebook
@onready var _noise: FastNoiseLite = FastNoiseLite.new()

var _t: float = 0.0
var _dwell: float = 0.0
var _dwell_target: Spottable = null

func _ready() -> void:
	_noise.frequency = 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aim += (event as InputEventMouseMotion).relative * sensitivity * (0.5 if magnification == 1 else 1.0)
		aim = aim.clamp(-pan_limit, pan_limit)
	elif event.is_action_pressed("ui_cancel"):
		dismissed.emit()
	elif event.is_action_pressed("zoom_in"):
		magnification = 1
	elif event.is_action_pressed("zoom_out"):
		magnification = 0
	steady = Input.is_action_pressed("steady")

func _process(dt: float) -> void:
	_t += dt
	# right stick support
	var stick: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	aim = (aim + stick * 240.0 * dt * sensitivity).clamp(-pan_limit, pan_limit)

	var amp: float = sway_amount * (steady_factor if steady else 1.0) * (1.0 + magnification * 0.6)
	var sway := Vector2(_noise.get_noise_2d(_t * 30.0, 0.0), _noise.get_noise_2d(0.0, _t * 30.0 + 100.0)) * amp
	_cam.position = aim + sway
	_cam.zoom = Vector2.ONE * (2.0 if magnification == 0 else 4.0)
	_update_dwell(dt)
	queue_redraw()

func _update_dwell(dt: float) -> void:
	var t: Spottable = _target_under_center()
	if t != null and t == _dwell_target:
		_dwell += dt
		if _dwell >= dwell_to_name:
			_notebook.text = t.sighting_phrase
			target_named.emit(t)
			_dwell = -1.0   # name only once per glance
	elif t != _dwell_target:
		_dwell_target = t
		_dwell = 0.0

func _target_under_center() -> Spottable:
	var center_world: Vector2 = _cam.get_screen_center_position()
	for n: Node in get_tree().get_nodes_in_group("spottable"):
		var s := n as Spottable
		if s != null and s.global_position.distance_to(center_world) < s.radius:
			return s
	return null

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	# crosshair with centre gap
	draw_line(Vector2(c.x - r, c.y), Vector2(c.x - gap, c.y), line_color, line_width)
	draw_line(Vector2(c.x + gap, c.y), Vector2(c.x + r, c.y), line_color, line_width)
	draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - gap), line_color, line_width)
	draw_line(Vector2(c.x, c.y + gap), Vector2(c.x, c.y + r), line_color, line_width)
	# stadia ticks every 24 px along the horizontal
	for i: int in range(1, 8):
		var d: float = gap + i * 24.0
		var h: float = 3.0 if i % 2 == 0 else 2.0
		draw_line(Vector2(c.x + d, c.y - h), Vector2(c.x + d, c.y + h), line_color, line_width)
		draw_line(Vector2(c.x - d, c.y - h), Vector2(c.x - d, c.y + h), line_color, line_width)
	# dwell ring: a thin arc that fills while a target sits under the cross
	if _dwell > 0.0:
		draw_arc(c, gap + 8.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(_dwell / dwell_to_name, 0.0, 1.0), 32, line_color, 1.5)
```

```gdscript
# spottable.gd -- attach to Node2D (ship, bird, buoy)
class_name Spottable
extends Node2D

@export var sighting_phrase: String = "Brig, two masts, heading north-east."
@export var radius: float = 20.0
@export var logbook_remark_id: StringName = &"brig_ne"

func _ready() -> void:
	add_to_group("spottable")
```

The dwell ring is an optional *engraved* fine arc on the lens, not a HUD; it is on the eyepiece rim, as a real reticle might show a mark. Disable it in "Pure Eyepiece" setting.

### B6. Handwritten logbook on the oak desk

**Idle read:** a cloth-bound book with a ribbon, a pen in a stand, an inkwell, a brass paperweight. Dusk has a lamp-lit glow on the cover.

**Open interaction ("Turn and Read"):**

- Click the book to bring it into the foreground (the camera leans in).
- Left/right edge click, arrow keys, or shoulder buttons turn pages. A page-turn animation curls the page with a soft shadow.
- The left page shows the day (date, weather, entries). The right page shows notes (tasks as entries "To do: fresh paint on the gallery rail"), with checkmarks drawn when done, in the same ink. Tasks are never pinned outside the book.
- Back pages: a gazetteer of ships spotted (sketches that fill in), a seabird list, a tide tally, recipes, and the settings pages (see B7).
- Handwriting reveal: text is revealed as ink flowing from a nib at the writing rate. Writing happens only when the day gets a new entry. Re-reading older pages shows the full text instantly.
- Save: closing the book with the ribbon is the save moment; a brief rustle, then a blotter-press sound. No "Saving..." icon. A small wax-seal sprite stamps in the corner of the page when saved; autosave shows the seal.

Node tree:

```
Logbook (Interactable)
LogbookView (Control)                # in FocusLayer
├── Cover (TextureRect)
├── PageLeft (Control)
│   ├── PaperBG (TextureRect)
│   ├── Header (Label, handwriting font)
│   └── Body (RichTextLabel, visible_ratio animated)
├── PageRight (Control)
│   ├── PaperBG (TextureRect)
│   └── Body (RichTextLabel)
├── PageTurn (TextureRect + shader curl)
├── Ribbon (TextureRect)
├── Seal (TextureRect)               # appears when saved
├── Nib (Sprite2D)                   # follows reveal front
├── ScratchSfx (AudioStreamPlayer)
└── Access (Control)                 # focusable text mirror for screen readers
```

```gdscript
# logbook_view.gd
class_name LogbookView
extends Control

signal dismissed

@export var chars_per_second: float = 32.0
@export var turn_time: float = 0.45
@export var fast_reveal_multiplier: float = 6.0

@onready var _left_body: RichTextLabel = %LeftBody
@onready var _right_body: RichTextLabel = %RightBody
@onready var _curl: TextureRect = %PageTurn
@onready var _scratch: AudioStreamPlayer = %ScratchSfx
@onready var _nib: Sprite2D = %Nib
@onready var _seal: TextureRect = %Seal

var _spread: int = 0                       # index into Journal.spreads
var _reveal_tw: Tween
var _turning: bool = false

func _ready() -> void:
	_left_body.bbcode_enabled = true
	_right_body.bbcode_enabled = true
	_show_spread(_spread, Journal.spread_is_fresh(_spread))
	_apply_accessibility()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or event.is_action_pressed("page_next"):
		turn(1)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("page_prev"):
		turn(-1)
	elif event.is_action_pressed("ui_cancel"):
		_close_with_seal()
	elif event.is_action_pressed("ui_accept") and _reveal_tw != null and _reveal_tw.is_running():
		_reveal_tw.set_speed_scale(fast_reveal_multiplier)

func turn(dir: int) -> void:
	if _turning:
		return
	var next: int = clampi(_spread + dir, 0, Journal.spread_count() - 1)
	if next == _spread:
		return
	_turning = true
	_kill_reveal()
	var mat: ShaderMaterial = _curl.material as ShaderMaterial
	mat.set_shader_parameter("direction", float(dir))
	_curl.visible = true
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, turn_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_callback(func() -> void: _show_spread(next, Journal.spread_is_fresh(next))).set_delay(turn_time * 0.5)
	await tw.finished
	_curl.visible = false
	_spread = next
	_turning = false

func _show_spread(i: int, animate: bool) -> void:
	_spread = i
	var data: Dictionary = Journal.get_spread(i)
	_left_body.text = data.get("left", "")
	_right_body.text = data.get("right", "")
	_apply_accessibility()
	if animate and not Settings.reduce_motion:
		_reveal(_left_body, Journal.mark_spread_seen.bind(i))
	else:
		_left_body.visible_ratio = 1.0
		_right_body.visible_ratio = 1.0
		_nib.visible = false

func _reveal(body: RichTextLabel, on_done: Callable) -> void:
	body.visible_ratio = 0.0
	_nib.visible = true
	_scratch.play()
	var total_chars: int = maxi(1, body.get_total_character_count())
	var duration: float = float(total_chars) / chars_per_second
	_kill_reveal()
	_reveal_tw = create_tween()
	_reveal_tw.tween_method(func(r: float) -> void:
		body.visible_ratio = r
		_nib.position = _nib_position_for(body, r)
		_scratch.pitch_scale = 0.95 + randf() * 0.1
	, 0.0, 1.0, duration)
	_reveal_tw.tween_callback(func() -> void:
		_nib.visible = false
		_scratch.stop()
		on_done.call())

func _nib_position_for(body: RichTextLabel, r: float) -> Vector2:
	# Place the nib at the end of the last visible line.
	var visible_chars: int = int(r * body.get_total_character_count())
	var line: int = body.get_character_line(visible_chars)
	var line_rect: Rect2i = Rect2i(body.get_line_offset(line) as int, 0, 0, 0)
	var y: float = body.get_line_offset(line) + body.global_position.y
	var x: float = body.global_position.x + minf(body.size.x, 20.0 + float(visible_chars % 40) * 7.0)
	return Vector2(x, y + 10.0)

func _kill_reveal() -> void:
	if _reveal_tw != null and _reveal_tw.is_valid():
		_reveal_tw.kill()

func _close_with_seal() -> void:
	_kill_reveal()
	_left_body.visible_ratio = 1.0
	Journal.save()                               # autosave on book-close
	_seal.visible = true
	_seal.scale = Vector2(1.6, 1.6)
	var tw: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_seal, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(0.35)
	await tw.finished
	dismissed.emit()

func _apply_accessibility() -> void:
	var plain: String = Journal.spread_plain_text(_spread)
	%Access.accessibility_name = "Logbook, page %d of %d" % [_spread + 1, Journal.spread_count()]
	%Access.accessibility_description = plain
```

Notes on the code: `_nib_position_for` approximates. For production, compute the glyph position through `RichTextLabel.get_line_offset(line)` and per-line character offsets (via the `TextParagraph` of the label); I have kept it simple. **[Verify]** the exact `RichTextLabel` API names (`get_character_line`, `get_line_offset`) in 4.7.2; I recall both exist. The unused `line_rect` local should be deleted in production.

Page-curl shader (a classic cylinder-bend, kept simple for pixel art; the curl is quantized so it reads as hand-animated):

```glsl
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float direction = 1.0;     // 1 = turning forward, -1 = back
uniform float steps = 12.0;         // quantize for pixel look

void fragment() {
	float p = floor(progress * steps) / steps;
	vec2 uv = UV;
	if (direction < 0.0) { uv.x = 1.0 - uv.x; }
	float fold = 1.0 - p * 2.0;              // fold x-position sweeps 1 -> -1
	float x = uv.x * 2.0 - 1.0;
	vec4 c = texture(TEXTURE, UV);
	if (x > fold) {
		// back of page: mirrored and darker
		float mx = 2.0 * fold - x;
		vec2 muv = vec2((mx + 1.0) * 0.5, UV.y);
		if (direction < 0.0) { muv.x = 1.0 - muv.x; }
		c = texture(TEXTURE, muv) * vec4(0.82, 0.78, 0.7, 1.0);
		if (mx < -1.0) { c.a = 0.0; }
	}
	// soft shadow just left of the fold
	float shade = smoothstep(0.0, 0.25, fold - x);
	c.rgb *= mix(0.78, 1.0, shade);
	COLOR = c;
}
```

#### Writing conventions in the writing system

- Use a handwritten pixel font with a legible variant. Always ship **two fonts for the book**: a flourish hand (default) and a plain clear hand (accessibility, see B8). Keep both inked in the same color so diegesis stays intact.
- Dates in the form "Tuesday the 14th of May, 1896"; time in 24-hour or 12-hour with "A.M./P.M." (toggle).
- Keep the keeper's voice cozy and modest. Example entry:

```
Thursday, 14th May.
Lighted at sunset, 7.42. Wick trimmed twice. Wind SW, fresh breeze.
Glass falling since noon. Gulls restless on the south rocks.
A brig, two masts, standing north-east at 4. Sea moderate.
Put a coat of white on the gallery rail. Extinguished at sunrise, 4.58.
All well.
```

### B7. Settings and the controls page (diegetic)

Settings live inside the keeper's trunk ("Notions") as cards and in the logbook's back pages ("Keeper's Memoranda"):

| Setting | Card / object | Notes |
|---|---|---|
| Volume | Three brass sliders on a small ship's radio-like panel | Music, ambience, effects |
| Text size | A pair of spectacles on the desk; swapping to "reading glasses" increases text | See B8 |
| Contrast | A wick-trim-style knob on the lamp: "Soft lamp / Bright lamp" | See B8 |
| Reduce motion | A paperweight placed on the page ("Pin down the papers") | Stops sway, curl, reveal |
| Ease mode | A cup of tea labeled "Take it easy" | Global |
| Controls | Index card with hand-drawn button sketches | Glyphs only on this card |
| Language | A stack of letters with stamps | |
| Quit | "Put out the lamp and go to bed" | Confirms by a hand on the lamp key |

### B8. Accessibility without breaking diegesis

Principle: *accessibility is part of the keeper's workshop.* Every accessibility change should look like a believable object or the same ink on the same page.

**Text size.** The logbook's body font scales through a project-wide `text_scale` (0.8x to 2.0x). It is selected by "spectacles" or a "magnifying glass" on the desk: the glass, drawn as a prop, enlarges text on the page when held over it. In code, update `Theme` default font size and relayout the book (fewer words per page; add more pages).

**High contrast.** Offered as "Bright lamp": a warm white lamplight on the desk, paper becomes lighter and ink darker (hex #141008 on #F4EBD3 is above 12:1 contrast), engraved dial lettering turns black on lighter brass, telescope reticle becomes thick white with a dark outline. Everything remains the same objects, just better lit. No UI chrome is added.

**Color blindness.** Never use color alone. The barometer's zones also differ by engraved shape; the tide table highlights the current row with a bold ink underline not color; flags carry letters.

**Screen-reader labels.** Godot has AccessKit-based screen-reader support on `Control` nodes (introduced in the 4.5 series; **[Verify]** property names and which platforms in 4.7.2). The approach: every `Interactable` owns a hidden focusable `Control` mirror positioned over the object, labelled with a concise name and a dynamic description. Navigation: `Tab` cycles through mirrors in a logical order (clock, barometer, logbook, telescope, tide table, flags). Activating a mirror (Enter) is equivalent to clicking.

```gdscript
# a11y.gd -- autoload "A11y"
extends Node

var text_scale: float = 1.0
var high_contrast: bool = false
var screen_reader_hints: bool = true

signal settings_changed

func time_phrase(hours: float) -> String:
	var h: int = int(hours) % 24
	var m: int = int(fposmod(hours, 1.0) * 60.0)
	var part: String = "night"
	if h >= 5 and h < 12: part = "morning"
	elif h >= 12 and h < 17: part = "afternoon"
	elif h >= 17 and h < 21: part = "evening"
	var approx: String = "o'clock"
	if m >= 8 and m < 23: approx = "quarter past"
	elif m >= 23 and m < 38: approx = "half past"
	elif m >= 38 and m < 53: approx = "quarter to"
	return "Clock: %s, %s %d, %s" % [approx, "hour" if approx == "o'clock" else "", ((h + (1 if approx == "quarter to" else 0) + 11) % 12) + 1, part]

func apply_theme(theme: Theme) -> void:
	theme.default_font_size = int(round(16.0 * text_scale))
	settings_changed.emit()

func make_mirror(owner_obj: Interactable) -> Control:
	var c := Control.new()
	c.focus_mode = Control.FOCUS_ALL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.modulate = Color(1, 1, 1, 0)  # invisible but focusable
	c.accessibility_name = owner_obj.accessible_name
	c.focus_entered.connect(func() -> void: owner_obj.show_focus_ring(true))
	c.focus_exited.connect(func() -> void: owner_obj.show_focus_ring(false))
	return c
```

The diegetic focus ring for keyboard focus is a warm lamp-like soft outline or a pencil-circle drawn round the object (hand-drawn circle sprite). It shows only for keyboard/controller focus, never for mouse.

Note on `time_phrase`: the string assembly above is intentionally rough (the "hour" insertion would read badly). Replace with a lookup table of 24 clear phrases for production. I flag this so nobody ships it as is.

**Subtitles and sound.** Ship ambient cues with captions rendered as handwritten marginalia in the logbook margin ("[Distant foghorn]") for deaf and hard-of-hearing players, plus optional captions on the *telescope's rim notebook*. No on-screen toast text.

**Motion.** `Settings.reduce_motion` kills sway, page curl animation, camera lean zoom (cut instead), and handwriting reveal (instant).

**Input remap.** Every action is remappable from the Controls index card. Mouse-only and keyboard-only paths exist for every interaction; hold actions have a toggle alternative.

**Timing.** There are no timed inputs. Hold-and-circle interactions have the "Ease" one-press alternative (A2).

### B9. Object view focus controller

```gdscript
# focus_camera.gd -- gentle lean-in; add node to group "focus_camera"
extends Camera2D

@export var lean_time: float = 0.5
var _home_pos: Vector2
var _home_zoom: Vector2

func _ready() -> void:
	add_to_group("focus_camera")
	_home_pos = global_position
	_home_zoom = zoom

func focus_on(world_pos: Vector2, z: float) -> void:
	_home_pos = global_position if _home_pos == Vector2.ZERO else _home_pos
	if Settings.reduce_motion:
		global_position = world_pos
		zoom = Vector2.ONE * z
		return
	var tw: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", world_pos, lean_time)
	tw.tween_property(self, "zoom", Vector2.ONE * z, lean_time)

func release() -> void:
	var tw: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_position", _home_pos, lean_time)
	tw.tween_property(self, "zoom", _home_zoom, lean_time)
```

Pixel-art note: keep zoom values to integers (2.0, 3.0, 4.0) at integer-scaled render so pixels stay square. Sub-integer zoom shimmers on nearest-neighbor.

### B10. Tide table

A printed card pinned beside the desk (tide times differ every day; tide tables have been printed in almanacs for centuries, so **[Solid]** for the concept; the table format below is invented). The tide times are generated from a simple harmonic model (two high tides about 12 h 25 min apart, with a spring/neap cycle of ~14.77 days). The player reads high and low water for today (row highlighted), then sets the day's walks (tide pools at low water; boat landing at high).

Interaction: click to bring close; a finger-follow underline slides to the current row; clicking a row writes a short remark into the logbook ("Low water at 2.10; will walk to the pools.").

```gdscript
# tide_table.gd -- autoload "Tides"
extends Node

const LUNAR_DAY_HOURS: float = 24.8412  # time between successive lunar transits
const SEMIDIURNAL_PERIOD: float = LUNAR_DAY_HOURS / 2.0
const SPRING_NEAP_DAYS: float = 14.765

func height(hours_since_epoch: float, phase_days: float) -> float:
	var main: float = cos(TAU * hours_since_epoch / SEMIDIURNAL_PERIOD)
	var range_mod: float = 0.75 + 0.25 * cos(TAU * phase_days / (SPRING_NEAP_DAYS / 2.0))
	return 0.5 + 0.5 * main * range_mod   # 0..1

func next_extremes(from_hours: float, phase_days: float, count: int = 4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var step: float = 0.05
	var t: float = from_hours
	var last: float = height(t, phase_days)
	var going_up: bool = height(t + step, phase_days) > last
	while out.size() < count and t < from_hours + 48.0:
		t += step
		var h: float = height(t, phase_days)
		var up: bool = h > last
		if up != going_up:
			out.append({"hour": t - step, "kind": &"high" if going_up else &"low", "height": last})
			going_up = up
		last = h
	return out
```

### B11. Signal flag locker

Practice: ships and shore stations exchanged messages by flag hoists using the International Code of Signals (first British Board of Trade code 1857, with later revisions, notably 1900). **[Likely]** on dates; **[Verify]** against a code book. Meanings of individual one-flag signals changed across editions, so *do not quote real meanings in the game*. Use a **fictional island code** (clearly labeled "Island Code") for cozy messages: "Good morning", "Fair winds", "Supplies wanted", "Tea at four". Real flag *designs* can be public-domain-like alphabet flags; use original pixel designs.

Interaction spec ("Hoist a Message"):

1. Open the locker: pigeonholes of folded flags, each with a stitched letter label.
2. Click up to four flags in sequence; they appear clipped to a halyard line in the view.
3. Pull the rope (drag down) to hoist; they flutter in the wind (shader waves based on Weather.wind).
4. A passing ship may dip its ensign in answer (a visible reply in the telescope).
5. Lowering returns them to the pigeonholes automatically overnight.

Node tree:

```
FlagLockerView (Control)
├── Cabinet (TextureRect)
├── Pigeonholes (GridContainer)       # 26 slots, each a TextureButton
├── Halyard (Line2D)                  # rope
├── Hoist (Control)                   # flag slots 0..3
└── RopeHandle (Control, draggable)
```

```gdscript
# flag_slot.gd
class_name FlagSlot
extends TextureButton

signal picked(flag_id: StringName)

@export var flag_id: StringName = &"A"
@export var meaning: String = "Good morning"

func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(flag_id))
	accessibility_name = "Flag %s" % String(flag_id)
	accessibility_description = meaning
```

### B12. Zero-HUD checklist (QA)

- [ ] No screen-space text during normal play.
- [ ] Every notification arrives as a sound, a world change, or a line in the logbook.
- [ ] Every number is found on a prop.
- [ ] Every prop is reachable by keyboard and controller.
- [ ] Every prop has an accessible name and live description.
- [ ] Reduced-motion and bright-lamp modes tested on every prop.
- [ ] No empty containers; no disabled grey buttons.
- [ ] Saving shows only a wax seal.
- [ ] The pause is a pocketwatch lid snapping shut over a darkened desk, not a menu.

### B13. Open questions and flags for the team

1. **Lens naming.** Confirm "hyper-radial" vs "hyper-radiant" and the exact meaning of "biform" against Chance Brothers or Barbier-Bénard catalogs before using the names in the codex. **[Verify]**
2. **Mercury.** Do not model handling. Confirm a content decision (sealed float vs roller-ring) with design leads.
3. **Winding interval and wick-trim interval.** Numbers here are design values, not citations. **[Verify]** if a "historical mode" is promised.
4. **AccessKit property names** in Godot 4.7.2. Confirm in the engine docs before wiring `A11y`.
5. **IOV burner steps.** Confirm against a maker's manual before claiming accuracy in a codex entry.
6. **Country neutrality.** The game uses "the Service" and "the Inspector"; avoid real-service insignia.
7. **International Code of Signals.** Avoid real meanings; use the fictional Island Code (B11).
8. **Handwriting fonts.** Pixel handwriting fonts must be licensed or hand-drawn; check OFL licensing.
