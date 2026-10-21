extends SceneTree
## Generator audio (narzędzie developerskie): renderuje wszystkie melodie i efekty do audio/*.wav.
## Uruchomienie:  godot --headless --path . --script tools/gen_audio.gd
## Dodanie muzyki do nowej gry = nowy wpis w _songs() + ponowne uruchomienie.

const S = preload("res://tools/chip_synth.gd")

func _init() -> void:
	_gen_music()
	_gen_sfx()
	print("OK: audio wygenerowane")
	quit()

# ------------------------------------------------------------------- MUZYKA
func _songs() -> Dictionary:
	return {
		# Menu / hub: pogodny, A-moll, 136 BPM
		"menu": {
			"bpm": 136, "lead_duty": 0.25, "lead_vol": 0.20, "arp": [0, 2, 1, 2], "arp_vol": 0.08,
			"kick": "k.....k.k.......", "snare": "....s.......s...", "hat": "h.h.h.h.h.h.h.hH",
			"chords": ["Am", "F", "C", "G", "Am", "F", "G", "E", "C", "G", "Am", "Em", "F", "C", "G", "E"],
			"lead": [
				"E5 _ _ A5 _ _ G5 _ E5 _ _ D5 _ C5 _ _",
				"C5 _ _ F5 _ _ E5 _ C5 _ _ A4 _ C5 _ _",
				"E5 _ _ G5 _ _ E5 _ C5 _ _ D5 _ E5 _ _",
				"D5 _ _ G5 _ _ F5 _ D5 _ _ B4 _ D5 _ _",
				"A5 _ _ _ G5 _ E5 _ A5 _ _ _ B5 _ C6 _",
				"A5 _ _ _ G5 _ F5 _ E5 _ C5 _ A4 _ C5 _",
				"B5 _ _ B5 _ _ A5 _ G5 _ _ F5 _ D5 _ _",
				"E5 _ G#5 _ B5 _ G#5 _ E5 _ - - - - - -",
				"G5 _ _ E5 _ G5 _ C6 _ _ _ B5 _ G5 _ _",
				"B5 _ _ G5 _ B5 _ D6 _ _ _ C6 _ B5 _ _",
				"C6 _ _ A5 _ C6 _ E6 _ _ _ D6 _ C6 _ _",
				"B5 _ _ G5 _ B5 _ E6 _ _ _ D6 _ B5 _ _",
				"A5 _ F5 _ A5 _ C6 _ A5 _ F5 _ A5 _ _ _",
				"G5 _ E5 _ G5 _ C6 _ G5 _ E5 _ G5 _ _ _",
				"D6 _ _ B5 _ _ G5 _ B5 _ D6 _ _ _ _ _",
				"E6 _ _ _ B5 _ _ _ G#5 _ _ _ E5 _ - -",
			],
		},
		# Marble Maze: napięty, E-moll, 124 BPM, "obwodowy"
		"marble": {
			"bpm": 124, "lead_duty": 0.125, "lead_vol": 0.19, "arp": [0, 1, 2, 4, 2, 1, 0, 1], "arp_vol": 0.11,
			"bass": [1, 0, 1, 0, 2, 0, 1, 0, 1, 0, 1, 0, 2, 0, 3, 0],
			"kick": "k.....k.k.....k.", "snare": "....s.......s..s", "hat": "h.h.h.h.h.h.h.h.",
			"chords": ["Em", "C", "G", "D", "Em", "C", "D", "B7", "Am", "Em", "C", "D", "Am", "Em", "B7", "Em"],
			"lead": [
				"B5 _ _ _ A5 _ G5 _ E5 _ _ _ G5 _ A5 _",
				"B5 _ _ _ C6 _ B5 _ G5 _ _ _ E5 _ G5 _",
				"D6 _ _ _ B5 _ G5 _ B5 _ _ _ D6 _ B5 _",
				"A5 _ _ _ F#5 _ A5 _ D6 _ _ _ C#6 _ A5 _",
				"E6 _ _ D6 _ B5 _ G5 _ B5 _ D6 _ _ - -",
				"E6 _ _ C6 _ G5 _ E5 _ G5 _ C6 _ _ - -",
				"F#6 _ _ D6 _ A5 _ F#5 _ A5 _ D6 _ _ - -",
				"D#6 _ _ B5 _ F#5 _ D#5 _ F#5 _ B5 _ _ - -",
				"A5 _ C6 _ E6 _ C6 _ A5 _ C6 _ E6 _ _ _",
				"G5 _ B5 _ E6 _ B5 _ G5 _ B5 _ E6 _ _ _",
				"G5 _ C6 _ E6 _ C6 _ G5 _ C6 _ G6 _ _ _",
				"A5 _ D6 _ F#6 _ D6 _ A5 _ D6 _ F#6 _ _ _",
				"E6 _ _ _ D6 _ C6 _ B5 _ _ _ A5 _ C6 _",
				"B5 _ _ _ A5 _ G5 _ E5 _ _ _ G5 _ B5 _",
				"D#6 _ _ _ F#6 _ D#6 _ B5 _ _ _ A5 _ F#5 _",
				"E6 _ _ _ _ _ _ _ B5 _ _ _ G5 _ - -",
			],
		},
		# Pinball: szybki, D-moll, 150 BPM
		"pinball": {
			"bpm": 150, "lead_duty": 0.25, "lead_vol": 0.20, "arp": [0, 1, 2, 1], "arp_vol": 0.09,
			"bass": [1, 0, 1, 0, 2, 0, 1, 0, 1, 0, 1, 0, 2, 0, 3, 0],
			"kick": "k...k...k...k...", "snare": "....s.......s...", "hat": "h.h.h.h.h.h.h.hH",
			"chords": ["Dm", "Bb", "F", "C", "Dm", "Bb", "C", "A7", "Dm", "Gm", "Bb", "C", "Dm", "Gm", "A7", "Dm"],
			"lead": [
				"A5 _ _ D6 _ _ F6 _ E6 _ D6 _ A5 _ _ _",
				"D6 _ _ F6 _ _ E6 _ D6 _ Bb5 _ D6 _ _ _",
				"C6 _ _ F6 _ _ A6 _ G6 _ F6 _ C6 _ _ _",
				"E6 _ _ G6 _ _ E6 _ C6 _ D6 _ E6 _ _ _",
				"F6 _ A6 _ F6 _ D6 _ A5 _ D6 _ F6 _ _ _",
				"D6 _ F6 _ Bb6 _ F6 _ D6 _ F6 _ D6 _ _ _",
				"G6 _ _ E6 _ _ C6 _ E6 _ G6 _ C7 _ _ _",
				"C#6 _ E6 _ A6 _ G6 _ E6 _ C#6 _ A5 _ - -",
				"D6 _ _ _ A5 _ D6 _ F6 _ _ _ A6 _ F6 _",
				"G5 _ _ _ Bb5 _ D6 _ G6 _ _ _ F6 _ D6 _",
				"Bb5 _ _ _ D6 _ F6 _ Bb6 _ _ _ A6 _ F6 _",
				"C6 _ _ _ E6 _ G6 _ C7 _ _ _ B6 _ G6 _",
				"A6 _ F6 _ D6 _ F6 _ A6 _ D7 _ C7 _ A6 _",
				"G6 _ D6 _ Bb5 _ D6 _ G6 _ Bb6 _ A6 _ G6 _",
				"E6 _ _ _ C#6 _ A5 _ E6 _ G6 _ A6 _ C#7 _",
				"D7 _ _ _ _ _ _ _ A6 _ _ _ F6 _ - -",
			],
		},
		# Chip Match: lekki, C-dur, 124 BPM
		"match3": {
			"bpm": 124, "lead_duty": 0.25, "lead_vol": 0.19, "arp": [0, 1, 2, 1], "arp_vol": 0.09,
			"kick": "k.......k.......", "snare": "........s.......", "hat": "h...h...h...h...",
			"chords": ["C", "Am", "F", "G", "C", "Am", "Dm", "G", "F", "G", "Em", "Am", "F", "G", "C", "G"],
			"lead": [
				"E5 _ G5 _ C6 _ B5 _ G5 _ E5 _ G5 _ _ _",
				"A5 _ C6 _ E6 _ D6 _ C6 _ A5 _ C6 _ _ _",
				"A5 _ C6 _ F6 _ E6 _ C6 _ A5 _ F5 _ _ _",
				"G5 _ B5 _ D6 _ C6 _ B5 _ G5 _ D5 _ _ _",
				"E6 _ _ D6 _ C6 _ G5 _ C6 _ E6 _ _ - -",
				"E6 _ _ C6 _ A5 _ C6 _ E6 _ A6 _ _ - -",
				"F6 _ _ D6 _ A5 _ D6 _ F6 _ A6 _ _ - -",
				"G6 _ _ D6 _ B5 _ D6 _ G6 _ B6 _ _ - -",
				"C6 _ A5 _ C6 _ F6 _ C6 _ A5 _ C6 _ _ _",
				"B5 _ G5 _ B5 _ D6 _ B5 _ G5 _ B5 _ _ _",
				"G5 _ B5 _ E6 _ B5 _ G5 _ B5 _ E6 _ _ _",
				"A5 _ C6 _ E6 _ C6 _ A5 _ C6 _ E6 _ _ _",
				"F6 _ _ E6 _ D6 _ C6 _ A5 _ C6 _ F6 _ _",
				"G6 _ _ F6 _ D6 _ B5 _ D6 _ G6 _ _ - -",
				"E6 _ _ _ G6 _ _ _ C7 _ _ _ G6 _ E6 _",
				"D6 _ _ _ B5 _ _ _ G5 _ _ _ D5 _ - -",
			],
		},
		# Sirtet: dynamiczny, C-moll, 140 BPM (oryginalna melodia)
		"sirtet": {
			"bpm": 140, "lead_duty": 0.125, "lead_vol": 0.19, "arp": [0, 1, 2, 1], "arp_vol": 0.09,
			"kick": "k...k...k...k...", "snare": "....s.......s...", "hat": "h.h.h.h.h.h.h.hH",
			"chords": ["Cm", "Ab", "Eb", "Bb", "Cm", "Ab", "Bb", "G7", "Fm", "Cm", "Ab", "Bb", "Cm", "Ab", "Bb", "G7"],
			"lead": [
				"G5 _ C6 _ Eb6 _ D6 _ C6 _ G5 _ Eb5 _ G5 _",
				"Eb6 _ C6 _ Ab5 _ C6 _ Eb6 _ F6 _ Eb6 _ C6 _",
				"G5 _ Bb5 _ Eb6 _ Bb5 _ G5 _ Bb5 _ Eb6 _ G6 _",
				"F6 _ D6 _ Bb5 _ D6 _ F6 _ D6 _ Bb5 _ F5 _",
				"C6 _ _ G5 _ C6 _ Eb6 _ G6 _ _ F6 _ Eb6 _",
				"Eb6 _ _ C6 _ Eb6 _ Ab6 _ G6 _ _ Eb6 _ C6 _",
				"D6 _ _ Bb5 _ D6 _ F6 _ Bb6 _ _ A6 _ F6 _",
				"D6 _ B5 _ G5 _ B5 _ D6 _ F6 _ G6 _ _ _",
				"F6 _ Ab6 _ C7 _ Ab6 _ F6 _ Ab6 _ C7 _ _ _",
				"G6 _ Eb6 _ C6 _ Eb6 _ G6 _ C7 _ Bb6 _ G6 _",
				"Ab6 _ _ Eb6 _ C6 _ Eb6 _ Ab6 _ _ G6 _ Eb6 _",
				"F6 _ _ D6 _ Bb5 _ D6 _ F6 _ _ D6 _ Bb5 _",
				"C6 _ Eb6 _ G6 _ Eb6 _ C6 _ G5 _ C6 _ Eb6 _",
				"Ab5 _ C6 _ Eb6 _ C6 _ Ab5 _ Eb6 _ Ab6 _ Eb6 _",
				"Bb5 _ D6 _ F6 _ D6 _ Bb5 _ F6 _ Bb6 _ F6 _",
				"G6 _ _ _ F6 _ D6 _ B5 _ _ _ G5 _ - -",
			],
		},
		# Dionakra: żwawy marsz w A-dur, 132 BPM
		"dionakra": {
			"bpm": 132, "lead_duty": 0.25, "lead_vol": 0.19, "arp": [0, 1, 2, 1], "arp_vol": 0.09,
			"kick": "k...k...k...k...", "snare": "....s.......s...", "hat": "h.h.h.h.h.h.h.h.",
			"chords": ["A", "F#m", "D", "E", "A", "F#m", "D", "E", "D", "E", "C#m", "F#m", "D", "E", "A", "E"],
			"lead": [
				"E6 _ A5 _ C#6 _ E6 _ A6 _ _ _ E6 _ C#6 _",
				"F#6 _ A5 _ C#6 _ F#6 _ A6 _ _ _ F#6 _ C#6 _",
				"D6 _ F#5 _ A5 _ D6 _ F#6 _ _ _ D6 _ A5 _",
				"E6 _ G#5 _ B5 _ E6 _ G#6 _ _ _ E6 _ B5 _",
				"A6 _ _ E6 _ C#6 _ E6 _ A6 _ _ B6 _ A6 _",
				"A6 _ _ F#6 _ C#6 _ F#6 _ A6 _ _ G#6 _ F#6 _",
				"F#6 _ _ D6 _ A5 _ D6 _ F#6 _ _ E6 _ D6 _",
				"E6 _ _ B5 _ G#5 _ B5 _ E6 _ _ _ _ - -",
				"D6 _ F#6 _ A6 _ F#6 _ D6 _ A5 _ D6 _ F#6 _",
				"E6 _ G#6 _ B6 _ G#6 _ E6 _ B5 _ E6 _ G#6 _",
				"C#6 _ E6 _ G#6 _ E6 _ C#6 _ G#5 _ C#6 _ E6 _",
				"F#6 _ A6 _ C#7 _ A6 _ F#6 _ C#6 _ F#6 _ A6 _",
				"D6 _ _ A5 _ D6 _ F#6 _ A6 _ _ F#6 _ D6 _",
				"E6 _ _ B5 _ E6 _ G#6 _ B6 _ _ G#6 _ E6 _",
				"A6 _ E6 _ C#6 _ E6 _ A6 _ C#7 _ E7 _ _ _",
				"B6 _ _ _ G#6 _ _ _ E6 _ _ _ B5 _ - -",
			],
		},
	}

