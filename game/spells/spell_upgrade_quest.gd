class_name SpellUpgradeQuest
extends Resource
## Data-defined qualification for one upgrade row. No quest means legacy casts.
enum Kind { CASTS, REDIRECTED_HITS, VOLLEY }
@export var kind: Kind = Kind.CASTS
@export_multiline var objective: String = ""
@export_range(1, 10000) var goal: int = 1
@export_range(2, 100) var projectiles: int = 3
@export_range(0.01, 2.0) var window_seconds: float = 0.15
