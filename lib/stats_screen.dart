import 'package:flutter/material.dart';

import 'data.dart';
import 'ui.dart';

/// Статистика по упражнению:
/// 1) сверху — по каждому участнику: эта неделя, прошлая, рекорд за всё время;
/// 2) ниже — история по датам (новые сверху).
class StatsScreen extends StatefulWidget {
  final String? initialExerciseId;
  const StatsScreen({super.key, this.initialExerciseId});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final repo = Repository.instance;
  String? selectedId;

  @override
  void initState() {
    super.initState();
    if (repo.exercises.isNotEmpty) {
      selectedId = widget.initialExerciseId != null &&
              repo.exercises.any((e) => e.id == widget.initialExerciseId)
          ? widget.initialExerciseId
          : repo.exercises.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: repo.exercises.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Сначала добавьте упражнения на главном экране.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Упражнение:',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  value: selectedId,
                  isExpanded: true,
                  items: repo.exercises
                      .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedId = v),
                ),
                const SizedBox(height: 16),
                if (repo.people.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Нет участников — добавьте их на главном экране.',
                        textAlign: TextAlign.center),
                  )
                else
                  ...repo.people.map(_personCard),
                if (repo.people.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Прогресс — лучший вес',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _progressSection(),
                ],
                const SizedBox(height: 24),
                Text('История',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._history(),
              ],
            ),
    );
  }

  Widget _personCard(Person person) {
    final exerciseId = selectedId;
    if (exerciseId == null) return const SizedBox.shrink();

    final thisStart = weekStart(DateTime.now());
    final lastStart = thisStart.subtract(const Duration(days: 7));

    final thisWeek = _setsInWeek(exerciseId, person.id, thisStart);
    final lastWeek = _setsInWeek(exerciseId, person.id, lastStart);
    final record = repo.personalRecord(exerciseId, person.id);
    final color = personColor(person.id);

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withValues(alpha: 0.25),
                  child: Text(personInitial(person.name),
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Text(person.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statCell('Эта неделя', thisWeek, color),
                ),
                Expanded(
                  child: _statCell('Прошлая', lastWeek, color),
                ),
                Expanded(
                  child: _statCell('Рекорд', record == null ? [] : [record],
                      color,
                      icon: Icons.emoji_events),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String title, List<SetEntry> sets, Color color,
      {IconData? icon}) {
    final best = _best(sets);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
            ],
            Text(title,
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          sets.isEmpty ? '—' : '${sets.length} подх.',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        Text(
          best == null ? '' : fmtSet(best),
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15, color: color),
        ),
      ],
    );
  }

  List<Widget> _history() {
    final exerciseId = selectedId;
    if (exerciseId == null) return const [];

    final list = repo.sessions
        .where((s) => s.exerciseId == exerciseId && s.sets.isNotEmpty)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (list.isEmpty) {
      return [
        Text('Записей пока нет.',
            style: TextStyle(color: Theme.of(context).disabledColor)),
      ];
    }

    return list.map((s) {
      final person = repo.people.where((p) => p.id == s.personId).toList();
      final name = person.isEmpty ? '—' : person.first.name;
      final setsStr = s.sets.map((e) => fmtSet(e)).join('   ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatDateShortRu(DateTime.parse(s.date)),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text('$name: $setsStr'),
          ],
        ),
      );
    }).toList();
  }

  /// Подходы человека за неделю, начинающуюся с [start].
  List<SetEntry> _setsInWeek(String exerciseId, String personId, DateTime start) {
    final end = start.add(const Duration(days: 7));
    final result = <SetEntry>[];
    for (final s in repo.sessions) {
      if (s.exerciseId != exerciseId ||
          s.personId != personId ||
          s.sets.isEmpty) {
        continue;
      }
      final d = DateTime.parse(s.date);
      if (!d.isBefore(start) && d.isBefore(end)) {
        result.addAll(s.sets);
      }
    }
    return result;
  }

  /// Лучший подход: по весу × повторениям.
  SetEntry? _best(List<SetEntry> sets) {
    SetEntry? best;
    var score = -1.0;
    for (final s in sets) {
      final v = (s.weight ?? 0) * s.reps;
      if (best == null || v > score) {
        best = s;
        score = v;
      }
    }
    return best;
  }

  /// График «лучший вес по датам» — по линии на каждого участника.
  Widget _progressSection() {
    final exerciseId = selectedId;
    if (exerciseId == null) return const SizedBox.shrink();

    final dates = <String>{};
    for (final s in repo.sessions) {
      if (s.exerciseId == exerciseId && s.sets.any((e) => e.weight != null)) {
        dates.add(s.date);
      }
    }
    if (dates.isEmpty) {
      return Text(
        'Пока нет данных с весом — график появится, когда будете записывать кг.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final sorted = dates.toList()..sort();

    final series = repo.people.map((p) {
      final values = <double?>[];
      for (final d in sorted) {
        double? best;
        for (final s in repo.sessions) {
          if (s.exerciseId != exerciseId ||
              s.personId != p.id ||
              s.date != d) {
            continue;
          }
          for (final e in s.sets) {
            final w = e.weight;
            if (w == null) continue;
            if (best == null || w > best) best = w;
          }
        }
        values.add(best);
      }
      return _Series(p.name, personColor(p.id), values);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 190,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ChartPainter(series, Theme.of(context).colorScheme, sorted),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(s.label, style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Одна линия на графике: подпись, цвет и значения (null — нет данных в точке).
class _Series {
  final String label;
  final Color color;
  final List<double?> values;
  _Series(this.label, this.color, this.values);
}

/// Простой график без сторонних библиотек: сетка + ломаные линии по людям.
class _ChartPainter extends CustomPainter {
  final List<_Series> series;
  final ColorScheme scheme;
  final List<String> dates;

  _ChartPainter(this.series, this.scheme, this.dates);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, right = 12.0, top = 10.0, bottom = 22.0;
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    if (plotW <= 0 || plotH <= 0) return;

    final all = <double>[];
    for (final s in series) {
      for (final v in s.values) {
        if (v != null) all.add(v);
      }
    }
    if (all.isEmpty) return;

    var minV = all.reduce((a, b) => a < b ? a : b);
    var maxV = all.reduce((a, b) => a > b ? a : b);
    if (minV == maxV) {
      minV -= 5;
      maxV += 5;
    }
    final pad = (maxV - minV) * 0.12;
    minV -= pad;
    maxV += pad;

    final grid = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: scheme.onSurfaceVariant, fontSize: 10);

    void drawLabel(String t, Offset o, {bool right = false, bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = right
          ? o.dx - tp.width
          : center
              ? o.dx - tp.width / 2
              : o.dx;
      tp.paint(canvas, Offset(dx, o.dy - tp.height / 2));
    }

    String fmtV(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

    final n = series.isEmpty ? 0 : series.first.values.length;
    double yOf(double v) => top + (maxV - v) / (maxV - minV) * plotH;
    double xOf(int i) =>
        n <= 1 ? left + plotW / 2 : left + plotW * i / (n - 1);

    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = top + plotH * frac;
      canvas.drawLine(Offset(left, y), Offset(left + plotW, y), grid);
      final v = maxV - (maxV - minV) * frac;
      drawLabel(fmtV(v), Offset(left - 6, y), right: true);
    }

    for (final s in series) {
      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final dot = Paint()..color = s.color;
      final path = Path();
      var started = false;
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          started = false;
          continue;
        }
        final p = Offset(xOf(i), yOf(v));
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawCircle(p, 3, dot);
      }
      canvas.drawPath(path, line);
    }

    // Подписи по оси X: первая и последняя даты.
    if (dates.isNotEmpty) {
      String shortDate(String iso) {
        final p = iso.split('-');
        if (p.length < 3) return iso;
        return '${int.parse(p[2])}.${int.parse(p[1])}';
      }

      drawLabel(shortDate(dates.first),
          Offset(xOf(0), size.height - 8), center: true);
      if (n > 1) {
        drawLabel(shortDate(dates.last),
            Offset(xOf(n - 1), size.height - 8), center: true);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
