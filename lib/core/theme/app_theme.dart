import 'package:closer_app/core/models/models.dart';
import 'package:flutter/material.dart';

/// Brand tokens (plan section 9.2).
abstract final class Brand {
  static const blue = Color(0xFF2F7BE6);
  static const blueTint = Color(0xFFE6F0FC);
  static const pink = Color(0xFFFF6B8A);
  static const pinkTint = Color(0xFFFFE3EA);
  static const purple = Color(0xFF7B6CF6);
  static const purpleTint = Color(0xFFEFEBFF);
  static const lavender = Color(0xFFE6E0FF);
  static const indigo = Color(0xFF5B50E0);
  static const indigoDeep = Color(0xFF4A3FCB);
  static const peach = Color(0xFFFFD9C4);
  static const green = Color(0xFF5DBB63);
  static const greenTint = Color(0xFFE3F5E4);
  static const amber = Color(0xFFFFB547);

  static const ink = Color(0xFF1C2433);
  static const grey700 = Color(0xFF4A5263);
  static const grey500 = Color(0xFF8A90A0);
  static const grey200 = Color(0xFFE7E8EE);
  static const grey100 = Color(0xFFF4F4F7);
  static const cream = Color(0xFFF8F6FF);

  static const darkBg = Color(0xFF12141C);
  static const darkSurface = Color(0xFF1C1F2A);
  static const darkSurfaceHigh = Color(0xFF262A37);
}

/// 8-pt spacing scale.
abstract final class Space {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class Radii {
  static const card = 28.0;
  static const tile = 20.0;
  static const small = 12.0;
}

/// Brand colours that Material's ColorScheme does not cover. Couple mode
/// leans pink, friends mode blue/purple — swap the extension by mode.
@immutable
class CloserColors extends ThemeExtension<CloserColors> {
  const CloserColors({
    required this.accent,
    required this.accentTint,
    required this.secondary,
    required this.secondaryTint,
    required this.plant,
    required this.plantTint,
    required this.card,
    required this.muted,
    required this.gradient,
  });

  factory CloserColors.forMode(PairMode mode, Brightness b) {
    final dark = b == Brightness.dark;
    final couple = mode == PairMode.couple;
    final accent = couple ? Brand.pink : Brand.purple;
    final secondary = couple ? Brand.blue : Brand.blue;
    return CloserColors(
      accent: accent,
      accentTint: dark
          ? accent.withValues(alpha: 0.18)
          : (couple ? Brand.pinkTint : Brand.purpleTint),
      secondary: secondary,
      secondaryTint: dark ? secondary.withValues(alpha: 0.18) : Brand.blueTint,
      plant: Brand.green,
      plantTint: dark ? Brand.green.withValues(alpha: 0.18) : Brand.greenTint,
      card: dark ? Brand.darkSurface : Colors.white,
      muted: dark ? const Color(0xFF9AA0B2) : Brand.grey500,
      gradient: couple
          ? const [Color(0xFFA796FF), Color(0xFFFF9DB4)]
          : const [Color(0xFF9A8CFF), Color(0xFF6F86FF)],
    );
  }

  final Color accent;
  final Color accentTint;
  final Color secondary;
  final Color secondaryTint;
  final Color plant;
  final Color plantTint;
  final Color card;
  final Color muted;
  final List<Color> gradient;

  @override
  CloserColors copyWith({
    Color? accent,
    Color? accentTint,
    Color? secondary,
    Color? secondaryTint,
    Color? plant,
    Color? plantTint,
    Color? card,
    Color? muted,
    List<Color>? gradient,
  }) =>
      CloserColors(
        accent: accent ?? this.accent,
        accentTint: accentTint ?? this.accentTint,
        secondary: secondary ?? this.secondary,
        secondaryTint: secondaryTint ?? this.secondaryTint,
        plant: plant ?? this.plant,
        plantTint: plantTint ?? this.plantTint,
        card: card ?? this.card,
        muted: muted ?? this.muted,
        gradient: gradient ?? this.gradient,
      );

  @override
  CloserColors lerp(CloserColors? other, double t) {
    if (other == null) return this;
    return CloserColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryTint: Color.lerp(secondaryTint, other.secondaryTint, t)!,
      plant: Color.lerp(plant, other.plant, t)!,
      plantTint: Color.lerp(plantTint, other.plantTint, t)!,
      card: Color.lerp(card, other.card, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      gradient: [
        for (var i = 0; i < gradient.length; i++)
          Color.lerp(gradient[i], other.gradient[i], t)!,
      ],
    );
  }
}

extension CloserThemeX on BuildContext {
  CloserColors get cc => Theme.of(this).extension<CloserColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

abstract final class AppTheme {
  static const fontFamily = 'Nunito';

  static ThemeData build(Brightness brightness, PairMode mode) {
    final dark = brightness == Brightness.dark;
    final cc = CloserColors.forMode(mode, brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.purple,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF9C90FF) : Brand.purple,
      onPrimary: Colors.white,
      secondary: cc.accent,
      onSecondary: Colors.white,
      surface: dark ? Brand.darkBg : Brand.cream,
      onSurface: dark ? const Color(0xFFF2F4FA) : Brand.ink,
      surfaceContainerLowest: dark ? Brand.darkBg : Colors.white,
      surfaceContainerLow: dark ? Brand.darkSurface : Colors.white,
      surfaceContainer: dark ? Brand.darkSurface : Brand.grey100,
      surfaceContainerHigh: dark ? Brand.darkSurfaceHigh : Brand.grey200,
      outlineVariant: dark ? const Color(0xFF2E3242) : Brand.grey200,
      error: const Color(0xFFE5484D),
    );

    const base = TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.15),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.25),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    );
    final text = base.apply(
      fontFamily: fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [cc],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: cc.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: text.labelMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Brand.darkSurface : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.small + 4),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.small + 4),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.small + 4),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small + 4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cc.card,
        indicatorColor: cc.accentTint,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        height: 68,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cc.accent : null,
        ),
      ),
    );
  }
}
