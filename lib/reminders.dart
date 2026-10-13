// ---------------------------------------------------------------------------
// Напоминания о тренировках (§10): локальные уведомления в те дни недели,
// где тренируется хоть один участник с программой. Полностью офлайн.
//
// Включаются в онбординге и в Настройках (по умолчанию ВЫКЛ). Расписание:
// одно повторяющееся уведомление на день недели (id = день недели).
// Текст собирается из актуальных программ участников при пересчёте.
// ---------------------------------------------------------------------------

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'data.dart';
import 'trainer_apply.dart';

/// Напоминания: запрос разрешения и постановка расписания.
class Reminders {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'trainer_reminders',
    'Напоминания тренера',
    channelDescription: 'Напоминание о тренировке в запланированный день',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  static const NotificationDetails _details =
      NotificationDetails(android: _android);

  /// Инициализация: канал, часовой пояс. На платформах без уведомлений —
  /// молча выходим (тесты, десктоп).
  static Future<void> init() async {
    if (_inited) return;
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // Не вышло определить локацию — работаем с системным tz.local.
      }
      _inited = true;
    } catch (_) {
      // Уведомлений нет — дальше всё равно живём без ошибок.
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _androidImpl =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Разрешены ли уведомления (на Android 12 и ниже — всегда true).
  static Future<bool> isEnabled() async {
    final impl = _androidImpl;
    if (impl == null) return false;
    try {
      return await impl.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Спросить разрешение (Android 13+). В true — получили.
  static Future<bool> requestPermission() async {
    final impl = _androidImpl;
    if (impl == null) return false;
    try {
      return await impl.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Пересчитать расписание под текущие программы участников.
  ///
  /// Возвращает false, если уведомления выключены или разрешения нет —
  /// вызывающий код показывает честное сообщение.
  static Future<bool> reschedule(
    Repository repo, {
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await init();
    for (var id = 1; id <= 7; id++) {
      await _plugin.cancel(id);
    }
    if (!enabled || !_inited) return false;
    if (!await requestPermission()) return false;

    for (var weekday = 1; weekday <= 7; weekday++) {
      final text = reminderTextForWeekday(repo: repo, weekday: weekday);
      if (text == null) continue;
      await _plugin.zonedSchedule(
        weekday,
        'Тренировка сегодня',
        text,
        _nextInstanceOfWeekday(weekday, hour, minute),
        _details,
        // inexact — не просим разрешения на точные будильники,
        // уведомление приходит в течение примерно получаса от указанного.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
    return true;
  }

  /// Ближайший указанный день недели в [hour]:[minute] по локальному tz.
  static tz.TZDateTime _nextInstanceOfWeekday(
      int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Разбор 'HH:mm' → часы, минуты. Мусор → 18:00.
  static (int, int) parseTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first.trim()) ?? 18;
    final m = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    return (h.clamp(0, 23).toInt(), m.clamp(0, 59).toInt());
  }
}
