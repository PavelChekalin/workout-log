// ---------------------------------------------------------------------------
// Онбординг (§2): приветствие → анкета → «включить тренера?» →
// «напоминать о тренировках?» → готово.
//
// Показывается один раз (флаг onboarded в данных): при первом открытии и при
// обновлении приложения. Отказ от тренера — нормальный выбор: можно просто
// пользоваться журналом, тренер вернётся кнопкой на главном экране.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'data.dart';
import 'reminders.dart';
import 'trainer_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final repo = Repository.instance;

  /// 0 — приветствие, 1 — имя (только если участников нет),
  /// 2 — анкета (отдельный экран), 3 — включить тренера?,
  /// 4 — напоминать?, 5 — готово.
  int step = 0;
  final nameCtrl = TextEditingController();
  String? personId;

  @override
  void initState() {
    super.initState();
    // Приветствие показываем всегда; если участники уже есть — имя не спрашиваем.
    if (repo.people.isNotEmpty) {
      personId = repo.people.first.id;
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  /// Завершить онбординг: флаг больше не показывать.
  void _finish() {
    repo.setTrainerOnboarded();
    Navigator.pop(context);
  }

  Future<void> _openQuestionnaire() async {
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => QuestionnaireScreen(personId: personId)));
    if (!mounted) return;
    if (ok == true) {
      setState(() => step = 3);
    } else {
      // Анкету закрыли — уходим без тренера, больше не навязываемся.
      _finish();
    }
  }

  Future<void> _enableReminders() async {
    await Reminders.init();
    final ok = await Reminders.requestPermission();
    if (ok) {
      await repo.setReminders(true, time: '18:00');
      await Reminders.reschedule(repo, enabled: true, hour: 18, minute: 0);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Разрешение на уведомления не выдано — напоминания не '
              'включились. Разреши их в настройках телефона, когда захочешь.')));
    }
    if (mounted) setState(() => step = 5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (step) {
          0 => _welcome(),
          1 => _nameStep(),
          2 => const SizedBox.shrink(), // анкета — отдельный экран
          3 => _trainerQuestion(),
          4 => _remindersQuestion(),
          _ => _done(),
        },
      ),
    );
  }

  Widget _welcome() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.fitness_center, size: 64),
          const SizedBox(height: 16),
          Text('Это твой тренер в кармане',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
            'Всё работает офлайн, без интернета. Журнал тренировок '
            'останется как есть — тренер только поможет: подберёт '
            'программу, подскажет веса и подбадривает.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              if (repo.people.isEmpty) {
                setState(() => step = 1); // сначала спросим имя
              } else {
                setState(() => step = 2);
                _openQuestionnaire();
              }
            },
            child: const Text('Дальше'),
          ),
          TextButton(
            onPressed: _finish,
            child: const Text('Пока без тренера'),
          ),
        ],
      ),
    );
  }

  /// Имя первого участника — если в приложении ещё никого нет.
  Widget _nameStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Как тебя зовут?',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Это имя для твоей анкеты и программ. Друзей добавишь '
            'позже в Настройках — у каждого своя анкета.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final p = repo.addPerson(name);
              setState(() {
                personId = p.id;
                step = 2;
              });
              _openQuestionnaire();
            },
            child: const Text('Дальше'),
          ),
        ],
      ),
    );
  }

  Widget _trainerQuestion() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Включить тренера?',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
            'Тренер предложит программу, будет вести по ней, '
            'подсказывать веса и подбадривать.\n\n'
            'Можно заниматься и без него — просто журнал.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => setState(() => step = 4),
            child: const Text('Да, включаем'),
          ),
          TextButton(
            onPressed: _finish,
            child: const Text('Пока без тренера'),
          ),
        ],
      ),
    );
  }

  Widget _remindersQuestion() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Напоминать о тренировках?',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
            'Приложение напишет в дни тренировок в выбранное время. '
            'Телефон спросит разрешение на уведомления.\n\n'
            'Выключить — когда угодно, в Настройках.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _enableReminders,
            child: const Text('Включить (18:00)'),
          ),
          TextButton(
            onPressed: () => setState(() => step = 5),
            child: const Text('Не нужно'),
          ),
        ],
      ),
    );
  }

  Widget _done() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_outline, size: 64),
          const SizedBox(height: 16),
          Text('Готово!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Дальше — подбор программы: тренер посоветует, но решать '
            'всегда за тобой.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              repo.setTrainerOnboarded();
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TrainerScreen()));
            },
            child: const Text('К тренеру — выбрать программу'),
          ),
          TextButton(
            onPressed: _finish,
            child: const Text('Позже сам'),
          ),
        ],
      ),
    );
  }
}
