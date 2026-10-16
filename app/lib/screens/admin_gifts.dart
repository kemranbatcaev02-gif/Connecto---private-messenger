import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/ui.dart';

// Админка: магазин подарков (добавить сезонный подарок, цена, тираж, срок продажи)
// и выкладка обновлений приложения (APK / установщик + «что нового»).
// Всё хранится на сервере — приложение пересобирать не нужно.

String _two(int n) => n.toString().padLeft(2, '0');

String _dt(DateTime? d) =>
    d == null ? '—' : '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

String _size(int? b) {
  if (b == null) return '';
  if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(b / 1024).round()} КБ';
}

const Map<String, (String, Color)> _kStatus = {
  'on_sale': ('В продаже', kSuccess),
  'soon': ('Скоро', kWarning),
  'ended': ('Закончился', Color(0xFF64748B)),
  'off': ('Выключен', kDanger),
};

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
      );
}

Widget _errorBox(String error, VoidCallback retry) => ListView(children: [
      const SizedBox(height: 60),
      EmptyState(
          icon: AppIcons.wifiOff,
          title: 'Не удалось загрузить',
          subtitle: error,
          action: TextButton(onPressed: retry, child: const Text('Повторить'))),
    ]);

// ═════════════════════════════════ подарки ═════════════════════════════════

class AdminGiftsTab extends StatefulWidget {
  const AdminGiftsTab({super.key});
  @override
  State<AdminGiftsTab> createState() => _AdminGiftsTabState();
}

