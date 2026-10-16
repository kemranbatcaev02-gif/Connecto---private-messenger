import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _lang = 'Русский';
  static const _langs = [
    ['Русский', 'Russian'],
    ['English', 'English'],
    ['Español', 'Spanish'],
    ['Deutsch', 'German'],
    ['Français', 'French'],
    ['Türkçe', 'Turkish'],
    ['Українська', 'Ukrainian'],
    ['العربية', 'Arabic'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Язык')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
                color: cardColor(context),
                borderRadius: BorderRadius.circular(kRadiusL)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final l in _langs)
                  ListTile(
                    title: Text(l[0],
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(l[1],
                        style: TextStyle(color: subtleText(context), fontSize: 13)),
                    trailing: _lang == l[0]
                        ? Icon(AppIcons.check, color: appState.accent)
                        : null,
                    onTap: () => setState(() => _lang = l[0]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
