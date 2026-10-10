import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Модели
// ---------------------------------------------------------------------------

/// Человек: Паша, Антон, Дима и т.д.
class Person {
  final String id;
  String name;
  Person({required this.id, required this.name});

  factory Person.fromJson(Map<String, dynamic> j) =>
      Person(id: j['id'] as String, name: j['name'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Упражнение: название + дни недели (1 = Пн ... 7 = Вс).
/// [techId] — привязка к записи справочника техники (может быть null).
class Exercise {
  final String id;
  String name;
  final Set<int> weekdays;
  String? techId;

  Exercise(
      {required this.id,
      required this.name,
      Set<int>? weekdays,
      this.techId})
      : weekdays = weekdays ?? <int>{};

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: j['name'] as String,
        weekdays: ((j['weekdays'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toSet(),
        techId: j['tech'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'weekdays': weekdays.toList(),
        if (techId != null) 'tech': techId,
      };
}

/// Один подход. weight — вес в кг (может быть null, если упражнение без веса).
class SetEntry {
  final double? weight;
  final int reps;
  const SetEntry(this.weight, this.reps);

  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
        j['w'] == null ? null : (j['w'] as num).toDouble(),
        (j['r'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'w': weight, 'r': reps};
}

/// Запись тренировки: один человек — одно упражнение — одна дата — подходы.
class Session {
  final String date; // 'yyyy-MM-dd'
  final String exerciseId;
  final String personId;
  final List<SetEntry> sets;

  Session({
    required this.date,
    required this.exerciseId,
    required this.personId,
    List<SetEntry>? sets,
  }) : sets = sets ?? <SetEntry>[];

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        date: j['date'] as String,
        exerciseId: j['exerciseId'] as String,
        personId: j['personId'] as String,
        sets: ((j['sets'] as List?) ?? const [])
            .map((e) => SetEntry.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'exerciseId': exerciseId,
        'personId': personId,
        'sets': sets.map((e) => e.toJson()).toList(),
      };
}

// ---------------------------------------------------------------------------
// Формат чисел и дат
// ---------------------------------------------------------------------------

/// Красивый вид числа: 60.0 -> "60", 62.5 -> "62.5".
String fmtNumber(double d) =>
    (d.isFinite && d == d.roundToDouble()) ? d.toInt().toString() : d.toString();

/// Вид подхода: "60×10", а если веса нет — "×12".
String fmtSet(SetEntry s) {
  final w = s.weight == null ? null : fmtNumber(s.weight!);
  return w == null ? '\u00d7${s.reps}' : '$w\u00d7${s.reps}';
}

/// Дата в формате ISO: 'yyyy-MM-dd'.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _uid() {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 31)}';
}

const List<String> _monthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const List<String> _weekdaysFull = [
  'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье',
];

const List<String> weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// "7 октября, среда"
String formatDateRu(DateTime d) =>
    '${d.day} ${_monthsGenitive[d.month - 1]}, ${_weekdaysFull[d.weekday - 1]}';

/// "Пн, 7 октября"
String formatDateShortRu(DateTime d) =>
    '${weekdaysShort[d.weekday - 1]}, ${d.day} ${_monthsGenitive[d.month - 1]}';

/// Название дня недели в именительном падеже: "сегодня пятница".
String weekdayNameRu(int isoDay) => _weekdaysFull[isoDay - 1];

// Винительный падеж — для конструкции "на ..." ("упражнения на пятницу").
const List<String> _weekdaysAcc = [
  'понедельник', 'вторник', 'среду', 'четверг', 'пятницу', 'субботу', 'воскресенье',
];

/// Название дня недели в винительном падеже: "на пятницу".
String weekdayNameRuAcc(int isoDay) => _weekdaysAcc[isoDay - 1];

/// Начало недели (понедельник) для даты.
DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

// ---------------------------------------------------------------------------
// Хранилище — всё в одном JSON внутри приложения, без интернета
// ---------------------------------------------------------------------------

class Repository {
  Repository._();
  static final Repository instance = Repository._();

  static const String _prefsKey = 'workout_log_v1';
  static const String _themeKey = 'workout_theme';
  static const String _restEnabledKey = 'workout_rest_enabled';
  static const String _restSecondsKey = 'workout_rest_seconds';

  /// 'system' | 'light' | 'dark'
  String _themeName = 'dark';
  String get themeName => _themeName;

  /// Показывать ли таймер отдыха между подходами.
  bool _restTimerEnabled = true;
  bool get restTimerEnabled => _restTimerEnabled;

  /// Сколько отдыхать, секунд (по умолчанию 2 минуты).
  int _restSeconds = 120;
  int get restSeconds => _restSeconds;

  final List<Person> people = [];
  final List<Exercise> exercises = [];
  final List<Session> sessions = [];

  /// Заметки к тренировке по датам ('yyyy-MM-dd').
  final Map<String, String> notes = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        _loadFrom(raw);
      } catch (_) {
        // Файл повреждён — не роняем приложение, начнём с пустого
      }
    }
    _themeName = prefs.getString(_themeKey) ?? 'dark';
    _restTimerEnabled = prefs.getBool(_restEnabledKey) ?? true;
    _restSeconds = prefs.getInt(_restSecondsKey) ?? 120;
  }

  Future<void> setThemeName(String value) async {
    _themeName = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, value);
  }

  Future<void> setRestTimerEnabled(bool value) async {
    _restTimerEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_restEnabledKey, value);
  }

  Future<void> setRestSeconds(int seconds) async {
    _restSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_restSecondsKey, seconds);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_toJson()));
  }

  // ---------- Люди ----------

  Person addPerson(String name) {
    final p = Person(id: _uid(), name: name);
    people.add(p);
    save();
    return p;
  }

  void renamePerson(Person p, String name) {
    p.name = name;
    save();
  }

  /// Удаление человека со всеми его записями. Нельзя удалить последнего.
  bool deletePerson(Person p) {
    if (people.length <= 1) return false;
    people.remove(p);
    sessions.removeWhere((s) => s.personId == p.id);
    save();
    return true;
  }

  // ---------- Упражнения ----------

  Exercise addExercise(String name, Set<int> weekdays, {String? techId}) {
    final e = Exercise(
        id: _uid(), name: name, weekdays: {...weekdays}, techId: techId);
    exercises.add(e);
    save();
    return e;
  }

  void updateExercise(Exercise e, String name, Set<int> weekdays,
      {String? techId, bool clearTech = false}) {
    e.name = name;
    e.weekdays
      ..clear()
      ..addAll(weekdays);
    if (clearTech) {
      e.techId = null;
    } else if (techId != null) {
      e.techId = techId;
    }
    save();
  }

  void deleteExercise(Exercise e) {
    exercises.remove(e);
    sessions.removeWhere((s) => s.exerciseId == e.id);
    save();
  }

  // ---------- Записи тренировок ----------

  Session? sessionFor(DateTime date, String exerciseId, String personId) {
    final d = isoDate(date);
    for (final s in sessions) {
      if (s.date == d && s.exerciseId == exerciseId && s.personId == personId) {
        return s;
      }
    }
    return null;
  }

  Session sessionForOrNew(DateTime date, String exerciseId, String personId) {
    final existing = sessionFor(date, exerciseId, personId);
    if (existing != null) return existing;
    final s =
        Session(date: isoDate(date), exerciseId: exerciseId, personId: personId);
    sessions.add(s);
    return s;
  }

  /// Что этот человек делал ровно неделю назад по этому упражнению.
  List<SetEntry>? lastWeekSets(
      DateTime date, String exerciseId, String personId) {
    final target = isoDate(date.subtract(const Duration(days: 7)));
    for (final s in sessions) {
      if (s.date == target &&
          s.exerciseId == exerciseId &&
          s.personId == personId &&
          s.sets.isNotEmpty) {
        return s.sets;
      }
    }
    return null;
  }

  /// Последний подход человека по упражнению (чтобы предзаполнить вес).
  SetEntry? lastSet(String exerciseId, String personId) {
    Session? best;
    for (final s in sessions) {
      if (s.exerciseId == exerciseId &&
          s.personId == personId &&
          s.sets.isNotEmpty) {
        if (best == null || s.date.compareTo(best.date) > 0) best = s;
      }
    }
    if (best == null || best.sets.isEmpty) return null;
    return best.sets.last;
  }

  /// Рекорд за всё время: лучший подход человека по упражнению (вес × повторы).
  SetEntry? personalRecord(String exerciseId, String personId) {
    SetEntry? best;
    var bestScore = -1.0;
    for (final s in sessions) {
      if (s.exerciseId != exerciseId || s.personId != personId) continue;
      for (final e in s.sets) {
        final score = (e.weight ?? 0) * e.reps;
        if (best == null || score > bestScore) {
          best = e;
          bestScore = score;
        }
      }
    }
    return best;
  }

  /// Суммарный объём (тоннаж) подходов: сумма вес × повторы.
  double volume(List<SetEntry> sets) =>
      sets.fold(0.0, (sum, e) => sum + (e.weight ?? 0) * e.reps);

  /// Итог дня для человека: (число подходов, тоннаж в кг).
  (int, double) dayStats(DateTime date, String personId) {
    final d = isoDate(date);
    var setCount = 0;
    var vol = 0.0;
    for (final s in sessions) {
      if (s.date == d && s.personId == personId) {
        setCount += s.sets.length;
        vol += volume(s.sets);
      }
    }
    return (setCount, vol);
  }

  /// Даты, где есть хоть один подход или заметка (для календаря).
  Set<String> recordedDates() {
    final s = <String>{};
    for (final sess in sessions) {
      if (sess.sets.isNotEmpty) s.add(sess.date);
    }
    s.addAll(notes.keys);
    return s;
  }

  /// Подходы самой свежей прошлой тренировки по упражнению (строго раньше даты).
  List<SetEntry>? previousSessionSets(
      DateTime beforeDate, String exerciseId, String personId) {
    final limit = isoDate(beforeDate);
    Session? best;
    for (final s in sessions) {
      if (s.exerciseId != exerciseId ||
          s.personId != personId ||
          s.sets.isEmpty) {
        continue;
      }
      if (s.date.compareTo(limit) >= 0) continue;
      if (best == null || s.date.compareTo(best.date) > 0) best = s;
    }
    return best?.sets;
  }

  // ---------- Заметки к тренировке ----------

  String? noteFor(DateTime date) {
    final n = notes[isoDate(date)];
    return (n == null || n.trim().isEmpty) ? null : n;
  }

  void setNote(DateTime date, String text) {
    final key = isoDate(date);
    final t = text.trim();
    if (t.isEmpty) {
      notes.remove(key);
    } else {
      notes[key] = t;
    }
    save();
  }

  // ---------- Экспорт / импорт ----------

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toJson());

  /// Полностью заменяет данные содержимым JSON. true — успех.
  bool importJson(String raw) {
    try {
      _loadFrom(raw);
      save();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- JSON ----------

  Map<String, dynamic> _toJson() => {
        'people': people.map((e) => e.toJson()).toList(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'notes': notes,
      };

  void _loadFrom(String raw) {
    final root = jsonDecode(raw) as Map<String, dynamic>;
    people.clear();
    exercises.clear();
    sessions.clear();
    notes.clear();
    for (final p in (root['people'] as List? ?? const [])) {
      people.add(Person.fromJson((p as Map).cast<String, dynamic>()));
    }
    for (final e in (root['exercises'] as List? ?? const [])) {
      exercises.add(Exercise.fromJson((e as Map).cast<String, dynamic>()));
    }
    for (final s in (root['sessions'] as List? ?? const [])) {
      sessions.add(Session.fromJson((s as Map).cast<String, dynamic>()));
    }
    final n = root['notes'];
    if (n is Map) {
      n.forEach((k, v) => notes[k.toString()] = v.toString());
    }
  }
}
