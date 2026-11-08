# Sippier branding

The mark is a rounded square split into two interlocking halves by an
S-shaped gap: two endpoints, one session. The gap is transparent, so the S
takes the colour of whatever is behind the mark: white on light backgrounds,
black on dark ones.

| File | Use |
|---|---|
| `sippier-mark.svg` | The mark. |
| `sippier-wordmark.svg` | "sippier" in monoline lettering. |
| `sippier-lockup.svg` | Mark and wordmark side by side. |
| `sippier-lockup-dark.svg` | The lockup with white letters, for dark backgrounds. |

Colours:

| | |
|---|---|
| Top-left half | `#7FE0FF` to `#25B4F5`, top to bottom |
| Bottom-right half | `#2E8CFF` to `#1556D6`, top to bottom |
| Wordmark i-dots | `#1E7BF2`, also the app's theme seed (`app/lib/ui/theme.dart`) |
| Wordmark letters | `#17181C`, white on dark backgrounds |

## App icons

`generate.py` holds the geometry and writes everything above plus:

- macOS app icon: `app/macos/Runner/AppIcon.icon`, an Icon Composer file
  with a white background in light mode and black in dark mode. macOS shows
  icons with transparent holes on a grey tile, so the S can't be a real hole
  there. Xcode turns the file into the older icon formats for macOS before 26.
- macOS menu bar: `StatusIcon` (registered) and `StatusIconOff` in
  `app/macos/Runner/Assets.xcassets`, template images of the filled and
  outlined mark.
- Android launcher: an adaptive icon in `mipmap-anydpi-v26/ic_launcher.xml`.
  The halves are the foreground. The background is white, or black in dark
  mode (`values-night`), though some launchers ignore the dark variant.
  The monochrome layer is used for themed icons.
- Android notifications: `drawable/ic_stat_sippier.xml`.
- Windows app icon: `app/windows/runner/resources/app_icon.ico`, the mark
  itself. Windows shows app icons without a tile, so the S shows the taskbar
  or desktop behind it.
- Windows tray: `tray_on.ico` (an account registered) and `tray_off.ico`
  (the mark in grey) next to it. The macOS outline doesn't work at 16 px:
  it fills the thin bands.

```bash
python3 branding/generate.py
```

The legacy Android PNGs are rendered by `render.swift`, which needs Xcode;
the Windows icons by `rsvg-convert` (librsvg: `brew install librsvg`, or in
MSYS2 `pacman -S mingw-w64-clang-aarch64-librsvg`). The script skips each
where its tool is missing. Building the macOS app needs Xcode 26 or later
for the `.icon` file.
