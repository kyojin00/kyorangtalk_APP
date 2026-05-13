import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ═══════════════════════════════════════════════════
// 🔒 PhotoVisibilitySheet — 사진 공개 범위 설정
//
// 3가지 모드:
// - public:   전체공개
// - friends:  친구만 (기본값)
// - specific: 특정 친구만 (다중 선택)
//
// 사용법:
//   final result = await showPhotoVisibilitySheet(
//     context: context,
//     photoId: photoId,
//     currentVisibility: 'friends',
//     myId: myId,
//   );
//   // result: {'visibility': 'specific', 'viewers': [uuid1, uuid2]}
// ═══════════════════════════════════════════════════

Future<Map<String, dynamic>?> showPhotoVisibilitySheet({
  required BuildContext context,
  required String photoId,
  required String currentVisibility,
  required String myId,
}) async {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PhotoVisibilitySheet(
      photoId: photoId,
      currentVisibility: currentVisibility,
      myId: myId,
    ),
  );
}

class _PhotoVisibilitySheet extends StatefulWidget {
  final String photoId;
  final String currentVisibility;
  final String myId;

  const _PhotoVisibilitySheet({
    required this.photoId,
    required this.currentVisibility,
    required this.myId,
  });

  @override
  State<_PhotoVisibilitySheet> createState() =>
      _PhotoVisibilitySheetState();
}

