/// Работа с локальными файлами одинаково на телефоне, компьютере и в браузере.
///
/// В браузере «путь к файлу» — это blob:-ссылка (её дают image_picker, record,
/// camera), поэтому картинки, видео и звук открываются как по сети, а байты
/// для загрузки на сервер читаются через XFile.
library;

export 'local_files_io.dart' if (dart.library.js_interop) 'local_files_web.dart';
