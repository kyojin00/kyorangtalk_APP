import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/friends_provider.dart';
import '../widgets/friend_tile.dart';

// ═══════════════════════════════════════════════
// 친구 요청함 (받은 요청 + 보낸 요청)
//
// 위치: lib/features/friends/sheets/requests_sheet.dart
//
// 콜백:
//   - onAccept(requestId) : 받은 요청 수락 → 수락 후 시트 자동 닫힘
//   - onReject(requestId) : 받은 요청 거절
//   - onCancel(requestId) : 보낸 요청 취소
// ═══════════════════════════════════════════════

class RequestsSheet extends ConsumerWidget {
  final void Function(String requestId) onAccept;
  final void Function(String requestId) onReject;
  final void Function(String requestId) onCancel;

  const RequestsSheet({
    super.key,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingRequestsProvider);
    final sentAsync    = ref.watch(sentRequestsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          _SheetHandle(),
          Expanded(
            child: ListView(
              controller: sc,
              children: [
                _SectionTitle(
                  title: '받은 요청',
                  badge: pendingAsync.value?.length ?? 0,
                ),
                pendingAsync.when(
                  loading: () => const _LoadingIndicator(),
                  error: (_, __) => const SizedBox(),
                  data: (requests) => requests.isEmpty
                      ? const _EmptyText('받은 요청이 없어요')
                      : Column(
                          children: requests.map((req) {
                            return RequestTile(
                              request: req,
                              onAccept: () {
                                onAccept(req['id'] as String);
                                Navigator.pop(context);
                              },
                              onReject: () =>
                                  onReject(req['id'] as String),
                            );
                          }).toList(),
                        ),
                ),
                Divider(color: AppTheme.border),
                const _SectionTitle(title: '보낸 요청'),
                sentAsync.when(
                  loading: () => const _LoadingIndicator(),
                  error: (_, __) => const SizedBox(),
                  data: (sent) => sent.isEmpty
                      ? const _EmptyText('보낸 요청이 없어요')
                      : Column(
                          children: sent.map((req) {
                            return _SentRequestRow(
                              request: req,
                              onCancel: () =>
                                  onCancel(req['id'] as String),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 보낸 요청 한 줄 (취소 버튼만 있음) ───
class _SentRequestRow extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onCancel;

  const _SentRequestRow({
    required this.request,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          AvatarWidget(
            url: request['avatar_url'] as String?,
            name: request['nickname'] as String?,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['nickname'] as String? ?? '알 수 없음',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain),
                ),
                Text('대기 중',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSub)),
              ],
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('취소',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── 시트 상단 손잡이 ───
class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ─── 섹션 제목 + 뱃지 ───
class _SectionTitle extends StatelessWidget {
  final String title;
  final int badge;

  const _SectionTitle({required this.title, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain)),
          if (badge > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$badge',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 빈 상태 텍스트 ───
class _EmptyText extends StatelessWidget {
  final String message;
  const _EmptyText(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Text(message,
          style: TextStyle(
              color: AppTheme.textSub, fontSize: 13)),
    );
  }
}

// ─── 로딩 표시 ───
class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );
  }
}