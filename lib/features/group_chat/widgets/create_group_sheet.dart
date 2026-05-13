import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../friends/screens/friends_screen.dart';
import '../enums/group_chat_enums.dart';
import '../providers/group_chat_provider.dart';
import 'password_dialog.dart';

// ═══════════════════════════════════════════════════
// 채팅방 만들기 시트
//
// 위치: lib/features/group_chat/widgets/create_group_sheet.dart
// ═══════════════════════════════════════════════════

class CreateGroupSheet extends ConsumerStatefulWidget {
  final String myId;
  const CreateGroupSheet({super.key, required this.myId});

  @override
  ConsumerState<CreateGroupSheet> createState() =>
      _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<CreateGroupSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _tagController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordEnabled = false;

  String _roomType = 'group';
  String _category = '일반';
  bool _loading = false;
  List<String> _selectedFriendIds = [];
  List<String> _tags = [];

  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() => _roomType =
          _tabController.index == 0 ? 'group' : 'open');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _tagController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim().replaceAll('#', '');
    if (tag.isEmpty) return;
    if (_tags.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('태그는 최대 5개까지 추가할 수 있어요')),
      );
      return;
    }
    if (_tags.contains(tag)) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();

    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined,
                  color: AppTheme.textMain),
              title: Text('카메라로 촬영',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppTheme.textMain),
              title: Text('갤러리에서 선택',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_imageFile != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFEF4444)),
                title: const Text('이미지 삭제',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _imageFile = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (picked == null) return;

    setState(() => _imageFile = File(picked.path));
  }

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) return;

    String? password;
    if (_passwordEnabled) {
      password = _passwordController.text.trim();
      if (password.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호는 4자 이상으로 설정해주세요')),
        );
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    String? avatarUrl;
    if (_imageFile != null) {
      avatarUrl = await uploadRoomImage(_imageFile!);
    }

    final room = await createGroupRoom(
      name: _nameController.text.trim(),
      roomType: _roomType,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      category: _category,
      memberIds: _selectedFriendIds,
      avatarUrl: avatarUrl,
      tags: _roomType == 'open' ? _tags : [],
      password: password,
    );

    if (mounted) {
      Navigator.pop(context);
      ref.invalidate(groupRoomsProvider);
      ref.invalidate(openRoomsProvider);
      if (room != null) {
        context.push('/main/group/${room.id}', extra: room);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방 생성에 실패했어요')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
              child: Row(
                children: [
                  Text(
                    '채팅방 만들기',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMain,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _loading ||
                            _nameController.text.trim().isEmpty
                        ? null
                        : _create,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.border,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Text(
                            '만들기',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // 탭
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary,
                        AppTheme.primary.withOpacity(0.85),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppTheme.textSub,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                  tabs: const [
                    Tab(text: '그룹채팅'),
                    Tab(text: '오픈채팅'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // 이미지 픽커
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.bg,
                              border: Border.all(
                                color: _imageFile != null
                                    ? AppTheme.primary
                                        .withOpacity(0.3)
                                    : AppTheme.border,
                                width: 2,
                              ),
                              image: _imageFile != null
                                  ? DecorationImage(
                                      image: FileImage(_imageFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _imageFile == null
                                ? Icon(
                                    Icons.camera_alt_outlined,
                                    color: AppTheme.textSub,
                                    size: 30,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppTheme.bgCard, width: 2),
                              ),
                              child: Icon(
                                _imageFile == null
                                    ? Icons.add
                                    : Icons.edit,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      _imageFile == null
                          ? '대표 이미지 추가 (선택)'
                          : '이미지 변경',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 이름
                  _Label('채팅방 이름'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: AppTheme.textMain),
                    maxLength: 30,
                    decoration: InputDecoration(
                      hintText: '채팅방 이름을 입력해요',
                      hintStyle:
                          TextStyle(color: AppTheme.textMuted),
                      counterStyle: TextStyle(
                          color: AppTheme.textSub, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 비번 설정 카드
                  PasswordSettingsCard(
                    enabled: _passwordEnabled,
                    controller: _passwordController,
                    onToggle: (v) {
                      setState(() => _passwordEnabled = v);
                      if (!v) _passwordController.clear();
                    },
                  ),
                  const SizedBox(height: 16),

                  // 오픈채팅 전용 필드
                  if (_roomType == 'open') ...[
                    _Label('설명 (선택)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      style: TextStyle(color: AppTheme.textMain),
                      maxLength: 200,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '채팅방 소개를 입력해요',
                        hintStyle:
                            TextStyle(color: AppTheme.textMuted),
                        counterStyle: TextStyle(
                            color: AppTheme.textSub, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _Label('카테고리'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: createCategories.map((cat) {
                        final selected = _category == cat;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _category = cat),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? LinearGradient(colors: [
                                      AppTheme.primary,
                                      AppTheme.primary.withOpacity(0.85),
                                    ])
                                  : null,
                              color: selected ? null : AppTheme.bg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : AppTheme.border,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected
                                    ? Colors.white
                                    : AppTheme.textSub,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        _Label('태그 (선택)'),
                        const SizedBox(width: 6),
                        Text(
                          '${_tags.length}/5',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagController,
                            style: TextStyle(color: AppTheme.textMain),
                            maxLength: 10,
                            onSubmitted: (_) => _addTag(),
                            decoration: InputDecoration(
                              hintText: '소통, 친목, 게임',
                              hintStyle: TextStyle(
                                  color: AppTheme.textMuted),
                              prefixText: '#',
                              prefixStyle: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                              counterStyle: TextStyle(
                                  color: AppTheme.textSub,
                                  fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _addTag,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppTheme.primary.withOpacity(0.15),
                            foregroundColor: AppTheme.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '추가',
                            style: TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _tags.map((tag) {
                          return GestureDetector(
                            onTap: () => _removeTag(tag),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                  10, 5, 6, 5),
                              decoration: BoxDecoration(
                                color: AppTheme.primary
                                    .withOpacity(0.12),
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '#$tag',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.primaryLight,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: AppTheme.primaryLight,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  // 그룹채팅 전용 — 친구 초대
                  if (_roomType == 'group') ...[
                    _Label('친구 초대'),
                    const SizedBox(height: 8),
                    friendsAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.primary)),
                      error: (_, __) => const SizedBox(),
                      data: (friends) => friends.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.bg,
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '초대할 친구가 없어요',
                                  style: TextStyle(
                                    color: AppTheme.textSub,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              children: friends.map((f) {
                                final selected = _selectedFriendIds
                                    .contains(f.friendId);
                                return InkWell(
                                  onTap: () => setState(() {
                                    if (selected) {
                                      _selectedFriendIds
                                          .remove(f.friendId);
                                    } else {
                                      _selectedFriendIds
                                          .add(f.friendId);
                                    }
                                  }),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 4,
                                        vertical: 10),
                                    child: Row(
                                      children: [
                                        AvatarWidget(
                                          url: f.avatarUrl,
                                          name: f.nickname,
                                          size: 40,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            f.nickname,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight:
                                                  FontWeight.w600,
                                              color: AppTheme
                                                  .textMain,
                                            ),
                                          ),
                                        ),
                                        AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? AppTheme.primary
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: selected
                                                  ? AppTheme.primary
                                                  : AppTheme.border,
                                              width: 2,
                                            ),
                                          ),
                                          child: selected
                                              ? const Icon(
                                                  Icons.check,
                                                  color: Colors
                                                      .white,
                                                  size: 14,
                                                )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 헬퍼 위젯 ─────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AppTheme.textMain,
        letterSpacing: -0.2,
      ),
    );
  }
}