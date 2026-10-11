import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data.dart';
import 'ui.dart';

/// Настройки: тема оформления, участники и резервная копия данных.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final repo = Repository.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(12),
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
          const _SectionTitle('Участники'),
          ...repo.people.map(_personTile),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _showPersonDialog(null),
            icon: const Icon(Icons.person_add),
            label: const Text('Добавить участника'),
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
          const _SectionTitle('О программе'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('О программе'),
              subtitle: const Text('Версия, что за приложение и где данные'),
              onTap: _showAbout,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Журнал тренировок'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Версия ${info.version}+${info.buildNumber}'),
              const SizedBox(height: 12),
              const Text(
                'Дневник тренировок для себя и друзей: подходы, веса, '
                'статистика, таймер отдыха и заметки.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Все данные хранятся только на этом устройстве — '
                'интернет не используется. Копию можно сохранить '
                'и восстановить в разделе «Данные».',
              ),
              const SizedBox(height: 12),
              Text(
                'Участников: ${repo.people.length} · '
                'Упражнений: ${repo.exercises.length} · '
                'Записей: ${repo.sessions.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
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
