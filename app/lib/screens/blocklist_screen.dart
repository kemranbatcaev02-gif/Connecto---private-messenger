import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';

/// Чёрный список — заблокированные пользователи, с разблокировкой.
class BlocklistScreen extends StatefulWidget {
  const BlocklistScreen({super.key});

  @override
  State<BlocklistScreen> createState() => _BlocklistScreenState();
}

class _BlocklistScreenState extends State<BlocklistScreen> {
  List<dynamic> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await Api.blockedUsers();
      if (mounted) setState(() { _users = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _unblock(Map<String, dynamic> u) async {
    try {
      await Api.unblockUser(u['id'] as String);
      setState(() => _users.removeWhere((x) => x['id'] == u['id']));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Разблокирован')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чёрный список')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: appState.accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.triangleAlert,
                            color: subtleText(context), size: 34),
                        const SizedBox(height: 12),
                        Text('Не удалось загрузить',
                            style: TextStyle(color: subtleText(context))),
                        TextButton(
                            onPressed: _load, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : _users.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.userCheck,
                                color: subtleText(context), size: 40),
                            const SizedBox(height: 14),
                            Text('Никто не заблокирован',
                                style: TextStyle(color: subtleText(context))),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final u = _users[i] as Map<String, dynamic>;
                        final avatar = u['avatar_url'] as String?;
                        final name =
                            (u['display_name'] ?? u['username'] ?? '?').toString();
                        final handle = u['handle'] as String?;
                        return Container(
                          decoration: BoxDecoration(
                              color: cardColor(context),
                              borderRadius: BorderRadius.circular(kRadius)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: accentGradient(appState.accent),
                                  image: (avatar != null && avatar.isNotEmpty)
                                      ? DecorationImage(
                                          image: NetworkImage('$kBaseUrl$avatar'),
                                          fit: BoxFit.cover)
                                      : null,
                                ),
                                child: (avatar != null && avatar.isNotEmpty)
                                    ? null
                                    : Center(
                                        child: Text(
                                            name.characters.first.toUpperCase(),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    if (handle != null && handle.isNotEmpty)
                                      Text('@$handle',
                                          style: TextStyle(
                                              color: subtleText(context),
                                              fontSize: 13)),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => _unblock(u),
                                child: Text('Разблокировать',
                                    style: TextStyle(color: appState.accent)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
