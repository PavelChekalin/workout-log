import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:workoutlog/catalog.dart';
import 'package:workoutlog/coach_lines.dart';
import 'package:workoutlog/programs.dart';
import 'package:workoutlog/trainer_logic.dart';

void main() {
  // ---------- Каталог программ ----------

  test('каталог: все программы имеют уникальные id и привязку к технике', () {
    final ids = kPrograms.map((p) => p.id).toSet();
    expect(ids.length, kPrograms.length);
    expect(kPrograms.length, 8);

    // Все techId из каталога должны существовать в справочнике техники —
    // иначе упражнение не создастся и план не сработает.
    final knownTech = kTechCatalog.map((t) => t.id).toSet();
    for (final p in kPrograms) {
      for (final day in p.days) {
        expect(day.exercises, isNotEmpty, reason: '${p.id}/${day.title}');
        for (final e in day.exercises) {
          expect(knownTech, contains(e.techId),
              reason: '${p.id}/${day.title}: нет техники «${e.techId}»');
        }
      }
      // Основные движения 5/3/1 тоже должны быть известны.
      for (final lift in p.mainLifts) {
        expect(knownTech, contains(lift), reason: '${p.id}: 1RM «$lift»');
      }
    }
    expect(programById('strong_5x5')!.name, contains('5×5'));
    expect(programById('нет'), isNull);
    expect(programById(null), isNull);
  });

  test('каталог: у 5/3/1 четыре основных движения и цикл 4 недели', () {
    final p = programById('s531')!;
    expect(p.mainLifts, ['squat', 'bench', 'deadlift', 'ohp']);
    expect(p.cycleWeeks, 4);
    expect(p.daysPerWeek, 4);
  });

  // ---------- Подбор программы (таблица правил) ----------

  test('подбор: сброс веса всегда ведёт в круговую (или занятых на 2 днях)', () {
    expect(recommendProgramId(exp: 'beginner', goal: 'loss', days: 3),
        'circuit');
    expect(recommendProgramId(exp: 'regular', goal: 'loss', days: 6),
        'circuit');
    expect(
        recommendProgramId(exp: 'regular', goal: 'loss', days: 2), 'busy');
  });

  test('подбор: 2 дня — всегда «Занятые люди»', () {
    expect(recommendProgramId(exp: 'beginner', goal: 'strength', days: 2),
        'busy');
    expect(recommendProgramId(exp: 'regular', goal: 'mass', days: 2), 'busy');
  });

  test('подбор: 3 дня — новичок в форму, опытный в сплит', () {
    expect(recommendProgramId(exp: 'beginner', goal: 'strength', days: 3),
        'strong_5x5');
    expect(recommendProgramId(exp: 'beginner', goal: 'shape', days: 3),
        'full_beginner');
    expect(recommendProgramId(exp: 'break', goal: 'mass', days: 3),
        'full_beginner');
    expect(recommendProgramId(exp: 'regular', goal: 'mass', days: 3), 'cbl');
    expect(recommendProgramId(exp: 'regular', goal: 'strength', days: 3),
        'strong_5x5');
  });

  test('подбор: 4 дня — 5/3/1 только для регулярных', () {
    expect(recommendProgramId(exp: 'regular', goal: 'strength', days: 4),
        's531');
    expect(recommendProgramId(exp: 'beginner', goal: 'strength', days: 4),
        'ul');
    expect(recommendProgramId(exp: 'regular', goal: 'mass', days: 4), 'ul');
  });

  test('подбор: 5–6 дней — PPL для опытных, Верх/Низ для новичков', () {
    expect(recommendProgramId(exp: 'regular', goal: 'mass', days: 6), 'ppl');
    expect(recommendProgramId(exp: 'beginner', goal: 'mass', days: 6), 'ul');
    expect(recommendProgramId(exp: 'regular', goal: 'strength', days: 6),
        's531');
  });

  // ---------- Замены при ограничениях ----------

  test('замены: колено убирает присед и выпады', () {
    expect(substituteTech('squat', {'knee'}), 'legpress');
    expect(substituteTech('lunge', {'knee'}), 'legpress');
    expect(substituteTech('bench', {'knee'}), isNull);
  });

  test('замены: спина убирает становую и тягу штанги', () {
    expect(substituteTech('deadlift', {'back'}), 'rdl');
    expect(substituteTech('row_barbell', {'back'}), 'row_cable');
    expect(substituteTech('squat', {'back'}), isNull);
  });

  test('замены: плечо убирает жим стоя', () {
    expect(substituteTech('ohp', {'shoulder'}), 'bench');
    expect(substituteTech('ohp', {}), isNull);
  });

  test('замены: applyLimits меняет технику, сохраняя подходы/повторы', () {
    const e = PlanExercise('squat', 4, 5, '5');
    final sub = applyLimits(e, {'knee'});
    expect(sub.techId, 'legpress');
    expect(sub.sets, 4);
    expect(sub.reps, 5);
    // Без ограничений — то же упражнение.
    expect(identical(applyLimits(e, {}), e), isTrue);
  });

  // ---------- Стартовые веса ----------

  test('стартовые веса: дефолты по технике, без веса — null', () {
    expect(defaultStartWeight('squat'), 20);
    expect(defaultStartWeight('bench'), 20);
    expect(defaultStartWeight('lateral_raise'), 4);
    expect(defaultStartWeight('pullup'), isNull); // свой вес
    expect(defaultStartWeight('plank'), isNull); // на время
  });

  // ---------- Прогрессия ----------

  test('прогрессия: выполнил+легко → вес вверх на шаг', () {
    final fails = <String, int>{};
    expect(
        nextWeight(
            techId: 'bench',
            current: 60,
            result: WorkoutResult.easy,
            fails: fails),
        62.5);
    // Ноги — шаг 5.
    expect(
        nextWeight(
            techId: 'squat',
            current: 100,
            result: WorkoutResult.easy,
            fails: fails),
        105);
  });

  test('прогрессия: выполнил, но тяжело — держим вес', () {
    final fails = <String, int>{};
    expect(
        nextWeight(
            techId: 'bench',
            current: 60,
            result: WorkoutResult.hard,
            fails: fails),
        60);
    expect(fails['bench'], 0);
  });

  test('прогрессия: не выполнил — держим вес, после 3 неудач −10%', () {
    final fails = <String, int>{};
    expect(
        nextWeight(
            techId: 'bench',
            current: 60,
            result: WorkoutResult.failed,
            fails: fails),
        60);
    expect(fails['bench'], 1);
    nextWeight(
        techId: 'bench',
        current: 60,
        result: WorkoutResult.failed,
        fails: fails);
    expect(fails['bench'], 2);
    // Третья неудача — дельоад до 54 (60 × 0.9), округляем до 2,5 → 55.
    final dropped = nextWeight(
        techId: 'bench',
        current: 60,
        result: WorkoutResult.failed,
        fails: fails);
    expect(dropped, 55);
    expect(fails['bench'], 0); // серия сброшена
  });

  test('прогрессия: упражнение без веса — null, без прогрессии', () {
    final fails = <String, int>{};
    expect(
        nextWeight(
            techId: 'pullup',
            current: null,
            result: WorkoutResult.easy,
            fails: fails),
        isNull);
  });

  // ---------- 5/3/1 ----------

  test('Эпли: 1RM из веса и повторов', () {
    expect(epley1RM(100, 1), 100);
    expect(epley1RM(100, 5), closeTo(116.67, 0.01));
    expect(epley1RM(80, 8), closeTo(101.33, 0.01));
  });

  test('5/3/1: проценты по неделям, округление до 2,5', () {
    // 1RM = 100 кг.
    final w1 = scheme531(week: 1, oneRM: 100);
    expect(w1, [65.0, 75.0, 85.0]);

    final w2 = scheme531(week: 2, oneRM: 100);
    expect(w2, [70.0, 80.0, 90.0]);

    final w3 = scheme531(week: 3, oneRM: 100);
    expect(w3, [75.0, 85.0, 95.0]);

    // Неделя 4 — дельоад (лёгкая).
    final w4 = scheme531(week: 4, oneRM: 100);
    expect(w4, [40.0, 50.0, 60.0]);
    // За пределами цикла — тоже дельоад.
    expect(scheme531(week: 5, oneRM: 100), w4);
  });

  test('5/3/1: нестандартный 1RM округляется до ближайших 2,5', () {
    // 1RM = 87 кг: 65% = 56.55 → 55; 75% = 65.25 → 65; 85% = 73.95 → 75.
    final w1 = scheme531(week: 1, oneRM: 87);
    expect(w1[0] % 2.5, 0);
    expect(w1[1] % 2.5, 0);
    expect(w1[2] % 2.5, 0);
  });

  // ---------- Сегодняшний день программы ----------

  test('сегодня: сплит определяется днём недели', () {
    final cbl = programById('cbl')!; // Грудь/Спина/Ноги
    final days = {1, 3, 5};
    // Пн → Грудь, Ср → Спина, Пт → Ноги.
    expect(
        todayPlanDay(
                program: cbl,
                weekdays: days,
                today: DateTime(2026, 10, 12), // понедельник
                completedSessions: 0)
            .title,
        'Грудь');
    expect(
        todayPlanDay(
                program: cbl,
                weekdays: days,
                today: DateTime(2026, 10, 14), // среда
                completedSessions: 0)
            .title,
        'Спина');
    expect(
        todayPlanDay(
                program: cbl,
                weekdays: days,
                today: DateTime(2026, 10, 16), // пятница
                completedSessions: 0)
            .title,
        'Ноги');
    // Выходной (суббота) — план недели не ломается, берём первый.
    expect(
        todayPlanDay(
                program: cbl,
                weekdays: days,
                today: DateTime(2026, 10, 17),
                completedSessions: 0)
            .title,
        'Грудь');
  });

  test('сегодня: A/B чередуется по числу сделанных тренировок', () {
    final p = programById('strong_5x5')!;
    final days = {1, 3, 5};
    final mon = DateTime(2026, 10, 12);
    expect(
        todayPlanDay(
                program: p,
                weekdays: days,
                today: mon,
                completedSessions: 0)
            .title,
        'День A');
    expect(
        todayPlanDay(
                program: p,
                weekdays: days,
                today: mon,
                completedSessions: 1)
            .title,
        'День B');
    expect(
        todayPlanDay(
                program: p,
                weekdays: days,
                today: mon,
                completedSessions: 2)
            .title,
        'День A');
  });

  test('сегодня: однодневная программа (круговая) не чередуется', () {
    final p = programById('circuit')!;
    final days = {1, 3, 5};
    final mon = DateTime(2026, 10, 12);
    expect(
        todayPlanDay(
                program: p,
                weekdays: days,
                today: mon,
                completedSessions: 5)
            .title,
        'Круг');
  });

  test('выполненных тренировок: считаются даты с подходами после старта', () {
    final n = completedSessionsSince(
      startDate: '2026-10-14',
      recordedDates: {
        '2026-10-10', // до старта — не считается
        '2026-10-14',
        '2026-10-16',
        '2026-10-19',
      },
    );
    expect(n, 3);
  });

  // ---------- Недели цикла ----------

  test('цикл: номер недели считается от даты старта', () {
    // Старт 14.10 (среда).
    expect(
        currentCycleWeek(
            startDate: '2026-10-14', today: DateTime(2026, 10, 14), cycleWeeks: 6),
        1);
    expect(
        currentCycleWeek(
            startDate: '2026-10-14', today: DateTime(2026, 10, 20), cycleWeeks: 6),
        1); // ещё 1-я неделя (7 дней ровно — 20.10 конец недели 1)
    expect(
        currentCycleWeek(
            startDate: '2026-10-14', today: DateTime(2026, 10, 27), cycleWeeks: 6),
        2);
    // За пределами цикла — не вылезаем за последнюю неделю.
    expect(
        currentCycleWeek(
            startDate: '2026-10-14', today: DateTime(2026, 12, 27), cycleWeeks: 6),
        6);
    // Дата в прошлом — неделя 1.
    expect(
        currentCycleWeek(
            startDate: '2026-10-14', today: DateTime(2026, 10, 1), cycleWeeks: 6),
        1);
  });

  test('цикл: конец цикла наступает после последней недели', () {
    final start = '2026-10-14';
    // 4-недельный цикл: недели 1–4 — это дни 0–27 (до 10.11 включительно).
    // 10.11 ещё внутри цикла, 11.11 (28-й день) — цикл закончился.
    expect(
        cycleEnded(
            startDate: start, today: DateTime(2026, 11, 10), cycleWeeks: 4),
        isFalse);
    expect(
        cycleEnded(
            startDate: start, today: DateTime(2026, 11, 11), cycleWeeks: 4),
        isTrue);
    expect(weeksSinceStart(startDate: start, today: DateTime(2026, 10, 14)), 1);
  });

  // ---------- Фразы тренера ----------

  test('фразы: у каждого события есть варианты для всех трёх тонов', () {
    for (final event in kCoachLines.values) {
      expect(event.keys,
          containsAll([CoachTone.robot, CoachTone.coach, CoachTone.buddy]));
      for (final lines in event.values) {
        expect(lines.length, greaterThanOrEqualTo(3));
        expect(lines.every((l) => l.trim().isNotEmpty), isTrue);
      }
    }
  });

  test('фразы: выбор по тону, неизвестный тон падает на «Тренера»', () {
    final line = coachLine(CoachTone.robot, CoachEvent.start, random: Random(1));
    expect(line, isNotNull);
    // Фраза из словаря именно робота.
    expect(kCoachLines[CoachEvent.start]![CoachTone.robot], contains(line));
    expect(coachLine('нет-такого', CoachEvent.start), isNotNull);
    // Для неизвестного события — null, вызывающий код не показывает пустоту.
    expect(coachLine(CoachTone.coach, 'нет-такого'), isNull);
  });
}
