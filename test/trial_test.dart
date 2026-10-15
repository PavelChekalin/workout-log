import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workoutlog/trial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Trial.firstLaunch = null;
    Trial.unlocked = false;
  });

  test('первый запуск запоминает дату, триал не истёк', () async {
    await Trial.init();
    expect(Trial.firstLaunch, isNotNull);
    expect(Trial.trialExpired, isFalse);
    expect(Trial.daysLeft, 30);
  });

  test('через 31 день триал истекает', () async {
    final ago = DateTime.now().subtract(const Duration(days: 31));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workout_trial_start': ago.toIso8601String(),
    });
    await Trial.init();
    expect(Trial.trialExpired, isTrue);
    expect(Trial.daysLeft, 0);
  });

  test('разблокировка кодом: регистр, пробелы и дефисы не важны', () async {
    await Trial.init();
    expect(await Trial.tryUnlock('wsl 2026'), isTrue);
    expect(Trial.unlocked, isTrue);
    // Повторный запуск — разблокировка сохраняется.
    await Trial.init();
    expect(Trial.unlocked, isTrue);

    expect(Trial.isCodeValid('WSL2026'), isTrue);
    expect(Trial.isCodeValid('чужой-код'), isFalse);
  });

  test('неверный код не разблокирует', () async {
    await Trial.init();
    expect(await Trial.tryUnlock('12345'), isFalse);
    expect(Trial.unlocked, isFalse);
  });
}
