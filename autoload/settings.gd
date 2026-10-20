extends Node
## Ustawienia globalne (zapisywane w user://settings.cfg).
## Każda zmiana przez Settings.save() trafia na dysk od razu.

const PATH := "user://settings.cfg"
## Wersja układu pliku. v2: domyślnie odwrócone osie X i Y (jednorazowo nadpisuje stare zapisy).
const VERSION := 2

var vibration := true
var effects := true          # iskry, płynący prąd, zwarcia
var invert_x := true
var invert_y := true
var sensitivity := 1.0
var show_debug := false      # linia z surowymi wartościami czujnika

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		vibration = bool(cfg.get_value("input", "vibration", true))
		effects = bool(cfg.get_value("input", "effects", true))
		var ver := int(cfg.get_value("meta", "version", 1))
		if ver >= 2:
			invert_x = bool(cfg.get_value("input", "invert_x", true))
			invert_y = bool(cfg.get_value("input", "invert_y", true))
		# ver < 2: zostają nowe domyślne (odwrócone) i od razu zapisujemy migrację
		sensitivity = float(cfg.get_value("input", "sensitivity", 1.0))
		show_debug = bool(cfg.get_value("input", "show_debug", false))
		if ver < VERSION:
			save()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
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
