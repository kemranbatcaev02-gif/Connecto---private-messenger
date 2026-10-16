import 'package:flutter/material.dart';

import 'icons.dart';

/// Вариант оформления: id, название, подпись, Premium или нет.
class Opt {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool premium;
  const Opt(this.id, this.title, this.subtitle, this.icon, {this.premium = false});
}

Opt optOf(List<Opt> list, String id) =>
    list.firstWhere((o) => o.id == id, orElse: () => list.first);

// ── Тема (палитра фона и карточек) ──
const List<Opt> kThemeStyles = [
  Opt('default', 'Классика', 'Графит и белый', AppIcons.palette),
  Opt('amoled', 'AMOLED', 'Чистый чёрный — бережёт батарею', AppIcons.moon),
  Opt('soft', 'Мягкая', 'Тёплые спокойные тона', AppIcons.sun),
  Opt('midnight', 'Полночь', 'Глубокий синий', AppIcons.moon, premium: true),
  Opt('ocean', 'Океан', 'Бирюзовая глубина', AppIcons.waves, premium: true),
  Opt('forest', 'Лес', 'Хвойная зелень', AppIcons.sparkles, premium: true),
  Opt('sunset', 'Закат', 'Сливовый вечер', AppIcons.sun, premium: true),
  Opt('sakura', 'Сакура', 'Нежно-розовая', AppIcons.heart, premium: true),
  Opt('cyber', 'Киберпанк', 'Неоновая ночь', AppIcons.brushSpark, premium: true),
  Opt('mocha', 'Мокка', 'Кофейные оттенки', AppIcons.cake, premium: true),
];

class Palette {
  final Color darkBg, darkCard, lightBg, lightCard;
  const Palette(this.darkBg, this.darkCard, this.lightBg, this.lightCard);
}

const Map<String, Palette> kPalettes = {
  'default': Palette(Color(0xFF0A0B0F), Color(0xFF15171E), Color(0xFFF5F6F9), Color(0xFFFFFFFF)),
  'amoled': Palette(Color(0xFF000000), Color(0xFF0F0F12), Color(0xFFFFFFFF), Color(0xFFF1F2F5)),
  'soft': Palette(Color(0xFF14120F), Color(0xFF1F1C18), Color(0xFFF7F3EE), Color(0xFFFFFCF8)),
  'midnight': Palette(Color(0xFF070B1A), Color(0xFF111833), Color(0xFFEEF2FF), Color(0xFFFFFFFF)),
  'ocean': Palette(Color(0xFF041417), Color(0xFF0B2328), Color(0xFFEAF7F8), Color(0xFFFFFFFF)),
  'forest': Palette(Color(0xFF07120C), Color(0xFF102018), Color(0xFFEEF6F0), Color(0xFFFFFFFF)),
  'sunset': Palette(Color(0xFF150A14), Color(0xFF241425), Color(0xFFFBEFF3), Color(0xFFFFFFFF)),
  'sakura': Palette(Color(0xFF170C12), Color(0xFF261520), Color(0xFFFFF1F5), Color(0xFFFFFFFF)),
  'cyber': Palette(Color(0xFF07040F), Color(0xFF140C24), Color(0xFFF3EEFF), Color(0xFFFFFFFF)),
  'mocha': Palette(Color(0xFF120D0A), Color(0xFF211914), Color(0xFFF6EFE9), Color(0xFFFFFBF7)),
};

// ── Стиль сообщений ──
const List<Opt> kBubbleStyles = [
  Opt('classic', 'Классика', 'Градиент и хвостик', AppIcons.bubble),
  Opt('flat', 'Плоский', 'Сплошной цвет без теней', AppIcons.square),
  Opt('round', 'Капсула', 'Максимально круглые', AppIcons.circle),
  Opt('glass', 'Стекло', 'Полупрозрачные с рамкой', AppIcons.layers, premium: true),
  Opt('neon', 'Неон', 'Тёмные со свечением', AppIcons.brushSpark, premium: true),
  Opt('aurora', 'Сияние', 'Переливающийся градиент', AppIcons.gradient, premium: true),
];

// ── Шрифт ──
const List<Opt> kFonts = [
  Opt('Manrope', 'Manrope', 'Стандартный', AppIcons.type),
  Opt('Nunito', 'Nunito', 'Мягкий, округлый', AppIcons.type),
  Opt('Montserrat', 'Montserrat', 'Строгий геометрический', AppIcons.type, premium: true),
  Opt('Comfortaa', 'Comfortaa', 'Круглый и дружелюбный', AppIcons.type, premium: true),
  Opt('Rubik', 'Rubik', 'Плотный, современный', AppIcons.type, premium: true),
  Opt('Unbounded', 'Unbounded', 'Широкий, яркий', AppIcons.type, premium: true),
  Opt('JetBrains Mono', 'JetBrains Mono', 'Для программистов', AppIcons.squareSlash, premium: true),
  Opt('Caveat', 'Caveat', 'Рукописный', AppIcons.pencil, premium: true),
];

