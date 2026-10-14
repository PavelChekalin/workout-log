// ---------------------------------------------------------------------------
// Экран «Тренер»: анкета участника, подбор программы, план на сегодня,
// «Итог тренировки» с прогрессией.
//
// Всё офлайн: подбор — таблица правил (trainer_logic.dart), реплики тренера —
// из каталога фраз (создадим позже, этап 5).
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'catalog.dart';
import 'coach_lines.dart';
import 'data.dart';
import 'programs.dart';
import 'reminders.dart';
import 'trainer_apply.dart';
import 'trainer_data.dart';
import 'trainer_logic.dart';
import 'ui.dart';

/// Названия дней недели (1 = Пн ... 7 = Вс).
const List<String> kWeekdayNames = [
  '',
  'Пн',
  'Вт',
  'Ср',
  'Чт',
  'Пт',
  'Сб',
  'Вс',
];

/// Сколько вес кг — без лишнего нуля: 40 / 42.5.
String fmtKg(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : '$v';

/// Главный экран тренера.
class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  final repo = Repository.instance;
  String? personId;

  /// Гард «не заиграться»: фраза по событию — один раз на время экрана.
  final Set<String> _shownLines = <String>{};

  String? _lineOnce(String event, {String? tone}) {
    if (!_shownLines.add(event)) return null;
    return coachLine(tone ?? repo.trainerTone, event);
  }

  /// Дней с последней записанной тренировки участника (999 — записей нет).
  int _daysSinceLastSession(Person p) {
    String? last;
    for (final s in repo.sessions) {
      if (s.personId == p.id && s.sets.isNotEmpty) {
        if (last == null || s.date.compareTo(last) > 0) last = s.date;
      }
    }
    if (last == null) return 999;
    final parts = last.split('-');
    final d = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    return DateTime.now().difference(d).inDays;
  }

  @override
  void initState() {
    super.initState();
    personId = repo.people.isNotEmpty ? repo.people.first.id : null;
  }

  Person? get person {
    for (final p in repo.people) {
      if (p.id == personId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = person;
    return Scaffold(
      appBar: AppBar(title: const Text('Тренер')),
      body: repo.people.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Сначала добавьте участников на главном экране — '
                  'тренеру есть кого тренировать.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _personSelector(),
                const SizedBox(height: 16),
                if (p != null) ..._personContent(p),
              ],
            ),
    );
  }

  /// Выбор участника: у каждого своя анкета и программа.
  Widget _personSelector() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: repo.people.map((p) {
          final selected = p.id == personId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              avatar: personAvatar(p, radius: 12),
              label: Text(p.name),
              onSelected: (_) => setState(() => personId = p.id),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _personContent(Person p) {
    final profile = repo.trainerProfile(p.id);
    if (profile == null || !profile.questionnaireDone) {
      return [_questionnaireCard(p)];
    }
    if (profile.program == null || programById(profile.program) == null) {
      return [
        _profileDoneCard(profile),
        _recommendationCard(profile),
        const SizedBox(height: 12),
        _catalogCard(),
      ];
    }
    return [
      _planCard(p, profile),
      const SizedBox(height: 12),
      _programCard(p, profile),
    ];
  }

  // ---------- Анкета ----------

  Widget _questionnaireCard(Person p) {
    final exists = repo.trainerProfile(p.id) != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Анкета: ${p.name}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              '7 простых вопросов: возраст, вес, опыт, цель. По ним тренер '
              'подберёт программу. Всё остаётся на телефоне, ничего не '
              'уходит в интернет.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            QuestionnaireScreen(personId: p.id)));
                if (ok == true && mounted) setState(() {});
              },
              icon: const Icon(Icons.assignment_outlined),
              label: Text(exists ? 'Пройти заново' : 'Пройти анкету'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileDoneCard(TrainerProfile profile) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: const Text('Анкета пройдена'),
        subtitle: Text(
            '${_expLabels[profile.exp]?[0] ?? ''} · цель: '
            '${_goalLabels[profile.goal]?[0] ?? ''} · ${profile.days} дн./нед.'),
        trailing: TextButton(
          onPressed: () async {
            final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => QuestionnaireScreen(personId: personId!)));
            if (ok == true && mounted) setState(() {});
          },
          child: const Text('Изменить'),
        ),
      ),
    );
  }

  // ---------- Подбор программы ----------

  Widget _recommendationCard(TrainerProfile profile) {
    final id = recommendProgramId(
        exp: profile.exp, goal: profile.goal, days: profile.days);
    final program = programById(id)!;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.lightbulb_outline),
              const SizedBox(width: 8),
              Text('Тренер советует',
                  style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            Text(program.name,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(program.description),
            const SizedBox(height: 4),
            Text(program.progression,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openSetup(program),
              icon: const Icon(Icons.check),
              label: const Text('Взять эту'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Все программы',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Можно взять любую — выбор человека главнее совета.'),
            const SizedBox(height: 8),
            ...kPrograms.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fitness_center),
                  title: Text(p.name),
                  subtitle: Text(
                      '${p.daysPerWeek} дн./нед. · ${p.level == 'beginner' ? 'новичкам' : p.level == 'intermediate' ? 'с опытом' : 'продвинутым'}\n'
                      '${p.description}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  onTap: () => _openSetup(p),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _openSetup(Program program) async {
    final p = person;
    if (p == null) return;
    final profile = repo.trainerProfile(p.id);
    final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => ProgramSetupScreen(
                  personId: p.id,
                  program: program,
                  limits: profile?.limits ?? <String>{},
                  initialWeekdays: profile?.weekdays ?? <int>{},
                )));
    if (done == true && mounted) setState(() {});
  }

  // ---------- План на сегодня ----------

  Widget _planCard(Person p, TrainerProfile profile) {
    final program = programById(profile.program)!;
    final today = DateTime.now();
    final start = profile.startDate ?? isoDate(today);
    final week = currentCycleWeek(
        startDate: start, today: today, cycleWeeks: program.cycleWeeks);
    final sessionDates = repo.sessions
        .where((s) => s.sets.isNotEmpty)
        .map((s) => s.date)
        .toSet();
    final done = completedSessionsSince(
        startDate: start, recordedDates: sessionDates);
    final planDay = todayPlanDay(
        program: program,
        weekdays: profile.weekdays,
        today: today,
        completedSessions: done);
    final trainingToday = profile.weekdays.contains(today.weekday);
    final ended = cycleEnded(
        startDate: start, today: today, cycleWeeks: program.cycleWeeks);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(program.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Text('Неделя $week из ${program.cycleWeeks}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text(
              trainingToday
                  ? 'Сегодня по плану: ${planDay.title}'
                  : 'Сегодня не тренировочный день. План на ближайший: '
                      '${planDay.title}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_daysSinceLastSession(p) >= 7) ...[
              const SizedBox(height: 4),
              _coachLineText(_lineOnce(CoachEvent.skipWeek)),
            ],
            if (trainingToday) ...[
              const SizedBox(height: 4),
              _coachLineText(_lineOnce(CoachEvent.planToday)),
            ],
            if (ended) ...[
              const SizedBox(height: 8),
              _cycleReportCard(p, profile, program),
            ],
            const Divider(height: 24),
            ...planDay.exercises.map((e) => _planRow(p, profile, program, e)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final applied = await _showSummary(p, profile, planDay);
                  if (applied != null && mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(applied)));
                  }
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Итог тренировки'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Курсивная строчка фразы тренера (или пустота).
  Widget _coachLineText(String? line) {
    if (line == null || line.isEmpty) return const SizedBox.shrink();
    return Text(line,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontStyle: FontStyle.italic));
  }

  /// Карточка конца цикла: статистика + рекорды + «что дальше?» (§8).
  Widget _cycleReportCard(Person p, TrainerProfile profile, Program program) {
    final report = buildCycleReport(
        repo: repo,
        personId: p.id,
        program: program,
        profile: profile);
    final line = _lineOnce(CoachEvent.cycleEnd);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Цикл закончился (${program.cycleWeeks} нед.)',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (line != null) ...[
            const SizedBox(height: 2),
            Text(line,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 6),
          Text('Тренировок выполнено: ${report.done} из ${report.planned}'),
          if (report.records.isEmpty)
            const Text('Новых рекордов за цикл не было — но веса держим.')
          else ...[
            const SizedBox(height: 4),
            Text('Новые рекорды:',
                style: Theme.of(context).textTheme.bodySmall),
            ...report.records.map((r) => Text('• $r',
                style: Theme.of(context).textTheme.bodySmall)),
          ],
          const SizedBox(height: 8),
          Text('Что дальше?',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton.tonal(
                onPressed: () {
                  profile.startDate = shiftStartDate(
                      profile.startDate!, program.cycleWeeks);
                  repo.setTrainerProfile(p.id, profile);
                  setState(() {});
                  _snack('Продолжаем: недели пошли заново, веса растут дальше');
                },
                child: const Text('Продолжить'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  profile.startDate = shiftStartDate(
                      profile.startDate!, program.cycleWeeks);
                  profile.fails.clear();
                  repo.setTrainerProfile(p.id, profile);
                  setState(() {});
                  _snack('Цикл повторён: счётчики неудач обнулены');
                },
                child: const Text('Повторить цикл'),
              ),
              OutlinedButton(
                onPressed: () {
                  // Прошёл полный цикл — опыт уже «регулярно»: рекомендация
                  // в каталоге может измениться (§8).
                  profile.exp = 'regular';
                  repo.setTrainerProfile(p.id, profile);
                  _openSetup(program);
                },
                child: const Text('Новая программа'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _planRow(
      Person p, TrainerProfile profile, Program program, PlanExercise e) {
    final ex = exerciseByTech(repo, e.techId);
    final session = ex == null ? null : repo.sessionFor(DateTime.now(), ex.id, p.id);
    final recorded = session != null && session.sets.isNotEmpty;
    final isMain = program.mainLifts.contains(e.techId);
    final name = techById(e.techId)?.name ?? e.techId;

    String weightText;
    if (isMain) {
      final oneRM = current1RM(repo: repo, personId: p.id, techId: e.techId);
      final week = currentCycleWeek(
          startDate: profile.startDate ?? isoDate(DateTime.now()),
          today: DateTime.now(),
          cycleWeeks: program.cycleWeeks);
      final w = scheme531(week: week, oneRM: oneRM);
      weightText =
          '5/3/1: ${fmtKg(w[0])} / ${fmtKg(w[1])} / ${fmtKg(w[2])} кг';
    } else {
      final w = planWeight(
          repo: repo, personId: p.id, profile: profile, techId: e.techId);
      weightText = w == null ? 'свой вес' : '${fmtKg(w)} кг';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(recorded ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: recorded
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name — ${e.sets}×${e.label}',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  recorded
                      ? '$weightText · записано: '
                          '${session.sets.map((s) => '${s.weight == null ? '—' : fmtKg(s.weight!)}×${s.reps}').join(', ')}'
                      : weightText,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Программа участника ----------

  Widget _programCard(Person p, TrainerProfile profile) {
    final program = programById(profile.program)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Программа',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(program.progression),
            const SizedBox(height: 4),
            Text(
              'Дни: ${(profile.weekdays.toList()..sort()).map((d) => kWeekdayNames[d]).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text('Старт: ${profile.startDate ?? '—'}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openSetup(program),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Сменить программу'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Итог тренировки ----------

  /// Возвращает текст-результат (или null, если закрыли без применения).
  Future<String?> _showSummary(
      Person p, TrainerProfile profile, ProgramDay planDay) {
    return showDialog<String>(
      context: context,
      builder: (_) => _SummaryDialog(
          person: p,
          profile: profile,
          planDay: planDay,
          tone: repo.trainerTone),
    );
  }
}

// ---------------------------------------------------------------------------
// Анкета (7 шагов)
// ---------------------------------------------------------------------------

/// Названия и пояснения вариантов ответов.
const Map<String, List<String>> _expLabels = {
  'beginner': [
    'Только начинаю',
    'Меньше 6 месяцев или ещё не занимался',
  ],
  'break': [
    'Был перерыв',
    'Занимался раньше, но давно не трогал железо',
  ],
  'regular': [
    'Регулярно',
    'Больше года без больших перерывов',
  ],
};

const Map<String, List<String>> _goalLabels = {
  'strength': [
    'Стать сильнее',
    'Тяжёлые веса, базовые движения',
  ],
  'shape': [
    'Общая форма',
    'Подтянуть фигуру и держать тонус',
  ],
  'mass': [
    'Набрать массу',
    'Больше объёмов, сплит по группам',
  ],
  'loss': [
    'Сбросить вес',
    'Жиросжигание, короткий отдых',
  ],
};

const List<int> _daysOptions = [2, 3, 4, 6];

const Map<String, List<String>> _limitLabels = {
  'knee': [
    'Колено',
    'Присед и выпады заменим на жим ногами',
  ],
  'back': [
    'Спина',
    'Становую и тягу штанги заменим на более щадящие',
  ],
  'shoulder': [
    'Плечо',
    'Жим стоя заменим на жим лёжа',
  ],
};

/// Анкета участника: по одному вопросу на экран.
class QuestionnaireScreen extends StatefulWidget {
  final String? personId;
  const QuestionnaireScreen({super.key, this.personId});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final repo = Repository.instance;
  int step = 0;
  static const totalSteps = 7;

  final ageCtrl = TextEditingController();
  final heightCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  String exp = 'beginner';
  String goal = 'shape';
  int days = 3;
  final Set<String> limits = <String>{};

  @override
  void dispose() {
    ageCtrl.dispose();
    heightCtrl.dispose();
    weightCtrl.dispose();
    super.dispose();
  }

  int? _parseInt(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return int.tryParse(t.split('.').first);
  }

  bool get _stepOk {
    switch (step) {
      case 0:
        return _parseInt(ageCtrl) != null;
      case 1:
        return _parseInt(heightCtrl) != null;
      case 2:
        return _parseInt(weightCtrl) != null;
      default:
        return true;
    }
  }

  void _next() {
    if (step < totalSteps - 1) {
      setState(() => step++);
      return;
    }
    // Сохраняем.
    final pid = widget.personId;
    if (pid != null) {
      final old = repo.trainerProfile(pid);
      final profile = old ?? TrainerProfile();
      profile.age = _parseInt(ageCtrl);
      profile.height = _parseInt(heightCtrl);
      profile.weight = _parseInt(weightCtrl);
      profile.exp = exp;
      profile.goal = goal;
      profile.days = days;
      profile.limits
        ..clear()
        ..addAll(limits);
      repo.setTrainerProfile(pid, profile);
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Анкета · шаг ${step + 1} из $totalSteps'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (step + 1) / totalSteps),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (step == 0 && widget.personId != null) ...[
                    Text(
                      'Это про тебя. Друзей и их параметры можно добавить '
                      'позже в Настройках — у каждого своя анкета и программа.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                  ],
                  ..._stepContent(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => step--),
                      child: const Text('Назад'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _stepOk ? _next : null,
                    child: Text(step < totalSteps - 1 ? 'Дальше' : 'Готово'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stepContent() {
    switch (step) {
      case 0:
        return [
          const Text('Сколько тебе лет?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: ageCtrl,
            keyboardType: TextInputType.number,
            // Без setState кнопка «Дальше» оставалась бы серой: _stepOk
            // пересчитывается только при перерисовке (правка 14.10).
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Возраст', suffixText: 'лет'),
          ),
        ];
      case 1:
        return [
          const Text('Рост?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: heightCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Рост', suffixText: 'см'),
          ),
        ];
      case 2:
        return [
          const Text('Вес?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: weightCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration:
                const InputDecoration(labelText: 'Вес', suffixText: 'кг'),
          ),
        ];
      case 3:
        return [
          const Text('Какой у тебя опыт?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: exp,
            onChanged: (v) => setState(() => exp = v!),
            child: Column(
              children: _expLabels.entries
                  .map((e) => RadioListTile<String>(
                        value: e.key,
                        title: Text(e.value[0]),
                        subtitle: Text(e.value[1]),
                      ))
                  .toList(),
            ),
          ),
        ];
      case 4:
        return [
          const Text('Какая цель?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: goal,
            onChanged: (v) => setState(() => goal = v!),
            child: Column(
              children: _goalLabels.entries
                  .map((e) => RadioListTile<String>(
                        value: e.key,
                        title: Text(e.value[0]),
                        subtitle: Text(e.value[1]),
                      ))
                  .toList(),
            ),
          ),
        ];
      case 5:
        return [
          const Text('Сколько дней в неделю готов заниматься?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _daysOptions
                .map((d) => ChoiceChip(
                      label: Text('$d ${d == 6 ? 'дней' : 'дня'}'),
                      selected: days == d,
                      onSelected: (_) => setState(() => days = d),
                    ))
                .toList(),
          ),
        ];
      case 6:
        return [
          const Text('Есть ли ограничения по здоровью?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Программа аккуратно заменит упражнения. Можно пропустить.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          ..._limitLabels.entries.map((e) => CheckboxListTile(
                value: limits.contains(e.key),
                title: Text(e.value[0]),
                subtitle: Text(e.value[1]),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    limits.add(e.key);
                  } else {
                    limits.remove(e.key);
                  }
                }),
              )),
        ];
    }
    return const [];
  }
}

// ---------------------------------------------------------------------------
// Настройка программы: дни недели + стартовые веса
// ---------------------------------------------------------------------------

/// Предложенные дни недели по числу тренировок.
Set<int> suggestWeekdays(int days) {
  switch (days) {
    case 2:
      return {2, 4};
    case 3:
      return {1, 3, 5};
    case 4:
      return {1, 2, 4, 5};
    default:
      return {1, 2, 3, 4, 5, 6};
  }
}

class ProgramSetupScreen extends StatefulWidget {
  final String personId;
  final Program program;
  final Set<String> limits;
  final Set<int> initialWeekdays;

  const ProgramSetupScreen({
    super.key,
    required this.personId,
    required this.program,
    required this.limits,
    required this.initialWeekdays,
  });

  @override
  State<ProgramSetupScreen> createState() => _ProgramSetupScreenState();
}

class _ProgramSetupScreenState extends State<ProgramSetupScreen> {
  final repo = Repository.instance;
  late Set<int> weekdays = widget.initialWeekdays.isNotEmpty
      ? {...widget.initialWeekdays}
      : suggestWeekdays(widget.program.daysPerWeek);
  late final Map<String, TextEditingController> weightCtrls;

  @override
  void initState() {
    super.initState();
    final suggested = suggestStartWeights(
        repo, widget.personId, widget.program);
    weightCtrls = {
      for (final techId in neededTechIds(
          program: widget.program, weekdays: weekdays, limits: widget.limits))
        techId: TextEditingController(
            text: suggested[techId] == null ? '' : fmtKg(suggested[techId]!)),
    };
  }

  @override
  void dispose() {
    for (final c in weightCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parseWeight(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  void _assign() {
    if (weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выбери хотя бы один день')));
      return;
    }
    final startWeights = <String, double>{};
    weightCtrls.forEach((techId, c) {
      final v = _parseWeight(c);
      if (v != null) startWeights[techId] = v;
    });
    final created = assignProgram(
      repo: repo,
      personId: widget.personId,
      program: widget.program,
      weekdays: weekdays,
      limits: widget.limits,
      startWeights: startWeights,
    );
    // Программа задала дни тренировок — пересчитать напоминания.
    if (repo.remindersOn) {
      final (h, m) = Reminders.parseTime(repo.remindersTime);
      Reminders.reschedule(repo, enabled: true, hour: h, minute: m);
    }
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(created.isEmpty
            ? 'Программа назначена'
            : 'Программа назначена. Создано упражнений: ${created.length}')));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(p.description),
          const SizedBox(height: 16),
          Text('Дни тренировок',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(kWeekdayNames[d]),
                  selected: weekdays.contains(d),
                  onSelected: (v) => setState(() {
                    if (v) {
                      weekdays.add(d);
                    } else {
                      weekdays.remove(d);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Стартовые веса',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Подсказка взята из журнала, если записей нет — рабочий '
            'дефолт. Пусто — упражнение без веса (свой вес, планка).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ...weightCtrls.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(techById(e.key)?.name ?? e.key),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: e.value,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'кг', isDense: true),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _assign,
            icon: const Icon(Icons.check),
            label: Text('Назначить: ${p.name}'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Итог тренировки: как прошло → прогрессия весов
// ---------------------------------------------------------------------------

class _SummaryDialog extends StatefulWidget {
  final Person person;
  final TrainerProfile profile;
  final ProgramDay planDay;
  final String tone;

  const _SummaryDialog({
    required this.person,
    required this.profile,
    required this.planDay,
    required this.tone,
  });

  @override
  State<_SummaryDialog> createState() => _SummaryDialogState();
}

class _SummaryDialogState extends State<_SummaryDialog> {
  final repo = Repository.instance;

  /// Выбор по каждому техId: 'easy' | 'hard' | 'failed'.
  late final Map<String, String> results = {};

  /// Дефолт по записи в журнале: записано — «тяжело» (держим вес),
  /// не записано — «не вышло».
  String _defaultResult(PlanExercise e) {
    final ex = exerciseByTech(repo, e.techId);
    final s =
        ex == null ? null : repo.sessionFor(DateTime.now(), ex.id, widget.person.id);
    return (s != null && s.sets.isNotEmpty) ? 'hard' : 'failed';
  }

  @override
  Widget build(BuildContext context) {
    final program = programById(widget.profile.program);
    final mainLifts = program?.mainLifts ?? const <String>[];
    final weighted = widget.planDay.exercises
        .where((e) => !mainLifts.contains(e.techId))
        .toList();

    return AlertDialog(
      title: const Text('Как прошла тренировка?'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (mainLifts.isNotEmpty)
              Text(
                'Основные движения 5/3/1 растут на границе цикла — '
                'отметим только дополнительные упражнения.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ...weighted.map((e) => _exerciseTile(e)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _apply()),
          child: const Text('Применить'),
        ),
      ],
    );
  }

  Widget _exerciseTile(PlanExercise e) {
    final name = techById(e.techId)?.name ?? e.techId;
    final current = planWeight(
        repo: repo,
        personId: widget.person.id,
        profile: widget.profile,
        techId: e.techId);
    final done = results[e.techId] ?? _defaultResult(e);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$name · план ${e.sets}×${e.label}${current == null ? '' : ' @ ${fmtKg(current)} кг'}',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'easy', label: Text('Легко')),
              ButtonSegment(value: 'hard', label: Text('Тяжело')),
              ButtonSegment(value: 'failed', label: Text('Не вышло')),
            ],
            selected: {done},
            onSelectionChanged: (s) =>
                setState(() => results[e.techId] = s.first),
          ),
        ],
      ),
    );
  }

  String _apply() {
    final changes = <String>[];
    final fails = widget.profile.fails;
    var anyProgress = false;
    for (final e in widget.planDay.exercises) {
      final program = programById(widget.profile.program);
      if (program != null && program.mainLifts.contains(e.techId)) continue;
      final current = planWeight(
          repo: repo,
          personId: widget.person.id,
          profile: widget.profile,
          techId: e.techId);
      final r = results[e.techId] ?? _defaultResult(e);
      final result = switch (r) {
        'easy' => WorkoutResult.easy,
        'hard' => WorkoutResult.hard,
        _ => WorkoutResult.failed,
      };
      if (result != WorkoutResult.failed) anyProgress = true;
      final next = nextWeight(
          techId: e.techId, current: current, result: result, fails: fails);
      final name = techById(e.techId)?.name ?? e.techId;
      if (next != null && current != null && next != current) {
        widget.profile.startWeights[e.techId] = next;
        changes.add('$name: ${fmtKg(current)} → ${fmtKg(next)} кг');
      }
    }
    repo.setTrainerProfile(widget.person.id, widget.profile);
    final phrase = coachLine(
        widget.tone,
        anyProgress ? CoachEvent.planDone : CoachEvent.planPartial);
    if (changes.isEmpty) {
      return 'Готово. Веса держим как есть.'
          '${phrase == null ? '' : '\n$phrase'}';
    }
    return 'Готово! Следующие веса: ${changes.join('; ')}'
        '${phrase == null ? '' : '\n$phrase'}';
  }
}
