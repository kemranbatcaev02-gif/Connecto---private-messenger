import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';

/// Аккуратная плашка «функция в разработке» вместо серого SnackBar.
void showSoonSheet(BuildContext context, String title, {String? subtitle}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(kRadiusL)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: appState.accent.withOpacity(0.14),
                    shape: BoxShape.circle),
                child: Icon(AppIcons.hammer, color: appState.accent, size: 30),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(subtitle ?? 'Функция в разработке — скоро добавим 🙌',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtleText(context), height: 1.4)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: appState.accent,
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Понятно'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