// ── Переходы между экранами ──
const List<Opt> kTransitions = [
  Opt('slide', 'Сдвиг', 'Плавный сдвиг вбок', AppIcons.arrowRightLeft),
  Opt('fade', 'Проявление', 'Мягкое затухание', AppIcons.eye),
  Opt('zoom', 'Зум', 'Экран вырастает из центра', AppIcons.search, premium: true),
  Opt('depth', 'Глубина', 'Старый экран уходит вглубь', AppIcons.layers, premium: true),
  Opt('rise', 'Подъём', 'Выезжает снизу с пружиной', AppIcons.chevronUp, premium: true),
];

// ── Нижнее меню ──
const List<Opt> kNavStyles = [
  Opt('glass', 'Стекло', 'Размытая плавающая панель', AppIcons.navBar),
  Opt('solid', 'Классика', 'Панель во всю ширину', AppIcons.navBar),
  Opt('floating', 'Капсула', 'Компактная, только иконки', AppIcons.circle, premium: true),
  Opt('neon', 'Неон', 'Светящиеся иконки', AppIcons.brushSpark, premium: true),
];

// ── Стиль иконок в меню и профилях ──
const List<Opt> kIconStyles = [
  Opt('color', 'Цветные', 'Яркие плашки, как в iOS', AppIcons.palette),
  Opt('pastel', 'Пастель', 'Мягкие цветные', AppIcons.brush),
  Opt('soft', 'Акцент', 'В цвет темы', AppIcons.circle),
  Opt('mono', 'Минимал', 'Строгие, без цвета', AppIcons.circle),
  Opt('glow', 'Неон', 'Светятся в темноте', AppIcons.brushSpark, premium: true),
  Opt('aurora', 'Сияние', 'Переливы от акцента', AppIcons.sparkles, premium: true),
];

// ── Рамка аватара в профиле ──
const List<Opt> kAvatarRings = [
  Opt('none', 'Без рамки', '', AppIcons.circle),
  Opt('accent', 'Акцент', 'Цвет темы', AppIcons.circle),
  Opt('rainbow', 'Радуга', 'Вращается', AppIcons.gradient, premium: true),
  Opt('gold', 'Золото', 'Мерцает', AppIcons.crown, premium: true),
  Opt('aurora', 'Сияние', 'Переливается', AppIcons.sparkles, premium: true),
];

// ── Рамки чатов в списке ──
const List<Opt> kChatFrames = [
  Opt('none', 'Без рамок', 'Классический список', AppIcons.ban),
  Opt('card', 'Карточки', 'Мягкие плитки с тенью', AppIcons.square),
  Opt('outline', 'Контур', 'Тонкая рамка в цвет темы', AppIcons.frame),
  Opt('pill', 'Капсулы', 'Очень круглые', AppIcons.circle),
  Opt('gradient', 'Градиент', 'Рамка из двух оттенков', AppIcons.gradient, premium: true),
  Opt('neon', 'Неон', 'Светящийся контур', AppIcons.brushSpark, premium: true),
  Opt('aurora', 'Сияние', 'Переливается по кругу', AppIcons.sparkles, premium: true),
  Opt('glass', 'Стекло', 'Прозрачные с бликом', AppIcons.layers, premium: true),
  Opt('gold', 'Золото', 'Золотой кант с блеском', AppIcons.crown, premium: true),
  Opt('custom', 'Своя', 'Цвета, толщина, свечение', AppIcons.tune, premium: true),
];

// ── Обводка сообщений ──
const List<Opt> kBubbleFrames = [
  Opt('none', 'Без обводки', '', AppIcons.ban),
  Opt('thin', 'Тонкая', 'Аккуратный светлый кант', AppIcons.frame),
  Opt('accent', 'Акцент', 'Кант в цвет темы', AppIcons.circle),
  Opt('gradient', 'Градиент', 'Два оттенка', AppIcons.gradient, premium: true),
  Opt('neon', 'Неон', 'Светится', AppIcons.brushSpark, premium: true),
  Opt('aurora', 'Сияние', 'Бегущий перелив', AppIcons.sparkles, premium: true),
  Opt('gold', 'Золото', 'С блеском', AppIcons.crown, premium: true),
  Opt('custom', 'Своя', 'Ручная настройка', AppIcons.tune, premium: true),
];

/// Ручная настройка рамки (Premium). Хранится в настройках как JSON.
class FrameCustom {
  final Color c1;
  final Color c2;
  final bool twoColors;  // градиент из двух цветов
  final double width;    // толщина 0.5–4
  final double radius;   // скругление плиток в списке 6–32
  final double glow;     // свечение 0–1
  final double fill;     // заливка плитки 0–1 (только список)
  final bool animated;   // перелив по кругу / бегущий блик

