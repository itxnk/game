# Nasrr Racer

A top-down endless racing game built with Flutter. Weave through traffic on a
four-lane road, grab near-miss bonus points and survive as long as you can.

## Controls

| Action | Touch | Keyboard |
| --- | --- | --- |
| Steer | Left / right arrow buttons | `A` / `D` or ← / → |
| Gas | Green button | `W` or ↑ |
| Brake | Red button | `S` or ↓ |
| Nitro | ⚡ button | `Space` (needs gas) |

Passing a car closely gives 5 bonus points instead of 1. Nitro drains while in
use and recharges when released.

## Run it

```bash
flutter pub get
flutter run            # pick a device, or add -d chrome for web
```

Build the web version:

```bash
flutter build web
```

The game rotates with the device in both portrait and landscape.

## Project layout

- `lib/main.dart` – the whole game: physics, traffic, HUD and rendering
- `web/`, `android/` – platform runners
- `public/`, `build/web/` – pre-built web output (rebuild with
  `flutter build web` after changing the code)
- `old/` – an earlier version of the web page
