/// Микрофон/динамики «по умолчанию» в Windows (через COM), в браузере — заглушка.
library;

export 'win_audio_stub.dart' if (dart.library.ffi) 'win_audio_ffi.dart';
