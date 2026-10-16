import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: subtleText(context).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.shoppingBag,
                  size: 36,
                  color: subtleText(context).withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Скоро.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: subtleText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
