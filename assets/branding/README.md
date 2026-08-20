# AthleteIQ branding assets

Source-of-truth colors from `docs/wireframe.html.html` / `lib/theme/app_colors.dart`:

| Token | Hex | Use |
|-------|-----|-----|
| Mint | `#2FE6B8` | Icon background, accents |
| Mint dark | `#06231C` | Activity pulse stroke |
| Background | `#0B0D0C` | Splash screen |

## Files

- `app_icon.svg` / `app_icon.png` — master app icon (1024×1024). Mint rounded square + activity pulse (wireframe `#i-activity`).
- `splash_logo.svg` / `splash_logo.png` — centered mark for native splash (transparent outside the mark).

## Regenerate platform assets

After editing the PNG masters:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### What gets generated

**iOS** — `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (20pt–1024pt marketing icon) and splash via `LaunchScreen.storyboard` / `LaunchImage`.

**Android** — `mipmap-*` launcher icons, adaptive icon layers, `drawable*` splash, Android 12+ splash in `values-v31/styles.xml`.

## Store listing

Use `app_icon.png` (1024×1024) for App Store Connect and Google Play high-res icon.