class _AdminGiftsTabState extends State<AdminGiftsTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _gifts;
  String? _error;
  String _filter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminGifts();
      if (!mounted) return;
      setState(() {
        _gifts = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _open([Map<String, dynamic>? g]) async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => GiftEditorScreen(gift: g)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final all = _gifts;
    Widget body;
    if (_error != null && all == null) {
      body = _errorBox(_error!, _load);
    } else if (all == null) {
      body = ListView(children: const [ListSkeleton()]);
    } else {
      int count(String st) => all.where((g) => g['status'] == st).length;
      final shown = _filter == 'all' ? all : all.where((g) => g['status'] == _filter).toList();
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in [
                ('all', 'Все', all.length),
                ('on_sale', 'В продаже', count('on_sale')),
                ('soon', 'Скоро', count('soon')),
                ('ended', 'Закончились', count('ended')),
                ('off', 'Выключены', count('off')),
              ])
                ChoiceChip(
                  label: Text('${f.$2} · ${f.$3}'),
                  selected: _filter == f.$1,
                  onSelected: (_) => setState(() => _filter = f.$1),
                ),
            ]),
            const SizedBox(height: 14),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyState(icon: AppIcons.gift, title: 'Тут пусто'),
              ),
            for (final g in shown) ...[
              _GiftRow(gift: g, onTap: () => _open(g)),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        backgroundColor: appState.accent,
        foregroundColor: Colors.white,
        icon: const Icon(AppIcons.plus),
        label: const Text('Новый подарок', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _GiftRow extends StatelessWidget {
  final Map<String, dynamic> gift;
  final VoidCallback onTap;
  const _GiftRow({required this.gift, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = gift;
    final rarity = g['rarity'] as String? ?? 'common';
    final st = _kStatus[g['status']] ?? _kStatus['off']!;
    final from = parseServerTime(g['sale_from'] as String?);
    final until = parseServerTime(g['sale_until'] as String?);
    final supply = (g['supply'] as num?)?.toInt();
    final sold = (g['sold'] as num?)?.toInt() ?? 0;
    String when = '';
    if (from != null && until != null) {
      when = '${_dt(from)} — ${_dt(until)}';
    } else if (until != null) {
      when = 'до ${_dt(until)}';
    } else if (from != null) {
      when = 'с ${_dt(from)}';
    }
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(kRadius),
          border: rarity == 'common'
              ? null
              : Border.all(color: rarityColor(rarity).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            GiftArt(gift: g, size: 62, animate: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(g['title'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    ),
                    const SizedBox(width: 8),
                    _Pill(st.$1, st.$2),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                      '${rarityName(rarity)} · продано $sold${supply != null ? ' из $supply' : ''}',
                      style: TextStyle(
                          color: rarityColor(rarity), fontSize: 12.5, fontWeight: FontWeight.w700)),
                  if (when.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(AppIcons.calendar, size: 13, color: subtleText(context)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: subtleText(context), fontSize: 12)),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            CoinAmount((g['price'] as num?)?.toInt() ?? 0, size: 13.5),
          ],
        ),
      ),
    );
  }
}

/// Готовые цвета для редких, эпических и легендарных подарков.
const List<(String, List<String>?)> _kPalettes = [
  ('Авто', null),
  ('Хэллоуин', ['#FF8A00', '#4C1D95']),
  ('Тыква', ['#FDBA74', '#C2410C']),
  ('Новый год', ['#86EFAC', '#B91C1C']),
  ('Зима', ['#E0F2FE', '#2563EB']),
  ('Любовь', ['#FDA4AF', '#BE123C']),
  ('Весна', ['#BBF7D0', '#16A34A']),
  ('Космос', ['#A78BFA', '#1E1B4B']),
  ('Океан', ['#67E8F9', '#0E7490']),
  ('Золото', ['#FEF3C7', '#B45309']),
  ('Ночь', ['#64748B', '#020617']),
];

/// Шаблон праздника: эмодзи, цвета и окно продажи (месяц/день начала и конца).
class _Holiday {
  final String name;
  final String emoji;
  final String title;
  final List<String> colors;
  final String rarity;
  final (int, int) start;
  final (int, int) end; // не включительно, 00:00
  final String bg, fx, anim, symbol;
  const _Holiday(this.name, this.emoji, this.title, this.colors, this.rarity, this.start, this.end,
      {required this.bg, required this.fx, required this.anim, this.symbol = ''});

  (DateTime, DateTime) window() {
    final now = DateTime.now();
    var y = now.year;
    DateTime mk(int yy, (int, int) md) => DateTime(yy, md.$1, md.$2);
    var s = mk(y, start);
    var e = mk(end.$1 < start.$1 ? y + 1 : y, end);
    if (!e.isAfter(now)) {
      y++;
      s = mk(y, start);
      e = mk(end.$1 < start.$1 ? y + 1 : y, end);
    }
    return (s.isBefore(now) ? now : s, e);
  }
}

const List<_Holiday> _kHolidays = [
  _Holiday('Хэллоуин', '🎃', 'Тыква', ['#FF8A00', '#4C1D95'], 'epic', (10, 24), (11, 2),
      bg: 'aurora', fx: 'float', anim: 'swing', symbol: '🦇'),
  _Holiday('Новый год', '🎄', 'Ёлка', ['#86EFAC', '#B91C1C'], 'rare', (12, 20), (1, 9),
      bg: 'starry', fx: 'snow', anim: 'float'),
  _Holiday('14 февраля', '💘', 'Сердце', ['#FDA4AF', '#BE123C'], 'rare', (2, 10), (2, 16),
      bg: 'glow', fx: 'hearts', anim: 'pulse'),
  _Holiday('8 марта', '🌷', 'Тюльпаны', ['#BBF7D0', '#DB2777'], 'rare', (3, 4), (3, 10),
      bg: 'sunset', fx: 'float', anim: 'float', symbol: '🌸'),
  _Holiday('День рождения Connecto', '🥳', 'Праздник', ['#C4B5FD', '#6D28D9'], 'legendary',
      (6, 14), (6, 19), bg: 'rays', fx: 'confetti', anim: 'bounce'),
];

class GiftEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? gift;
  const GiftEditorScreen({super.key, this.gift});
  @override
  State<GiftEditorScreen> createState() => _GiftEditorScreenState();
}

