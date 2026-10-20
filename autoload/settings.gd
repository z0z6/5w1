extends Node
## Ustawienia globalne (zapisywane w user://settings.cfg).
## Każda zmiana przez Settings.save() trafia na dysk od razu.

const PATH := "user://settings.cfg"

var vibration := true
var effects := true          # iskry, płynący prąd, zwarcia
var invert_x := false
var invert_y := false
var sensitivity := 1.0
var show_debug := false      # linia z surowymi wartościami czujnika

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		vibration = bool(cfg.get_value("input", "vibration", true))
		effects = bool(cfg.get_value("input", "effects", true))
		invert_x = bool(cfg.get_value("input", "invert_x", false))
		invert_y = bool(cfg.get_value("input", "invert_y", false))
		sensitivity = float(cfg.get_value("input", "sensitivity", 1.0))
		show_debug = bool(cfg.get_value("input", "show_debug", false))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "vibration", vibration)
	cfg.set_value("input", "effects", effects)
	cfg.set_value("input", "invert_x", invert_x)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("input", "show_debug", show_debug)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: zapis nieudany (%d)" % err)

func vibrate(ms: int) -> void:
	if vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)

func _notification(what: int) -> void:
	# dodatkowe zabezpieczenie: zapis przy wyjściu / zminimalizowaniu aplikacji
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
