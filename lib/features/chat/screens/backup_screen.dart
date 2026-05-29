import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../subscription/screens/subscription_screen.dart';
import '../models/chat_room_model.dart';
import '../providers/chat_provider.dart' as chat_provider;
import '../services/message_backup_service.dart';
import '../services/message_cache_service.dart';
import '../services/subscription_service.dart';

// ═══════════════════════════════════════════════════
// ☁️ BackupScreen (= 메시지 서랍)
//
// 위치: lib/features/chat/screens/backup_screen.dart
//
// ⭐ 변경점 (v4)
// 1. 메시지 양 숨김 — 대화방 + 용량 두 칸만 표시
// 2. 용량은 메시지당 평균 추정치 (~ 표시)
//    정확한 값은 MessageCacheService 에 DM-only stats 함수 추가 시 가능
// 3. 미디어 백업 (사진/동영상/파일) 은 별도 작업
//    → MessageBackupService 코드 받은 후 진행
// ═══════════════════════════════════════════════════
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _loading = true;
  bool _busy = false;
  List<BackupInfo> _backups = [];

  // ⭐ DM 전용 통계
  int _dmRoomCount = 0;
  int _dmMessageCount = 0; // _createBackup 가드용 (UI 노출 X)
  int _dmEstimatedBytes = 0;

  // 메시지당 평균 크기 추정 (메타데이터 + content 평균)
  static const int _bytesPerMessageEstimate = 300;

  bool _listenerRegistered = false;

  @override
  void initState() {
    super.initState();
    _load();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);
      _listenerRegistered = true;

      final rooms =
          ref.read(chat_provider.chatRoomsProvider).value;
      if (rooms != null) _recomputeDmStats(rooms);
    });
  }

  @override
  void dispose() {
    if (_listenerRegistered) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdate);
    }
    super.dispose();
  }

  void _onCustomerInfoUpdate(CustomerInfo info) {
    if (!mounted) return;
    ref.invalidate(subscriptionStatusProvider);
  }

  // ⭐ chatRoomsProvider 데이터로부터 DM 전용 통계 재계산
  void _recomputeDmStats(List<ChatRoomModel> rooms) {
    int messages = 0;
    int roomsWithCache = 0;
    for (final r in rooms) {
      final c = MessageCacheService.loadDM(r.roomId);
      if (c != null && c.messages.isNotEmpty) {
        roomsWithCache++;
        messages += c.messages.length;
      }
    }
    if (!mounted) return;
    setState(() {
      _dmRoomCount = roomsWithCache;
      _dmMessageCount = messages;
      _dmEstimatedBytes = messages * _bytesPerMessageEstimate;
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final backups = await MessageBackupService.listBackups();
    if (!mounted) return;
    setState(() {
      _backups = backups;
      _loading = false;
    });

    final rooms = ref.read(chat_provider.chatRoomsProvider).value;
    if (rooms != null) _recomputeDmStats(rooms);
  }

  Future<void> _goToSubscription() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
    if (!mounted) return;
    ref.invalidate(subscriptionStatusProvider);
    await _load();
  }

  // ───────────────────────────────────────────────
  // 백업 만들기
  // ───────────────────────────────────────────────
  Future<void> _createBackup() async {
    if (_busy) return;

    final status = await ref.read(subscriptionStatusProvider.future);
    if (!mounted) return;

    if (!status.isPro) {
      await _goToSubscription();
      return;
    }

    if (_dmMessageCount == 0) {
      _snack('백업할 메시지가 없어요');
      return;
    }

    setState(() => _busy = true);

    final ctrl = ValueNotifier<_ProgressState>(
      _ProgressState(0.0, '준비 중...'),
    );

    _showProgressDialog(ctrl, '백업 중');

    final result = await MessageBackupService.createBackup(
      onProgress: (p, s) => ctrl.value = _ProgressState(p, s),
    );

    if (!mounted) return;
    Navigator.pop(context);

    setState(() => _busy = false);

    if (result.isSuccess) {
      _snack(
        '백업 완료 · ${result.messageCount}개 메시지 · ${_fmtBytes(result.fileSize ?? 0)}',
      );
      await _load();
    } else {
      _snack(result.errorMessage ?? '백업에 실패했어요');
    }
  }

  // ───────────────────────────────────────────────
  // 복원
  // ───────────────────────────────────────────────
  Future<void> _restoreBackup(BackupInfo b) async {
    if (_busy) return;

    final mode = await showDialog<_RestoreMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '백업 복원',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${b.messageCount}개 메시지, ${b.roomCount}개 방을 복원합니다.',
              style: TextStyle(color: AppTheme.textSub, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('병합 복원',
                      style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('현재 메시지는 두고, 백업에 있는 것만 추가/덮어쓰기',
                      style: TextStyle(
                          color: AppTheme.textSub, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('전체 교체',
                      style: TextStyle(
                          color: const Color(0xFFEF4444),
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('현재 모든 캐시를 삭제하고 백업 내용으로 교체',
                      style: TextStyle(
                          color: AppTheme.textSub, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RestoreMode.replace),
            child: const Text('전체 교체',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RestoreMode.merge),
            child: Text('병합',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (mode == null || !mounted) return;

    setState(() => _busy = true);

    final ctrl = ValueNotifier<_ProgressState>(
      _ProgressState(0.0, '준비 중...'),
    );

    _showProgressDialog(ctrl, '복원 중');

    final result = await MessageBackupService.restoreBackup(
      filePath: b.filePath,
      mergeWithLocal: mode == _RestoreMode.merge,
      onProgress: (p, s) => ctrl.value = _ProgressState(p, s),
    );

    if (!mounted) return;
    Navigator.pop(context);
    setState(() => _busy = false);

    if (result.isSuccess) {
      ref.invalidate(chat_provider.chatRoomsProvider);

      final serverNote = result.restoredRoomsOnServer > 0
          ? ' · 채팅 ${result.restoredRoomsOnServer}개 복구'
          : '';

      _snack(
        '복원 완료 · ${result.restoredMessages}개 메시지 · ${result.restoredRooms}개 방$serverNote',
      );
      await _load();
    } else {
      _snack(result.errorMessage ?? '복원에 실패했어요');
    }
  }

  // ───────────────────────────────────────────────
  // 백업 삭제
  // ───────────────────────────────────────────────
  Future<void> _deleteBackup(BackupInfo b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '백업 삭제',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          '이 백업을 삭제할까요?\n삭제하면 복구할 수 없어요.',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final success = await MessageBackupService.deleteBackup(b.filePath);
    if (!mounted) return;
    if (success) {
      _snack('백업을 삭제했어요');
      await _load();
    } else {
      _snack('삭제에 실패했어요');
    }
  }

  // ───────────────────────────────────────────────
  // 진행 다이얼로그
  // ───────────────────────────────────────────────
  void _showProgressDialog(
      ValueNotifier<_ProgressState> ctrl, String title) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.all(22),
            child: ValueListenableBuilder<_ProgressState>(
              valueListenable: ctrl,
              builder: (_, s, __) {
                final pct = (s.progress * 100).toInt();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          title,
                          style: TextStyle(
                            color: AppTheme.textMain,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: s.progress,
                        backgroundColor: AppTheme.bg,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primary,
                        ),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.status,
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ chatRoomsProvider 변경 시 DM stats 자동 재계산
    ref.listen(chat_provider.chatRoomsProvider, (_, next) {
      next.whenData(_recomputeDmStats);
    });

    final statusAsync = ref.watch(subscriptionStatusProvider);
    final isPro = statusAsync.maybeWhen(
      data: (s) => s.isPro,
      orElse: () => false,
    );

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
            fontSize: 16,
          ),
        ),
      ),
      body: _loading
          ? Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primary),
            )
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildIntroCard(isPro),
                  const SizedBox(height: 16),
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  _buildBackupButton(isPro),
                  const SizedBox(height: 24),
                  _buildBackupListHeader(),
                  const SizedBox(height: 8),
                  if (_backups.isEmpty)
                    _buildEmptyBackups()
                  else
                    ..._backups
                        .map((b) => _buildBackupTile(b))
                        .toList(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ───────────────────────────────────────────────
  // 위젯 빌더
  // ───────────────────────────────────────────────
  Widget _buildIntroCard(bool isPro) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.15),
            AppTheme.primary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                isPro ? '백업 사용 가능' : 'Pro 전용 기능',
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'DM 메시지는 내 폰에만 영구 저장돼요. '
            '기기를 옮기거나 앱을 다시 설치하면 사라져요. '
            '백업해두면 어디서든 추억을 지킬 수 있어요. '
            '(그룹 채팅은 서버에 보관되어 백업이 필요 없어요)',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ⭐ 통계 카드: 대화방 + 용량 두 칸
  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '백업 대상',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statItem('대화방', '$_dmRoomCount개'),
              _statDivider(),
              _statItem(
                '용량',
                _dmEstimatedBytes == 0
                    ? '0B'
                    : '~ ${_fmtBytes(_dmEstimatedBytes)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 24,
      color: AppTheme.border,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildBackupButton(bool isPro) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _busy
            ? null
            : (isPro ? _createBackup : _goToSubscription),
        icon: Icon(
          isPro ? Icons.cloud_upload_outlined : Icons.lock_outline,
          color: Colors.white,
          size: 18,
        ),
        label: Text(
          isPro ? '지금 백업하기' : 'Pro로 백업하기',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildBackupListHeader() {
    return Row(
      children: [
        Icon(Icons.history, color: AppTheme.textSub, size: 16),
        const SizedBox(width: 6),
        Text(
          '내 백업',
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (_backups.isNotEmpty)
          Text(
            '${_backups.length}개',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyBackups() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined,
              color: AppTheme.textMuted, size: 36),
          const SizedBox(height: 10),
          Text(
            '아직 백업이 없어요',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupTile(BackupInfo b) {
    final isExpiringSoon = b.daysUntilExpiry < 14;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android,
                  color: AppTheme.textSub, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  b.deviceLabel ?? '알 수 없는 기기',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isExpiringSoon)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${b.daysUntilExpiry}일 후 만료',
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${b.messageCount}개 메시지 · ${b.roomCount}개 방 · ${b.formattedSize}',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _fmtDate(b.createdAt),
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _deleteBackup(b),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.border),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '삭제',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _restoreBackup(b),
                  icon: const Icon(
                    Icons.cloud_download_outlined,
                    size: 14,
                    color: Colors.white,
                  ),
                  label: const Text(
                    '복원하기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding:
                        const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 내부 유틸
// ═══════════════════════════════════════════════════
class _ProgressState {
  final double progress;
  final String status;
  _ProgressState(this.progress, this.status);
}

enum _RestoreMode { merge, replace }