class _PhotoVisibilitySheetState
    extends State<_PhotoVisibilitySheet> {
  late String _selected;
  bool _loadingFriends = false;
  bool _saving = false;
  List<Map<String, dynamic>> _friends = [];
  final Set<String> _selectedViewers = {};

  @override
  void initState() {
    super.initState();
    _selected = widget.currentVisibility;
    _loadInitialViewers();
    _loadFriends();
  }

  Future<void> _loadInitialViewers() async {
    if (widget.currentVisibility != 'specific') return;
    try {
      final data = await Supabase.instance.client
          .from('kyorangtalk_photo_viewers')
          .select('viewer_id')
          .eq('photo_id', widget.photoId);
      if (mounted) {
        setState(() {
          _selectedViewers.addAll(
              (data as List).map((r) => r['viewer_id'] as String));
        });
      }
    } catch (e) {
      print('viewers 로드 실패: $e');
    }
  }

  Future<void> _loadFriends() async {
    setState(() => _loadingFriends = true);
    try {
      final supabase = Supabase.instance.client;

      // 친구 관계 (accepted)
      final friendsData = await supabase
          .from('kyorangtalk_friends')
          .select('requester_id, receiver_id')
          .eq('status', 'accepted')
          .or('requester_id.eq.${widget.myId},receiver_id.eq.${widget.myId}');

      final friendIds = <String>{};
      for (final row in (friendsData as List)) {
        final r = row['requester_id'] as String;
        final c = row['receiver_id'] as String;
        if (r == widget.myId) friendIds.add(c);
        if (c == widget.myId) friendIds.add(r);
      }

      if (friendIds.isEmpty) {
        if (mounted) setState(() => _loadingFriends = false);
        return;
      }

      // 친구들의 프로필
      final profiles = await supabase
          .from('kyorangtalk_profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', friendIds.toList());

      if (mounted) {
        setState(() {
          _friends = List<Map<String, dynamic>>.from(profiles);
          _loadingFriends = false;
        });
      }
    } catch (e) {
      print('친구 로드 실패: $e');
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_selected == 'specific' && _selectedViewers.isEmpty) {
      _showSnack('한 명 이상 선택해주세요');
      return;
    }

    setState(() => _saving = true);

    try {
      final supabase = Supabase.instance.client;

      // visibility 업데이트
      await supabase
          .from('kyorangtalk_profile_photos')
          .update({'visibility': _selected})
          .eq('id', widget.photoId);

      // viewers 정리
      await supabase
          .from('kyorangtalk_photo_viewers')
          .delete()
          .eq('photo_id', widget.photoId);

      if (_selected == 'specific' && _selectedViewers.isNotEmpty) {
        await supabase.from('kyorangtalk_photo_viewers').insert(
              _selectedViewers
                  .map((vid) => {
                        'photo_id': widget.photoId,
                        'viewer_id': vid,
                      })
                  .toList(),
            );
      }

      if (mounted) {
        Navigator.pop(context, {
          'visibility': _selected,
          'viewers': _selectedViewers.toList(),
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('저장 실패: $e');
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.25),
                          AppTheme.primary.withOpacity(0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.visibility_rounded,
                        color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '공개 범위',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMain,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  // 저장 버튼
                  _SaveButton(
                    enabled: !_saving,
                    loading: _saving,
                    onTap: _save,
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: sc,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  _VisibilityOption(
                    icon: Icons.public_rounded,
                    title: '전체공개',
                    subtitle: '모든 사용자가 볼 수 있어요',
                    color: const Color(0xFF06B6D4),
                    selected: _selected == 'public',
                    onTap: () =>
                        setState(() => _selected = 'public'),
                  ),
                  const SizedBox(height: 10),
                  _VisibilityOption(
                    icon: Icons.people_alt_rounded,
                    title: '친구만',
                    subtitle: '내 친구만 볼 수 있어요',
                    color: AppTheme.primary,
                    selected: _selected == 'friends',
                    onTap: () =>
                        setState(() => _selected = 'friends'),
                  ),
                  const SizedBox(height: 10),
                  _VisibilityOption(
                    icon: Icons.lock_person_rounded,
                    title: '특정 친구만',
                    subtitle: _selected == 'specific' &&
                            _selectedViewers.isNotEmpty
                        ? '${_selectedViewers.length}명에게 공개'
                        : '선택한 친구만 볼 수 있어요',
                    color: const Color(0xFFFBBF24),
                    selected: _selected == 'specific',
                    onTap: () =>
                        setState(() => _selected = 'specific'),
                  ),

                  // 친구 선택 영역
                  if (_selected == 'specific') ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 13, color: AppTheme.textSub),
                        const SizedBox(width: 5),
                        Text(
                          '공개할 친구 선택',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textSub,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        if (_selectedViewers.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primary.withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_selectedViewers.length}명',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryLight,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_loadingFriends)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppTheme.primary),
                          ),
                        ),
                      )
                    else if (_friends.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: AppTheme.border),
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.people_outline_rounded,
                                color: AppTheme.textMuted,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '친구가 없어요',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSub,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: _friends.asMap().entries.map((e) {
                            final i = e.key;
                            final friend = e.value;
                            final id = friend['id'] as String;
                            final isSelected =
                                _selectedViewers.contains(id);
                            final isLast = i == _friends.length - 1;
                            return Column(
                              children: [
                                _FriendCheckTile(
                                  friend: friend,
                                  selected: isSelected,
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedViewers.remove(id);
                                      } else {
                                        _selectedViewers.add(id);
                                      }
                                    });
                                  },
                                ),
                                if (!isLast)
                                  Container(
                                    height: 0.5,
                                    color: AppTheme.border
                                        .withOpacity(0.5),
                                    margin: const EdgeInsets.only(
                                        left: 64),
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 공개 범위 옵션 카드
// ═══════════════════════════════════════════════════
class _VisibilityOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _VisibilityOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.15),
                      color.withOpacity(0.04),
                    ],
                  )
                : null,
            color: selected ? null : AppTheme.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withOpacity(0.4)
                  : AppTheme.border,
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.25),
                      color.withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                          letterSpacing: -0.3,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub,
                          letterSpacing: -0.2,
                        )),
                  ],
                ),
              ),
              // 라디오
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected
                      ? LinearGradient(colors: [
                          color,
                          color.withOpacity(0.85),
                        ])
                      : null,
                  border: Border.all(
                    color: selected ? color : AppTheme.border,
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 친구 체크 타일
// ═══════════════════════════════════════════════════
class _FriendCheckTile extends StatelessWidget {
  final Map<String, dynamic> friend;
  final bool selected;
  final VoidCallback onTap;

  const _FriendCheckTile({
    required this.friend,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = friend['nickname'] as String? ?? '';
    final avatar = friend['avatar_url'] as String?;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          child: Row(
            children: [
              AvatarWidget(
                url: avatar,
                name: nickname,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nickname,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 체크박스
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  gradient: selected
                      ? LinearGradient(colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.85),
                        ])
                      : null,
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.border,
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 저장 버튼
// ═══════════════════════════════════════════════════
class _SaveButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  const _SaveButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withOpacity(0.85),
                ],
              )
            : null,
        color: enabled ? null : AppTheme.bg,
        borderRadius: BorderRadius.circular(11),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text('저장',
                        style: TextStyle(
                          color: enabled
                              ? Colors.white
                              : AppTheme.textMuted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        )),
              ),
            ),
          ),
        ),
      ),
    );
  }
}