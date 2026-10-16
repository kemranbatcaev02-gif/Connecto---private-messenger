part of 'chat_screen.dart';

/// Тик раз в секунду для таймеров автоудаления (без перестройки всего чата).
final ValueNotifier<int> _ttlTick = ValueNotifier(0);

// ─────────────────────────────────────────────────────────────
// Мелкие элементы ленты
// ─────────────────────────────────────────────────────────────

class _DayPill extends StatelessWidget {
  final String text;
  const _DayPill(this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
              color: cardColor(context).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12)),
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: subtleText(context))),
        ),
      );
}

class _ServicePill extends StatelessWidget {
  final String text;
  const _ServicePill(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 30),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: cardColor(context).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14)),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: subtleText(context), height: 1.3)),
        ),
      );
}

class _AuthorHeaderBadge extends StatelessWidget {
  final String name;
  final bool verified, premium, bot;
  final Color color;
  final String? bannerUrl;

  const _AuthorHeaderBadge({
    required this.name,
    required this.verified,
    required this.premium,
    required this.bot,
    required this.color,
    this.bannerUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (bannerUrl == null || bannerUrl!.isEmpty) {
      return NameBadges(name,
          verified: verified,
          premium: premium,
          bot: bot,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        image: DecorationImage(
          image: NetworkImage(bannerUrl!.startsWith('http') ? bannerUrl! : '$kBaseUrl$bannerUrl'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.4), BlendMode.darken),
        ),
      ),
      child: NameBadges(name,
          verified: verified,
          premium: premium,
          bot: bot,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }
}

class _ReactionPick extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _ReactionPick(
      {required this.emoji, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.8,
      onTap: onTap,
      child: Container(
        width: 48,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? appState.accent.withValues(alpha: 0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 27)),
      ),
    );
  }
}

class _ScrollDownButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ScrollDownButton({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cardColor(context),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(AppIcons.chevronDown, color: subtleText(context)),
          ),
          if (count > 0)
            Positioned(top: -6, left: 0, right: 0, child: Center(child: CountBadge(count))),
        ],
      ),
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(14),
      children: [
        for (var i = 0; i < 9; i++)
          Align(
            alignment: i % 3 == 1 ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Shimmer(
                  width: w * (0.35 + (i % 4) * 0.1), height: 40 + (i % 2) * 14, radius: 16),
            ),
          ),
      ],
    );
  }
}

class _BottomAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final bool subtle;
  const _BottomAction(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.loading = false,
      this.subtle = false});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: subtle
            ? Pressable(
                onTap: onTap,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: cardColor(context),
                      borderRadius: BorderRadius.circular(kRadius)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: appState.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(label,
                          style: TextStyle(
                              color: appState.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5)),
                    ],
                  ),
                ),
              )
            : PrimaryButton(label: label, icon: icon, loading: loading, onTap: onTap),
      ),
    );
  }
}

class _BottomInfo extends StatelessWidget {
  final String text;
  final IconData icon;
  const _BottomInfo({required this.text, required this.icon});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
            color: cardColor(context), borderRadius: BorderRadius.circular(kRadius)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: subtleText(context)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtleText(context), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Текст со ссылками, /командами и приглашениями
// ─────────────────────────────────────────────────────────────

final RegExp _linkRe = RegExp(
    r'((?:https?://|www\.)[^\s]+)|((?<![\w/])/[a-zA-Z0-9_]{1,32}\b)',
    caseSensitive: false);

final RegExp _emojiOnlyRe = RegExp(
    r'^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|\p{Emoji_Component}|‍|️|\s)+$',
    unicode: true);

bool _isJumboEmoji(String t) {
  final s = t.trim();
  if (s.isEmpty || s.characters.length > 3) return false;
  if (RegExp(r'[0-9#*]').hasMatch(s)) return false;
  return _emojiOnlyRe.hasMatch(s);
}

class _LinkText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final ValueChanged<String>? onCommand;
  final ValueChanged<String> onInvite;
  const _LinkText(
      {required this.text,
      required this.style,
      required this.linkColor,
      required this.onInvite,
      this.onCommand});
  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  final List<TapGestureRecognizer> _rec = [];

  @override
  void dispose() {
    for (final r in _rec) {
      r.dispose();
    }
    super.dispose();
  }

  /// Ссылка ведёт на наш сервер: по IP (приложения) или на сайт (веб-версия).
  static bool _ourHost(String url) {
    final host = Uri.tryParse(url.startsWith('http') ? url : 'https://$url')?.host ?? '';
    if (host.isEmpty) return false;
    return host == Uri.parse(kServerUrl).host ||
        host == Uri.parse(kBaseUrl).host ||
        host == 'connectomes.duckdns.org';
  }

