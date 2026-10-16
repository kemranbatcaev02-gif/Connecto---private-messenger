import 'package:flutter/material.dart';
import '../icons.dart';

import '../theme.dart';

/// Архив чатов — появится в следующей версии.
class ArchivedScreen extends StatelessWidget {
  const ArchivedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.archive, size: 48, color: subtleText(context)),
            const SizedBox(height: 12),
            Text('Архив пуст', style: TextStyle(color: subtleText(context))),
          ],
        ),
      ),
    );
  }
}
