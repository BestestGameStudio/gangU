extends RefCounted
## Presentation only. Read the existing terrace cells; never change gameplay data.
const EDGE = preload("res://assets/sprites/terrain/terrace_grass_cliff_16.png")
const FRONT = preload("res://assets/sprites/terrain/terrace_front_tiles_flat.png")
const CELL = 32
static var _ribbons: Dictionary = {}

static func draw_tiles(canvas: CanvasItem, terraces: RefCounted, view: Rect2) -> void:
	for level in [1,2]:
		# One front ribbon follows the exact dual-grid grass boundary. Art pixels
		# have one owner, so adjacent wall cells cannot overlap or reset depth.
		var key := str(terraces.get_instance_id())+":"+str(level)
		if not _ribbons.has(key):
			_ribbons[key] = []
			for px in range(terraces.bounds.position.x*32,terraces.bounds.end.x*32):
				var bottom := -100000
				for py in range(terraces.bounds.end.y*32,terraces.bounds.position.y*32,-1):
					var q := (Vector2(px+0.5,py+0.5)-Vector2(16,16))/32.0
					var c := Vector2i(q.floor())
					var f := q-Vector2(c)
					var a := 1.0 if terraces.tops.get(c,0)==level else 0.0
					var b := 1.0 if terraces.tops.get(c+Vector2i.RIGHT,0)==level else 0.0
					var d := 1.0 if terraces.tops.get(c+Vector2i.DOWN,0)==level else 0.0
					var e := 1.0 if terraces.tops.get(c+Vector2i.ONE,0)==level else 0.0
					if lerpf(lerpf(a,b,f.x),lerpf(d,e,f.x),f.y)>=0.5:
						bottom=py+1
						break
				if bottom == -100000: continue
				_ribbons[key].append(Vector2(px,bottom))
		for origin in _ribbons[key]:
			if not view.grow(64).has_point(origin):continue
			var depth := 0
			while depth < 64:
				var at: Vector2 = origin+Vector2(0,depth)
				var length: int = mini(64-depth,32-posmod(int(at.y),32))
				if not terraces.stairs.has(terraces.cell_at(at+Vector2.ONE)):
					canvas.draw_texture_rect_region(FRONT,Rect2(at,Vector2(1,length)),Rect2(0,depth,1,length))
				depth += length
	# Dual-grid corners are the existing cell centres, not noisy contours.
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
				_draw_edge(canvas,terraces,Rect2(at,Vector2(32,32)),Vector2((mask%4)*32,(mask/4)*32))

static func _draw_edge(canvas: CanvasItem, terraces: RefCounted, rect: Rect2, source: Vector2) -> void:
	var parts: Array[Rect2] = [rect]
	for c in terraces.stairs:
		var cut := Rect2(Vector2(c)*32,Vector2(32,32))
		if not rect.intersects(cut):continue
		var next: Array[Rect2] = []
		for part in parts:
			var hit := part.intersection(cut)
			if not hit.has_area():
				next.append(part)
				continue
			for box in [Rect2(part.position,Vector2(part.size.x,hit.position.y-part.position.y)),Rect2(Vector2(part.position.x,hit.end.y),Vector2(part.size.x,part.end.y-hit.end.y)),Rect2(Vector2(part.position.x,hit.position.y),Vector2(hit.position.x-part.position.x,hit.size.y)),Rect2(Vector2(hit.end.x,hit.position.y),Vector2(part.end.x-hit.end.x,hit.size.y))]:
				if box.has_area():next.append(box)
		parts=next
	for part in parts:
		canvas.draw_texture_rect_region(EDGE,part,Rect2(source+part.position-rect.position,part.size))
