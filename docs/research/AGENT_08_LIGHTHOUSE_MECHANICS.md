# AGENT 08 - Lighthouse Mechanics (Clockwork, Oil Lamp, Lens Drive, Foghorn)

Project: Last Light (Godot 4.7.2, GDScript 2.0, static typing). Scope: three physical-toy mechanisms in the lantern room and gallery, each a self-contained scene with its own script. No managers, no autoload bus. Parents wire children with signals ("call down, signal up").

## 0. Design Contract (applies to every mechanism)

| Rule | Consequence in this document |
|---|---|
| Cozy: nothing fails hard | Every state variable has a gentle floor. Weight bottoms out onto a catch-spring and a maintenance spring keeps the lens crawling at 10% torque. Oil runs to a "wick reserve" ember, never to black. Horn at zero pressure still sighs. Over-pressure pops a relief valve, never bursts. |
| Anti-enterprise | One scene = one toy = one script. Cross-talk is signal or a direct typed call from parent to child. Ships find the foghorn by group (`"foghorn"`) once, then connect a signal. No `MechanismManager`, no event bus. |
| Tactile first | Every continuous quantity has (a) a visible analog readout on the object itself, (b) a sound whose pitch/volume tracks the quantity, (c) a hand-feel proxy (drag lag, click detents, haptic pulse). No numeric HUD for mechanisms. |
| Recoverable | All thresholds are hysteresis-free except the vaporizer (deliberately bistable, see 2.4), and even that recovers with one preheat. |
| Units | SI inside scripts: m, kg, s, N, N*m, rad, rad/s, kPa (gauge unless `abs`), W, K/degC, mL. Pixels only at the render boundary via `PX_PER_M`. |

Time model: all mechanisms integrate in real seconds (`_physics_process(delta)`, 60 Hz). Day/night is a separate system; mechanisms never read it except the foghorn's `carry_bonus_db` (optional input). Offline catch-up is closed-form (section 6).

Shared conventions:
- Angles: radians, Godot screen convention (y down, positive = clockwise on screen).
- Pointer input uses mouse events. Set `input_devices/pointing/emulate_mouse_from_touch = true` so touch drags arrive as mouse motion; gamepad right-stick is polled explicitly.
- Pixel-art gears: tooth-periodic sprites. A 12-tooth gear has 30 deg symmetry; draw 4 frames covering one tooth pitch and index `frame = int(fposmod(angle, TAU/teeth) / (TAU/teeth) * 4.0)`. Never rotate pixel sprites by arbitrary angles (shimmer). Large rotors (lens drum, flyweights) use pre-rendered 32-step rings (`step = round(angle / (TAU/32))`).

---

## 1. Clockwork: Weight Descent and Manual Winding

### 1.1 Physical model

The keeper's clockwork is a falling weight in the tower shaft driving a gear train to the lens. Weight height `h` (m above the catch cradle, `0..H`). The lens (not the weight) sets the rate of fall: the weight can only fall as fast as the governor lets the train turn.

Constants (game-scaled from a real 40 kg / 6 m clock weight):

| Symbol | Name | Value | Unit |
|---|---|---|---|
| m | weight mass | 40 | kg |
| g | gravity | 9.81 | m/s^2 |
| r_d | drum radius | 0.08 | m |
| H | shaft drop | 6.0 | m |
| G | train ratio (lens revs per drum rev) | 15.0 (3 x 5) | - |
| eta | train efficiency | 0.70 | - |
| R_w | winding ratio (crank revs per drum rev) | 4 | - |
| h_soft | catch-spring zone | 0.6 | m |
| f_res | maintenance-spring factor | 0.10 | - |

Stored energy: `E = m g H = 40 * 9.81 * 6 = 2354 J`.

Drum torque: `T_drum = m g r_d = 40 * 9.81 * 0.08 = 31.4 N*m`.

Drive factor (cozy floor), `f(h) = f_res + (1 - f_res) * smoothstep(0, h_soft, h)`. Below `h_soft` a coil catch-spring takes the weight progressively. At `h = 0` the maintenance spring still delivers `f_res`.

Torque reflected to the lens shaft:

```
tau_lens = m * g * r_d * eta * f(h) / G        [N*m]
         = 40 * 9.81 * 0.08 * 0.70 * 1 / 15 = 1.465 N*m  (full drive)
```

Rates (kinematics, lens angular speed `omega_L` supplied by LensDrive):

```
omega_drum = omega_L / G                          [rad/s]
dh/dt      = - omega_drum * r_d = - omega_L * r_d / G   [m/s]
```

At nominal lens period T_L = 12 s: `omega_L = 2*pi/12 = 0.5236 rad/s`, `dh/dt = 0.5236*0.08/15 = 2.79e-3 m/s`.

Run time of a full wind: `t_run = H / (dh/dt) = 6 / 2.79e-3 = 2149 s = 35.8 min`. Equivalently `t_run = (H / (2 pi r_d)) * G * T_L = 11.94 * 15 * 12 s`.

Gear train (visible, 2 stages): `12:36 (3.0) x 10:50 (5.0) = 15.0`. Drum turns 0.335 rev/min at nominal. This is slow enough to be seen creeping, fast enough to see the weight descend.

Winding (crank angle `d_theta`, rad):

```
dh = d_theta * r_d / R_w      [m]       (0.02 m per rad; 0.1257 m per crank rev)
full wind from 0: H / 0.1257 = 47.7 crank revs; at 1.2 rev/s drag ~ 40 s
```

Torque advantage at the crank (crank radius 0.25 m): `F_hand = T_drum / (R_w * 0.25 m) = 31.4/(4*0.25) = 31 N` (about 3 kgf, feels "weighty"; conveyed via lag, not numbers).

Maintaining power: the weight keeps driving the lens during winding, so the light never skips while the player winds.

### 1.2 Ratchet

24 teeth, pitch 15 deg per click on the crank axle. The pawl blocks reverse. Reverse drag motion is absorbed (handle held by pawl) and rubs a soft "tk" (cooldown 0.12 s). One click = one tooth = 0.0052 m of weight lift (`0.02 m/rad * 0.2618 rad`).

### 1.3 Scene tree

```
ClockworkMechanism (Node2D)          clockwork_mechanism.gd
├─ Frame (Sprite2D)                  brass cage, back plate
├─ Shaft (Node2D)
│  ├─ Cord (Line2D)                  drum to weight, 1 px, 2 vertices
│  └─ WeightCarriage (Sprite2D)      iron block, bob offset
├─ Drum (Sprite2D)                   32-step rotation ring
├─ GearTrain (Node2D)
│  ├─ GearA (Sprite2D)               12t, tooth-frame animated
│  ├─ GearB (Sprite2D)               36t
│  ├─ GearC (Sprite2D)               10t
│  └─ GearD (Sprite2D)               50t, meshes to lens drive
├─ WindingCrank (Node2D)             winding_crank.gd
│  ├─ Handle (Sprite2D)
│  ├─ Pawl (Sprite2D)                flicks on each click
│  └─ ClickPlayer (AudioStreamPlayer2D)
├─ MaintenanceSpring (Sprite2D)      pulses when engaged
├─ TickPlayer (AudioStreamPlayer2D)  gear mesh tick
└─ SwayTween holder (none; tween created in code)
```

### 1.4 Signals

| Signal | Emitter | Payload | Listener |
|---|---|---|---|
| `drive_torque_changed(torque_nm)` | ClockworkMechanism | lens-shaft torque | LensDrive.set_drive_torque |
| `wind_fraction_changed(fraction)` | ClockworkMechanism | 0..1, throttled to 0.01 steps | LanternRoom (weight gauge sprite), save |
| `reserve_engaged(active)` | ClockworkMechanism | bool | UI-free: spring sprite pulse, soft chime |
| `wound_full()` | ClockworkMechanism | - | one-shot "ding", crank soft stop |
| `turned(delta_angle_rad)` | WindingCrank | accepted forward angle | ClockworkMechanism |
| `ratchet_clicked(tooth, speed_rad_s)` | WindingCrank | tooth index, drag speed | ClockworkMechanism (audio pitch) |
| `grabbed()` / `released()` | WindingCrank | - | LanternRoom (cursor change) |

Inbound call (from parent): `ClockworkMechanism.set_lens_omega(omega_rad_s)`, connected from `LensDrive.omega_changed`.

### 1.5 Script: `clockwork_mechanism.gd`

