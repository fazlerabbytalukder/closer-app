import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/theme/gloss.dart';
import 'package:material_ui/material_ui.dart';

/// Brand tokens from the Duosy Figma file: violet primary, candy pink and
/// mint accents, lavender page background, deep indigo night mode.
abstract final class Brand {
  // Primary violet scale (the old "blue" names are kept so call sites follow).
  static const blue50 = Color(0xFFEFE9FF);
  static const blue100 = Color(0xFFC6B6FF);
  static const blue300 = Color(0xFFA98BFF);
  static const blue500 = Color(0xFF6A3DF0);
  static const blue700 = Color(0xFF4A22C4);

  /// Primary button gradient.
  static const royalLight = Color(0xFF8A4DFF);
  static const royal = Color(0xFF6A3DF0);

  /// Hero gradient (Figma: #3D4BFF → #7A45F0 → #E45CB0).
  static const heroStart = Color(0xFF7A45F0);
  static const cyan = Color(0xFF5FE0C8);

  static const blue = blue500;
  static const blueTint = blue50;
  static const pink = Color(0xFFFF5C9E);
  static const pinkTint = Color(0xFFFFE3F0);
  static const purple = Color(0xFF6A3DF0);
  static const purpleTint = Color(0xFFEFE9FF);
  static const mint = Color(0xFF8CF0DA);
  static const green = Color(0xFF1FAF9F);
  static const greenTint = Color(0xFFDDFBF4);
  static const amber = Color(0xFFFFB347);

  // Legacy names, re-pointed at the new palette so older call sites follow.
  static const lavender = blue50;
  static const indigo = blue500;
  static const indigoDeep = blue700;
  static const peach = Color(0xFFFFD9C4);

  static const ink = Color(0xFF1E1B3A);
  static const grey700 = Color(0xFF5A5380);
  static const grey500 = Color(0xFF8A84A8);
  static const grey200 = Color(0xFFE6E0F5);
  static const grey100 = Color(0xFFF5F1FF);

  /// Light page background.
  static const cream = Color(0xFFFBF8FF);

  // Dark mode (Figma onboarding #17142E with #2A2659 tiles).
  static const darkBg = Color(0xFF17142E);
  static const darkSurface = Color(0xFF221E42);
  static const darkSurfaceHigh = Color(0xFF2A2659);
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
  static const card = [BoxShadow(color: Color(0x1F6A3DF0), blurRadius: 24, offset: Offset(0, 8))];
  static const soft = [BoxShadow(color: Color(0x146A3DF0), blurRadius: 12, offset: Offset(0, 4))];
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
      muted: dark ? const Color(0xFFC6B6FF) : Brand.grey700,
      gradient: couple ? const [Color(0xFF7B5CFF), Color(0xFFFF4F9A)] : const [Color(0xFF3D4BFF), Brand.heroStart],
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
  /// Body font (Figma: Nunito 600/700/800).
  static const fontFamily = 'Nunito';

  /// Heading font (Figma: Fredoka SemiBold) for titles and big numbers.
  static const displayFamily = 'Fredoka';

  /// Flat design: a soft lift at rest, none when pressed or disabled.
  static final _buttonElevation = WidgetStateProperty.resolveWith<double>((states) {
    if (states.contains(WidgetState.disabled) || states.contains(WidgetState.pressed)) return 0;
    return 2;
  });

  /// Gap between the date/time picker buttons and the dialog edge. The
  /// pickers only pad their button row by 8px, so the buttons draw their
  /// own outer margin to sit clear of the rounded corner.
  static const _pickerButtonGap = EdgeInsetsDirectional.only(end: 10, bottom: 14);

  /// Picker "Cancel": muted text, bottom gap matching the OK pill.
  static ButtonStyle _pickerCancel(TextTheme text, CloserColors cc) =>
      TextButton.styleFrom(
        foregroundColor: cc.muted,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.transparent,
      ).copyWith(
        backgroundBuilder: (_, _, child) => Padding(padding: const EdgeInsets.only(bottom: 14), child: child),
      );

