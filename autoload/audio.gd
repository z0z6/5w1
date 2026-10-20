extends Node
## Warstwa dźwiękowa całej aplikacji: muzyka (pętle) + efekty + dźwięk toczenia.
## Wszystkie dźwięki to pliki WAV z audio/ (wygenerowane przez tools/gen_audio.gd).
## Użycie w dowolnej grze:  Audio.play_music("nazwa")  /  Audio.play_sfx("click")

const SFX_NAMES := [
	"click", "back", "toggle_on", "toggle_off", "type", "boot_ok", "coin", "calib", "hit", "zap",
	"spark", "buzz", "shock", "discharge", "emi", "hole", "win", "level", "pu_good", "pu_bad",
	"jumper", "mine", "scan", "flipper", "bumper", "sling", "target", "rollover", "launch", "drain",
	"multi", "tilt", "tick", "swap", "bad", "match", "special", "blast", "emp", "shuffle", "booster", "rot", "lock", "hard", "line", "quad", "hold",
]
const MUSIC_NAMES := ["intro", "menu", "marble", "pinball", "match3", "sirtet"]
const POOL := 10

var sfx := {}
var music := {}
var pool: Array[AudioStreamPlayer] = []
var pool_idx := 0
var music_player: AudioStreamPlayer
var roll_player: AudioStreamPlayer
var current_music := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # dźwięki interfejsu działają też podczas pauzy
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for n in SFX_NAMES:
		var st := load("res://audio/sfx/%s.wav" % n) as AudioStream
		if st:
			sfx[n] = st
	for n in MUSIC_NAMES:
		var st := load("res://audio/music/%s.wav" % n) as AudioStreamWAV
		if st:
			if n != "intro":
				_make_loop(st)
			music[n] = st
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.finished.connect(_on_music_finished)
	add_child(music_player)
	roll_player = AudioStreamPlayer.new()
	roll_player.bus = "SFX"
	var roll := load("res://audio/sfx/roll.wav") as AudioStreamWAV
	if roll:
		_make_loop(roll)
		roll_player.stream = roll
	add_child(roll_player)
	apply_settings()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")

func _make_loop(st: AudioStreamWAV) -> void:
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * st.mix_rate)

func apply_settings() -> void:
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_mute(mi, not Settings.music)
	AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(Settings.music_vol, 0.0001)))
	AudioServer.set_bus_mute(si, not Settings.sounds)
	AudioServer.set_bus_volume_db(si, linear_to_db(maxf(Settings.sfx_vol, 0.0001)))
	if not Settings.sounds and roll_player and roll_player.playing:
		roll_player.stop()

func play_sfx(sfx_name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not Settings.sounds or not sfx.has(sfx_name):
		return
	var p := pool[pool_idx]
	for q in pool:
		if not q.playing:
			p = q
			break
	pool_idx = (pool_idx + 1) % POOL
	p.stream = sfx[sfx_name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

func play_music(music_name: String, restart := false) -> void:
	if not music.has(music_name):
		return
	if current_music == music_name and music_player.playing and not restart:
		return
	current_music = music_name
	music_player.stream = music[music_name]
	music_player.play()

func stop_music() -> void:
	current_music = ""
	music_player.stop()

## Dźwięk toczenia: głośność i wysokość zależą od prędkości (0 = cisza).
func set_roll(speed: float) -> void:
	if roll_player == null or roll_player.stream == null:
		return
	if not Settings.sounds or speed < 0.2:
		if roll_player.playing:
			roll_player.stop()
		return
	if not roll_player.playing:
		roll_player.play()
	var k := clampf(speed / 6.0, 0.0, 1.0)
	roll_player.volume_db = lerpf(-36.0, -12.0, k)
	roll_player.pitch_scale = lerpf(0.6, 1.5, k)

func _on_music_finished() -> void:
	# po jingle'u startowym płynnie wchodzi muzyka menu
	if current_music == "intro":
		play_music("menu")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		music_player.stream_paused = true
		roll_player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		music_player.stream_paused = false
		roll_player.stream_paused = false