```gdscript
class_name ClockworkMechanism
extends Node2D
## Falling-weight drive. Lens speed sets the fall rate; winding raises the weight.

signal drive_torque_changed(torque_nm: float)
signal wind_fraction_changed(fraction: float)
signal reserve_engaged(active: bool)
signal wound_full()

const GRAVITY: float = 9.81  # m/s^2
const PX_PER_M: float = 24.0

@export var weight_mass_kg: float = 40.0
@export var drum_radius_m: float = 0.08
@export var shaft_height_m: float = 6.0
@export var train_ratio: float = 15.0        # lens revs per drum rev
@export var efficiency: float = 0.70
@export var wind_ratio: float = 4.0          # crank revs per drum rev
@export var soft_zone_m: float = 0.6
@export var reserve_factor: float = 0.10
@export var start_fraction: float = 0.5

@onready var _carriage: Sprite2D = $Shaft/WeightCarriage
@onready var _cord: Line2D = $Shaft/Cord
@onready var _drum: Sprite2D = $Drum
@onready var _gears: Array[Sprite2D] = [$GearTrain/GearA, $GearTrain/GearB, $GearTrain/GearC, $GearTrain/GearD]
@onready var _crank: WindingCrank = $WindingCrank
@onready var _spring: Sprite2D = $MaintenanceSpring
@onready var _tick: AudioStreamPlayer2D = $TickPlayer

const GEAR_TEETH: Array[int] = [12, 36, 10, 50]
const GEAR_RATIO_FROM_DRUM: Array[float] = [1.0, 1.0 / 3.0, 1.0 / 3.0, 1.0 / 15.0]
## Gear angles are advanced as drum_angle * ratio_factor; signed to alternate mesh direction.

var height_m: float = 3.0       # m above catch cradle, 0..shaft_height_m
var _lens_omega: float = 0.0    # rad/s
var _drum_angle: float = 0.0    # rad
var _last_fraction: float = -1.0
var _last_torque: float = -1.0
var _reserve_on: bool = false
var _tick_accum: float = 0.0

func _ready() -> void:
    height_m = shaft_height_m * start_fraction
    _crank.turned.connect(_on_crank_turned)
    _crank.ratchet_clicked.connect(_on_ratchet_clicked)
    _refresh_visuals()
    _emit_state(true)

func set_lens_omega(omega_rad_s: float) -> void:
    _lens_omega = maxf(omega_rad_s, 0.0)

func drive_factor() -> float:
    return reserve_factor + (1.0 - reserve_factor) * smoothstep(0.0, soft_zone_m, height_m)

func lens_torque_nm() -> float:
    return weight_mass_kg * GRAVITY * drum_radius_m * efficiency * drive_factor() / train_ratio

func wind_fraction() -> float:
    return height_m / shaft_height_m

func _physics_process(delta: float) -> void:
    var drum_omega: float = _lens_omega / train_ratio
    height_m = maxf(height_m - drum_omega * drum_radius_m * delta, 0.0)
    _drum_angle += drum_omega * delta
    _tick_accum += drum_omega * delta
    if _tick_accum >= TAU / 48.0:           # one soft tick per 7.5 deg of drum
        _tick_accum -= TAU / 48.0
        _tick.pitch_scale = 0.9 + 0.2 * wind_fraction()
        _tick.play()
    var on_reserve: bool = height_m <= 0.0
    if on_reserve != _reserve_on:
        _reserve_on = on_reserve
        reserve_engaged.emit(_reserve_on)
    _crank.set_resistance(0.25 + 0.5 * wind_fraction())  # heavier as weight rises
    _crank.set_soft_stop(height_m >= shaft_height_m - 0.001)
    _refresh_visuals()
    _emit_state(false)

func _on_crank_turned(delta_angle_rad: float) -> void:
    var room_m: float = shaft_height_m - height_m
    var lift_m: float = delta_angle_rad * drum_radius_m / wind_ratio
    if lift_m >= room_m:
        height_m = shaft_height_m
        wound_full.emit()
    else:
        height_m += lift_m

func _on_ratchet_clicked(tooth: int, speed_rad_s: float) -> void:
    pass  # crank owns its click sound; hook kept for haptics/analytics if desired.

func _refresh_visuals() -> void:
    var y_px: float = -height_m * PX_PER_M
    var sway: float = sin(Time.get_ticks_msec() * 0.0016) * 0.5 * smoothstep(0.0, 0.4, height_m)
    _carriage.position = Vector2(roundf(sway), roundf(y_px))   # pixel snap
    _cord.set_point_position(1, _carriage.position + Vector2(0, -8))
    _drum.frame = int(roundf(fposmod(_drum_angle, TAU) / (TAU / 32.0))) % 32
    for i: int in _gears.size():
        var a: float = _drum_angle * GEAR_RATIO_FROM_DRUM_SIGNED(i)
        var pitch: float = TAU / float(GEAR_TEETH[i])
        _gears[i].frame = int(fposmod(a, pitch) / pitch * 4.0) % 4
    _spring.modulate.a = 1.0 if _reserve_on else 0.35

func GEAR_RATIO_FROM_DRUM_SIGNED(i: int) -> float:
    # Sign flips per mesh; ratios are speed multipliers relative to the drum.
    # Gear stage speeds: A=drum x1, B=drum x(12/36)... see GEAR_RATIO_FROM_DRUM; sign alternates.
    return GEAR_RATIO_FROM_DRUM[i] * (1.0 if i % 2 == 0 else -1.0)

func _emit_state(force: bool) -> void:
    var frac: float = wind_fraction()
    if force or absf(frac - _last_fraction) >= 0.01:
        _last_fraction = frac
        wind_fraction_changed.emit(frac)
    var t: float = lens_torque_nm()
    if force or absf(t - _last_torque) >= 0.005:
        _last_torque = t
        drive_torque_changed.emit(t)

func save_state() -> Dictionary:
    return {"height_m": height_m}

func load_state(d: Dictionary) -> void:
    height_m = clampf(float(d.get("height_m", height_m)), 0.0, shaft_height_m)

## Closed-form offline catch-up (section 6). Returns the new height.
func catch_up(elapsed_s: float, nominal_omega: float, drain_cap: float = 0.6) -> void:
    var drop_m: float = nominal_omega * drum_radius_m / train_ratio * elapsed_s
    drop_m = minf(drop_m, shaft_height_m * drain_cap)
    height_m = maxf(height_m - drop_m, 0.0)
```

Note: the gear speed table assumes drum -> A (1x) -> B (12/36 of A... ) is implementation art direction; only the lens connection (`G = 15`) is physical. Gear sprite speeds are cosmetic ratios derived from the tooth counts and must be revisited only if the art changes tooth counts.

### 1.6 Script: `winding_crank.gd` (circular drag input)

Algorithm: pointer angle about crank pivot, delta wrapped to `(-pi, pi]`, accumulated into a pending-angle debt. The handle chases the debt at a capped speed, which is the tactile "weight": heavier load means slower follow, so the cursor visibly runs ahead of the handle.

```
max_follow = w_max * (1 - 0.55 * resistance)        [rad/s], w_max = 9 rad/s (~1.43 rev/s)
step = clamp(pending, -max_follow*dt, +max_follow*dt)
pending -= step
```
Resistance runs 0.25 (weight low) to 0.75 (weight high): follow speed 7.8 down to 5.3 rad/s.

```gdscript
class_name WindingCrank
extends Node2D
## Circular-drag crank with ratchet. Forward (clockwise) only.

signal turned(delta_angle_rad: float)
signal ratchet_clicked(tooth: int, speed_rad_s: float)
signal grabbed()
signal released()

@export var teeth: int = 24
@export var grab_radius_px: float = 28.0
@export var dead_radius_px: float = 8.0
@export var max_follow_rad_s: float = 9.0
@export var stick_deadzone: float = 0.6

@onready var _handle: Sprite2D = $Handle
@onready var _pawl: Sprite2D = $Pawl
@onready var _click: AudioStreamPlayer2D = $ClickPlayer

var _grabbed: bool = false
var _last_pointer_angle: float = 0.0
var _pending: float = 0.0
var _handle_angle: float = 0.0
var _tooth_accum: float = 0.0
var _tooth_index: int = 0
var _resistance: float = 0.3
var _soft_stop: bool = false
var _reverse_cooldown: float = 0.0
var _last_step_speed: float = 0.0

func set_resistance(r: float) -> void:
    _resistance = clampf(r, 0.0, 1.0)

func set_soft_stop(on: bool) -> void:
    _soft_stop = on

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.button_index != MOUSE_BUTTON_LEFT:
            return
        if mb.pressed and get_local_mouse_position().length() <= grab_radius_px:
            _grabbed = true
            _last_pointer_angle = get_local_mouse_position().angle()
            grabbed.emit()
            get_viewport().set_input_as_handled()
        elif not mb.pressed and _grabbed:
            _grabbed = false
            released.emit()
    elif event is InputEventMouseMotion and _grabbed:
        var local: Vector2 = get_local_mouse_position()
        if local.length() < dead_radius_px:
            return                      # angle is noise near the pivot
        var a: float = local.angle()
        _pending += wrapf(a - _last_pointer_angle, -PI, PI)
        _pending = clampf(_pending, -TAU, TAU)   # bounded debt; no runaway
        _last_pointer_angle = a

func _poll_stick(delta: float) -> void:
    var v: Vector2 = Input.get_vector("crank_left", "crank_right", "crank_up", "crank_down")
    if v.length() < stick_deadzone:
        return
    var a: float = v.angle()
    _pending += wrapf(a - _last_pointer_angle, -PI, PI)
    _pending = clampf(_pending, -TAU, TAU)
    _last_pointer_angle = a

func _physics_process(delta: float) -> void:
    _reverse_cooldown = maxf(_reverse_cooldown - delta, 0.0)
    if not _grabbed:
        _poll_stick(delta)
    var follow: float = max_follow_rad_s * (1.0 - 0.55 * _resistance)
    if _soft_stop:
        follow *= 0.15                  # gentle "full" stiffness, never a lock
    var max_step: float = follow * delta
    var step: float = clampf(_pending, -max_step, max_step)
    _pending -= step
    if step > 0.0:
        _handle_angle += step
        _last_step_speed = step / delta
        if not _soft_stop:
            turned.emit(step)
        _tooth_accum += step
        var pitch: float = TAU / float(teeth)
        while _tooth_accum >= pitch:
            _tooth_accum -= pitch
            _tooth_index = (_tooth_index + 1) % teeth
            _click_now()
    elif step < -0.05 and _reverse_cooldown <= 0.0:
        _reverse_cooldown = 0.12        # pawl holds; handle does not go back
        _click.pitch_scale = 0.6
        _click.volume_db = -14.0
        _click.play()
    _pending = maxf(_pending, 0.0) if step < 0.0 else _pending
    _handle.frame = int(roundf(fposmod(_handle_angle, TAU) / (TAU / 32.0))) % 32
    _pawl.rotation = lerp_angle(_pawl.rotation, 0.0, 18.0 * delta)

func _click_now() -> void:
    _pawl.rotation = deg_to_rad(-14.0)
    _click.pitch_scale = 0.95 + randf() * 0.1 + 0.002 * _last_step_speed
    _click.volume_db = -8.0 + minf(_last_step_speed, 9.0) * 0.5
    _click.play()
    ratchet_clicked.emit(_tooth_index, _last_step_speed)
    Input.vibrate_handheld(6, 0.25)    # no-op on desktop
```

### 1.7 Tuning table

| Parameter | Value | Effect |
|---|---|---|
| Full-wind run time | 35.8 min | Wind chore recurs about once per 36 real min |
| Full wind from empty | ~40 s @ 1.2 rev/s | Satisfying, not tedious |
| Partial wind (0.5 -> 1.0) | ~20 s | Always allowed; no overshoot penalty |
| Crank follow speed | 9 -> 4 rad/s (resistance 0 -> 1) | Rising-weight heft |
| Ratchet pitch | 15 deg (24 teeth) | 24 clicks/rev, ~29 clicks/s at max speed |
| Click pitch | 0.95..1.05 + 0.002*speed | Faster cranking = brighter chatter |
| Maintenance factor | 0.10 | Lens period at floor: `T = T_nom / sqrt(0.1) = 3.16 x` = 38 s |
| Soft zone | 0.6 m (10% of H) | Gradual slowdown starting at ~5 min left of wind |

Slowdown preview (drive factor to lens period, using `omega_eq proportional to sqrt(f)` from 2.3):

| Remaining drop h (m) | f(h) | Lens period (s) |
|---|---|---|
| >= 0.6 | 1.00 | 12.0 |
| 0.45 | 0.84 | 13.1 |
| 0.30 | 0.55 | 16.2 |
| 0.15 | 0.26 | 23.5 |
| 0.00 | 0.10 | 38.0 |

### 1.8 Tactile map

| Quantity | Visual | Audio | Hand-feel |
|---|---|---|---|
| Weight height | Carriage rides up shaft, cord shortens, 1 px sway | Tick pitch 0.9 -> 1.1 with wind | Crank resistance 0.25 -> 0.75 |
| Winding progress | Pawl flick per tooth | Click per 15 deg, pitch rises with speed | Haptic 6 ms @ 0.25 per click on mobile |
| Reverse drag | Handle holds, pawl shudder 1 px | Soft low "tk" | Cursor runs ahead (dead pending angle absorbed) |
| Full | Carriage touches buffer, tiny bounce | Single bell "ding" | Handle follow drops to 15%, a soft push-back |
| Maintenance spring | Spring sprite brightens | Quiet two-note chime once | Lens visibly slows |

