/// Браузер: системные аудиоустройства Windows недоступны.
library;

export 'device_names.dart';

class WinAudio {
  WinAudio._();
  static String? defaultId({required bool capture}) => null;
}
