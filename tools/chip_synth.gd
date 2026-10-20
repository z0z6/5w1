class_name ChipSynth
extends RefCounted
## Syntezator "chiptune" (fale prostokątne, trójkątne, piłokształtne, szum) - narzędzie developerskie.
## Używany przez tools/gen_audio.gd do wyrenderowania plików WAV w audio/. Nie jest potrzebny w grze.

const RATE := 22050
const SQUARE := 0
const TRI := 1
const SAW := 2
const SINE := 3

static var _rng := RandomNumberGenerator.new()

static func reseed(seed_value: int) -> void:
	_rng.seed = seed_value

static func midi_freq(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

static func pc_of(letter: String) -> int:
	match letter:
		"C": return 0
		"D": return 2
		"E": return 4
		"F": return 5
		"G": return 7
		"A": return 9
		_: return 11

## "C#5", "Bb3", "A4" -> numer MIDI
static func note_midi(name: String) -> int:
	var pc := pc_of(name[0])
	var i := 1
	if name.length() > 1 and name[1] == "#":
		pc += 1
		i = 2
	elif name.length() > 1 and name[1] == "b":
		pc -= 1
		i = 2
	return 12 * (int(name.substr(i)) + 1) + pc

## Akord: "Am", "F", "B7", "G#m" -> nuty MIDI (root w oktawie base_oct)
static func chord_notes(name: String, base_oct: int) -> Array[int]:
	var pc := pc_of(name[0])
	var idx := 1
	if name.length() > 1 and name[1] == "#":
		pc += 1
		idx = 2
	elif name.length() > 1 and name[1] == "b":
		pc -= 1
		idx = 2
	var q := name.substr(idx)
	var iv: Array[int] = [0, 4, 7]
	if q == "m":
		iv = [0, 3, 7]
	elif q == "7":
		iv = [0, 4, 7, 10]
	elif q == "m7":
		iv = [0, 3, 7, 10]
	var base := 12 * (base_oct + 1) + pc
	var out: Array[int] = []
	for x in iv:
		out.append(base + x)
	return out

static func new_buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b

## Pojedynczy dźwięk. f0 -> f1: liniowy glissando. decay: wykładnicze wygaszanie (1/s).
## vib: głębokość wibrata (ułamek częstotliwości), crush: poziomy kwantyzacji trójkąta (4-bit ~ 7.5).
static func tone(buf: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, wave: int, vol: float,
		duty := 0.5, att := 0.004, rel := 0.03, decay := 0.0, vib := 0.0, vib_rate := 6.0, crush := 0.0) -> void:
	var n0 := int(t0 * RATE)
	var n := int(dur * RATE)
	if n <= 0:
		return
	var end := mini(n0 + n, buf.size())
	var phase := 0.0
	var inv := 1.0 / RATE
	var att_n := maxf(att * RATE, 1.0)
	var rel_n := maxf(rel * RATE, 1.0)
	for i in range(maxi(n0, 0), end):
		var k := i - n0
		var t := k * inv
		var f := f0 + (f1 - f0) * (float(k) / n)
		if vib > 0.0:
			f *= 1.0 + vib * sin(TAU * vib_rate * t)
		phase += f * inv
		phase -= floor(phase)
		var s := 0.0
		if wave == SQUARE:
			s = 1.0 if phase < duty else -1.0
		elif wave == TRI:
			s = 4.0 * absf(phase - 0.5) - 1.0
			if crush > 0.0:
				s = roundf(s * crush) / crush
		elif wave == SAW:
			s = 2.0 * phase - 1.0
		else:
			s = sin(TAU * phase)
		var env := 1.0
		if k < att_n:
			env = k / att_n
		var left := n - k
		if left < rel_n:
			env *= left / rel_n
		if decay > 0.0:
			env *= exp(-decay * t)
		buf[i] += s * env * vol

## Szum. smooth = 1 -> biały; mniejsze -> przepuszczony przez filtr dolnoprzepustowy; hp = górnoprzepustowy.
static func noise(buf: PackedFloat32Array, t0: float, dur: float, vol: float, decay := 20.0, smooth := 1.0,
		hp := false, att := 0.002, rel := 0.01) -> void:
	var n0 := int(t0 * RATE)
	var n := int(dur * RATE)
	if n <= 0:
		return
	var end := mini(n0 + n, buf.size())
	var lp := 0.0
	var inv := 1.0 / RATE
	var att_n := maxf(att * RATE, 1.0)
	var rel_n := maxf(rel * RATE, 1.0)
	for i in range(maxi(n0, 0), end):
		var k := i - n0
		var r := _rng.randf() * 2.0 - 1.0
		lp += (r - lp) * smooth
		var s := (r - lp) if hp else lp
		var env := 1.0
		if k < att_n:
			env = k / att_n
		var left := n - k
		if left < rel_n:
			env *= left / rel_n
		env *= exp(-decay * k * inv)
		buf[i] += s * env * vol

static func kick(buf: PackedFloat32Array, t: float, vol := 0.6) -> void:
	tone(buf, t, 0.16, 150.0, 42.0, SINE, vol, 0.5, 0.001, 0.03, 6.0)
	noise(buf, t, 0.02, vol * 0.25, 60.0, 0.5)

static func snare(buf: PackedFloat32Array, t: float, vol := 0.35) -> void:
	noise(buf, t, 0.16, vol, 20.0, 0.7)
	tone(buf, t, 0.09, 210.0, 150.0, TRI, vol * 0.5, 0.5, 0.001, 0.03, 12.0)

static func hat(buf: PackedFloat32Array, t: float, vol := 0.12, open := false) -> void:
	noise(buf, t, 0.22 if open else 0.045, vol, 14.0 if open else 70.0, 0.35, true)

## Parsuje takt (16 tokenów): nuta = start, "_" = przedłużenie, "-" = pauza.
## Zwraca tablicę [krok, nazwa_nuty, długość_w_krokach].
static func parse_bar(bar: String) -> Array:
	var out: Array = []
	var tokens := bar.split(" ", false)
	var i := 0
	while i < tokens.size():
		var tk := tokens[i]
		if tk == "-" or tk == "_":
			i += 1
			continue
		var len_steps := 1
		var j := i + 1
		while j < tokens.size() and tokens[j] == "_":
			len_steps += 1
			j += 1
		out.append([i, tk, len_steps])
		i = j
	return out

## Utwór w pętli: spec = {bpm, chords[], lead[], arp[], bass[], kick, hat, lead_duty, ...}
static func render_song(spec: Dictionary) -> PackedFloat32Array:
	var step := 60.0 / float(spec.bpm) / 4.0
	var bars: int = spec.chords.size()
	var buf := new_buf(bars * 16 * step)
	var lead_duty: float = spec.get("lead_duty", 0.25)
	var arp_pat: Array = spec.get("arp", [0, 1, 2, 1])
	var bass_pat: Array = spec.get("bass", [1, 0, 0, 2, 0, 0, 1, 0, 1, 0, 0, 2, 0, 0, 1, 0])
	var kick_pat: String = spec.get("kick", "k.......k.......")
	var snare_pat: String = spec.get("snare", "....s.......s...")
	var hat_pat: String = spec.get("hat", "h.h.h.h.h.h.h.hH")
	var arp_vol: float = spec.get("arp_vol", 0.10)
	var lead_vol: float = spec.get("lead_vol", 0.20)
	var bass_vol: float = spec.get("bass_vol", 0.30)
	var drums: bool = spec.get("drums", true)
	var echo: bool = spec.get("echo", true)

	for bar in bars:
		var tb := bar * 16 * step
		var ch := chord_notes(spec.chords[bar], 4)
		var ext: Array[int] = []
		for m in ch:
			ext.append(m)
		for m in ch:
			ext.append(m + 12)
		# melodia
		for ev in parse_bar(spec.lead[bar]):
			var f := midi_freq(note_midi(ev[1]))
			var ts: float = tb + ev[0] * step
			var ln: float = ev[2] * step
			var vib := 0.006 if ev[2] >= 4 else 0.0
			tone(buf, ts, ln * 0.94, f, f, SQUARE, lead_vol, lead_duty, 0.004, 0.05, 0.0, vib, 5.5)
			if echo:
				tone(buf, ts + 3.0 * step, ln * 0.9, f, f, SQUARE, lead_vol * 0.32, 0.5, 0.004, 0.05, 0.0, vib, 5.5)
		# arpeggio
		for s in 16:
			var idx: int = arp_pat[s % arp_pat.size()]
			var m: int = ext[idx % ext.size()]
			tone(buf, tb + s * step, step * 0.72, midi_freq(m), midi_freq(m), SQUARE, arp_vol, 0.125, 0.002, 0.02)
		# bas (trójkąt, oktawa 3)
		var bch := chord_notes(spec.chords[bar], 3)
		for s in 16:
			var b: int = bass_pat[s]
			if b == 0:
				continue
			var m: int = bch[0]
			if b == 2:
				m += 12
			elif b == 3:
				m = bch[2]
			tone(buf, tb + s * step, step * 1.8, midi_freq(m), midi_freq(m), TRI, bass_vol, 0.5, 0.002, 0.04, 2.0, 0.0, 6.0, 7.5)
		# perkusja
		if drums:
			for s in 16:
				var t := tb + s * step
				if kick_pat[s] == "k":
					kick(buf, t)
				if snare_pat[s] == "s":
					snare(buf, t)
				if hat_pat[s] == "h":
					hat(buf, t)
				elif hat_pat[s] == "H":
					hat(buf, t, 0.12, true)
	return buf

static func normalize(buf: PackedFloat32Array, peak: float) -> void:
	var mx := 0.0
	for v in buf:
		mx = maxf(mx, absf(v))
	if mx <= 0.0:
		return
	var g := peak / mx
	for i in buf.size():
		buf[i] *= g

## Płynne wejście/wyjście (bez klików).
static func fade_edges(buf: PackedFloat32Array, ms := 4.0) -> void:
	var n := int(ms * 0.001 * RATE)
	for i in mini(n, buf.size()):
		var g := float(i) / n
		buf[i] *= g
		buf[buf.size() - 1 - i] *= g

## Zapętlenie bez przeskoku: ogon wtapiany w początek.
static func make_loopable(buf: PackedFloat32Array, fade_s := 0.06) -> PackedFloat32Array:
	var m := int(fade_s * RATE)
	var n := buf.size() - m
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = buf[i]
	for i in m:
		var a := float(i) / m
		out[i] = buf[i] * a + buf[n + i] * (1.0 - a)
	return out

static func save_wav(path: String, buf: PackedFloat32Array) -> void:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(RATE)
	f.store_32(RATE * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	f.store_buffer(data)
	f.close()
