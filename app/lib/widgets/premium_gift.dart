import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../screens/chat_screen.dart' show playEffect;
import '../screens/wallet_screen.dart';
import '../theme.dart';
import 'gift_widgets.dart';
import 'ui.dart';

/// Подарить Connecto Premium (за коины). true — подарено.
Future<bool> showPremiumGift(BuildContext context,
    {required String toUserId, required String toName}) async {
  final ok = await showAppSheet<bool>(context,
      scrollable: true, builder: (_) => _PremiumGiftSheet(toUserId: toUserId, toName: toName));
  if (ok == true && context.mounted) {
    playEffect(context, 'fireworks');
    toast(context, 'Premium подарен: $toName ⭐', icon: AppIcons.crown);
  }
  return ok == true;
}

class _PremiumGiftSheet extends StatefulWidget {
  final String toUserId;
  final String toName;
  const _PremiumGiftSheet({required this.toUserId, required this.toName});
  @override
  State<_PremiumGiftSheet> createState() => _PremiumGiftSheetState();
}

class _PremiumGiftSheetState extends State<_PremiumGiftSheet> {
  List<Map<String, dynamic>>? _plans;
  String? _error;
  String? _busy;
  int _sel = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.shop();
      if (!mounted) return;
      setState(() {
        _plans = ((d['premium_plans'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        if (_sel >= _plans!.length) _sel = 0;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _buy() async {
    final plans = _plans;
    if (plans == null || plans.isEmpty) return;
    final plan = plans[_sel];
    final price = (plan['coins'] as num).toInt();
    if (appState.coins < price) {
      toast(context, 'Не хватает кристаллов — пополни кошелёк', error: true);
      return;
    }
    setState(() => _busy = plan['id'] as String);
    try {
      final r = await Api.buyPremiumWithCoins(plan['id'] as String, toUserId: widget.toUserId);
      appState.applyServerUser(r);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadiusL),
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1F05), Color(0xFF5A3D00), Color(0xFFB8860B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kPremiumGradient),
                child: const Icon(AppIcons.crown, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 12),
              const Text('Подарить Premium',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('для ${widget.toName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFFE7A3), fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center))
          else if (plans == null)
            const Padding(
                padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
          else ...[
            for (var i = 0; i < plans.length; i++) ...[
              _planTile(plans[i], i == _sel, () => setState(() => _sel = i)),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Row(children: [
              Text('Баланс: ', style: TextStyle(color: subtleText(context))),
              CoinAmount(appState.coins, size: 14),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                  if (mounted) setState(() {});
                },
                child: const Text('Пополнить'),
              ),
            ]),
            const SizedBox(height: 8),
            PrimaryButton(
              label: plans.isEmpty
                  ? 'Нет тарифов'
                  : 'Подарить за ${fmtCoins((plans[_sel]['coins'] as num).toInt())}',
              icon: AppIcons.gift,
              gradient: kPremiumGradient,
              loading: _busy != null,
              onTap: plans.isEmpty ? null : _buy,
            ),
          ],
        ],
      ),
    );
  }

  Widget _planTile(Map<String, dynamic> p, bool sel, VoidCallback onTap) {
    final discount = (p['discount'] as num?)?.toInt() ?? 0;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: sel ? kPremium.withValues(alpha: 0.14) : Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: sel ? kPremium : Colors.transparent, width: 1.6),
        ),
        child: Row(children: [
          Icon(sel ? AppIcons.circleCheck : AppIcons.circle,
              color: sel ? kPremium : subtleText(context), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${p['title']}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          ),
          if (discount > 0)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: kSuccess.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text('−$discount%',
                  style: const TextStyle(
                      color: kSuccess, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          CoinAmount((p['coins'] as num).toInt(), size: 14),
        ]),
      ),
    );
  }
}