class _GiftEditorScreenState extends State<GiftEditorScreen> {
  late final bool _isNew = widget.gift == null;
  late final _title = TextEditingController(text: widget.gift?['title'] as String? ?? '');
  late final _emoji = TextEditingController(text: widget.gift?['emoji'] as String? ?? '🎁');
  late final _id = TextEditingController(text: widget.gift?['id'] as String? ?? '');
  late final _price =
      TextEditingController(text: '${(widget.gift?['price'] as num?)?.toInt() ?? 50}');
  late final _supply =
      TextEditingController(text: '${(widget.gift?['supply'] as num?)?.toInt() ?? 1000}');
  late String _rarity = widget.gift?['rarity'] as String? ?? 'common';
  late bool _limited = widget.gift?['supply'] != null;
  late String? _image = widget.gift?['image_url'] as String?;
  late List<String>? _colors =
      (widget.gift?['colors'] as List?)?.whereType<String>().toList();
  late DateTime? _from = parseServerTime(widget.gift?['sale_from'] as String?);
  late DateTime? _until = parseServerTime(widget.gift?['sale_until'] as String?);
  late bool _active = widget.gift?['active'] != false;
  // оформление: новый подарок сразу красивый (по редкости), старые — «классика», пока не выберешь
  late String _bg = widget.gift == null
      ? giftDefaultStyle(_rarity).bg
      : (widget.gift!['bg'] as String? ?? 'auto');
  late String _fx = widget.gift == null
      ? giftDefaultStyle(_rarity).fx
      : (widget.gift!['fx'] as String? ?? 'auto');
  late String _anim = widget.gift == null
      ? giftDefaultStyle(_rarity).anim
      : (widget.gift!['anim'] as String? ?? 'auto');
  late final _symbol = TextEditingController(text: widget.gift?['symbol'] as String? ?? '');
  bool _styleTouched = false;
  bool _removeBg = true;
  bool _uploading = false;
  bool _saving = false;

  int get _sold => (widget.gift?['sold'] as num?)?.toInt() ?? 0;

