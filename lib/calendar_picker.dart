import 'package:flutter/material.dart';

import 'data.dart';

/// Окно-календарь: перелистываются месяцы, дни с записями помечены точкой,
/// дни из будущего недоступны. Возвращает выбранную дату (или null).
Future<DateTime?> showDayCalendar(
  BuildContext context, {
  required Set<String> marked,
  required DateTime initial,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(
      child: _DayCalendar(marked: marked, initial: initial),
    ),
  );
}

class _DayCalendar extends StatefulWidget {
  const _DayCalendar({required this.marked, required this.initial});

  final Set<String> marked;
  final DateTime initial;

  @override
  State<_DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends State<_DayCalendar> {
  late DateTime _month; // первый день показанного месяца

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initial.year, widget.initial.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  static String _monthName(int m) => const [
        'январь', 'февраль', 'март', 'апрель',
        'май', 'июнь', 'июль', 'август',
        'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
      ][m - 1];

  static const List<String> _dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    final cells = <Widget>[
      for (var i = 0; i < firstWeekday - 1; i++) const SizedBox.shrink(),
    ];
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isFuture = date.isAfter(today);
      final isMarked = !isFuture && widget.marked.contains(isoDate(date));
      final isToday = date == today;

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isFuture ? null : () => Navigator.pop(context, date),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.primary, width: 1.6),
                      )
                    : null,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isFuture
                        ? cs.outline.withValues(alpha: 0.5)
                        : cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isMarked ? cs.primary : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Предыдущий месяц',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    '${_monthName(_month.month)} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Следующий месяц',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.05,
              children: [
                for (final d in _dayNames)
                  Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ...cells,
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }
}