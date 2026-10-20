class_name MazeLevels
extends RefCounted
## 30 poziomów: 1 = ręczny, 2-30 = generowane (zawsze przechodnie).
## Znaki: # ściana, . podłoga, S start, G cel (CPU), O otwór (pułapka),
##        Z zwarcie (okresowy łuk elektryczny na ścieżce)

const COUNT := 30
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const LEVEL_1: Array = [
	"###########",
	"#S..#.....#",
	"#.#.#.###.#",
	"#.#...#...#",
	"#.#####.###",
	"#.....#...#",
	"###.#.###.#",
	"#...#.....#",
	"#.#######.#",
	"#.#.....#.#",
	"#.#.###.#.#",
	"#...#O#...#",
	"###.#.#.#.#",
	"#...#...#G#",
	"###########",
]

static func get_level(n: int) -> Array:
	if n == 1:
		return LEVEL_1.duplicate()
	return _generate(n)

static func _in(p: Vector2i, w: int, h: int) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

static func _bfs(g: Array, w: int, h: int, s: Vector2i, goal: Vector2i, blocked: Dictionary) -> Dictionary:
	var prev := {s: s}
	var q: Array[Vector2i] = [s]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c == goal:
			break
		for d in DIRS:
			var n2: Vector2i = c + d
			if not _in(n2, w, h) or g[n2.y][n2.x] == 1 or blocked.has(n2) or prev.has(n2):
				continue
			prev[n2] = c
			q.append(n2)
	return prev

static func _open_neighbors(g: Array, p: Vector2i) -> int:
	var k := 0
	for d in DIRS:
		if g[p.y + d.y][p.x + d.x] == 0:
			k += 1
	return k

static func _generate(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * n + 13
	var cw := clampi(5 + floori(n / 6.0), 5, 8)
	var ch := clampi(7 + floori(n / 3.0), 7, 12)
	var w := cw * 2 + 1
	var h := ch * 2 + 1

	var g: Array = []
	for y in h:
		var row := []
		row.resize(w)
		row.fill(1)
		g.append(row)

	# Labirynt: DFS (recursive backtracker)
	var visited := {Vector2i(0, 0): true}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	g[1][1] = 0
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var nb: Array[Vector2i] = []
		for d in DIRS:
			var n2: Vector2i = c + d
			if _in(n2, cw, ch) and not visited.has(n2):
				nb.append(n2)
		if nb.is_empty():
			stack.pop_back()
		else:
			var nx: Vector2i = nb[rng.randi() % nb.size()]
			visited[nx] = true
			g[c.y * 2 + 1 + (nx.y - c.y)][c.x * 2 + 1 + (nx.x - c.x)] = 0
			g[nx.y * 2 + 1][nx.x * 2 + 1] = 0
			stack.append(nx)

	# Pętle (kilka dziur w ścianach), żeby były alternatywne drogi
	for i in int(w * h * 0.03):
		var x := rng.randi_range(1, w - 2)
		var y := rng.randi_range(1, h - 2)
		if (x + y) % 2 == 1:
			g[y][x] = 0

	# Otwarte "pokoje" 3x3 (od poziomu 5) - tu holes są naprawdę groźne
	var room_cells := {}
	if n >= 5:
		var rooms := clampi(floori((n - 3) / 6.0), 1, 3)
		for i in rooms:
			var rx := rng.randi_range(2, w - 5)
			var ry := rng.randi_range(3, h - 6)
			for yy in range(ry, ry + 3):
				for xx in range(rx, rx + 3):
					g[yy][xx] = 0
					room_cells[Vector2i(xx, yy)] = true

	var s := Vector2i(1, 1)
	var goal := Vector2i(w - 2, h - 2)

	# Najkrótsza ścieżka
	var prev := _bfs(g, w, h, s, goal, {})
	var path := {s: true}
	var path_list: Array[Vector2i] = []
	var c2 := goal
	while c2 != s:
		path[c2] = true
		path_list.append(c2)
		c2 = prev[c2]

	# Zwarcia (Z): na ścieżce, w korytarzach (2 sąsiedzi), z dala od startu/celu
	var shorts := {}
	var want_z := clampi(floori((n - 1) / 3.0), 0, 7) if n >= 3 else 0
	var z_cand: Array[Vector2i] = []
	for p in path_list:
		if absi(p.x - s.x) + absi(p.y - s.y) <= 4 or absi(p.x - goal.x) + absi(p.y - goal.y) <= 3:
			continue
		if _open_neighbors(g, p) == 2 and not room_cells.has(p):
			z_cand.append(p)
	for i in range(z_cand.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := z_cand[i]
		z_cand[i] = z_cand[j]
		z_cand[j] = tmp
	for p in z_cand:
		if shorts.size() >= want_z:
			break
		var far := true
		for q in shorts:
			if absi(p.x - q.x) + absi(p.y - q.y) < 5:
				far = false
		if far:
			shorts[p] = true

	# Kandydaci na otwory: pokoje + ścieżka i jej sąsiedztwo, z dala od startu i celu
	var cand: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var p := Vector2i(x, y)
			if g[y][x] != 0 or shorts.has(p):
				continue
			if absi(x - s.x) + absi(y - s.y) <= 4 or absi(x - goal.x) + absi(y - goal.y) <= 2:
				continue
			var near := path.has(p) or room_cells.has(p)
			for d in DIRS:
				if path.has(p + d):
					near = true
			if near:
				cand.append(p)
	for i in range(cand.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cand[i]
		cand[i] = cand[j]
		cand[j] = tmp

	var holes := {}
	var want := clampi(1 + floori(n / 2.0), 2, 14)
	for p in cand:
		if holes.size() >= want:
			break
		holes[p] = true
		if not _bfs(g, w, h, s, goal, holes).has(goal):
			holes.erase(p)   # nie wolno odciąć mety

	var out: Array = []
	for y in h:
		var line := ""
		for x in w:
			var p := Vector2i(x, y)
			if p == s:
				line += "S"
			elif p == goal:
				line += "G"
			elif holes.has(p):
				line += "O"
			elif shorts.has(p):
				line += "Z"
			elif g[y][x] == 1:
				line += "#"
			else:
				line += "."
		out.append(line)
	return out