  @override
  void dispose() {
    for (final c in [_title, _emoji, _id, _price, _supply, _symbol]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _preview => {
        'id': _id.text.trim().isEmpty ? 'new' : _id.text.trim(),
        'title': _title.text.trim().isEmpty ? 'Подарок' : _title.text.trim(),
        'emoji': _emoji.text.trim().isEmpty ? '🎁' : _emoji.text.trim(),
        'price': int.tryParse(_price.text.trim()) ?? 0,
        'rarity': _rarity,
        if (_image != null) 'image_url': _image,
        if (_colors != null) 'colors': _colors,
        if (_limited) 'supply': int.tryParse(_supply.text.trim()),
        if (_until != null) 'sale_until': _until!.toUtc().toIso8601String(),
        'bg': _bg,
        'fx': _fx,
        'anim': _anim,
        if (_symbol.text.trim().isNotEmpty) 'symbol': _symbol.text.trim(),
      };

  void _setRarity(String r) {
    setState(() {
      _rarity = r;
      // пока оформление не трогали — подбираем красивое под редкость
      if (!_styleTouched && (_isNew || _bg != 'auto')) {
        final d = giftDefaultStyle(r);
        _bg = d.bg;
        _fx = d.fx;
        _anim = d.anim;
      }
    });
  }

  void _applyHoliday(_Holiday h) {
    final (s, e) = h.window();
    setState(() {
      if (_emoji.text.trim().isEmpty || _emoji.text.trim() == '🎁') _emoji.text = h.emoji;
      if (_title.text.trim().isEmpty) _title.text = h.title;
      _colors = h.colors;
      _rarity = h.rarity;
      _from = s;
      _until = e;
      _bg = h.bg;
      _fx = h.fx;
      _anim = h.anim;
      if (h.symbol.isNotEmpty) _symbol.text = h.symbol;
      _styleTouched = true;
    });
    toast(context, '${h.name}: ${_dt(s)} — ${_dt(e)}', icon: AppIcons.calendar);
  }

  Future<void> _pickImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: kIsWeb);
      final f = res?.files.single;
      if (f == null) return;
      setState(() => _uploading = true);
      Map<String, dynamic> r;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) throw ApiException('Не удалось прочитать файл');
        r = await Api.adminGiftImage(bytes: bytes, fileName: f.name, removeBg: _removeBg);
      } else {
        r = await Api.adminGiftImage(path: f.path!, fileName: f.name, removeBg: _removeBg);
      }
      if (!mounted) return;
      setState(() => _image = r['url'] as String?);
      if (_removeBg) {
        toast(context, r['removed_bg'] == true ? 'Фон убран ✨' : 'Фон уже был прозрачный');
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Уже загруженная картинка с белым фоном — переделать на сервере.
  Future<void> _cutExisting() async {
    final src = _image;
    if (src == null || !src.startsWith('/media/')) return;
    setState(() => _uploading = true);
    try {
      final r = await Api.adminGiftImage(src: src);
      if (!mounted) return;
      setState(() => _image = r['url'] as String?);
      toast(context, r['removed_bg'] == true ? 'Фон убран ✨' : 'Фон уже был прозрачный');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final base = initial ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Выбери дату',
      cancelText: 'Отмена',
      confirmText: 'Дальше',
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: 'Время',
      cancelText: 'Отмена',
      confirmText: 'Готово',
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final price = int.tryParse(_price.text.trim());
    final supply = int.tryParse(_supply.text.trim());
    if (title.isEmpty) return toast(context, 'Напиши название', error: true);
    if (price == null || price < 1) return toast(context, 'Цена — целое число от 1', error: true);
    if (_limited && (supply == null || supply < 1)) {
      return toast(context, 'Тираж — целое число от 1', error: true);
    }
    if (_from != null && _until != null && !_until!.isAfter(_from!)) {
      return toast(context, 'Конец продажи должен быть позже начала', error: true);
    }
    setState(() => _saving = true);
    try {
      await Api.adminSaveGift({
        if (_isNew && _id.text.trim().isNotEmpty) 'id': _id.text.trim().toLowerCase(),
        'title': title,
        'emoji': _emoji.text.trim().isEmpty ? '🎁' : _emoji.text.trim(),
        'image_url': _image,
        'price': price,
        'rarity': _rarity,
        'supply': _limited ? supply : null,
        'colors': _colors,
        'sale_from': _from?.toUtc().toIso8601String(),
        'sale_until': _until?.toUtc().toIso8601String(),
        'active': _active,
        'bg': _bg,
        'fx': _fx,
        'anim': _anim,
        'symbol': _symbol.text.trim().isEmpty ? null : _symbol.text.trim(),
      }, id: _isNew ? null : widget.gift!['id'] as String);
      if (!mounted) return;
      toast(context, _isNew ? 'Подарок добавлен — он уже в магазине' : 'Сохранено');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: _sold > 0 ? 'Снять с продажи?' : 'Удалить подарок?',
        body: _sold > 0
            ? 'Его уже купили $_sold раз — у владельцев он останется, а в магазине пропадёт.'
            : 'Его ещё никто не купил — удалится совсем.',
        action: _sold > 0 ? 'Снять' : 'Удалить',
        danger: true);
    if (!ok || !mounted) return;
    try {
      final r = await Api.adminDeleteGift(widget.gift!['id'] as String);
      if (!mounted) return;
      toast(context, r['deleted'] == true ? 'Удалён' : 'Снят с продажи');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Widget _dateRow(String label, DateTime? value, ValueChanged<DateTime?> set, {bool end = false}) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconTile(end ? AppIcons.hourglass : AppIcons.calendar, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(value == null ? (end ? 'без срока' : 'сразу') : _dt(value),
                    style: TextStyle(color: subtleText(context), fontSize: 13)),
              ]),
            ),
            TextButton(
              onPressed: () async {
                final d = await _pickDateTime(value);
                if (d != null) set(d);
              },
              child: const Text('Выбрать'),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ActionChip(label: Text(end ? 'Без срока' : 'Сразу'), onPressed: () => set(null)),
            if (end)
              for (final days in [1, 3, 7, 14, 30])
                ActionChip(
                  label: Text('+$days д'),
                  onPressed: () => set((_from != null && _from!.isAfter(now) ? _from! : now)
                      .add(Duration(days: days))),
                )
            else
              for (final days in [1, 3, 7])
                ActionChip(
                  label: Text('через $days д'),
                  onPressed: () {
                    final d = DateTime(now.year, now.month, now.day).add(Duration(days: days));
                    set(d);
                  },
                ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новый подарок' : 'Подарок'),
        actions: [
          if (!_isNew)
            IconButton(
                tooltip: _sold > 0 ? 'Снять с продажи' : 'Удалить',
                icon: const Icon(AppIcons.trash2, color: kDanger),
                onPressed: _delete),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // ── предпросмотр: как подарок увидят в магазине ──
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadiusL),
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [
                      rarityColor(_rarity).withValues(alpha: dark ? 0.28 : 0.16),
                      cardColor(context),
                    ],
                  ),
                ),
                child: Column(children: [
                  GiftArt(gift: p, size: 128),
                  const SizedBox(height: 12),
                  Text(p['title'] as String,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(rarityName(_rarity),
                        style: TextStyle(color: rarityColor(_rarity), fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    CoinAmount(p['price'] as int, size: 14),
                    if (_limited) ...[
                      const SizedBox(width: 10),
                      Text('тираж ${_supply.text}',
                          style: TextStyle(color: subtleText(context), fontSize: 13)),
                    ],
                  ]),
                  if (giftSaleCorner(p) != null) ...[
                    const SizedBox(height: 8),
                    _Pill(giftSaleCorner(p)!, rarityColor(_rarity)),
                  ],
                ]),
              ),
              if (_isNew) ...[
                const SizedBox(height: 16),
                const SectionLabel('Шаблон праздника'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in _kHolidays)
                    ActionChip(
                      avatar: Text(h.emoji),
                      label: Text(h.name),
                      onPressed: () => _applyHoliday(h),
                    ),
                ]),
              ],
              const SizedBox(height: 18),
              const SectionLabel('Внешний вид'),
              SectionCard(children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(16)),
                      child: _uploading
                          ? const SizedBox(
                              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : GiftImage(
                              id: p['id'] as String,
                              emoji: p['emoji'] as String,
                              size: 52,
                              url: _image),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Картинка', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('Белый фон удалится автоматически при загрузке. Без картинки — эмодзи.',
                            style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          FilledButton.tonalIcon(
                            onPressed: _uploading ? null : _pickImage,
                            icon: const Icon(AppIcons.upload, size: 18),
                            label: Text(_image == null ? 'Загрузить' : 'Заменить'),
                          ),
                          if (_image != null && _image!.startsWith('/media/'))
                            TextButton.icon(
                                onPressed: _uploading ? null : _cutExisting,
                                icon: const Icon(AppIcons.eraser, size: 18),
                                label: const Text('Убрать фон')),
                          if (_image != null)
                            TextButton(
                                onPressed: () => setState(() => _image = null),
                                child: const Text('Убрать')),
                        ]),
                        Row(children: [
                          SizedBox(
                            height: 30,
                            child: Switch(
                                value: _removeBg,
                                onChanged: (v) => setState(() => _removeBg = v)),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('убирать фон при загрузке',
                                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                          ),
                        ]),
                      ]),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Row(children: [
                    SizedBox(
                      width: 92,
                      child: AppTextField(
                          controller: _emoji,
                          hint: 'Эмодзи',
                          maxLength: 8,
                          onChanged: (_) => setState(() {})),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(
                          controller: _title,
                          hint: 'Название, например «Тыква»',
                          maxLength: 64,
                          onChanged: (_) => setState(() {})),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              const SectionLabel('Редкость'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in const ['common', 'rare', 'epic', 'legendary'])
                  Pressable(
                    onTap: () => _setRarity(r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _rarity == r
                            ? rarityColor(r).withValues(alpha: 0.18)
                            : cardColor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _rarity == r ? rarityColor(r) : Colors.transparent, width: 1.6),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(rarityName(r),
                            style: TextStyle(
                                color: rarityColor(r), fontWeight: FontWeight.w800)),
                        Text(
                            switch (r) {
                              'rare' => 'градиент и искры',
                              'epic' => 'анимация и орбита',
                              'legendary' => 'золото и сияние',
                              _ => 'спокойная плашка',
                            },
                            style: TextStyle(color: subtleText(context), fontSize: 11)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 18),
              const SectionLabel('Фон'),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kGiftBackdrops.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final o = kGiftBackdrops[i];
                    final sel = _bg == o.id;
                    return Pressable(
                      onTap: () => setState(() {
                        _bg = o.id;
                        _styleTouched = true;
                      }),
                      child: Column(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel ? appState.accent : Colors.transparent, width: 2),
                          ),
                          child: GiftArt(
                              gift: {...p, 'bg': o.id, 'fx': o.id == 'auto' ? 'auto' : 'none',
                                'anim': o.id == 'auto' ? 'auto' : 'none'},
                              size: 60,
                              animate: false),
                        ),
                        const SizedBox(height: 4),
                        Text(o.name,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                                color: sel ? appState.accent : subtleText(context))),
                      ]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel('Эффект'),
              _choiceWrap(kGiftEffects, _fx, (v) => _fx = v),
              if (_fx == 'float' || _bg == 'pattern') ...[
                const SizedBox(height: 10),
                AppTextField(
                    controller: _symbol,
                    hint: 'Символ для эффекта/узора: 🦇 👻 ❄️ 🌸 ⭐',
                    maxLength: 8,
                    onChanged: (_) => setState(() {})),
              ],
              const SizedBox(height: 14),
              const SectionLabel('Анимация'),
              _choiceWrap(kGiftAnims, _anim, (v) => _anim = v),
              const SizedBox(height: 8),
              Text('«Классика» — прежний вид по редкости. Превью сверху — как увидят все.',
                  style: TextStyle(color: subtleText(context), fontSize: 12)),
              if (_rarity != 'common' || _bg != 'auto') ...[
                const SizedBox(height: 14),
                const SectionLabel('Цвет'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final pal in _kPalettes)
                    Pressable(
                      onTap: () => setState(() => _colors = pal.$2),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                        decoration: BoxDecoration(
                          color: cardColor(context),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _sameColors(_colors, pal.$2)
                                  ? appState.accent
                                  : Colors.transparent,
                              width: 1.6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: pal.$2 == null
                                  ? accentGradient(appState.accent)
                                  : LinearGradient(colors: pal.$2!.map(hexColor).toList()),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(pal.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 18),
              const SectionLabel('Цена и тираж'),
              SectionCard(children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: AppTextField(
                      controller: _price,
                      hint: 'Цена в коинах',
                      icon: AppIcons.coin,
                      keyboard: TextInputType.number,
                      onChanged: (_) => setState(() {})),
                ),
                SwitchTile(
                  icon: AppIcons.layers,
                  title: 'Лимитированный',
                  subtitle: _sold > 0
                      ? 'уже куплено $_sold'
                      : 'у каждого купленного будет свой номер: №1, №2…',
                  value: _limited,
                  onChanged: (v) => setState(() => _limited = v),
                ),
                if (_limited)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: AppTextField(
                        controller: _supply,
                        hint: 'Сколько штук всего',
                        icon: AppIcons.layers,
                        keyboard: TextInputType.number,
                        onChanged: (_) => setState(() {})),
                  ),
              ]),
              const SizedBox(height: 18),
              const SectionLabel('Когда продаётся'),
              SectionCard(children: [
                _dateRow('Начало продажи', _from, (d) => setState(() => _from = d)),
                _dateRow('Конец продажи', _until, (d) => setState(() => _until = d), end: true),
                SwitchTile(
                  icon: AppIcons.storefront,
                  title: 'Включён',
                  subtitle: 'выключенный не продаётся, но у владельцев остаётся',
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ]),
              if (_isNew) ...[
                const SizedBox(height: 18),
                const SectionLabel('ID (необязательно)'),
                AppTextField(
                    controller: _id,
                    hint: 'например halloween_pumpkin — латиница, цифры, _',
                    maxLength: 32),
              ] else ...[
                const SizedBox(height: 12),
                Text('ID: ${widget.gift!['id']}',
                    style: TextStyle(color: subtleText(context), fontSize: 12.5)),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: _isNew ? 'Добавить в магазин' : 'Сохранить',
                icon: AppIcons.check,
                loading: _saving,
                onTap: _uploading ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceWrap(List<GiftStyleOpt> opts, String value, void Function(String) set) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opts)
            ChoiceChip(
              label: Text(o.name),
              selected: value == o.id,
              onSelected: (_) => setState(() {
                set(o.id);
                _styleTouched = true;
              }),
            ),
        ],
      );

  static bool _sameColors(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toUpperCase() != b[i].toUpperCase()) return false;
    }
    return true;
  }
}

