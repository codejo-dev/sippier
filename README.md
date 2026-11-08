# <picture><source media="(prefers-color-scheme: dark)" srcset="branding/sippier-lockup-dark.svg"><img src="branding/sippier-lockup.svg" alt="Sippier" width="300"></picture>

A simple, open-source SIP phone for macOS, Windows and Android,
built with Flutter on top of [baresip](https://github.com/baresip/baresip)
via `dart:ffi`. It connects directly to any standards-compliant SIP provider,
with multiple accounts and no server of its own.

Status: milestone 1 (macOS + Android) in progress. Saved accounts,
registration, outgoing and incoming calls, keypad, mute, hold, speaker and
call history.

| Milestone | Platforms | Status |
|---|---|---|
| 1 | macOS, Android | In progress |
| 2 | Windows | Started: core, app and tray run (arm64) |
| Later, maybe | iOS, Linux | Out of scope for now |

The plan for milestone 2 and what parking iOS and Linux covers are in
[docs/sip-audio-research.md](docs/sip-audio-research.md) (section 1a.13).

## Layout

| Path | What |
|---|---|
| `app/` | The Flutter app (macOS, Android, Windows) |
| `packages/sippier_core/` | Dart bindings; its build hook builds and bundles the native library |
| `native/sippier_core/` | C wrapper around baresip with a small FFI API |
| `native/patches/` | Patches on top of the pinned baresip release |
| `native/scripts/build.sh` | Builds OpenSSL, Opus, libg722, libre, baresip and `libsippier_core` for one target |
| `third_party/` | libre, baresip, libg722 as pinned submodules |
| `scripts/` | Install and uninstall scripts for test builds; the Android release key |
| `.github/workflows/release.yml` | Builds and publishes a release for every version tag |
| `spike_app/` | The original macOS spike |
| `docs/sip-audio-research.md` | Research and design decisions |

## Build

Requires Flutter 3.47+, CMake, Ninja and Meson (`brew install cmake ninja
meson`), Xcode for macOS, and the Android SDK with an NDK for Android.

```bash
git submodule update --init
cd app
flutter run -d macos
flutter run -d <android-device-id>
flutter run -d windows
```

Windows needs Visual Studio 2022 with "Desktop development with C++" (for
Flutter; add the ARM64 build tools on Windows on Arm), Developer Mode (for
Flutter's plugin symlinks), and [MSYS2](https://www.msys2.org) for the native
library, with the clang environment for your architecture:

```bash
pacman -S --needed make patch perl cpio mingw-w64-clang-aarch64-{toolchain,cmake,ninja,meson,pkgconf}
```

That's for arm64; for x64 use `mingw-w64-clang-x86_64-` and add its `nasm`.
The build hook finds MSYS2 in `C:\msys64`, or through `PATH` (its folder or
its `usr\bin`). Flutter builds for the machine's own architecture: on Windows
on Arm that's `windows-arm64`.

The first build per target takes a few minutes: the build hook runs
`native/scripts/build.sh`, which downloads OpenSSL and Opus (checksums
verified), on macOS and Windows also WebRTC audio processing and abseil for
echo cancellation, and builds everything into `build/<os>-<arch>/`. Later builds only
recompile what changed. After bumping a submodule, touch
`native/scripts/build.sh` so the hook runs again.

Tests: `flutter test` in `app/` renders every screen at phone and desktop
sizes (`SCREENSHOTS=1` writes PNGs to `app/build/screenshots/`);
`dart test` in `packages/sippier_core/` builds the native library and starts
the core.

## Test builds

Every version tag is built for macOS (12+, Apple silicon), Windows
(x64 and Arm64) and Android (9+, arm64) and published as a
[release](https://github.com/codejo-dev/sippier/releases). The macOS and
Windows apps aren't code-signed yet. Downloaded with a browser, macOS won't
open them and Windows warns about them, so install with these scripts
instead. Running one again updates Sippier.

macOS, in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/install.sh | bash
```

Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/install.ps1 | iex
```

Android: open the release on the phone, download `Sippier-android-arm64.apk`
and open it; Android asks once to allow installing apps from the browser. A
self-built Sippier has to be uninstalled first, as it's signed with another
key.

Until the apps are signed, macOS may ask for microphone access again after
an update.

### Uninstalling

These remove Sippier and everything it keeps: accounts and their passwords,
settings, call history and the log, on macOS also its microphone permission.

macOS, in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/uninstall.sh | bash
```

Sippier is sandboxed and keeps its data in its own container, so macOS may
ask whether Terminal may access data from other apps.

Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/uninstall.ps1 | iex
```

Android: uninstall it like any other app, which removes its data too.

### Making a release

```bash
git tag v0.2.0 && git push origin v0.2.0
```

A suffix such as `v0.2.0-beta.1` makes it a pre-release. Before the first
release, run `scripts/android-release-key.sh` once: it creates the Android
release key and asks for its details, or takes a keystore you already made
(with Android Studio, say), and stores it as repository secrets for the
workflow and in `app/android/key.properties` for local builds. Back up the keystore and its
password; without them no later APK installs as an update.

## Licence

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).
Third-party components in `third_party/` keep their own licences.