func _gen_music() -> void:
	var songs := _songs()
	for name in songs:
		var spec: Dictionary = songs[name]
		for i in spec.lead.size():
			var cnt := (spec.lead[i] as String).split(" ", false).size()
			if cnt != 16:
				push_error("%s takt %d ma %d kroków" % [name, i + 1, cnt])
		S.reseed(1234)
		var buf := S.render_song(spec)
		S.normalize(buf, 0.70)
		S.fade_edges(buf, 3.0)
		S.save_wav("res://audio/music/%s.wav" % name, buf)
		print("  muzyka %s: %.1f s" % [name, buf.size() / float(S.RATE)])
	_gen_intro()

func _gen_intro() -> void:
	S.reseed(77)
	var b := S.new_buf(4.6)
	# włączenie: niski sygnał + narastający sweep
	S.tone(b, 0.0, 0.16, 110.0, 110.0, S.SQUARE, 0.40, 0.5, 0.002, 0.03)
	S.tone(b, 0.18, 0.34, 220.0, 880.0, S.SQUARE, 0.30, 0.25, 0.01, 0.06)
	# fanfara w A-dur: szybkie arpeggio i długa nuta
	var run := [64, 69, 73, 76]
	for i in run.size():
		var f := S.midi_freq(run[i])
		S.tone(b, 0.95 + i * 0.10, 0.12, f, f, S.SQUARE, 0.30, 0.25, 0.002, 0.03)
	var t := 1.35
	S.tone(b, t, 1.15, S.midi_freq(81), S.midi_freq(81), S.SQUARE, 0.28, 0.25, 0.004, 0.25, 0.8, 0.008, 5.5)
	S.tone(b, t, 1.15, S.midi_freq(57), S.midi_freq(57), S.TRI, 0.42, 0.5, 0.004, 0.2, 0.0, 0.0, 6.0, 7.5)
	S.tone(b, t, 1.15, S.midi_freq(76), S.midi_freq(76), S.SQUARE, 0.10, 0.5, 0.004, 0.25, 0.8)
	# iskrzące gwiazdki
	var spark := [85, 88, 93, 88, 85, 93]
	for i in spark.size():
		var f := S.midi_freq(spark[i])
		S.tone(b, 2.0 + i * 0.085, 0.14, f, f, S.SQUARE, 0.14, 0.125, 0.002, 0.05, 6.0)
	# końcowy akord
	for m in [81, 85, 88]:
		S.tone(b, 2.75, 1.4, S.midi_freq(m), S.midi_freq(m), S.SQUARE, 0.17, 0.25, 0.004, 0.5, 2.5)
	S.tone(b, 2.75, 1.4, S.midi_freq(45), S.midi_freq(45), S.TRI, 0.45, 0.5, 0.004, 0.4, 1.5, 0.0, 6.0, 7.5)
	S.kick(b, 2.75, 0.5)
	S.hat(b, 2.75, 0.14, true)
	S.normalize(b, 0.72)
	S.fade_edges(b, 3.0)
	S.save_wav("res://audio/music/intro.wav", b)
	print("  muzyka intro: %.1f s" % (b.size() / float(S.RATE)))

