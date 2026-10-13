// ---------------------------------------------------------------------------
// Каталог программ офлайн-тренера.
//
// Программы — константы в коде (как справочник техники). Все упражнения
// привязаны к techId из lib/catalog.dart — новые упражнения добавлять не
// нужно. Никакого интернета: подбор — таблица правил (trainer_logic.dart).
//
// Источники идей: Википедия (Full-body workout, Split weight training,
// Starting Strength), stronglifts.com (5×5, прогрессия), 5/3/1 Wendler.
// ---------------------------------------------------------------------------

/// Упражнение внутри плана дня.
class PlanExercise {
  /// Ключ техники из catalog.dart (bench, squat, ...).
  final String techId;

  /// Сколько подходов.
  final int sets;

  /// Целевое число повторов (null — max/планка, вес не растёт по повторам).
  final int? reps;

  /// Как показывать повторы: '5', 'max', '60с'.
  final String label;

  const PlanExercise(this.techId, this.sets, this.reps, this.label);
}

/// Упрощённый конструктор: повторы числом.
PlanExercise pe(String techId, int sets, int reps) =>
    PlanExercise(techId, sets, reps, '$reps');

/// Упражнение «на максимум» (подтягивания, брусья).
PlanExercise peMax(String techId, int sets) =>
    PlanExercise(techId, sets, null, 'max');

/// Упражнение на время (планка).
PlanExercise peTime(String techId, int sets, String label) =>
    PlanExercise(techId, sets, null, label);

/// Один день программы.
class ProgramDay {
  final String title;
  final List<PlanExercise> exercises;
  const ProgramDay(this.title, this.exercises);
}

/// Программа тренировок.
class Program {
  final String id;
  final String name;

  /// 'beginner' | 'intermediate' | 'advanced'.
  final String level;

  /// К каким целям подходит: 'strength', 'shape', 'mass', 'loss'.
  final List<String> goals;

  /// Сколько тренировочных дней в неделю (2, 3, 4, 6).
  final int daysPerWeek;

  /// Длительность цикла в неделях (потом — отчёт и выбор следующего).
  final int cycleWeeks;

  /// Короткое описание для карточки.
  final String description;

  /// Правило прогрессии — текстом для пользователя.
  final String progression;

  /// true — дни чередуются по кругу (A/B/A/B...), false — день №index недели.
  final bool rotateDays;

  /// Техника основных упражнений — для них работает схема 5/3/1 (s531).
  final List<String> mainLifts;

  /// Дни программы (при rotateDays последовательность A/B, иначе по дням недели).
  final List<ProgramDay> days;

  const Program({
    required this.id,
    required this.name,
    required this.level,
    required this.goals,
    required this.daysPerWeek,
    required this.cycleWeeks,
    required this.description,
    required this.progression,
    this.rotateDays = false,
    this.mainLifts = const [],
    required this.days,
  });
}

