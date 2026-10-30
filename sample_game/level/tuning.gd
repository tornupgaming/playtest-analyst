class_name LevelTuning
extends Resource
## Every value the level reads at `_ready()`. The level has no other tunables.

@export var ledge_gap_width: float
## Deaths at the ledge before a bridge appears across the gap.
@export var ledge_bypass_deaths: int
@export var marker_color: Color
@export var marker_emission: float
@export_multiline var switch_prompt_text: String
## Seconds between the player landing in the drop room and the enemy charging.
@export var enemy_aggro_delay: float
@export_enum("left", "right") var fork_arrow_points_to: String
## The corridor is built from this many identical 20 m segments.
@export var corridor_segments: int