// ═════════════════════════════════ обновления ═════════════════════════════════

const Map<String, (String, IconData, String)> _kPlatforms = {
  'android': ('Телефон (Android)', AppIcons.smartphone, 'apk'),
  'windows': ('Компьютер (Windows)', AppIcons.monitor, 'exe'),
};

class AdminReleaseTab extends StatefulWidget {
  const AdminReleaseTab({super.key});
  @override
  State<AdminReleaseTab> createState() => _AdminReleaseTabState();
}

class _AdminReleaseTabState extends State<AdminReleaseTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.adminRelease();
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _open(String platform, {bool textOnly = false}) async {
    final cur = ((_d?[platform] as Map?) ?? const {}).cast<String, dynamic>();
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ReleasePublishScreen(platform: platform, current: cur, textOnly: textOnly)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _d;
    if (_error != null && d == null) return _errorBox(_error!, _load);
    if (d == null) return ListView(children: const [ListSkeleton()]);
    final history =
        ((d['history'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final p in _kPlatforms.keys) ...[
            _platformCard(p, ((d[p] as Map?) ?? const {}).cast<String, dynamic>()),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 18),
            child: Text(
                'Сайт обновляется сборкой: build_all.ps1 -Web -Upload. '
                'Номер сборки = число после «+» в pubspec.yaml (version: 1.0.1+8 → 8). '
                'В этом приложении сборка $kAppBuild.',
                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
          ),
          if (history.isNotEmpty) ...[
            const SectionLabel('История'),
            SectionCard(children: [
              for (final h in history)
                ListTile(
                  leading: Icon(_kPlatforms[h['platform']]?.$2 ?? AppIcons.download,
                      color: appState.accent),
                  title: Text('${h['version']} · сборка ${h['build']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${_dt(parseServerTime(h['at'] as String?))} · ${h['by'] ?? ''}\n${h['notes'] ?? ''}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                  isThreeLine: true,
                ),
            ]),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _platformCard(String p, Map<String, dynamic> cur) {
    final meta = _kPlatforms[p]!;
    final file = (cur['file'] as Map?)?.cast<String, dynamic>();
    final has = cur['build'] != null;
    final when = parseServerTime(
        (cur['released_at'] as String?) ?? (file?['uploaded_at'] as String?));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconTile(meta.$2, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(meta.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                    has
                        ? 'Версия ${cur['version']} · сборка ${cur['build']}'
                            '${file != null ? ' · ${_size((file['size'] as num?)?.toInt())}' : ''}'
                        : 'Ещё не выкладывали',
                    style: TextStyle(color: subtleText(context), fontSize: 13)),
                if (when != null)
                  Text(_dt(when), style: TextStyle(color: subtleText(context), fontSize: 12)),
              ]),
            ),
            if (cur['mandatory'] == true) const _Pill('обязательное', kDanger),
          ]),
          if (has && (cur['notes'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(cur['notes'] as String,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtleText(context), fontSize: 13.5)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _open(p),
                style: FilledButton.styleFrom(backgroundColor: appState.accent),
                icon: const Icon(AppIcons.upload, size: 18),
                label: const Text('Выложить новую'),
              ),
            ),
            if (has) ...[
              const SizedBox(width: 8),
              TextButton(
                  onPressed: () => _open(p, textOnly: true), child: const Text('Изменить текст')),
            ],
          ]),
        ],
      ),
    );
  }
}