/// Все программы каталога.
final List<Program> kPrograms = [
  // ---------------------------------------------------------------------
  // Первые шаги — фулл-боди для новичка, чередование A/B.
  // ---------------------------------------------------------------------
  Program(
    id: 'full_beginner',
    name: 'Первые шаги (фулл-боди)',
    level: 'beginner',
    goals: ['strength', 'shape', 'mass'],
    daysPerWeek: 3,
    cycleWeeks: 4,
    description:
        'Классический старт: каждую тренировку — всё тело, три базовых '
        'упражнения. Чередуем дни A и B через тренировку. Подходит, если '
        'только начинаешь или возвращаешься после перерыва.',
    progression:
        'Выполнил все подходы — прибавляем 2,5 кг (ноги — 5 кг) на '
        'следующую тренировку. Не вышло — держим вес.',
    rotateDays: true,
    days: [
      ProgramDay('День A', [
        pe('squat', 3, 8),
        pe('bench', 3, 8),
        pe('row_barbell', 3, 10),
        peTime('plank', 3, '60с'),
        pe('crunch', 3, 15),
      ]),
      ProgramDay('День B', [
        pe('squat', 3, 8),
        pe('ohp', 3, 8),
        pe('pulldown', 3, 10),
        pe('hyperext', 3, 15),
        peTime('plank', 3, '60с'),
      ]),
    ],
  ),

  // ---------------------------------------------------------------------
  // 5×5 Сила — по мотивам stronglifts.com, сила и техника базы.
  // ---------------------------------------------------------------------
  Program(
    id: 'strong_5x5',
    name: '5×5 Сила',
    level: 'beginner',
    goals: ['strength'],
    daysPerWeek: 3,
    cycleWeeks: 6,
    description:
        'Пять подходов по пять повторений в базовых движениях. '
        'Чередуем дни A и B. Самый быстрый способ новичку стать сильнее '
        'в приседе, жиме и тяге.',
    progression:
        'Выполнил все 5×5 — прибавляем 2,5 кг (присед — 5 кг) к следующей '
        'тренировке. Три тренировки подряд не вышло — уменьшаем вес на 10%.',
    rotateDays: true,
    days: [
      ProgramDay('День A', [
        pe('squat', 5, 5),
        pe('bench', 5, 5),
        pe('row_barbell', 5, 5),
      ]),
      ProgramDay('День B', [
        pe('squat', 5, 5),
        pe('ohp', 5, 5),
        pe('deadlift', 1, 5),
      ]),
    ],
  ),

  // ---------------------------------------------------------------------
  // Грудь — Спина — Ноги — текущий формат Паши.
  // ---------------------------------------------------------------------
  Program(
    id: 'cbl',
    name: 'Грудь — Спина — Ноги',
    level: 'intermediate',
    goals: ['mass', 'shape'],
    daysPerWeek: 3,
    cycleWeeks: 6,
    description:
        'Сплит на три дня: каждый день прорабатываем одну крупную группу. '
        'Хорош, когда есть опыт и хочется набрать массу.',
    progression:
        'Прибавляем 2,5 кг в неделю, если все подходы выполнены. '
        'Не вышло — держим вес и повторяем на следующей неделе.',
    days: [
      ProgramDay('Грудь', [
        pe('bench', 4, 8),
        pe('bench_dumbbell', 3, 10),
        pe('fly', 3, 12),
        peMax('dip', 3),
      ]),
      ProgramDay('Спина', [
        pe('row_barbell', 4, 8),
        pe('pulldown', 4, 10),
        pe('row_cable', 3, 12),
        pe('shrug', 3, 15),
        pe('curl_barbell', 3, 12),
      ]),
      ProgramDay('Ноги', [
        pe('squat', 4, 8),
        pe('legpress', 3, 12),
        pe('rdl', 3, 10),
        pe('lunge', 3, 10),
        pe('calf', 4, 15),
        pe('crunch', 3, 15),
      ]),
    ],
  ),

  // ---------------------------------------------------------------------
  // Верх / Низ — четыре дня, сила и объём по очереди.
  // ---------------------------------------------------------------------
  Program(
    id: 'ul',
    name: 'Верх / Низ',
    level: 'intermediate',
    goals: ['strength', 'mass', 'shape'],
    daysPerWeek: 4,
    cycleWeeks: 6,
    description:
        'Четыре дня: верх тела и низ тела, по два раза в неделю. Один день '
        'на силу (тяжело, мало повторов), другой на объём (легче, больше '
        'повторов). Классика для роста и силы сразу.',
    progression:
        'Прибавляем 2,5 кг в неделю, если все подходы выполнены. '
        'Не вышло — держим вес.',
    days: [
      ProgramDay('Верх — сила', [
        pe('bench', 4, 5),
        pe('row_barbell', 4, 5),
        pe('ohp', 3, 8),
        pe('pulldown', 3, 10),
        pe('triceps_push', 3, 12),
        pe('curl_hammer', 3, 12),
      ]),
      ProgramDay('Низ — сила', [
        pe('squat', 4, 5),
        pe('rdl', 3, 8),
        pe('legpress', 3, 12),
        pe('calf', 3, 15),
      ]),
      ProgramDay('Верх — объём', [
        pe('bench_dumbbell', 4, 10),
        pe('fly', 3, 12),
        peMax('pullup', 3),
        pe('row_cable', 3, 12),
        pe('lateral_raise', 3, 15),
        pe('curl_barbell', 3, 12),
      ]),
      ProgramDay('Низ — объём', [
        pe('legpress', 4, 12),
        pe('lunge', 3, 12),
        pe('hyperext', 3, 15),
        pe('calf', 4, 15),
        pe('legraise', 3, 12),
      ]),
    ],
  ),

  // ---------------------------------------------------------------------
  // Push — Pull — Legs — шесть дней, для продвинутых.
  // ---------------------------------------------------------------------
  Program(
    id: 'ppl',
    name: 'Push — Pull — Legs',
    level: 'advanced',
    goals: ['mass', 'strength'],
    daysPerWeek: 6,
    cycleWeeks: 6,
    description:
        'Шесть дней: толкающие, тяговые, ноги — по два круга в неделю. '
        'Максимальный объём для тех, кто готов заниматься почти каждый день.',
    progression:
        'Прибавляем 2,5 кг в неделю, если все подходы выполнены. '
        'Не вышло — держим вес.',
    days: [
      ProgramDay('Push (толкающие)', [
        pe('bench', 4, 8),
        pe('ohp', 4, 10),
        pe('bench_dumbbell', 3, 12),
        peMax('dip', 3),
        pe('lateral_raise', 3, 15),
        pe('triceps_push', 3, 12),
      ]),
      ProgramDay('Pull (тяговые)', [
        peMax('pullup', 4),
        pe('row_barbell', 4, 8),
        pe('pulldown', 3, 12),
        pe('shrug', 3, 15),
        pe('curl_barbell', 3, 12),
        pe('curl_hammer', 3, 12),
      ]),
      ProgramDay('Legs (ноги)', [
        pe('squat', 4, 8),
        pe('rdl', 4, 10),
        pe('legpress', 3, 12),
        pe('lunge', 3, 10),
        pe('calf', 4, 15),
        peTime('plank', 3, '60с'),
        pe('crunch', 3, 15),
      ]),
    ],
  ),

  // ---------------------------------------------------------------------
  // 5/3/1 упрощённый — проценты от 1RM, цикл 4 недели с дельоадом.
  // ---------------------------------------------------------------------
  Program(
    id: 's531',
    name: '5/3/1 упрощённый',
    level: 'intermediate',
    goals: ['strength'],
    daysPerWeek: 4,
    cycleWeeks: 4,
    description:
        'Силовая схема по процентам от твоего максимума (1RM): три недели '
        'тянем вверх, четвёртая — лёгкая (дельоад) для восстановления. '
        'Основные движения: присед, жим лёжа, становая, жим стоя.',
    progression:
        'После полного цикла (4 недели) базовый вес +2,5 кг (верх) или '
        '+5 кг (ноги) — и заново. 1RM считаем из твоих записей в журнале.',
    mainLifts: ['squat', 'bench', 'deadlift', 'ohp'],
    days: [
      ProgramDay('Присед', [
        pe('squat', 3, 5), // схема 5/3/1 задаётся процентами
        pe('rdl', 3, 8),
        pe('legpress', 3, 12),
      ]),
      ProgramDay('Жим лёжа', [
        pe('bench', 3, 5),
        pe('row_barbell', 4, 8),
        pe('triceps_push', 3, 12),
      ]),
      ProgramDay('Становая', [
        pe('deadlift', 3, 5),
        pe('hyperext', 3, 15),
        peTime('plank', 3, '60с'),
      ]),
      ProgramDay('Жим стоя', [
        pe('ohp', 3, 5),
        pe('lateral_raise', 3, 15),
        pe('curl_barbell', 3, 12),
      ]),
    ],
  ),

  // ---------------------------------------------------------------------
  // Круговая — жиросжигание, короткий отдых, много повторов.
  // ---------------------------------------------------------------------
  Program(
    id: 'circuit',
    name: 'Круговая (жиросжигание)',
    level: 'beginner',
    goals: ['loss', 'shape'],
    daysPerWeek: 3,
    cycleWeeks: 4,
    description:
        'Круг упражнений с коротким отдыхом (60 секунд) и большим числом '
        'повторов — держит пульс и тратит больше энергии за тренировку. '
        'Помни: дефицит калорий решает питание, тренировка — только '
        'помощник.',
    progression:
        'Прибавляем 2,5 кг, если все подходы выполнены. '
        'Отдых между упражнениями — 60 секунд, между кругами — 90.',
    days: [
      ProgramDay('Круг', [
        pe('squat', 3, 15),
        pe('bench', 3, 15),
        pe('row_cable', 3, 15),
        pe('lunge', 3, 12),
        pe('lateral_raise', 3, 15),
        peTime('plank', 3, '60с'),
        pe('crunch', 3, 20),
      ]),
    ],
  ),

  // ---------------------------------------------------------------------
  // Занятые люди — два дня, минимальная форма.
  // ---------------------------------------------------------------------
  Program(
    id: 'busy',
    name: 'Занятые люди',
    level: 'beginner',
    goals: ['shape', 'strength', 'mass'],
    daysPerWeek: 2,
    cycleWeeks: 4,
    description:
        'Всего две тренировки в неделю по три подхода — чтобы держать '
        'форму, даже когда совсем нет времени. Всё тело за каждую тренировку.',
    progression:
        'Прибавляем 2,5 кг в неделю, если все подходы выполнены. '
        'Не вышло — держим вес.',
    days: [
      ProgramDay('Всё тело', [
        pe('squat', 3, 8),
        pe('bench', 3, 8),
        pe('row_barbell', 3, 8),
        pe('pulldown', 3, 8),
        pe('rdl', 3, 8),
        pe('ohp', 3, 8),
        peTime('plank', 3, '60с'),
      ]),
    ],
  ),
];

/// Найти программу по id.
Program? programById(String? id) {
  if (id == null) return null;
  for (final p in kPrograms) {
    if (p.id == id) return p;
  }
  return null;
}

/// Все уникальные techId, которые встречаются в программе.
Set<String> programTechIds(Program program) {
  final s = <String>{};
  for (final day in program.days) {
    for (final e in day.exercises) {
      s.add(e.techId);
    }
  }
  return s;
}

/// Шаг прибавки веса (кг) по технике: ноги/спина тяжёлые — 5, остальное 2,5.
double weightStepFor(String techId) {
  const heavy = {'squat', 'deadlift', 'legpress'};
  return heavy.contains(techId) ? 5 : 2.5;
}
