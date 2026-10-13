// ---------------------------------------------------------------------------
// Назначение программы участнику: создаём/подхватываем упражнения в журнале,
// привязываем к дням недели, запоминаем программу и стартовые веса.
//
// Упражнения в журнале ОБЩИЕ для всех участников (так устроен журнал), а
// программа — своя у каждого. Поэтому назначение только ДОБАВЛЯЕТ привязки
// дней и не трогает чужие упражнения: сменили программу у Паши — у Антона
// ничего не пропало.
// ---------------------------------------------------------------------------

import 'catalog.dart';
import 'data.dart';
import 'programs.dart';
import 'trainer_data.dart';
import 'trainer_logic.dart';

/// Найти в журнале упражнение с привязкой techId (если несколько — первое).
Exercise? exerciseByTech(Repository repo, String techId) {
  for (final e in repo.exercises) {
    if (e.techId == techId) return e;
  }
  return null;
}

/// Последний записанный вес участника по технике (из журнала). null — записей нет.
double? lastJournalWeight(Repository repo, String personId, String techId) {
  final ex = exerciseByTech(repo, techId);
  if (ex == null) return null;
  return repo.lastSet(ex.id, personId)?.weight;
}

/// Стартовые веса для программы: подсказка из журнала, иначе дефолт
/// (штанга/гантели), иначе null — упражнение без веса.
Map<String, double> suggestStartWeights(
    Repository repo, String personId, Program program) {
  final result = <String, double>{};
  for (final techId in programTechIds(program)) {
    final fromJournal = lastJournalWeight(repo, personId, techId);
    if (fromJournal != null) {
      result[techId] = fromJournal;
      continue;
    }
    final def = defaultStartWeight(techId);
    if (def != null) result[techId] = def;
  }
  return result;
}

/// Текущий плановый вес по технике.
///
/// План живёт в профиле (startWeights как «текущий плановый вес»): растёт по
/// «Итогу тренировки», после 3 неудач падает на 10%. План главнее журнала —
/// иначе дельоад (−10%) сразу откатился бы назад от старых записей. Если
/// плана нет — берём журнал, иначе дефолт. Фактические записи остаются в
/// журнале, их видно рядом с планом.
double? planWeight({
  required Repository repo,
  required String personId,
  required TrainerProfile profile,
  required String techId,
}) {
  final plan = profile.startWeights[techId];
  if (plan != null) return plan;
  return lastJournalWeight(repo, personId, techId) ??
      defaultStartWeight(techId);
}

/// Назначить программу: создаёт недостающие упражнения, добавляет привязки
/// дней, заполняет анкету (программа/старт/дни/веса).
///
/// Возвращает список созданных упражнений (для «Создано N упражнений»).
List<Exercise> assignProgram({
  required Repository repo,
  required String personId,
  required Program program,
  required Set<int> weekdays,
  required Set<String> limits,
  Map<String, double>? startWeights,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final binding = planByWeekday(
      program: program, weekdays: weekdays, limits: limits);

  // 1. Подхватить или создать упражнение по технике.
  Exercise ensureExercise(String techId) {
    final existing = exerciseByTech(repo, techId);
    if (existing != null) return existing;
    final name = techById(techId)?.name ?? techId;
    return repo.addExercise(name, {}, techId: techId);
  }

  final created = <Exercise>[];
  for (final entry in binding.entries) {
    for (final planEx in entry.value) {
      final isNew = exerciseByTech(repo, planEx.techId) == null;
      final ex = ensureExercise(planEx.techId);
      if (isNew) created.add(ex);
      ex.weekdays.add(entry.key);
    }
  }
  repo.save();

  // 2. Заполнить анкету.
  final profile = repo.trainerProfiles[personId] ?? TrainerProfile();
  profile.program = program.id;
  profile.startDate = isoDate(now);
  profile.weekdays
    ..clear()
    ..addAll(weekdays);
  profile.limits.addAll(limits.difference(profile.limits));
  profile.startWeights
    ..clear()
    ..addAll(startWeights ??
        suggestStartWeights(repo, personId, program));
  profile.fails.clear();
  repo.setTrainerProfile(personId, profile);

  return created;
}

/// Расчёт 1RM (Эпли) для основных движений 5/3/1 — из журнала участника.
/// Если записей нет — базовый «новичковый» максимум.
double current1RM({
  required Repository repo,
  required String personId,
  required String techId,
}) {
  final journal = lastJournalWeight(repo, personId, techId);
  if (journal != null) {
    // Берём последний подход: 5 повторов — типичный максимум в плане.
    final ex = exerciseByTech(repo, techId);
    final last = ex == null ? null : repo.lastSet(ex.id, personId);
    final reps = last == null || last.reps <= 0 ? 5 : last.reps;
    return epley1RM(journal, reps);
  }
  const beginner1RM = <String, double>{
    'squat': 60,
    'bench': 40,
    'deadlift': 80,
    'ohp': 30,
  };
  return beginner1RM[techId] ?? 40;
}

/// Итоги цикла участника из журнала (§8): выполненные тренировки и рекорды.
CycleReport buildCycleReport({
  required Repository repo,
  required String personId,
  required Program program,
  required TrainerProfile profile,
}) {
  final startDate = profile.startDate ?? '';
  final techs = programTechIds(program);
  final techByExercise = <String, String?>{
    for (final e in repo.exercises) e.id: e.techId,
  };

  final dates = <String>{};
  final bestBefore = <String, double>{};
  final bestDuring = <String, double>{};

  for (final s in repo.sessions) {
    if (s.personId != personId || s.sets.isEmpty) continue;
    final tech = techByExercise[s.exerciseId];
    if (tech == null || !techs.contains(tech)) continue;
    var weight = 0.0;
    for (final set in s.sets) {
      final w = set.weight ?? 0;
      if (w > weight) weight = w.toDouble();
    }
    if (startDate.isNotEmpty && s.date.compareTo(startDate) >= 0) {
      dates.add(s.date);
      if (weight > (bestDuring[tech] ?? 0)) bestDuring[tech] = weight;
    } else if (weight > (bestBefore[tech] ?? 0)) {
      bestBefore[tech] = weight;
    }
  }

  return CycleReport(
    planned: profile.weekdays.length * program.cycleWeeks,
    done: dates.length,
    records: recordLines(
      bestBefore: bestBefore,
      bestDuring: bestDuring,
      nameOf: (id) => techById(id)?.name ?? id,
    ),
  );
}
