# Decisions

One line per decision: date, decision, reason.

- 2026-10-10: viewport 640x360, window 1280x720 (2x), stretch canvas_items/keep/integer.
- 2026-10-10: Clock phases (game minutes since 18:00 evening): dusk 18:00-20:00, night 20:00-04:00, pre-dawn 04:00-05:30, sunrise 05:30-06:00. Placeholder values, tune in T20.
- 2026-10-10: autoloads Game, Clock, Debug (Sfx later); max 4.
- 2026-10-10: greybox rooms are exactly 640x360 (no camera yet), floors are ColorRects, walls StaticBody2D on physics layer 1; room exits are Area2D on layer 4 (trigger).
- 2026-10-10: player is a top-down 4-direction walker for the greybox; revisit when AGENT_07 camera/stairs are built.
- 2026-10-10: greybox match for relighting sits at the lantern (spec says quarters table); move in T13. A relight needs oil; adding oil alone does not relight.
- 2026-10-10: one oil can = one full reservoir (add_oil(1.0)); barrel holds 4 cans.
