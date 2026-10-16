import 'package:flutter/material.dart';

import 'create_channel_screen.dart';

/// Новая группа — та же форма, что и у канала. Возвращает созданный чат.
class CreateGroupScreen extends StatelessWidget {
  const CreateGroupScreen({super.key});
  @override
  Widget build(BuildContext context) => const CreateChatForm(channel: false);
}