---

## 2. Lens Drive: Governor, Flywheel and Light Character

### 2.1 Rotor dynamics

The lens assembly is a heavy brass rotor (flywheel) with a fan/flyweight governor. State: lens angular speed `omega` (rad/s).

```
I * d(omega)/dt = tau_drive - k_g * omega * |omega| - c * omega
```

| Symbol | Meaning | Value | Unit |
|---|---|---|---|
| I | rotor inertia (lens + flywheel) | 8.0 | kg*m^2 |
| tau_drive | from clockwork | up to 1.465 | N*m |
| k_g | governor (flyweight fan) coefficient | 5.25 nominal | N*m*s^2/rad^2 |
| c | bearing viscous friction | 0.05 | N*m*s/rad |

Equilibrium: `omega_eq = (-c + sqrt(c^2 + 4 k_g tau_drive)) / (2 k_g)`. For nominal: `k_g = (tau - c*omega_nom)/omega_nom^2 = (1.465 - 0.0262)/0.2742 = 5.248`. Equilibrium `omega_eq = 0.5236 rad/s` (period 12.0 s).

Regulation property: because brake torque grows with `omega^2`, a torque change of dtau gives `d omega / omega = dtau / (2 tau)` (square-root law). A 20% weight-factor drop only slows the lens 10%.

Time constant at nominal: `tau_t = I / (2 k_g omega + c) = 8 / (5.496 + 0.05) = 1.44 s`. A fresh start from rest eases in over about 5 s (3 tau_t). This is the "lens eases up to speed" feel after winding from a dead stop.

Numerical stability: explicit Euler needs `dt < 2 I / (2 k_g omega + c) = 2.9 s`; at 60 Hz margin is 170x.

Governor trim (brass thumbscrew spreading the flyweights): `k_eff = k_g * (1 + 0.35 * trim)`, `trim in [-1, +1]`.

| trim | k_eff | omega_eq ratio | Period (s) |
|---|---|---|---|
| -1.0 | 3.41 | 1.24 | 9.7 |
| -0.5 | 4.33 | 1.10 | 10.9 |
| 0.0 | 5.25 | 1.00 | 12.0 |
| +0.5 | 6.17 | 0.92 | 13.0 |
| +1.0 | 7.09 | 0.86 | 14.0 |

Rhythm quality (soft, feeds ship confidence): `q = 1 - clamp(abs(T_actual/T_character - 1) / 0.25, 0, 1)`. Within +-8% period reads as `q > 0.68` ("keeping good time"); the lantern hums in tune.

Flyweight visual: `phi_g = lerp(15 deg, 65 deg, smoothstep(0, 1.6, omega/omega_nom))`, smoothed with first-order lag (0.25 s).

### 2.2 Scene tree

```
LensDrive (Node2D)                      lens_drive.gd
├─ Pedestal (Sprite2D)                  mercury-bath ring, static
├─ Rotor (Node2D)
│  ├─ Flywheel (Sprite2D)               32-step ring
│  ├─ LensDrum (Sprite2D)               brass frame, 9 bullseye windows
│  ├─ Shutters (Node2D)                 9 x Sprite2D "cloth curtains", toggled
│  └─ BeamSource (Node2D)               holds 9 slot markers
├─ Governor (Node2D)
│  ├─ FlyweightL (Sprite2D)
│  ├─ FlyweightR (Sprite2D)
│  └─ TrimScrew (Area2D)                drag up/down to trim
├─ BeamLights (Node2D)                  9 x PointLight2D, texture = beam cone
├─ HumPlayer (AudioStreamPlayer2D)      loop, pitch_scale = omega/omega_nom
└─ WhirrPlayer (AudioStreamPlayer2D)    governor fan, volume ~ omega^2
```

### 2.3 Signals

| Signal | Payload | Listeners |
|---|---|---|
| `omega_changed(omega_rad_s)` | each physics tick when changed > 0.002 | ClockworkMechanism.set_lens_omega |
| `flash_started(slot, bearing_rad)` | when a slot's beam passes the nearest-ship bearing or on a fixed cadence for FX | LanternRoom (flare FX), ships via group |
| `period_changed(period_s, quality)` | 1 Hz | save, ship confidence |
| `character_changed(character)` | shutters changed | Ship scripts via LanternRoom |

Inbound: `set_drive_torque(torque_nm)` from ClockworkMechanism; `set_lamp_level(b)` from VaporMantle (0..1 brightness); `set_character(c)`.

### 2.4 Light character resource: `light_character.gd`

```gdscript
class_name LightCharacter
extends Resource
## Pure data + beam math. Slots are 9 lens windows at slot_pitch_deg spacing.

@export var id: StringName = &"fl2_12"
@export var display_name: String = "Fl(2) 12s"
@export var nominal_period_s: float = 12.0
@export var slot_pitch_deg: float = 40.0
@export var open_slots: PackedInt32Array = PackedInt32Array([0, 1])
@export var beam_fwhm_deg: float = 8.0
@export var halo: float = 0.06          # steady loom, always visible

const LN2_4: float = 2.772588722        # 4 * ln(2)

func slot_bearing(slot: int, lens_angle_rad: float) -> float:
    return lens_angle_rad + deg_to_rad(float(slot) * slot_pitch_deg)

## Observed intensity (0..1) at absolute bearing (rad) from lighthouse,
## before distance/fog attenuation.
func intensity_at(bearing_rad: float, lens_angle_rad: float) -> float:
    var sum: float = 0.0
    var fwhm: float = deg_to_rad(beam_fwhm_deg)
    for s: int in open_slots:
        var d: float = wrapf(bearing_rad - slot_bearing(s, lens_angle_rad), -PI, PI)
        sum += exp(-LN2_4 * (d / fwhm) * (d / fwhm))
    return clampf(maxf(sum, halo), 0.0, 1.0)

func nominal_omega() -> float:
    return TAU / nominal_period_s

## Predicted flash start times (s) within one period for a fixed observer,
## useful for tests and for the ship's "I know this light" logic.
func flash_times(period_s: float) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    var deg_per_s: float = 360.0 / period_s
    for s: int in open_slots:
        out.append(fposmod(-float(s) * slot_pitch_deg / deg_per_s, period_s))
    out.sort()
    return out
```

Flash geometry. Flash duration (FWHM) `t_f = fwhm_deg / (360/T)`, eclipse between adjacent open slots `t_e = (pitch_deg*k - fwhm_deg) / (360/T)`.

Character table (all reached by lens period + which curtains are open):

| Character | open_slots | pitch (deg) | T (s) | deg/s | flash FWHM (s) | spacing (s) | long dark (s) | Feel |
|---|---|---|---|---|---|---|---|---|
| Fl 12s | {0} | 40 | 12 | 30.0 | 0.27 | - | 11.7 | slow single wink |
| Fl(2) 12s (home light) | {0,1} | 40 | 12 | 30.0 | 0.27 | 1.33 | 10.4 | double-blink, calm |
| Fl(3) 15s | {0,1,2} | 40 | 15 | 24.0 | 0.33 | 1.67 | 11.3 | triple, "stern" |
| Fl(2+1) 12s | {0,1,4} | 40 | 12 | 30.0 | 0.27 | 1.33 / 5.33 | 6.7 | composite, distinctive |
| Q Fl 8s | {0..8} | 40 | 8 | 45.0 | 0.18 | 0.89 | 0.7 | excited sparkle (festival nights) |

Long dark = `T - (last_start - first_start) - flash_fwhm`.

Curtain interaction: tapping a curtain toggles that slot; `character_changed` fires with an ad-hoc `LightCharacter` duplicated from the base, `open_slots` updated. Matches whichever named table row it equals; if no match the game shows nothing (anything is a valid, if unnamed, pattern).

### 2.5 Script: `lens_drive.gd`

```gdscript
class_name LensDrive
extends Node2D
## Rotating brass lens with flywheel inertia and a quadratic-brake governor.

signal omega_changed(omega_rad_s: float)
signal flash_started(slot: int, bearing_rad: float)
signal period_changed(period_s: float, quality: float)
signal character_changed(character: LightCharacter)

@export var inertia_kg_m2: float = 8.0
@export var viscous_nm_s_per_rad: float = 0.05
@export var governor_k: float = 5.248          # N*m*s^2/rad^2
@export_range(-1.0, 1.0) var trim: float = 0.0
@export var character: LightCharacter

@onready var _rotor_ring: Sprite2D = $Rotor/Flywheel
@onready var _lens_ring: Sprite2D = $Rotor/LensDrum
@onready var _fly_l: Sprite2D = $Governor/FlyweightL
@onready var _fly_r: Sprite2D = $Governor/FlyweightR
@onready var _hum: AudioStreamPlayer2D = $HumPlayer
@onready var _whirr: AudioStreamPlayer2D = $WhirrPlayer
@onready var _beams: Node2D = $BeamLights

var omega: float = 0.0                 # rad/s
var lens_angle: float = 0.0            # rad, bearing of slot 0 beam
var lamp_level: float = 1.0            # 0..1 from VaporMantle
var _torque: float = 0.0
var _fly_phi: float = deg_to_rad(15.0)
var _last_omega_sent: float = -1.0
var _period_timer: float = 0.0
var _prev_slot_phase: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
    omega = character.nominal_omega() if character != null else 0.5
    _update_beam_lights()

func set_drive_torque(t: float) -> void:
    _torque = maxf(t, 0.0)

func set_lamp_level(b: float) -> void:
    lamp_level = clampf(b, 0.0, 1.0)

func set_character(c: LightCharacter) -> void:
    character = c
    _update_beam_lights()
    character_changed.emit(c)

func set_trim(v: float) -> void:
    trim = clampf(v, -1.0, 1.0)

func _physics_process(delta: float) -> void:
    var k_eff: float = governor_k * (1.0 + 0.35 * trim)
    var brake: float = k_eff * omega * absf(omega) + viscous_nm_s_per_rad * omega
    omega = maxf(omega + (_torque - brake) / inertia_kg_m2 * delta, 0.0)
    var prev: float = lens_angle
    lens_angle = fposmod(lens_angle + omega * delta, TAU)
    _detect_flashes(prev, lens_angle)
    _animate(delta)
    _period_timer += delta
    if _period_timer >= 1.0:
        _period_timer = 0.0
        var period: float = TAU / maxf(omega, 0.001)
        var q: float = 1.0 - clampf(absf(period / character.nominal_period_s - 1.0) / 0.25, 0.0, 1.0)
        period_changed.emit(period, q)
    if absf(omega - _last_omega_sent) > 0.002:
        _last_omega_sent = omega
        omega_changed.emit(omega)

func _detect_flashes(prev: float, now: float) -> void:
    # Fires a flash FX whenever any open slot crosses the lantern's "front" (bearing 0).
    if character == null:
        return
    for s: int in character.open_slots:
        var off: float = deg_to_rad(float(s) * character.slot_pitch_deg)
        var a0: float = wrapf(prev + off, -PI, PI)
        var a1: float = wrapf(now + off, -PI, PI)
        if a0 < 0.0 and a1 >= 0.0 and absf(a1 - a0) < 1.0:
            flash_started.emit(s, 0.0)

func _animate(delta: float) -> void:
    _rotor_ring.frame = int(roundf(lens_angle / (TAU / 32.0))) % 32
    _lens_ring.frame = _rotor_ring.frame
    var ratio: float = omega / maxf(character.nominal_omega(), 0.001)
    var target: float = lerpf(deg_to_rad(15.0), deg_to_rad(65.0), smoothstep(0.0, 1.6, ratio))
    _fly_phi = lerpf(_fly_phi, target, 1.0 - exp(-delta / 0.25))
    _fly_l.rotation = -_fly_phi
    _fly_r.rotation = _fly_phi
    _hum.pitch_scale = clampf(0.6 + 0.4 * ratio, 0.4, 1.4)
    _whirr.volume_db = linear_to_db(clampf(ratio * ratio, 0.001, 2.0)) - 18.0
    _beams.rotation = lens_angle
    _beams.modulate.a = lamp_level

func _update_beam_lights() -> void:
    for child: Node in _beams.get_children():
        var idx: int = child.get_index()
        (child as PointLight2D).visible = character != null and character.open_slots.has(idx)

func save_state() -> Dictionary:
    return {"omega": omega, "lens_angle": lens_angle, "trim": trim}

func load_state(d: Dictionary) -> void:
    omega = float(d.get("omega", omega))
    lens_angle = float(d.get("lens_angle", 0.0))
    trim = clampf(float(d.get("trim", 0.0)), -1.0, 1.0)
```

