import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ═══════════════════════════════════════════════
// 프로필 선택 결과 모델
// ═══════════════════════════════════════════════
class ProfileSelection {
  /// null이면 기본 프로필, 값이 있으면 서브 프로필 ID
  final String? subProfileId;
  final String displayName;
  final String? avatarUrl;

  ProfileSelection({
    this.subProfileId,
    required this.displayName,
    this.avatarUrl,
  });

  bool get isDefault => subProfileId == null;
}

// ═══════════════════════════════════════════════
// 서브 프로필 모델
// ═══════════════════════════════════════════════
class SubProfileModel {
  final String id;
  final String userId;
  final String name;
  final String? nickname;
  final String? avatarUrl;
  final String? statusMessage;
  final bool isDefault;

  SubProfileModel({
    required this.id,
    required this.userId,
    required this.name,
    this.nickname,
    this.avatarUrl,
    this.statusMessage,
    required this.isDefault,
  });

  factory SubProfileModel.fromJson(Map<String, dynamic> json) {
    return SubProfileModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      statusMessage: json['status_message'] as String?,
      isDefault: (json['is_default'] as bool?) ?? false,
    );
  }

  String get displayName => nickname?.isNotEmpty == true ? nickname! : name;
}

// ═══════════════════════════════════════════════
// 기본 프로필 모델
// ═══════════════════════════════════════════════
class MainProfileModel {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? statusMessage;

  MainProfileModel({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.statusMessage,
  });
}

// ═══════════════════════════════════════════════
// 내 기본 프로필 Provider
// ═══════════════════════════════════════════════
final myMainProfileProvider =
    FutureProvider<MainProfileModel?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;

  final data = await Supabase.instance.client
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url, status_message')
      .eq('id', user.id)
      .maybeSingle();

  if (data == null) return null;

  return MainProfileModel(
    id: data['id'] as String,
    nickname: data['nickname'] as String? ?? '사용자',
    avatarUrl: data['avatar_url'] as String?,
    statusMessage: data['status_message'] as String?,
  );
});

// ═══════════════════════════════════════════════
// 내 서브 프로필 목록 Provider
// ═══════════════════════════════════════════════
final mySubProfilesProvider =
    FutureProvider<List<SubProfileModel>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  final data = await Supabase.instance.client
      .from('kyorangtalk_sub_profiles')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', ascending: true);

  return data.map((e) => SubProfileModel.fromJson(e)).toList();
});

// ═══════════════════════════════════════════════
// 프로필 선택 화면
// ═══════════════════════════════════════════════
class ProfileSelectScreen extends ConsumerStatefulWidget {
  final String roomName;

  const ProfileSelectScreen({
    super.key,
    required this.roomName,
  });

  @override
  ConsumerState<ProfileSelectScreen> createState() =>
      _ProfileSelectScreenState();
}

class _ProfileSelectScreenState
    extends ConsumerState<ProfileSelectScreen> {
  // null = 기본 프로필 선택, String = 서브 프로필 ID
  String? _selectedSubProfileId;
  bool _defaultSelected = true; // 초기값: 기본 프로필 선택됨

  void _selectDefault() {
    setState(() {
      _defaultSelected = true;
      _selectedSubProfileId = null;
    });
  }

  void _selectSub(String subId) {
    setState(() {
      _defaultSelected = false;
      _selectedSubProfileId = subId;
    });
  }

  void _showCreateProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CreateProfileSheet(),
    ).then((created) {
      if (created == true) {
        ref.invalidate(mySubProfilesProvider);
      }
    });
  }

  void _confirm(MainProfileModel? mainProfile,
      List<SubProfileModel> subProfiles) {
    if (_defaultSelected) {
      if (mainProfile == null) return;
      Navigator.pop(
        context,
        ProfileSelection(
          subProfileId: null,
          displayName: mainProfile.nickname,
          avatarUrl: mainProfile.avatarUrl,
        ),
      );
    } else {
      final sub = subProfiles
          .firstWhere((p) => p.id == _selectedSubProfileId);
      Navigator.pop(
        context,
        ProfileSelection(
          subProfileId: sub.id,
          displayName: sub.displayName,
          avatarUrl: sub.avatarUrl,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainProfileAsync = ref.watch(myMainProfileProvider);
    final subProfilesAsync = ref.watch(mySubProfilesProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '프로필 선택',
          style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 17,
              fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: mainProfileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (e, _) => Center(
            child: Text('오류: $e',
                style: TextStyle(color: AppTheme.textSub))),
        data: (mainProfile) {
          return subProfilesAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primary)),
            error: (e, _) => Center(
                child: Text('오류: $e',
                    style: TextStyle(color: AppTheme.textSub))),
            data: (subProfiles) {
              return Column(
                children: [
                  // 안내 메시지
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      border: Border(
                          bottom: BorderSide(color: AppTheme.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🎭',
                            style: TextStyle(fontSize: 28)),
                        const SizedBox(height: 8),
                        Text(
                          '어떤 프로필로 참여할까요?',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '"${widget.roomName}" 채팅방에 프로필을 선택해주세요',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSub),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline,
                                  color: AppTheme.primary,
                                  size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '한 번 선택하면 변경할 수 없어요',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.primaryLight,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 프로필 목록
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // ✨ 1. 기본 프로필 (항상 맨 위)
                        if (mainProfile != null)
                          _ProfileTile(
                            name: mainProfile.nickname,
                            subtitle: mainProfile.statusMessage
                                        ?.isNotEmpty ==
                                    true
                                ? mainProfile.statusMessage!
                                : '기본 프로필',
                            avatarUrl: mainProfile.avatarUrl,
                            isSelected: _defaultSelected,
                            isDefault: true,
                            onTap: _selectDefault,
                          ),

                        // ✨ 2. 서브 프로필 목록
                        if (subProfiles.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 4, bottom: 8),
                            child: Text(
                              '서브 프로필',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSub),
                            ),
                          ),
                          ...subProfiles.map((profile) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ProfileTile(
                                name: profile.displayName,
                                subtitle: profile.statusMessage
                                            ?.isNotEmpty ==
                                        true
                                    ? profile.statusMessage!
                                    : profile.name,
                                avatarUrl: profile.avatarUrl,
                                isSelected: !_defaultSelected &&
                                    _selectedSubProfileId ==
                                        profile.id,
                                isDefault: false,
                                onTap: () => _selectSub(profile.id),
                              ),
                            );
                          }),
                        ],

                        // ✨ 3. 새 서브 프로필 만들기 버튼
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: _showCreateProfileSheet,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.primary
                                  .withOpacity(0.08),
                              borderRadius:
                                  BorderRadius.circular(14),
                              border: Border.all(
                                color: AppTheme.primary
                                    .withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50, height: 50,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary
                                        .withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add,
                                      color: AppTheme.primary,
                                      size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          subProfiles.isEmpty
                                              ? '새 서브 프로필 만들기'
                                              : '프로필 추가하기',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight:
                                                  FontWeight.w800,
                                              color: AppTheme
                                                  .primary)),
                                      const SizedBox(height: 2),
                                      Text(
                                          '다른 닉네임과 아바타로 활동해요',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  AppTheme.textSub)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: AppTheme.primary,
                                    size: 20),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),

                  // 하단 입장 버튼
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                          20, 12, 20, 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        border: Border(
                            top: BorderSide(color: AppTheme.border)),
                      ),
                      child: ElevatedButton(
                        onPressed: (_defaultSelected &&
                                    mainProfile != null) ||
                                _selectedSubProfileId != null
                            ? () => _confirm(mainProfile, subProfiles)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.border,
                          minimumSize:
                              const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '선택한 프로필로 입장',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
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
}

