# Infinity Block

Flutter-App (macOS / iOS / Android) mit Block-Puzzle und Minispielen.

## Wichtig

- **GitHub** und **dein Mac** sind getrennt.
- Aenderungen hier aendern deine lokale App **nicht**, bis du selbst ziehst.

```bash
cd ~/Developer/block_infinity
git remote add origin https://github.com/ManuelZellinger/infinity-block.git  # falls noetig
git fetch origin
git pull origin main
flutter pub get
flutter run -d macos
```

## Struktur

- `lib/main.dart` – Einstieg
- `lib/screens/pixel_runner_screen.dart` – Infinity Run (Subway-Stil)
- `pubspec.yaml` – Abhaengigkeiten

## Terminal bleibt deine Kontrolle

Nur du fuehrst `git pull` / `flutter run` lokal aus.