Beam lights are `PointLight2D` cones parented to `BeamLights`, one per slot, rotated in place by `slot * pitch` in the scene; the parent rotates them.

### 2.6 Seeing the light (ship side)

Visibility by meteorological range `V` (Koschmieder): extinction `sigma = 3.912 / V`, transmittance `Tr = exp(-sigma * d) = exp(-3.912 d / V)`.

Observed brightness at distance `d` (m): `I_seen = lamp_level * character.intensity_at(bearing, lens_angle) * Tr`. Detected if `I_seen >= 0.02`.

| Weather | V (m) | Tr at 1 km | Practical range (flash peak at 0.02) |
|---|---|---|---|
| Clear | 12000 | 0.72 | beyond map |
| Haze | 4000 | 0.38 | ~4000 m |
| Fog | 1000 | 0.020 | ~1000 m (peak) |
| Thick fog | 400 | 0.00006 | ~400 m |

Thick fog is where the horn takes over; the light still glows as a halo (`halo` term) at short range.

### 2.7 Tactile map

| Quantity | Visual | Audio | Hand-feel |
|---|---|---|---|
| Lens speed | Ring steps, beam sweep on the water | Hum pitch 0.6 + 0.4*(omega/omega_nom) | Light period readable by counting |
| Governor | Flyweights fly outward when fast | Fan whirr volume ~ omega^2 | Trim screw drag: 12 detent clicks over [-1, +1] |
| Flywheel inertia | 1.4 s ease on start/stop | Hum glides rather than jumps | Wind-from-dead: lens coasts up |
| Flash | Cone lights sweep, lens flare on front crossing | Soft "whoosh" per flash, -24 dB | Pattern readable as rhythm |

---

## 3. Oil Lamp: Reservoir, Pressure, Preheat, Mantle

An incandescent oil vapor (IOV) lamp: oil in a pressurized reservoir is forced through a vaporizer tube heated by a spirit preheater, burns in a Bunsen-style jet, and heats a ceria mantle to incandescence. All numbers below are game-balanced; the structure follows the real procedure (fill, pump, preheat, open valve, light).

### 3.1 Scene tree

```
OilLamp (Node2D)                        oil_lamp.gd (thin wiring, no physics)
├─ Reservoir (Node2D)                   oil_reservoir.gd
│  ├─ TankBody (Sprite2D)
│  ├─ SightGlass (Sprite2D)             oil level line, rendered from oil_ml
│  ├─ Funnel (Area2D)                   accepts OilCan drops
│  ├─ PumpPlunger (Area2D)              vertical drag
│  └─ PressureDial (Node2D)             small gauge, shares pressure_gauge.gd
├─ NeedleValve (Area2D)                 knob_dial.gd? no: valve drag in oil_lamp.gd
├─ SpiritPreheater (Node2D)             spirit_preheater.gd
│  ├─ Cup (Sprite2D)
│  └─ Flame (AnimatedSprite2D)
├─ Vaporizer (Node2D)                   vapor_mantle.gd
│  ├─ Tube (Sprite2D)                   color-ramps with temperature
│  └─ Jet (AnimatedSprite2D)            hiss / spit / blue flame
├─ Mantle (Sprite2D)                    glow color ramps by mantle temp
├─ Glow (PointLight2D)                  energy from brightness
├─ HissPlayer (AudioStreamPlayer2D)
└─ SputterPlayer (AudioStreamPlayer2D)
```

Procedure and what the player sees:

1. Pour oil from can into funnel (drag can; `oil_ml += pour_rate * delta`).
2. Pump plunger until the dial needle reaches the green band (>= 120 kPa).
3. Light the spirit cup (click flame).
4. Wait about 23 s for the tube to straw-yellow/blue tint (>= 200 degC) with valve closed.
5. Open needle valve slowly. Vapor ignites at the mantle; mantle glow rises over ~15 s to white.
6. Valve stays open; the lamp is now self-sustaining. Pressure sags with oil consumption, so every ~12 min pump a few strokes.

### 3.2 Reservoir physics (`oil_reservoir.gd`)

Tank volume `V_tank = 2000 mL`. Air headspace `V_air = V_tank - oil_ml`. Isothermal gas: `P_abs * V_air = const` between pump strokes.

- Consumption by oil draw `dV`: headspace grows, `P_abs' = P_abs * V_air / (V_air + dV)`.
- Pump stroke (plunger swept volume `V_p = 60 mL` of free air at 101.3 kPa): `dP_abs = P_atm * V_p / V_air * eta_s`, with `eta_s = 1 - 0.5 * P_g/P_max`, `P_max = 250 kPa gauge`.

Example: oil 1200 mL, `V_air = 800 mL`, one stroke adds `101.3 * 60/800 * 1 = 7.6 kPa`; 26 strokes to 200 kPa gauge (about 35 s of pumping).

Oil flow (needle valve opening `u in [0,1]`): normalized vapor flow `q = u * sqrt(P_g / P_ref)`, `P_ref = 150 kPa`, clamped `[0, 1.25]`. Oil burn `Q_oil = 0.40 mL/s * q`. At full pressure and open valve: `1200 mL / 0.40 = 3000 s = 50 min`.

Cozy floors:
- `P_g_eff = max(P_g, 15 kPa)` unless oil exhausted: a capillary wick keeps a tiny flow (`q >= 0.08`).
- Last `reserve_ml = 30 mL` is the "wick reserve", burned at fixed `q = 0.08`: `30 / (0.40 * 0.08) = 940 s = 15.6 min` of ember glow. No hard black until the tank is truly empty, and then relighting after a pour is the normal startup.

Pressure regimes:

| Regime | P_g (kPa) | Result |
|---|---|---|
| Ember | < 30 | q ~0.45 cap: dim glow, jet hisses softly |
| Dim | 30 .. 90 | q 0.45..0.77 |
| Good | 90 .. 180 | q 0.77..1.1: green band |
| Strong | 180 .. 250 | q up to 1.25; mantle blindingly white, oil burns fast |
| Relief | > 260 | relief valve hisses, pressure held at 255 (no damage) |

Script outline:

```gdscript
class_name OilReservoir
extends Node2D

signal pressure_changed(gauge_kpa: float, fraction: float)
signal oil_changed(oil_ml: float, fraction: float)
signal relief_popped()
signal plunger_stroked(speed: float)

const P_ATM_KPA: float = 101.3
const TANK_ML: float = 2000.0
@export var stroke_ml: float = 60.0
@export var max_gauge_kpa: float = 250.0
@export var relief_kpa: float = 260.0
@export var reserve_ml: float = 30.0
@export var pour_ml_per_s: float = 90.0

var oil_ml: float = 600.0
var p_abs: float = P_ATM_KPA + 120.0

func gauge_kpa() -> float:
    return maxf(p_abs - P_ATM_KPA, 0.0)

func in_reserve() -> bool:
    return oil_ml <= reserve_ml

func pour(delta: float) -> void:
    var air_before: float = TANK_ML - oil_ml
    oil_ml = minf(oil_ml + pour_ml_per_s * delta, TANK_ML - 100.0)  # keep 100 mL air
    p_abs = maxf(p_abs * air_before / (TANK_ML - oil_ml), P_ATM_KPA)  # compression rises P
    _emit_all()

func draw_oil(ml: float) -> void:
    var air_before: float = TANK_ML - oil_ml
    oil_ml = maxf(oil_ml - ml, 0.0)
    p_abs = maxf(p_abs * air_before / (TANK_ML - oil_ml), P_ATM_KPA)
    _emit_all()

## travel_fraction: portion (0..1) of a full stroke swept this frame (downward only)
func pump(travel_fraction: float) -> void:
    var air: float = TANK_ML - oil_ml
    var eta: float = 1.0 - 0.5 * clampf(gauge_kpa() / max_gauge_kpa, 0.0, 1.0)
    p_abs += P_ATM_KPA * (stroke_ml * travel_fraction) / air * eta
    if gauge_kpa() > relief_kpa:
        p_abs = P_ATM_KPA + relief_kpa - 5.0
        relief_popped.emit()
    plunger_stroked.emit(travel_fraction)
    _emit_all()

func vapor_flow(valve_u: float) -> float:
    if oil_ml <= 0.0:
        return 0.0
    if in_reserve():
        return 0.08 * valve_u
    var p_eff: float = maxf(gauge_kpa(), 15.0)
    return clampf(valve_u * sqrt(p_eff / 150.0), 0.0, 1.25)

func _emit_all() -> void:
    pressure_changed.emit(gauge_kpa(), gauge_kpa() / max_gauge_kpa)
    oil_changed.emit(oil_ml, oil_ml / TANK_ML)

func save_state() -> Dictionary:
    return {"oil_ml": oil_ml, "p_abs": p_abs}

func load_state(d: Dictionary) -> void:
    oil_ml = clampf(float(d.get("oil_ml", oil_ml)), 0.0, TANK_ML)
    p_abs = maxf(float(d.get("p_abs", p_abs)), P_ATM_KPA)
```

