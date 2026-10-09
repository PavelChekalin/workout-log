import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workoutlog/catalog.dart';
import 'package:workoutlog/data.dart';

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

  test('рекорд за всё время — лучший подход по весу × повторениям', () async {
    final repo = Repository.instance;
    await repo.init();
    final ex = repo.addExercise('Тяга', {5});
    final p = repo.addPerson('Антон');

    repo.sessionForOrNew(DateTime(2026, 9, 1), ex.id, p.id)
        .sets
        .add(const SetEntry(80, 10)); // 800
    repo.sessionForOrNew(DateTime(2026, 10, 9), ex.id, p.id)
        .sets
        .add(const SetEntry(100, 4)); // 400
    repo.sessionForOrNew(DateTime(2026, 9, 20), ex.id, p.id)
        .sets
        .add(const SetEntry(90, 6)); // 540

    final record = repo.personalRecord(ex.id, p.id);
    expect(record, isNotNull);
    expect(record!.weight, 80);
    expect(record.reps, 10);
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
}
