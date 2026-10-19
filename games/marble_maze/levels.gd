class_name MazeLevels
extends RefCounted
## Poziomy: 1 = ręcznie zrobiony, kolejne = generowane (zawsze przechodnie).
## Znaki: # ściana, . podłoga, S start, G cel (CPU), O otwór montażowy (pułapka)

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

static func _generate(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * n + 13
	var cw := mini(4 + n, 8)
	var ch := mini(6 + n * 2, 12)
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

	var s := Vector2i(1, 1)
	var goal := Vector2i(w - 2, h - 2)

	# Najkrótsza ścieżka
	var prev := _bfs(g, w, h, s, goal, {})
	var path := {s: true}
	var c2 := goal
	while c2 != s:
		path[c2] = true
		c2 = prev[c2]

	# Kandydaci na otwory: na ścieżce lub obok niej, z dala od startu i celu
	var cand: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var p := Vector2i(x, y)
			if g[y][x] != 0:
				continue
			if absi(x - s.x) + absi(y - s.y) <= 4 or absi(x - goal.x) + absi(y - goal.y) <= 2:
				continue
			var near := path.has(p)
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
	var want := mini(2 + n * 2, 14)
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
			elif g[y][x] == 1:
				line += "#"
			else:
				line += "."
		out.append(line)
	return out
