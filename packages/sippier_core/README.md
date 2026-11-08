# sippier_core

Dart bindings for Sippier's native SIP core (baresip via `dart:ffi`).
The build hook (`hook/build.dart`) runs `native/scripts/build.sh` for the
target OS and architecture and bundles `libsippier_core` with the app.