Plunger input: vertical drag; `travel_fraction = max(dy_px, 0) / stroke_px` where `stroke_px = 40`. Downward = pressurize; upward = free (check valve click on reversal).

### 3.3 Spirit preheater (`spirit_preheater.gd`)

State: `spirit_s` (burn time left, 70 s per fill), `burning` (bool). Power `Q_pre = 220 W` while burning. Refill by dragging the spirit bottle (adds 70 s). Signals: `burning_changed(on)`, `spirit_changed(s)`. When spirit runs out the flame gutters over 2 s (pretty), never explodes. Lighting: click the cup (or drag taper).

### 3.4 Vaporizer + mantle thermodynamics (`vapor_mantle.gd`)

State: `T_v` (vaporizer tube, degC), `T_m` (mantle, degC). Inputs: preheater power `Q_pre` (W), normalized vapor flow `q`, valve opening `u`, ambient `T_a = 15 degC`.

Vapor quality (smooth threshold): `q_v = smoothstep(150, 220, T_v)`.

Combustion strength: `comb = q * (0.25 + 0.75 * q_v)`. Cold vaporizer sends mostly liquid oil: a sooty low flame (25% heat) instead of nothing.

Tube heat balance (game-scaled thermal mass):

```
C_v * dT_v/dt = Q_pre + Q_fb * comb - h_v * (T_v - T_a) - Q_vap * q * q_v      [W]
C_v = 14.4 J/K, h_v = 0.9 W/K, Q_fb = 260 W, Q_vap = 60 W
tau_v = C_v / h_v = 16 s
```

Mantle (first-order radiator, different rise/fall):

```
T_target = T_a + 1385 * clamp(comb, 0, 1.25)            [degC]  (white heat at comb = 1)
dT_m/dt = (T_target - T_m) / tau,  tau = 6 s rising, 9 s falling
```

Luminance (Planck-like, smooth): `B = clamp((T_m - 700) / 700, 0, 1)^1.6`. Lit-flame floor: `B = max(B, 0.08)` whenever `lit and comb > 0.05`. Light energy `energy = lerp(0.15, 2.2, B)`; color ramp: `T_m 700 -> (255,140,40)`, `1100 -> (255,200,120)`, `1400 -> (255,238,205)`.

Ignition rule: `lit` becomes true when `q > 0.05` and (`preheater.burning` or `T_m > 400`). It remains true while `comb > 0.02`. Relighting is always possible via preheater/taper.

Closed-form checks (so tests can assert):

| Case | Equation | Result |
|---|---|---|
| Preheat, valve closed, from 15 degC | `T_eq = 15 + 220/0.9 = 259`; `T(t) = 259 - 244 e^(-t/16)` | 200 degC at `t = 16 ln(244/59) = 22.7 s` |
| Preheat with valve open at q=1 (comb 0.25) | `T_eq = 15 + (220 + 65)/0.9 = 332` | 200 degC at 14 s (but sooty) |
| Self-sustaining at q=1, q_v=1 | `T_eq = 15 + (260 - 60)/0.9 = 237` | stable above 220 |
| Unstable threshold (q=1, no preheat) | solve `T = 15 + (260 c(T) - 60 q_v(T))/0.9` | ~195 degC; below it falls to cold, above it climbs |
| Dim at q = 0.4, no preheat | comb 0.1 at cold: `T_eq ~ 37 degC` | stays dim; fix by preheat or more pressure |

The bistability is a feature: after preheat the lamp "catches" with a visible jump (jet turns from yellow to blue, hiss pitch rises). If the player closes the valve (or lets pressure fall below ~40 kPa) the tube cools slowly; reopening with the tube still warm re-catches without re-preheating.

Brightness timeline from cold (valve closed, preheater on, open at 23 s):

| t (s) | Event | B |
|---|---|---|
| 0 | spirit lit | 0 |
| 23 | tube 200 degC, open valve | 0 |
| 24 | ignition, jet catches | 0.08 floor |
| 30 | T_m ~ 700 | 0 -> 0.1 |
| 38 | T_m ~ 1100 | ~0.35 |
| 45 | T_m ~ 1300 | ~0.73 |
| 60 | T_m ~ 1370 | ~0.95 |

Script core:

```gdscript
class_name VaporMantle
extends Node2D

signal brightness_changed(level: float)      # 0..1 -> LensDrive.set_lamp_level
signal ignited()
signal sputtered()                            # liquid spitting, hint cue
signal went_dim()

const T_AMBIENT: float = 15.0
@export var c_v: float = 14.4
@export var h_v: float = 0.9
@export var q_fb: float = 260.0
@export var q_vap: float = 60.0
@export var q_pre_w: float = 220.0
@export var t_flame_span: float = 1385.0

var t_v: float = T_AMBIENT
var t_m: float = T_AMBIENT
var lit: bool = false
var valve_u: float = 0.0
var preheat_on: bool = false
var flow_q: float = 0.0     # set by OilLamp from reservoir.vapor_flow(valve_u)

@onready var _glow: PointLight2D = $"../Glow"
@onready var _mantle: Sprite2D = $"../Mantle"
@onready var _hiss: AudioStreamPlayer2D = $"../HissPlayer"
@onready var _sputter: AudioStreamPlayer2D = $"../SputterPlayer"

var _last_b: float = -1.0
var _sputter_cd: float = 0.0

func vapor_quality() -> float:
    return smoothstep(150.0, 220.0, t_v)

func combustion() -> float:
    return flow_q * (0.25 + 0.75 * vapor_quality())

func brightness() -> float:
    var b: float = pow(clampf((t_m - 700.0) / 700.0, 0.0, 1.0), 1.6)
    if lit and combustion() > 0.05:
        b = maxf(b, 0.08)
    return b

func _physics_process(delta: float) -> void:
    var comb: float = combustion()
    var qv: float = vapor_quality()
    var q_pre: float = q_pre_w if preheat_on else 0.0
    var dtv: float = (q_pre + q_fb * comb - h_v * (t_v - T_AMBIENT) - q_vap * flow_q * qv) / c_v
    t_v += dtv * delta
    if not lit and flow_q > 0.05 and (preheat_on or t_m > 400.0):
        lit = true
        ignited.emit()
    elif lit and comb < 0.02:
        lit = false
        went_dim.emit()
    var target: float = T_AMBIENT + t_flame_span * clampf(comb if lit else 0.0, 0.0, 1.25)
    var tau: float = 6.0 if target > t_m else 9.0
    t_m += (target - t_m) * (1.0 - exp(-delta / tau))
    _sputter_cd = maxf(_sputter_cd - delta, 0.0)
    if lit and qv < 0.5 and flow_q > 0.3 and _sputter_cd <= 0.0:
        _sputter_cd = randf_range(0.6, 1.8)   # liquid spitting, "preheat more"
        _sputter.pitch_scale = randf_range(0.9, 1.1)
        _sputter.play()
        sputtered.emit()
    _present(delta)

func _present(delta: float) -> void:
    var b: float = brightness()
    _glow.energy = lerpf(0.15, 2.2, b)
    _glow.texture_scale = lerpf(0.9, 1.4, b)
    _mantle.modulate = _mantle_color(t_m)
    _hiss.volume_db = linear_to_db(clampf(flow_q, 0.001, 1.25)) - 14.0
    _hiss.pitch_scale = 0.8 + 0.5 * vapor_quality()
    if absf(b - _last_b) > 0.005:
        _last_b = b
        brightness_changed.emit(b)

func _mantle_color(temp_c: float) -> Color:
    var t: float = clampf((temp_c - 700.0) / 700.0, 0.0, 1.0)
    var warm: Color = Color8(255, 140, 40)
    var mid: Color = Color8(255, 200, 120)
    var hot: Color = Color8(255, 238, 205)
    return warm.lerp(mid, minf(t * 2.0, 1.0)).lerp(hot, maxf(t * 2.0 - 1.0, 0.0))

func save_state() -> Dictionary:
    return {"t_v": t_v, "t_m": t_m, "lit": lit}

func load_state(d: Dictionary) -> void:
    t_v = float(d.get("t_v", T_AMBIENT))
    t_m = float(d.get("t_m", T_AMBIENT))
    lit = bool(d.get("lit", false))
```

### 3.5 `oil_lamp.gd` wiring (thin)

```gdscript
class_name OilLamp
extends Node2D
## Glue only: valve knob drag plus pushing reservoir flow into the vaporizer.

signal brightness_changed(level: float)

@onready var _res: OilReservoir = $Reservoir
@onready var _vap: VaporMantle = $Vaporizer
@onready var _pre: SpiritPreheater = $SpiritPreheater

var valve_u: float = 0.0

func _ready() -> void:
    _vap.brightness_changed.connect(func(b: float) -> void: brightness_changed.emit(b))
    _pre.burning_changed.connect(func(on: bool) -> void: _vap.preheat_on = on)

func set_valve(u: float) -> void:
    valve_u = clampf(u, 0.0, 1.0)

func _physics_process(delta: float) -> void:
    var q: float = _res.vapor_flow(valve_u)
    _vap.flow_q = q
    if q > 0.0:
        _res.draw_oil(0.40 * q * delta)       # mL
```

The glue is not a manager: it forwards a single float (flow) and one signal. Parent LanternRoom connects `OilLamp.brightness_changed` to `LensDrive.set_lamp_level`.

### 3.6 Needle valve feel

Drag the knob in a circle (reuse the angular-delta technique of 1.6). Range 0..270 deg for `u`. Detents every 30 deg (soft click), stiff at 0 (closed). Hiss sound begins at `u = 0.03`, spits when tube is cold and `u` is high. This is the main skill: "open slowly, listen".

### 3.7 Tactile map

| Quantity | Visual | Audio | Hand-feel |
|---|---|---|---|
| Oil level | Sight-glass amber line | Pour glug pitch rises as tank fills | Can tilts on drag |
| Pressure | Small dial needle, damped (same as foghorn gauge) | Pump "chuff" per stroke, pitch drops as pressure rises | Plunger drag gets stiffer: follow speed -35% at full |
| Preheat | Tube color: grey -> straw -> blue tint | Spirit flame crackle, tube ticks while expanding | Wait: no forced input |
| Vapor catch | Jet turns yellow -> blue, mantle blooms | Hiss pitch up, soft "whump" at ignition | Haptic 15 ms pulse at ignition |
| Mantle heat | Orange -> warm white, glow radius grows | Faint filament-like sizzle at low T | - |
| Low oil / low pressure | Mantle dims to ember orange | Hiss softens | Pump again and it recovers |

---

## 4. Foghorn: Pressure, Valve, Echo Across the Sea

### 4.1 Mechanism