# ------------------------------------------------------------------- EFEKTY
func _save(name: String, b: PackedFloat32Array, peak := 0.85) -> void:
	S.normalize(b, peak)
	S.fade_edges(b, 2.0)
	S.save_wav("res://audio/sfx/%s.wav" % name, b)

func _gen_sfx() -> void:
	S.reseed(99)
	var b: PackedFloat32Array

	# --- interfejs
	b = S.new_buf(0.07)
	S.tone(b, 0, 0.06, 900, 1500, S.SQUARE, 0.6, 0.5, 0.001, 0.02)
	_save("click", b, 0.55)
	b = S.new_buf(0.11)
	S.tone(b, 0, 0.1, 700, 350, S.SQUARE, 0.6, 0.5, 0.001, 0.03)
	_save("back", b, 0.55)
	b = S.new_buf(0.15)
	S.tone(b, 0, 0.05, 660, 660, S.SQUARE, 0.6, 0.5, 0.001, 0.01)
	S.tone(b, 0.055, 0.09, 990, 990, S.SQUARE, 0.6, 0.5, 0.001, 0.03)
	_save("toggle_on", b, 0.55)
	b = S.new_buf(0.15)
	S.tone(b, 0, 0.05, 990, 990, S.SQUARE, 0.6, 0.5, 0.001, 0.01)
	S.tone(b, 0.055, 0.09, 660, 660, S.SQUARE, 0.6, 0.5, 0.001, 0.03)
	_save("toggle_off", b, 0.55)
	b = S.new_buf(0.03)
	S.tone(b, 0, 0.022, 1700, 1700, S.SQUARE, 0.4, 0.5, 0.0005, 0.005)
	_save("type", b, 0.35)
	b = S.new_buf(0.3)
	S.tone(b, 0, 0.09, 880, 880, S.SQUARE, 0.5, 0.5, 0.001, 0.02)
	S.tone(b, 0.1, 0.18, 1320, 1320, S.SQUARE, 0.5, 0.5, 0.001, 0.05)
	_save("boot_ok", b, 0.55)
	b = S.new_buf(0.65)
	S.tone(b, 0, 0.08, 988, 988, S.SQUARE, 0.6, 0.5, 0.001, 0.01)
	S.tone(b, 0.08, 0.55, 1319, 1319, S.SQUARE, 0.6, 0.5, 0.001, 0.25, 4.0)
	_save("coin", b, 0.7)
	b = S.new_buf(0.3)
	S.tone(b, 0, 0.07, 880, 880, S.SQUARE, 0.5, 0.5, 0.001, 0.02)
	S.tone(b, 0.08, 0.2, 1320, 1320, S.SQUARE, 0.5, 0.5, 0.001, 0.1, 5.0)
	_save("calib", b, 0.55)

	# --- kulka
	b = S.new_buf(0.1)
	S.noise(b, 0, 0.05, 0.7, 50.0, 0.6)
	S.tone(b, 0, 0.08, 260, 100, S.TRI, 0.6, 0.5, 0.001, 0.03, 0.0, 0.0, 6.0, 7.5)
	_save("hit", b, 0.8)
	b = S.new_buf(1.3)
	S.noise(b, 0, 1.3, 1.0, 0.0, 0.06)
	for i in b.size():
		b[i] *= 0.75 + 0.25 * sin(TAU * float(i) / S.RATE * 7.0)
	b = S.make_loopable(b)
	S.normalize(b, 0.5)
	S.save_wav("res://audio/sfx/roll.wav", b)

	# --- elektryka
	b = S.new_buf(0.3)
	S.noise(b, 0, 0.14, 0.6, 25.0, 0.9, true)
	S.tone(b, 0, 0.12, 2600, 500, S.SQUARE, 0.35, 0.25, 0.001, 0.03)
	for i in 3:
		S.noise(b, 0.06 + i * 0.05, 0.02, 0.5, 80.0, 1.0, true)
	_save("zap", b, 0.8)
	b = S.new_buf(0.15)
	S.noise(b, 0, 0.09, 0.5, 30.0, 0.5, true)
	S.tone(b, 0, 0.05, 3200, 2200, S.SINE, 0.2, 0.5, 0.001, 0.02)
	_save("spark", b, 0.6)
	b = S.new_buf(0.4)
	S.tone(b, 0, 0.35, 110, 110, S.SQUARE, 0.4, 0.25, 0.01, 0.08, 0.0, 0.02, 30.0)
	S.noise(b, 0, 0.35, 0.3, 4.0, 0.3)
	_save("buzz", b, 0.55)
	b = S.new_buf(0.5)
	S.tone(b, 0, 0.4, 1800, 90, S.SQUARE, 0.6, 0.125, 0.001, 0.05)
	S.noise(b, 0, 0.4, 0.6, 6.0, 0.8)
	S.tone(b, 0, 0.4, 60, 60, S.SAW, 0.4, 0.5, 0.001, 0.05, 4.0)
	_save("shock", b, 0.9)
	b = S.new_buf(0.5)
	for i in 9:
		S.noise(b, i * 0.04 + S._rng.randf() * 0.02, 0.015, 0.7, 120.0, 1.0, true)
	S.tone(b, 0, 0.3, 400, 2400, S.TRI, 0.25, 0.5, 0.01, 0.1)
	_save("discharge", b, 0.8)
	b = S.new_buf(0.5)
	for i in 6:
		S.noise(b, i * 0.07, 0.05, 0.5, 8.0, 0.5 + S._rng.randf() * 0.5)
	_save("emi", b, 0.6)

	# --- dziury, wygrana, start
	b = S.new_buf(0.95)
	S.tone(b, 0, 0.7, 900, 70, S.TRI, 0.6, 0.5, 0.002, 0.05, 1.5, 0.03, 18.0, 7.5)
	S.tone(b, 0.62, 0.22, 90, 40, S.SINE, 0.7, 0.5, 0.002, 0.05, 4.0)
	S.noise(b, 0.62, 0.12, 0.3, 25.0, 0.2)
	_save("hole", b, 0.85)
	b = S.new_buf(1.6)
	var arp := ["C5", "E5", "G5", "C6"]
	for i in arp.size():
		var f := S.midi_freq(S.note_midi(arp[i]))
		S.tone(b, i * 0.09, 0.1, f, f, S.SQUARE, 0.4, 0.25, 0.002, 0.02)
	for n in ["C6", "E6", "G6"]:
		var f := S.midi_freq(S.note_midi(n))
		S.tone(b, 0.38, 0.8, f, f, S.SQUARE, 0.22, 0.25, 0.004, 0.3, 1.5, 0.006, 5.5)
	S.tone(b, 0.38, 0.8, S.midi_freq(48), S.midi_freq(48), S.TRI, 0.4, 0.5, 0.004, 0.2, 0.0, 0.0, 6.0, 7.5)
	for i in 3:
		var f := S.midi_freq(S.note_midi(["E6", "G6", "C7"][i]))
		S.tone(b, 1.0 + i * 0.07, 0.15, f, f, S.SQUARE, 0.15, 0.125, 0.002, 0.05, 6.0)
	_save("win", b, 0.85)
	b = S.new_buf(0.3)
	for i in 3:
		var f := S.midi_freq(S.note_midi(["G4", "C5", "E5"][i]))
		S.tone(b, i * 0.075, 0.08, f, f, S.SQUARE, 0.5, 0.5, 0.002, 0.02)
	_save("level", b, 0.6)

	# --- power-upy
	b = S.new_buf(0.5)
	for i in 4:
		var f := S.midi_freq(S.note_midi(["C6", "E6", "G6", "C7"][i]))
		S.tone(b, i * 0.055, 0.07, f, f, S.SQUARE, 0.45, 0.25, 0.001, 0.015)
	S.tone(b, 0.22, 0.25, S.midi_freq(96), S.midi_freq(96), S.SQUARE, 0.3, 0.25, 0.001, 0.1, 8.0)
	_save("pu_good", b, 0.75)
	b = S.new_buf(0.45)
	S.tone(b, 0, 0.35, 440, 110, S.SAW, 0.45, 0.5, 0.002, 0.05, 3.0)
	S.tone(b, 0, 0.3, 330, 80, S.SQUARE, 0.3, 0.125, 0.002, 0.05)
	S.noise(b, 0, 0.3, 0.25, 6.0, 0.4)
	_save("pu_bad", b, 0.75)
	b = S.new_buf(0.4)
	S.tone(b, 0, 0.12, 220, 900, S.SQUARE, 0.5, 0.25, 0.002, 0.02)
	S.tone(b, 0.12, 0.2, 900, 260, S.SQUARE, 0.5, 0.25, 0.002, 0.05, 0.0, 0.02, 14.0)
	_save("jumper", b, 0.75)
	b = S.new_buf(0.95)
	S.noise(b, 0, 0.8, 0.9, 4.0, 0.25)
	S.tone(b, 0, 0.6, 130, 35, S.TRI, 0.8, 0.5, 0.002, 0.1, 3.0, 0.0, 6.0, 7.5)
	S.noise(b, 0, 0.03, 0.8, 60.0, 1.0, true)
	_save("mine", b, 0.95)
	b = S.new_buf(0.9)
	S.tone(b, 0, 0.5, 1400, 1400, S.SINE, 0.6, 0.5, 0.002, 0.2, 7.0)
	S.tone(b, 0.28, 0.5, 1400, 1400, S.SINE, 0.25, 0.5, 0.002, 0.2, 9.0)
	_save("scan", b, 0.7)

	# --- Pinball
	b = S.new_buf(0.12)
	S.noise(b, 0, 0.04, 0.6, 60.0, 0.5)
	S.tone(b, 0, 0.09, 150, 70, S.SQUARE, 0.55, 0.5, 0.001, 0.03)
	_save("flipper", b, 0.8)
	b = S.new_buf(0.22)
	S.tone(b, 0, 0.1, 500, 1300, S.SQUARE, 0.5, 0.25, 0.001, 0.03)
	S.tone(b, 0.05, 0.14, 1300, 700, S.SQUARE, 0.3, 0.5, 0.001, 0.05)
	S.noise(b, 0, 0.03, 0.4, 70.0, 1.0, true)
	_save("bumper", b, 0.85)
	b = S.new_buf(0.15)
	S.tone(b, 0, 0.08, 900, 300, S.SQUARE, 0.5, 0.125, 0.001, 0.03)
	S.noise(b, 0, 0.04, 0.5, 60.0, 0.8, true)
	_save("sling", b, 0.8)
	b = S.new_buf(0.3)
	S.tone(b, 0, 0.25, 1568, 1568, S.SINE, 0.6, 0.5, 0.001, 0.1, 9.0)
	S.tone(b, 0, 0.2, 2093, 2093, S.SINE, 0.25, 0.5, 0.001, 0.1, 11.0)
	_save("target", b, 0.75)
	b = S.new_buf(0.2)
	S.tone(b, 0, 0.06, 880, 880, S.SQUARE, 0.45, 0.25, 0.001, 0.02)
	S.tone(b, 0.07, 0.1, 1175, 1175, S.SQUARE, 0.45, 0.25, 0.001, 0.04)
	_save("rollover", b, 0.65)
	b = S.new_buf(0.8)
	S.noise(b, 0, 0.7, 0.5, 3.0, 0.15)
	S.tone(b, 0, 0.7, 120, 900, S.SAW, 0.35, 0.5, 0.01, 0.15)
	_save("launch", b, 0.85)
	b = S.new_buf(1.0)
	S.tone(b, 0, 0.8, 440, 60, S.SAW, 0.5, 0.5, 0.002, 0.15, 1.2, 0.02, 7.0)
	S.tone(b, 0, 0.8, 330, 50, S.SQUARE, 0.3, 0.125, 0.002, 0.15, 1.2)
	_save("drain", b, 0.85)
	b = S.new_buf(1.2)
	var mn := ["D5", "F5", "A5", "D6", "F6", "A6", "D7"]
	for i in mn.size():
		var f := S.midi_freq(S.note_midi(mn[i]))
		S.tone(b, i * 0.07, 0.12, f, f, S.SQUARE, 0.4, 0.25, 0.002, 0.03)
	for n in ["D6", "F6", "A6"]:
		var f := S.midi_freq(S.note_midi(n))
		S.tone(b, 0.5, 0.6, f, f, S.SQUARE, 0.22, 0.25, 0.004, 0.25, 1.5, 0.006, 5.5)
	_save("multi", b, 0.85)
	b = S.new_buf(0.9)
	S.tone(b, 0, 0.8, 90, 90, S.SQUARE, 0.5, 0.25, 0.005, 0.1, 0.0, 0.05, 25.0)
	S.noise(b, 0, 0.8, 0.35, 2.0, 0.3)
	S.tone(b, 0, 0.8, 60, 55, S.SAW, 0.4, 0.5, 0.005, 0.1)
	_save("tilt", b, 0.9)
	b = S.new_buf(0.06)
	S.tone(b, 0, 0.04, 1400, 1400, S.SQUARE, 0.4, 0.5, 0.0005, 0.01)
	_save("tick", b, 0.5)

	# --- Chip Match
	b = S.new_buf(0.08)
	S.tone(b, 0, 0.06, 500, 800, S.SQUARE, 0.5, 0.5, 0.001, 0.02)
	_save("swap", b, 0.55)
	b = S.new_buf(0.2)
	S.tone(b, 0, 0.14, 300, 140, S.SQUARE, 0.5, 0.125, 0.001, 0.04)
	S.noise(b, 0, 0.05, 0.3, 50.0, 0.7)
	_save("bad", b, 0.65)
	b = S.new_buf(0.4)
	S.tone(b, 0, 0.35, 1047, 1047, S.SINE, 0.6, 0.5, 0.001, 0.15, 7.0)
	S.tone(b, 0, 0.12, 2093, 2093, S.SQUARE, 0.16, 0.25, 0.001, 0.05, 12.0)
	_save("match", b, 0.7)
	b = S.new_buf(0.5)
	for i in 5:
		var f := S.midi_freq(S.note_midi(["G5", "C6", "E6", "G6", "C7"][i]))
		S.tone(b, i * 0.05, 0.09, f, f, S.SQUARE, 0.4, 0.25, 0.001, 0.02)
	S.tone(b, 0.25, 0.25, 2093, 2093, S.SINE, 0.3, 0.5, 0.001, 0.1, 8.0)
	_save("special", b, 0.8)
	b = S.new_buf(0.6)
	S.noise(b, 0, 0.45, 0.6, 5.0, 0.9, true)
	S.tone(b, 0, 0.4, 2200, 180, S.SAW, 0.5, 0.5, 0.001, 0.1)
	for i in 4:
		S.noise(b, 0.04 + i * 0.07, 0.02, 0.5, 90.0, 1.0, true)
	_save("blast", b, 0.9)
	b = S.new_buf(1.0)
	S.tone(b, 0, 0.8, 160, 40, S.TRI, 0.8, 0.5, 0.002, 0.2, 2.0, 0.0, 6.0, 7.5)
	S.noise(b, 0, 0.7, 0.5, 3.5, 0.25)
	S.tone(b, 0, 0.4, 300, 3000, S.SAW, 0.3, 0.5, 0.002, 0.1)
	_save("emp", b, 0.95)
	b = S.new_buf(0.6)
	S.noise(b, 0, 0.5, 0.5, 2.0, 0.15)
	S.tone(b, 0, 0.5, 300, 900, S.SINE, 0.3, 0.5, 0.01, 0.1, 0.0, 0.05, 14.0)
	_save("shuffle", b, 0.7)
	b = S.new_buf(0.45)
	S.tone(b, 0, 0.15, 880, 1760, S.SQUARE, 0.45, 0.25, 0.001, 0.02)
	S.tone(b, 0.15, 0.28, 1760, 1760, S.SQUARE, 0.45, 0.5, 0.001, 0.12, 4.0)
	_save("booster", b, 0.7)

	# --- Sirtet
	b = S.new_buf(0.07)
	S.tone(b, 0, 0.05, 700, 1100, S.SQUARE, 0.45, 0.5, 0.001, 0.02)
	_save("rot", b, 0.55)
	b = S.new_buf(0.15)
	S.noise(b, 0, 0.05, 0.5, 50.0, 0.6)
	S.tone(b, 0, 0.1, 160, 80, S.TRI, 0.6, 0.5, 0.001, 0.04, 0.0, 0.0, 6.0, 7.5)
	_save("lock", b, 0.7)
	b = S.new_buf(0.25)
	S.noise(b, 0, 0.1, 0.6, 30.0, 0.9)
	S.tone(b, 0, 0.18, 240, 55, S.SINE, 0.7, 0.5, 0.001, 0.06, 4.0)
	_save("hard", b, 0.85)
	b = S.new_buf(0.4)
	for i in 4:
		var f := S.midi_freq(S.note_midi(["G5", "C6", "E6", "G6"][i]))
		S.tone(b, i * 0.055, 0.1, f, f, S.SQUARE, 0.4, 0.25, 0.001, 0.03)
	S.tone(b, 0.2, 0.18, 2093, 2093, S.SINE, 0.25, 0.5, 0.001, 0.08, 9.0)
	_save("line", b, 0.75)
	b = S.new_buf(1.0)
	var qn := ["C5", "G5", "C6", "E6", "G6", "C7"]
	for i in qn.size():
		var f := S.midi_freq(S.note_midi(qn[i]))
		S.tone(b, i * 0.06, 0.12, f, f, S.SQUARE, 0.4, 0.25, 0.002, 0.03)
	for n in ["C6", "E6", "G6"]:
		var f := S.midi_freq(S.note_midi(n))
		S.tone(b, 0.4, 0.55, f, f, S.SQUARE, 0.22, 0.25, 0.004, 0.25, 1.8, 0.006, 5.5)
	S.noise(b, 0, 0.35, 0.4, 6.0, 0.9, true)
	_save("quad", b, 0.9)
	b = S.new_buf(0.15)
	S.tone(b, 0, 0.05, 500, 400, S.SQUARE, 0.45, 0.5, 0.001, 0.01)
	S.tone(b, 0.06, 0.07, 400, 650, S.SQUARE, 0.45, 0.5, 0.001, 0.02)
	_save("hold", b, 0.55)

	# --- Dionakra
	b = S.new_buf(0.12)
	S.tone(b, 0, 0.07, 800, 1300, S.SQUARE, 0.5, 0.25, 0.001, 0.02)
	S.noise(b, 0, 0.03, 0.4, 70.0, 1.0, true)
	_save("brick", b, 0.7)
	b = S.new_buf(0.2)
	S.tone(b, 0, 0.14, 420, 380, S.SQUARE, 0.5, 0.125, 0.001, 0.05, 5.0)
	S.tone(b, 0, 0.1, 1250, 1250, S.SINE, 0.3, 0.5, 0.001, 0.05, 8.0)
	_save("clang", b, 0.7)
	b = S.new_buf(0.12)
	S.tone(b, 0, 0.09, 190, 120, S.TRI, 0.7, 0.5, 0.001, 0.03, 0.0, 0.0, 6.0, 7.5)
	S.noise(b, 0, 0.02, 0.4, 80.0, 0.7)
	_save("paddle", b, 0.8)
	b = S.new_buf(0.07)
	S.tone(b, 0, 0.05, 520, 520, S.SQUARE, 0.4, 0.5, 0.001, 0.02)
	_save("wall", b, 0.5)
	b = S.new_buf(0.2)
	S.tone(b, 0, 0.16, 2100, 2100, S.SINE, 0.5, 0.5, 0.001, 0.08, 9.0)
	_save("tink", b, 0.6)
	b = S.new_buf(0.6)
	S.noise(b, 0, 0.5, 0.8, 5.0, 0.25)
	S.tone(b, 0, 0.4, 150, 40, S.TRI, 0.8, 0.5, 0.001, 0.1, 3.0, 0.0, 6.0, 7.5)
	_save("boom", b, 0.9)
	b = S.new_buf(0.2)
	S.tone(b, 0, 0.14, 1900, 500, S.SQUARE, 0.45, 0.25, 0.001, 0.04)
	S.noise(b, 0, 0.04, 0.3, 60.0, 1.0, true)
	_save("laser", b, 0.65)
