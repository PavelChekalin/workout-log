import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workoutlog/catalog.dart';
import 'package:workoutlog/data.dart';
import 'package:workoutlog/trainer_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Repository.instance.people.clear();
    Repository.instance.exercises.clear();
    Repository.instance.sessions.clear();
  });

  test('по умолчанию участников нет', () async {
    await Repository.instance.init();
    expect(Repository.instance.people, isEmpty);
  });

  test('таймер отдыха: по умолчанию включён, настройки сохраняются', () async {
    final repo = Repository.instance;
    await repo.init();
    expect(repo.restTimerEnabled, isTrue);
    expect(repo.restSeconds, 120);

    await repo.setRestTimerEnabled(false);
    await repo.setRestSeconds(180);
    await repo.init(); // перечитываем из хранилища
    expect(repo.restTimerEnabled, isFalse);
    expect(repo.restSeconds, 180);
  });

  test('подходы сохраняются, вес предзаполняется, есть подсказка «неделю назад»',
      () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Жим лёжа', {1});
    final p = repo.addPerson('Паша');

    final today = DateTime(2026, 10, 9);
    final session = repo.sessionForOrNew(today, ex.id, p.id);
    session.sets.add(const SetEntry(60, 10));
    session.sets.add(const SetEntry(62.5, 8));

    expect(repo.lastSet(ex.id, p.id)?.weight, 62.5);
    expect(repo.lastSet(ex.id, p.id)?.reps, 8);

    final prev = DateTime(2026, 10, 2);
    repo.sessionForOrNew(prev, ex.id, p.id).sets.add(const SetEntry(55, 8));
    final lastWeek = repo.lastWeekSets(today, ex.id, p.id);
    expect(lastWeek, isNotNull);
    expect(lastWeek!.first.weight, 55);
  });

  test('неделю назад ищется только точная дата −7 дней', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Присед', {3});
    final p = repo.addPerson('Паша');
    final today = DateTime(2026, 10, 9);

    repo.sessionForOrNew(DateTime(2026, 10, 1), ex.id, p.id)
        .sets
        .add(const SetEntry(100, 5));
    expect(repo.lastWeekSets(today, ex.id, p.id), isNull);
  });

  test('рекорд за всё время — самый тяжёлый взятый вес', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Тяга', {5});
    final p = repo.addPerson('Антон');

    repo.sessionForOrNew(DateTime(2026, 9, 1), ex.id, p.id)
        .sets
        .add(const SetEntry(80, 10)); // 800, но вес меньше
    repo.sessionForOrNew(DateTime(2026, 10, 9), ex.id, p.id)
        .sets
        .add(const SetEntry(100, 4)); // самый тяжёлый вес
    repo.sessionForOrNew(DateTime(2026, 9, 20), ex.id, p.id)
        .sets
        .add(const SetEntry(90, 6));

    final record = repo.personalRecord(ex.id, p.id);
    expect(record, isNotNull);
    expect(record!.weight, 100);
    expect(record.reps, 4);

    // При равном весе выигрывает больший повтор.
    repo.sessionForOrNew(DateTime(2026, 9, 21), ex.id, p.id)
        .sets
        .add(const SetEntry(100, 8));
    expect(repo.personalRecord(ex.id, p.id)!.reps, 8);
  });

  test('аватарка: фото сохраняется в JSON и переживает экспорт/импорт', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    expect(p.avatar, isNull);

    final photo = Uint8List.fromList([1, 2, 3, 4, 5]);
    repo.setAvatar(p, photo);
    await repo.save();
    final dump = repo.exportJson();
    expect(dump, contains('"av"'));

    repo.people.clear();
    expect(repo.importJson(dump), isTrue);
    expect(repo.people.single.avatar, isNotNull);
    expect(repo.people.single.avatar!, photo);

    // Убрать фото тоже можно.
    repo.setAvatar(repo.people.single, null);
    expect(repo.people.single.avatar, isNull);
  });

  test('нельзя удалить последнего человека', () async {
    final repo = Repository.instance;
    await repo.init();
    repo.addPerson('Паша');
    repo.addPerson('Антон');
    repo.deletePerson(repo.people.last);
    expect(repo.people.length, 1);
    expect(repo.deletePerson(repo.people.first), isFalse);
    expect(repo.people.length, 1);
  });

  test('удаление упражнения убирает и его записи', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Тяга', {5});
    final p = repo.addPerson('Паша');
    repo.sessionForOrNew(DateTime(2026, 10, 9), ex.id, p.id)
        .sets
        .add(const SetEntry(80, 10));
    expect(repo.sessions, isNotEmpty);
    repo.deleteExercise(ex);
    expect(repo.exercises.any((e) => e.id == ex.id), isFalse);
    expect(repo.sessions.any((s) => s.exerciseId == ex.id), isFalse);
  });

  test('форматирование чисел и подходов', () {
    expect(fmtNumber(60), '60');
    expect(fmtNumber(62.5), '62.5');
    expect(fmtSet(const SetEntry(60, 10)), '60\u00d710');
    expect(fmtSet(const SetEntry(null, 12)), '\u00d712');
  });

  test('дни недели: именительный и винительный («на ...») падежи', () {
    const nominative = [
      'понедельник', 'вторник', 'среда', 'четверг',
      'пятница', 'суббота', 'воскресенье',
    ];
    const accusative = [
      'понедельник', 'вторник', 'среду', 'четверг',
      'пятницу', 'субботу', 'воскресенье',
    ];
    for (var day = 1; day <= 7; day++) {
      expect(weekdayNameRu(day), nominative[day - 1],
          reason: 'именительный, день $day');
      expect(weekdayNameRuAcc(day), accusative[day - 1],
          reason: 'винительный «на ...», день $day');
    }
  });

  test('recordedDates: отмечаются дни с подходами и заметками', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Жим', {1});
    final p = repo.addPerson('Паша');
    final d1 = DateTime(2026, 10, 5);
    final d2 = DateTime(2026, 10, 7);
    repo.sessionForOrNew(d1, ex.id, p.id).sets.add(const SetEntry(50, 10));
    repo.setNote(d2, 'пропуск');
    final marks = repo.recordedDates();
    expect(marks.contains(isoDate(d1)), isTrue, reason: 'день с подходами');
    expect(marks.contains(isoDate(d2)), isTrue, reason: 'день с заметкой');
    expect(marks.contains(isoDate(DateTime(2026, 10, 6))), isFalse,
        reason: 'пустой день не отмечен');
  });

  test('сохранение и загрузка JSON', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Становая', {2});
    final p = repo.addPerson('Паша');
    repo.sessionForOrNew(DateTime(2026, 10, 9), ex.id, p.id)
        .sets
        .add(const SetEntry(120, 5));
    await repo.save();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('workout_log_v1');
    expect(raw, isNotNull);
    expect(raw, contains('Становая'));
    expect(raw, contains('120'));
  });

  test('заметки к тренировке сохраняются и удаляются', () async {
    final repo = Repository.instance;
    await repo.init();
    final d = DateTime(2026, 10, 9);
    expect(repo.noteFor(d), isNull);
    repo.setNote(d, '  Паша с травмой кисти  ');
    expect(repo.noteFor(d), 'Паша с травмой кисти');
    repo.setNote(d, '   ');
    expect(repo.noteFor(d), isNull);
  });

  test('видео: привязка к дате и упражнению, своё в списке первое', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex1 = repo.addExercise('Жим лёжа', {5});
    final ex2 = repo.addExercise('Присед', {5});
    final d = DateTime(2026, 10, 11);
    expect(repo.videosFor(d, ex1.id), isEmpty);

    repo.addVideo(d, ex1.id, 'content://media/1');
    repo.addVideo(d, ex2.id, '/storage/app/WL_2.mp4');
    repo.addVideo(DateTime(2026, 10, 4), ex1.id, '/storage/app/WL_3.mp4');

    // Свежее видео идёт первым, чужие упражнения/даты не попадают.
    final list = repo.videosFor(d, ex1.id);
    expect(list, hasLength(1));
    expect(list.single.path, 'content://media/1');
    expect(repo.videosFor(d, ex2.id).single.path, '/storage/app/WL_2.mp4');
    expect(repo.videosFor(DateTime(2026, 10, 4), ex1.id), hasLength(1));

    // Дата с видео отмечается в календаре.
    expect(repo.recordedDates(), contains('2026-10-11'));

    // Убираем — запись уходит из журнала.
    repo.removeVideo(list.single);
    expect(repo.videosFor(d, ex1.id), isEmpty);

    // JSON содержит только путь, не сам файл.
    await repo.save();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('workout_log_v1')!;
    expect(raw, contains('WL_2.mp4'));
  });

  test('куда сохранять видео: по умолчанию Галерея, выбор сохраняется', () async {
    final repo = Repository.instance;
    await repo.init();
    expect(repo.videoStorage, 'gallery');
    await repo.setVideoStorage('app');
    expect(Repository.instance.videoStorage, 'app');
  });

  test('«повторить прошлый раз» берёт самую свежую прошлую тренировку', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Жим лёжа', {5});
    final p = repo.addPerson('Паша');
    final today = DateTime(2026, 10, 9);

    repo.sessionForOrNew(DateTime(2026, 10, 2), ex.id, p.id)
        .sets
        .add(const SetEntry(50, 10));
    repo.sessionForOrNew(DateTime(2026, 9, 25), ex.id, p.id)
        .sets
        .add(const SetEntry(45, 10));

    final prev = repo.previousSessionSets(today, ex.id, p.id);
    expect(prev, isNotNull);
    expect(prev!.single.weight, 50);
    expect(prev.single.reps, 10);

    // Если записи только «сегодня» — прошлого раза нет.
    repo.sessionForOrNew(today, ex.id, p.id).sets.add(const SetEntry(60, 8));
    final before = repo.previousSessionSets(DateTime(2026, 9, 20), ex.id, p.id);
    expect(before, isNull);
  });

  test('экспорт и импорт восстанавливают данные', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Присед', {1});
    final p = repo.addPerson('Антон');
    repo.sessionForOrNew(DateTime(2026, 10, 9), ex.id, p.id)
        .sets
        .add(const SetEntry(100, 5));
    repo.setNote(DateTime(2026, 10, 9), 'тест');

    final dump = repo.exportJson();
    repo.people.clear();
    repo.exercises.clear();
    repo.sessions.clear();
    repo.notes.clear();

    expect(repo.importJson(dump), isTrue);
    expect(repo.people.single.name, 'Антон');
    expect(repo.exercises.single.name, 'Присед');
    expect(repo.sessions.single.sets.single.weight, 100);
    expect(repo.notes.isNotEmpty, isTrue);

    expect(repo.importJson('не json'), isFalse);
  });

  test('справочник техники подсказывает по названию', () {
    expect(techById('squat')?.name, contains('Приседания'));
    final s = suggestTech('Жим лёжа');
    expect(s, isNotEmpty);
    expect(s.first.id, 'bench');
    expect(suggestTech('   ').isEmpty, isTrue);
    expect(techById(null), isNull);
  });

  test('привязка техники сохраняется и восстанавливается', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Жим лёжа', {1}, techId: 'bench');
    expect(ex.techId, 'bench');

    repo.updateExercise(ex, 'Жим лёжа', {1}, clearTech: true);
    expect(ex.techId, isNull);

    repo.updateExercise(ex, 'Жим лёжа', {1}, techId: 'squat');
    expect(ex.techId, 'squat');

    final dump = repo.exportJson();
    repo.exercises.clear();
    expect(repo.importJson(dump), isTrue);
    expect(repo.exercises.single.techId, 'squat');
  });

  // ---------- Тренер: данные ----------

  test('тренер: по умолчанию тон «тренер», напоминания выключены, онбординг не пройден', () async {
    final repo = Repository.instance;
    await repo.init();
    expect(repo.trainerTone, 'coach');
    expect(repo.remindersOn, isFalse);
    expect(repo.remindersTime, '18:00');
    expect(repo.trainerOnboarded, isFalse);
  });

  test('тренер: настройки сохраняются', () async {
    final repo = Repository.instance;
    await repo.init();
    await repo.setTrainerTone('buddy');
    await repo.setReminders(true, time: '07:30');
    repo.setTrainerOnboarded();
    expect(repo.trainerTone, 'buddy');
    expect(repo.remindersOn, isTrue);
    expect(repo.remindersTime, '07:30');
    expect(repo.trainerOnboarded, isTrue);
  });

  test('тренер: анкета сохраняется и переживает экспорт/импорт', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');

    final profile = TrainerProfile(
      age: 30,
      height: 178,
      weight: 80,
      exp: 'regular',
      goal: 'strength',
      days: 3,
      limits: {'knee'},
      program: 'strong_5x5',
      startDate: '2026-10-14',
      weekdays: {1, 3, 5},
      startWeights: {'squat': 40, 'bench': 30},
      fails: {'squat': 1},
    );
    repo.setTrainerProfile(p.id, profile);

    expect(repo.trainerProfile(p.id)!.program, 'strong_5x5');
    expect(repo.trainerProfile(p.id)!.limits, contains('knee'));
    expect(repo.trainerProfile('нет-такого'), isNull);

    final dump = repo.exportJson();
    expect(dump, contains('"trainer"'));
    expect(dump, contains('strong_5x5'));
    repo.trainerProfiles.clear();
    expect(repo.importJson(dump), isTrue);
    final loaded = repo.trainerProfile(p.id)!;
    expect(loaded.age, 30);
    expect(loaded.weight, 80);
    expect(loaded.weekdays, {1, 3, 5});
    expect(loaded.startWeights['squat'], 40);
    expect(loaded.fails['squat'], 1);
  });

  test('тренер: старый JSON без блока trainer грузится без ошибок', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    final ex = repo.addExercise('Присед', {1});
    repo.sessionForOrNew(DateTime(2026, 10, 9), ex.id, p.id)
        .sets
        .add(const SetEntry(100, 5));

    // Старый формат: без блока trainer.
    final oldJson =
        '{"people":[],"exercises":[],"sessions":[],"notes":{},"videos":[]}';
    expect(repo.importJson(oldJson), isTrue);
    expect(repo.trainerProfiles, isEmpty);
    expect(repo.trainerTone, 'coach');
    expect(repo.workouts, isEmpty);
  });

  test('тренер: удаление участника удаляет и его анкету', () async {
    final repo = Repository.instance;
    await repo.init();
    final p1 = repo.addPerson('Паша');
    final p2 = repo.addPerson('Антон');
    repo.setTrainerProfile(p1.id, TrainerProfile(age: 30, weight: 80));
    repo.setTrainerProfile(p2.id, TrainerProfile(age: 25, weight: 70));

    expect(repo.deletePerson(p2), isTrue);
    expect(repo.trainerProfile(p1.id), isNotNull);
    expect(repo.trainerProfile(p2.id), isNull);
  });

  test('тренер: тренировка дня — начало, конец, продолжение отрезком', () async {
    final repo = Repository.instance;
    await repo.init();
    final day = DateTime(2026, 10, 14);

    expect(repo.workoutOn(day), isNull);
    final w = repo.startWorkout(day);
    expect(w.running, isTrue);
    expect(repo.workoutOn(day), isNotNull);

    repo.endWorkout(day);
    expect(repo.workoutOn(day)!.running, isFalse);
    final firstStart = w.start;
    final firstEnd = w.end;

    // Продолжение: прежний отрезок ушёл в done, пошёл новый.
    final resumed = repo.startWorkout(day);
    expect(resumed.running, isTrue);
    expect(resumed.done, [[firstStart, firstEnd]]);
    expect(resumed.end, isNull); // новый отрезок идёт

    // Фазовые накопители переживают экспорт/импорт.
    resumed.activeSec = 120;
    resumed.restSec = 300;
    resumed.pauseSec = 60;
    final dump = repo.exportJson();
    repo.workouts.clear();
    expect(repo.importJson(dump), isTrue);
    final loaded = repo.workoutOn(day)!;
    expect(loaded.done, hasLength(1));
    expect(loaded.activeSec, 120);
    expect(loaded.restSec, 300);
    expect(loaded.pauseSec, 60);

    repo.removeWorkout(day);
    expect(repo.workoutOn(day), isNull);
  });

  test('лимит участников — 4', () async {
    final repo = Repository.instance;
    await repo.init();
    expect(repo.canAddPerson, isTrue);
    repo.addPerson('1');
    repo.addPerson('2');
    repo.addPerson('3');
    expect(repo.canAddPerson, isTrue);
    repo.addPerson('4');
    expect(repo.canAddPerson, isFalse);
    expect(Repository.maxPeople, 4);
  });
}