A brass compressed-air tank on the gallery. A hand bellows (vertical pump lever) fills it. A valve lever (pull-lanyard) releases air to a diaphone horn. The horn's sound travels across the sea at finite speed, echoes off cliffs and islets, and ships hear it with delay and attenuation.

### 4.2 Scene tree

```
Foghorn (Node2D)                        foghorn.gd   [group "foghorn"]
├─ AirTank (Node2D)                     air_tank.gd
│  ├─ TankSprite (Sprite2D)
│  ├─ BellowsHandle (Area2D)            drag vertical; pumps
│  ├─ ReliefValve (Sprite2D)            hisses puff on pop
│  └─ HuffPlayer (AudioStreamPlayer2D)  pump air noise
├─ PressureGauge (Node2D)               pressure_gauge.gd
│  ├─ Face (Sprite2D)                   dial with bands
│  └─ Needle (Sprite2D)
├─ ValveLever (Node2D)                  valve_lever.gd
│  ├─ Arm (Sprite2D)
│  ├─ Latch (Sprite2D)
│  └─ ClunkPlayer (AudioStreamPlayer2D)
├─ HornBell (Node2D)
│  ├─ BellSprite (AnimatedSprite2D)     vibrates, dust puff frames
│  └─ HornPlayer (AudioStreamPlayer2D)  looped diaphone sample, bus "Horn"
├─ EchoPlayers (Node)                   6 x AudioStreamPlayer on "Echo_Near/Mid/Far"
├─ WaveRing (Node2D)                    draws expanding ring on the sea
└─ ShakeAnchor (Node2D)                 child of gallery camera rig
```

Audio buses: `Horn` (dry), `Sea` (AudioEffectReverb + AudioEffectLowPassFilter), `Echo_Near` (LP 4000 Hz), `Echo_Mid` (LP 1800 Hz), `Echo_Far` (LP 800 Hz). Echo buses send to `Sea`.

### 4.3 Signals

| Signal | Payload | Listeners |
|---|---|---|
| `pressure_changed(gauge_kpa, fraction)` | AirTank | PressureGauge.set_target, Foghorn |
| `relief_popped()` | AirTank | ReliefValve FX |
| `valve_changed(u)` | ValveLever | Foghorn |
| `blast_started(origin, source_level_db, pitch_scale)` | Foghorn | Ships (ShipEar), WaveRing |
| `blast_ended(duration_s)` | Foghorn | logbook toy, ships |
| `echo_returned(surface_id, delay_s, level_db)` | Foghorn (per tap) | lighthouse log, "listening ring" sprite |
| `horn_ready_changed(ready)` | Foghorn | gauge band glow |

### 4.4 Pressure model (`air_tank.gd`)

Pump (isothermal, free air volume `V_s` into tank `V_t`): `dP_g = P_atm * (V_s / V_t) * eta(P)`, `eta(P) = 1 - 0.5 * P_g/P_max`. With `V_t = 50 L`, `V_s = 10 L`: first stroke adds `101.3 * 0.2 = 20.3 kPa`, a late stroke (at 600 kPa) adds `20.3 * (1 - 0.43) = 11.6 kPa`.

| Gauge target | Strokes (full) | Time at 1 stroke/s |
|---|---|---|
| 350 kPa (two standard blasts) | ~21 | 21 s |
| 700 kPa (full) | ~44 | 44 s |

Venting through the valve (orifice; choked-flow form `dP_abs/dt = -lambda' * u * P_abs` simplifies to a gauge-exponential so pressure approaches but never crosses zero):

```
dP_g/dt = - lambda * u * P_g,  lambda = 0.18 s^-1
P_g(t) = P_g0 * exp(-lambda * u * t)
```
Choked derivation: `lambda' = 0.0404 * Cd * A * R * sqrt(T0) / V_t = 0.18 s^-1` for orifice area `A = 0.57 cm^2` (about 8.5 mm bore), `Cd = 0.8`, `R = 287 J/(kg*K)`, `T0 = 293 K`, `V_t = 0.05 m^3`.

Standard 3 s blast at `u = 1` from 700 kPa: `P = 700 * exp(-0.54) = 408 kPa`; a second: 238; third: 139; fourth: 81. Four standard blasts per tank fill, plus a tail of ever-quieter blasts.

| Constant | Value |
|---|---|
| P_max (full-scale gauge) | 700 kPa |
| Relief pops at | 720 kPa gauge (reseats at 700) |
| Min "good" pressure | 350 kPa |
| Green band | 350..700 |
| Dusk band (blue) | 150..350 |
| Sigh band | 0..150 (no red zone, cozy) |

Script:

```gdscript
class_name AirTank
extends Node2D

signal pressure_changed(gauge_kpa: float, fraction: float)
signal relief_popped()
signal pumped(speed: float)

const P_ATM_KPA: float = 101.3
@export var tank_volume_l: float = 50.0
@export var stroke_volume_l: float = 10.0
@export var max_gauge_kpa: float = 700.0
@export var relief_kpa: float = 720.0
@export var vent_lambda: float = 0.18      # 1/s at full valve

@onready var _huff: AudioStreamPlayer2D = $HuffPlayer

var p_gauge: float = 300.0

func fraction() -> float:
    return clampf(p_gauge / max_gauge_kpa, 0.0, 1.0)

## travel: fraction of a full bellows stroke swept this frame (down-stroke only)
func pump(travel: float, speed: float) -> void:
    var eta: float = 1.0 - 0.5 * fraction()
    p_gauge += P_ATM_KPA * (stroke_volume_l * travel) / tank_volume_l * eta
    if p_gauge > relief_kpa:
        p_gauge = max_gauge_kpa
        relief_popped.emit()
    _huff.volume_db = -18.0 + minf(speed, 4.0) * 3.0
    _huff.pitch_scale = 1.1 - 0.35 * fraction()
    if not _huff.playing:
        _huff.play()
    pumped.emit(speed)
    pressure_changed.emit(p_gauge, fraction())

func vent(valve_u: float, delta: float) -> void:
    if valve_u <= 0.0:
        return
    p_gauge *= exp(-vent_lambda * valve_u * delta)
    pressure_changed.emit(p_gauge, fraction())

func save_state() -> Dictionary:
    return {"p_gauge": p_gauge}

func load_state(d: Dictionary) -> void:
    p_gauge = clampf(float(d.get("p_gauge", p_gauge)), 0.0, relief_kpa)
```

Bellows input: vertical drag of the handle between `y_top` and `y_bot` (48 px). `travel = max(dy, 0)/48` per motion event; the up-stroke gives the check-valve "tk" and no pressure. Pointer speed `speed = |dy|/48/dt` in strokes/s feeds the huff.

### 4.5 Gauge needle (second-order, `pressure_gauge.gd`)

```
theta'' = w_n^2 (theta_target - theta) - 2 zeta w_n theta'
w_n = 14 rad/s, zeta = 0.45  ->  overshoot = exp(-pi*zeta/sqrt(1-zeta^2)) = 20.5%, settling (2%) ~ 4/(zeta*w_n) = 0.63 s
theta_target = lerp(-135 deg, +135 deg, P_g / P_max)
```

Pressure jitter when blasting: add `0.6 deg * A(t)` noise to the target (vibration through the pipe).

```gdscript
class_name PressureGauge
extends Node2D

@export var natural_freq: float = 14.0       # rad/s
@export var damping_ratio: float = 0.45
@export var sweep_deg: float = 135.0

@onready var _needle: Sprite2D = $Needle

var _theta: float = deg_to_rad(-135.0)
var _omega: float = 0.0
var _target: float = deg_to_rad(-135.0)
var _vibe: float = 0.0

func set_fraction(f: float) -> void:
    _target = deg_to_rad(lerpf(-sweep_deg, sweep_deg, clampf(f, 0.0, 1.0)))

func set_vibration(amplitude: float) -> void:
    _vibe = clampf(amplitude, 0.0, 1.0)

func _physics_process(delta: float) -> void:
    var tgt: float = _target + deg_to_rad(0.6) * _vibe * sin(Time.get_ticks_msec() * 0.09)
    var accel: float = natural_freq * natural_freq * (tgt - _theta) - 2.0 * damping_ratio * natural_freq * _omega
    _omega += accel * delta
    _theta += _omega * delta
    _needle.rotation = snappedf(_theta, TAU / 128.0)    # pixel-art snap, 128 steps
```

Wire: `AirTank.pressure_changed` -> `PressureGauge.set_fraction(fraction)`.

### 4.6 Valve lever (`valve_lever.gd`)

Pivot lever pulled down by dragging. Angle range 0..55 deg; `u = angle / 55`. A spring returns it to 0 with `tau = 0.25 s` when released. A latch detent at `u >= 0.95` holds it open until the next pull.

Quick tap (pull and release within 0.25 s) triggers a "standard blast": the latch holds for `blast_s = 3.0 s` then auto-releases (counterweight). Hold longer to hold the valve open freely (up to 8 s). Cozy: tap spam queues nothing; a blast in progress ignores new taps.

```gdscript
class_name ValveLever
extends Node2D

signal valve_changed(u: float)
signal pulled_quick()
signal clunked(kind: StringName)         # &"crack", &"latch", &"release"

@export var max_angle_deg: float = 55.0
@export var return_tau_s: float = 0.25
@export var standard_blast_s: float = 3.0
@export var tap_window_s: float = 0.25

@onready var _arm: Sprite2D = $Arm
@onready var _clunk: AudioStreamPlayer2D = $ClunkPlayer

var u: float = 0.0
var _held: bool = false
var _hold_time: float = 0.0
var _auto_hold_left: float = 0.0
var _latched: bool = false

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.button_index != MOUSE_BUTTON_LEFT:
            return
        if mb.pressed and get_local_mouse_position().length() < 40.0:
            _held = true
            _hold_time = 0.0
            get_viewport().set_input_as_handled()
        elif not mb.pressed and _held:
            _held = false
            if _hold_time <= tap_window_s and _auto_hold_left <= 0.0:
                _auto_hold_left = standard_blast_s
                pulled_quick.emit()
            _latched = false

func _physics_process(delta: float) -> void:
    var prev: float = u
    if _held:
        _hold_time += delta
        var a: float = clampf(get_local_mouse_position().angle() - deg_to_rad(90.0), 0.0, deg_to_rad(max_angle_deg))
        u = lerpf(u, a / deg_to_rad(max_angle_deg), 1.0 - exp(-delta / 0.04))
    elif _auto_hold_left > 0.0:
        _auto_hold_left -= delta
        u = lerpf(u, 1.0, 1.0 - exp(-delta / 0.05))
    else:
        u = lerpf(u, 0.0, 1.0 - exp(-delta / return_tau_s))
    if prev < 0.12 and u >= 0.12:
        clunked.emit(&"crack")
        _clunk.pitch_scale = 0.8
        _clunk.play()
    if not _latched and u >= 0.95:
        _latched = true
        clunked.emit(&"latch")
        Input.vibrate_handheld(20, 0.6)
    if u < 0.05 and prev >= 0.05:
        clunked.emit(&"release")
    _arm.rotation = snappedf(deg_to_rad(max_angle_deg) * u, TAU / 128.0)
    if absf(u - prev) > 0.002:
        valve_changed.emit(u)
```

