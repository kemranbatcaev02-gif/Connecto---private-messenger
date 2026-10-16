import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buy_contact.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/ui.dart';
import '../widgets/user_picker.dart';
import 'chat_screen.dart' show playEffect;

/// Кошелёк коинов: баланс, ежедневный бонус, пополнение, Premium за коины, история.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _w;
  List<dynamic>? _history;
  String? _error;
  bool _claiming = false;
  String? _pendingPayment;

  int get _balance => (_w?['balance'] as num?)?.toInt() ?? appState.coins;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // вернулись из браузера после оплаты — проверяем платёж
    if (state == AppLifecycleState.resumed && _pendingPayment != null) _checkPayment();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.wallet(), Api.coinHistory()]);
      if (!mounted) return;
      setState(() {
        _w = r[0] as Map<String, dynamic>;
        _history = r[1] as List<dynamic>;
        _error = null;
      });
      appState.coins = _balance;
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  // ── ежедневный бонус ──

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final r = await Api.claimDaily();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      playEffect(context, 'confetti');
      toast(context, '+${r['reward']} кристаллов · возвращайся завтра!', icon: AppIcons.coin);
      await _load();
      appState.refreshMe();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  // ── пополнение ──

  /// Пока нет онлайн-оплаты — покупка через продавца (личка в Connecto или Telegram).
  void _contact(Map<String, dynamic> p) {
    showBuyContact(context,
        item: '${fmtCoins((p['coins'] as num).toInt())} кристаллов',
        price: '${p['rub']} ₽',
        seller: (_w?['seller'] as Map?)?.cast<String, dynamic>());
  }

  Future<void> _buy(Map<String, dynamic> p) async {
    if (_w?['payments_enabled'] != true) {
      _contact(p);
      return;
    }
    try {
      final r = await Api.buyCoins(p['id'] as String);
      final url = r['confirmation_url'] as String?;
      if (url == null || url.isEmpty) throw ApiException('Платёж не создан, попробуй ещё раз');
      _pendingPayment = r['id'] as String;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (mounted) {
        toast(context, 'После оплаты кристаллы придут автоматически', icon: AppIcons.coin);
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.status == 503) {
        _contact(p);
      } else {
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _checkPayment() async {
    final id = _pendingPayment;
    if (id == null) return;
    for (var i = 0; i < 10; i++) {
      try {
        final r = await Api.paymentStatus(id);
        final st = r['status'];
        if (st == 'succeeded') {
          _pendingPayment = null;
          if (!mounted) return;
          HapticFeedback.heavyImpact();
          playEffect(context, 'money');
          toast(context, '+${r['coins']} кристаллов! Спасибо 💎', icon: AppIcons.coin);
          await _load();
          appState.refreshMe();
          return;
        }
        if (st == 'canceled') {
          _pendingPayment = null;
          if (mounted) toast(context, 'Оплата отменена', error: true);
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
    }
  }

  Future<void> _promo() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Промокод'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'CONNECTO-XXXX'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Активировать', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    try {
      final r = await Api.redeemPromo(code);
      appState.applyServerUser(r);
      if (!mounted) return;
      final coins = (r['promo_coins'] as num?)?.toInt() ?? 0;
      final days = (r['promo_days'] as num?)?.toInt() ?? 0;
      HapticFeedback.heavyImpact();
      playEffect(context, coins > 0 ? 'money' : 'confetti');
      toast(
          context,
          [
            if (coins > 0) '+$coins коинов',
            if (days > 0) 'Premium на $days дн.',
          ].join(' и '),
          icon: AppIcons.ticket);
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  // ── Premium за коины ──

  Future<void> _premium(Map<String, dynamic> plan, {required bool gift}) async {
    String? toId;
    String who = 'себе';
    if (gift) {
      final users = await pickUsers(context,
          title: 'Кому подарить Premium', multi: false, exclude: {appState.myUserId ?? ''});
      if (users == null || users.isEmpty || !mounted) return;
      toId = users.first['id'] as String;
      who = userName(users.first);
    }
    final price = (plan['coins'] as num).toInt();
    final ok = await confirm(context,
        title: 'Premium на ${plan['title']} $who?',
        body: 'Спишется ${fmtCoins(price)} коинов.',
        action: 'Купить');
    if (!ok || !mounted) return;
    try {
      final r = await Api.buyPremiumWithCoins(plan['id'] as String, toUserId: toId);
      appState.applyServerUser(r);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      playEffect(context, 'fireworks');
      toast(context, gift ? 'Premium подарен: $who ⭐' : 'Premium активирован ⭐',
          icon: AppIcons.star);
      _load();
    } catch (e) {
      if (!mounted) return;
      toast(context, friendlyError(e), error: true);
    }
  }

  // ── интерфейс ──

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadiusL),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C1F38), Color(0xFF0369A1), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          const _SpinningCoin(size: 86),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _balance.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(fmtCoins(v.round()),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1)),
          ),
          const Text('кристаллов на балансе',
              style: TextStyle(color: Color(0xFFBAE6FD), fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Text(_w?['rate'] as String? ?? '100 кристаллов = 49 ₽',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _daily() {
    final d = (_w?['daily'] as Map?)?.cast<String, dynamic>();
    if (d == null) return const SizedBox();
    final rewards = ((d['rewards'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();
    final available = d['available'] == true;
    final nextDay = (d['next_day'] as num?)?.toInt() ?? 1;
    final streak = (d['streak'] as num?)?.toInt() ?? 0;
    return SectionCard(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            const IconTile(AppIcons.flame, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ежедневный бонус',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  Text(
                      streak > 0
                          ? 'Серия: ${plural(streak, 'день', 'дня', 'дней')}${d['premium_x2'] == true ? ' · ×2 Premium' : ''}'
                          : 'Заходи каждый день — награда растёт',
                      style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Row(
          children: [
            for (var i = 0; i < rewards.length; i++)
              Expanded(
                child: _DayDot(
                  day: i + 1,
                  reward: rewards[i],
                  done: i + 1 < nextDay,
                  current: available && i + 1 == nextDay,
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: PrimaryButton(
          label: available ? 'Забрать +${d['reward']}' : 'Завтра: +${d['reward']}',
          icon: available ? AppIcons.gift : AppIcons.clock,
          loading: _claiming,
          gradient: available ? kPremiumGradient : null,
          onTap: available ? _claim : null,
        ),
      ),
    ]);
  }

  Widget _packages() {
    final list = ((_w?['packages'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.35),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final coins = (p['coins'] as num).toInt();
        final disc = (p['discount'] as num?)?.toInt() ?? 0;
        final popular = p['popular'] == true;
        return FadeSlideIn(
          delayMs: 40 * i,
          child: Pressable(
            onTap: () => _buy(p),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardColor(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: popular ? kPremium : kPremium.withValues(alpha: 0.18),
                    width: popular ? 2 : 1),
                boxShadow: popular
                    ? [BoxShadow(color: kPremium.withValues(alpha: 0.25), blurRadius: 16)]
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var k = 0; k < math.min(3, 1 + i ~/ 2); k++)
                            Transform.translate(
                              offset: Offset(-8.0 * k, 0),
                              child: const CoinIcon(size: 26),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(fmtCoins(coins),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      Text('${p['rub']} ₽',
                          style: TextStyle(
                              color: subtleText(context), fontWeight: FontWeight.w700)),
                    ],
                  ),
                  if (disc > 0 || popular)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: popular ? kPremiumGradient : null,
                          color: popular ? null : kSuccess,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(popular ? 'хит · −$disc%' : '−$disc%',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _premiumPlans() {
    final plans = ((_w?['premium_plans'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return SectionCard(children: [
      for (final p in plans)
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(gradient: kPremiumGradient, shape: BoxShape.circle),
            child: const Icon(AppIcons.star, color: Colors.white),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text('Premium · ${p['title']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (((p['discount'] as num?)?.toInt() ?? 0) > 0) ...[
                const SizedBox(width: 6),
                Text('−${p['discount']}%',
                    style: const TextStyle(color: kSuccess, fontWeight: FontWeight.w900, fontSize: 12.5)),
              ],
            ],
          ),
          subtitle: CoinAmount((p['coins'] as num).toInt(), size: 13),
          trailing: PopupMenuButton<String>(
            icon: const Icon(AppIcons.chevronDown),
            onSelected: (v) {
              if (v == 'rub') {
                showBuyContact(context,
                    item: 'Premium на ${p['title']}',
                    price: '${p['rub']} ₽',
                    premium: true,
                    seller: (_w?['seller'] as Map?)?.cast<String, dynamic>());
              } else {
                _premium(p, gift: v == 'gift');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'me', child: Text('Купить себе за кристаллы')),
              const PopupMenuItem(value: 'gift', child: Text('Подарить другу')),
              if (p['rub'] != null)
                PopupMenuItem(value: 'rub', child: Text('Купить за ${p['rub']} ₽')),
            ],
          ),
          onTap: () => _premium(p, gift: false),
        ),
    ]);
  }

  Widget _historyList() {
    final h = _history;
    if (h == null) {
      return const Padding(padding: EdgeInsets.all(16), child: Shimmer(height: 60, radius: 14));
    }
    if (h.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Text('Пока пусто — забери ежедневный бонус 🙂',
            textAlign: TextAlign.center, style: TextStyle(color: subtleText(context))),
      );
    }
    return Column(
      children: [
        for (final raw in h.take(40))
          Builder(builder: (context) {
            final t = (raw as Map).cast<String, dynamic>();
            final amount = (t['amount'] as num).toInt();
            final icon = switch (t['kind']) {
              'daily' => AppIcons.flame,
              'gift' => AppIcons.gift,
              'convert' => AppIcons.swap,
              'premium' => AppIcons.star,
              'promo' => AppIcons.ticket,
              'purchase' => AppIcons.creditCard,
              _ => AppIcons.coin,
            };
            final d = parseServerTime(t['created_at'] as String? ?? '');
            return ListTile(
              dense: true,
              leading: IconTile(icon, size: 34),
              title: Text(t['title'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: d == null
                  ? null
                  : Text(
                      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} · '
                      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: subtleText(context), fontSize: 12)),
              trailing: Text('${amount > 0 ? '+' : ''}${fmtCoins(amount)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: amount > 0 ? kSuccess : Theme.of(context).colorScheme.onSurface)),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кристаллы'),
        actions: [
          IconButton(tooltip: 'Промокод', icon: const Icon(AppIcons.ticket), onPressed: _promo),
          const SizedBox(width: 4),
        ],
      ),
      body: _error != null && _w == null
          ? EmptyState(
              icon: AppIcons.wifiOff,
              mascot: 'empty_no_internet',
              title: 'Не удалось загрузить',
              subtitle: _error,
              action: TextButton(onPressed: _load, child: const Text('Повторить')))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  FadeSlideIn(child: _hero()),
                  const SizedBox(height: 16),
                  if (_w == null)
                    const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()))
                  else ...[
                    FadeSlideIn(delayMs: 60, child: _daily()),
                    const SizedBox(height: 18),
                    const SectionLabel('Пополнить'),
                    if (_w?['payments_enabled'] != true)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                        child: Row(
                           children: [
                            Icon(AppIcons.storefront, size: 16, color: subtleText(context)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Выбери пакет — оформим покупку в личке Connecto или Telegram',
                                  style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ),
                    _packages(),
                    const SizedBox(height: 18),
                    const SectionLabel('Premium за кристаллы'),
                    FadeSlideIn(delayMs: 80, child: _premiumPlans()),
                    const SizedBox(height: 18),
                    const SectionLabel('На что потратить'),
                    SectionCard(children: [
                      SettingsTile(
                          icon: AppIcons.gift,
                          title: 'Подарки друзьям',
                          subtitle: 'Открой профиль человека → «Подарок». '
                              'Дорогие подарки светятся и переливаются',
                          chevron: false),
                      SettingsTile(
                          icon: AppIcons.swap,
                          title: 'Обмен подарков',
                          subtitle: 'Подаренный подарок можно обменять на 70% его цены',
                          chevron: false),
                    ]),
                    const SizedBox(height: 18),
                    const SectionLabel('История'),
                    SectionCard(children: [_historyList()]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _DayDot extends StatelessWidget {
  final int day;
  final int reward;
  final bool done;
  final bool current;
  const _DayDot({required this.day, required this.reward, required this.done, required this.current});

  @override
  Widget build(BuildContext context) {
    final c = done || current ? kPremium : subtleText(context).withValues(alpha: 0.4);
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: current ? 38 : 32,
          height: current ? 38 : 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: done ? kPremiumGradient : null,
            color: done ? null : c.withValues(alpha: current ? 0.18 : 0.08),
            border: Border.all(color: c, width: current ? 2 : 1),
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(AppIcons.check, color: Colors.white, size: 17)
              : Text('+$reward',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: c)),
        ),
        const SizedBox(height: 4),
        Text(day == 7 ? '7 🔥' : '$day',
            style: TextStyle(fontSize: 11, color: subtleText(context), fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Монета, которая медленно вращается.
class _SpinningCoin extends StatefulWidget {
  final double size;
  const _SpinningCoin({required this.size});
  @override
  State<_SpinningCoin> createState() => _SpinningCoinState();
}

class _SpinningCoinState extends State<_SpinningCoin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    if (appState.motion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final a = _c.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(0, math.sin(a) * 3),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateY(a),
            child: child,
          ),
        );
      },
      child: CoinIcon(size: widget.size),
    );
  }
}
