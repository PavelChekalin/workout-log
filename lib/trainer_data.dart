// ---------------------------------------------------------------------------
// Данные офлайн-тренера: анкеты участников, настройки, время тренировок.
//
// Всё живёт в общем JSON приложения (блок "trainer") — экспорт/импорт и
// резервная копия задевают новые данные автоматически. Старые файлы без
// блока "trainer" грузятся как раньше (тренер просто выключен).
// Никакого интернета: логика тренера — правила "если... то..." (trainer_logic).
// ---------------------------------------------------------------------------

/// Анкета участника: ответы на вопросы тренера.
class TrainerProfile {
  int? age;
  int? height;
  int? weight;

  /// 'beginner' (< 6 мес) | 'break' (занимался, перерыв) | 'regular' (> года)
  String exp;

  /// 'strength' (сила) | 'shape' (общая форма) | 'mass' (масса) | 'loss' (сбросить)
  String goal;

  /// Сколько дней в неделю готов заниматься: 2, 3, 4 или 6.
  int days;

  /// Ограничения по здоровью: 'knee' (колено) | 'back' (спина) | 'shoulder' (плечо).
  final Set<String> limits;

  /// Назначенная программа (id из каталога) или null — тренер ещё не выбран.
  String? program;

  /// Дата старта программы 'yyyy-MM-dd' или null.
  String? startDate;

  /// Выбранные дни недели (1..7), в которые тренируемся.
  final Set<int> weekdays;

  /// Стартовые веса: techId -> кг (задаются при назначении программы).
  final Map<String, double> startWeights;

  /// Серия неудач: techId -> сколько тренировок подряд не выполнил план.
  final Map<String, int> fails;

  TrainerProfile({
    this.age,
    this.height,
    this.weight,
    this.exp = 'beginner',
    this.goal = 'shape',
    this.days = 3,
    Set<String>? limits,
    this.program,
    this.startDate,
    Set<int>? weekdays,
    Map<String, double>? startWeights,
    Map<String, int>? fails,
  })  : limits = limits ?? <String>{},
        weekdays = weekdays ?? <int>{},
        startWeights = startWeights ?? <String, double>{},
        fails = fails ?? <String, int>{};

  factory TrainerProfile.fromJson(Map<String, dynamic> j) {
    double asDouble(dynamic v) => v == null ? 0 : (v as num).toDouble();
    return TrainerProfile(
      age: j['age'] as int?,
      height: j['height'] as int?,
      weight: j['weight'] as int?,
      exp: j['exp'] as String? ?? 'beginner',
      goal: j['goal'] as String? ?? 'shape',
      days: j['days'] as int? ?? 3,
      limits: ((j['limits'] as List?) ?? const []).cast<String>().toSet(),
      program: j['program'] as String?,
      startDate: j['startDate'] as String?,
      weekdays: ((j['weekdays'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toSet(),
      startWeights: ((j['startWeights'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), asDouble(v))),
      fails: ((j['fails'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
    );
  }

  Map<String, dynamic> toJson() => {
        if (age != null) 'age': age,
        if (height != null) 'height': height,
        if (weight != null) 'weight': weight,
        'exp': exp,
        'goal': goal,
        'days': days,
        if (limits.isNotEmpty) 'limits': limits.toList(),
        if (program != null) 'program': program,
        if (startDate != null) 'startDate': startDate,
        if (weekdays.isNotEmpty) 'weekdays': weekdays.toList(),
        if (startWeights.isNotEmpty) 'startWeights': startWeights,
        if (fails.isNotEmpty) 'fails': fails,
      };

  /// Анкета пройдена настолько, что тренер может подобрать программу.
  bool get questionnaireDone => age != null && weight != null;
}

/// Тренировка одного дня: начало 'HH:mm', конец — пока идёт, null.
///
/// Тренировку можно завершить и продолжить — каждый «заход» добавляет
/// завершённый отрезок в [done], а общий таймер = сумма отрезков + текущий.
/// Разрыв между завершением и продолжением НЕ считается (честно: на диване
/// не горят калории).
///
/// Фазовые накопители (секунды актив/восстановление/пауза) хранятся здесь же:
/// приложение считает их, пока открыт экран, и сохраняет при завершении.
class WorkoutTime {
  String start;
  String? end;

  /// Завершённые отрезки [['18:32','19:28'], ...].
  final List<List<String>> done;

  /// Секунды по фазам калорий (накоплено за все отрезки).
  int activeSec;
  int restSec;
  int pauseSec;

  /// «На паузе» (решение Паши 14.10): отрезок закончен, но тренировка
  /// не закончена — можно возобновить. Старые записи без поля = false.
  bool paused;

  /// Последняя активность 'HH:mm' (старт, возобновление, подход) —
  /// по ней авто-закрытие считает простой.
  String? lastAct;

  WorkoutTime({
    required this.start,
    this.end,
    List<List<String>>? done,
    this.activeSec = 0,
    this.restSec = 0,
    this.pauseSec = 0,
    this.paused = false,
    this.lastAct,
  }) : done = done ?? <List<String>>[];

  bool get running => end == null;

  factory WorkoutTime.fromJson(Map<String, dynamic> j) => WorkoutTime(
        start: j['start'] as String? ?? '',
        end: j['end'] as String?,
        done: ((j['done'] as List?) ?? const [])
            .map((e) => ((e as List).map((x) => '$x').toList()))
            .toList(),
        activeSec: (j['activeSec'] as num?)?.toInt() ?? 0,
        restSec: (j['restSec'] as num?)?.toInt() ?? 0,
        pauseSec: (j['pauseSec'] as num?)?.toInt() ?? 0,
        paused: j['paused'] as bool? ?? false,
        lastAct: j['lastAct'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'start': start,
        if (end != null) 'end': end,
        if (done.isNotEmpty) 'done': done,
        if (activeSec > 0) 'activeSec': activeSec,
        if (restSec > 0) 'restSec': restSec,
        if (pauseSec > 0) 'pauseSec': pauseSec,
        if (paused) 'paused': true,
        if (lastAct != null) 'lastAct': lastAct,
      };
}
