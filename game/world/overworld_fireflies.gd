extends Node2D
## #710: presentation-only vegetation fireflies across the outdoor world.
## No RNG, bodies, particles, terrain writes or gameplay-clock changes.
## One soft light per visible pack, not per insect; allocation is bounded.
const MAX_PACKS := 16
const FLIES_PER_PACK := 6
const MIN_SPACING := 180.0
const GLOW_COLOR := Color(0.77, 1.0, 0.36)
var ground: OverworldGround
var _anchors: Array[Vector2] = []
var _active: Array[int] = []
var _lights: Array[PointLight2D] = []
var _glow: GradientTexture2D
var _time := 0.0
var _strength := 0.0
var _selection_time := 1.0
var _animation_time := 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = 4 # Tiny airborne cores above the vegetation, below labels.
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1,1,1,0.6), Color(1,1,1,0.12), Color(1,1,1,0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.width = 128
	_glow.height = 128
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	# Prefer grass packs, then fill the gaps with trees. Retain every biome
	# and the south extension by deriving positions from the real layout.
	for patch in ground.grass_patches:
		_add_anchor(patch["at"])
	for item in ground.decor:
		if item["kind"] == "tree":
			_add_anchor(item["at"] + Vector2(0, float(item["r"]) + 16))
	for i in MAX_PACKS:
		var light := PointLight2D.new()
		light.texture = _glow
		light.texture_scale = 1.8
		light.color = GLOW_COLOR
		light.shadow_enabled = false
		light.enabled = false
		add_child(light)
		_lights.append(light)

func _add_anchor(at: Vector2) -> void:
	for existing in _anchors:
		if existing.distance_squared_to(at) < MIN_SPACING * MIN_SPACING:
			return
	_anchors.append(at)

func _process(delta: float) -> void:
	_time += delta
	_selection_time += delta
	_animation_time += delta
	if _animation_time < 1.0 / 30.0:
		return
	_animation_time = 0.0
	var clock := DayNightClock.find_clock(get_tree())
	# Smooth dusk/dawn response from the existing tint; full day is zero.
	_strength = 1.0 - smoothstep(0.30, 0.94, clock.tint_color().r) if clock != null else 0.0
	if not is_visible_in_tree() or _strength <= 0.001:
		for light in _lights:
			light.enabled = false
		_active.clear()
		_selection_time = 1.0
		queue_redraw()
		return
	if _selection_time >= 0.2:
		_selection_time = 0.0
		_select_visible_packs()
	for i in _lights.size():
		var light := _lights[i]
		light.enabled = i < _active.size()
		if light.enabled:
			var index := _active[i]
			light.position = _pack_position(index)
			light.energy = _strength * (0.45 + 0.05 * sin(_time * 1.4 + index))
	queue_redraw()

func _select_visible_packs() -> void:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var a := inverse * Vector2.ZERO
	var b := inverse * get_viewport_rect().size
	var view := Rect2(a.min(b), (b-a).abs()).grow(120.0)
	var center := view.get_center()
	var candidates: Array[int] = []
	for i in _anchors.size():
		if view.has_point(_anchors[i]):
			candidates.append(i)
	candidates.sort_custom(func(a_index: int, b_index: int) -> bool:
		return _anchors[a_index].distance_squared_to(center) < _anchors[b_index].distance_squared_to(center))
	_active.assign(candidates.slice(0, MAX_PACKS))

func _pack_position(index: int) -> Vector2:
	var phase := float(index) * 2.39996
	return _anchors[index] + Vector2(sin(_time * 0.23 + phase) * 24.0, cos(_time * 0.19 + phase) * 16.0)

func _fly_position(index: int, fly: int) -> Vector2:
	var phase := float(index) * 2.39996 + float(fly) * 1.618
	return (_pack_position(index) + Vector2(sin(_time * 0.65 + phase) * 35.0,
		cos(_time * 0.49 + phase * 1.7) * 26.0)).round()

func _draw() -> void:
	for index in _active:
		for fly in FLIES_PER_PACK:
			var at := _fly_position(index, fly)
			var pulse := 0.55 + 0.45 * sin(_time * 1.8 + float(index + fly) * 2.4)
			var alpha := _strength * (0.35 + pulse * 0.65)
			draw_texture_rect(_glow, Rect2(at - Vector2(9, 9), Vector2(18, 18)), false,
				Color(GLOW_COLOR, alpha * 0.5))
			var size := Vector2(2, 2) if fly % 3 == 0 else Vector2.ONE
			draw_rect(Rect2(at, size), Color(Color("efffb3"), alpha))
