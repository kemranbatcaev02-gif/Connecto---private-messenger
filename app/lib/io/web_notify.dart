/// Уведомления браузера (веб-версия). На телефоне и компьютере — пустышки.
library;

export 'web_notify_stub.dart' if (dart.library.js_interop) 'web_notify_web.dart';
