import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../theme.dart';
import '../screens/chat_screen.dart' show openDirectChat;
import 'gift_widgets.dart';
import 'ui.dart';

/// Покупка коинов и Premium через продавца, пока нет онлайн-оплаты:
/// лист с готовым текстом заказа и кнопками «Написать в Connecto» / «в Telegram».
/// (Готовый код оплаты через RollyPay — на сервере, app/routers/rollypay.py.)

const _kTelegramGradient = LinearGradient(
  colors: [Color(0xFF2AABEE), Color(0xFF1E88D0)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

Map<String, dynamic>? _shopCache;

/// Витрина: пакеты, тарифы Premium (с ценой в ₽) и контакты продавца.
Future<Map<String, dynamic>?> loadShop({bool force = false}) async {
  if (_shopCache != null && !force) return _shopCache;
  try {
    _shopCache = await Api.shop();
  } catch (_) {}
  return _shopCache;
}

String _orderText(String item, String price) {
  final nick = (appState.handle ?? '').isNotEmpty ? '@${appState.handle}' : appState.username;
  final name = appState.displayName.isNotEmpty ? ' (${appState.displayName})' : '';
  return 'Привет! Хочу купить $item за $price.\n'
      'Мой аккаунт в Connecto: $nick$name\n'
      'ID: ${appState.myUserId ?? '—'}';
}

/// Показать лист покупки. [premium] — золотое оформление вместо коина.
Future<void> showBuyContact(BuildContext context,
    {required String item, required String price, bool premium = false,
    Map<String, dynamic>? seller}) async {
  seller ??= ((await loadShop())?['seller'] as Map?)?.cast<String, dynamic>();
  if (!context.mounted) return;
  final s = seller ?? const <String, dynamic>{'telegram': 'kemq78'};
  final order = _orderText(item, price);
  final tg = (s['telegram'] as String?)?.replaceAll('@', '') ?? 'kemq78';
  final sellerId = s['user_id'] as String?;
  final itsMe = sellerId != null && sellerId == appState.myUserId;

  await showAppSheet(context, scrollable: true, builder: (ctx) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _Badge(premium: premium)),
          const SizedBox(height: 14),
          Text('Покупка: $item',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: premium ? kPremiumGradient : accentGradient(appState.accent),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(price,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 18),
          const _Step(n: 1, text: 'Напиши продавцу — текст заказа уже готов'),
          const _Step(n: 2, text: 'Оплати удобным способом: перевод или СБП'),
          _Step(
              n: 3,
              text: premium
                  ? 'Premium включится сразу после оплаты'
                  : 'Кристаллы придут на баланс сразу после оплаты'),
          const SizedBox(height: 14),
          _OrderBox(text: order),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Написать в Connecto',
            icon: AppIcons.messageCircle,
            gradient: accentGradient(appState.accent),
            onTap: () {
              if (sellerId == null) {
                toast(ctx, 'Продавец сейчас недоступен — напиши в Telegram', error: true);
                return;
              }
              if (itsMe) {
                toast(ctx, 'Это твой аккаунт продавца 🙂', icon: AppIcons.storefront);
                return;
              }
              Navigator.pop(ctx);
              openDirectChat(context, sellerId, draft: order);
            },
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Написать в Telegram',
            icon: AppIcons.send,
            gradient: _kTelegramGradient,
            onTap: () async {
              // текст дублируем в буфер: если Telegram не подставит его сам — просто вставить
              await Clipboard.setData(ClipboardData(text: order));
              final uri = Uri.parse('https://t.me/$tg?text=${Uri.encodeComponent(order)}');
              var ok = false;
              try {
                ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.pop(ctx);
                if (context.mounted) {
                  toast(context, 'Текст заказа скопирован — отправь его в Telegram',
                      icon: AppIcons.copy);
                }
              } else {
                toast(ctx, 'Не удалось открыть Telegram. Ник: @$tg (текст скопирован)',
                    error: true);
              }
            },
          ),
          const SizedBox(height: 12),
          Text('@$tg в Telegram · оплата картой прямо в приложении скоро появится',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(ctx), fontSize: 12, height: 1.35)),
        ],
      ),
    );
  });
}

/// Выбор тарифа Premium за рубли → лист покупки.
Future<void> showPremiumRubPicker(BuildContext context) async {
  final shop = await loadShop();
  if (!context.mounted) return;
  final plans = ((shop?['premium_plans'] as List?) ?? const [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
  if (plans.isEmpty) {
    toast(context, 'Не удалось загрузить тарифы, попробуй позже', error: true);
    return;
  }
  final seller = (shop?['seller'] as Map?)?.cast<String, dynamic>();
  final picked = await showAppSheet<Map<String, dynamic>>(context, builder: (ctx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Premium за рубли',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Выбери срок — оформим в личке',
              textAlign: TextAlign.center, style: TextStyle(color: subtleText(ctx))),
          const SizedBox(height: 14),
          for (final p in plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PlanTile(plan: p, onTap: () => Navigator.pop(ctx, p)),
            ),
        ],
      ),
    );
  });
  if (picked == null || !context.mounted) return;
  await showBuyContact(context,
      item: 'Premium на ${picked['title']}',
      price: '${picked['rub']} ₽',
      premium: true,
      seller: seller);
}

class _PlanTile extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onTap;
  const _PlanTile({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disc = (plan['discount'] as num?)?.toInt() ?? 0;
    final best = plan['id'] == 'p12';
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: best ? kPremium : kPremium.withValues(alpha: 0.25), width: best ? 1.8 : 1),
          boxShadow: best
              ? [BoxShadow(color: kPremium.withValues(alpha: 0.22), blurRadius: 14)]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(gradient: kPremiumGradient, shape: BoxShape.circle),
              child: const Icon(AppIcons.star, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${plan['title']}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  if (disc > 0)
                    Text('выгода $disc%',
                        style: const TextStyle(
                            color: kSuccess, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ],
              ),
            ),
            Text('${plan['rub']} ₽',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(width: 4),
            Icon(AppIcons.chevronRight, color: subtleText(context), size: 20),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final bool premium;
  const _Badge({required this.premium});
  @override
  Widget build(BuildContext context) {
    final glow = premium ? kPremium : appState.accent;
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          glow.withValues(alpha: 0.28),
          glow.withValues(alpha: 0.0),
        ]),
      ),
      alignment: Alignment.center,
      child: premium
          ? Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: kPremiumGradient,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kPremium.withValues(alpha: 0.45), blurRadius: 18)],
              ),
              child: const Icon(AppIcons.star, color: Colors.white, size: 34),
            )
          : const CoinIcon(size: 62),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: appState.accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: TextStyle(
                    color: appState.accent, fontWeight: FontWeight.w900, fontSize: 12.5)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.3))),
        ],
      ),
    );
  }
}

class _OrderBox extends StatelessWidget {
  final String text;
  const _OrderBox({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(text,
                style: TextStyle(fontSize: 13, height: 1.4, color: subtleText(context))),
          ),
          IconButton(
            tooltip: 'Скопировать',
            icon: const Icon(AppIcons.copy, size: 19),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) toast(context, 'Скопировано', icon: AppIcons.copy);
            },
          ),
        ],
      ),
    );
  }
}
