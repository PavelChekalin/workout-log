import 'package:health/health.dart';

/// Шаги и пульс за сегодня из Health Connect (данные владельца телефона).
class TodayHealth {
  const TodayHealth({
    this.steps,
    this.pulseBpm,
    this.granted = false,
    this.sdkReady = false,
  });

  /// Шаги за сегодня (null — данных нет или нет доступа).
  final int? steps;

  /// Последний за сегодня пульс, уд/мин.
  final int? pulseBpm;

  /// Доступ к Health Connect выдан.
  final bool granted;

  /// Health Connect доступен (на Android 15 он встроен в телефон).
  final bool sdkReady;
}

/// Тонкий мост к Health Connect: только чтение шагов и пульса за сегодня.
/// Все ошибки глотаем — часы не должны ронять журнал тренировок.
class HealthBridge {
  HealthBridge._();

  static final Health _health = Health();

  static List<HealthDataType> get _types =>
      [HealthDataType.STEPS, HealthDataType.HEART_RATE];

  /// Прочитать состояние (доступен Health Connect / выдан доступ / данные).
  /// Разрешения НЕ запрашивает — только читает, что уже можно.
  static Future<TodayHealth> load() async {
    try {
      final status = await _health.getHealthConnectSdkStatus();
      final sdkReady = status == HealthConnectSdkStatus.sdkAvailable;
      if (!sdkReady) return const TodayHealth();
      final granted = await _health.hasPermissions(_types) ?? false;
      if (!granted) return const TodayHealth(sdkReady: true);

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      int? steps;
      try {
        steps = await _health.getTotalStepsInInterval(start, now);
      } catch (_) {
        // Шаги могут быть недоступны — не беда, покажем без них.
      }
      int? pulse;
      try {
        final points = await _health.getHealthDataFromTypes(
          types: [HealthDataType.HEART_RATE],
          startTime: start,
          endTime: now,
        );
        if (points.isNotEmpty) {
          points.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
          pulse = (points.last.value as NumericHealthValue)
              .numericValue
              .round();
        }
      } catch (_) {
        // Пульс может быть недоступен — не беда, покажем без него.
      }
      return TodayHealth(
          steps: steps, pulseBpm: pulse, granted: true, sdkReady: true);
    } catch (_) {
      return const TodayHealth();
    }
  }

  /// Запросить доступ к шагам и пульсу. true — доступ выдан.
  static Future<bool> requestAccess() async {
    try {
      return await _health.requestAuthorization(_types);
    } catch (_) {
      return false;
    }
  }

  /// Отобрать доступ (если захочется переиграть).
  static Future<void> revokeAccess() async {
    try {
      await _health.revokePermissions();
    } catch (_) {}
  }

  /// Установить Health Connect (для телефонов, где он не встроен).
  static Future<void> installHealthConnect() async {
    try {
      await _health.installHealthConnect();
    } catch (_) {}
  }
}
