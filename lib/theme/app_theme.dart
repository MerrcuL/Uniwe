import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Material 3 shape scale, including the Expressive "increased" steps.
abstract final class AppShapes {
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double largeIncreased = 20;
  static const double extraLarge = 28;

  static const BorderRadius smallRadius = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumRadius =
      BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeRadius = BorderRadius.all(Radius.circular(large));
  static const BorderRadius largeIncreasedRadius =
      BorderRadius.all(Radius.circular(largeIncreased));
}

/// 8dp spacing scale.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Readable line length on tablets / foldables / landscape.
  static const double maxContentWidth = 840;

  /// Bottom padding for scrollable content: the usual spacing plus whatever
  /// overlays the bottom of the screen (the floating navigation bar, the
  /// system gesture area), so the last item can always scroll clear of it.
  static double bottomInset(BuildContext context, {double spacing = lg}) =>
      MediaQuery.paddingOf(context).bottom + spacing;

  /// Horizontal padding that keeps content at [maxContentWidth] and never
  /// closer than [min] to the window edge.
  static double gutter(BuildContext context, {double min = md}) {
    final width = MediaQuery.sizeOf(context).width;
    final extra = (width - maxContentWidth) / 2;
    return extra > min ? extra : min;
  }
}

/// Motion tokens.
///
/// Material 3 Expressive drives component motion with springs. Flutter's
/// implicit animations take curves, so the *spatial* spring (position, size,
/// shape — slightly overshoots) is approximated with an overshooting cubic,
/// while *effects* (colour, opacity — never overshoot) use the standard
/// easing.
abstract final class AppMotion {
  static const Curve spatial = Cubic(0.34, 1.36, 0.64, 1.0);
  static const Duration spatialFast = Duration(milliseconds: 300);
  static const Duration spatialDefault = Duration(milliseconds: 450);

  static const Curve effects = Easing.standard;
  static const Duration effectsFast = Durations.short3;
  static const Duration effectsDefault = Durations.short4;

  static const Curve enter = Easing.emphasizedDecelerate;
  static const Curve exit = Easing.emphasizedAccelerate;
}

/// Colour roles Material does not define but the app needs (dietary tags,
/// "departing now", overlap warnings). Generated as tonal palettes and
/// harmonised with the primary colour so they follow dynamic colour and
/// light/dark mode like every built-in role.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;

  static const Color _successSeed = Color(0xFF2E7D32);
  static const Color _warningSeed = Color(0xFFEF6C00);

  factory SemanticColors.from(ColorScheme scheme) {
    ColorScheme palette(Color seed) => ColorScheme.fromSeed(
          seedColor: seed.harmonizeWith(scheme.primary),
          brightness: scheme.brightness,
        );
    final success = palette(_successSeed);
    final warning = palette(_warningSeed);
    return SemanticColors(
      success: success.primary,
      successContainer: success.primaryContainer,
      onSuccessContainer: success.onPrimaryContainer,
      warning: warning.primary,
      warningContainer: warning.primaryContainer,
      onWarningContainer: warning.onPrimaryContainer,
    );
  }

  static SemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SemanticColors>() ??
        SemanticColors.from(theme.colorScheme);
  }

  @override
  SemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) {
    return SemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    );
  }

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}

abstract final class AppTheme {
  /// HTW green.
  static const Color seedColor = Color(0xFF76B900);

  /// Builds the colour scheme for [brightness].
  ///
  /// [systemScheme] is the scheme built from the system's Material You
  /// palettes, if the user enabled dynamic colour and the platform has them.
  static ColorScheme colorScheme({
    required Brightness brightness,
    ColorScheme? systemScheme,
    bool amoled = false,
  }) {
    ColorScheme scheme;
    if (systemScheme != null) {
      // Already resolved role by role from the system palettes.
      scheme = systemScheme;
    } else {
      // `fidelity` keeps the palette close to the brand green while still
      // generating every role as a correct tonal pair (on-colours included).
      scheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
      // `fidelity` makes the primary container the vivid brand lime itself,
      // which is too loud for the many small accents drawn on it (class
      // times, prices, line numbers). Use the soft green of the secondary
      // container instead, the same as today's day pill.
      scheme = scheme.copyWith(
        primaryContainer: scheme.secondaryContainer,
        onPrimaryContainer: scheme.onSecondaryContainer,
      );
    }

    if (brightness == Brightness.dark) {
      if (amoled) {
        // True-black surfaces for OLED panels: the one place where literal
        // colours are intended.
        scheme = scheme.copyWith(
          surface: Colors.black,
          surfaceDim: Colors.black,
          surfaceContainerLowest: const Color(0xFF050505),
          surfaceContainerLow: const Color(0xFF0A0A0A),
          surfaceContainer: const Color(0xFF121212),
          surfaceContainerHigh: const Color(0xFF1A1A1A),
          surfaceContainerHighest: const Color(0xFF222222),
        );
      } else {
        scheme = scheme.copyWith(
          surface: Color.lerp(scheme.surface, Colors.black, 0.1),
        );
      }
    }
    return scheme;
  }

  /// Emphasized type styles of M3 Expressive: same scale, heavier weights
  /// for the roles that carry hierarchy. Merged over the default typography.
  static const TextTheme _emphasizedText = TextTheme(
    displayLarge: TextStyle(fontWeight: FontWeight.w500),
    displayMedium: TextStyle(fontWeight: FontWeight.w500),
    displaySmall: TextStyle(fontWeight: FontWeight.w500),
    headlineLarge: TextStyle(fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontWeight: FontWeight.w600),
    labelLarge: TextStyle(fontWeight: FontWeight.w600),
  );

  /// Buttons are fully rounded at rest and morph towards a rounded square
  /// while pressed (the framework animates between the two borders).
  static final WidgetStateProperty<OutlinedBorder> _buttonShape =
      WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return const RoundedRectangleBorder(borderRadius: AppShapes.mediumRadius);
    }
    return const StadiumBorder();
  });

  static ThemeData build(ColorScheme scheme, {bool amoled = false}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _emphasizedText,
    );
    // `base.textTheme` carries colours and weights only; sizes are merged in
    // per locale when the theme is read. Component themes that need complete
    // styles (app bar title, navigation labels) take them from here.
    final text =
        ThemeData.localize(base, base.typography.englishLike).textTheme;

    final buttonStyle = ButtonStyle(
      shape: _buttonShape,
      minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );

    return base.copyWith(
      extensions: [SemanticColors.from(scheme)],
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: amoled ? scheme.surface : scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: amoled ? scheme.surface : scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(shape: _buttonShape),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(shape: _buttonShape),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: AppShapes.largeIncreasedRadius,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppShapes.extraLarge),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? const Icon(Icons.check_rounded)
              : null;
        }),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.secondaryContainer,
        circularTrackColor: scheme.secondaryContainer,
        // Opts into the current (rounded, gapped) progress indicators.
        // ignore: deprecated_member_use
        year2023: false,
      ),
    );
  }
}
