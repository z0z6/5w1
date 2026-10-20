# Retro Arcade (5 w 1) – Godot 4.4

Hub + gry. Aktualnie: **Marble Maze** (3D, Jolt, sterowanie przechyłem telefonu).
Kolejne gry dodajesz jako sceny pod ścieżkami z `main_menu/main_menu.gd` – przycisk włączy się sam.

## Build
Push na `main` → GitHub Actions (`.github/workflows/android.yml`) → artefakt `retro-arcade-debug-apk`
(podpisany kluczem debug, wystarczy do instalacji na własnym telefonie).

## Lokalnie
Otwórz w Godot 4.4.x. Na PC steruj strzałkami.

## Strojenie czujnika (na telefonie)
Przyciski w grze: **Kalibruj** (ustaw aktualne trzymanie telefonu jako „poziom") oraz
**Osie ++ / +- / -+ / --** (odwracanie osi X/Y, jeśli kulka jedzie w złą stronę).
Stała siła: `TILT_FORCE` w `marble_maze.gd`; czułość: `Settings.sensitivity`.

## Opcje (menu główne i w grze)
Wibracje, efekty (iskry / płynący prąd / zwarcia), odwrócenie osi X i Y, czułość, podgląd danych czujnika.
Wszystko zapisuje się od razu w `user://settings.cfg` i wraca po restarcie aplikacji.

## Marble Maze
30 poziomów (przycisk „Poziomy"; kolejne odblokowują się po ukończeniu poprzedniego), 12 rodzajów elementów
elektronicznych jako ściany, otwory montażowe oraz **zwarcia** - okresowe łuki elektryczne na ścieżce
(porażenie = odrzut kulki + 2 s kary).

## Efekty i power-upy (wersja 1.2)
- **Magistrale**: poza labiryntem wiązki równoległych ścieżek (szyny zasilania, magistrale danych, cienkie wiązki),
  podłączone do ścian przez sloty; płyną po nich kolorowe impulsy o różnym natężeniu (`bus.gdshader`).
- **Kulka**: fluorescencyjna powłoka z migoczącymi ładunkami (`ball.gdshader`). Ładunek rośnie z prędkością,
  po przekroczeniu progu przeskakuje na pobliski element ściany (najchętniej metalowy) + iskry i wibracja.
- **Power-upy** (od poziomu 2; zielona obwódka = pomaga, czerwona = przeszkadza):
  ZWORKA, IZOLATOR, RADIATOR, SKANER, BATERIA / PRZEPIĘCIE, ODWROTNA POLARYZACJA, ZAKŁÓCENIA, MINA.
- Wyłączenie **Efektów** w opcjach gasi impulsy na magistralach, iskry i wyładowania (power-upy działają nadal).

## Zmiany w wersji 1.3
- Osie X i Y są domyślnie **odwrócone** (przełączniki w opcjach zostają). Stary zapis ustawień jest jednorazowo
  zmigrowany do nowych domyślnych (wersja pliku `meta/version = 2`); późniejsze wybory użytkownika są respektowane.
- Efekty (iskry, błyski, łuki, zwarcia, komunikaty, power-upy) są dłuższe i wyraźniejsze.
- Prąd na magistralach osłabiony; kulka mocniej naelektryzowana (gęstsze ładunki, częstsze wyładowania, korona iskier).

## Wersja 1.4 - ścieżki, magistrale, dźwięk, strona startowa, ikona
- **Ścieżki PCB** są teraz spójne: długie trasy z 45° narożnikami, w wiązkach równoległych, zakończone padami
  (zamiast urwanych odcinków). Generator: `_make_trace_texture()` w `marble_maze.gd`.
- **Magistrale** to delikatne złote przewody z falującymi prądami (`bus.gdshader`).
- **Dźwięk**: autoload `Audio` (muzyka + efekty). Pliki w `audio/` są **generowane**:
  `godot --headless --path . --script tools/gen_audio.gd` (syntezator chiptune w `tools/chip_synth.gd`).
  Nowa melodia = nowy wpis w `_songs()`; nowy efekt = nowy blok w `_gen_sfx()` + nazwa w `autoload/audio.gd`.
  Opcje: muzyka / efekty WŁ/WYŁ + osobne głośności.
- **Strona startowa** (`intro/`): sekwencja BIOS, tytuł z jingle'em, „DOTKNIJ, ABY ROZPOCZĄĆ" -> menu.
  Styl: pikselowa czcionka Press Start 2P (SIL OFL, `fonts/OFL-PressStart2P.txt`), tło synthwave, nakładka CRT.
- **Ikona**: `python3 tools/make_icons.py` (Pillow + numpy) -> `icons/`. Ikona adaptacyjna + splash.

## Wersja 1.5
- Magistrale mają nieprzezroczysty podkład (`mats.ribbon`), który zakrywa ścieżki i pady pod spodem.
- Sieć ścieżek PCB: gęsta poza labiryntem, rzadka i mocno wygaszona w środku (`maze_half` w `pcb.gdshader`).
- Kulka jaskrawo czerwona (`body_color` w `ball.gdshader`, światło towarzyszące w `_spawn_ball()`).