  const FrameCustom({
    this.c1 = const Color(0xFF7C6CFF),
    this.c2 = const Color(0xFF22D3EE),
    this.twoColors = true,
    this.width = 2,
    this.radius = 20,
    this.glow = 0.35,
    this.fill = 1,
    this.animated = true,
  });

  FrameCustom copyWith({Color? c1, Color? c2, bool? twoColors, double? width, double? radius,
          double? glow, double? fill, bool? animated}) =>
      FrameCustom(
        c1: c1 ?? this.c1,
        c2: c2 ?? this.c2,
        twoColors: twoColors ?? this.twoColors,
        width: width ?? this.width,
        radius: radius ?? this.radius,
        glow: glow ?? this.glow,
        fill: fill ?? this.fill,
        animated: animated ?? this.animated,
      );

  Map<String, dynamic> toJson() => {
        'c1': c1.toARGB32(),
        'c2': c2.toARGB32(),
        'two': twoColors,
        'w': width,
        'r': radius,
        'g': glow,
        'f': fill,
        'a': animated,
      };

  static double _d(Object? v, double def, double lo, double hi) {
    final x = (v is num) ? v.toDouble() : def;
    return x < lo ? lo : (x > hi ? hi : x);
  }

  factory FrameCustom.fromJson(Map<String, dynamic> j) => FrameCustom(
        c1: Color((j['c1'] as num?)?.toInt() ?? 0xFF7C6CFF),
        c2: Color((j['c2'] as num?)?.toInt() ?? 0xFF22D3EE),
        twoColors: j['two'] != false,
        width: _d(j['w'], 2, 0.5, 4),
        radius: _d(j['r'], 20, 6, 32),
        glow: _d(j['g'], 0.35, 0, 1),
        fill: _d(j['f'], 1, 0, 1),
        animated: j['a'] != false,
      );
}

// ── Иконка приложения (Android) ──
const List<Opt> kLauncherIcons = [
  Opt('classic', 'Классика', 'Фирменная', AppIcons.circle),
  Opt('night', 'Ночь', 'Тёмная', AppIcons.moon),
  Opt('light', 'Светлая', 'Воздушная', AppIcons.sun),
  Opt('neon', 'Неон', 'Ночной город', AppIcons.brushSpark, premium: true),
  Opt('gold', 'Золото', 'Роскошь', AppIcons.crown, premium: true),
  Opt('glass', 'Стекло', 'Прозрачная', AppIcons.layers, premium: true),
  Opt('space', 'Космос', 'Туманность', AppIcons.sparkles, premium: true),
  Opt('sakura', 'Сакура', 'Весна', AppIcons.heart, premium: true),
  Opt('lava', 'Лава', 'Огонь', AppIcons.flame, premium: true),
  Opt('aurora', 'Аврора', 'Северное сияние', AppIcons.waves, premium: true),
];

// ── Анимированные обои (Premium) ──
class LiveWallpaper {
  final String title;
  final List<Color> colors;
  const LiveWallpaper(this.title, this.colors);
}

const List<LiveWallpaper> kLiveWallpapers = [
  LiveWallpaper('Северное сияние',
      [Color(0xFF0B1E3A), Color(0xFF0E6B5C), Color(0xFF3A1C71), Color(0xFF0B1E3A)]),
  LiveWallpaper('Лава', [Color(0xFF2B0A0A), Color(0xFF8E1B1B), Color(0xFFD9480F), Color(0xFF2B0A0A)]),
  LiveWallpaper('Космос', [Color(0xFF05010F), Color(0xFF2A0E61), Color(0xFF0B3B8C), Color(0xFF05010F)]),
  LiveWallpaper('Неон', [Color(0xFF0D0221), Color(0xFF7B2CBF), Color(0xFF00B4D8), Color(0xFF0D0221)]),
  LiveWallpaper('Рассвет', [Color(0xFF2E1437), Color(0xFFB5487D), Color(0xFFF4A261), Color(0xFF2E1437)]),
  LiveWallpaper('Мята', [Color(0xFF0A1F1A), Color(0xFF1B7F6B), Color(0xFF7ED6C1), Color(0xFF0A1F1A)]),
];

/// Эмодзи для статуса рядом с именем (Premium).
const List<String> kStatusEmojis = [
  '🔥', '⭐', '💎', '👑', '🚀', '💜', '💙', '💚', '🖤', '❤️', '⚡', '🌙',
  '☀️', '🌸', '🍀', '🎮', '🎧', '🏋️', '🏊', '⚽', '🎯', '💻', '📚', '✈️',
  '😎', '🤖', '👻', '🦊', '🐺', '🐉', '🍕', '☕', '🎉', '💤', '🧠', '🛸',
];
