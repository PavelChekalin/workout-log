// ---------------------------------------------------------------------------
// Панель активной тренировки (§6.1): таймер, ≈ккал, следующее упражнение
// плана, счётчик подходов, напутствие тренера. Липкая полоска под шапкой —
// мимо неё можно записывать подходы.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'data.dart';
import 'kcal.dart';

/// Панель идущей тренировки. Все данные считаются снаружи (main.dart) —
/// панель только рисует.
class WorkoutPanel extends StatelessWidget {
  final int elapsedSec;
  final double? kcal;
  final bool weightKnown;

  /// Подпись под таймером: «С 18:32» + число заходов, если был разрыв.
  final String timeText;

  /// Участники, у кого известен вес (для калорий и переключения).
  final List<Person> people;
  final String selectedPersonId;
  final ValueChanged<String> onSelectPerson;

  final String planText;
  final int setsCount;
  final String trainerLine;
  final VoidCallback onEnd;

  const WorkoutPanel({
    super.key,
    required this.elapsedSec,
    required this.kcal,
    required this.weightKnown,
    this.timeText = '',
    required this.people,
    required this.selectedPersonId,
    required this.onSelectPerson,
    required this.planText,
    required this.setsCount,
    required this.trainerLine,
    required this.onEnd,
  });

  String get _timer => ruDurationWords(elapsedSec);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 20),
              const SizedBox(width: 6),
              // Фраза вместо цифр (правка Паши 14.10): «Вы занимаетесь …».
              Expanded(
                child: Text('Вы занимаетесь $_timer',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onEnd,
                child: const Text('Завершить'),
              ),
            ],
          ),
          if (weightKnown)
            Text(
              '≈ ${kcal == null ? '…' : kcal!.round()} ккал',
              style: theme.textTheme.titleMedium,
            ),
          if (timeText.isNotEmpty)
            Text(timeText, style: theme.textTheme.bodySmall),
          if (weightKnown)
            Text('калории — грубая оценка, силовая ±25–40%',
                style: theme.textTheme.bodySmall),
          if (!weightKnown)
            Text('калории посчитаем, когда в анкете будет вес',
                style: theme.textTheme.bodySmall),
          if (people.length > 1) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: people
                    .map((p) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(p.name),
                            selected: p.id == selectedPersonId,
                            onSelected: (_) => onSelectPerson(p.id),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(planText, style: theme.textTheme.bodyMedium),
          Text('Подходов записано сегодня: $setsCount',
              style: theme.textTheme.bodySmall),
          if (trainerLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(trainerLine,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
