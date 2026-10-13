import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workoutlog/data.dart';
import 'package:workoutlog/programs.dart';
import 'package:workoutlog/reminders.dart';
import 'package:workoutlog/trainer_apply.dart';
import 'package:workoutlog/trainer_data.dart';
import 'package:workoutlog/trainer_logic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = Repository.instance;
    repo.people.clear();
    repo.exercises.clear();
    repo.sessions.clear();
    repo.trainerProfiles.clear();
    repo.workouts.clear();
  });

  // ---------- Привязка плана к дням недели ----------

  test('план по дням: сплит ложится по порядку на выбранные дни', () {
    final cbl = programById('cbl')!;
    final binding = planByWeekday(
        program: cbl, weekdays: {1, 3, 5}, limits: <String>{});
    expect(binding.keys.toSet(), {1, 3, 5});
    expect(binding[1]!.first.techId, 'bench'); // Грудь
    expect(binding[3]!.first.techId, 'row_barbell'); // Спина
    expect(binding[5]!.first.techId, 'squat'); // Ноги
  });

  test('план по дням: PPL повторяется по кругу на 6 дней', () {
    final ppl = programById('ppl')!;
    final binding = planByWeekday(
        program: ppl, weekdays: {1, 2, 3, 4, 5, 6}, limits: <String>{});
    expect(binding[1]!.first.techId, 'bench'); // Push
    expect(binding[2]!.first.techId, 'pullup'); // Pull
    expect(binding[3]!.first.techId, 'squat'); // Legs
    expect(binding[4]!.first.techId, 'bench'); // Push снова
  });

  test('план по дням: A/B-программа даёт свод на каждый день', () {
    final p = programById('strong_5x5')!;
    final binding = planByWeekday(
        program: p, weekdays: {1, 3, 5}, limits: <String>{});
    // Свод A+B: присед, жим, тяга, жим стоя, становая — на всех днях.
    final ids = binding[1]!.map((e) => e.techId).toSet();
    expect(ids, containsAll(['squat', 'bench', 'row_barbell', 'ohp', 'deadlift']));
    expect(binding[3]!.length, binding[1]!.length);
  });

  test('план по дням: ограничение колена меняет присед на жим ногами', () {
    final p = programById('strong_5x5')!;
    final binding = planByWeekday(
        program: p, weekdays: {1, 3, 5}, limits: {'knee'});
    final ids = binding[1]!.map((e) => e.techId).toSet();
    expect(ids, isNot(contains('squat')));
    expect(ids, contains('legpress'));
    // Без ограничений — присед на месте.
    final free = planByWeekday(
        program: p, weekdays: {1, 3, 5}, limits: <String>{});
    expect(free[1]!.map((e) => e.techId), contains('squat'));
  });

  // ---------- Назначение программы ----------

  test('назначение: создаёт упражнения и привязывает их к дням', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    final cbl = programById('cbl')!;

    final created = assignProgram(
      repo: repo,
      personId: p.id,
      program: cbl,
      weekdays: {1, 3, 5},
      limits: <String>{},
      today: DateTime(2026, 10, 14),
    );

    expect(created, isNotEmpty);
    // Все созданы с techId.
    expect(created.every((e) => e.techId != null), isTrue);
    // Жим лёжа привязан к понедельнику (Грудь).
    final bench = exerciseByTech(repo, 'bench');
    expect(bench, isNotNull);
    expect(bench!.weekdays, contains(1));
    // Присед — к пятнице (Ноги).
    expect(exerciseByTech(repo, 'squat')!.weekdays, contains(5));

    // Анкета заполнена.
    final prof = repo.trainerProfile(p.id)!;
    expect(prof.program, 'cbl');
    expect(prof.startDate, '2026-10-14');
    expect(prof.weekdays, {1, 3, 5});
    expect(prof.startWeights, isNotEmpty);
  });

  test('назначение: существующее упражнение подхватывается, не дублируется', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    final mine = repo.addExercise('Мой присед', {2}, techId: 'squat');

    assignProgram(
      repo: repo,
      personId: p.id,
      program: programById('strong_5x5')!,
      weekdays: {1, 3, 5},
      limits: <String>{},
    );

    // Дубля нет: squat ровно один, и дни объединились.
    final squats =
        repo.exercises.where((e) => e.techId == 'squat').toList();
    expect(squats, hasLength(1));
    expect(squats.single.id, mine.id);
    expect(mine.weekdays, containsAll({1, 2, 3, 5}));
  });

  test('назначение: чужие упражнения не трогаются (общий список)', () async {
    final repo = Repository.instance;
    await repo.init();
    final anton = repo.addPerson('Антон');
    final pasha = repo.addPerson('Паша');
    final custom = repo.addExercise('Своё упражнение', {1, 4});

    assignProgram(
      repo: repo,
      personId: pasha.id,
      program: programById('cbl')!,
      weekdays: {1, 3, 5},
      limits: <String>{},
    );

    expect(custom.weekdays, {1, 4});
    // У Антона анкеты нет — программа только у Паши.
    expect(repo.trainerProfile(anton.id), isNull);
    expect(repo.trainerProfile(pasha.id)!.program, 'cbl');
  });

  // ---------- Плановые веса ----------

  test('стартовые веса: из журнала, иначе дефолт, без веса — не включаем', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    final bench = repo.addExercise('Жим лёжа', {1}, techId: 'bench');
    repo.sessionForOrNew(DateTime(2026, 10, 1), bench.id, p.id)
        .sets
        .add(const SetEntry(55, 5));

    final w = suggestStartWeights(
        repo, p.id, programById('strong_5x5')!);
    expect(w['bench'], 55); // из журнала
    expect(w['squat'], 20); // дефолт — пустая штанга
    expect(w.containsKey('plank'), isFalse); // без веса — нет ключа
  });

  test('плановый вес: план главнее журнала (дельоад не откатывается)', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    final bench = repo.addExercise('Жим лёжа', {1}, techId: 'bench');

    final profile = TrainerProfile(program: 'strong_5x5');
    profile.startWeights['bench'] = 50;
    repo.setTrainerProfile(p.id, profile);

    // План 50, журнал пуст → план.
    expect(
        planWeight(
            repo: repo, personId: p.id, profile: profile, techId: 'bench'),
        50);

    // Записали в журнал 55 — план не прыгает сам: растёт только через
    // «Итог тренировки».
    repo.sessionForOrNew(DateTime(2026, 10, 12), bench.id, p.id)
        .sets
        .add(const SetEntry(55, 5));
    expect(
        planWeight(
            repo: repo, personId: p.id, profile: profile, techId: 'bench'),
        50);

    // Дельоад: план 45, в журнале ещё 55 — остаёмся на 45.
    profile.startWeights['bench'] = 45;
    expect(
        planWeight(
            repo: repo, personId: p.id, profile: profile, techId: 'bench'),
        45);

    // Нет ни плана, ни журнала → дефолт.
    expect(
        planWeight(
            repo: repo, personId: p.id, profile: profile, techId: 'squat'),
        20);
  });

  test('1RM для 5/3/1: из журнала по Эпли, без записей — новичковый', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    final bench = repo.addExercise('Жим лёжа', {1}, techId: 'bench');

    // Без записей — базовый новичковый максимум.
    expect(current1RM(repo: repo, personId: p.id, techId: 'bench'), 40);

    // 60 кг × 5 повторов → Эпли ≈ 70.
    repo.sessionForOrNew(DateTime(2026, 10, 12), bench.id, p.id)
        .sets
        .add(const SetEntry(60, 5));
    expect(
        current1RM(repo: repo, personId: p.id, techId: 'bench'),
        closeTo(70, 0.01));
  });

  // ---------- Отчёт по циклу ----------

  test('отчёт по циклу: выполнено из запланированных + рекорды журнала', () async {
    final repo = Repository.instance;
    await repo.init();
    final p = repo.addPerson('Паша');
    final bench = repo.addExercise('Жим лёжа', {1}, techId: 'bench');
    final squat = repo.addExercise('Приседания', {5}, techId: 'squat');

    // До цикла: жим 70 (лучший до).
    repo.sessionForOrNew(DateTime(2026, 10, 7), bench.id, p.id)
        .sets
        .add(const SetEntry(70, 5));

    // Цикл с 14.10: три тренировки, жим вырос до 75, присед без роста.
    for (final day in [14, 16, 19]) {
      repo.sessionForOrNew(DateTime(2026, 10, day), bench.id, p.id)
          .sets
          .add(SetEntry(day == 19 ? 75 : 70, 5));
      repo.sessionForOrNew(DateTime(2026, 10, day), squat.id, p.id)
          .sets
          .add(const SetEntry(90, 5));
    }

    final profile = TrainerProfile(
        program: 'cbl',
        startDate: '2026-10-14',
        weekdays: {1, 3, 5});
    repo.setTrainerProfile(p.id, profile);

    final report = buildCycleReport(
        repo: repo,
        personId: p.id,
        program: programById('cbl')!,
        profile: profile);

    // 3 дня в неделю × 6 недель = 18 запланировано, сделано 3.
    expect(report.planned, 18);
    expect(report.done, 3);
    // Жим 70 → 75 — рекорд; присед одинаковый — не показываем.
    expect(report.records, contains('Жим лёжа: 70 → 75 кг'));
    expect(report.records.any((r) => r.contains('Присед')), isFalse);
  });

  // ---------- Напоминания ----------

  test('напоминания: текст по дню недели из программ участников', () async {
    final repo = Repository.instance;
    await repo.init();
    final pasha = repo.addPerson('Паша');
    final anton = repo.addPerson('Антон');

    // Без программ — в любой день тишина.
    expect(reminderTextForWeekday(repo: repo, weekday: 1), isNull);

    assignProgram(
      repo: repo,
      personId: pasha.id,
      program: programById('cbl')!, // Грудь/Спина/Ноги
      weekdays: {1, 3, 5},
      limits: <String>{},
    );

    // Пн/Ср/Пт — тренировочные дни, текст с именем и упражнениями.
    final mon = reminderTextForWeekday(repo: repo, weekday: 1);
    expect(mon, startsWith('Сегодня по плану'));
    expect(mon, contains('Паша:'));
    // Вт/Чт/Сб/Вс — никто не тренируется.
    expect(reminderTextForWeekday(repo: repo, weekday: 2), isNull);

    // Антон тоже берёт программу — текст объединяет обоих.
    assignProgram(
      repo: repo,
      personId: anton.id,
      program: programById('strong_5x5')!, // A/B на все дни
      weekdays: {1, 3, 5},
      limits: <String>{},
    );
    final both = reminderTextForWeekday(repo: repo, weekday: 1)!;
    expect(both, contains('Паша:'));
    expect(both, contains('Антон:'));
  });

  test('напоминания: разбор времени — мусор не роняет', () {
    expect(Reminders.parseTime('18:00'), (18, 0));
    expect(Reminders.parseTime('7:05'), (7, 5));
    expect(Reminders.parseTime('мусор'), (18, 0));
    expect(Reminders.parseTime('25:99'), (23, 59)); // зажимаем в сутки
  });
}
