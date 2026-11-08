import 'package:flutter/material.dart';

/// The blue of the logo's i-dots (branding/README.md).
const brandColor = Color(0xFF1E7BF2);

/// The app's theme, seeded from the brand colour. The fidelity variant keeps
/// the primary colour close to the brand instead of muting it.
ThemeData sippierTheme(Brightness brightness, {String? fontFamily}) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: brandColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  ),
  fontFamily: fontFamily,
);
