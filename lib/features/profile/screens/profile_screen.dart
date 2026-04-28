import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../features/auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _editing = false;

  final _nicknameController = TextEditingController();
  final _statusController   = TextEditingController();
  bool _saving  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final supabase = Supabase.instance.client;
    final user     = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('kyorangtalk_profiles')
        .select('*')
        .eq('id', user.id)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _profile = data;
        _loading = false;
        if (data != null) {
          _nicknameController.text = data['nickname'] as String? ?? '';
          _statusController.text   = data['status_message'] as String? ?? '';
        }
      });
    }
  }

  void _startEdit() => setState(() { _editing = true; _error = null; });
  void _cancelEdit() {
    setState(() {
      _editing = false;
      _error   = null;
      _nicknameController.text = _profile?['nickname'] as String? ?? '';
      _statusController.text   = _profile?['status_message'] as String? ?? '';
    });
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.length < 2) {
      setState(() => _error = '닉네임은 2자 이상이어야 해요');
      return;
    }

    setState(() { _saving = true; _error = null; });

    final supabase = Supabase.instance.client;
    final userId   = supabase.auth.currentUser!.id;

    try {
      // 닉네임 중복 확인
      final existing = await supabase
          .from('kyorangtalk_profiles')
          .select('id')
          .eq('nickname', nickname)
          .neq('id', userId)
          .maybeSingle();

      if (existing != null) {
        setState(() {
          _error  = '이미 사용 중인 닉네임이에요';
          _saving = false;
        });
        return;
      }

      final status = _statusController.text.trim();
      await supabase.from('kyorangtalk_profiles').upsert({
        'id':             userId,
        'nickname':       nickname,
        'status_message': status.isEmpty ? null : status,
      });

      setState(() {
        _profile = {
          ..._profile ?? {},
          'nickname':       nickname,
          'status_message': status.isEmpty ? null : status,
        };
        _editing = false;
        _saving  = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('프로필이 저장됐어요!'),
            backgroundColor: AppTheme.bgCard,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error  = '저장 중 오류가 발생했어요';
        _saving = false;
      });
    }
  }

  Future<void> _changeAvatar() async {
    final picker = ImagePicker();
    final source = await _showImageSourceDialog();
    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _saving = true);

    try {
      final supabase = Supabase.instance.client;
      final userId   = supabase.auth.currentUser!.id;
      final file     = File(picked.path);
      final ext      = picked.path.split('.').last;
      final path     = 'avatars/$userId.$ext';

      await supabase.storage
          .from('kyorangtalk')
          .upload(path, file,
              fileOptions: const FileOptions(upsert: true));

      final url = supabase.storage
          .from('kyorangtalk')
          .getPublicUrl(path);

      await supabase
          .from('kyorangtalk_profiles')
          .update({'avatar_url': url})
          .eq('id', userId);

      setState(() {
        _profile = {..._profile ?? {}, 'avatar_url': url};
        _saving  = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('프로필 사진이 변경됐어요!'),
            backgroundColor: AppTheme.bgCard,
          ),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('사진 업로드 실패: $e'),
            backgroundColor: AppTheme.bgCard,
          ),
        );
      }
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
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
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppTheme.textMain),
              title: const Text('카메라로 촬영',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.textMain),
              title: const Text('갤러리에서 선택',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  const Text('프로필',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain)),
                  const Spacer(),
                  if (!_editing)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppTheme.textSub),
                      onPressed: _startEdit,
                    )
                  else ...[
                    TextButton(
                      onPressed: _cancelEdit,
                      child: const Text('취소',
                          style: TextStyle(color: AppTheme.textSub)),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _saveProfile,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primary))
                          : const Text('저장',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),

            // 바디
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),

                          // 아바타
                          Stack(
                            children: [
                              AvatarWidget(
                                url: _profile?['avatar_url'] as String? ??
                                    user?.userMetadata?['avatar_url']
                                        as String?,
                                name: _profile?['nickname'] as String?,
                                size: 88,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _saving ? null : _changeAvatar,
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: AppTheme.bg, width: 2),
                                    ),
                                    child: const Icon(
                                        Icons.camera_alt_rounded,
                                        color: Colors.white,
                                        size: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          if (!_editing) ...[
                            // 보기 모드
                            Text(
                              _profile?['nickname'] as String? ?? '닉네임 없음',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textMain,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user?.email ?? '',
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textSub),
                            ),
                            if (_profile?['status_message'] != null &&
                                (_profile!['status_message'] as String)
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppTheme.bgCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: AppTheme.border),
                                ),
                                child: Text(
                                  _profile!['status_message'] as String,
                                  style: const TextStyle(
                                      color: AppTheme.textSub,
                                      fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ] else ...[
                            // 편집 모드
                            if (_error != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppTheme.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          AppTheme.error.withOpacity(0.3)),
                                ),
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: AppTheme.error,
                                        fontSize: 13)),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // 닉네임 입력
                            Align(
                              alignment: Alignment.centerLeft,
                              child: const Text('닉네임',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textSub)),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nicknameController,
                              onChanged: (_) => setState(() {}),
                              style:
                                  const TextStyle(color: AppTheme.textMain),
                              maxLength: 20,
                              decoration: const InputDecoration(
                                hintText: '닉네임 (2~20자)',
                                counterStyle: TextStyle(
                                    color: AppTheme.textSub, fontSize: 11),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 상태 메시지 입력
                            Align(
                              alignment: Alignment.centerLeft,
                              child: const Text('상태 메시지',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textSub)),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _statusController,
                              style:
                                  const TextStyle(color: AppTheme.textMain),
                              maxLength: 50,
                              decoration: const InputDecoration(
                                hintText: '상태 메시지 (선택)',
                                counterStyle: TextStyle(
                                    color: AppTheme.textSub, fontSize: 11),
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),
                          const Divider(color: AppTheme.border),
                          const SizedBox(height: 8),

                          // 메뉴
                          _MenuTile(
                            icon: Icons.notifications_outlined,
                            label: '알림 설정',
                            onTap: () {},
                          ),
                          _MenuTile(
                            icon: Icons.lock_outline,
                            label: '개인정보 보호',
                            onTap: () {},
                          ),
                          const SizedBox(height: 8),
                          _MenuTile(
                            icon: Icons.logout,
                            label: '로그아웃',
                            color: const Color(0xFFEF4444),
                            onTap: () async {
                              await ref
                                  .read(authServiceProvider)
                                  .signOut();
                            },
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textMain;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: c,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            if (color == null)
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSub, size: 18),
          ],
        ),
      ),
    );
  }
}