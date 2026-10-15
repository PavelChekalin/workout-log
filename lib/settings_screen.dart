import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data.dart';
import 'coach_lines.dart';
import 'health.dart';
import 'reminders.dart';
import 'trainer_screen.dart';
import 'ui.dart';

/// Настройки: тема оформления, участники и резервная копия данных.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final repo = Repository.instance;

  /// Состояние Health Connect (шаги/пульс владельца).
  TodayHealth _health = const TodayHealth();

  @override
  void initState() {
    super.initState();
    _reloadHealth();
  }

  Future<void> _reloadHealth() async {
    final h = await HealthBridge.load();
    if (!mounted) return;
    setState(() => _health = h);
  }

  Future<void> _requestHealth() async {
    final ok = await HealthBridge.requestAccess();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Нет доступа к данным Health Connect. Сейчас '
              'откроется Health Connect — разреши там: Приложения → '
              'Журнал тренировок → Шаги и Пульс.')));
    }
    await _reloadHealth();
  }

  /// Выбрать, чьи данные часов показывать (по умолчанию — первый участник).
  Future<void> _pickHealthProfile() async {
    if (repo.people.isEmpty) return;
    final current = repo.healthProfile?.id;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Данные часов принадлежат'),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              children: [
                for (final p in repo.people)
                  RadioListTile<String>(value: p.id, title: Text(p.name)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await repo.setHealthProfileId(picked);
    setState(() {});
  }

  /// Пересчитать расписание напоминаний под текущие программы.
  Future<void> _rescheduleReminders() async {
    final (h, m) = Reminders.parseTime(repo.remindersTime);
    await Reminders.reschedule(repo,
        enabled: repo.remindersOn, hour: h, minute: m);
  }

  Future<void> _toggleReminders(bool on) async {
    if (on) {
      await Reminders.init();
      final ok = await Reminders.requestPermission();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Разрешение на уведомления не выдано. Разреши их для '
                'приложения в настройках телефона — и включим напоминания.')));
        return;
      }
    }
    await repo.setReminders(on);
    if (!mounted) return;
    setState(() {});
    await _rescheduleReminders();
  }

  Future<void> _pickReminderTime() async {
    final (h, m) = Reminders.parseTime(repo.remindersTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
    );
    if (picked == null || !mounted) return;
    final time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await repo.setReminders(true, time: time);
    if (!mounted) return;
    setState(() {});
    await _rescheduleReminders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        // Запас снизу — кнопки управления телефона перекрывают низ экрана.
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 12 + MediaQuery.of(context).viewPadding.bottom + 40),
        children: [
          const _SectionTitle('Оформление'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Тема'),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Системная')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                    ],
                    selected: {appThemeMode.value},
                    onSelectionChanged: (s) {
                      final mode = s.first;
                      appThemeMode.value = mode;
                      repo.setThemeName(themeModeName(mode));
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          const _SectionTitle('Отдых между подходами'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Использовать таймер отдыха'),
                  subtitle: const Text(
                      'После записанного подхода на экране идёт обратный '
                      'отсчёт, по концу — вибрация и звук. Кому отдыхать по '
                      'часам не нужно — выключите здесь.'),
                  value: repo.restTimerEnabled,
                  onChanged: (v) {
                    repo.setRestTimerEnabled(v);
                    setState(() {});
                  },
                ),
                if (repo.restTimerEnabled) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Сколько отдыхать'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final (sec, label) in const [
                              (60, '1 мин'),
                              (120, '2 мин'),
                              (180, '3 мин'),
                              (300, '5 мин'),
                            ])
                              ChoiceChip(
                                label: Text(label),
                                selected: repo.restSeconds == sec,
                                onSelected: (_) {
                                  repo.setRestSeconds(sec);
                                  setState(() {});
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const _SectionTitle('Данные с часов и браслетов'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  title: const Text('Чьи данные показывать'),
                  subtitle: Text(repo.healthProfile?.name ?? 'Нет участников'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickHealthProfile,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    !_health.sdkReady
                        ? Icons.help_outline
                        : _health.granted
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                  ),
                  title: Text(!_health.sdkReady
                      ? 'Health Connect не найден'
                      : _health.granted
                          ? 'Доступ выдан'
                          : 'Доступ не выдан'),
                  subtitle: Text(!_health.sdkReady
                      ? 'Это приложение видит только встроенный в телефон '
                          'Health Connect (Android 15+).'
                      : _health.granted
                          ? 'Шаги и пульс за сегодня появятся на экране '
                              '«Сегодня» одной строкой сверху.'
                          : 'Данные берутся из Health Connect — только с '
                              'телефона владельца. Жми «Дать доступ» — '
                              'окно откроется само.'),
                  trailing: _health.sdkReady
                      ? _health.granted
                          ? TextButton(
                              onPressed: () async {
                                await HealthBridge.revokeAccess();
                                await _reloadHealth();
                              },
                              child: const Text('Забрать'),
                            )
                          : TextButton(
                              onPressed: _requestHealth,
                              child: const Text('Дать доступ'),
                            )
                      : TextButton(
                          onPressed: HealthBridge.installHealthConnect,
                          child: const Text('Установить'),
                        ),
                ),
              ],
            ),
          ),
          const _SectionTitle('Видео'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Куда сохранять видео'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Галерея'),
                        selected: repo.videoStorage == 'gallery',
                        onSelected: (_) {
                          repo.setVideoStorage('gallery');
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Память приложения'),
                        selected: repo.videoStorage == 'app',
                        onSelected: (_) {
                          repo.setVideoStorage('app');
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    repo.videoStorage == 'gallery'
                        ? 'Видео ляжет в папку «Видео/WorkoutLog» и будет видно в '
                            'Галереи телефона.'
                        : 'Видео будет храниться только внутри приложения. '
                            'ВНИМАНИЕ: при удалении приложения эти видео '
                            'удалятся вместе с ним — восстановить их нельзя. '
                            'Если видео нужны на телефоне — выберите «Галерея».',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: repo.videoStorage == 'app'
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SD-карта не поддерживается: Android 11+ запрещает '
                    'приложениям писать на вторую карту памяти.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _SectionTitle('Тренер'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  title: Text('Как тренер говорит'),
                  subtitle: Text(
                      'Уровень человечности реплик. Фразы показываются '
                      'редко — один раз на событие.'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Робот'),
                        selected: repo.trainerTone == CoachTone.robot,
                        onSelected: (_) {
                          repo.setTrainerTone(CoachTone.robot);
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Тренер'),
                        selected: repo.trainerTone == CoachTone.coach,
                        onSelected: (_) {
                          repo.setTrainerTone(CoachTone.coach);
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Приятель'),
                        selected: repo.trainerTone == CoachTone.buddy,
                        onSelected: (_) {
                          repo.setTrainerTone(CoachTone.buddy);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TrainerScreen())),
                        icon: const Icon(Icons.fitness_center),
                        label: const Text('Анкета и программа'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: repo.remindersOn,
                    title: const Text('Напоминания о тренировках'),
                    subtitle: Text(repo.remindersOn
                        ? 'В тренировочные дни, в ${repo.remindersTime}. '
                            'Текст — из программ участников.'
                        : 'Выключены. Включим — телефон напомнит '
                            'в тренировочный день.'),
                    onChanged: (v) => _toggleReminders(v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('Время напоминания'),
                    trailing: Text(repo.remindersTime,
                        style: Theme.of(context).textTheme.titleMedium),
                    enabled: repo.remindersOn,
                    onTap: repo.remindersOn ? _pickReminderTime : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Напоминание приходит только в те дни, где у кого-то '
                    'запланирована тренировка. Уведомления локальные — '
                    'ничего не уходит в интернет.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _SectionTitle('Участники'),
          ...repo.people.map(_personTile),
          const SizedBox(height: 4),
          if (repo.canAddPerson)
            OutlinedButton.icon(
              onPressed: () => _showPersonDialog(null),
              icon: const Icon(Icons.person_add),
              label: const Text('Добавить участника'),
            )
          else
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.person_off_outlined),
              label: Text('Лимит ${Repository.maxPeople} участников'),
            ),
          const _SectionTitle('Данные'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Экспорт (сохранить копию)'),
                  subtitle: const Text('Показать все данные текстом — можно скопировать и сохранить'),
                  onTap: _showExport,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Импорт (загрузить копию)'),
                  subtitle: const Text('Вставить сохранённый текст и восстановить данные'),
                  onTap: _showImport,
                ),
              ],
            ),
          ),
          const _SectionTitle('О приложении'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('О приложении'),
              subtitle: const Text('Версия, что за приложение и где данные'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AboutScreen())),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _personTile(Person person) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: personAvatar(person, radius: 20),
        title: Text(person.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Изменить имя',
              icon: const Icon(Icons.edit),
              onPressed: () => _showPersonDialog(person),
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(person),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPersonDialog(Person? person) async {
    final res = await showDialog<_PersonResult>(
      context: context,
      builder: (_) => _PersonDialog(person: person),
    );
    if (res == null || res.name.isEmpty) return;
    if (person == null) {
      final p = repo.addPerson(res.name);
      if (res.photo != null) repo.setAvatar(p, res.photo);
    } else {
      repo.renamePerson(person, res.name);
      // Фото может измениться (в т.ч. на null — «убрать фото»),
      // поэтому ставим всегда, если оно не совпадает с текущим.
      if (!_sameBytes(person.avatar, res.photo)) {
        repo.setAvatar(person, res.photo);
      }
    }
    setState(() {});
  }

  /// Совпадают ли два фото (или оба пустые).
  static bool _sameBytes(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _confirmDelete(Person person) {
    if (repo.people.length <= 1) {
      _snack('Должен остаться хотя бы один человек');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Удалить ${person.name}?'),
        content: const Text('Все его записи тренировок тоже будут удалены.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              repo.deletePerson(person);
              // Участник ушёл — его дни тренировок могли выпасть из текста
              // напоминаний, пересчитаем.
              if (repo.remindersOn) _rescheduleReminders();
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExport() async {
    final data = repo.exportJson();
    final copied = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Резервная копия'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              data,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Закрыть'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.copy),
            label: const Text('Копировать'),
          ),
        ],
      ),
    );
    if (copied != true) return;
    await Clipboard.setData(ClipboardData(text: data));
    _snack('Данные скопированы. Сохраните их в заметках или отправьте себе.');
  }

  Future<void> _showImport() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Восстановить из копии'),
        content: SizedBox(
          width: 600,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Вставьте сюда сохранённый текст',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final ok = repo.importJson(text);
    if (ok) {
      setState(() {});
      _snack('Данные восстановлены');
    } else {
      _snack('Не получилось прочитать текст — проверьте, что скопировано целиком');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Результат диалога участника: имя и выбранное фото (null — фото нет).
class _PersonResult {
  final String name;
  final Uint8List? photo;
  const _PersonResult(this.name, this.photo);
}

/// Диалог участника: имя + фото-аватарка (выбрать из галереи или убрать).
/// Ничего не пишет в хранилище — результат применяет вызвавшая сторона.
class _PersonDialog extends StatefulWidget {
  final Person? person;
  const _PersonDialog({this.person});

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  late final TextEditingController _controller;
  Uint8List? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.person?.name ?? '');
    _photo = widget.person?.avatar;
    // Чтобы буква в кружке обновлялась, пока печатаете имя.
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      setState(() => _photo = bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не получилось выбрать фото')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, _PersonResult(name, _photo));
  }

  @override
  Widget build(BuildContext context) {
    // Превью: фото из диалога, буква — по набираемому имени.
    final previewPerson = Person(
      id: widget.person?.id ?? 'preview',
      name: _controller.text.trim(),
      avatar: _photo,
    );

    return AlertDialog(
      title: Text(widget.person == null ? 'Новый участник' : 'Участник'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                personAvatar(previewPerson, radius: 40),
                Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _pickPhoto,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.camera_alt, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(_photo == null ? 'Выбрать фото' : 'Заменить фото'),
            ),
            if (_photo != null)
              TextButton.icon(
                onPressed: () => setState(() => _photo = null),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Убрать фото'),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Имя'),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Страница «О приложении» (правка Паши 14.10): версия, что за приложение,
/// что умеет тренер, где хранятся данные и совет сделать копию.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        // Запас снизу — низ экрана перекрывают кнопки управления телефона.
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom + 48),
        children: [
          Center(
            child: Icon(Icons.fitness_center,
                size: 56, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Журнал тренировок',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (_, snap) => Center(
              child: Text(
                'Версия ${snap.data?.version ?? '…'}'
                '+${snap.data?.buildNumber ?? ''}',
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _AboutCard(
            icon: Icons.menu_book,
            title: 'Что это',
            text: 'Дневник тренировок для себя и друзей: подходы, веса, '
                'статистика, таймер отдыха, видео техники и заметки.',
          ),
          const _AboutCard(
            icon: Icons.fitness_center,
            title: 'Тренер',
            text: 'Офлайн-тренер без интернета: анкета, подбор программы, '
                'план на сегодня, подбадривание во время тренировки и отчёт '
                'по циклу. Всё считается по правилам — никакого облака.',
          ),
          const _AboutCard(
            icon: Icons.lock_outline,
            title: 'Где данные',
            text: 'Только на этом устройстве — интернет приложению не нужен. '
                'Копию можно сохранить и восстановить в разделе «Данные» '
                'экрана «Настройки».',
          ),
          Card(
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Сейчас в приложении',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'Участников: ${repo.people.length} · '
                    'Упражнений: ${repo.exercises.length} · '
                    'Записей тренировок: ${repo.sessions.length}',
                    style: TextStyle(fontSize: 13.5, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Совет: раз в месяц сохраняйте резервную копию '
            '(экран «Настройки» → «Данные») — если телефон потеряется, '
            'данные не потеряются.',
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
        ],
      ),
    );
  }
}

/// Карточка-абзац на странице «О приложении».
class _AboutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _AboutCard({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