class ReleasePublishScreen extends StatefulWidget {
  final String platform;
  final Map<String, dynamic> current;
  final bool textOnly;
  const ReleasePublishScreen(
      {super.key, required this.platform, required this.current, this.textOnly = false});
  @override
  State<ReleasePublishScreen> createState() => _ReleasePublishScreenState();
}

class _ReleasePublishScreenState extends State<ReleasePublishScreen> {
  late final _version = TextEditingController(text: _nextVersion());
  late final _build = TextEditingController(
      text: '${widget.textOnly ? _curBuild : math.max(_curBuild + 1, kAppBuild)}');
  late final _notes = TextEditingController(
      text: widget.textOnly
          ? (widget.current['notes'] as String? ?? '')
          : 'Что нового:\n• \n\nИсправлено:\n• ');
  late bool _mandatory = widget.current['mandatory'] == true;
  PlatformFile? _file;
  double? _progress;
  bool _busy = false;

  int get _curBuild => (widget.current['build'] as num?)?.toInt() ?? 0;

  String _nextVersion() {
    final v = widget.current['version'] as String?;
    if (v == null || v.isEmpty) return '1.0.0';
    if (widget.textOnly) return v;
    final parts = v.split('.');
    final last = int.tryParse(parts.last);
    if (last == null) return v;
    parts[parts.length - 1] = '${last + 1}';
    return parts.join('.');
  }

