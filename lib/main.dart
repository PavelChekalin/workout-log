import 'package:flutter/material.dart';

import 'catalog.dart';
import 'data.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Repository.instance.init();
  appThemeMode.value = themeModeFromName(Repository.instance.themeName);
  runApp(const WorkoutLogApp());
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

class _MainScreenState extends State<MainScreen> {
  final repo = Repository.instance;
  DateTime selectedDate = DateTime.now();

  void _refresh() => setState(() {});

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
            tooltip: 'Добавить участника',
            icon: const Icon(Icons.person_add_alt),
            onPressed: _addPerson,
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
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editExercise(null),
        icon: const Icon(Icons.add),
        label: const Text('Упражнение'),
      ),
      body: Column(
        children: [
          _dateBar(),
          _participantsBar(),
          _daySummary(),
          const Divider(height: 1),
          Expanded(
            child: dayExercises.isEmpty
                ? _emptyExercises()
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 96),
                    itemCount: dayExercises.length,
                    itemBuilder: (_, i) => _exerciseCard(dayExercises[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dateBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Предыдущий день',
            onPressed: () => setState(
                () => selectedDate = selectedDate.subtract(const Duration(days: 1))),
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
                  'упражнения на ${weekdayNameRu(selectedDate.weekday)}',
                  style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Следующий день',
            onPressed: () => setState(
                () => selectedDate = selectedDate.add(const Duration(days: 1))),
          ),
          TextButton(
            onPressed: () => setState(() => selectedDate = DateTime.now()),
            child: const Text('Сегодня'),
          ),
        ],
      ),
    );
  }

  /// Итог дня (подходы + тоннаж) и заметка к тренировке.
  Widget _daySummary() {
    final d = isoDate(selectedDate);
    var setCount = 0;
    var vol = 0.0;
    for (final s in repo.sessions) {
      if (s.date == d) {
        setCount += s.sets.length;
        vol += repo.volume(s.sets);
      }
    }
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
              Expanded(
                child: Text(
                  setCount == 0
                      ? 'Итог дня: пока пусто'
                      : 'Итог дня: $setCount подх. · ${grouped(vol)} кг',
                  style: TextStyle(color: _cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: _editNote,
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(note == null ? 'Заметка' : 'Заметка ✓'),
              ),
            ],
          ),
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
            hintText: 'Например: у Паши травма кисти, подтягивания не делал',
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

  /// Строка участников: чипы людей + кнопка «Участник».
  Widget _participantsBar() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final p in repo.people)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                avatar: CircleAvatar(
                  backgroundColor: personColor(p.id).withValues(alpha: 0.25),
                  child: Text(
                    personInitial(p.name),
                    style: TextStyle(
                      color: personColor(p.id),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                label: Text(p.name),
                onPressed: () => _renamePerson(p),
                onDeleted: () => _confirmDeletePerson(p),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Участник'),
            onPressed: _addPerson,
          ),
        ],
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
              'На ${weekdayNameRu(selectedDate.weekday)} упражнений нет',
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
            if (repo.people.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Добавьте участников (кнопка «+ Участник» выше), '
                  'чтобы записывать подходы.',
                  style: TextStyle(color: _cs.onSurfaceVariant, fontSize: 13),
                ),
              )
            else
              ...repo.people.map((p) => _personRow(exercise, p)),
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
            CircleAvatar(
              radius: 14,
              backgroundColor: color.withValues(alpha: 0.25),
              child: Text(
                personInitial(person.name),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
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
    final name = await _askName('Новый участник', '');
    if (name == null || name.isEmpty) return;
    repo.addPerson(name);
    setState(() {});
  }

  Future<void> _renamePerson(Person person) async {
    final name = await _askName('Имя участника', person.name);
    if (name == null || name.isEmpty) return;
    repo.renamePerson(person, name);
    setState(() {});
  }

  void _confirmDeletePerson(Person person) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Удалить ${person.name}?'),
        content: const Text('Все записи этого участника тоже будут удалены.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              repo.deletePerson(person);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSets(Exercise exercise, Person person) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SetsDialog(
        exercise: exercise,
        person: person,
        date: selectedDate,
      ),
    );
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
  Future<void> _showTech(Exercise exercise) async {
    final tech = techById(exercise.techId);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: tech == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

  const _SetsDialog({
    required this.exercise,
    required this.person,
    required this.date,
  });

  @override
  State<_SetsDialog> createState() => _SetsDialogState();
}

class _SetsDialogState extends State<_SetsDialog> {
  final _weight = TextEditingController();
  final _reps = TextEditingController();
  static const List<String> _quickReps = ['6', '8', '10', '12', '15'];

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
    Repository.instance.save();
    _reps.clear();
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
    Repository.instance.save();
    setState(() {});
  }

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
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.25),
            child: Text(personInitial(widget.person.name),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weight,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Вес, кг',
                      hintText: 'пусто = без веса',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reps,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Повторы'),
                    onSubmitted: (_) => _addSet(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final r in _quickReps)
                  ActionChip(
                    label: Text(r),
                    onPressed: () => setState(() => _reps.text = r),
                  ),
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

  Future<void> _pickTech() async {
    final picked = await showDialog<TechEntry>(
      context: context,
      builder: (_) => const _TechPicker(),
    );
    if (picked == null) return;
    setState(() {
      _techId = picked.id;
      _techCleared = false;
    });
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
            const SizedBox(height: 16),
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
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
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
                      onPressed: () => setState(() {
                        _techId = s.id;
                        _techCleared = false;
                      }),
                    ),
                ],
              ),
            ],
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
