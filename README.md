# Infinity Block

Flutter project (runner + more games).

## Branch `work/runner`

Improved endless runner:
- Straight flat rails (no curved track)
- New obstacles: barrier, duck bar, train, double barrier, ramp, cone
- Lane switch, jump, duck, jetpack, ghost

## Local Mac

This GitHub branch does **not** change your Mac until you pull:

```bash
cd ~/Developer/block_infinity
git fetch origin
git checkout work/runner
# or copy only lib/screens/pixel_runner_screen.dart
flutter pub get
flutter run -d macos
```

Your current Terminal app stays as-is if you do nothing.
