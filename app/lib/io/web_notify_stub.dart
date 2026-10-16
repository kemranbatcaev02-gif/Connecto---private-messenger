class WebNotify {
  WebNotify._();
  static bool get supported => false;
  static bool get granted => false;
  static bool get canAsk => false;
  static bool get pageActive => true;
  static Future<bool> ask() async => false;
  static void show(String title, String body,
      {String? icon, String? tag, void Function()? onClick}) {}
  static void close(String tag) {}
  static void setTitleBadge(int unread) {}
}
