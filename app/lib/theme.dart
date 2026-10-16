import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_state.dart';
import 'customization.dart';

/// ── Дизайн-токены ──────────────────────────────────────────
const double kRadius = 18;
const double kRadiusL = 26;
const double kGap = 16;

const Color kDanger = Color(0xFFF43F5E);
const Color kSuccess = Color(0xFF22C55E);
const Color kWarning = Color(0xFFF59E0B);
const Color kPremium = Color(0xFFFFB020);

/// Пресеты акцентов (сдержанные, «дорогие» тона)
const List<Color> kAccentPresets = [
  Color(0xFF7C6CFF), // виолет
  Color(0xFF3B82F6), // синий
  Color(0xFF10B981), // изумруд
  Color(0xFFEC4899), // розовый
  Color(0xFFF59E0B), // янтарь
  Color(0xFF64748B), // графит
];

/// Эксклюзивные акценты для Premium
const List<Color> kPremiumAccents = [
  Color(0xFFE11D48), // рубин
  Color(0xFF06B6D4), // бирюза
  Color(0xFFA855F7), // аметист
  Color(0xFFD4AF37), // золото
];

/// Градиент из акцента (акцент → чуть светлее)
LinearGradient accentGradient(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  final light = hsl.withLightness((hsl.lightness + 0.13).clamp(0.0, 1.0)).toColor();
  return LinearGradient(
    colors: [accent, light],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

const LinearGradient kPremiumGradient = LinearGradient(
  colors: [Color(0xFFFF8A00), Color(0xFFFFC53D), Color(0xFFB65CFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Цвет карточек/секций (зависит от выбранной темы)
Color cardColor(BuildContext c) => Theme.of(c).colorScheme.surface;

/// Приглушённый текст
Color subtleText(BuildContext c) => Theme.of(c).colorScheme.onSurfaceVariant;

/// Текст выбранным шрифтом.
TextStyle appFont({double? fontSize, FontWeight? fontWeight, Color? color,
    double? height, double? letterSpacing}) {
  try {
    return GoogleFonts.getFont(appState.fontEff,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing);
  } catch (_) {
    return GoogleFonts.manrope(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing);
  }
}

// ── Пузыри сообщений в выбранном стиле ──

/// Радиус пузыря с учётом стиля «Капсула».
double bubbleRadiusEff() =>
    appState.bubbleStyleEff == 'round' ? 24 : appState.bubbleRadius;

/// Пузырь своего сообщения.
BoxDecoration myBubbleDecoration(BorderRadius radius,
    {bool highlighted = false, String? style}) {
  final a = appState.accent;
  final glow = highlighted
      ? [BoxShadow(color: a.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)]
      : null;
  switch (style ?? appState.bubbleStyleEff) {
    case 'flat':
      return BoxDecoration(color: a, borderRadius: radius, boxShadow: glow);
    case 'glass':
      return BoxDecoration(
        color: a.withValues(alpha: 0.72),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1),
        boxShadow: glow ??
            [BoxShadow(color: a.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4))],
      );
    case 'neon':
      return BoxDecoration(
        color: const Color(0xFF0B0B14),
        borderRadius: radius,
        border: Border.all(color: a, width: 1.4),
        boxShadow: [
          BoxShadow(color: a.withValues(alpha: highlighted ? 0.8 : 0.45), blurRadius: highlighted ? 20 : 12),
        ],
      );
    case 'aurora':
      final h = HSLColor.fromColor(a);
      return BoxDecoration(
        gradient: LinearGradient(
          colors: [
            a,
            h.withHue((h.hue + 40) % 360).toColor(),
            h.withHue((h.hue + 90) % 360).withLightness((h.lightness + 0.08).clamp(0.0, 0.85)).toColor(),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: radius,
        boxShadow: glow,
      );
    default:
      return BoxDecoration(
        gradient: accentGradient(a),
        borderRadius: radius,
        boxShadow: glow ??
            [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
      );
  }
}

/// Пузырь чужого сообщения.
BoxDecoration otherBubbleDecoration(BuildContext c, BorderRadius radius,
    {bool highlighted = false, String? style}) {
  final a = appState.accent;
  final glow = highlighted
      ? [BoxShadow(color: a.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)]
      : null;
  switch (style ?? appState.bubbleStyleEff) {
    case 'glass':
      return BoxDecoration(
        color: cardColor(c).withValues(alpha: 0.62),
        borderRadius: radius,
        border: Border.all(color: hairline(c).withValues(alpha: 0.2), width: 1),
        boxShadow: glow,
      );
    case 'neon':
      return BoxDecoration(
        color: cardColor(c),
        borderRadius: radius,
        border: Border.all(color: a.withValues(alpha: 0.35), width: 1),
        boxShadow: glow,
      );
    case 'flat':
      return BoxDecoration(color: cardColor(c), borderRadius: radius, boxShadow: glow);
    default:
      return BoxDecoration(
        color: cardColor(c),
        borderRadius: radius,
        boxShadow: glow ??
            [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1))],
      );
  }
}

/// Тонкий разделитель
Color hairline(BuildContext c) =>
    (Theme.of(c).brightness == Brightness.dark ? Colors.white : Colors.black)
        .withValues(alpha: 0.06);

/// Плавный переход между экранами: лёгкий сдвиг + проявление.
/// Отключается в режиме энергосбережения / без анимаций.
class SmoothPageTransitions extends PageTransitionsBuilder {
  const SmoothPageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation,
      Widget child) {
    if (!appState.motion) return child;
    switch (appState.transitionEff) {
      case 'fade':
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: FadeTransition(
              opacity: Tween(begin: 1.0, end: 0.0).animate(
                  CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeIn)),
              child: child),
        );
      case 'zoom':
        final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: 0.86, end: 1.0).animate(a),
              child: ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.06).animate(
                      CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut)),
                  child: child)),
        );
      case 'depth':
        final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        final b = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
        return ScaleTransition(
          scale: Tween(begin: 1.0, end: 0.92).animate(b),
          child: FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.6).animate(b),
            child: SlideTransition(
              position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
        );
      case 'rise':
        final a = CurvedAnimation(parent: animation, curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.6)),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(a),
            child: child,
          ),
        );
    }
    // быстрый «въезд» справа; уходящий экран только чуть сдвигается — без полупрозрачности,
    // которая заставляла перерисовывать через отдельный слой сразу два экрана
    final inCurve =
        CurvedAnimation(parent: animation, curve: Curves.easeOutQuart,
            reverseCurve: Curves.easeInCubic);
    final outCurve =
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(-0.06, 0)).animate(outCurve),
      child: SlideTransition(
        position: Tween(begin: const Offset(0.1, 0), end: Offset.zero).animate(inCurve),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.55)),
          child: child,
        ),
      ),
    );
  }
}

