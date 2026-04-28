import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../models/group_room_model.dart';
import '../providers/group_chat_provider.dart';

class GroupMembersScreen extends ConsumerStatefulWidget {
  final GroupRoomModel room;

  const GroupMembersScreen({super.key, required this.room});

  @override
  ConsumerState<GroupMembersScreen> createState() =>
      _GroupMembersScreenState();
}

class _GroupMembersScreenState
    extends ConsumerState<GroupMembersScreen> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  String _myRole = 'member';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final supabase = Supabase.instance.client;

    final members = await supabase
        .from('kyorangtalk_group_members')
        .select('*')
        .eq('room_id', widget.room.id)
        .order('joined_at', ascending: true);

    if (members.isEmpty) {
      setState(() { _members = []; _loading = false; });
      return;
    }

    final myMember = members.firstWhere(
      (m) => m['user_id'] == _myId,
      orElse: () => {},
    );
    final myRole = myMember['role'] as String? ?? 'member';

    final userIds =
        members.map((m) => m['user_id'] as String).toList();
    final subProfileIds = members
        .where((m) => m['sub_profile_id'] != null)
        .map((m) => m['sub_profile_id'] as String)
        .toSet()
        .toList();

    final profiles = await supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url, status_message')
        .inFilter('id', userIds);

    final profileMap = {
      for (final p in profiles) p['id'] as String: p
    };

    Map<String, Map<String, dynamic>> subProfileMap = {};
    if (subProfileIds.isNotEmpty) {
      final subProfiles = await supabase
          .from('kyorangtalk_sub_profiles')
          .select('id, name, nickname, avatar_url, status_message')
          .inFilter('id', subProfileIds);

      subProfileMap = {
        for (final p in subProfiles) p['id'] as String: p
      };
    }

    final result = members.map((m) {
      final subProfileId = m['sub_profile_id'] as String?;
      final defaultProfile = profileMap[m['user_id']];

      String? displayNickname;
      String? displayAvatar;
      String? displayStatus;
      bool isSubProfile = false;

      if (subProfileId != null &&
          subProfileMap.containsKey(subProfileId)) {
        final sub = subProfileMap[subProfileId]!;
        final subNick = sub['nickname'] as String?;
        final subName = sub['name'] as String?;
        displayNickname =
            subNick?.isNotEmpty == true ? subNick : subName;
        displayAvatar = sub['avatar_url'] as String?;
        displayStatus = sub['status_message'] as String?;
        isSubProfile = true;
      } else {
        displayNickname = defaultProfile?['nickname'] as String?;
        displayAvatar = defaultProfile?['avatar_url'] as String?;
        displayStatus =
            defaultProfile?['status_message'] as String?;
      }

      return {
        ...m,
        'nickname':       displayNickname ?? '알 수 없음',
        'avatar_url':     displayAvatar,
        'status_message': displayStatus,
        'is_sub_profile': isSubProfile,
      };
    }).toList();

    // 정렬: 방장 → 관리자 → 일반 → 가입일순
    result.sort((a, b) {
      final roleA = a['role'] as String;
      final roleB = b['role'] as String;
      final priorityA = _rolePriority(roleA);
      final priorityB = _rolePriority(roleB);
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      return (a['joined_at'] as String)
          .compareTo(b['joined_at'] as String);
    });

    if (mounted) {
      setState(() {
        _members = result;
        _myRole = myRole;
        _loading = false;
      });
    }
  }

  int _rolePriority(String role) {
    switch (role) {
      case 'admin': return 0;
      case 'moderator': return 1;
      default: return 2;
    }
  }

  bool get _isAdmin => _myRole == 'admin';
  bool get _canModerate =>
      _myRole == 'admin' || _myRole == 'moderator';

  // ═══════════════════════════════════════════════
  // 멤버 액션 시트
  // ═══════════════════════════════════════════════
  void _showMemberActions(Map<String, dynamic> member) {
    final userId = member['user_id'] as String;
    final nickname = member['nickname'] as String;
    final role = member['role'] as String;
    final isTargetAdmin = role == 'admin';
    final isTargetModerator = role == 'moderator';

    if (isTargetAdmin) return;
    if (userId == _myId) return;
    if (isTargetModerator && !_isAdmin) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  AvatarWidget(
                    url: member['avatar_url'] as String?,
                    name: nickname,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nickname,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMain)),
                        if (isTargetModerator)
                          Text('관리자',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFF06B6D4),
                                  fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.border, height: 1),

            // 방장만 가능: 관리자 임명/해임
            if (_isAdmin) ...[
              if (isTargetModerator)
                ListTile(
                  leading: Icon(Icons.person_outline,
                      color: AppTheme.textMain),
                  title: Text('관리자 해임',
                      style: TextStyle(color: AppTheme.textMain)),
                  subtitle: Text('일반 멤버로 변경해요',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSub)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _demoteMember(userId, nickname);
                  },
                )
              else
                ListTile(
                  leading: const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF06B6D4)),
                  title: Text('관리자로 임명',
                      style: TextStyle(color: AppTheme.textMain)),
                  subtitle: Text('멤버를 내보낼 수 있어요',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSub)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _promoteMember(userId, nickname);
                  },
                ),
              Divider(color: AppTheme.border, height: 1),
            ],

            // 강퇴 (방장 + 관리자)
            ListTile(
              leading: const Icon(
                  Icons.person_remove_outlined,
                  color: Color(0xFFEF4444)),
              title: const Text('내보내기',
                  style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600)),
              subtitle: Text('채팅방에서 추방해요',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSub)),
              onTap: () {
                Navigator.pop(ctx);
                _kickMember(userId, nickname);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _promoteMember(String userId, String nickname) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('관리자 임명',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text(
            '$nickname님을 관리자로 임명할까요?\n관리자는 멤버를 내보낼 수 있어요.',
            style: TextStyle(
                color: AppTheme.textSub, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('임명',
                style: TextStyle(
                    color: Color(0xFF06B6D4),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await promoteToModerator(
          roomId: widget.room.id, userId: userId);
      await _loadMembers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$nickname님을 관리자로 임명했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('임명 실패: $e')),
        );
      }
    }
  }

  Future<void> _demoteMember(String userId, String nickname) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('관리자 해임',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text('$nickname님을 관리자에서 해임할까요?',
            style: TextStyle(
                color: AppTheme.textSub, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('해임',
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await demoteToMember(
          roomId: widget.room.id, userId: userId);
      await _loadMembers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$nickname님을 관리자에서 해임했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('해임 실패: $e')),
        );
      }
    }
  }

  Future<void> _kickMember(String userId, String nickname) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('멤버 내보내기',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text('$nickname님을 채팅방에서 내보낼까요?',
            style: TextStyle(
                color: AppTheme.textSub, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('내보내기',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await kickMember(roomId: widget.room.id, userId: userId);
      await _loadMembers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$nickname님을 내보냈어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('내보내기 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = widget.room.isOpen;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('멤버',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain)),
            Text('${_members.length}명',
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSub)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary))
          : ListView.builder(
              itemCount: _members.length,
              itemBuilder: (_, i) {
                final m            = _members[i];
                final userId       = m['user_id'] as String;
                final nickname     = m['nickname'] as String;
                final avatar       = m['avatar_url'] as String?;
                final status       = m['status_message'] as String?;
                final role         = m['role'] as String;
                final isSubProfile =
                    (m['is_sub_profile'] as bool?) ?? false;
                final isMe         = userId == _myId;
                final isTargetAdmin = role == 'admin';
                final isTargetModerator = role == 'moderator';

                final canShowMenu = !isMe &&
                    !isTargetAdmin &&
                    (_isAdmin ||
                        (_canModerate && !isTargetModerator));

                return InkWell(
                  onTap: isMe || (isOpen && isSubProfile)
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(
                                userId:    userId,
                                nickname:  nickname,
                                avatarUrl: avatar,
                              ),
                            ),
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: AppTheme.border)),
                    ),
                    child: Row(
                      children: [
                        AvatarWidget(
                            url:  avatar,
                            name: nickname,
                            size: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      isMe ? '$nickname (나)' : nickname,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w600,
                                          color:
                                              AppTheme.textMain),
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // ✨ 방장 배지
                                  if (isTargetAdmin) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets
                                          .symmetric(
                                          horizontal: 6,
                                          vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                                0xFFF59E0B)
                                            .withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius
                                                .circular(6),
                                      ),
                                      child: const Row(
                                        mainAxisSize:
                                            MainAxisSize.min,
                                        children: [
                                          Icon(
                                              Icons.star_rounded,
                                              size: 11,
                                              color: Color(
                                                  0xFFF59E0B)),
                                          SizedBox(width: 2),
                                          Text('방장',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Color(
                                                      0xFFF59E0B),
                                                  fontWeight:
                                                      FontWeight
                                                          .w700)),
                                        ],
                                      ),
                                    ),
                                  ]
                                  // ✨ 관리자 배지
                                  else if (isTargetModerator) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets
                                          .symmetric(
                                          horizontal: 6,
                                          vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                                0xFF06B6D4)
                                            .withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius
                                                .circular(6),
                                      ),
                                      child: const Row(
                                        mainAxisSize:
                                            MainAxisSize.min,
                                        children: [
                                          Icon(Icons.shield,
                                              size: 10,
                                              color: Color(
                                                  0xFF06B6D4)),
                                          SizedBox(width: 2),
                                          Text('관리자',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Color(
                                                      0xFF06B6D4),
                                                  fontWeight:
                                                      FontWeight
                                                          .w700)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (status != null &&
                                  status.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(status,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSub),
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis),
                              ],
                            ],
                          ),
                        ),
                        if (canShowMenu)
                          IconButton(
                            icon: Icon(Icons.more_vert,
                                color: AppTheme.textSub,
                                size: 20),
                            onPressed: () => _showMemberActions(m),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}