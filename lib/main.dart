import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'calendar_picker.dart';
import 'coach_lines.dart';
import 'data.dart';
import 'health.dart';
import 'kcal.dart';
import 'onboarding_screen.dart';
import 'programs.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'trainer_apply.dart';
import 'trainer_logic.dart';
import 'trainer_screen.dart';
import 'ui.dart';
import 'video_bridge.dart';
import 'workout_panel.dart';
import 'reminders.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = Repository.instance;
  await repo.init();
  appThemeMode.value = themeModeFromName(repo.themeName);
  runApp(const WorkoutLogApp());
  // Расписание напоминаний пересчитываем при каждом старте — так оно
  // переживает перезагрузку телефона и смену программ участников.
  if (repo.remindersOn) {
    final (h, m) = Reminders.parseTime(repo.remindersTime);
    Reminders.reschedule(repo, enabled: true, hour: h, minute: m);
  }
}

class WorkoutLogApp extends StatelessWidget {
  const WorkoutLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (_, mode, _) => MaterialApp(
        title: 'Журнал тренировок',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: mode,
        home: const MainScreen(),
      ),
    );
  }
}

/// Главный экран: дата сверху, строка участников с «+», ниже — упражнения
/// этого дня недели и строки по каждому участнику.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final repo = Repository.instance;
  DateTime selectedDate = DateTime.now();

  /// Отсчёт отдыха: конец в DateTime, пока тикает — показываем плашку.
  DateTime? _restEndsAt;
  Timer? _restTicker;

  /// Тикер активной тренировки: секунда в секунду крутится, пока тенировка
  /// идёт (таймер панели + накопители фаз для калорий).
  Timer? _workoutTicker;

  /// Когда последний раз записывали подход (для фаз калорий).
  DateTime? _lastSetAt;

  /// Кто выбран в панели тренировки (для плана и калорий).
  String? _panelPersonId;

  /// Шаги и пульс за сегодня (данные владельца, Health Connect).
  TodayHealth _todayHealth = const TodayHealth();

  /// Показанные фразы тренера (гард «не заиграться»: одно событие — одна фраза
  /// на время жизни экрана).
  final Set<String> _shownCoachLines = <String>{};

  /// Фраза по событию, но не чаще раза (пока открыт экран).
  String? _coachLineOnce(String event) {
    if (!_shownCoachLines.add(event)) return null;
    return coachLine(repo.trainerTone, event);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Висящие «идущие» тренировки (в т.ч. прошлых дней) закрыть молча.
    repo.closeIdleWorkouts(DateTime.now());
    _ensureWorkoutTicker();
    _loadTodayHealth();
    // Первый запуск (в том числе после обновления приложения) — онбординг.
    if (!repo.trainerOnboarded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const OnboardingScreen()))
            .then((_) {
          if (mounted) setState(() {});
        });
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись в приложение (например, из окна разрешений часов) —
    // перечитать шаги/пульс.
    if (state == AppLifecycleState.resumed) _loadTodayHealth();
  }

  void _refresh() {
    if (!repo.restTimerEnabled && _restEndsAt != null) _stopRest();
    setState(() {});
  }

  /// Прочитать шаги/пульс за сегодня (вызывается при открытии экрана и
  /// после настроек, где могут выдать доступ).
  Future<void> _loadTodayHealth() async {
    final h = await HealthBridge.load();
    if (!mounted) return;
    setState(() => _todayHealth = h);
  }

  Future<void> _requestHealthAccess() async {
    final ok = await HealthBridge.requestAccess();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Нет доступа к данным Health Connect. Сейчас '
              'откроется Health Connect — разреши там: Приложения → '
              'Журнал тренировок → Шаги и Пульс.')));
    }
    await _loadTodayHealth();
  }

  /// Строка «шаги и пульс за сегодня» — одна строка сверху на экране
  /// «Сегодня» (решение Паши 14.10: без дублей в карточках упражнений).
  Widget _healthLine() {
    final h = _todayHealth;
    if (!h.sdkReady) return const SizedBox.shrink();
    final owner = repo.healthProfile;
    final String text;
    if (!h.granted) {
      text = 'Часы и браслеты: нет доступа к данным Health Connect';
    } else {
      final parts = <String>[
        if (owner != null) owner.name,
        if (h.pulseBpm != null) '♥ ${h.pulseBpm} уд/мин',
        if (h.steps != null) '${h.steps} шагов',
      ];
      text = parts.isEmpty
          ? 'Часы пока не прислали данные за сегодня'
          : parts.join(' · ');
    }
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: h.granted ? _loadTodayHealth : _requestHealthAccess,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        child: Row(
          children: [
            Icon(
                h.granted
                    ? Icons.monitor_heart_outlined
                    : Icons.watch_later_outlined,
                size: 14,
                color: cs.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12.5, color: cs.outline)),
            ),
            if (!h.granted)
              Text('Дать доступ',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restTicker?.cancel();
    _workoutTicker?.cancel();
    TimerSignals.keepScreenOn(false);
    // Фазовые накопители могли копиться без сохранения — сохраним.
    if (repo.workoutOn(DateTime.now())?.running ?? false) repo.save();
    super.dispose();
  }

  /// Сколько секунд отдыха осталось (0 — время вышло).
  int get _restLeft {
    final end = _restEndsAt;
    if (end == null) return 0;
    final left = end.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  /// Начать (и перезапустить) отдых после записанного подхода.
  void _startRest() {
    if (!repo.restTimerEnabled) return;
    _restEndsAt = DateTime.now().add(Duration(seconds: repo.restSeconds));
    _restTicker?.cancel();
    _restTicker = Timer.periodic(const Duration(seconds: 1), (_) => _onRestTick());
    TimerSignals.keepScreenOn(true);
    if (mounted) setState(() {});
  }

  void _onRestTick() {
    if (_restEndsAt == null) return;
    if (_restLeft <= 0) {
      _restTicker?.cancel();
      _restTicker = null;
      _restEndsAt = null;
      TimerSignals.keepScreenOn(false);
      TimerSignals.notifyEnd();
      if (mounted) setState(() {});
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Стоп: просто убрать отсчёт без оповещения.
  void _stopRest() {
    _restTicker?.cancel();
    _restTicker = null;
    _restEndsAt = null;
    TimerSignals.keepScreenOn(false);
    if (mounted) setState(() {});
  }

  /// «+30 сек» — продлить отдых.
  void _restPlus(int seconds) {
    final end = _restEndsAt;
    if (end == null) return;
    _restEndsAt = end.add(Duration(seconds: seconds));
    if (mounted) setState(() {});
  }

  // ---------- Активная тренировка ----------

  /// Запустить тикер, если тренировка сегодня идёт (например, открыли приложение).
  void _ensureWorkoutTicker() {
    final running = repo.workoutOn(DateTime.now())?.running ?? false;
    if (running && _workoutTicker == null) {
      _workoutTicker =
          Timer.periodic(const Duration(seconds: 1), (_) => _onWorkoutTick());
    } else if (!running && _workoutTicker != null) {
      _workoutTicker?.cancel();
      _workoutTicker = null;
    }
  }

  void _onWorkoutTick() {
    if (!mounted) return;
    // Авто-закрытие (решение Паши 14.10): 2 часа без подходов — конец.
    if (repo.closeIdleWorkouts(DateTime.now())) {
      _workoutTicker?.cancel();
      _workoutTicker = null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Тренировка закрыта сама: 2 часа без подходов'),
          duration: Duration(seconds: 4)));
      setState(() {});
      return;
    }
    final w = repo.workoutOn(DateTime.now());
    if (w == null || !w.running) {
      _workoutTicker?.cancel();
      _workoutTicker = null;
      setState(() {});
      return;
    }
    // Фаза по времени с последнего подхода и состоянию отдых-таймера.
    final since = _lastSetAt == null
        ? 999999
        : DateTime.now().difference(_lastSetAt!).inSeconds;
    final met = metForPhase(
        sinceLastSetSec: since, restRunning: _restEndsAt != null);
    if (met >= 6) {
      w.activeSec++;
    } else if (met >= 4) {
      w.restSec++;
    } else {
      w.pauseSec++;
    }
    setState(() {});
  }

  /// Фраза-напутствие: одна на тренировку (выбирается при старте).
  String? _startLine;

  void _startWorkout() {
    repo.startWorkout(DateTime.now());
    _lastSetAt = null; // до первого подхода — пауза, так честнее
    _ensureWorkoutTicker();
    _startLine = coachLine(repo.trainerTone, CoachEvent.start);
    if (_startLine != null) {
      // Фраза тренера — жёлтая жирная (правка Паши 14.10).
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: coachLineText(context, _startLine),
          duration: const Duration(seconds: 2)));
    }
    setState(() {});
  }

  /// Пауза (кнопка «Пауза»): отрезок закрывается, время сохраняется.
  void _pauseWorkout() {
    repo.pauseWorkout(DateTime.now());
    _ensureWorkoutTicker();
    setState(() {});
  }

  /// Возобновление: новый отрезок; до первого подхода — пауза по фазам.
  void _resumeWorkout() {
    repo.startWorkout(DateTime.now());
    _lastSetAt = null;
    _ensureWorkoutTicker();
    setState(() {});
  }

  /// Завершение: переспросить, показать итог.
  Future<void> _endWorkoutDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Закончить тренировку?'),
        content: const Text('Время и калории зафиксируем.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ещё нет')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Закончить')),
        ],
      ),
    );
    if (confirm != true) return;
    final w = repo.workoutOn(DateTime.now());
    if (w == null) return;
    final elapsed =
        workoutElapsedSec(done: w.done, start: w.start, end: w.end, now: DateTime.now());
    final kcalByPerson = <Person, double?>{};
    for (final p in repo.people) {
      final weight = repo.trainerProfile(p.id)?.weight;
      kcalByPerson[p] = weight == null
          ? null
          : kcalFromPhases(
              activeSec: w.activeSec,
              restSec: w.restSec,
              pauseSec: w.pauseSec,
              weightKg: weight.toDouble());
    }
    repo.endWorkout(DateTime.now());
    _workoutTicker?.cancel();
    _workoutTicker = null;
    if (mounted) setState(() {});
    if (!mounted) return;
    // Отрезки для итога: завершённые + текущий (endWorkout уже проставил end).
    final segments = <List<String>>[
      ...w.done,
      if (w.end != null) [w.start, w.end!],
    ];
    // Фраза по итогу: весь план дня записан — «план выполнен», иначе «частично».
    String? endLine;
    for (final p in repo.people) {
      final planDay = _todayPlanDayFor(p);
      if (planDay == null) continue;
      var allDone = true;
      for (final e in planDay.exercises) {
        final ex = exerciseByTech(repo, e.techId);
        final s =
            ex == null ? null : repo.sessionFor(DateTime.now(), ex.id, p.id);
        if (s == null || s.sets.isEmpty) {
          allDone = false;
          break;
        }
      }
      endLine = coachLine(
          repo.trainerTone,
          allDone ? CoachEvent.planDone : CoachEvent.planPartial);
      break;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _WorkoutSummaryDialog(
          elapsedSec: elapsed,
          kcalByPerson: kcalByPerson,
          segments: segments,
          line: endLine),
    );
  }

  /// План дня участника (null — анкеты или программы нет).
  ProgramDay? _todayPlanDayFor(Person p) {
    final profile = repo.trainerProfile(p.id);
    final program = profile == null ? null : programById(profile.program);
    if (profile == null ||
        program == null ||
        profile.startDate == null ||
        profile.weekdays.isEmpty) {
      return null;
    }
    final sessionDates = repo.sessions
        .where((s) => s.personId == p.id && s.sets.isNotEmpty)
        .map((s) => s.date)
        .toSet();
    final doneCount = completedSessionsSince(
        startDate: profile.startDate!, recordedDates: sessionDates);
    return todayPlanDay(
        program: program,
        weekdays: profile.weekdays,
        today: DateTime.now(),
        completedSessions: doneCount);
  }

  /// Строка плана для панели: следующее упражнение или итог дня.
  String _planTextFor(Person p) {
    final profile = repo.trainerProfile(p.id);
    final program =
        profile == null ? null : programById(profile.program);
    if (profile == null ||
        program == null ||
        profile.startDate == null ||
        profile.weekdays.isEmpty) {
      return 'План появится после анкеты и программы — веди журнал как обычно.';
    }
    final today = DateTime.now();
    final sessionDates = repo.sessions
        .where((s) => s.personId == p.id && s.sets.isNotEmpty)
        .map((s) => s.date)
        .toSet();
    final doneCount = completedSessionsSince(
        startDate: profile.startDate!, recordedDates: sessionDates);
    final planDay = todayPlanDay(
        program: program,
        weekdays: profile.weekdays,
        today: today,
        completedSessions: doneCount);

    var done = 0;
    String? next;
    for (final e in planDay.exercises) {
      final ex = exerciseByTech(repo, e.techId);
      final s =
          ex == null ? null : repo.sessionFor(today, ex.id, p.id);
      if (s != null && s.sets.isNotEmpty) {
        done++;
        continue;
      }
      next ??= () {
        final name = techById(e.techId)?.name ?? e.techId;
        final w = profile.startWeights[e.techId];
        final weight = w == null ? 'свой вес' : '${fmtKg(w)} кг';
        final recorded = s == null ? 0 : s.sets.length;
        return '$name — ${e.sets}×${e.label} @ $weight '
            '(записано $recorded из ${e.sets})';
      }();
    }
    if (next == null) {
      return 'Весь план на сегодня выполнен! ($done из ${planDay.exercises.length})';
    }
    return 'Дальше по плану: $next · выполнено $done из ${planDay.exercises.length}';
  }

  int _setsTodayFor(Person p) {
    final today = isoDate(DateTime.now());
    var n = 0;
    for (final s in repo.sessions) {
      if (s.date == today && s.personId == p.id) n += s.sets.length;
    }
    return n;
  }

  ColorScheme get _cs => Theme.of(context).colorScheme;

  @override
  Widget build(BuildContext context) {
    final dayExercises = repo.exercises
        .where((e) => e.weekdays.contains(selectedDate.weekday))
        .toList();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Журнал тренировок'),
        actions: [
          IconButton(
            tooltip: 'Тренер',
            icon: const Icon(Icons.fitness_center),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TrainerScreen()));
              _refresh();
            },
          ),
          IconButton(
            tooltip: 'Статистика',
            icon: const Icon(Icons.insights),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StatsScreen()));
              _refresh();
            },
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _refresh();
              _loadTodayHealth();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editExercise(null),
        icon: const Icon(Icons.add),
        label: const Text('Упражнение'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _dateBar(),
              if (_selectedDateIsToday) ...[
                _healthLine(),
                _workoutSection(),
              ],
              _daySummary(),
              const Divider(height: 1),
              Expanded(
                child: repo.people.isEmpty
                    ? _noParticipants()
                    : dayExercises.isEmpty
                        ? _emptyExercises()
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 96),
                            itemCount: dayExercises.length,
                            itemBuilder: (_, i) =>
                                _exerciseCard(dayExercises[i]),
                          ),
              ),
            ],
          ),
          if (_restEndsAt != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 84,
              child: _restBar(),
            ),
        ],
      ),
    );
  }

  bool get _selectedDateIsToday =>
      isoDate(selectedDate) == isoDate(DateTime.now());

  /// Кнопка «Начать/Продолжить тренировку» или панель идущей тренировки.
  Widget _workoutSection() {
    final now = DateTime.now();
    final w = repo.workoutOn(now);
    final active = w != null && (w.running || w.paused);
    if (!active) {
      // Слово «Продолжить» убрано (правка Паши 14.10): любая новая
      // тренировка начинается кнопкой «Начать».
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _startWorkout,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Начать тренировку'),
          ),
        ),
      );
    }

    // Участники с известным весом — им тренер считает калории.
    final people = repo.people
        .where((p) => (repo.trainerProfile(p.id)?.weight ?? 0) > 0)
        .toList();
    final selectedId = () {
      final cur = _panelPersonId;
      if (cur != null && people.any((p) => p.id == cur)) return cur;
      return people.isNotEmpty ? people.first.id : null;
    }();
    final selected = selectedId == null
        ? null
        : repo.people.firstWhere((p) => p.id == selectedId);
    final weight =
        selected == null ? null : repo.trainerProfile(selected.id)?.weight;

    return WorkoutPanel(
      elapsedSec: workoutElapsedSec(
          done: w.done, start: w.start, end: w.end, now: now),
      // Наглядность времени (правка 14.10): когда начался текущий заход,
      // сколько заходов было до этого, с какого времени на паузе.
      timeText: 'С ${w.start}'
          '${w.done.isEmpty ? '' : ' · заходов сегодня: ${w.done.length + 1}'}'
          '${w.paused && w.end != null ? ' · на паузе с ${w.end}' : ''}',
      kcal: weight == null
          ? null
          : kcalFromPhases(
              activeSec: w.activeSec,
              restSec: w.restSec,
              pauseSec: w.pauseSec,
              weightKg: weight.toDouble()),
      weightKnown: weight != null,
      people: people,
      selectedPersonId: selectedId ?? '',
      onSelectPerson: (id) => setState(() => _panelPersonId = id),
      planText: selected == null
          ? 'Веди журнал как обычно.'
          : _planTextFor(selected),
      setsCount: selected == null ? 0 : _setsTodayFor(selected),
      trainerLine: _startLine ?? '',
      paused: w.paused,
      onPause: _pauseWorkout,
      onResume: _resumeWorkout,
      onEnd: _endWorkoutDialog,
    );
  }

  /// Плашка обратного отсчёта: висит поверх списка, не мешая записи подходов.
  Widget _restBar() {
    final left = _restLeft;
    final m = left ~/ 60;
    final s = left % 60;
    return Material(
      color: _cs.primaryContainer,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, color: _cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Отдых $m:${s.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _cs.onPrimaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _restPlus(30),
              child: const Text('+30 сек'),
            ),
            IconButton(
              tooltip: 'Стоп',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, color: _cs.onPrimaryContainer),
              onPressed: _stopRest,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Календарь',
            icon: const Icon(Icons.calendar_month),
            onPressed: _openCalendar,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  formatDateRu(selectedDate),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  'упражнения на ${weekdayNameRuAcc(selectedDate.weekday)}',
                  style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Следующий день',
            onPressed: () {
              final next = DateTime(selectedDate.year, selectedDate.month,
                  selectedDate.day + 1);
              final today = DateTime.now();
              final todayOnly = DateTime(today.year, today.month, today.day);
              if (!next.isAfter(todayOnly)) {
                setState(() => selectedDate = next);
              }
            },
          ),
          TextButton(
            onPressed: () => setState(() => selectedDate = DateTime.now()),
            child: const Text('Сегодня'),
          ),
        ],
      ),
    );
  }

  /// Открыть календарь и перейти к выбранному дню.
  Future<void> _openCalendar() async {
    final picked = await showDayCalendar(
      context,
      marked: repo.recordedDates(),
      initial: selectedDate,
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  /// Итог дня (подходы + тоннаж) и заметка к тренировке.
  Widget _daySummary() {
    final note = repo.noteFor(selectedDate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_outlined,
                  size: 16, color: _cs.onSurfaceVariant),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Итог дня', style: TextStyle(fontSize: 13)),
              ),
              TextButton.icon(
                onPressed: _editNote,
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(note == null ? 'Заметка' : 'Заметка ✓'),
              ),
            ],
          ),
          for (final p in repo.people) _personDayRow(p),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 22, right: 8, bottom: 2),
              child: Text(
                note,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: _cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Итог дня одного участника: подходы · тоннаж.
  Widget _personDayRow(Person person) {
    final (setCount, vol) = repo.dayStats(selectedDate, person.id);
    return Padding(
      padding: const EdgeInsets.only(left: 22, bottom: 2),
      child: Row(
        children: [
          personAvatar(person, radius: 9),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              setCount == 0
                  ? '${person.name}: —'
                  : '${person.name}: $setCount подх. · ${grouped(vol)} кг',
              style: TextStyle(color: _cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNote() async {
    final controller =
        TextEditingController(text: repo.noteFor(selectedDate) ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Заметка к тренировке'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Например: много повторений, вес уменьшил',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (text == null) return;
    repo.setNote(selectedDate, text);
    setState(() {});
  }

  Widget _noParticipants() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 56, color: _cs.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('Пока нет участников',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Добавьте тех, кто тренируется, '
              'чтобы на экране появились строки для ввода подходов.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addPerson,
              icon: const Icon(Icons.person_add),
              label: const Text('Добавить участника'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyExercises() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center, size: 56, color: _cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'На ${weekdayNameRuAcc(selectedDate.weekday)} упражнений нет',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите «Упражнение» внизу и отметьте, в какие дни недели оно делается.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exerciseCard(Exercise exercise) {
    return Card(
      color: _cs.surfaceContainerHigh,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Видео',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.videocam_outlined, size: 20, color: _cs.primary),
                  onPressed: () => _addVideo(exercise),
                ),
                if (exercise.techId != null)
                  IconButton(
                    tooltip: 'Техника',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.menu_book, size: 20, color: _cs.primary),
                    onPressed: () => _showTech(exercise),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    switch (v) {
                      case 'stats':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StatsScreen(initialExerciseId: exercise.id),
                          ),
                        ).then((_) => _refresh());
                        break;
                      case 'edit':
                        _editExercise(exercise);
                        break;
                      case 'tech':
                        _showTech(exercise);
                        break;
                      case 'delete':
                        _confirmDeleteExercise(exercise);
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'stats', child: Text('Статистика')),
                    PopupMenuItem(value: 'tech', child: Text('Техника')),
                    PopupMenuItem(value: 'edit', child: Text('Изменить')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ],
            ),
            ...repo.people.map((p) => _personRow(exercise, p)),
            ..._videoRows(exercise),
          ],
        ),
      ),
    );
  }

  Widget _personRow(Exercise exercise, Person person) {
    final session = repo.sessionFor(selectedDate, exercise.id, person.id);
    final sets = session?.sets ?? const <SetEntry>[];
    final setsText = sets.map((s) => fmtSet(s)).join('   ');
    final lastWeek = repo.lastWeekSets(selectedDate, exercise.id, person.id);
    final color = personColor(person.id);

    return InkWell(
      onTap: () => _openSets(exercise, person),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            personAvatar(person, radius: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (setsText.isNotEmpty)
                    Text(setsText,
                        style: const TextStyle(fontSize: 14, height: 1.3))
                  else if (lastWeek != null)
                    Text(
                      'неделю назад: '
                      '${lastWeek.map((s) => fmtSet(s)).join(', ')}',
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Записать подходы',
              onPressed: () => _openSets(exercise, person),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Видео ----------

  /// Предложить выбрать: записать видео сейчас или взять уже записанное
  /// на телефоне. Оба варианта дают путь к файлу — дальше всё одинаково.
  Future<void> _addVideo(Exercise exercise) async {
    final how = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Видео к упражнению',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Записать видео'),
              subtitle: const Text('Откроется камера телефона'),
              onTap: () => Navigator.pop(context, 'record'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Взять готовое видео'),
              subtitle: const Text('Выбрать из памяти телефона'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (how == null || !mounted) return;

    String? path;
    try {
      path = how == 'record'
          ? await VideoBridge.record(toGallery: repo.videoStorage == 'gallery')
          : await VideoBridge.pick();
    } on VideoException catch (e) {
      _videoError(e.message);
      return;
    }
    if (path == null || path.isEmpty) return; // отменили
    repo.addVideo(selectedDate, exercise.id, path);
    if (mounted) setState(() {});
  }

  List<Widget> _videoRows(Exercise exercise) {
    final items = repo.videosFor(selectedDate, exercise.id);
    if (items.isEmpty) return const [];
    return [
      const Divider(height: 1),
      for (final v in items)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _playVideo(v),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.play_circle_outline,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _videoLabel(v),
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Поделиться',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.share, size: 18),
                  onPressed: () => _shareVideo(v),
                ),
                IconButton(
                  tooltip: 'Убрать из журнала',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _confirmDeleteVideo(v),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  String _videoLabel(VideoNote v) {
    final t = DateTime.fromMillisecondsSinceEpoch(v.createdAt);
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final where = v.path.startsWith('content://') ? 'Галерея' : 'память телефона';
    return 'Видео · $hm · $where';
  }

  Future<void> _playVideo(VideoNote v) async {
    try {
      await VideoBridge.open(v.path);
    } on VideoException catch (e) {
      _videoError(e.message);
    }
  }

  Future<void> _shareVideo(VideoNote v) async {
    try {
      await VideoBridge.share(v.path);
    } on VideoException catch (e) {
      _videoError(e.message);
    }
  }

  void _confirmDeleteVideo(VideoNote v) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Убрать видео?'),
        content: const Text(
            'Запись исчезнет из журнала. Сам файл видео при этом может '
            'остаться на телефоне.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await VideoBridge.delete(v.path);
              repo.removeVideo(v);
              if (mounted) setState(() {});
            },
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
  }

  void _videoError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Диалоги ----------

  Future<String?> _askName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Имя'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPerson() async {
    if (!repo.canAddPerson) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Лимит ${Repository.maxPeople} участников')));
      return;
    }
    final name = await _askName('Новый участник', '');
    if (name == null || name.isEmpty) return;
    repo.addPerson(name);
    setState(() {});
  }

  Future<void> _openSets(Exercise exercise, Person person) async {
    final recordBefore = repo.personalRecord(exercise.id, person.id);
    await showDialog<void>(
      context: context,
      builder: (_) => _SetsDialog(
        exercise: exercise,
        person: person,
        date: selectedDate,
        onSetAdded: () {
          // Записанный подход — старт фазы «актив» для калорий.
          _lastSetAt = DateTime.now();
          _startRest();
        },
      ),
    );
    // Новый рекорд? Сравним лучший вес до и после записи.
    final recordAfter = repo.personalRecord(exercise.id, person.id);
    final beat = recordAfter != null &&
        recordAfter.weight != null &&
        (recordBefore == null ||
            recordBefore.weight == null ||
            recordAfter.weight! > recordBefore.weight!);
    if (beat) {
      final line = _coachLineOnce(CoachEvent.record);
      if (line != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$line (${fmtKg(recordAfter.weight!)} кг)')));
      }
    }
    setState(() {});
  }

  Future<void> _editExercise(Exercise? exercise) async {
    final res = await showDialog<(String, Set<int>, String?, bool)>(
      context: context,
      builder: (_) => _ExerciseDialog(
        exercise: exercise,
        defaultDay: selectedDate.weekday,
      ),
    );
    if (res == null) return;
    final (name, days, techId, clearTech) = res;
    if (exercise == null) {
      repo.addExercise(name, days, techId: techId);
    } else {
      repo.updateExercise(exercise, name, days,
          techId: techId, clearTech: clearTech);
    }
    setState(() {});
  }

  /// Показывает технику упражнения (или предлагает подобрать, если не задана).
  /// Шторка (правка 14.10) вытягивается до середины экрана, прокручивается
  /// и имеет запас снизу — текст не уходит под нарисованные кнопки
  /// управления телефона.
  Future<void> _showTech(Exercise exercise) async {
    final tech = techById(exercise.techId);
    // Запас снизу: системная навигация + кнопки, которые телефон рисует
    // поверх приложения.
    final bottomPad = 28.0 + MediaQuery.of(context).viewPadding.bottom + 48;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.4,
        minChildSize: 0.25,
        maxChildSize: 0.5, // середина экрана — выше не нужно
        builder: (_, sheetCtrl) => ListView(
          controller: sheetCtrl,
          padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPad),
          children: tech == null
              ? [
                  const Text('Техника не выбрана',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Можно подобрать технику при изменении упражнения '
                      '(меню → Изменить).'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editExercise(exercise);
                    },
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Подобрать технику'),
                  ),
                ]
              : [
                  Text(tech.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.fitness_center,
                          size: 15, color: _cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(tech.muscles,
                            style: TextStyle(
                                color: _cs.onSurfaceVariant, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(tech.technique, style: const TextStyle(height: 1.4)),
                ],
        ),
      ),
    );
  }

  void _confirmDeleteExercise(Exercise exercise) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить упражнение?'),
        content: Text('«${exercise.name}» и все его записи будут удалены.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              repo.deleteExercise(exercise);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

/// Окно записи подходов: список уже записанных сегодня подходов + быстрый
/// ввод нового (вес × повторения). Можно добавить несколько подряд.
class _SetsDialog extends StatefulWidget {
  final Exercise exercise;
  final Person person;
  final DateTime date;

  /// Вызывается, когда подход записан (запускает таймер отдыха).
  final VoidCallback? onSetAdded;

  const _SetsDialog({
    required this.exercise,
    required this.person,
    required this.date,
    this.onSetAdded,
  });

  @override
  State<_SetsDialog> createState() => _SetsDialogState();
}

class _SetsDialogState extends State<_SetsDialog> {
  final _weight = TextEditingController();
  final _reps = TextEditingController();
  static const List<String> _quickReps = ['6', '8', '10', '12', '15'];

  /// Быстрые прибавки веса в кг.
  static const List<double> _quickWeight = [10, 5, 2.5, 1];

  @override
  void initState() {
    super.initState();
    final last = Repository.instance.lastSet(widget.exercise.id, widget.person.id);
    final w = last?.weight;
    if (w != null) _weight.text = fmtNumber(w);
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  List<SetEntry> get _sets {
    final s = Repository.instance
        .sessionFor(widget.date, widget.exercise.id, widget.person.id);
    return s?.sets ?? const <SetEntry>[];
  }

  void _addSet() {
    final reps = int.tryParse(_reps.text.trim());
    if (reps == null || reps <= 0) return;
    final weightStr = _weight.text.trim().replaceAll(',', '.');
    final weight = weightStr.isEmpty ? null : double.tryParse(weightStr);
    final session = Repository.instance
        .sessionForOrNew(widget.date, widget.exercise.id, widget.person.id);
    session.sets.add(SetEntry(weight, reps));
    Repository.instance.touchWorkout(widget.date);
    Repository.instance.save();
    _reps.clear();
    widget.onSetAdded?.call();
    setState(() {});
  }

  void _removeSet(int index) {
    final session = Repository.instance
        .sessionFor(widget.date, widget.exercise.id, widget.person.id);
    if (session == null) return;
    session.sets.removeAt(index);
    Repository.instance.save();
    setState(() {});
  }

  void _repeatPrevious() {
    final prev = Repository.instance
        .previousSessionSets(widget.date, widget.exercise.id, widget.person.id);
    if (prev == null) return;
    final session = Repository.instance
        .sessionForOrNew(widget.date, widget.exercise.id, widget.person.id);
    session.sets.addAll(prev.map((e) => SetEntry(e.weight, e.reps)));
    Repository.instance.touchWorkout(widget.date);
    Repository.instance.save();
    setState(() {});
  }

  /// Подпись плитки веса: "+2,5" — с русской запятой.
  String _fmtDelta(double d) => '+${fmtNumber(d).replaceAll('.', ',')}';

  /// Прибавить вес к тому, что уже стоит в поле (не заменять).
  /// Пустое поле = 0. Округление до сотых гасит двоичные хвосты.
  void _addWeight(double delta) {
    final cur =
        double.tryParse(_weight.text.trim().replaceAll(',', '.')) ?? 0;
    final sum = ((cur + delta) * 100).round() / 100;
    _weight.text = fmtNumber(sum);
  }

  /// Компактная плитка, чтобы целая строка влезала на экран телефона.
  Widget _quickChip(String label, VoidCallback onPressed) => ActionChip(
        label: Text(label),
        onPressed: () {
          onPressed();
          setState(() {});
        },
        labelStyle: const TextStyle(fontSize: 13),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  @override
  Widget build(BuildContext context) {
    final sets = _sets;
    final lastWeek = Repository.instance
        .lastWeekSets(widget.date, widget.exercise.id, widget.person.id);
    final prev = Repository.instance
        .previousSessionSets(widget.date, widget.exercise.id, widget.person.id);
    final color = personColor(widget.person.id);

    return AlertDialog(
      title: Row(
        children: [
          personAvatar(widget.person, radius: 14),
          const SizedBox(width: 10),
          Expanded(child: Text('${widget.person.name} · ${widget.exercise.name}')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lastWeek != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Неделю назад: '
                    '${lastWeek.map((s) => fmtSet(s)).join(', ')}'),
              ),
            if (prev != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton.icon(
                  onPressed: _repeatPrevious,
                  icon: const Icon(Icons.replay, size: 18),
                  label: Text('Повторить прошлый раз (${prev.length} подх.)'),
                ),
              ),
            if (sets.isNotEmpty) ...[
              const Text('Записано сегодня:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < sets.length; i++)
                    Chip(
                      label: Text(fmtSet(sets[i])),
                      onDeleted: () => _removeSet(i),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Вес, кг',
                hintText: 'пусто = без веса',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final d in _quickWeight)
                  _quickChip(_fmtDelta(d), () => _addWeight(d)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reps,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Повторы'),
              onSubmitted: (_) => _addSet(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final r in _quickReps) _quickChip(r, () => _reps.text = r),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
        FilledButton.icon(
          onPressed: _addSet,
          icon: const Icon(Icons.add),
          label: const Text('Добавить подход'),
        ),
      ],
    );
  }
}

/// Диалог создания/редактирования упражнения с выбором дней недели.
class _ExerciseDialog extends StatefulWidget {
  final Exercise? exercise;
  final int defaultDay;

  const _ExerciseDialog({required this.exercise, required this.defaultDay});

  @override
  State<_ExerciseDialog> createState() => _ExerciseDialogState();
}

class _ExerciseDialogState extends State<_ExerciseDialog> {
  late final TextEditingController _name;
  late final Set<int> _days;
  String? _techId;
  bool _techCleared = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.exercise?.name ?? '');
    _days = widget.exercise == null
        ? {widget.defaultDay}
        : {...widget.exercise!.weekdays};
    _techId = widget.exercise?.techId;
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Последнее название, подставленное автоматически (чтобы не затирать
  /// название, которое пользователь написал сам).
  String _autoName = '';

  /// Выбор техники: подставить её название в поле, если поле пустое или
  /// в нём прежнее автоматическое название (правка Паши 14.10).
  void _applyTech(TechEntry picked) {
    final cur = _name.text.trim();
    if (cur.isEmpty || cur == _autoName) {
      _name.text = picked.name;
      _autoName = picked.name;
    }
    _techId = picked.id;
    _techCleared = false;
  }

  Future<void> _pickTech() async {
    final picked = await showDialog<TechEntry>(
      context: context,
      builder: (_) => const _TechPicker(),
    );
    if (picked == null) return;
    setState(() => _applyTech(picked));
  }

  @override
  Widget build(BuildContext context) {
    final tech = techById(_techId);
    final suggestions = tech == null ? suggestTech(_name.text) : <TechEntry>[];
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
          widget.exercise == null ? 'Новое упражнение' : 'Изменить упражнение'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Например: Жим лёжа',
              ),
            ),
            const SizedBox(height: 16),
            // Порядок по правке Паши (14.10): описание-ярлык выезжает выше,
            // дни недели уходят вниз.
            if (suggestions.isNotEmpty) ...[
              Text('Похоже на:',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s.name),
                      avatar: const Icon(Icons.auto_awesome, size: 16),
                      onPressed: () => setState(() => _applyTech(s)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                const Text('Техника:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tech?.name ?? 'не выбрана',
                    style: TextStyle(
                      color: tech == null ? cs.onSurfaceVariant : cs.primary,
                      fontWeight:
                          tech == null ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickTech,
                  icon: const Icon(Icons.menu_book, size: 18),
                  label: Text(tech == null
                      ? 'Выбрать из справочника'
                      : 'Другая'),
                ),
                if (tech != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _techId = null;
                      _techCleared = true;
                    }),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Убрать'),
                  ),
              ],
            ),
            if (tech != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tech.muscles,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(tech.technique,
                        style:
                            const TextStyle(height: 1.35, fontSize: 13)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Дни недели:'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (i) {
                final day = i + 1;
                return FilterChip(
                  label: Text(weekdaysShort[day - 1]),
                  selected: _days.contains(day),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _days.add(day);
                    } else {
                      _days.remove(day);
                    }
                  }),
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty || _days.isEmpty) return;
            Navigator.pop(context, (name, {..._days}, _techId, _techCleared));
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Выбор записи справочника техники с поиском.
class _TechPicker extends StatefulWidget {
  const _TechPicker();

  @override
  State<_TechPicker> createState() => _TechPickerState();
}

class _TechPickerState extends State<_TechPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase().trim();
    final list = kTechCatalog
        .where((t) =>
            q.isEmpty ||
            t.name.toLowerCase().contains(q) ||
            t.muscles.toLowerCase().contains(q))
        .toList();

    return AlertDialog(
      title: const Text('Справочник техники'),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Поиск упражнения…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Ничего не найдено'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final t = list[i];
                        return ListTile(
                          title: Text(t.name),
                          subtitle: Text(t.muscles),
                          onTap: () => Navigator.pop(context, t),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}

/// Сигналы «телефону» во время отдыха: экран не гаснет, пока идёт отсчёт,
/// и оповещение (вибрация + звук) по концу. Если платформа этого не умеет —
/// тихо ничего не делаем, таймер всё равно отсчитывает.
/// Итог завершённой тренировки: длительность, ≈ккал по участникам,
/// кнопка в «Тренер» — там «Итог тренировки» по каждому участнику.
class _WorkoutSummaryDialog extends StatelessWidget {
  final int elapsedSec;
  final Map<Person, double?> kcalByPerson;

  /// Отрезки [['18:32','19:28'], ...] — для наглядной строки времени.
  final List<List<String>> segments;
  final String? line;

  const _WorkoutSummaryDialog({
    required this.elapsedSec,
    required this.kcalByPerson,
    this.segments = const [],
    this.line,
  });

  @override
  Widget build(BuildContext context) {
    final known = kcalByPerson.entries
        .where((e) => e.value != null)
        .toList();
    return AlertDialog(
      title: const Text('Тренировка завершена!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Длительность: ${fmtDuration(elapsedSec)}'),
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 4),
            // Наглядно: разрыв между заходами виден и не считается.
            for (var i = 0; i < segments.length; i++)
              Text(
                segments[i].length >= 2
                    ? '${i + 1}-й заход ${segments[i][0]}–${segments[i][1]}'
                    : 'Заход ${i + 1}: ${segments[i].join('–')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (segments.length > 1)
              Text(
                'Разрыв между заходами не в счёт — ни по времени, ни по калориям.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 8),
          if (known.isEmpty)
            const Text(
                'Калории не посчитали: в анкете нет веса ни у одного участника.')
          else
            ...known.map((e) => Text(
                '${e.key.name}: ≈ ${e.value!.round()} ккал (грубая оценка)')),
          if (line != null) ...[
            const SizedBox(height: 8),
            // Фраза тренера — жёлтая жирная (правка Паши 14.10).
            coachLineText(context, line),
          ],
          const SizedBox(height: 8),
          Text(
            'Отметить, как прошло и какие веса взять дальше — '
            'в разделе «Тренер».',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TrainerScreen()));
          },
          child: const Text('Итог тренировки'),
        ),
      ],
    );
  }
}

class TimerSignals {
  static const MethodChannel _ch = MethodChannel('workout/timer');

  static Future<void> keepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  static Future<void> notifyEnd() async {
    try {
      await _ch.invokeMethod('notifyEnd');
    } catch (_) {}
  }
}