ThemeData buildTheme(Color accent, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final pal = kPalettes[appState.themeStyleEff] ?? kPalettes['default']!;
  final bg = dark ? pal.darkBg : pal.lightBg;
  final surface = dark ? pal.darkCard : pal.lightCard;
  final fg = dark ? const Color(0xFFF5F6F8) : const Color(0xFF14161B);
  final subtle = dark ? const Color(0xFF8A8F9C) : const Color(0xFF6B7280);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(
    primary: accent,
    surface: surface,
    onSurface: fg,
    onSurfaceVariant: subtle,
  );

  final base = dark ? ThemeData.dark() : ThemeData.light();
  TextTheme text;
  try {
    text = GoogleFonts.getTextTheme(appState.fontEff, base.textTheme);
  } catch (_) {
    text = GoogleFonts.manropeTextTheme(base.textTheme);
  }
  text = text.apply(bodyColor: fg, displayColor: fg);

  return base.copyWith(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textTheme: text,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SmoothPageTransitions(),
      TargetPlatform.iOS: SmoothPageTransitions(),
      TargetPlatform.windows: SmoothPageTransitions(),
      TargetPlatform.linux: SmoothPageTransitions(),
      TargetPlatform.macOS: SmoothPageTransitions(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: fg),
      titleTextStyle: appFont(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: fg,
      ),
    ),
    dividerColor: Colors.transparent,
    // обычная «волна» — спокойнее и без подтормаживания при первом касании
    splashFactory: InkRipple.splashFactory,
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.3),
      selectionHandleColor: accent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF23262F) : const Color(0xFF1F2330),
      contentTextStyle: appFont(
          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusL)),
      titleTextStyle: appFont(
          color: fg, fontSize: 19, fontWeight: FontWeight.w700),
      contentTextStyle: appFont(color: subtle, fontSize: 15, height: 1.4),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalBackgroundColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: appFont(color: fg, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: TextStyle(color: subtle),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: BorderSide(color: accent, width: 1.6)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : null),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : null),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : null),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: subtle,
      titleTextStyle: appFont(
          color: fg, fontSize: 15.5, fontWeight: FontWeight.w600),
      subtitleTextStyle: appFont(color: subtle, fontSize: 13),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: appFont(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        textStyle: appFont(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      thumbColor: accent,
      inactiveTrackColor: accent.withValues(alpha: 0.2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: const Color(0xFF23262F), borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(color: Colors.white),
    ),
  );
}

