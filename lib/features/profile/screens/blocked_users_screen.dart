import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

final blockedUsersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  final blocks = await Supabase.instance.client
      .from('kyorangtalk_blocks')
      .select('blocked_id, created_at')
      .eq('blocker_id', user.id)
      .order('created_at', ascending: false);

  if (blocks.isEmpty) return [];

  final blockedIds =
      blocks.map((b) => b['blocked_id'] as String).toList();

  final profiles = await Supabase.instance.client
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url, status_message')
      .inFilter('id', blockedIds);

  final profileMap = {
    for (final p in profiles) p['id'] as String: p
  };

  return blocks.map((b) {
    final prof = profileMap[b['blocked_id']];
    return {
      'blocked_id': b['blocked_id'],
      'nickname': prof?['nickname'] ?? '알 수 없음',
      'avatar_url': prof?['avatar_url'],
      'status_message': prof?['status_message'],
      'created_at': b['created_at'],
    };
  }).toList();
});

Future<void> unblockUser(String blockedId) async {
  final user = Supabase.instance.client.auth.currentUser!;
  await Supabase.instance.client
      .from('kyorangtalk_blocks')
      .delete()
      .eq('blocker_id', user.id)
      .eq('blocked_id', blockedId);
}

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('차단한 친구',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: blockedAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
        error: (e, _) => Center(
          child: Text('오류: $e',
              style: TextStyle(color: AppTheme.textSub)),
        ),
        data: (blocked) {
          if (blocked.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block,
                      size: 48, color: AppTheme.textMuted),
                  const SizedBox(height: 16),
                  Text('차단한 친구가 없어요',
                      style: TextStyle(
                          color: AppTheme.textSub,
                          fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(
                      '친구 프로필에서 차단할 수 있어요',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12)),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppTheme.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '차단한 친구는 나를 찾거나 메시지를 보낼 수 없어요',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSub),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: blocked.length,
                  itemBuilder: (_, i) {
                    final user = blocked[i];
                    return _BlockedUserTile(
                      user: user,
                      onUnblock: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppTheme.bgCard,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(16)),
                            title: Text('차단 해제',
                                style: TextStyle(
                                    color: AppTheme.textMain,
                                    fontWeight: FontWeight.w700)),
                            content: Text(
                                '${user['nickname']}님의 차단을 해제하시겠어요?\n다시 메시지를 주고받을 수 있어요.',
                                style: TextStyle(
                                    color: AppTheme.textSub,
                                    fontSize: 14)),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, false),
                                child: Text('취소',
                                    style: TextStyle(
                                        color:
                                            AppTheme.textSub)),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, true),
                                child: Text('해제',
                                    style: TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight:
                                            FontWeight.w700)),
                              ),
                            ],
                          ),
                        );

                        if (confirm != true) return;

                        try {
                          await unblockUser(
                              user['blocked_id']);
                          ref.invalidate(blockedUsersProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '${user['nickname']}님의 차단을 해제했어요'),
                                  backgroundColor:
                                      AppTheme.bgCard),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              SnackBar(
                                  content: Text('실패: $e'),
                                  backgroundColor:
                                      AppTheme.bgCard),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onUnblock;

  const _BlockedUserTile({
    required this.user,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          AvatarWidget(
              url: user['avatar_url'] as String?,
              name: user['nickname'] as String,
              size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['nickname'] as String,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain)),
                if (user['status_message'] != null &&
                    (user['status_message'] as String).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(user['status_message'] as String,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onUnblock,
            style: TextButton.styleFrom(
              backgroundColor:
                  AppTheme.primary.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('차단 해제',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}