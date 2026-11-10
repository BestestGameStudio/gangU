class_name ExitPortal
extends Area2D
## #9: exit portal back to the hub. Using it returns the player to the hub in
## the SAME run: spells, pickups and current HP are retained because the shared
## Player node is repositioned, never recreated (transport is owned by main.gd,
## which connects `entered` the same way it connects gates).
## Normal-gate dungeons mount it unlocked (retreat at any time, objective not
## required). Red-gate dungeons WITH an objective mount it locked; it opens
## when the dungeon objective completes (clear-or-die: death restarts the run
## via RunManager). #55: a red-gate dungeon WITHOUT an objective mounts it
## unlocked - no objective exists to open a locked one, so a locked mount
## would soft-lock the run. (DungeonB gained an ELIMINATION objective in
## #177 / O1, 2026-11-08, and now mounts it locked. The boss-gate arena
## DungeonC (#173 / O6) mounts it locked until the Head boss dies, and the
## Beast's den DungeonD (#326 / O7) mounts it locked until the Beast dies.
## The DEFENSE dungeon DungeonE (#337) is entered through a NORMAL gate and
## mounts it unlocked; Main also unlocks it if the defense fails.)
## #204: opt-in portal look (red_portal_look). The RED dungeon's locked gate
## and exit gate are this same portal in its two states, so both get the
## #195 gate portal look - desaturated gray while locked, red tint once
## unlocked. OFF (the default everywhere else) keeps the flat decor every
## other dungeon and generated-dungeon exit has always had. Visuals only:
## lock/unlock logic, objective wiring, collision shape and label text are
## untouched, and the geometry reuses Gate's portal statics (no gate.gd
## changes).
## #447: the same opt-in for the BEAST den's exit portal (beast_portal_look),
## in purple (Daniel 2026-11-09: "exit portal should look like the other
## portals, purple", "just copy the other portals", locked state: "use the
## existing locked portal"). Locked = the same LOCKED_TINT gray look as the
## red mount; unlocked = EXIT_PURPLE, the tint the flat exit decor has always
## used. Same idle animation, same step-in behavior - visuals only.

signal entered(portal: ExitPortal)

## Locked portals ignore the player. Red dungeons with an objective start
## locked and open on completion; normal dungeons leave this false.
@export var locked: bool = false
## Optional path to a node with an `objective_completed` signal (the #8
## DungeonObjective). Duck-typed by signal name so this file stands alone.
@export var objective_path: NodePath
## #204: opt-in #195 portal look for the RED DungeonB mount only. main.gd
## turns this on for area DungeonB; every other mount keeps the flat look.
@export var red_portal_look: bool = false
## #447: opt-in portal look for the BEAST den DungeonD mount only (purple).
@export var beast_portal_look: bool = false

## #204: locked-state portal tint - the desaturated gray family of the flat
## locked tint (0.35,0.35,0.4), so locked and unlocked read as two states of
## one portal; the LOCKED text and dimmed (gray-tinted) particles carry the
## locked semantics.
const LOCKED_TINT := Color(0.4, 0.4, 0.45)
## #447: unlocked tint for the beast den's exit portal - the purple the flat
## exit decor has always used (0.5, 0.2, 0.8), now in the full portal look.
const EXIT_PURPLE := Color(0.5, 0.2, 0.8)

var _anim_t := 0.0

func _ready() -> void:
	add_to_group("exit_portals")
	body_entered.connect(_on_body_entered)
	if objective_path != NodePath(""):
		var obj := get_node_or_null(objective_path)
		if obj != null and obj.has_signal("objective_completed"):
			obj.objective_completed.connect(_on_objective_completed)
		else:
			push_warning("ExitPortal: objective_path did not resolve to a node with an objective_completed signal.")
	_refresh_visual()

func unlock() -> void:
	if not locked:
		return
	locked = false
	print("exit portal unlocked")
	_refresh_visual()

func _on_objective_completed(_dungeon_id) -> void:
	unlock()

