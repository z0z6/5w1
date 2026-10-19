extends Node
## Ustawienia globalne (zapisywane w user://settings.cfg).

const PATH := "user://settings.cfg"

var vibration := true
var invert_x := false
var invert_y := false
var sensitivity := 1.0

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		vibration = cfg.get_value("input", "vibration", true)
		invert_x = cfg.get_value("input", "invert_x", false)
		invert_y = cfg.get_value("input", "invert_y", false)
		sensitivity = cfg.get_value("input", "sensitivity", 1.0)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "vibration", vibration)
	cfg.set_value("input", "invert_x", invert_x)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.save(PATH)

func vibrate(ms: int) -> void:
	if vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
