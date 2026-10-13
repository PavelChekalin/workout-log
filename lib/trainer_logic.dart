// ---------------------------------------------------------------------------
// Логика офлайн-тренера: подбор программы, прогрессия весов, схема 5/3/1,
// замены при ограничениях, стартовые веса.
//
// Всё — таблицы правил «если... то...», без интернета и ИИ. Каждая функция
// чистая (много данных на вход, одно значение на выход) — легко тестировать.
// ---------------------------------------------------------------------------

import 'programs.dart';

// ---------------------------------------------------------------------------
// Подбор программы (таблица правил §4 спецификации)
// ---------------------------------------------------------------------------

/// Подобрать программу по анкете: опыт + цель + дни в неделю.
///
/// [exp] — 'beginner' (< 6 мес) | 'break' (перерыв) | 'regular' (> года).
/// [goal] — 'strength' | 'shape' | 'mass' | 'loss'.
/// [days] — 2, 3, 4 или 6.
String recommendProgramId({
  required String exp,
  required String goal,
  required int days,
}) {
  // Сброс веса — приоритетнее всего: круговая подходит под любые дни.
  if (goal == 'loss') {
    if (days <= 2) return 'busy';
    return 'circuit';
  }

  if (days <= 2) return 'busy';

  if (days == 3) {
    // Новичок или после перерыва — фундамент.
    if (exp == 'beginner' || exp == 'break') {
      return goal == 'strength' ? 'strong_5x5' : 'full_beginner';
    }
    // Опытный: сила — 5×5, масса/форма — сплит.
    return goal == 'strength' ? 'strong_5x5' : 'cbl';
  }

  if (days == 4) {
    // Сила на 4 днях: 5/3/1 только для «регулярно», новичку — Верх/Низ.
    if (goal == 'strength') {
      return exp == 'regular' ? 's531' : 'ul';
    }
    return 'ul';
  }

  // 5–6 дней.
  if (goal == 'strength') return 's531';
  // Новичок на 6 днях рано — дадим Верх/Низ.
  if (exp == 'beginner' || exp == 'break') return 'ul';
  return 'ppl';
}

// ---------------------------------------------------------------------------
// Замены при ограничениях (§4): колено / спина / плечо
// ---------------------------------------------------------------------------

/// Как заменить технику при ограничениях. null — замена не нужна.
String? substituteTech(String techId, Set<String> limits) {
  if (limits.contains('knee')) {
    if (techId == 'squat') return 'legpress';
    if (techId == 'lunge') return 'legpress';
  }
  if (limits.contains('back')) {
    if (techId == 'deadlift') return 'rdl';
    if (techId == 'row_barbell') return 'row_cable';
  }
  if (limits.contains('shoulder')) {
    if (techId == 'ohp') return 'bench';
  }
  return null;
}

/// Применить все замены к упражнению плана.
PlanExercise applyLimits(PlanExercise e, Set<String> limits) {
  final sub = substituteTech(e.techId, limits);
  if (sub == null) return e;
  return PlanExercise(sub, e.sets, e.reps, e.label);
}

// ---------------------------------------------------------------------------
// Стартовые веса (§5)
// ---------------------------------------------------------------------------

/// Дефолтный стартовый вес (кг) по технике, если в журнале нет записей.
/// null — упражнение без веса (свой вес, планка).
double? defaultStartWeight(String techId) {
  const weights = <String, double>{
    'squat': 20,
    'bench': 20,
    'deadlift': 40,
    'ohp': 20,
    'row_barbell': 30,
    'rdl': 30,
    'legpress': 40,
    'lunge': 10,
    'bench_dumbbell': 10,
    'fly': 6,
    'curl_barbell': 15,
    'curl_hammer': 8,
    'triceps_fr': 15,
    'triceps_push': 15,
    'lateral_raise': 4,
    'shrug': 20,
    'calf': 20,
  };
  return weights[techId];
}

// ---------------------------------------------------------------------------
// Прогрессия (§7)
// ---------------------------------------------------------------------------

/// Итог тренировки по упражнению.
enum WorkoutResult {
  /// Выполнил план и было легко/норма — вес вверх.
  easy,

  /// Выполнил план, но тяжело — держим вес.
  hard,

  /// Не выполнил план — держим вес, считаем неудачу.
  failed,
}

/// Следующий рабочий вес.
///
/// [current] — текущий вес; null — упражнение без веса (вернёт null).
/// Возвращает новый вес и обновляет счётчик неудач [fails] (techId -> серия).
double? nextWeight({
  required String techId,
  required double? current,
  required WorkoutResult result,
  required Map<String, int> fails,
}) {
  if (current == null) return null; // упражнение без веса — прогрессии нет

  if (result == WorkoutResult.easy) {
    fails[techId] = 0; // серия неудач прервалась
    return current + weightStepFor(techId);
  }

  if (result == WorkoutResult.hard) {
    fails[techId] = 0; // выполнил, но тяжело — неудач не прибавляем
    return current;
  }

  // failed: считаем неудачу, после трёх подряд — дельоад −10%.
  final f = (fails[techId] ?? 0) + 1;
  fails[techId] = f;
  if (f >= 3) {
    fails[techId] = 0;
    return _round25(current * 0.9);
  }
  return current;
}

/// Округлить до 2,5 (ближайшее рабочее значение штанги).
double _round25(double v) => (v / 2.5).round() * 2.5;

// ---------------------------------------------------------------------------
// 5/3/1 (§3): проценты от 1RM по неделям
// ---------------------------------------------------------------------------

/// Формула Эпли: оценка 1RM по весу и повторам.
double epley1RM(double weight, int reps) {
  if (reps <= 1) return weight;
  return weight * (1 + reps / 30);
}

/// Рабочие веса схемы 5/3/1 на неделю цикла (1..4) от 1RM.
///
/// Возвращает три числа (кг), уже округлённых до 2,5.
/// Неделя 4 — дельоад (лёгкая).
List<double> scheme531({required int week, required double oneRM}) {
  final percents = switch (week) {
    1 => [0.65, 0.75, 0.85],
    2 => [0.70, 0.80, 0.90],
    3 => [0.75, 0.85, 0.95],
    _ => [0.40, 0.50, 0.60], // дельоад
  };
  return percents.map((p) => _round25(oneRM * p)).toList();
}

/// Какая неделя цикла сейчас (1..N), от даты старта и длительности цикла.
///
/// [startDate] — 'yyyy-MM-dd', [today] — текущая дата, [cycleWeeks] — длина
/// цикла в неделях. Возвращает 1-based номер недели.
int currentCycleWeek({
  required String startDate,
  required DateTime today,
  required int cycleWeeks,
}) {
  final parts = startDate.split('-');
  final start = DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  final diff = today.difference(start).inDays;
  final week = (diff ~/ 7) + 1;
  if (week < 1) return 1;
  // После конца цикла — считаем последнюю неделю (цикл на переоценке).
  return week > cycleWeeks ? cycleWeeks : week;
}

/// Сколько всего недель прошло с старта (для отчёта о конце цикла).
int weeksSinceStart({required String startDate, required DateTime today}) {
  final parts = startDate.split('-');
  final start = DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  final diff = today.difference(start).inDays;
  return diff < 0 ? 0 : (diff ~/ 7) + 1;
}

/// Закончился ли цикл (прошло недель не меньше длительности цикла).
bool cycleEnded({
  required String startDate,
  required DateTime today,
  required int cycleWeeks,
}) =>
    weeksSinceStart(startDate: startDate, today: today) > cycleWeeks;
