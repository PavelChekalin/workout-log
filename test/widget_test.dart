import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workoutlog/data.dart';
import 'package:workoutlog/main.dart';

void main() {
  testWidgets('приложение запускается и показывает заголовок',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Repository.instance.init();
    await tester.pumpWidget(const WorkoutLogApp());
    await tester.pumpAndSettle();
    expect(find.text('Журнал тренировок'), findsWidgets);
  });
}
