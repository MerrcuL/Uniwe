// CorePalette is the (deprecated) type the dynamic_color plugin returns.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:uniwe/theme/system_colors.dart';

/// A system palette as Android reports it: 5 palettes x 13 tones.
CorePalette systemPalette({
  required double hue,
  required double accentChroma,
  double neutralChroma = 6,
}) {
  final palettes = [
    TonalPalette.of(hue, accentChroma),
    TonalPalette.of(hue, accentChroma / 2),
    TonalPalette.of(hue + 60, accentChroma / 1.5),
    TonalPalette.of(hue, neutralChroma),
    TonalPalette.of(hue, neutralChroma + 2),
  ];
  return CorePalette.fromList([
    for (final palette in palettes)
      for (final tone in TonalPalette.commonTones) palette.get(tone),
  ]);
}

double luminance(Color c) => c.computeLuminance();

void main() {
  test('monochrome system style gives a black / white primary, not grey', () {
    final palette = systemPalette(hue: 0, accentChroma: 0, neutralChroma: 0);

    final light = colorSchemeFromSystemPalette(palette, Brightness.light);
    expect(light.primary, const Color(0xFF000000));
    expect(luminance(light.onPrimary), greaterThan(0.7));

    final dark = colorSchemeFromSystemPalette(palette, Brightness.dark);
    // In dark mode the spec puts the primary just below pure white.
    expect(luminance(dark.primary), greaterThan(0.7));
    expect(luminance(dark.onPrimary), lessThan(0.05));
    final darkPrimary = Hct.fromInt(dark.primary.toARGB32());
    expect(darkPrimary.chroma, lessThan(5)); // neutral, no tint
  });

  test('a coloured system palette keeps its hue and fills every surface role',
      () {
    final palette = systemPalette(hue: 140, accentChroma: 40); // green
    final light = colorSchemeFromSystemPalette(palette, Brightness.light);

    final primary = Hct.fromInt(light.primary.toARGB32());
    expect(primary.hue, closeTo(140, 8));
    expect(primary.tone, closeTo(40, 2));

    // Tonal surfaces are distinct steps, not all equal to `surface`.
    final surfaces = {
      light.surface,
      light.surfaceContainerLow,
      light.surfaceContainer,
      light.surfaceContainerHigh,
      light.surfaceContainerHighest,
    };
    expect(surfaces, hasLength(5));

    // On-colours contrast with what they sit on.
    expect(luminance(light.onPrimary), greaterThan(luminance(light.primary)));
    expect(luminance(light.onSurface), lessThan(luminance(light.surface)));

    final dark = colorSchemeFromSystemPalette(palette, Brightness.dark);
    expect(luminance(dark.surface), lessThan(0.05));
    expect(luminance(dark.primary), greaterThan(luminance(dark.onPrimary)));
  });
}
