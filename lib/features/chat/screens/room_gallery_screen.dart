import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../services/room_stats_service.dart';
import '../widgets/file_bubble.dart';
import 'multi_image_viewer_screen.dart';

// ═══════════════════════════════════════════════════
// 🖼 채팅방 갤러리
// ═══════════════════════════════════════════════════
//
// 탭: 사진 | 파일 | 링크
// DM: 상단에 "전체 / 나 / 상대" 세그먼트 필터
// 그룹: 세그먼트 숨김 (보낸 사람이 여러 명이라 의미 약함)
//
// 사용법
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => RoomGalleryScreen(
//       roomId: ..., isGroup: false, roomName: ...,
//       myId: ..., partnerId: ..., partnerName: ...),
//   ));
// ═══════════════════════════════════════════════════

class RoomGalleryScreen extends StatefulWidget {
  final String roomId;
  final bool isGroup;
  final String roomName;
  final String myId;
  final String? partnerId;
  final String? partnerName;

  const RoomGalleryScreen({
    super.key,
    required this.roomId,
    required this.isGroup,
    required this.roomName,
    required this.myId,
    this.partnerId,
    this.partnerName,
  });

  @override
  State<RoomGalleryScreen> createState() => _RoomGalleryScreenState();
}

class _RoomGalleryScreenState extends State<RoomGalleryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // null = 전체, myId = 나, partnerId = 상대
  String? _senderFilter;

  Future<List<RoomPhoto>>? _photosFuture;
  Future<List<RoomFile>>? _filesFuture;
  Future<List<RoomLink>>? _linksFuture;

  bool get _showSegment => !widget.isGroup && widget.partnerId != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _reload();
  }

  void _reload() {
    setState(() {
      _photosFuture = RoomStatsService.fetchPhotos(
        roomId: widget.roomId,
        isGroup: widget.isGroup,
        senderFilter: _senderFilter,
      );
      _filesFuture = RoomStatsService.fetchFiles(
        roomId: widget.roomId,
        isGroup: widget.isGroup,
        senderFilter: _senderFilter,
      );
      _linksFuture = RoomStatsService.fetchLinks(
        roomId: widget.roomId,
        isGroup: widget.isGroup,
        senderFilter: _senderFilter,
      );
    });
  }

  void _setFilter(String? value) {
    if (_senderFilter == value) return;
    _senderFilter = value;
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          '갤러리',
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_showSegment ? 100 : 48),
          child: Column(
            children: [
              if (_showSegment) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _SenderSegment(
                    selected: _senderFilter,
                    myId: widget.myId,
                    partnerId: widget.partnerId!,
                    partnerLabel: widget.partnerName ?? '상대',
                    onChanged: _setFilter,
                  ),
                ),
              ],
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 2.5,
                labelColor: AppTheme.textMain,
                unselectedLabelColor: AppTheme.textSub,
                labelStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: '사진'),
                  Tab(text: '파일'),
                  Tab(text: '링크'),
                ],
              ),
              Divider(height: 1, color: AppTheme.border),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPhotosTab(),
          _buildFilesTab(),
          _buildLinksTab(),
        ],
      ),
    );
  }

  Widget _buildPhotosTab() {
    return FutureBuilder<List<RoomPhoto>>(
      future: _photosFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final photos = snap.data!;
        if (photos.isEmpty) {
          return _empty(Icons.photo_library_outlined,
              _emptyLabel('주고받은 사진'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: photos.length,
          itemBuilder: (ctx, i) {
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MultiImageViewerScreen(
                      imageUrls: photos.map((p) => p.url).toList(),
                      initialIndex: i,
                      senderName: widget.roomName,
                      time: _formatDate(photos[i].createdAt),
                    ),
                  ),
                );
              },
              child: Container(
                color: AppTheme.border,
                child: Image.network(
                  photos[i].url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.border,
                    child: Icon(Icons.broken_image,
                        color: AppTheme.textMuted, size: 24),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilesTab() {
    return FutureBuilder<List<RoomFile>>(
      future: _filesFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final files = snap.data!;
        if (files.isEmpty) {
          return _empty(Icons.folder_outlined, _emptyLabel('주고받은 파일'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: files.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final f = files[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileBubble(
                  fileUrl: f.url,
                  fileName: f.name,
                  fileSize: f.size,
                  fileType: f.type,
                  isMe: false,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    _formatDate(f.createdAt),
                    style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLinksTab() {
    return FutureBuilder<List<RoomLink>>(
      future: _linksFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final links = snap.data!;
        if (links.isEmpty) {
          return _empty(Icons.link_off, _emptyLabel('주고받은 링크'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: links.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final l = links[i];
            return InkWell(
              onTap: () async {
                try {
                  await launchUrl(Uri.parse(l.url),
                      mode: LaunchMode.externalApplication);
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('링크를 열 수 없어요')),
                    );
                  }
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
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
                      child: Icon(Icons.link,
                          color: AppTheme.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.url,
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(l.createdAt),
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.open_in_new,
                        color: AppTheme.textMuted, size: 14),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _emptyLabel(String base) {
    if (_senderFilter == null) return '$base이/가 없어요';
    if (_senderFilter == widget.myId) return '내가 보낸 $base이/가 없어요';
    return '${widget.partnerName ?? "상대"}가 보낸 $base이/가 없어요';
  }

  Widget _empty(IconData icon, String text) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.textMuted, size: 56),
            const SizedBox(height: 12),
            Text(text,
                style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
          ],
        ),
      );

  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}.${l.month}.${l.day}';
  }
}

// ═══════════════════════════════════════════════════
// 보낸 사람 세그먼트 (전체 / 나 / 상대)
// ═══════════════════════════════════════════════════
class _SenderSegment extends StatelessWidget {
  final String? selected; // null=전체, myId=나, partnerId=상대
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