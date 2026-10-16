import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'premium_screen.dart';

/// Обои чатов: картинки (часть — Premium) и градиенты.
class WallpaperScreen extends StatelessWidget {
  const WallpaperScreen({super.key});

  static const _grid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 0.58,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Обои')),
        body: CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverToBoxAdapter(child: SectionLabel('Картинки')),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverGrid(
                gridDelegate: _grid,
                delegate: SliverChildListDelegate([
                  _tile(context, -1, null),
                  for (var i = 0; i < kImageWallpapers.length; i++)
                    _imageTile(context, i, kImageWallpapers[i]),
                ]),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: SectionLabel('Градиенты')),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverGrid(
                gridDelegate: _grid,
                delegate: SliverChildListDelegate([
                  for (var i = 0; i < kWallpapers.length; i++) _tile(context, i, kWallpapers[i]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pick(BuildContext context, int index, bool locked) {
    if (locked) {
      toast(context, 'Эти обои доступны с Premium', icon: AppIcons.star);
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
      return;
    }
    appState.setWallpaper(index);
  }

  Widget _badge(bool locked) => Positioned(
        right: 7,
        top: 7,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: Icon(locked ? AppIcons.lock : AppIcons.star,
              color: locked ? Colors.white : kPremium, size: 14),
        ),
      );

  Widget _frame(BuildContext context, bool selected, Widget child) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? appState.accent : hairline(context), width: selected ? 3 : 1),
          boxShadow: selected
              ? [BoxShadow(color: appState.accent.withValues(alpha: 0.35), blurRadius: 12)]
              : null,
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(selected ? 15 : 17), child: child),
      );

  Widget _imageTile(BuildContext context, int i, ImageWallpaper w) {
    final index = kImageWallpaperBase + i;
    final selected = appState.chatWallpaper == index;
    final locked = w.premium && !appState.isPremium;
    return Pressable(
      onTap: () => _pick(context, index, locked),
      child: _frame(
        context,
        selected,
        Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(w.thumb, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
            // подпись снизу на затемнении
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Text(w.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            ),
            if (selected)
              const Center(child: Icon(AppIcons.circleCheck, color: Colors.white, size: 30)),
            if (w.premium) _badge(locked),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int index, List<Color>? colors) {
    final selected = appState.chatWallpaper == index;
    final premium = index >= kFreeWallpapers;
    final locked = premium && !appState.isPremium;
    return Pressable(
      onTap: () => _pick(context, index, locked),
      child: _frame(
        context,
        selected,
        Container(
          decoration: BoxDecoration(
            gradient: colors != null
                ? LinearGradient(
                    colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter)
                : null,
            color: colors == null ? cardColor(context) : null,
          ),
          child: Stack(
            children: [
              Center(
                child: colors == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.ban, color: subtleText(context)),
                          const SizedBox(height: 6),
                          Text('Без обоев',
                              style: TextStyle(color: subtleText(context), fontSize: 12)),
                        ],
                      )
                    : (selected
                        ? const Icon(AppIcons.circleCheck, color: Colors.white, size: 30)
                        : null),
              ),
              if (colors != null && premium) _badge(locked),
            ],
          ),
        ),
      ),
    );
  }
}
