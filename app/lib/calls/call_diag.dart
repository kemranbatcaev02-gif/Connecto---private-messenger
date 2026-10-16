import 'dart:io';

import '../platform.dart';

/// Журнал звонков на компьютере: какие устройства выбраны, уходит ли звук,
/// какой кодек видео, сколько памяти занято. Пишется в connecto_call.log рядом
/// с Connecto.exe (или в %APPDATA%\Connecto), чтобы разбирать проблемы по факту.
class CallDiag {
  CallDiag._();

  static File? _file;
  static bool _tried = false;

  static void log(String s) {
    if (!isDesktop) return;
    try {
      final f = _file ?? _open();
      if (f == null) return;
      final t = DateTime.now().toIso8601String();
      f.writeAsStringSync('${t.substring(0, t.length > 23 ? 23 : t.length)}  $s\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  /// Сколько памяти занимает приложение (МБ).
  static int rssMb() {
    try {
      return ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {
      return -1;
    }
  }

  static File? _open() {
    if (_tried) return _file;
    _tried = true;
    final dirs = <String>[];
    try {
      dirs.add(File(Platform.resolvedExecutable).parent.path);
    } catch (_) {}
    final appData = Platform.environment['APPDATA'];
    if (appData != null) dirs.add('$appData${Platform.pathSeparator}Connecto');
    for (final d in dirs) {
      try {
        Directory(d).createSync(recursive: true);
        final f = File('$d${Platform.pathSeparator}connecto_call.log');
        // старый большой журнал начинаем заново
        if (f.existsSync() && f.lengthSync() > 4 * 1024 * 1024) f.deleteSync();
        f.writeAsStringSync('\n===== Connecto запущен =====\n', mode: FileMode.append);
        _file = f;
        return f;
      } catch (_) {}
    }
    return null;
  }
}
