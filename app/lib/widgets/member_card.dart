import 'package:flutter/material.dart';
import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import 'shop_media.dart';
import 'ui.dart';
import 'user_picker.dart';

/// Стильная Discord-карточка участника в списке группы/сервера с индивидуальным фоном,
/// анимированной рамкой аватара и статусом.
class MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback? onTap;
  final Widget? trailing;
  final EdgeInsetsGeometry? margin;

  const MemberCard({
    super.key,
    required this.member,
    this.onTap,
    this.trailing,
    this.margin,
  });

  static const _discordThemes = [
    [Color(0xFF261238), Color(0xFF11081A)], // Midnight Nebula
    [Color(0xFF38121B), Color(0xFF19060B)], // Crimson Eclipse
    [Color(0xFF0D2D20), Color(0xFF071710)], // Emerald Aurora
    [Color(0xFF102138), Color(0xFF09121F)], // Deep Sapphire
    [Color(0xFF33180B), Color(0xFF1A0B05)], // Sunset Amber
    [Color(0xFF280F33), Color(0xFF14071A)], // Amethyst Glow
    [Color(0xFF182233), Color(0xFF0D121B)], // Cyber Slate
    [Color(0xFF231D18), Color(0xFF120E0C)], // Gothic Bronze
  ];

  @override
  Widget build(BuildContext context) {
    final m = member;
    final name = userName(m);
    final role = m['role'] as String? ?? 'member';
    final isMe = m['id'] == appState.myUserId;
    final isOnline = m['online'] == true;
    final isBot = m['is_bot'] == true;
    final status = isBot
        ? 'бот'
        : lastSeenText(parseServerTime(m['last_seen'] as String? ?? ''), online: isOnline);

    final coverUrl = (m['cover_url'] as String?) ?? (isMe ? appState.coverUrl : null);
    final coverKind = (m['cover_kind'] as String?) ?? (isMe ? appState.coverKind : null);
    final frame = (m['frame'] is Map)
        ? (m['frame'] as Map).cast<String, dynamic>()
        : (isMe ? appState.wornFrame : null);

    // Выбираем атмосферный Discord-фон для участников без купленной обложки
    final idHash = (m['id'] as String? ?? name).hashCode.abs();
    final themeColors = _discordThemes[idHash % _discordThemes.length];

    String? roleLabel;
    if (role == 'owner') roleLabel = 'владелец';
    if (role == 'admin') roleLabel = 'администратор';

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 0, vertical: 3.5),
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Индивидуальный фон (купленная обложка профиля или стильная Discord-тема)
          if (coverUrl != null && coverUrl.isNotEmpty)
            Positioned.fill(
              child: ShopMedia(
                url: coverUrl,
                kind: coverKind,
                fit: BoxFit.cover,
                still: true,
              ),
            )
          else
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: themeColors,
                  ),
                ),
              ),
            ),

          // 2. Затемняющий градиент для кристальной читаемости текста поверх фона
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.65, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.82),
                    Colors.black.withValues(alpha: 0.68),
                    Colors.black.withValues(alpha: 0.52),
                  ],
                ),
              ),
            ),
          ),

          // 3. Контент участника: Аватарка с рамкой, имя, бейджи, статус и кнопка/роль
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // Аватарка с анимированной рамкой магазина
                    FramedAvatar(
                      size: 38,
                      frame: frame,
                      child: Avatar(
                        name: name,
                        url: m['avatar_url'] as String?,
                        size: 38,
                        online: isOnline,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Имя, бейджи и статус
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NameBadges(
                            isMe ? '$name (вы)' : name,
                            verified: m['is_verified'] == true,
                            premium: m['is_premium'] == true,
                            bot: isBot,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 1.5),
                          Row(
                            children: [
                              if (isOnline)
                                Container(
                                  width: 6.5,
                                  height: 6.5,
                                  margin: const EdgeInsets.only(right: 5),
                                  decoration: const BoxDecoration(
                                    color: kSuccess,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(color: kSuccess, blurRadius: 4),
                                    ],
                                  ),
                                ),
                              Text(
                                status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isOnline ? const Color(0xFF4ADE80) : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Кастомный трейлинг или роль (Владелец / Администратор)
                    if (trailing != null)
                      trailing!
                    else if (roleLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: (role == 'owner' ? kPremium : appState.accent).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (role == 'owner' ? kPremium : appState.accent).withValues(alpha: 0.5),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: role == 'owner' ? kPremium : Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
