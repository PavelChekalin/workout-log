import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workoutlog/data.dart';
import 'package:workoutlog/main.dart';
import 'package:workoutlog/onboarding_screen.dart';
import 'package:workoutlog/trainer_screen.dart';

void main() {
  testWidgets('приложение запускается: первый запуск — онбординг, потом главная',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Repository.instance.init();
    await tester.pumpWidget(const WorkoutLogApp());
    await tester.pumpAndSettle();
    // Первый запуск — приветствие тренера.
    expect(find.text('Это твой тренер в кармане'), findsOneWidget);

    // Отказались — попадаем на главный экран.
    await tester.tap(find.text('Пока без тренера'));
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

  testWidgets('онбординг: с участником — приветствие, дальше анкета',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = Repository.instance;
    repo.people.clear();
    repo.exercises.clear();
    repo.sessions.clear();
    repo.trainerProfiles.clear();
    await repo.init();
    repo.addPerson('Паша');

    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Это твой тренер в кармане'), findsOneWidget);

    await tester.tap(find.text('Дальше'));
    await tester.pumpAndSettle();
    expect(find.textContaining('шаг 1 из 7'), findsOneWidget);
    // Пометка про друзей — на первом шаге анкеты (§2).
    expect(find.textContaining('Друзей и их параметры'), findsOneWidget);
  });
}
