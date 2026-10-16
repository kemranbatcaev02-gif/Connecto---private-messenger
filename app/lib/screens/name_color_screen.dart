import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Цвет своего имени в шапке чатов и профиле.
class NameColorScreen extends StatelessWidget {
  const NameColorScreen({super.key});

  static const _colors = [
    Color(0xFF7C6CFF), Color(0xFF3B82F6), Color(0xFF10B981),
    Color(0xFFEC4899), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFF14B8A6), Color(0xFFA855F7), Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final current = appState.nameColor;
        final name = appState.displayName.isEmpty ? 'Ты' : appState.displayName;
        return Scaffold(
          appBar: AppBar(title: const Text('Цвет имени')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
                child: Row(
                  children: [
                    Avatar(name: name, url: appState.avatarUrl, size: 46, useAccent: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: current ?? Theme.of(context).colorScheme.onSurface),
                        child: Text(name),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _dot(context, null, current == null),
                    for (final c in _colors)
                      _dot(context, c, current?.toARGB32() == c.toARGB32()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dot(BuildContext context, Color? c, bool sel) {
    return Pressable(
      onTap: () => appState.setNameColor(c),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: c ?? Theme.of(context).colorScheme.onSurface,
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? appState.accent : Colors.transparent, width: 3),
        ),
        child: sel
            ? Icon(AppIcons.check,
                color: c == null ? Theme.of(context).scaffoldBackgroundColor : Colors.white)
            : null,
      ),
    );
  }
}
