import 'dart:ffi';

import 'package:ffi/ffi.dart' show calloc, Utf16, Utf16Pointer;
import 'package:win32/win32.dart'
    show
        CoInitializeEx,
        COINIT_APARTMENTTHREADED,
        COMObject,
        CoTaskMemFree,
        FAILED,
        IMMDevice,
        MMDeviceEnumerator;

import '../platform.dart';

export 'device_names.dart';

/// Windows: какие микрофон и динамики выбраны «по умолчанию» в системе.
///
/// flutter_webrtc без подсказки берёт просто первое устройство из списка —
/// часто это виртуальный микрофон (Steam, NVIDIA Broadcast, Voicemeeter…),
/// и собеседник ничего не слышит. Здесь спрашиваем у Windows настоящий
/// «по умолчанию». Его id совпадает с deviceId из enumerateDevices().
class WinAudio {
  WinAudio._();

  static bool _com = false;

  /// capture — микрофон, иначе динамики. null — не удалось узнать.
  static String? defaultId({required bool capture}) {
    if (!isWindows) return null;
    try {
      if (!_com) {
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        _com = true;
      }
      final en = MMDeviceEnumerator.createInstance();
      // eConsole (0) — «устройство по умолчанию», eCommunications (2) — «для связи»
      for (final role in const [0, 2]) {
        final pp = calloc<COMObject>();
        final hr = en.getDefaultAudioEndpoint(capture ? 1 : 0, role, pp.cast());
        if (FAILED(hr) || pp.ref.isNull) {
          calloc.free(pp);
          continue;
        }
        final dev = IMMDevice(pp); // память и release — на финализаторе win32
        final idp = calloc<Pointer<Utf16>>();
        try {
          if (!FAILED(dev.getId(idp)) && idp.value.address != 0) {
            final id = idp.value.toDartString();
            CoTaskMemFree(idp.value);
            if (id.isNotEmpty) return id;
          }
        } finally {
          calloc.free(idp);
        }
      }
    } catch (_) {}
    return null;
  }
}
