// ---------------------------------------------------------------------------
// Калории тренировки: грубая оценка по фазам (MET × вес × время).
//
// Метод табличный (MET), честная точность силовой ±25–40% — показываем
// везде с пометкой «≈». Фазы (§6.1 спецификации):
//   актив          1,5 мин после записи подхода      MET 6
//   восстановление пока идёт отдых-таймер, до 3 мин  MET 4
//   пауза          тишина дольше 3 минут             MET 3
// Все функции чистые — легко тестировать.
// ---------------------------------------------------------------------------

/// Метка времени в минутах: 'HH:mm' → минуты с полуночи. Ошибка разбора → 0.
int minutesOfDay(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return 0;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return h * 60 + m;
}

/// Сколько секунд идёт тренировка (сумма завершённых отрезков + текущий).
/// [now] — текущее время. Концы недели после полуночи не считаем
/// (тренировка-марафон через полночь — редкость, оценим честно по факту).
int workoutElapsedSec({
  required List<List<String>> done,
  required String? start,
  required String? end,
  required DateTime now,
}) {
  var sec = 0;
  for (final seg in done) {
    if (seg.length < 2) continue;
    var diff = minutesOfDay(seg[1]) - minutesOfDay(seg[0]);
    if (diff < 0) diff += 24 * 60; // через полночь
    sec += diff * 60;
  }
  // Текущий (или последний) отрезок: от start до end, либо до «сейчас»,
  // если ещё идёт.
  if (start != null && start.isNotEmpty) {
    final untilMin = end != null
        ? minutesOfDay(end)
        : now.hour * 60 + now.minute;
    var diff = untilMin - minutesOfDay(start);
    if (diff < 0) diff += 24 * 60;
    sec += diff * 60;
  }
  return sec;
}

/// MET текущей фазы.
///
/// [sinceLastSetSec] — сколько секунд прошло с последнего записанного
/// подхода (большое значение — подхода ещё не было или экран перезагрузили).
/// [restRunning] — работает ли сейчас отдых-таймер.
double metForPhase({
  required int sinceLastSetSec,
  required bool restRunning,
}) {
  if (sinceLastSetSec <= 90) return 6; // актив: полторы минуты после подхода
  if (sinceLastSetSec <= 180 && restRunning) {
    return 4; // восстановление: отдых-таймер, но не дольше 3 минут
  }
  return 3; // пауза
}

/// Калории по накопленным секундам фаз: MET × вес × время.
///
/// [weightKg] — вес тела из анкеты. Без веса калории считать не умеем.
double kcalFromPhases({
  required int activeSec,
  required int restSec,
  required int pauseSec,
  required double weightKg,
}) {
  const metActive = 6.0;
  const metRest = 4.0;
  const metPause = 3.0;
  final metHours =
      (metActive * activeSec + metRest * restSec + metPause * pauseSec) /
          3600.0;
  return metHours * weightKg;
}

/// '1 ч 12 мин' / '37 мин' / '0 мин'.
String fmtDuration(int totalSec) {
  final min = totalSec ~/ 60;
  if (min < 60) return '$min мин';
  return '${min ~/ 60} ч ${min % 60} мин';
}