/// Стабильный цвет аватара по строке
Color avatarColor(String seed) {
  var hash = 0;
  for (final c in seed.codeUnits) {
    hash = c + ((hash << 5) - hash);
  }
  final hue = (hash.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.45, 0.55).toColor();
}

/// Пресеты обоев для чата (градиенты). Индекс -1 = без обоев.
/// Последние 4 — только для Premium.
const List<List<Color>> kWallpapers = [
  [Color(0xFF1A1B2F), Color(0xFF2D1B3D)],
  [Color(0xFF0F2027), Color(0xFF203A43)],
  [Color(0xFF232526), Color(0xFF414345)],
  [Color(0xFF3A1C71), Color(0xFF6C5CE7)],
  [Color(0xFF134E5E), Color(0xFF71B280)],
  [Color(0xFF42275A), Color(0xFF734B6D)],
  [Color(0xFF0B486B), Color(0xFF3B8686)],
  [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
  // Premium
  [Color(0xFF200122), Color(0xFF6F0000)],
  [Color(0xFF0F0C29), Color(0xFF302B63)],
  [Color(0xFF1D4350), Color(0xFFA43931)],
  [Color(0xFF3E5151), Color(0xFFDECBA4)],
];
const int kFreeWallpapers = 8;

/// Обои-картинки (assets/wallpapers). В настройках хранятся как индекс 100 + i.
class ImageWallpaper {
  final String id;
  final String title;
  final bool premium;
  final bool dark; // тёмная картинка — пузыри «чужих» сообщений читаются как в тёмной теме
  const ImageWallpaper(this.id, this.title, {this.premium = false, this.dark = true});
  String get asset => 'assets/wallpapers/$id.webp';
  String get thumb => 'assets/wallpapers/${id}_thumb.webp';
}

const int kImageWallpaperBase = 100;

const List<ImageWallpaper> kImageWallpapers = [
  ImageWallpaper('wp_doodle_light', 'Каракули', dark: false),
  ImageWallpaper('wp_doodle_dark', 'Ночные каракули'),
  ImageWallpaper('wp_soft_gradient', 'Пастель', dark: false),
  ImageWallpaper('wp_mountains', 'Рассвет', dark: false),
  ImageWallpaper('wp_night_sky', 'Ночное небо'),
  ImageWallpaper('wp_waves', 'Волны', dark: false),
  ImageWallpaper('wp_p_neon_city', 'Неоновый город', premium: true),
  ImageWallpaper('wp_p_nebula', 'Туманность', premium: true),
  ImageWallpaper('wp_p_aurora', 'Северное сияние', premium: true),
  ImageWallpaper('wp_p_sakura', 'Сакура', premium: true, dark: false),
  ImageWallpaper('wp_p_gold', 'Золото', premium: true),
  ImageWallpaper('wp_p_ocean', 'Океан', premium: true),
  ImageWallpaper('wp_p_cozy_room', 'Уютная комната', premium: true),
  ImageWallpaper('wp_p_lava', 'Лава', premium: true),
];

/// Картинка-обои по сохранённому индексу (или null, если это градиент/выкл).
ImageWallpaper? imageWallpaperOf(int index) {
  final i = index - kImageWallpaperBase;
  return (i >= 0 && i < kImageWallpapers.length) ? kImageWallpapers[i] : null;
}
