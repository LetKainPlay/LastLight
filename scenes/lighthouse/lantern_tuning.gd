class_name LanternTuning
extends Resource
## Tuning numbers for the flame. Defaults follow the M1 spec (B.3); tune in T20.

@export_range(0.0, 0.1) var oil_drain_per_second: float = 0.0065
## Drain multiplier during the deep-night window (00:00-04:00).
@export_range(1.0, 2.0) var deep_night_drain_factor: float = 1.2
## Seconds for the wick to wear from 0 to 1.
@export_range(30.0, 600.0) var wick_wear_seconds: float = 240.0
## Wear above this dims the flame.
@export_range(0.0, 1.0) var wick_wear_threshold: float = 0.6
## Brightness lost at full wear.
@export_range(0.0, 0.5) var wick_dim_amount: float = 0.15
