import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workoutlog/data.dart';
import 'package:workoutlog/main.dart';
import 'package:workoutlog/trainer_screen.dart';

void main() {
  testWidgets('приложение запускается и показывает заголовок',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Repository.instance.init();
    await tester.pumpWidget(const WorkoutLogApp());
    await tester.pumpAndSettle();
    expect(find.text('Журнал тренировок'), findsWidgets);
  });

  testWidgets('тренер: без участников — подсказка, с участником — анкета',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = Repository.instance;
    repo.people.clear();
    repo.exercises.clear();
    repo.sessions.clear();
    repo.trainerProfiles.clear();
    await repo.init();

    await tester.pumpWidget(const MaterialApp(home: TrainerScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('добавьте участников'), findsOneWidget);

    repo.addPerson('Паша');
    // key — чтобы State пересоздался, как при повторном открытии экрана.
    await tester.pumpWidget(
        const MaterialApp(home: TrainerScreen(key: ValueKey('pasha'))));
    await tester.pumpAndSettle();
    expect(find.text('Анкета: Паша'), findsOneWidget);
    expect(find.text('Пройти анкету'), findsOneWidget);
  });
}
