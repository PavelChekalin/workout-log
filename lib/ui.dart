import 'package:flutter/material.dart';

/// Основной акцентный цвет приложения.
const Color kSeed = Color(0xFF00E0A4);

/// Палитра акцентов для участников (чтобы каждый был узнаваем).
const List<Color> kPersonColors = [
  Color(0xFF00E0A4),
  Color(0xFF4FC3F7),
  Color(0xFFFFB74D),
  Color(0xFFBA68C8),
  Color(0xFFE57373),
  Color(0xFFAED581),
];

/// Устойчивый цвет по идентификатору человека (не меняется между запусками).
Color personColor(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kPersonColors[h % kPersonColors.length];
}

String personInitial(String name) =>
    name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

/// Число с разделителями тысяч: 12500 -> "12 500".
String grouped(num v) {
  final s = v.round().abs().toString();
  final buf = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Текущий режим темы (реагирует на переключение в настройках).
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF0E1116)
        : const Color(0xFFF3F5F7),
  );
}

ThemeMode themeModeFromName(String name) => switch (name) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

String themeModeName(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
