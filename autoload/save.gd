extends Node
## Rekordy i postępy (user://save.cfg). Czas: mniejszy = lepszy.

const PATH := "user://save.cfg"
var cfg := ConfigFile.new()

func _ready() -> void:
	cfg.load(PATH)

func get_best(game: String, key: String) -> float:
	return float(cfg.get_value(game, key, 0.0))

## Zwraca true, jeśli to nowy rekord.
func submit_time(game: String, key: String, t: float) -> bool:
	var best := get_best(game, key)
	if best == 0.0 or t < best:
		cfg.set_value(game, key, t)
		cfg.save(PATH)
		return true
	return false

func get_int(section: String, key: String, default := 0) -> int:
	return int(cfg.get_value(section, key, default))

func set_int(section: String, key: String, value: int) -> void:
	cfg.set_value(section, key, value)
	cfg.save(PATH)