  /// Picker "OK": solid violet pill drawn inside an outer margin.
  static ButtonStyle _pickerConfirm(TextTheme text) =>
      TextButton.styleFrom(
        foregroundColor: Colors.white,
        textStyle: text.labelLarge,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.transparent,
      ).copyWith(
        backgroundBuilder: (_, states, child) => Padding(
          padding: _pickerButtonGap,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: states.contains(WidgetState.pressed) ? Brand.blue700 : Brand.royal,
            ),
            child: child,
          ),
        ),
      );

  static ThemeData build(Brightness brightness, PairMode mode) {
    final dark = brightness == Brightness.dark;
    final cc = CloserColors.forMode(mode, brightness);
    final scheme = ColorScheme.fromSeed(seedColor: Brand.blue, brightness: brightness).copyWith(
      primary: dark ? Brand.blue300 : Brand.indigo,
      onPrimary: Colors.white,
      primaryContainer: dark ? const Color(0xFF332A6E) : Brand.blue50,
      onPrimaryContainer: dark ? Brand.blue100 : Brand.royal,
      secondary: cc.accent,
      onSecondary: Colors.white,
      surface: dark ? Brand.darkBg : Brand.cream,
      onSurface: dark ? const Color(0xFFF7F4FF) : Brand.ink,
      onSurfaceVariant: dark ? Brand.blue100 : Brand.grey700,
      surfaceContainerLowest: dark ? Brand.darkBg : Colors.white,
      surfaceContainerLow: dark ? Brand.darkSurface : Colors.white,
      surfaceContainer: dark ? Brand.darkSurface : Brand.grey100,
      surfaceContainerHigh: dark ? Brand.darkSurfaceHigh : Brand.grey200,
      outline: dark ? const Color(0xFF433C7A) : const Color(0xFFD3CBEA),
      outlineVariant: dark ? const Color(0xFF2F2A5C) : Brand.grey200,
      error: const Color(0xFFEF4444),
    );

    // Figma type: Fredoka 600 for headings, titles and big numbers; Nunito
    // 600-800 for everything else (rows and buttons 800, descriptions 600-700).
    const display = AppTheme.displayFamily;
    const body = AppTheme.fontFamily;
    const base = TextTheme(
      displayLarge: TextStyle(fontFamily: display, fontSize: 56, fontWeight: FontWeight.w600, height: 1.05),
      displayMedium: TextStyle(fontFamily: display, fontSize: 44, fontWeight: FontWeight.w600, height: 1.1),
      displaySmall: TextStyle(fontFamily: display, fontSize: 32, fontWeight: FontWeight.w600, height: 1.15),
      headlineLarge: TextStyle(fontFamily: display, fontSize: 30, fontWeight: FontWeight.w600, height: 1.15),
      headlineMedium: TextStyle(fontFamily: display, fontSize: 28, fontWeight: FontWeight.w600, height: 1.15),
      headlineSmall: TextStyle(fontFamily: display, fontSize: 24, fontWeight: FontWeight.w600, height: 1.2),
      titleLarge: TextStyle(fontFamily: display, fontSize: 20, fontWeight: FontWeight.w600, height: 1.25),
      titleMedium: TextStyle(fontFamily: display, fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
      titleSmall: TextStyle(fontFamily: body, fontSize: 15, fontWeight: FontWeight.w800, height: 1.3),
      bodyLarge: TextStyle(fontFamily: body, fontSize: 16, fontWeight: FontWeight.w600, height: 1.45),
      bodyMedium: TextStyle(fontFamily: body, fontSize: 14, fontWeight: FontWeight.w600, height: 1.45),
      bodySmall: TextStyle(fontFamily: body, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
      labelLarge: TextStyle(fontFamily: body, fontSize: 16, fontWeight: FontWeight.w800),
      labelMedium: TextStyle(fontFamily: body, fontSize: 14, fontWeight: FontWeight.w800),
      labelSmall: TextStyle(fontFamily: body, fontSize: 12, fontWeight: FontWeight.w700),
    );
    const controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control)));
    final text = base.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

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
          backgroundBuilder: Gloss.builder(),
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
      // Date picker in the Duosy style: white card, violet header, bold
      // days, solid violet selected day, pink ring on today, violet pill OK.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: cc.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        headerBackgroundColor: Brand.royal,
        headerForegroundColor: Colors.white,
        headerHelpStyle: text.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
        headerHeadlineStyle: text.headlineMedium?.copyWith(color: Colors.white, fontSize: 30),
        dividerColor: Colors.transparent,
        weekdayStyle: text.labelMedium?.copyWith(color: cc.muted),
        dayStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        dayForegroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return Colors.white;
          if (s.contains(WidgetState.disabled)) return scheme.onSurface.withValues(alpha: 0.3);
          return scheme.onSurface;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.royal : Colors.transparent,
        ),
        dayOverlayColor: WidgetStatePropertyAll(Brand.royal.withValues(alpha: 0.1)),
        todayForegroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return Colors.white;
          return dark ? Brand.blue300 : Brand.royal;
        }),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.royal : Colors.transparent,
        ),
        todayBorder: const BorderSide(color: Brand.pink, width: 1.8),
        yearStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
        yearForegroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return Colors.white;
          if (s.contains(WidgetState.disabled)) return scheme.onSurface.withValues(alpha: 0.3);
          return scheme.onSurface;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.royal : Colors.transparent,
        ),
        yearOverlayColor: WidgetStatePropertyAll(Brand.royal.withValues(alpha: 0.1)),
        cancelButtonStyle: _pickerCancel(text, cc),
        confirmButtonStyle: _pickerConfirm(text),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? scheme.surfaceContainerHigh : Brand.blue50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Brand.royal, width: 1.6),
          ),
        ),
      ),
      // Time picker to match: lavender hour/minute boxes, violet dial hand,
      // violet AM/PM choice and the same Cancel / OK buttons.
      timePickerTheme: TimePickerThemeData(
        backgroundColor: cc.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        helpTextStyle: text.labelMedium?.copyWith(color: cc.muted),
        hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        hourMinuteColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (dark ? Brand.royal.withValues(alpha: 0.35) : Brand.blue50)
              : (dark ? scheme.surfaceContainerHigh : const Color(0xFFF5F2FF)),
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (dark ? Colors.white : Brand.royal) : scheme.onSurface,
        ),
        hourMinuteTextStyle: text.displayMedium?.copyWith(fontSize: 48),
        dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        dayPeriodBorderSide: BorderSide(color: scheme.outline),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.royal : Colors.transparent,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : scheme.onSurface,
        ),
        dayPeriodTextStyle: text.labelLarge,
        dialBackgroundColor: dark ? scheme.surfaceContainerHigh : const Color(0xFFF5F2FF),
        dialHandColor: Brand.royal,
        dialTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : scheme.onSurface,
        ),
        dialTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
        entryModeIconColor: dark ? Brand.blue300 : Brand.royal,
        cancelButtonStyle: _pickerCancel(text, cc),
        confirmButtonStyle: _pickerConfirm(text),
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
