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
