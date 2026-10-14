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

  testWidgets('анкета: кнопка Дальше оживает после ввода возраста',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = Repository.instance;
    repo.people.clear();
    repo.exercises.clear();
    repo.sessions.clear();
    repo.trainerProfiles.clear();
    await repo.init();
    final p = repo.addPerson('Паша');

    await tester.pumpWidget(
        MaterialApp(home: QuestionnaireScreen(personId: p.id)));
    await tester.pumpAndSettle();

    // Пустой возраст — кнопки нет (disabled).
    final btn = find.widgetWithText(FilledButton, 'Дальше');
    expect(btn, findsOneWidget);
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);

    // Ввели возраст — кнопка оживает (баг 14.10: не перерисовывалась).
    await tester.enterText(find.byType(TextField).first, '35');
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);

    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.textContaining('шаг 2 из 7'), findsOneWidget);

    // Рост и вес — та же история.
    await tester.enterText(find.byType(TextField).first, '175');
    await tester.pump();
    final btn2 = find.widgetWithText(FilledButton, 'Дальше');
    expect(tester.widget<FilledButton>(btn2).onPressed, isNotNull);
    await tester.tap(btn2);
    await tester.pumpAndSettle();
    expect(find.textContaining('шаг 3 из 7'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '80');
    await tester.pump();
    final btn3 = find.widgetWithText(FilledButton, 'Дальше');
    expect(tester.widget<FilledButton>(btn3).onPressed, isNotNull);
  });
}
