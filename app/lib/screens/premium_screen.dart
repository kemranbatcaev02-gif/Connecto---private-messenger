import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/buy_contact.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/ui.dart';
import 'help_screen.dart';
import 'wallet_screen.dart';

/// Connecto Premium: статус, возможности, активация промокода.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});
  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _perks = [];
  bool _loading = true;
  final _code = TextEditingController();
  bool _redeeming = false;
  late final AnimationController _glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat(reverse: true);

  static const _fallback = [
    {'icon': 'star', 'title': 'Значок Premium', 'text': 'Звезда рядом с именем'},
    {'icon': 'heart', 'title': '3 реакции на сообщение', 'text': 'Вместо одной'},
    {'icon': 'upload', 'title': 'Файлы до 500 МБ', 'text': 'Вместо 100 МБ'},
    {'icon': 'users', 'title': 'До 6 аккаунтов', 'text': 'Вместо 3'},
    {'icon': 'pin', 'title': 'До 10 закреплённых чатов', 'text': 'Вместо 5'},
    {'icon': 'bot', 'title': 'До 20 ботов', 'text': 'Вместо 5'},
    {'icon': 'text', 'title': 'Описание до 300 символов', 'text': 'Вместо 140'},
    {'icon': 'palette', 'title': 'Эксклюзивные цвета и обои', 'text': 'Акценты и фоны чатов'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _glow.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.premiumStatus();
      if (!mounted) return;
      setState(() {
        _perks = ((d['perks'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
      appState.refreshMe();
    } catch (_) {
      if (mounted) {
        setState(() {
          _perks = _fallback.map((e) => Map<String, dynamic>.from(e)).toList();
          _loading = false;
        });
      }
    }
  }

  Future<void> _redeem() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      toast(context, 'Введи промокод', error: true);
      return;
    }
    setState(() => _redeeming = true);
    try {
      final u = await Api.redeemPromo(code);
      appState.applyServerUser(u);
      if (!mounted) return;
      _code.clear();
      FocusScope.of(context).unfocus();
      final days = (u['promo_days'] as num?)?.toInt() ?? 1;
      final coins = (u['promo_coins'] as num?)?.toInt() ?? 0;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: days > 0
              ? const Icon(AppIcons.star, color: kPremium, size: 48)
              : const CoinIcon(size: 48),
          title: Text(days > 0 ? 'Premium активирован!' : '+$coins коинов!'),
          content: Text([
            if (days > 0 && appState.premiumUntil != null)
              'Действует до ${_date(appState.premiumUntil!)}.',
            if (days > 0 && coins > 0) 'И ещё +$coins коинов на балансе.',
            'Спасибо, что ты с нами 💛',
          ].join(' ')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Супер')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  IconData _icon(String? key) => switch (key) {
        'star' => AppIcons.star,
        'heart' => AppIcons.heart,
        'upload' => AppIcons.upload,
        'users' => AppIcons.users,
        'pin' => AppIcons.pin,
        'bot' => AppIcons.bot,
        'text' => AppIcons.type,
        'palette' => AppIcons.palette,
        'layers' => AppIcons.layers,
        'bubble' => AppIcons.bubble,
        'transition' => AppIcons.transition,
        'waves' => AppIcons.waves,
        'cover' => AppIcons.cover,
        'emoji' => AppIcons.emoji,
        'ring' => AppIcons.circle,
        'nav' => AppIcons.navBar,
        'icons' => AppIcons.brushSpark,
        'effects' => AppIcons.partyPopper,
        'capsule' => AppIcons.timer,
        'stories' => AppIcons.stories,
        'stealth' => AppIcons.incognito,
        'coins' => AppIcons.coin,
        'gift' => AppIcons.gift,
        'frame' => AppIcons.frame,
        _ => AppIcons.sparkles,
      };

  static const _perkColors = [
    Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF3B82F6), Color(0xFF10B981),
    Color(0xFF8B5CF6), Color(0xFF14B8A6), Color(0xFFF97316), Color(0xFFE11D48),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final on = appState.isPremium;
        final until = appState.premiumUntil;
        return Scaffold(
          appBar: AppBar(),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            children: [
              Center(
                child: AnimatedBuilder(
                animation: _glow,
                builder: (_, child) => Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: kPremiumGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: kPremium.withValues(alpha: 0.25 + 0.3 * _glow.value),
                          blurRadius: 24 + 16 * _glow.value,
                          spreadRadius: 2),
                    ],
                  ),
                  child: child,
                ),
                child: const Icon(AppIcons.star, color: Colors.white, size: 64),
              ),
              ),
              const SizedBox(height: 18),
              const Text('Connecto Premium',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                  on
                      ? (until != null
                          ? 'Активен до ${_date(until)}'
                          : 'Активен')
                      : 'Больше возможностей и поддержка развития Connecto',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: on ? kSuccess : subtleText(context),
                      fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
              const SizedBox(height: 24),
              if (_loading)
                const ListSkeleton(count: 4)
              else
                SectionCard(children: [
                  for (var i = 0; i < _perks.length; i++)
                    FadeSlideIn(
                      delayMs: 40 * i,
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _perkColors[i % _perkColors.length],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_icon(_perks[i]['icon'] as String?),
                              color: Colors.white, size: 21),
                        ),
                        title: Text((_perks[i]['title'] as String?) ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text((_perks[i]['text'] as String?) ?? '',
                            style: TextStyle(color: subtleText(context))),
                      ),
                    ),
                ]),
              const SizedBox(height: 22),
              const SectionLabel('Промокод'),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _code,
                      hint: 'Например, CONNECTO30',
                      icon: AppIcons.ticket,
                      onSubmitted: (_) => _redeem(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: PrimaryButton(
                        label: 'Применить',
                        gradient: kPremiumGradient,
                        loading: _redeeming,
                        onTap: _redeem),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CoinIcon(size: 30),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Premium за кристаллы',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        CoinAmount(appState.coins, size: 14),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final p in const [
                      ['1 месяц', 299, ''],
                      ['3 месяца', 799, '−11%'],
                      ['12 месяцев', 2499, '−30%'],
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(p[0] as String,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            if ((p[2] as String).isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(p[2] as String,
                                  style: const TextStyle(
                                      color: kSuccess, fontWeight: FontWeight.w900, fontSize: 12.5)),
                            ],
                            const Spacer(),
                            CoinAmount(p[1] as int, size: 13.5),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text('Premium можно купить себе или подарить другу. '
                        'Кристаллы дают ежедневный бонус, промокоды и обмен подарков.',
                        style: TextStyle(color: subtleText(context), height: 1.4, fontSize: 13)),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Купить Premium за рубли',
                      icon: AppIcons.creditCard,
                      gradient: kPremiumGradient,
                      onTap: () => showPremiumRubPicker(context),
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: 'Купить за кристаллы',
                      icon: AppIcons.wallet,
                      gradient: accentGradient(appState.accent),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const WalletScreen())),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => openSupportChat(context),
                        icon: const Icon(AppIcons.messageCircle, size: 18),
                        label: const Text('Вопрос по Premium? Напиши в поддержку'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
