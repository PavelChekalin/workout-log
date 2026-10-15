import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============ Триал ============

/// 30-дневный триал: дата первого запуска запоминается, после срока —
/// экран блокировки с полем кода разблокировки. Код разблокировки человеку
/// присылает Паша в ТГ.
class Trial {
  static const int days = 30;
  static const String _startKey = 'workout_trial_start';
  static const String _unlockedKey = 'workout_unlocked';

  /// Коды разблокировки. Сравниваются без регистра, пробелов и дефисов,
  /// так что «wsl 2026» и «WSL-2026» — одно и то же.
  /// Новый код для следующего человека — добавить сюда строкой.
  static const List<String> _codes = [
    'WSL-2026',
  ];

  /// Дата первого запуска (null — ещё не запомнили).
  static DateTime? firstLaunch;

  /// Разблокирован кодом — триал больше не проверяем.
  static bool unlocked = false;

  static String _norm(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  /// Подходит ли введённый код.
  static bool isCodeValid(String code) =>
      _codes.map(_norm).contains(_norm(code));

  /// Прочитать дату первого запуска и флаг разблокировки. Если даты ещё
  /// нет — запомнить сегодняшний день (с него начнётся отсчёт триала).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_startKey);
    if (raw == null) {
      firstLaunch = DateTime.now();
      await prefs.setString(_startKey, firstLaunch!.toIso8601String());
    } else {
      firstLaunch = DateTime.tryParse(raw) ?? DateTime.now();
    }
    unlocked = prefs.getBool(_unlockedKey) ?? false;
  }

  /// Истёк ли триал (и не разблокирован ли кодом).
  static bool get trialExpired {
    if (unlocked) return false;
    final start = firstLaunch ?? DateTime.now();
    return DateTime.now().difference(start).inDays >= days;
  }

  /// Сколько дней триала осталось (0 — уже кончился).
  static int get daysLeft {
    if (unlocked) return days;
    final start = firstLaunch ?? DateTime.now();
    final left = days - DateTime.now().difference(start).inDays;
    return left < 0 ? 0 : left;
  }

  /// Ввести код: успех — запомнить разблокировку навсегда.
  static Future<bool> tryUnlock(String code) async {
    if (!isCodeValid(code)) return false;
    unlocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unlockedKey, true);
    return true;
  }
}

/// Экран блокировки после триала: объяснение + поле для кода из ТГ.
class TrialLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const TrialLockScreen({super.key, required this.onUnlocked});

  @override
  State<TrialLockScreen> createState() => _TrialLockScreenState();
}

class _TrialLockScreenState extends State<TrialLockScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _try() async {
    final ok = await Trial.tryUnlock(_controller.text);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Код не подошёл. Проверь и попробуй ещё раз.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Журнал тренировок',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(
                  'Пробный период закончился',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Тридцать дней триала прошли. Введи код разблокировки — '
                  'он присылается в Телеграме, напиши за ним.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.35, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Код разблокировки',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _try(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _try,
                    child: const Text('Разблокировать'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ Лог последней ошибки ============

/// Лог последней необработанной ошибки — чтобы человек мог скинуть его
/// в ТГ вместо долгого описания «что-то упало». Ловит ошибки фреймворка
/// (FlutterError) и асинхронные падения (PlatformDispatcher).
class ErrorLog {
  static const String _prefsKey = 'workout_last_error';

  /// Последняя ошибка (null — не было). Текст: дата, версия, ошибка, стек.
  static String? lastError;

  static String _version = '';

  /// Поставить ловушку — вызывается первым делом в main(), до runApp.
  static void install() {
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack ?? StackTrace.current);
      if (kDebugMode) {
        prev?.call(details);
      }
    };
    // true = «ошибка обработана, приложение не роняем» — в релизе
    // человек вместо падения увидит приложение и сможет скинуть лог.
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return !kDebugMode;
    };
  }

  /// Прочитать сохранённую ошибку + запомнить версию приложения.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    lastError = prefs.getString(_prefsKey);
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
  }

  /// Записать ошибку: в память и в хранилище (переживает перезапуск).
  static void record(Object error, StackTrace stack) {
    final now = DateTime.now();
    final stamp =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final text = 'Журнал тренировок $_version\nОшибка: $stamp\n\n'
        '$error\n\n$stack';
    lastError = text;
    // Ошибка пишется после падения — не ждём, но и не роняемся, если
    // хранилище само недоступно.
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefsKey, text))
        .catchError((_) {});
  }

  @visibleForTesting
  static void resetForTest() {
    lastError = null;
    _version = '';
  }
}
