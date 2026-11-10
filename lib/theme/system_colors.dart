// The dynamic_color plugin hands out the system palettes as a `CorePalette`,
// which material_color_utilities has deprecated in favour of the
// `DynamicScheme` this code feeds it into. There is no other source for it.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Builds a [ColorScheme] from the tonal palettes Android derives from the
/// user's wallpaper / colour choice ("Material You").
///
/// Every role is resolved the way Android resolves it itself: the system's
/// five palettes go into a [DynamicScheme] and each role takes its tone from
/// the Material colour spec. That keeps accents, containers *and* surfaces
/// faithful to the system, instead of re-deriving them from a single seed.
///
/// The monochrome system style (grey palettes) is recognised and mapped with
/// the monochrome rules — a black (light) / white (dark) primary rather than
/// a mid-grey one.
ColorScheme colorSchemeFromSystemPalette(
  CorePalette palette,
  Brightness brightness,
) {
  const greyChroma = 5.0;
  final isMonochrome = palette.primary.chroma < greyChroma &&
      palette.secondary.chroma < greyChroma &&
      palette.tertiary.chroma < greyChroma;

  final scheme = DynamicScheme(
    sourceColorHct: Hct.fromInt(palette.primary.get(40)),
    variant: isMonochrome ? Variant.monochrome : Variant.tonalSpot,
    isDark: brightness == Brightness.dark,
    primaryPalette: palette.primary,
    secondaryPalette: palette.secondary,
    tertiaryPalette: palette.tertiary,
    neutralPalette: palette.neutral,
    neutralVariantPalette: palette.neutralVariant,
  );

  Color c(DynamicColor color) => Color(color.getArgb(scheme));

  return ColorScheme(
    brightness: brightness,
    primary: c(MaterialDynamicColors.primary),
    onPrimary: c(MaterialDynamicColors.onPrimary),
    primaryContainer: c(MaterialDynamicColors.primaryContainer),
    onPrimaryContainer: c(MaterialDynamicColors.onPrimaryContainer),
    primaryFixed: c(MaterialDynamicColors.primaryFixed),
    primaryFixedDim: c(MaterialDynamicColors.primaryFixedDim),
    onPrimaryFixed: c(MaterialDynamicColors.onPrimaryFixed),
    onPrimaryFixedVariant: c(MaterialDynamicColors.onPrimaryFixedVariant),
    secondary: c(MaterialDynamicColors.secondary),
    onSecondary: c(MaterialDynamicColors.onSecondary),
    secondaryContainer: c(MaterialDynamicColors.secondaryContainer),
    onSecondaryContainer: c(MaterialDynamicColors.onSecondaryContainer),
    secondaryFixed: c(MaterialDynamicColors.secondaryFixed),
    secondaryFixedDim: c(MaterialDynamicColors.secondaryFixedDim),
    onSecondaryFixed: c(MaterialDynamicColors.onSecondaryFixed),
    onSecondaryFixedVariant: c(MaterialDynamicColors.onSecondaryFixedVariant),
    tertiary: c(MaterialDynamicColors.tertiary),
    onTertiary: c(MaterialDynamicColors.onTertiary),
    tertiaryContainer: c(MaterialDynamicColors.tertiaryContainer),
    onTertiaryContainer: c(MaterialDynamicColors.onTertiaryContainer),
    tertiaryFixed: c(MaterialDynamicColors.tertiaryFixed),
    tertiaryFixedDim: c(MaterialDynamicColors.tertiaryFixedDim),
    onTertiaryFixed: c(MaterialDynamicColors.onTertiaryFixed),
    onTertiaryFixedVariant: c(MaterialDynamicColors.onTertiaryFixedVariant),
    error: c(MaterialDynamicColors.error),
    onError: c(MaterialDynamicColors.onError),
    errorContainer: c(MaterialDynamicColors.errorContainer),
    onErrorContainer: c(MaterialDynamicColors.onErrorContainer),
    surface: c(MaterialDynamicColors.surface),
    onSurface: c(MaterialDynamicColors.onSurface),
    onSurfaceVariant: c(MaterialDynamicColors.onSurfaceVariant),
    surfaceDim: c(MaterialDynamicColors.surfaceDim),
    surfaceBright: c(MaterialDynamicColors.surfaceBright),
    surfaceContainerLowest: c(MaterialDynamicColors.surfaceContainerLowest),
    surfaceContainerLow: c(MaterialDynamicColors.surfaceContainerLow),
    surfaceContainer: c(MaterialDynamicColors.surfaceContainer),
    surfaceContainerHigh: c(MaterialDynamicColors.surfaceContainerHigh),
    surfaceContainerHighest: c(MaterialDynamicColors.surfaceContainerHighest),
    outline: c(MaterialDynamicColors.outline),
    outlineVariant: c(MaterialDynamicColors.outlineVariant),
    shadow: c(MaterialDynamicColors.shadow),
    scrim: c(MaterialDynamicColors.scrim),
    inverseSurface: c(MaterialDynamicColors.inverseSurface),
    onInverseSurface: c(MaterialDynamicColors.inverseOnSurface),
    inversePrimary: c(MaterialDynamicColors.inversePrimary),
    surfaceTint: c(MaterialDynamicColors.primary),
  );
}
