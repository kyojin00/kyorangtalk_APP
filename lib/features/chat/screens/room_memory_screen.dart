import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/room_stats_service.dart';

// ═══════════════════════════════════════════════════
// 💜 채팅방 추억 페이지
// ═══════════════════════════════════════════════════
//
// DM에선 상단에 "전체 / 나 / 상대" 세그먼트.
// - 전체: 통합 통계 + 첫 대화 + 시간대 + 가장 활발했던 날 + Top 단어
// - 나/상대: 그 사람이 보낸 것만 - 메시지/사진/음성/파일 카운트 + Top 단어
//
// 그룹은 세그먼트 숨김 (의미 약함)
//
// 사용법
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => RoomMemoryScreen(
//       roomId: ..., isGroup: false, roomName: ...,
//       myId: ..., partnerId: ..., partnerName: ...),
//   ));
// ═══════════════════════════════════════════════════

class RoomMemoryScreen extends StatefulWidget {
  final String roomId;
  final bool isGroup;
  final String roomName;
  final String myId;
  final String? partnerId;
  final String? partnerName;

  const RoomMemoryScreen({
    super.key,
    required this.roomId,
    required this.isGroup,
    required this.roomName,
    required this.myId,
    this.partnerId,
    this.partnerName,
  });

  @override
  State<RoomMemoryScreen> createState() => _RoomMemoryScreenState();
}

class _RoomMemoryScreenState extends State<RoomMemoryScreen> {
  Future<RoomMemoryStats>? _statsFuture;

  // null = 전체, myId = 나, partnerId = 상대
  String? _senderFilter;

  bool get _showSegment => !widget.isGroup && widget.partnerId != null;

  @override
  void initState() {
    super.initState();
    _statsFuture = RoomStatsService.fetchMemoryStats(
      roomId: widget.roomId,
      isGroup: widget.isGroup,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '추억',
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: FutureBuilder<RoomMemoryStats>(
        future: _statsFuture,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final stats = snap.data!;
          if (stats.totalMessages == 0) return _empty();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heroCard(stats),
                const SizedBox(height: 16),

                if (_showSegment) ...[
                  _SenderSegment(
                    selected: _senderFilter,
                    myId: widget.myId,
                    partnerId: widget.partnerId!,
                    partnerLabel: widget.partnerName ?? '상대',
                    onChanged: (v) => setState(() => _senderFilter = v),
                  ),
                  const SizedBox(height: 16),
                ],

                _statsGrid(stats),
                const SizedBox(height: 16),

                // ─ "전체"일 때만 첫 대화/시간대/가장 활발한 날 표시
                if (_senderFilter == null) ...[
                  if (stats.firstMessageAt != null) ...[
                    _firstMessageCard(stats),
                    const SizedBox(height: 16),
                  ],
                  _hourlyActivityCard(stats),
                  const SizedBox(height: 16),
                  if (stats.mostActiveDay != null) ...[
                    _mostActiveCard(stats),
                    const SizedBox(height: 16),
                  ],
                ],

                // ─ Top 단어 (필터별로 다른 데이터)
                _topWordsCard(stats),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, size: 64, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              Text('아직 쌓인 추억이 없어요',
                  style:
                      TextStyle(color: AppTheme.textSub, fontSize: 14)),
              const SizedBox(height: 4),
              Text('대화를 나눠보세요',
                  style: TextStyle(
                      color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
      );

  // ─── 히어로 카드 ───
  Widget _heroCard(RoomMemoryStats stats) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.roomName,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                const TextSpan(
                  text: '함께한 ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: '${stats.daysTogether}일째',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (stats.firstMessageAt != null)
            Text(
              '${_formatDate(stats.firstMessageAt!)}부터',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  // ─── 통계 그리드 (필터에 따라 분기) ───
  Widget _statsGrid(RoomMemoryStats stats) {
    int messages, photos, voices, files;

    if (_senderFilter == null) {
      messages = stats.totalMessages;
      photos = stats.totalPhotos;
      voices = stats.totalVoices;
      files = stats.totalFiles;
    } else {
      messages = stats.messagesBySender[_senderFilter] ?? 0;
      photos = stats.photosBySender[_senderFilter] ?? 0;
      voices = stats.voicesBySender[_senderFilter] ?? 0;
      files = stats.filesBySender[_senderFilter] ?? 0;
    }

    final items = <(String, String, IconData)>[
      (_formatNum(messages), '메시지', Icons.chat_bubble_outline),
      (_formatNum(photos), '사진', Icons.image_outlined),
      (_formatNum(voices), '음성', Icons.mic_none),
      (_formatNum(files), '파일', Icons.attach_file),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.$3, color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.$1,
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      item.$2,
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _firstMessageCard(RoomMemoryStats stats) {
    final hasContent = (stats.firstMessageContent ?? '').trim().isNotEmpty;
    return _section(
      icon: Icons.event_outlined,
      title: '첫 대화',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasContent)
            Text(
              '"${stats.firstMessageContent!.trim()}"',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            )
          else
            Text(
              '(이미지 또는 파일로 시작)',
              style:
                  TextStyle(color: AppTheme.textSub, fontSize: 13),
            ),
          const SizedBox(height: 8),
          Text(
            _formatDateTime(stats.firstMessageAt!),
            style:
                TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _hourlyActivityCard(RoomMemoryStats stats) {
    final max = stats.hourlyMax;
    return _section(
      icon: Icons.schedule_outlined,
      title: '시간대별 활동',
      child: Column(
        children: [
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (h) {
                final v = stats.hourlyActivity[h] ?? 0;
                final ratio = max == 0 ? 0.0 : v / max;
                final hasValue = v > 0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: hasValue ? (ratio * 76 + 4) : 4,
                      decoration: BoxDecoration(
                        color: hasValue
                            ? AppTheme.primary
                            : AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['0', '6', '12', '18', '23']
                .map((s) => Text(
                      '${s}시',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 10),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _mostActiveCard(RoomMemoryStats stats) {
    final m = stats.mostActiveDay!;
    return _section(
      icon: Icons.local_fire_department_outlined,
      title: '가장 활발했던 날',
      child: Row(
        children: [
          Expanded(
            child: Text(
              _formatDate(m.key),
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${m.value}개',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top 단어 (필터별로 다른 데이터) ───
  Widget _topWordsCard(RoomMemoryStats stats) {
    List<MapEntry<String, int>> words;
    String title;

    if (_senderFilter == null) {
      words = stats.topWords;
      title = '자주 쓴 단어';
    } else if (_senderFilter == widget.myId) {
      words = stats.topWordsBy(widget.myId);
      title = '내가 자주 쓴 단어';
    } else {
      words = stats.topWordsBy(_senderFilter!);
      title = '${widget.partnerName ?? "상대"}가 자주 쓴 단어';
    }

    if (words.isEmpty) {
      return _section(
        icon: Icons.chat_bubble_outline,
        title: title,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '단어가 충분히 모이지 않았어요',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    final topMax = words.first.value;
    return _section(
      icon: Icons.chat_bubble_outline,
      title: title,
      child: Column(
        children: words.take(5).toList().asMap().entries.map((e) {
          final rank = e.key + 1;
          final w = e.value;
          final ratio = w.value / topMax;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    w.key,
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${w.value}회',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(icon, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.textSub,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}.${l.month.toString().padLeft(2, '0')}.${l.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour;
    final m = l.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? '오전' : '오후';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '${_formatDate(dt)} $ampm $hh:$m';
  }

  String _formatNum(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) {
      final k = (n / 1000).toStringAsFixed(1);
      return '${k}K';
    }
    return '${(n / 10000).toStringAsFixed(1)}만';
  }
}

// ═══════════════════════════════════════════════════
// 보낸 사람 세그먼트 (전체 / 나 / 상대) - 갤러리와 동일
// ═══════════════════════════════════════════════════
class _SenderSegment extends StatelessWidget {
  final String? selected;
  final String myId;
  final String partnerId;
  final String partnerLabel;
  final ValueChanged<String?> onChanged;

  const _SenderSegment({
    required this.selected,
    required this.myId,
    required this.partnerId,
    required this.partnerLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _SegItem(label: '전체', selected: selected == null, onTap: () => onChanged(null)),
          _SegItem(label: '나',   selected: selected == myId,    onTap: () => onChanged(myId)),
          _SegItem(label: partnerLabel, selected: selected == partnerId, onTap: () => onChanged(partnerId)),
        ],
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegItem(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppTheme.textSub,
            ),
          ),
        ),
      ),
    );
  }
}