### 4.7 Horn voice (`foghorn.gd`)

Envelope (1-pole attack/decay, mimics air filling the horn):

```
dA/dt = (A_target - A) / tau, tau_a = 0.35 s (rising), tau_d = 0.60 s (falling)
A_target = u * pressure_gate,  pressure_gate = smoothstep(10, 150, P_g)  (hushed floor 0.15)
```

Source level and pitch (cozy: always sounds):

```
p = P_g / 700
L_src(1 m) = 84 + 16 * sqrt(p)          [dB re arbitrary 1 m]
pitch_scale = 0.88 + 0.12 * p            (base sample 96 Hz -> 84..96 Hz)
volume_db = linear_to_db(max(A, 1e-4)) + (L_src - 100) * 0.6
```

Diaphone "grunt": on release, `pitch_scale *= 1 - 0.2 * smoothstep(0, 1, release_t / 0.4)` over 0.4 s (descending end-grunt).

Source level vs range table (air attenuation 0.5 dB/km at 96 Hz, ambient audibility floor 28 dB):

| p | L_src | audible range, ship (km) |
|---|---|---|
| 1.00 | 100 | 3.2 |
| 0.50 | 95.3 | 2.1 |
| 0.20 | 91.2 | 1.4 |
| 0.05 | 87.6 | 1.0 |
| 0.00 | 84.0 | 0.6 (still a soft sigh) |

### 4.8 Propagation math (delay, loss, echoes)

Scale: `METERS_PER_PX = 2.5`. Speed of sound `c = 331.3 + 0.606 * T_C`; at 8 degC `c = 336.1 m/s = 134 px/s`.

Wind (optional, from Weather node, `w` in m/s along bearing): `c_eff = c + w · n` where `n` is unit propagation direction (wind component along path). 5 m/s tailwind gives +1.5%.

Direct path arrival time: `t_arr = t_blast + d_m / c_eff`.

Level at range (dB):
```
L(d) = L_src - 20*log10(max(d_m, 1)) - alpha * d_m / 1000 + carry_bonus
alpha = 0.5 dB/km (96 Hz), carry_bonus = +3 dB at night (temperature inversion), 0 at day
```

Echo from reflector `s` with path `d_out + d_back`:
```
path_m = (|src - s| + |s - listener|) * METERS_PER_PX
t_echo = path_m / c_eff
L_echo = L_src - 20*log10(path_m) - alpha * path_m/1000 - reflection_loss_dB(s)
```
Reflection losses: sheer cliff 3 dB, rocky islet 9 dB, distant shore 6 dB, open water 99 (none).

Examples (src and listener co-located on the island):

| Reflector | Range (m) | Round trip delay (s) | Level (p=1, dB) | Audible? |
|---|---|---|---|---|
| Cliff face | 400 | 2.4 | 100 - 58 - 0.4 - 3 = 38.6 | yes |
| Islet | 1200 | 7.1 | 100 - 67.6 - 1.2 - 9 = 22.2 | barely (near floor 25) |
| Far shore | 3000 | 17.9 | 100 - 75.6 - 3.0 - 6 = 15.4 | no |
| Game-friendly cliff at 1500 m | 1500 | 8.9 | 100 - 69.5 - 1.5 - 3 = 26.0 | at floor, ghostly |

Rule of thumb for the player: `distance_m = c * delay_s / 2` (one second of echo is ~170 m).

Echo filtering (distance dulls high frequencies):
```
cutoff_hz = clamp(6000 * exp(-path_km / 1.2), 350, 6000)
bus = Echo_Near (path < 1.5 km, LP 4000), Echo_Mid (< 4 km, LP 1800), Echo_Far (LP 800)
volume_db_echo = clamp((L_echo - 100) * 0.6, -60, 0)
```

Reverb (sea surface tail) by fog fraction `f in [0,1]` (AudioEffectReverb on "Sea"):
```
room_size   = 0.85 + 0.10 f
damping     = 0.45 + 0.35 f
wet         = 0.18 + 0.20 f
dry         = 1.0
predelay_msec = 80
predelay_feedback = 0.2
spread = 1.0
```
Fog makes the horn wetter and duller: a thick, muffled world. A single pre-echo tap at 0.6 s represents the lantern-room balcony (fixed).

Echo spawn:

```gdscript
func _spawn_echoes(source_level_db: float, pitch: float, listener_px: Vector2) -> void:
    for node: Node in get_tree().get_nodes_in_group("echo_surfaces"):
        var surf: EchoSurface = node as EchoSurface
        if surf == null:
            continue
        var path_m: float = (global_position.distance_to(surf.global_position) + surf.global_position.distance_to(listener_px)) * METERS_PER_PX
        var delay_s: float = path_m / _effective_c(surf.global_position)
        var level_db: float = source_level_db - 20.0 * log(maxf(path_m, 1.0)) / log(10.0) - ALPHA_DB_PER_KM * path_m / 1000.0 - surf.reflection_loss_db + carry_bonus_db
        if level_db < AUDIBLE_FLOOR_DB:
            continue
        _play_echo_after(delay_s, level_db, path_m, pitch, surf.surface_id)

func _play_echo_after(delay_s: float, level_db: float, path_m: float, pitch: float, surface_id: StringName) -> void:
    await get_tree().create_timer(delay_s).timeout
    var p: AudioStreamPlayer = _free_echo_player()
    if p == null:
        return
    p.bus = &"Echo_Near" if path_m < 1500.0 else (&"Echo_Mid" if path_m < 4000.0 else &"Echo_Far")
    p.volume_db = clampf((level_db - 100.0) * 0.6, -60.0, 0.0)
    p.pitch_scale = pitch
    p.play()
    echo_returned.emit(surface_id, delay_s, level_db)
```

Echoes replay the horn sample from the start; for a long blast the echo also lasts `blast_s` (the sample is looped by `HornPlayer` and the echo players use a pre-rendered 3 s "echo blast" `AudioStreamWAV` with the same envelope). Cozy shortcut: echoes are always the standard 3 s shape, scaled by `A_peak`.

`EchoSurface` (Node2D in group `"echo_surfaces"`): exports `surface_id: StringName`, `reflection_loss_db: float`. No logic, it is a prop (cliff, islet, headland).

Visual: `WaveRing` draws a ring with radius `r_px = c_px_s * t` (134 px/s), alpha fading `exp(-t/9)`. When a ring crosses a surface a small ripple puff appears; the echo ring returns inward. The player can literally time the return.

### 4.9 Ship hearing (`ship_ear.gd` on each ship)

```gdscript
class_name ShipEar
extends Node

signal horn_heard(bearing_rad: float, level_db: float)
signal horn_lost()

const METERS_PER_PX: float = 2.5
const ALPHA_DB_PER_KM: float = 0.5
@export var hearing_floor_db: float = 28.0
@export var c_mps: float = 336.1

@onready var _ship: Node2D = get_parent() as Node2D

func _ready() -> void:
    var horn: Foghorn = get_tree().get_first_node_in_group("foghorn") as Foghorn
    if horn != null:
        horn.blast_started.connect(_on_blast_started)

func _on_blast_started(origin: Vector2, source_level_db: float, pitch_scale: float) -> void:
    var d_m: float = origin.distance_to(_ship.global_position) * METERS_PER_PX
    var level_db: float = source_level_db - 20.0 * log(maxf(d_m, 1.0)) / log(10.0) - ALPHA_DB_PER_KM * d_m / 1000.0
    if level_db < hearing_floor_db:
        return
    await get_tree().create_timer(d_m / c_mps).timeout
    var bearing: float = _ship.global_position.angle_to_point(origin)
    horn_heard.emit(bearing, level_db)
```

Ship behavior on `horn_heard` (cozy): slows by 30%, steers a gentle 8 deg toward bearing correct for known channel (blind navigation is convenient, not required), rings its bell (reply pulse back to lighthouse as a `ShipBell` ring on the sea). Ships that cannot hear any horn or see any light in fog anchor and bob safely; they wait. Nothing wrecks.

Ship confidence: `confidence += 0.15` per horn heard, `+0.1 * light_quality` per flash recognized; above 1.0 the ship proceeds at full speed; decays 0.01/s. Purely cosmetic reward: warmer cabin lamp.

### 4.10 Blast schedule and ship signals (horn character)

| Pattern | Blasts | Use |
|---|---|---|
| Standard (tap) | 1 x 3.0 s, every ~30 s | default fog duty |
| Short | 1.0 s | "I'm here", quiet nights, 1/3 air |
| Long | 6.0 s (hold 6 s) | lost ship reply, uses 66% of pressure fraction at 0.18/s |
| Double | 2 x 1.0 s with 1.0 s gap | special callout (festival) |

Air use per blast (fraction of current gauge): `1 - exp(-0.18 * u * t)`: 1 s: 16.5%, 3 s: 41.7%, 6 s: 66.0%.

### 4.11 Foghorn coordinator (`foghorn.gd`)

