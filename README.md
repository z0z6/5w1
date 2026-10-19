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
