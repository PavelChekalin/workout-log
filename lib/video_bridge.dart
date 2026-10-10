import 'package:flutter/services.dart';

/// Разговор с телефоном про видео: открыть штатную камеру, поделиться,
/// открыть файл, удалить его. Если телефон чего-то не умеет — возвращаем
/// ошибку, а приложение показывает спокойное сообщение.
class VideoBridge {
  static const MethodChannel _ch = MethodChannel('workout/video');

  /// Открыть штатную камеру для записи видео.
  /// [toGallery] true — видео уйдёт в Галерею, false — в память приложения.
  /// Возвращает путь к файлу или null, если запись отменили.
  static Future<String?> record({required bool toGallery}) async {
    try {
      return await _ch.invokeMethod<String>('record', {'toGallery': toGallery});
    } on PlatformException catch (e) {
      throw VideoException(e.message ?? 'Камера недоступна');
    } on MissingPluginException {
      throw VideoException('На этой платформе видео пока не работает');
    }
  }

  /// Выбрать уже записанное видео из памяти телефона (чужой файл —
  /// в журнал кладём только путь, файл не трогаем). null — отменили.
  static Future<String?> pick() async {
    try {
      return await _ch.invokeMethod<String>('pick');
    } on PlatformException catch (e) {
      throw VideoException(e.message ?? 'Не получилось выбрать видео');
    } on MissingPluginException {
      throw VideoException('На этой платформе видео пока не работает');
    }
  }

  /// Открыть видео в плеере телефона.
  static Future<void> open(String path) async {
    try {
      await _ch.invokeMethod<void>('open', {'path': path});
    } catch (_) {
      throw VideoException('Не получилось открыть видео');
    }
  }

  /// Открыть системный шаринг («Поделиться»).
  static Future<void> share(String path) async {
    try {
      await _ch.invokeMethod<void>('share', {'path': path});
    } catch (_) {
      throw VideoException('Не получилось поделиться видео');
    }
  }

  /// Удалить файл видео с телефона. true — файл удалён.
  static Future<bool> delete(String path) async {
    try {
      final ok = await _ch.invokeMethod<bool>('delete', {'path': path});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Причина, которую можно показать человеку словами.
class VideoException implements Exception {
  final String message;
  VideoException(this.message);

  @override
  String toString() => message;
}