```gdscript
class_name Foghorn
extends Node2D
## Voices the horn from valve + pressure; emits blast signals; spawns echoes.

signal blast_started(origin: Vector2, source_level_db: float, pitch_scale: float)
signal blast_ended(duration_s: float)
signal echo_returned(surface_id: StringName, delay_s: float, level_db: float)
signal horn_ready_changed(ready: bool)

const METERS_PER_PX: float = 2.5
const ALPHA_DB_PER_KM: float = 0.5
const AUDIBLE_FLOOR_DB: float = 25.0
const TAU_ATTACK: float = 0.35
const TAU_DECAY: float = 0.60

@export var temperature_c: float = 8.0
@export var carry_bonus_db: float = 0.0
@export var wind_mps: Vector2 = Vector2.ZERO

@onready var _tank: AirTank = $AirTank
@onready var _gauge: PressureGauge = $PressureGauge
@onready var _lever: ValveLever = $ValveLever
@onready var _horn: AudioStreamPlayer2D = $HornBell/HornPlayer
@onready var _bell: AnimatedSprite2D = $HornBell/BellSprite

var _amp: float = 0.0
var _blasting: bool = false
var _blast_time: float = 0.0
var _release_t: float = 1.0
var _ready_flag: bool = false

func _ready() -> void:
    _tank.pressure_changed.connect(_on_pressure_changed)
    _gauge.set_fraction(_tank.fraction())
    _horn.stream_paused = false

func _on_pressure_changed(_g: float, fraction: float) -> void:
    _gauge.set_fraction(fraction)
    var ready: bool = _g >= 350.0
    if ready != _ready_flag:
        _ready_flag = ready
        horn_ready_changed.emit(ready)

func _physics_process(delta: float) -> void:
    var u: float = _lever.u
    _tank.vent(u, delta)
    var gate: float = maxf(smoothstep(10.0, 150.0, _tank.p_gauge), 0.15)
    var target: float = u * gate
    var tau: float = TAU_ATTACK if target > _amp else TAU_DECAY
    _amp += (target - _amp) * (1.0 - exp(-delta / tau))
    var p: float = _tank.fraction()
    var pitch: float = 0.88 + 0.12 * p
    if u < 0.05:
        _release_t = minf(_release_t + delta / 0.4, 1.0)
    else:
        _release_t = 0.0
    var grunt: float = 1.0 - 0.2 * smoothstep(0.0, 1.0, _release_t) if _amp > 0.05 else 1.0
    _horn.pitch_scale = pitch * grunt
    var level: float = 84.0 + 16.0 * sqrt(p)
    _horn.volume_db = linear_to_db(maxf(_amp, 1e-4)) + (level - 100.0) * 0.6
    if _amp > 0.05 and not _horn.playing:
        _horn.play()
    if _amp <= 0.02 and _horn.playing:
        _horn.stop()
    _gauge.set_vibration(_amp)
    if not _blasting and u > 0.12 and _amp > 0.05:
        _blasting = true
        _blast_time = 0.0
        var origin: Vector2 = global_position
        blast_started.emit(origin, level, pitch)
        _spawn_echoes(level, pitch, origin)
    elif _blasting:
        _blast_time += delta
        if u < 0.05 and _amp < 0.1:
            _blasting = false
            blast_ended.emit(_blast_time)
    _shake(_amp * p, delta)

func _effective_c(to_pos: Vector2) -> float:
    var c: float = 331.3 + 0.606 * temperature_c
    var n: Vector2 = (to_pos - global_position).normalized()
    return c + wind_mps.dot(n)

func _shake(strength: float, delta: float) -> void:
    # Integer-pixel camera rumble at 30 Hz (pixel-art safe). Camera rig owns the offset.
    var cam: Camera2D = get_viewport().get_camera_2d()
    if cam == null:
        return
    var amp_px: float = 1.5 * strength
    if Engine.get_physics_frames() % 2 == 0:
        cam.offset = Vector2(roundf(randf_range(-amp_px, amp_px)), roundf(randf_range(-amp_px, amp_px)))

func save_state() -> Dictionary:
    return {}   # tank state saved by AirTank itself
```

(`_spawn_echoes` and `_play_echo_after` as in 4.8; `_free_echo_player` returns the first idle `AudioStreamPlayer` in `$EchoPlayers`.)

### 4.12 Tactile map

| Quantity | Visual | Audio | Hand-feel |
|---|---|---|---|
| Pressure | Needle with 20% overshoot, pulses under blast vibration | Pump huff pitch falls as tank fills | Bellows handle follow slows 35% near full |
| Valve pull | Arm angle 0..55 deg, latch click at 95% | Crack at 12%, latch clunk at 95%, release clunk | Haptic 20 ms @ 0.6 on latch; rumble `strong = 0.6 A` during blast |
| Blast | Bell sprite vibrates, dust puff, window glints | Diaphone swell, descending end-grunt | Camera rumble 1.5 px * A * p, 30 Hz integer steps |
| Echo | Ring on water, ripple at the surface | Delayed, dull, quieter copy through Echo_* buses | Counting delay measures distance (170 m/s of delay) |
| Low pressure | Needle in dusk-blue band | Pitch drops to 0.88, quieter | Pump to recover; no penalty |
| Over-pressure | Relief valve puff | Hiss | Pressure parks at 700; pumping harmless |

---

## 5. LanternRoom Wiring (the one place everything meets)

```
LanternRoom (Node2D)                    lantern_room.gd (wiring only, ~30 lines)
├─ ClockworkMechanism
├─ LensDrive
├─ OilLamp
├─ Foghorn                              (on gallery; instanced here for convenience)
└─ ShakeRig
```

```gdscript
extends Node2D

@onready var _clock: ClockworkMechanism = $ClockworkMechanism
@onready var _lens: LensDrive = $LensDrive
@onready var _lamp: OilLamp = $OilLamp

func _ready() -> void:
    _clock.drive_torque_changed.connect(_lens.set_drive_torque)
    _lens.omega_changed.connect(_clock.set_lens_omega)
    _lamp.brightness_changed.connect(_lens.set_lamp_level)
    _lens.set_drive_torque(_clock.lens_torque_nm())
```

Signal graph:

```
WindingCrank --turned--> ClockworkMechanism --drive_torque_changed--> LensDrive
LensDrive --omega_changed--> ClockworkMechanism   (weight falls only as fast as lens turns)
OilLamp --brightness_changed--> LensDrive.set_lamp_level
Foghorn --blast_started--> ShipEar (via group "foghorn")
AirTank --pressure_changed--> PressureGauge
ValveLever --valve_changed--> (Foghorn polls lever.u each tick)
```

Cycles are avoided: ClockworkMechanism -> LensDrive carries torque; LensDrive -> ClockworkMechanism carries speed. Both are one-float updates, no recursion.

---

## 6. Persistence and Offline Catch-Up (cozy-capped)

Every mechanism implements `save_state() -> Dictionary` / `load_state(Dictionary)`. On launch, `lantern_room.gd` computes `elapsed_s = now - last_saved_unix` and calls the closed-form catch-ups with the offline drain cap `0.6` (the village children "keep an eye on it", so the lighthouse never completely runs out while the player is away):

| Mechanism | Offline formula | Cap |
|---|---|---|
| Clockwork height | `h' = max(h - omega_nom * r_d / G * elapsed, h_min)` | `h_min = 0.4 * h` (drain cap 0.6) |
| Oil | `oil' = max(oil - 0.40 * q_avg * elapsed, oil_min)` with `q_avg = 0.9`, assumes lit only if lamp was lit | `oil_min = max(reserve_ml, 0.4 * oil)` |
| Pressure | recomputed from `P_abs * V_air / V_air'` | min 60 kPa |
| Vaporizer / mantle | restored to cold, `lit = false` unless `elapsed < 120 s` | relight is part of play |
| Foghorn tank | unchanged (no leak) | - |

Gameplay result: coming back after a night, the lens is slow and warm-ember, the weight is partly up, and the tank has plenty; one short tending session restores everything.

---

## 7. Master Tuning Table

| Group | Parameter | Value | Unit |
|---|---|---|---|
| Clockwork | weight mass | 40 | kg |
| | drum radius | 0.08 | m |
| | shaft drop | 6.0 | m |
| | train ratio G | 15 | - |
| | efficiency | 0.70 | - |
| | wind ratio | 4 | crank rev/drum rev |
| | soft zone | 0.6 | m |
| | maintenance factor | 0.10 | - |
| | full-wind run time | 35.8 | min |
| Crank | ratchet teeth | 24 | - |
| | follow speed max | 9 | rad/s |
| | resistance range | 0.25..0.75 | - |
| Lens | inertia | 8.0 | kg*m^2 |
| | governor k | 5.248 | N*m*s^2/rad^2 |
| | viscous c | 0.05 | N*m*s/rad |
| | nominal period | 12 | s |
| | trim range | +-1 -> 9.7..14.0 | s |
| | beam FWHM | 8 | deg |
| | slot pitch | 40 | deg (9 slots) |
| Oil | tank | 2000 | mL |
| | initial oil | 1200 | mL |
| | burn | 0.40 | mL/s at q=1 |
| | reserve | 30 | mL (15.6 min ember) |
| | stroke | 60 | mL |
| | P_max / relief | 250 / 260 | kPa gauge |
| | P_ref | 150 | kPa |
| Thermal | C_v | 14.4 | J/K |
| | h_v | 0.9 | W/K |
| | Q_pre | 220 | W |
| | spirit | 70 | s per fill |
| | Q_fb / Q_vap | 260 / 60 | W |
| | mantle tau up/down | 6 / 9 | s |
| | catch threshold | ~195 | degC |
| Foghorn | tank | 50 | L |
| | stroke | 10 | L |
| | P_max / relief | 700 / 720 | kPa gauge |
| | vent lambda | 0.18 | 1/s |
| | needle w_n / zeta | 14 / 0.45 | rad/s / - |
| | tau attack/decay | 0.35 / 0.60 | s |
| | L_src range | 84..100 | dB |
| | pitch range | 0.88..1.00 | scale |
| Acoustics | meters/px | 2.5 | m |
| | c (8 degC) | 336.1 | m/s |
| | alpha | 0.5 | dB/km |
| | audible floor | 25 (echo) / 28 (ship) | dB |
| | echo bus cutoffs | 4000/1800/800 | Hz |

---

## 8. Acceptance Checklist (automated where possible)

1. Clockwork run time with lens at equilibrium: `H / (omega_eq * r_d / G)` within 1% of 2149 s. Assert in a headless test stepping 60 Hz for 600 s and checking `h` loss `= 0.5236*0.08/15*600 = 1.676 m`.
2. Lens eq at `f = 1`: `omega` converges to 0.5236 +- 0.5% within 6 s of starting from 0.
3. At `h = 0`, `omega_eq = 0.5236 * sqrt(0.1) = 0.1656 rad/s` (period 37.9 s). Never 0.
4. `LightCharacter.flash_times(12.0)` for Fl(2+1): `[0.0, 1.333.., 5.333..]` (mod ordering after sort). For Fl(2), spacing 1.333 s.
5. Preheat test: valve closed, `Q_pre = 220 W`: `T_v >= 200` at `t = 22.7 s +- 0.5 s`; then open valve: `T_m >= 1300` within 25 s.
6. Bistability test: set `T_v = 185`, `q = 1`, no preheat: `T_v` decays below 150 within 45 s; set `T_v = 205`: converges to ~237.
7. Oil: with 1200 mL at 200 kPa gauge and constant `q = 1`, pressure after 400 mL consumed ~ 99 kPa gauge (`301 * 800/1200 - 101.3`).
8. Foghorn: 3 s blast from 700 kPa ends at `408 +- 3 kPa`.
9. Gauge: step input 0 -> 1 fraction shows overshoot between 18% and 23%.
10. Echo: cliff at 400 px (1000 m): first echo `2000/336.1 = 5.95 s` after blast; level `100 - 66 - 1 - 3 = 30 dB` plays on `Echo_Mid`? No: path 2000 m is >= 1500 so `Echo_Mid` (LP 1800 Hz). Test asserts bus selection and delay within 0.05 s.
11. Cozy audit: all states reachable from any other with only player actions; no state transitions to a terminal condition; grep for `queue_free` of mechanisms or game-over signals: zero.
12. Pixel audit: no sprite rotation by non-snapped angles; camera offset integer; all 60 Hz.