// ═══════════════════════════════════════════════
// 프로필 타일 위젯 (공통)
// ═══════════════════════════════════════════════
class _ProfileTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? avatarUrl;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.name,
    required this.subtitle,
    required this.avatarUrl,
    required this.isSelected,
    required this.isDefault,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.1)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AvatarWidget(
              url: avatarUrl,
              name: name,
              size: 50,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('기본',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.primaryLight,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : AppTheme.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check,
                      color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 새 서브 프로필 생성 시트
// ═══════════════════════════════════════════════
class _CreateProfileSheet extends ConsumerStatefulWidget {
  const _CreateProfileSheet();

  @override
  ConsumerState<_CreateProfileSheet> createState() =>
      _CreateProfileSheetState();
}

class _CreateProfileSheetState
    extends ConsumerState<_CreateProfileSheet> {
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _statusController = TextEditingController();
  File? _avatarFile;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
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
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (picked == null) return;
    setState(() => _avatarFile = File(picked.path));
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _creating = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;

      String? avatarUrl;
      if (_avatarFile != null) {
        final ext = _avatarFile!.path.split('.').last;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path =
            'sub-profiles/${user.id}_$timestamp.$ext';

        await supabase.storage.from('kyorangtalk').upload(
              path,
              _avatarFile!,
              fileOptions: const FileOptions(upsert: true),
            );

        avatarUrl = supabase.storage
            .from('kyorangtalk')
            .getPublicUrl(path);
      }

      await supabase.from('kyorangtalk_sub_profiles').insert({
        'user_id': user.id,
        'name': name,
        'nickname': _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        'status_message':
            _statusController.text.trim().isEmpty
                ? null
                : _statusController.text.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'is_default': false,
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('프로필 생성 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Text('새 서브 프로필 만들기',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain)),
                  const Spacer(),
                  TextButton(
                    onPressed: _creating ||
                            _nameController.text.trim().isEmpty
                        ? null
                        : _create,
                    child: _creating
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary))
                        : const Text('완료',
                            style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        children: [
                          Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.bg,
                              border: Border.all(
                                  color: AppTheme.border, width: 2),
                              image: _avatarFile != null
                                  ? DecorationImage(
                                      image: FileImage(_avatarFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _avatarFile == null
                                ? Icon(Icons.camera_alt_outlined,
                                    color: AppTheme.textSub, size: 28)
                                : null,
                          ),
                          if (_avatarFile != null)
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppTheme.bgCard,
                                      width: 2),
                                ),
                                child: const Icon(Icons.edit,
                                    color: Colors.white, size: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _avatarFile == null
                          ? '아바타 추가 (선택)'
                          : '아바타 변경',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSub),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('프로필 이름 *',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: AppTheme.textMain),
                    maxLength: 20,
                    decoration: InputDecoration(
                      hintText: '예) 게임 캐릭터, 익명',
                      hintStyle: TextStyle(color: AppTheme.textSub),
                      counterStyle: TextStyle(
                          color: AppTheme.textSub, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text('닉네임 (선택)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nicknameController,
                    style: TextStyle(color: AppTheme.textMain),
                    maxLength: 15,
                    decoration: InputDecoration(
                      hintText: '채팅방에 표시될 이름',
                      hintStyle: TextStyle(color: AppTheme.textSub),
                      counterStyle: TextStyle(
                          color: AppTheme.textSub, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text('상태 메시지 (선택)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _statusController,
                    style: TextStyle(color: AppTheme.textMain),
                    maxLength: 30,
                    decoration: InputDecoration(
                      hintText: '나를 표현해보세요',
                      hintStyle: TextStyle(color: AppTheme.textSub),
                      counterStyle: TextStyle(
                          color: AppTheme.textSub, fontSize: 11),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}