  @override
  void dispose() {
    _version.dispose();
    _build.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final ext = _kPlatforms[widget.platform]!.$3;
    try {
      final res = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: [ext], withData: kIsWeb);
      final f = res?.files.single;
      if (f == null) return;
      if (!f.name.toLowerCase().endsWith('.$ext')) {
        if (mounted) toast(context, 'Нужен файл .$ext', error: true);
        return;
      }
      setState(() => _file = f);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось выбрать файл', error: true);
    }
  }

  Future<void> _publish() async {
    final build = int.tryParse(_build.text.trim());
    final version = _version.text.trim();
    if (version.isEmpty) return toast(context, 'Напиши версию, например 1.0.1', error: true);
    if (build == null || build < 1) return toast(context, 'Сборка — целое число', error: true);
    if (!widget.textOnly) {
      if (_file == null) return toast(context, 'Выбери файл', error: true);
      if (build <= _curBuild) {
        return toast(context, 'Сборка должна быть больше $_curBuild', error: true);
      }
      final ok = await confirm(context,
          title: 'Выложить ${_version.text.trim()} (сборка $build)?',
          body: 'У всех, у кого стоит сборка ниже $build, появится «Доступно обновление»'
              '${_mandatory ? ' — без кнопки «Позже»' : ''}.\n\n'
              'Проверь, что файл собран с этим номером сборки (pubspec.yaml: +$build), '
              'иначе обновление будет предлагаться снова и снова.',
          action: 'Выложить');
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _progress = widget.textOnly ? null : 0;
    });
    try {
      final f = _file;
      await Api.adminPublishRelease(
        platform: widget.platform,
        version: version,
        build: build,
        notes: _notes.text.trim(),
        mandatory: _mandatory,
        path: f != null && !kIsWeb ? f.path : null,
        bytes: f != null && kIsWeb ? f.bytes : null,
        fileName: f?.name,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      toast(context, widget.textOnly ? 'Текст обновлён' : 'Обновление выложено 🚀');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _kPlatforms[widget.platform]!;
    final f = _file;
    return Scaffold(
      appBar: AppBar(title: Text(widget.textOnly ? 'Текст обновления' : 'Новая версия')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: IconTile(meta.$2, size: 42),
                title: Text(meta.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(_curBuild > 0
                    ? 'Сейчас: ${widget.current['version']} · сборка $_curBuild'
                    : 'Первая версия'),
              ),
              const SizedBox(height: 10),
              if (!widget.textOnly) ...[
                const SectionLabel('Файл'),
                Pressable(
                  onTap: _busy ? null : _pick,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cardColor(context),
                      borderRadius: BorderRadius.circular(kRadius),
                      border: Border.all(
                          color: f == null ? hairline(context) : appState.accent, width: 1.4),
                    ),
                    child: Row(children: [
                      Icon(f == null ? AppIcons.upload : AppIcons.file,
                          color: appState.accent, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(f?.name ?? 'Выбрать .${meta.$3}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                              f == null
                                  ? (widget.platform == 'android'
                                      ? 'C:\\connecto\\dist\\Connecto.apk'
                                      : 'C:\\connecto\\dist\\Connecto-Setup.exe')
                                  : _size(f.size),
                              style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              const SectionLabel('Версия'),
              Row(children: [
                Expanded(
                  child: AppTextField(
                      controller: _version, hint: 'Версия, например 1.0.1', icon: AppIcons.tune),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: IgnorePointer(
                    ignoring: widget.textOnly,
                    child: Opacity(
                      opacity: widget.textOnly ? 0.5 : 1,
                      child: AppTextField(
                          controller: _build,
                          hint: 'Сборка',
                          icon: AppIcons.layers,
                          keyboard: TextInputType.number),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              const SectionLabel('Что изменилось'),
              AppTextField(
                  controller: _notes,
                  hint: 'Что нового, что исправлено…',
                  maxLines: 10,
                  maxLength: 4000),
              const SizedBox(height: 12),
              SectionCard(children: [
                SwitchTile(
                  icon: AppIcons.triangleAlert,
                  title: 'Обязательное обновление',
                  subtitle: 'окно без кнопки «Позже» — для важных исправлений',
                  value: _mandatory,
                  onChanged: (v) => setState(() => _mandatory = v),
                ),
              ]),
              const SizedBox(height: 22),
              if (_progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: _progress, minHeight: 8, color: appState.accent),
                ),
                const SizedBox(height: 6),
                Text(
                    (_progress ?? 0) >= 0.999
                        ? 'Сервер сохраняет файл…'
                        : 'Загружаю: ${((_progress ?? 0) * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtleText(context))),
                const SizedBox(height: 14),
              ],
              PrimaryButton(
                label: widget.textOnly ? 'Сохранить текст' : 'Выложить обновление',
                icon: widget.textOnly ? AppIcons.check : AppIcons.upload,
                loading: _busy,
                onTap: _publish,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
