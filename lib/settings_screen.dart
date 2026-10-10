import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        leading: CircleAvatar(
          backgroundColor: personColor(person.id).withValues(alpha: 0.25),
          child: Text(personInitial(person.name),
              style: TextStyle(
                  color: personColor(person.id), fontWeight: FontWeight.bold)),
        ),
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
    final controller = TextEditingController(text: person?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(person == null ? 'Новый участник' : 'Изменить имя'),
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
    if (name == null || name.isEmpty) return;
    if (person == null) {
      repo.addPerson(name);
    } else {
      repo.renamePerson(person, name);
    }
    setState(() {});
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