func _on_body_entered(body: Node2D) -> void:
	if locked:
		return
	if body is Player:
		entered.emit(self)

func _refresh_visual() -> void:
	var tint: ColorRect = $ColorRect
	var label: Label = $StateLabel
	if locked:
		tint.color = Color(0.35, 0.35, 0.4)
		label.text = "LOCKED"
	else:
		tint.color = Color(0.5, 0.2, 0.8)
		label.text = "EXIT"
	var look_tint := Color(0, 0, 0, 0)
	if red_portal_look:
		look_tint = Gate.RED_TINT
	elif beast_portal_look:
		look_tint = EXIT_PURPLE
	if look_tint.a > 0.0:
		_apply_portal_look(LOCKED_TINT if locked else look_tint)

## #204: build the #195 portal look in the given state tint. The flat decor
## (ColorRect + ExitArrow) hides but stays in the tree: the ColorRect keeps
## its role as the footprint/tint record, mirroring the gate (#195). The
## StateLabel stays live in both states so LOCKED/EXIT reads identically.
func _apply_portal_look(tint: Color) -> void:
	$ColorRect.visible = false
	$ExitArrow.visible = false
	var rim_color := tint.lightened(0.6)
	Gate._fill_band($Halo, Vector2(Gate.PORTAL_RX, Gate.PORTAL_RY), Color(tint, 0.45),
		Vector2(Gate.PORTAL_RX + Gate.HALO_SPREAD, Gate.PORTAL_RY + Gate.HALO_SPREAD), Color(tint, 0.0))
	Gate._fill_band($Body, Vector2.ZERO, tint.darkened(0.85), Vector2(Gate.PORTAL_RX, Gate.PORTAL_RY), tint)

	# The swirl is drawn as a circle and squashed by its pivot, so spinning
	# it keeps it inside the ellipse.
	var pivot: Node2D = $SwirlPivot
	pivot.scale = Vector2(1.0, Gate.PORTAL_RY / Gate.PORTAL_RX)
	var swirl: Line2D = $SwirlPivot/Swirl
	var r := Gate.PORTAL_RX * 0.8
	var arm := PackedVector2Array()
	for i in range(Gate.SWIRL_STEPS, -1, -1):
		var t := float(i) / Gate.SWIRL_STEPS
		arm.append(Vector2.from_angle(t * TAU * 0.9) * r * t)
	for i in range(1, Gate.SWIRL_STEPS + 1):
		var t := float(i) / Gate.SWIRL_STEPS
		arm.append(Vector2.from_angle(PI + t * TAU * 0.9) * r * t)
	swirl.points = arm
	swirl.default_color = Color(tint.lightened(0.4), 0.55)

	var rim: Line2D = $Rim
	rim.points = Gate.ellipse_points(Gate.PORTAL_RX, Gate.PORTAL_RY, Gate.PORTAL_POINTS)
	rim.default_color = rim_color

	var light: PointLight2D = $Light
	light.color = tint

	var particles: CPUParticles2D = $Particles
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	particles.emission_points = Gate.ellipse_points(Gate.PORTAL_RX, Gate.PORTAL_RY, Gate.PORTAL_POINTS)
	particles.color = rim_color
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	particles.emitting = true

	for n in ["Halo", "Body", "SwirlPivot", "Rim", "Particles", "Light"]:
		get_node(n).visible = true

## #204: portal idle animation, only while the look is on. Same pulse as the
## gate (#195); the locked state's gray tint keeps it visibly dimmed.
func _process(delta: float) -> void:
	if not (red_portal_look or beast_portal_look):
		return
	_anim_t += delta
	var pulse := sin(_anim_t * 2.4)
	($SwirlPivot/Swirl as Line2D).rotation = _anim_t * 1.6
	($Rim as Line2D).width = 2.5 + 0.8 * pulse
	($Light as PointLight2D).energy = 0.9 + 0.15 * pulse
