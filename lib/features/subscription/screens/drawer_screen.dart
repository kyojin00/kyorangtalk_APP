import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../chat/providers/chat_provider.dart' as chat_provider;
import '../services/subscription_service.dart';
import 'subscription_screen.dart';

// ═══════════════════════════════════════════════
// 🗄️ 내 서랍 화면
//
// 위치: lib/features/subscription/screens/drawer_screen.dart
//
// 나간 채팅방 목록 표시.
// 구독 안 한 상태면: 목록 블러 + 결제 유도
// 구독 한 상태면: 방 탭 → 옛 메시지 복원
// ═══════════════════════════════════════════════

class DrawerScreen extends ConsumerWidget {
  const DrawerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSubAsync = ref.watch(hasActiveSubscriptionProvider);
    final hiddenRoomsAsync = ref.watch(hiddenRoomsProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '메시지 서랍',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined,
                color: AppTheme.textSub),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: hasSubAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
        error: (e, _) => Center(
          child: Text('오류: $e',
              style: TextStyle(color: AppTheme.textSub)),
        ),
        data: (hasSub) {
          return hiddenRoomsAsync.when(
            loading: () => const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primary),
            ),
            error: (e, _) => Center(
              child: Text('오류: $e',
                  style: TextStyle(color: AppTheme.textSub)),
            ),
            data: (rooms) {
              if (rooms.isEmpty) {
                return _EmptyState();
              }

              return Column(
                children: [
                  // 상단 안내
                  if (!hasSub)
                    _SubscribeBanner(roomCount: rooms.length)
                  else
                    _ActiveBanner(
                        roomCount: rooms.length, ref: ref),

                  // 방 목록 (구독 안 했으면 블러)
                  Expanded(
                    child: Stack(
                      children: [
                        // 리스트 본체
                        ListView.separated(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          itemCount: rooms.length,
                          // 구독 X 일 때 스크롤·탭 불가
                          physics: hasSub
                              ? const BouncingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          separatorBuilder: (_, __) => Divider(
                              color: AppTheme.border,
                              height: 1,
                              indent: 80),
                          itemBuilder: (_, i) {
                            final room = rooms[i];
                            return _HiddenRoomTile(
                              room: room,
                              hasSubscription: hasSub,
                              onTap: hasSub
                                  ? () => _handleTap(
                                      context, ref, room, true)
                                  : () => _goSubscribe(context, ref),
                            );
                          },
                        ),

                        // 구독 안 했으면 블러 + 결제 유도 오버레이
                        if (!hasSub)
                          Positioned.fill(
                            child: _LockedOverlay(
                              onSubscribe: () =>
                                  _goSubscribe(context, ref),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _goSubscribe(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SubscriptionScreen(),
      ),
    ).then((_) {
      ref.invalidate(hasActiveSubscriptionProvider);
      ref.invalidate(subscriptionProvider);
    });
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    HiddenRoom room,
    bool hasSubscription,
  ) async {
    if (!hasSubscription) {
      _goSubscribe(context, ref);
      return;
    }

    // 복원 확인
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          '옛 메시지 복원',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '${room.partnerName}님과의 옛 메시지 '
          '${room.hiddenMessagesCount}개를 복원할까요?',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '복원',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await chat_provider.restoreChatRoom(room.roomId);
      ref.invalidate(hiddenRoomsProvider);
      ref.invalidate(chat_provider.chatRoomsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${room.partnerName}님 옛 메시지를 복원했어요'),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복원 실패: $e')),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════
// 잠금 오버레이 (블러 + 결제 유도)
// ═══════════════════════════════════════════════
class _LockedOverlay extends StatelessWidget {
  final VoidCallback onSubscribe;
  const _LockedOverlay({required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: AppTheme.bg.withOpacity(0.55),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary,
                        AppTheme.primary.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '서랍이 잠겨있어요',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '구독하면 나간 채팅방의 옛 메시지를\n언제든지 다시 볼 수 있어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSub,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onSubscribe,
                    icon:
                        const Icon(Icons.lock_open_rounded, size: 18),
                    label: const Text(
                      '서랍 열기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '7일 이내 미사용 시 100% 환불',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 빈 상태
// ═══════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🗄️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            '서랍이 비어있어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '나간 채팅방이 여기에 보관돼요',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSub,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 구독 유도 배너 (블러는 아래 리스트에 적용되므로 배너는 그대로 보임)
// ═══════════════════════════════════════════════
class _SubscribeBanner extends StatelessWidget {
  final int roomCount;
  const _SubscribeBanner({required this.roomCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.15),
            AppTheme.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Text('🔒', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$roomCount개의 대화가 잠겨있어요',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '서랍을 열면 모두 다시 볼 수 있어요',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSub,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              '열기',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 활성 상태 배너
// ═══════════════════════════════════════════════
class _ActiveBanner extends StatelessWidget {
  final int roomCount;
  final WidgetRef ref;
  const _ActiveBanner({required this.roomCount, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '서랍이 열려있어요 · $roomCount개의 대화',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMain,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _restoreAll(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
            child: Text(
              '전체 복원',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          '전체 복원',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '모든 옛 채팅 메시지를 복원할까요?',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '복원',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final count = await SubscriptionService.restoreAllRooms();
      ref.invalidate(hiddenRoomsProvider);
      ref.invalidate(chat_provider.chatRoomsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count개 채팅방의 옛 메시지를 복원했어요'),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('실패: $e')),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════
// 숨겨진 방 타일
// ═══════════════════════════════════════════════
class _HiddenRoomTile extends StatelessWidget {
  final HiddenRoom room;
  final bool hasSubscription;
  final VoidCallback onTap;

  const _HiddenRoomTile({
    required this.room,
    required this.hasSubscription,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarWidget(
                  url: room.partnerAvatar,
                  name: room.partnerName,
                  size: 48,
                ),
                if (!hasSubscription)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppTheme.bg, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.lock,
                        size: 11,
                        color: AppTheme.textSub,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.partnerName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${room.hiddenMessagesCount}개의 메시지 보관됨',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSub,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              hasSubscription
                  ? Icons.chevron_right
                  : Icons.lock_outline,
              color: AppTheme.textSub,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}