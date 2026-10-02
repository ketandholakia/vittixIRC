# VIRC — Vittix IRC Chat Client Branding

## Core identity
- Product: VIRC
- Full name: Vittix IRC Chat Client
- Symbol: speech bubble + stylized V + three connection dots
- Primary gradient: `#0758FF → #08A8FF → #15D8E7`
- Navy: `#0C1B3A`
- Light background: `#F8FBFF`
- Secondary text: `#63708A`

## Flutter
```yaml
flutter:
  assets:
    - assets/branding/logo/
    - assets/branding/icons/
    - assets/branding/splash/
    - assets/branding/marketing/
```

Use `virc_icon.svg` as the vector master, `virc_wordmark.svg` on light surfaces, and `virc_wordmark_dark.svg` on dark surfaces.

For launcher generation, the 512px icon is the primary raster master. Android adaptive foreground/background assets are also included.
