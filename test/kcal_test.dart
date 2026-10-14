import 'package:flutter_test/flutter_test.dart';
import 'package:workoutlog/kcal.dart';

void main() {
  // ---------- Таймер отрезков ----------

  test('таймер: один отрезок считается от старта до конца', () {
    // Начали 18:32, закончили 19:28 → 56 минут.
    final sec = workoutElapsedSec(
      done: const [],
      start: '18:32',
      end: '19:28',
      now: DateTime(2026, 10, 14, 20, 0),
    );
    expect(sec, 56 * 60);
  });

  test('таймер: текущий отрезок идёт до «сейчас»', () {
    // Начали 18:32, сейчас 18:40 → 8 минут.
    final sec = workoutElapsedSec(
      done: const [],
      start: '18:32',
      end: null,
      now: DateTime(2026, 10, 14, 18, 40),
    );
    expect(sec, 8 * 60);
  });

  test('таймер: после завершения время заморожено', () {
    // Закончили в 19:28, сейчас уже 21:00 — калорий и секунд не добавилось.
    final sec = workoutElapsedSec(
      done: const [],
      start: '18:32',
      end: '19:28',
      now: DateTime(2026, 10, 14, 21, 0),
    );
    expect(sec, 56 * 60);
  });

  test('таймер: продолжение — сумма отрезков плюс текущий', () {
    // Первый заход 18:32–19:28 (56 мин), вернулись в 21:05, сейчас 21:20.
    final sec = workoutElapsedSec(
      done: const [
        ['18:32', '19:28'],
      ],
      start: '21:05',
      end: null,
      now: DateTime(2026, 10, 14, 21, 20),
    );
    expect(sec, (56 + 15) * 60);
  });

  test('таймер: тренировка через полночь не уходит в минус', () {
    final sec = workoutElapsedSec(
      done: const [],
      start: '23:30',
      end: '00:15',
      now: DateTime(2026, 10, 15, 0, 15),
    );
    expect(sec, 45 * 60);
  });

  test('разбор времени: мусор не роняет расчёт', () {
    expect(minutesOfDay('18:32'), 18 * 60 + 32);
    expect(minutesOfDay('7:05'), 7 * 60 + 5);
    expect(minutesOfDay('мусор'), 0);
  });

  // ---------- Фазы ----------

  test('фазы: 1,5 минуты после подхода — актив (MET 6)', () {
    expect(metForPhase(sinceLastSetSec: 0, restRunning: false), 6);
    expect(metForPhase(sinceLastSetSec: 90, restRunning: false), 6);
  });

  test('фазы: дальше — восстановление, пока идёт отдых и не дольше 3 мин', () {
    expect(metForPhase(sinceLastSetSec: 91, restRunning: true), 4);
    expect(metForPhase(sinceLastSetSec: 180, restRunning: true), 4);
    // Отдых кончился — сразу пауза.
    expect(metForPhase(sinceLastSetSec: 91, restRunning: false), 3);
  });

  test('фазы: тишина дольше 3 минут — пауза (MET 3)', () {
    expect(metForPhase(sinceLastSetSec: 181, restRunning: true), 3);
    // Подхода ещё не было (или экран перезагрузили) — тоже пауза.
    expect(metForPhase(sinceLastSetSec: 999999, restRunning: false), 3);
  });

  // ---------- Калории ----------

  test('калории: MET × вес × время', () {
    // 30 минут активности для 80 кг: 6 × 0.5 ч × 80 = 240.
    expect(
        kcalFromPhases(
            activeSec: 1800, restSec: 0, pauseSec: 0, weightKg: 80),
        closeTo(240, 0.01));
    // Смешанная тренировка: 20 мин актив, 30 мин отдыха, 10 мин пауза.
    // 6×20 + 4×30 + 3×10 = 120+120+30 = 270 MET-мин → /60 × 70 кг = 315.
    expect(
        kcalFromPhases(
            activeSec: 1200, restSec: 1800, pauseSec: 600, weightKg: 70),
        closeTo(315, 0.01));
    // Ноль секунд — ноль калорий.
    expect(
        kcalFromPhases(activeSec: 0, restSec: 0, pauseSec: 0, weightKg: 80),
        0);
  });

  test('длительность: человеческий текст', () {
    expect(fmtDuration(0), '0 мин');
    expect(fmtDuration(37 * 60), '37 мин');
    expect(fmtDuration(60 * 60), '1 ч 0 мин');
    expect(fmtDuration(72 * 60 + 30), '1 ч 12 мин');
  });

  test('панель: длительность словами с правильными склонениями', () {
    expect(ruDurationWords(0), 'меньше минуты');
    expect(ruDurationWords(45), 'меньше минуты');
    expect(ruDurationWords(59), 'меньше минуты');
    expect(ruDurationWords(60), '1 минуту');
    expect(ruDurationWords(2 * 60), '2 минуты');
    expect(ruDurationWords(5 * 60), '5 минут');
    expect(ruDurationWords(11 * 60), '11 минут');
    expect(ruDurationWords(21 * 60), '21 минуту');
    expect(ruDurationWords(3600), '1 час');
    expect(ruDurationWords(3 * 3600), '3 часа');
    expect(ruDurationWords(5 * 3600), '5 часов');
    expect(ruDurationWords(11 * 3600), '11 часов');
    expect(ruDurationWords(21 * 3600), '21 час');
    expect(ruDurationWords(3600 + 60), '1 час 1 минуту');
    expect(ruDurationWords(72 * 60), '1 час 12 минут');
    expect(ruDurationWords(2 * 3600 + 5 * 60), '2 часа 5 минут');
    expect(ruDurationWords(5 * 3600 + 45 * 60), '5 часов 45 минут');
  });
}