  void _openUrl(String raw) {
    var url = raw;
    // хвостовая пунктуация не часть ссылки
    while (url.isNotEmpty && '.,!?)»"\''.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    final code = Api.inviteCodeOf(url);
    if (code != null && _ourHost(url)) {
      widget.onInvite(code);
      return;
    }
    openLink(url);
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _rec) {
      r.dispose();
    }
    _rec.clear();
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final m in _linkRe.allMatches(widget.text)) {
      final isCmd = m.group(2) != null;
      if (isCmd && widget.onCommand == null) continue;
      if (m.start > pos) spans.add(TextSpan(text: widget.text.substring(pos, m.start)));
      final value = m.group(0)!;
      final r = TapGestureRecognizer()
        ..onTap = () => isCmd ? widget.onCommand!(value) : _openUrl(value);
      _rec.add(r);
      spans.add(TextSpan(
        text: value,
        recognizer: r,
        style: TextStyle(
            color: widget.linkColor,
            decoration: isCmd ? null : TextDecoration.underline,
            decorationColor: widget.linkColor.withValues(alpha: 0.6),
            fontWeight: isCmd ? FontWeight.w700 : null),
      ));
      pos = m.end;
    }
    if (pos < widget.text.length) spans.add(TextSpan(text: widget.text.substring(pos)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

// ─────────────────────────────────────────────────────────────
// Пузырь сообщения
// ─────────────────────────────────────────────────────────────

class _Bubble extends StatefulWidget {
  final Message msg;
  final String chatId;
  final bool channel;
  final bool group;
  final bool first;
  final bool last;
  final bool highlighted;
  final String? replyAuthor;
  final String? replyPreview;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTap;
  final VoidCallback onSelectTap;
  final VoidCallback onReplyTap;
  final VoidCallback onSenderTap;
  final VoidCallback onRetry;
  final ValueChanged<String> onReact;
  final ValueChanged<String>? onCommand;
  final ValueChanged<String> onInvite;
  final VoidCallback? onSwipeReply;
  final VoidCallback onCapsuleOpened;
  final ValueChanged<String> onEffect;
  final ValueChanged<bool>? onCallBack;
  const _Bubble({
    super.key,
    required this.msg,
    required this.chatId,
    required this.channel,
    required this.group,
    required this.first,
    required this.last,
    required this.highlighted,
    this.replyAuthor,
    this.replyPreview,
    required this.selectMode,
    required this.isSelected,
    required this.onLongPress,
    required this.onDoubleTap,
    required this.onSelectTap,
    required this.onReplyTap,
    required this.onSenderTap,
    required this.onRetry,
    required this.onReact,
    required this.onInvite,
    this.onCommand,
    this.onSwipeReply,
    required this.onCapsuleOpened,
    required this.onEffect,
    this.onCallBack,
  });

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  double _dx = 0;
  bool _dragging = false;
  bool _armed = false;

  Message get msg => widget.msg;

  void _dragUpdate(DragUpdateDetails d) {
    if (widget.onSwipeReply == null) return;
    setState(() {
      _dragging = true;
      _dx = (_dx + d.delta.dx).clamp(-90.0, 0.0);
    });
    final armed = _dx <= -60;
    if (armed && !_armed) HapticFeedback.lightImpact();
    _armed = armed;
  }

  void _dragEnd(DragEndDetails _) {
    if (widget.onSwipeReply == null) return;
    if (_armed) widget.onSwipeReply!();
    setState(() {
      _dragging = false;
      _dx = 0;
      _armed = false;
    });
  }

  Color _onBubble(bool mine) => mine ? Colors.white : Theme.of(context).colorScheme.onSurface;
  Color _meta(bool mine) =>
      mine ? Colors.white.withValues(alpha: 0.8) : subtleText(context);

  Widget _content(bool mine, bool jumbo) {
    if (msg.sealed && msg.openAt != null) {
      return _CapsuleSealed(
          openAt: msg.openAt!, createdAt: msg.dt, onOpened: widget.onCapsuleOpened);
    }
    final full = msg.mediaUrl != null ? mediaUrl(msg.mediaUrl) : null;
    final fg = _onBubble(mine);
    if (msg.failed || msg.uploading) {
      if (msg.kind == 'text') {
        return _textContent(mine, jumbo);
      }
      if (msg.kind == 'round' && msg.localPath != null && !msg.failed) {
        return _RoundNote(msg: msg, mine: mine);
      }
      if (msg.kind == 'image' && msg.localPath != null) {
        return _NetImage(
            url: null, localPath: msg.localPath, mine: mine, uploading: msg.uploading);
      }
      if (msg.kind == 'image' && msg.uploading && (full ?? '').startsWith('http')) {
        return _NetImage(url: full, mine: mine, uploading: true); // GIF, пока уходит
      }
      return _UploadTile(
          kind: msg.kind, name: msg.fileName, mine: mine, failed: msg.failed);
    }
    switch (msg.kind) {
      case 'image':
        return _NetImage(url: full, localPath: msg.localPath, mine: mine);
      case 'video':
        return _VideoTile(url: full, localPath: msg.localPath, name: msg.fileName);
      case 'file':
        return _FileTile(
          url: full ?? '',
          name: msg.fileName ?? 'Файл',
          mine: mine,
          localPath: msg.localPath,
        );
      case 'voice':
        if (full == null) return const SizedBox();
        final meta = parseWave(msg.text);
        return _VoicePlayer(
          item: VoiceItem(
            id: msg.id,
            chatId: widget.chatId,
            url: full,
            localPath: msg.localPath,
            title: mine ? 'Вы' : (msg.senderName.isEmpty ? 'Голосовое' : msg.senderName),
            durationMs: meta?.durationMs ?? 0,
            mine: mine,
          ),
          bars: (meta != null && meta.bars.isNotEmpty) ? meta.bars : _fallbackBars(msg.id),
          mine: mine,
        );
      case 'round':
        if (full == null && msg.localPath == null) return const SizedBox();
        return _RoundNote(msg: msg, mine: mine);
      case 'call':
        return _CallContent(msg: msg, mine: mine, onCall: widget.onCallBack);
      case 'gift':
        final g = msg.gift;
        if (g == null) return _textContent(mine, jumbo);
        return _GiftContent(data: g, text: msg.text, mine: mine);
      case 'location':
        final parts = msg.text.split(',');
        final lat = parts.isNotEmpty ? parts[0].trim() : '';
        final lng = parts.length > 1 ? parts[1].trim() : '';
        return GestureDetector(
          onTap: () => launchUrl(
              Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
              mode: LaunchMode.externalApplication),
          child: SizedBox(
            width: 220,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: mine
                        ? Colors.white.withValues(alpha: 0.2)
                        : kSuccess.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(AppIcons.mapPin, color: mine ? Colors.white : kSuccess),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Геолокация',
                          style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                      Text('Открыть на карте',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: mine ? Colors.white70 : appState.accent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case 'contact':
        Map<String, dynamic> data;
        try {
          data = (jsonDecode(msg.text) as Map).cast<String, dynamic>();
        } catch (_) {
          data = {'name': msg.text};
        }
        final cname = (data['name'] as String?) ?? 'Контакт';
        final chandle = (data['handle'] ?? '').toString();
        final cid = (data['id'] ?? '').toString();
        return GestureDetector(
          onTap: cid.isEmpty
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => UserInfoScreen(userId: cid, name: cname))),
          child: SizedBox(
            width: 220,
            child: Row(
              children: [
                Avatar(name: cname, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                      Text(chandle.isNotEmpty ? '@$chandle' : 'Контакт',
                          style: TextStyle(fontSize: 12.5, color: _meta(mine))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        return _textContent(mine, jumbo);
    }
  }

  Widget _textContent(bool mine, bool jumbo) {
    if (jumbo) {
      return Text(msg.text.trim(), style: const TextStyle(fontSize: 46, height: 1.15));
    }
    return _LinkText(
      text: msg.text,
      style: TextStyle(
          color: _onBubble(mine),
          fontSize: 15.5 * appState.messageTextScale,
          height: 1.3),
      linkColor: mine ? Colors.white : appState.accent,
      onCommand: widget.onCommand,
      onInvite: widget.onInvite,
    );
  }

  Widget _metaRow(bool mine, {bool onMedia = false}) {
    final color = onMedia ? Colors.white : _meta(mine);
    Widget tick() {
      if (msg.failed) {
        return GestureDetector(
          onTap: widget.onRetry,
          child: const Icon(AppIcons.circleAlert, size: 14, color: kDanger),
        );
      }
      if (msg.uploading) return Icon(AppIcons.clock3, size: 12.5, color: color);
      return Icon(msg.read ? AppIcons.checkCheck : AppIcons.check,
          size: 14, color: color);
    }

    final fx = fxOf(msg.effect);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fx != null && !msg.sealed) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onEffect(fx.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(fx.emoji, style: const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 5),
        ],
        if (msg.expiresAt != null) ...[
          Icon(AppIcons.timer, size: 12, color: color),
          const SizedBox(width: 2),
          ValueListenableBuilder<int>(
            valueListenable: _ttlTick,
            builder: (_, __, ___) => Text('${_ttlLeft(msg.expiresAt!)}  ',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
        if (msg.edited)
          Text('изменено  ',
              style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: color)),
        Text(msg.time, style: TextStyle(fontSize: 11, color: color)),
        if (mine) ...[const SizedBox(width: 3), tick()],
      ],
    );
    if (!onMedia) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(10)),
      child: row,
    );
  }

  Widget _reactions(bool mine) {
    if (msg.reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final r in msg.reactions)
            Pressable(
              scale: 0.9,
              onTap: () => widget.onReact(r['emoji'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: r['mine'] == true
                      ? (mine ? Colors.white.withValues(alpha: 0.32) : appState.accent.withValues(alpha: 0.22))
                      : (mine ? Colors.white.withValues(alpha: 0.14) : subtleText(context).withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: r['mine'] == true
                          ? (mine ? Colors.white : appState.accent)
                          : Colors.transparent,
                      width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r['emoji'] as String, style: const TextStyle(fontSize: 14.5)),
                    const SizedBox(width: 4),
                    Text('${r['count'] ?? 1}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: mine ? Colors.white : appState.accent)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = !widget.channel && msg.mine;
    final r = bubbleRadiusEff();
    final round = appState.bubbleStyleEff == 'round';
    final isMedia = msg.kind == 'image' && !msg.failed;
    final jumbo = msg.kind == 'text' && _isJumboEmoji(msg.text) && msg.replyToId == null;
    final showAvatarSlot = widget.group && !mine;
    final showName = widget.group && !mine && widget.first && !jumbo;
    final maxW = MediaQuery.of(context).size.width * (showAvatarSlot ? 0.72 : 0.8);
    final nameColor = avatarColor(msg.senderName.isEmpty ? '?' : msg.senderName);
    final noBubble = jumbo ||
        (msg.sealed && msg.openAt != null) ||
        (msg.isGift && msg.gift != null) ||
        (msg.kind == 'round' && !msg.failed && !msg.sealed);
    final media = isMedia && !msg.sealed && msg.openAt == null && msg.reactions.isEmpty && widget.replyPreview == null &&
        msg.forwardedFrom == null && !showName;

    final radius = round
        ? BorderRadius.circular(r)
        : BorderRadius.only(
            topLeft: Radius.circular(!mine && !widget.first ? 7 : r),
            topRight: Radius.circular(mine && !widget.first ? 7 : r),
            bottomLeft: Radius.circular(!mine ? (widget.last ? 5 : 7) : r),
            bottomRight: Radius.circular(mine ? (widget.last ? 5 : 7) : r),
          );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showName)
          GestureDetector(
            onTap: widget.onSenderTap,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _AuthorHeaderBadge(
                name: msg.senderName,
                verified: msg.senderVerified,
                premium: msg.senderPremium,
                bot: msg.senderBot,
                color: nameColor,
                bannerUrl: msg.extra?['author_banner'] as String?,
              ),
            ),
          ),
        if (msg.forwardedFrom != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.forward,
                    size: 13, color: mine ? Colors.white70 : appState.accent),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                      msg.forwardedName != null && msg.forwardedName!.isNotEmpty
                          ? 'Переслано от ${msg.forwardedName}'
                          : 'Пересланное сообщение',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: mine ? Colors.white70 : appState.accent)),
                ),
              ],
            ),
          ),
        if (widget.replyPreview != null)
          GestureDetector(
            onTap: widget.onReplyTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(9, 5, 10, 5),
              decoration: BoxDecoration(
                color: mine
                    ? Colors.white.withValues(alpha: 0.16)
                    : appState.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
                border: Border(
                    left: BorderSide(
                        color: mine ? Colors.white : appState.accent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.replyAuthor != null)
                    Text(widget.replyAuthor!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: mine ? Colors.white : appState.accent)),
                  Text(widget.replyPreview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: _meta(mine))),
                ],
              ),
            ),
          ),
        if (msg.story != null)
          _StoryReplyChip(story: msg.story!, mine: mine),
        if (!msg.sealed && msg.openAt != null && msg.openAt!.isAfter(DateTime.now()))
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFF5B2A86).withValues(alpha: mine ? 0.55 : 0.18),
                const Color(0xFFB0457A).withValues(alpha: mine ? 0.55 : 0.18),
              ]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📦', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Капсула · откроется ${_capsuleDate(msg.openAt!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mine ? Colors.white : _onBubble(mine))),
                ),
              ],
            ),
          ),
        if (media)
          Stack(
            children: [
              _content(mine, jumbo),
              Positioned(right: 8, bottom: 8, child: _metaRow(mine, onMedia: true)),
            ],
          )
        else ...[
          _content(mine, jumbo),
          if (!msg.sealed) _reactions(mine),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: noBubble
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: cardColor(context).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10)),
                    child: _metaRow(false),
                  )
                : _metaRow(mine),
          ),
        ],
      ],
    );

    final bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      constraints: BoxConstraints(maxWidth: maxW, minWidth: 64),
      padding: media
          ? const EdgeInsets.all(3)
          : (noBubble
              ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
              : const EdgeInsets.fromLTRB(12, 8, 12, 7)),
      decoration: noBubble
          ? BoxDecoration(
              borderRadius: radius,
              boxShadow: widget.highlighted
                  ? [
                      BoxShadow(
                          color: appState.accent.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 1),
                    ]
                  : null)
          : (mine
              ? myBubbleDecoration(radius, highlighted: widget.highlighted)
              : otherBubbleDecoration(context, radius, highlighted: widget.highlighted)),
      child: IntrinsicWidth(child: body),
    );
    // обводка пузыря (Оформление → Рамки чатов)
    final frame = noBubble ? null : bubbleFrameLook(context, mine);
    final framedBubble = frame == null
        ? bubble
        : FramedBox(look: frame, radius: radius, clip: false, child: bubble);

    final isCenteredSpecial = (msg.isGift && msg.gift != null) || msg.isService;
    final row = Row(
      mainAxisAlignment: isCenteredSpecial
          ? MainAxisAlignment.center
          : (mine ? MainAxisAlignment.end : MainAxisAlignment.start),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showAvatarSlot && !isCenteredSpecial)
          SizedBox(
            width: 38,
            child: widget.last
                ? GestureDetector(
                    onTap: widget.onSenderTap,
                    child: FramedAvatar(
                      size: 32,
                      frame: msg.senderFrame,
                      child: Avatar(name: msg.senderName, url: msg.senderAvatar, size: 32),
                    ),
                  )
                : null,
          ),
        Flexible(
          child: GestureDetector(
            onLongPress: widget.onLongPress,
            onSecondaryTap: widget.selectMode ? null : widget.onLongPress, // правый клик
            onDoubleTap: widget.selectMode ? null : widget.onDoubleTap,
            onTap: widget.selectMode ? widget.onSelectTap : null,
            onHorizontalDragUpdate: widget.onSwipeReply == null ? null : _dragUpdate,
            onHorizontalDragEnd: widget.onSwipeReply == null ? null : _dragEnd,
            child: framedBubble,
          ),
        ),
      ],
    );

    final swiped = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerRight,
      children: [
        if (_dx < -8)
          Positioned(
            right: 4,
            child: AnimatedScale(
              scale: _armed ? 1.15 : 0.8,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: appState.accent.withValues(alpha: _armed ? 0.9 : 0.35),
                    shape: BoxShape.circle),
                child: const Icon(AppIcons.reply, color: Colors.white, size: 18),
              ),
            ),
          ),
        AnimatedContainer(
          duration: Duration(milliseconds: _dragging ? 0 : 220),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(_dx, 0, 0),
          child: row,
        ),
      ],
    );

    final padded = Padding(
      padding: EdgeInsets.only(top: widget.first ? 5 : 1.5, bottom: 1.5),
      child: swiped,
    );

    if (!widget.selectMode) return padded;
    return GestureDetector(
      onTap: widget.onSelectTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: widget.isSelected ? appState.accent.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                widget.isSelected ? AppIcons.circleCheck : AppIcons.circle,
                key: ValueKey(widget.isSelected),
                color: widget.isSelected ? appState.accent : subtleText(context),
                size: 22,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: IgnorePointer(child: padded)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Вложения
// ─────────────────────────────────────────────────────────────

/// Фото: локальный файл, сеть или «нажми, чтобы загрузить» (экономия трафика).
class _NetImage extends StatefulWidget {
  final String? url;
  final String? localPath;
  final bool mine;
  final bool uploading;
  const _NetImage(
      {required this.url, this.localPath, required this.mine, this.uploading = false});
  @override
  State<_NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<_NetImage> {
  late bool _load = appState.autoDownloadPhotos || widget.mine;

  @override
  Widget build(BuildContext context) {
    const w = 250.0;
    final local = localExists(widget.localPath);
    Widget img;
    if (local) {
      img = localImage(widget.localPath!,
          width: w, fit: BoxFit.cover, cacheWidth: 800, gaplessPlayback: true);
    } else if (widget.url == null) {
      img = Container(width: w, height: 160, color: Colors.black12);
    } else if (!_load) {
      img = GestureDetector(
        onTap: () => setState(() => _load = true),
        child: Container(
          width: w,
          height: 170,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              appState.accent.withValues(alpha: 0.35),
              appState.accent.withValues(alpha: 0.15),
            ]),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.download, color: Colors.white, size: 30),
              SizedBox(height: 6),
              Text('Фото · нажми, чтобы загрузить',
                  style: TextStyle(color: Colors.white, fontSize: 12.5)),
            ],
          ),
        ),
      );
    } else {
      img = Image.network(
        widget.url!,
        width: w,
        fit: BoxFit.cover,
        cacheWidth: 800,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        gaplessPlayback: true,
        frameBuilder: (c, child, frame, sync) => sync || frame != null
            ? AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: child)
            : const Shimmer(width: w, height: 180, radius: 0),
        errorBuilder: (_, __, ___) => Container(
            width: w,
            height: 120,
            color: Colors.black12,
            child: const Icon(AppIcons.imageOff)),
      );
    }
    final r = (appState.bubbleRadius - 3).clamp(4.0, 30.0);
    return GestureDetector(
      onTap: (!_load && !local) || widget.uploading
          ? null
          : () => openImageViewer(context,
              url: widget.url, localPath: local ? widget.localPath : null),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360), child: img),
            if (widget.uploading)
              Positioned.fill(
                child: Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String kind;
  final String? name;
  final bool mine;
  final bool failed;
  const _UploadTile(
      {required this.kind, this.name, required this.mine, required this.failed});
  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      'image' => 'Фото',
      'video' => 'Видео',
      'voice' => 'Голосовое',
      'file' => name ?? 'Файл',
      _ => 'Вложение',
    };
    final fg = mine ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: failed
                ? const Icon(AppIcons.circleAlert, color: kDanger, size: 26)
                : CircularProgressIndicator(
                    strokeWidth: 2.6, color: mine ? Colors.white : appState.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                Text(failed ? 'Не отправлено · нажми и удерживай' : 'Отправка…',
                    style: TextStyle(
                        fontSize: 12,
                        color: failed
                            ? kDanger
                            : (mine ? Colors.white70 : subtleText(context)))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final String? url;
  final String? localPath;
  final String? name;
  const _VideoTile({this.url, this.localPath, this.name});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openVideo(context, url: url, localPath: localPath),
      child: Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular((appState.bubbleRadius - 3).clamp(4.0, 30.0)),
          gradient: const LinearGradient(
              colors: [Color(0xFF1F2937), Color(0xFF111827)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(AppIcons.play, color: Colors.white, size: 28),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Row(
                children: [
                  const Icon(AppIcons.video, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 180,
                    child: Text(name ?? 'Видео',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends StatefulWidget {
  final String url;
  final String name;
  final bool mine;
  final String? localPath;
  const _FileTile({
    required this.url,
    required this.name,
    required this.mine,
    this.localPath,
  });

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _downloading = false;
  double _progress = 0.0;
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _checkLocal();
  }

  Future<void> _checkLocal() async {
    final p = await FileOpener.findLocalPath(widget.name, localPath: widget.localPath);
    if (mounted && p != null) {
      setState(() => _isDownloaded = true);
    }
  }

  void _tap() {
    FileOpener.openOrDownload(
      context,
      url: widget.url,
      fileName: widget.name,
      localPath: widget.localPath,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      onStateChanged: (d) {
        if (mounted) {
          setState(() {
            _downloading = d;
            if (!d) _isDownloaded = true;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.name.contains('.') ? widget.name.split('.').last.toUpperCase() : 'FILE';
    final (fileColor, fileIcon) = FileOpener.getFileStyle(widget.name);
    final themeColor = widget.mine ? Colors.white : fileColor;

    return GestureDetector(
      onTap: _tap,
      child: SizedBox(
        width: 235,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: widget.mine
                    ? Colors.white.withValues(alpha: 0.22)
                    : fileColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.mine
                      ? Colors.white.withValues(alpha: 0.3)
                      : fileColor.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Center(
                child: _downloading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: _progress > 0 ? _progress : null,
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                        ),
                      )
                    : Icon(
                        _isDownloaded ? fileIcon : AppIcons.download,
                        color: themeColor,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: widget.mine ? Colors.white : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _downloading
                        ? (_progress > 0
                            ? 'Загрузка ${(_progress * 100).toInt()}%…'
                            : 'Загрузка…')
                        : (_isDownloaded
                            ? '${ext.length > 5 ? 'FILE' : ext} · Открыть'
                            : '${ext.length > 5 ? 'FILE' : ext} · Скачать и открыть'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: widget.mine ? Colors.white70 : subtleText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Голосовые
// ─────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final bool paused;
  final IconData icon;
  const _PulseDot({this.paused = false, this.icon = AppIcons.mic});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paused) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: cardColor(context),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(widget.icon, color: subtleText(context), size: 16),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 28 + 8 * _c.value,
            height: 28 + 8 * _c.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kDanger.withValues(alpha: 0.28 * (1.0 - _c.value * 0.4)),
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kDanger,
              boxShadow: [
                BoxShadow(
                  color: kDanger.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Icon(widget.icon, color: Colors.white, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Поле ввода
// ─────────────────────────────────────────────────────────────

class _MicButton extends StatefulWidget {
  final bool hasText;
  final bool hidden;
  final bool roundMode;
  final VoidCallback onSend, onStart, onEnd;
  final VoidCallback? onSendLong;
  final VoidCallback? onTapMode;
  final ValueChanged<Offset> onMove;
  const _MicButton({
    required this.hasText,
    this.hidden = false,
    this.roundMode = false,
    this.onTapMode,
    required this.onSend,
    this.onSendLong,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });
  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  Timer? _hold;
  Offset _origin = Offset.zero;
  bool _started = false;
  bool _down = false;
  bool _longFired = false;

  void _onDown(PointerDownEvent e) {
    setState(() => _down = true);
    _longFired = false;
    if (widget.hasText) {
      if (widget.onSendLong != null) {
        _hold = Timer(const Duration(milliseconds: 380), () {
          _longFired = true;
          HapticFeedback.mediumImpact();
          if (mounted) setState(() => _down = false);
          widget.onSendLong!();
        });
      }
      return;
    }
    _origin = e.position;
    _started = false;
    _hold = Timer(const Duration(milliseconds: 160), () {
      _started = true;
      widget.onStart();
    });
  }

  void _onMove(PointerMoveEvent e) {
    if (_started) widget.onMove(e.position - _origin);
  }

  void _onUp(PointerUpEvent e) {
    _hold?.cancel();
    setState(() => _down = false);
    if (widget.hasText) {
      if (_longFired) {
        _longFired = false;
        return;
      }
      widget.onSend();
      return;
    }
    if (_started) {
      _started = false;
      widget.onEnd();
    } else if (widget.onTapMode != null) {
      widget.onTapMode!(); // короткое нажатие: голосовое ⇄ видеосообщение
    } else {
      toast(context, 'Удерживай, чтобы записать голосовое', icon: AppIcons.mic);
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: (_) {
        _hold?.cancel();
        setState(() => _down = false);
        if (_started) {
          _started = false;
          widget.onEnd();
        }
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: widget.hidden ? 0 : 1,
        child: AnimatedScale(
        scale: _down ? (widget.hasText ? 0.9 : 1.18) : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: accentGradient(appState.accent),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: appState.accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (c, a) {
              if (c.key == const ValueKey('send')) {
                return RotationTransition(
                    turns: Tween(begin: 0.75, end: 1.0).animate(a),
                    child: ScaleTransition(scale: a, child: c));
              }
              // микрофон ⇄ камера: иконка переворачивается, как карточка
              return AnimatedBuilder(
                animation: a,
                child: c,
                builder: (_, child) {
                  final v = a.value.clamp(0.0, 1.0);
                  return Opacity(
                    opacity: v,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.003)
                        ..rotateY((1 - v) * math.pi / 2),
                      child: Transform.scale(scale: 0.55 + 0.45 * v, child: child),
                    ),
                  );
                },
              );
            },
            child: widget.hasText
                ? const Padding(
                    padding: EdgeInsets.only(left: 2.5),
                    child: Icon(AppIcons.send, key: ValueKey('send'), color: Colors.white, size: 23),
                  )
                : Icon(
                    widget.roundMode ? AppIcons.video : AppIcons.mic,
                    key: ValueKey(widget.roundMode ? 'round' : 'mic'),
                    color: Colors.white,
                    size: 24,
                  ),
          ),
        ),
      ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final bool micHidden;
  final bool roundMode;
  final VoidCallback? onMicTap;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final bool emojiOpen;
  final String hint;
  final bool showCommands;
  final VoidCallback onCommands;
  final VoidCallback onSend, onAttach, onEmoji, onMicStart, onMicEnd, onFieldTap;
  final VoidCallback? onSendLong;
  final ValueChanged<Offset> onMicMove;
  const _InputBar({
    this.micHidden = false,
    this.roundMode = false,
    this.onMicTap,
    this.onSendLong,
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.emojiOpen,
    required this.hint,
    required this.showCommands,
    required this.onCommands,
    required this.onSend,
    required this.onAttach,
    required this.onEmoji,
    required this.onFieldTap,
    required this.onMicStart,
    required this.onMicMove,
    required this.onMicEnd,
  });

  @override
  Widget build(BuildContext context) {
    final glassColor = cardColor(context).withValues(alpha: 0.78);
    final glassBorder = Border.all(color: Colors.white.withValues(alpha: 0.12));
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 1. Отдельный стеклянный блок: Смайлик / Клавиатура
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: BorderRadius.circular(22),
                border: glassBorder,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    emojiOpen ? AppIcons.keyboard : AppIcons.smile,
                    key: ValueKey(emojiOpen),
                    color: emojiOpen ? appState.accent : subtleText(context),
                    size: 22,
                  ),
                ),
                onPressed: onEmoji,
              ),
            ),
            const SizedBox(width: 6),
            // 2. Отдельный стеклянный блок: Поле ввода сообщения
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  color: glassColor,
                  borderRadius: BorderRadius.circular(22),
                  border: glassBorder,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onTap: onFieldTap,
                        minLines: 1,
                        maxLines: 6,
                        maxLength: 4000,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: hint,
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (showCommands && !hasText)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Icon(AppIcons.squareSlash, color: subtleText(context), size: 19),
                        onPressed: onCommands,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 3. Отдельный стеклянный блок: Скрепка (вложения)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: BorderRadius.circular(22),
                border: glassBorder,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(AppIcons.paperclip, color: subtleText(context), size: 21),
                onPressed: onAttach,
              ),
            ),
            const SizedBox(width: 6),
            // 4. Отдельный блок: Отправка / Запись микрофона
            _MicButton(
              hasText: hasText,
              hidden: micHidden,
              roundMode: roundMode,
              onTapMode: onMicTap,
              onSend: onSend,
              onSendLong: onSendLong,
              onStart: onMicStart,
              onMove: onMicMove,
              onEnd: onMicEnd,
            ),
          ],
        ),
      ),
    );
  }
}

/// Панель под полем ввода: эмодзи и GIF (поиск через наш сервер).
class _EmojiPanel extends StatefulWidget {
  final ValueChanged<String> onPick;
  final ValueChanged<String>? onGif;
  const _EmojiPanel({required this.onPick, this.onGif});
  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<_EmojiPanel> {
  bool _gifTab = false;

  @override
  Widget build(BuildContext context) {
    final canGif = widget.onGif != null;
    return SafeArea(
      top: false,
      child: Container(
        height: 300,
        color: cardColor(context),
        child: Column(
          children: [
            if (canGif)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  children: [
                    _tab('Эмодзи', !_gifTab, () => setState(() => _gifTab = false)),
                    const SizedBox(width: 6),
                    _tab('GIF', _gifTab, () => setState(() => _gifTab = true)),
                  ],
                ),
              ),
            Expanded(
              child: _gifTab && canGif
                  ? _GifGrid(onPick: widget.onGif!)
                  : GridView.count(
                      crossAxisCount: 8,
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final e in _kEmojis)
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => widget.onPick(e),
                            child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, bool on, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: on ? appState.accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: on ? appState.accent : subtleText(context))),
        ),
      );
}

/// Сетка GIF: популярные / поиск, подгрузка при прокрутке.
class _GifGrid extends StatefulWidget {
  final ValueChanged<String> onPick;
  const _GifGrid({required this.onPick});
  @override
  State<_GifGrid> createState() => _GifGridState();
}

class _GifGridState extends State<_GifGrid> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  List<String> _cats = const [];
  int? _next = 0;
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_error == null && _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _load();
      }
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || _next == null)) return;
    final id = ++_req;
    if (reset) {
      _items.clear();
      _next = 0;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.gifs(_q.text.trim(), offset: _next ?? 0);
      if (!mounted || id != _req) return;
      final items = ((r['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .where((e) => e['url'] is String)
          .toList();
      setState(() {
        _items.addAll(items);
        _next = (r['next'] as num?)?.toInt();
        _cats = ((r['categories'] as List?) ?? const []).map((e) => '$e').toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _req) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _search(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _q,
              onChanged: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(reset: true),
              decoration: InputDecoration(
                hintText: 'Поиск GIF',
                isDense: true,
                prefixIcon: const Icon(AppIcons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(19), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        if (_cats.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final c in _cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(c, style: const TextStyle(fontSize: 12.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _q.text = c;
                        _load(reset: true);
                      },
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _error != null && _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center,
                          style: TextStyle(color: subtleText(context))),
                      TextButton(
                          onPressed: () => _load(reset: true), child: const Text('Повторить')),
                    ],
                  ),
                )
              : _items.isEmpty && _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Text('Ничего не нашлось',
                              style: TextStyle(color: subtleText(context))))
                      : GridView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(6),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 140,
                              mainAxisSpacing: 5,
                              crossAxisSpacing: 5,
                              childAspectRatio: 1.25),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final g = _items[i];
                            final prev = (g['preview'] ?? g['url']) as String;
                            return GestureDetector(
                              onTap: () => widget.onPick(g['url'] as String),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  prev,
                                  fit: BoxFit.cover,
                                  cacheWidth: 280,
                                  // в браузере чужие сайты могут не отдавать CORS — тогда <img>
                                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) =>
                                      Container(color: Colors.black12),
                                  frameBuilder: (c, child, frame, sync) =>
                                      sync || frame != null
                                          ? child
                                          : const Shimmer(height: 110, radius: 0),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

class _PinnedBanner extends StatelessWidget {
  final String text;
  final bool canUnpin;
  final VoidCallback onClose;
  final VoidCallback onUnpin;
  final VoidCallback onTap;
  const _PinnedBanner(
      {required this.text,
      required this.canUnpin,
      required this.onClose,
      required this.onUnpin,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardColor(context),
      child: InkWell(
        onTap: onTap,
        onLongPress: canUnpin ? onUnpin : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 7, 4, 7),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                    color: appState.accent, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Закреплённое сообщение',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: appState.accent)),
                    Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: subtleText(context))),
                  ],
                ),
              ),
              if (canUnpin)
                IconButton(
                  tooltip: 'Открепить',
                  icon: Icon(AppIcons.pinOff, size: 19, color: subtleText(context)),
                  onPressed: onUnpin,
                ),
              IconButton(
                tooltip: 'Скрыть',
                icon: Icon(AppIcons.x, size: 20, color: subtleText(context)),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Выбор чата для пересылки (только те, куда можно писать).
class _ForwardPicker extends StatefulWidget {
  const _ForwardPicker();
  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await Api.chats();
      if (!mounted) return;
      setState(() {
        _chats = c
            .map((e) => (e as Map).cast<String, dynamic>())
            .where((c) => c['can_send'] != false)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _chats
        : _chats
            .where((c) => ((c['title'] as String?) ?? '').toLowerCase().contains(q))
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Переслать в…')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: AppTextField(
                controller: _q,
                hint: 'Поиск чата',
                icon: AppIcons.search,
                onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: _loading
                ? const SingleChildScrollView(child: ListSkeleton())
                : list.isEmpty
                    ? const EmptyState(
                        icon: AppIcons.messageCircleOff,
                        mascot: 'empty_not_found',
                        title: 'Нет подходящих чатов')
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          final name = (c['title'] as String?) ?? 'Чат';
                          final type = c['type'];
                          return ListTile(
                            leading: Avatar(
                              name: name,
                              url: c['avatar_url'] as String?,
                              size: 46,
                              useAccent: c['is_system'] == true,
                              icon: c['is_system'] == true
                                  ? AppIcons.shieldCheck
                                  : (type == 'channel'
                                      ? AppIcons.megaphone
                                      : (type == 'group' ? AppIcons.users : null)),
                            ),
                            title: NameBadges(name,
                                verified: c['is_verified'] == true,
                                bot: c['peer_is_bot'] == true && c['is_system'] != true,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15.5)),
                            subtitle: Text(
                                type == 'channel'
                                    ? 'канал'
                                    : (type == 'group' ? 'группа' : 'личный чат'),
                                style: TextStyle(color: subtleText(context))),
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}


/// Подарок в переписке: большая карточка, тап — показать на весь экран.
class _GiftContent extends StatelessWidget {
  final Map<String, dynamic> data;
  final String text;
  final bool mine;
  const _GiftContent({required this.data, required this.text, required this.mine});

  @override
  Widget build(BuildContext context) {
    final g = (data['gift'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rarity = g['rarity'] as String? ?? 'common';
    final serial = data['serial'];
    final rc = rarityColor(rarity);
    final legend = rarity == 'legendary';
    final fromConnecto = data['from_connecto'] == true;
    final headline = mine
        ? 'Вы подарили'
        : (fromConnecto
            ? 'Подарок от Connecto'
            : (data['anonymous'] == true ? 'Анонимный подарок' : 'Подарок для вас'));
    void reveal() => showGiftReveal(
          context,
          {'gift': g, 'serial': serial, 'supply': g['supply'], 'text': text, 'anonymous': data['anonymous']},
          title: headline,
        );
    return GestureDetector(
      onTap: reveal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 260,
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: rc.withValues(alpha: 0.16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: legend
                    ? [
                        const Color(0xFFFFD166).withValues(alpha: 0.32),
                        const Color(0xFF7A4A00).withValues(alpha: 0.18),
                      ]
                    : [
                        rc.withValues(alpha: 0.30),
                        rc.withValues(alpha: 0.08),
                      ],
              ),
              border: Border.all(
                color: (legend ? const Color(0xFFFFD166) : rc).withValues(alpha: 0.55),
                width: legend ? 1.6 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: rc.withValues(alpha: 0.28),
                  blurRadius: 22,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                GiftArt(gift: g, size: 150),
                const SizedBox(height: 12),
                Text(headline,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(g['title'] as String? ?? 'Подарок',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(blurRadius: 10, color: rc.withValues(alpha: 0.6)),
                          const Shadow(blurRadius: 8, color: Colors.black45),
                        ])),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: rc.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '${rarityName(rarity)}${serial != null ? ' · №$serial' : ''}',
                    style: TextStyle(
                      color: rc,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (text.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('«${text.trim()}»',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.sparkles, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(mine ? 'Посмотреть' : 'Открыть подарок',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                if (!mine) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => UserInfoScreen(
                                userId: appState.myUserId ?? '', name: appState.displayName))),
                    child: Text('Уже в вашем профиле →',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Ответ на историю»: превью над текстом.
class _StoryReplyChip extends StatelessWidget {
  final Map<String, dynamic> story;
  final bool mine;
  const _StoryReplyChip({required this.story, required this.mine});

  @override
  Widget build(BuildContext context) {
    final owner = story['owner_id'] as String? ?? '';
    final isMyStory = owner == appState.myUserId;
    return GestureDetector(
      onTap: () => openStoriesOf(context, owner),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withValues(alpha: 0.16) : appState.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 46,
              child: StoryThumb(
                  mediaUrl: mediaUrl(story['media_url'] as String?),
                  video: story['kind'] == 'video',
                  radius: 8),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.stories, size: 13, color: mine ? Colors.white : appState.accent),
                      const SizedBox(width: 4),
                      Text('История',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: mine ? Colors.white : appState.accent)),
                    ],
                  ),
                  Text(
                      isMyStory
                          ? 'ответ на вашу историю'
                          : 'ответ на историю ${story['owner_name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: mine ? Colors.white70 : subtleText(context))),
                ],
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}


/// Появление нового сообщения: плавное появление со своей стороны.
class _MessageAppear extends StatefulWidget {
  final Widget child;
  final bool fromRight;
  final VoidCallback? onComplete;
  const _MessageAppear(
      {super.key, required this.child, required this.fromRight, this.onComplete});
  @override
  State<_MessageAppear> createState() => _MessageAppearState();
}

class _MessageAppearState extends State<_MessageAppear> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));

  @override
  void initState() {
    super.initState();
    if (appState.motion) {
      _c.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      });
      _c.forward();
    } else {
      _c.value = 1;
      widget.onComplete?.call();
    }
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
      child: widget.child,
      builder: (_, child) {
        final t = _c.value;
        final pos = Curves.easeOutCubic.transform(t);
        return Opacity(
          opacity: Curves.easeOut.transform(math.min(1.0, t * 1.5)),
          child: Transform.translate(
            offset: Offset((widget.fromRight ? 16 : -16) * (1 - pos), 0),
            child: Transform.scale(
              scale: 0.94 + 0.06 * pos,
              alignment: widget.fromRight ? Alignment.bottomRight : Alignment.bottomLeft,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
