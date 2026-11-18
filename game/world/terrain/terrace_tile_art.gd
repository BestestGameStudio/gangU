extends RefCounted
## Presentation only. Read the existing terrace cells; never change gameplay data.
const EDGE = preload("res://assets/sprites/terrain/terrace_grass_cliff_16.png")
const FRONT = preload("res://assets/sprites/terrain/terrace_front_tiles_flat.png")
const GRASS = preload("res://assets/sprites/terrain/dualgrid_variants_grass.png")
const CELL = 32

static func draw_tiles(canvas: CanvasItem, terraces: RefCounted, view: Rect2) -> void:
	# Separate face below the south edge, only inside existing wall cells.
	for c in terraces.walls:
		var at := Vector2(c) * CELL
		if not view.grow(64).has_point(at): continue
		var level: int = terraces.bases.get(c, 0)
		var depth := 0
		for n in range(1, 4):
			if terraces.tops.get(c - Vector2i(0,n),0) == level:
				depth = n
				break
		if depth == 0 or terraces.stairs.has(c): continue
		canvas.draw_texture_rect_region(FRONT,Rect2(at,Vector2(32,32)),Rect2(0,32 if depth > 1 else 0,32,32))
	# Dual-grid corners are the existing cell centres, not noisy contours.
	for level in [1,2]:
		for x in range(terraces.bounds.position.x,terraces.bounds.end.x):
			for y in range(terraces.bounds.position.y,terraces.bounds.end.y):
				var c := Vector2i(x,y)
				var at := Vector2(c) * CELL + Vector2(16,16)
				if not view.grow(64).has_point(at): continue
				var mask := 0
				var corners := [c,c+Vector2i.RIGHT,c+Vector2i.ONE,c+Vector2i.DOWN]
				for i in range(4):
					if terraces.tops.get(corners[i],0) == level: mask |= 1 << i
				if mask == 0: continue
				if terraces.stairs.has(c) or terraces.stairs.has(c+Vector2i.RIGHT): continue
				if mask == 15:
					var variant := int(DualGrid._hash01(x,y,182)*7.99)
					canvas.draw_texture_rect_region(GRASS,Rect2(at,Vector2(32,32)),Rect2(variant*64+(posmod(x,2)*32),posmod(y,2)*32,32,32))
					continue
				canvas.draw_texture_rect_region(EDGE,Rect2(at,Vector2(32,32)),Rect2((mask%4)*32,(mask/4)*32,32,32))
