import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/gloss.dart';
import 'package:flutter/material.dart';

/// Brand tokens, modelled on the "Dual Space" design system:
/// royal-blue primary scale, near-black navy dark mode, pink accent.
abstract final class Brand {
  // Primary blue scale (Figma "primary color-50…900").
  static const blue50 = Color(0xFFE8F1FF);
  static const blue100 = Color(0xFFB7D3FF);
  static const blue300 = Color(0xFF649FFF);
  static const blue500 = Color(0xFF1770FF);
  static const blue700 = Color(0xFF1050B5);

  /// Primary button gradient (Figma: #6878EA → #0722D8).
  static const royalLight = Color(0xFF6878EA);
  static const royal = Color(0xFF0722D8);

  /// Hero / premium gradient (Figma "Button Color": #1737E2 → #00FDFF).
  static const heroStart = Color(0xFF1737E2);
  static const cyan = Color(0xFF00C6FF);

  static const blue = blue500;
  static const blueTint = blue50;
  static const pink = Color(0xFFFF2D6F);
  static const pinkTint = Color(0xFFFFE4EC);
  static const purple = Color(0xFF6A3DE8);
  static const purpleTint = Color(0xFFEEE8FF);
  static const green = Color(0xFF22C55E);
  static const greenTint = Color(0xFFDDF7E7);
  static const amber = Color(0xFFFFB020);

  // Legacy names, re-pointed at the new palette so older call sites follow.
  static const lavender = blue50;
  static const indigo = Color(0xFF2343E6);
  static const indigoDeep = royal;
  static const peach = Color(0xFFFFD9C4);

  static const ink = Color(0xFF0F1221);
  static const grey700 = Color(0xFF4A5068);
  static const grey500 = Color(0xFF7D849B);
  static const grey200 = Color(0xFFDDE3EF);
  static const grey100 = Color(0xFFEFF3FA);

  /// Light page background — a whisper of primary-50.
  static const cream = Color(0xFFF1F5FD);

  // Dark mode (Figma home screen #0F1221 with navy tiles).
  static const darkBg = Color(0xFF0F1221);
  static const darkSurface = Color(0xFF1A1E2F);
  static const darkSurfaceHigh = Color(0xFF242A3E);
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
  static const card = 20.0;
  static const tile = 16.0;
  static const small = 12.0;

  /// Buttons and text fields.
  static const control = 12.0;
}

/// Soft, blue-tinted elevation used by cards and tiles in light mode.
abstract final class Shadows {
  static const card = [BoxShadow(color: Color(0x141737E2), blurRadius: 24, offset: Offset(0, 8))];
  static const soft = [BoxShadow(color: Color(0x0F1737E2), blurRadius: 12, offset: Offset(0, 4))];
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
    const secondary = Brand.blue;
    return CloserColors(
      accent: accent,
      accentTint: dark ? accent.withValues(alpha: 0.18) : (couple ? Brand.pinkTint : Brand.purpleTint),
      secondary: secondary,
      secondaryTint: dark ? secondary.withValues(alpha: 0.18) : Brand.blueTint,
      plant: Brand.green,
      plantTint: dark ? Brand.green.withValues(alpha: 0.18) : Brand.greenTint,
      card: dark ? Brand.darkSurface : Colors.white,
      muted: dark ? const Color(0xFF8E96AD) : Brand.grey500,
      gradient: couple ? const [Brand.heroStart, Color(0xFFFF5C9A)] : const [Brand.heroStart, Brand.cyan],
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
  }) => CloserColors(
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
      gradient: [for (var i = 0; i < gradient.length; i++) Color.lerp(gradient[i], other.gradient[i], t)!],
    );
  }
}

extension CloserThemeX on BuildContext {
  CloserColors get cc => Theme.of(this).extension<CloserColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

abstract final class AppTheme {
  static const fontFamily = 'PlusJakartaSans';

  /// Flat design: a soft lift at rest, none when pressed or disabled.
  static final _buttonElevation = WidgetStateProperty.resolveWith<double>((states) {
    if (states.contains(WidgetState.disabled) || states.contains(WidgetState.pressed)) return 0;
    return 2;
  });

  static ThemeData build(Brightness brightness, PairMode mode) {
    final dark = brightness == Brightness.dark;
    final cc = CloserColors.forMode(mode, brightness);
    final scheme = ColorScheme.fromSeed(seedColor: Brand.blue, brightness: brightness).copyWith(
      primary: dark ? const Color(0xFF5E8BFF) : Brand.indigo,
      onPrimary: Colors.white,
      primaryContainer: dark ? const Color(0xFF1C2A5C) : Brand.blue50,
      onPrimaryContainer: dark ? Brand.blue100 : Brand.royal,
      secondary: cc.accent,
      onSecondary: Colors.white,
      surface: dark ? Brand.darkBg : Brand.cream,
      onSurface: dark ? const Color(0xFFF2F4FA) : Brand.ink,
      onSurfaceVariant: dark ? const Color(0xFFB4BACB) : Brand.grey700,
      surfaceContainerLowest: dark ? Brand.darkBg : Colors.white,
      surfaceContainerLow: dark ? Brand.darkSurface : Colors.white,
      surfaceContainer: dark ? Brand.darkSurface : Brand.grey100,
      surfaceContainerHigh: dark ? Brand.darkSurfaceHigh : Brand.grey200,
      outline: dark ? const Color(0xFF3A4159) : const Color(0xFFC5CDDD),
      outlineVariant: dark ? const Color(0xFF283048) : Brand.grey200,
      error: const Color(0xFFEF4444),
    );

    // Type scale from the design file: H1 32 / H2 28 / H3 24 / H4 20,
    // headings SemiBold, body 18-12 Regular/Medium.
    const base = TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.4),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.3),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.375),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.36),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    const controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control)));
    final text = base.apply(fontFamily: fontFamily, bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      ),
      // Flat 12px-radius buttons; the primary gets the royal-blue gradient
      // (painted by Gloss over the deep royal base colour).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: controlShape,
          backgroundColor: Brand.royal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.surfaceContainerHigh,
          textStyle: text.labelLarge,
          shadowColor: Brand.royal.withValues(alpha: 0.6),
          backgroundBuilder: Gloss.builder(radius: Radii.control),
        ).copyWith(elevation: _buttonElevation),
      ),
      // Secondary: light primary tint with a blue outline (Figma "Button CTA").
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: controlShape,
          textStyle: text.labelLarge,
          foregroundColor: dark ? Brand.blue100 : Brand.royal,
          backgroundColor: dark ? Brand.darkSurfaceHigh : Brand.blue50,
          side: BorderSide(color: dark ? scheme.outline : Brand.blue300, width: 1.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: controlShape,
          foregroundColor: scheme.primary,
          textStyle: text.labelMedium,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: controlShape)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Brand.darkSurface : Colors.white,
        hintStyle: text.bodyMedium?.copyWith(color: cc.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: dark ? Brand.darkSurface : Colors.white,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelMedium,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.small)),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall?.copyWith(color: cc.muted),
        iconColor: scheme.primary,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? Brand.darkSurfaceHigh : Brand.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cc.card,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        height: 68,
      ),
      // Figma toggles: solid primary track, white thumb, no outline.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blue500 : null),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blue500 : null),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blue500 : null),
      ),
    );
  }
}
