import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import 'sub_profiles_screen.dart';

// ═══════════════════════════════════════════════════
// MyProfileScreen — 시네마틱 + 원본 화질 배경
//
// 해상도 개선:
// - 배경: file_picker로 원본 파일 직접 업로드 (압축 X)
// - cacheWidth/Height = 디바이스 픽셀 비율 (다운샘플링 X)
// - filterQuality: high
// - 오버레이 투명도 대폭 감소 (배경 선명하게)
// ═══════════════════════════════════════════════════

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() =>
      _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _avatarHistory = [];
  List<Map<String, dynamic>> _stickers = [];
  int _subProfilesCount = 0;
  bool _loading = true;
  bool _editing = false;
  bool _stickerMode = false;
  bool _saving = false;

  final _nicknameController = TextEditingController();
  final _statusController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _nicknameController.addListener(() => setState(() {}));
    _statusController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadProfile(),
      _loadAvatarHistory(),
      _loadStickers(),
      _loadSubProfilesCount(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadProfile() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_profiles')
        .select('*')
        .eq('id', _myId)
        .maybeSingle();
    if (mounted && data != null) {
      setState(() {
        _profile = data;
        _nicknameController.text = data['nickname'] as String? ?? '';
        _statusController.text =
            data['status_message'] as String? ?? '';
      });
    }
  }

  Future<void> _loadAvatarHistory() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_avatar_history')
        .select('*')
        .eq('user_id', _myId)
        .order('created_at', ascending: false)
        .limit(20);
    if (mounted) setState(() => _avatarHistory = List.from(data));
  }

  Future<void> _loadStickers() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_profile_stickers')
        .select('*')
        .eq('user_id', _myId);
    if (mounted) setState(() => _stickers = List.from(data));
  }

  Future<void> _loadSubProfilesCount() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_sub_profiles')
        .select('id')
        .eq('user_id', _myId);
    if (mounted) {
      setState(() => _subProfilesCount = data.length);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(msg, style: TextStyle(color: AppTheme.textMain)),
          backgroundColor: AppTheme.bgCard,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════
  // 아바타 — image_picker 사용 (작아도 됨)
  // ═══════════════════════════════════════════════════
  Future<void> _changeAvatar() async {
    final picker = ImagePicker();
    final source = await _showAvatarSourceDialog();
    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      final file = File(picked.path);
      final ext = picked.path.split('.').last.toLowerCase();
      final path =
          'avatars/$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('kyorangtalk').upload(
            path,
            file,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _getContentType(ext),
            ),
          );

      final url = supabase.storage
          .from('kyorangtalk')
          .getPublicUrl(path);

      await supabase
          .from('kyorangtalk_profiles')
          .update({'avatar_url': url})
          .eq('id', _myId);

      await supabase.from('kyorangtalk_avatar_history').insert({
        'user_id': _myId,
        'avatar_url': url,
      });

      await _loadData();
      _showSnack('프로필 사진이 변경됐어요!');
    } catch (e) {
      _showSnack('사진 업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _getContentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  Future<ImageSource?> _showAvatarSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
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
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_rounded,
                  color: AppTheme.textMain),
              title: Text('카메라로 촬영',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded,
                  color: AppTheme.textMain),
              title: Text('갤러리에서 선택',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () =>
                  Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ⭐ 배경 — file_picker로 원본 파일 (압축 X)
  // ═══════════════════════════════════════════════════
  Future<void> _changeBackground() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
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
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('배경화면',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                        letterSpacing: -0.3)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_rounded,
                  color: AppTheme.textMain),
              title: Text('카메라로 촬영',
                  style: TextStyle(color: AppTheme.textMain)),
              subtitle: Text('새로 촬영한 사진',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textSub)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded,
                  color: AppTheme.primary),
              title: Text('갤러리에서 원본 선택',
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w700)),
              subtitle: Text('압축 없이 원본 화질 그대로',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.primary)),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_profile?['background_url'] != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444)),
                title: const Text('배경화면 제거',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'remove') {
      setState(() => _saving = true);
      try {
        await Supabase.instance.client
            .from('kyorangtalk_profiles')
            .update({'background_url': null})
            .eq('id', _myId);
        await _loadProfile();
        _showSnack('배경화면이 제거됐어요');
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    File? file;
    String ext = 'jpg';

    if (action == 'camera') {
      // 카메라는 image_picker (file_picker는 카메라 미지원)
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (picked == null) return;
      file = File(picked.path);
      ext = picked.path.split('.').last.toLowerCase();
    } else {
      // ⭐ 갤러리는 file_picker — 원본 파일 그대로
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false, // 메모리에 안 올리고 파일 경로만
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;
      file = File(filePath);
      ext = filePath.split('.').last.toLowerCase();
    }

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      final path =
          'backgrounds/$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      // 파일 크기 로그
      final sizeBytes = await file.length();
      final sizeMB = sizeBytes / 1024 / 1024;
      print('📸 배경 이미지 원본 크기: ${sizeMB.toStringAsFixed(2)} MB');

      // 50MB 초과 시 경고
      if (sizeMB > 50) {
        _showSnack('파일이 너무 커요 (${sizeMB.toStringAsFixed(1)}MB)');
        setState(() => _saving = false);
        return;
      }

      await supabase.storage.from('kyorangtalk').upload(
            path,
            file,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _getContentType(ext),
              cacheControl: '3600',
            ),
          );

      final url = supabase.storage
          .from('kyorangtalk')
          .getPublicUrl(path);

      await supabase
          .from('kyorangtalk_profiles')
          .update({'background_url': url})
          .eq('id', _myId);

      // 이미지 캐시 비우기
      imageCache.clear();
      imageCache.clearLiveImages();

      await _loadProfile();
      _showSnack('배경화면이 변경됐어요!');
    } catch (e) {
      _showSnack('업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addSticker() async {
    if (_stickers.length >= 10) {
      _showSnack('스티커는 최대 10개까지 추가할 수 있어요');
      return;
    }

    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('스티커 선택',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                        letterSpacing: -0.3)),
              ),
            ),
            Expanded(
              child: GridView.count(
                controller: sc,
                crossAxisCount: 6,
                padding: const EdgeInsets.all(16),
                children: _emojiList.map((emoji) {
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, emoji),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );

    if (emoji == null) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('kyorangtalk_profile_stickers')
          .insert({
        'user_id': _myId,
        'emoji': emoji,
        'pos_x': 0.5,
        'pos_y': 0.4,
        'scale': 1.0,
        'rotation': 0.0,
      });
      await _loadStickers();
      _showSnack('스티커가 추가됐어요! 드래그해서 위치를 조정하세요');
    } catch (e) {
      _showSnack('추가 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateStickerPosition(
      String id, double x, double y) async {
    await Supabase.instance.client
        .from('kyorangtalk_profile_stickers')
        .update({'pos_x': x, 'pos_y': y})
        .eq('id', id);
  }

  Future<void> _deleteSticker(String id) async {
    await Supabase.instance.client
        .from('kyorangtalk_profile_stickers')
        .delete()
        .eq('id', id);
    await _loadStickers();
    _showSnack('스티커가 삭제됐어요');
  }

  Future<void> _updateStickerScale(String id, double scale) async {
    await Supabase.instance.client
        .from('kyorangtalk_profile_stickers')
        .update({'scale': scale})
        .eq('id', id);
    await _loadStickers();
  }

  void _showStickerOptions(Map<String, dynamic> sticker) {
    final id = sticker['id'] as String;
    final currentScale =
        (sticker['scale'] as num?)?.toDouble() ?? 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          double scale = currentScale;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin:
                      const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Text(sticker['emoji'] as String,
                          style: const TextStyle(fontSize: 36)),
                      const SizedBox(width: 12),
                      Text('스티커 편집',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain,
                              letterSpacing: -0.3)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20),
                  child: Row(
                    children: [
                      Text('크기',
                          style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      Expanded(
                        child: StatefulBuilder(
                          builder: (_, setS) => Slider(
                            value: scale,
                            min: 0.5,
                            max: 2.5,
                            activeColor: AppTheme.primary,
                            inactiveColor: AppTheme.border,
                            onChanged: (v) {
                              setS(() => scale = v);
                            },
                            onChangeEnd: (v) async {
                              await _updateStickerScale(id, v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444)),
                  title: const Text('삭제',
                      style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w700)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _deleteSticker(id);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.length < 2) {
      _showSnack('닉네임은 2자 이상이어야 해요');
      return;
    }

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;

      final status = _statusController.text.trim();
      await supabase.from('kyorangtalk_profiles').upsert({
        'id': _myId,
        'nickname': nickname,
        'status_message': status.isEmpty ? null : status,
      });

      await _loadProfile();
      setState(() {
        _editing = false;
        _saving = false;
      });
      _showSnack('프로필이 저장됐어요!');
    } catch (e) {
      setState(() => _saving = false);
      _showSnack('저장 실패: $e');
    }
  }

  void _showAvatarFullscreen(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullscreenImageViewer(url: url),
      ),
    );
  }

  void _showBackgroundFullscreen(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullscreenImageViewer(url: url),
      ),
    );
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _nicknameController.text =
          _profile?['nickname'] as String? ?? '';
      _statusController.text =
          _profile?['status_message'] as String? ?? '';
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final nickname = _profile?['nickname'] as String? ?? '';
    final avatar = _profile?['avatar_url'] as String?;
    final background = _profile?['background_url'] as String?;
    final statusMessage = _profile?['status_message'] as String?;

    final List<Map<String, dynamic>> pastAvatars = [];
    if (_avatarHistory.length > 1) {
      pastAvatars.addAll(_avatarHistory.sublist(1));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final thumbSize = (screenWidth - 40 - 30) / 4;

    // ⭐ 디바이스 픽셀 비율로 캐싱 (다운샘플링 방지)
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final bgCacheWidth = (screenWidth * pixelRatio).round();
    final bgCacheHeight = (screenHeight * pixelRatio).round();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: _editing,
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primary))
          : Stack(
              children: [
                // ⭐ 배경 — 고해상도 캐싱 + 탭 가능
                Positioned.fill(
                  child: GestureDetector(
                    onTap: (background != null &&
                            !_editing &&
                            !_stickerMode)
                        ? () => _showBackgroundFullscreen(background)
                        : null,
                    child: background != null
                        ? Image.network(
                            background,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            cacheWidth: bgCacheWidth,
                            cacheHeight: bgCacheHeight,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                _DefaultBackground(),
                          )
                        : _DefaultBackground(),
                  ),
                ),

                // ⭐ 오버레이 — 훨씬 약하게
                IgnorePointer(
                  child: Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.25),
                            Colors.transparent,
                            AppTheme.bg.withOpacity(0.4),
                            AppTheme.bg,
                          ],
                          stops: const [0.0, 0.4, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // 편집 모드 backdrop
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _editing
                      ? Positioned.fill(
                          key: const ValueKey('edit_backdrop'),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                                sigmaX: 10, sigmaY: 10),
                            child: Container(
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('no_backdrop')),
                ),

                ..._stickers.map((sticker) {
                  final id = sticker['id'] as String;
                  final emoji = sticker['emoji'] as String;
                  final x = (sticker['pos_x'] as num?)?.toDouble() ??
                      0.5;
                  final y = (sticker['pos_y'] as num?)?.toDouble() ??
                      0.4;
                  final scale =
                      (sticker['scale'] as num?)?.toDouble() ?? 1.0;

                  return _DraggableSticker(
                    key: ValueKey(id),
                    emoji: emoji,
                    initialX: x * screenWidth,
                    initialY: y * screenHeight,
                    scale: scale,
                    editMode: _stickerMode,
                    onPositionChanged: (newX, newY) {
                      _updateStickerPosition(
                        id,
                        newX / screenWidth,
                        newY / screenHeight,
                      );
                    },
                    onTap: _stickerMode
                        ? () => _showStickerOptions(sticker)
                        : null,
                  );
                }),

                SafeArea(
                  child: _editing
                      ? _buildEditingLayout(avatar, nickname)
                      : _buildViewingLayout(
                          avatar: avatar,
                          nickname: nickname,
                          statusMessage: statusMessage,
                          pastAvatars: pastAvatars,
                          thumbSize: thumbSize,
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildViewingLayout({
    required String? avatar,
    required String nickname,
    required String? statusMessage,
    required List<Map<String, dynamic>> pastAvatars,
    required double thumbSize,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _GlassIconButton(
                icon: Icons.close_rounded,
                onTap: _stickerMode
                    ? () => setState(() => _stickerMode = false)
                    : () => Navigator.pop(context),
              ),
              const Spacer(),
              if (_stickerMode) ...[
                _GlassIconButton(
                  icon: Icons.add_reaction_outlined,
                  onTap: _saving ? () {} : _addSticker,
                ),
                const SizedBox(width: 8),
                _GlassTextButton(
                  label: '완료',
                  onTap: () => setState(() => _stickerMode = false),
                ),
              ] else ...[
                _MultiProfileButton(
                  count: _subProfilesCount,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubProfilesScreen(),
                      ),
                    );
                    _loadSubProfilesCount();
                  },
                ),
                const SizedBox(width: 8),
                _GlassIconButton(
                  icon: Icons.emoji_emotions_outlined,
                  onTap: () => setState(() => _stickerMode = true),
                ),
                const SizedBox(width: 8),
                _GlassIconButton(
                  icon: Icons.wallpaper_rounded,
                  onTap: _saving ? () {} : _changeBackground,
                ),
                const SizedBox(width: 8),
                _GlassIconButton(
                  icon: Icons.edit_rounded,
                  onTap: () => setState(() => _editing = true),
                ),
              ],
            ],
          ),
        ),

        const Spacer(flex: 2),

        if (!_stickerMode)
          Stack(
            children: [
              Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: AppTheme.primaryLight.withOpacity(0.3),
                      blurRadius: 60,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: avatar != null
                    ? () => _showAvatarFullscreen(avatar)
                    : null,
                child: Container(
                  width: 124,
                  height: 124,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryLight,
                        AppTheme.primary,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: Container(
                      color: AppTheme.bg,
                      padding: const EdgeInsets.all(2),
                      child: ClipOval(
                        child: AvatarWidget(
                          url: avatar,
                          name: nickname,
                          size: 114,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _saving ? null : _changeAvatar,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.85),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppTheme.bg, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: _saving
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),

        if (!_stickerMode) ...[
          const SizedBox(height: 20),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                Colors.white,
                Colors.white.withOpacity(0.85),
              ],
            ).createShader(bounds),
            child: Text(
              nickname,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          if (statusMessage != null && statusMessage.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter:
                      ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                    child: Text(
                      statusMessage,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.95),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],

        const Spacer(flex: 3),

        if (_stickerMode)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.touch_app_rounded,
                            color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '스티커를 드래그해서 이동, 탭해서 편집하세요',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        if (!_stickerMode && pastAvatars.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.history_rounded,
                      color: AppTheme.textSub, size: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  '이전 프로필 사진',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2),
                ),
                const SizedBox(width: 6),
                Text(
                  '${pastAvatars.length}',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSub,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          SizedBox(
            height: thumbSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const BouncingScrollPhysics(),
              itemCount: pastAvatars.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final item = pastAvatars[i];
                final url = item['avatar_url'] as String;
                return GestureDetector(
                  onTap: () => _showAvatarFullscreen(url),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        url,
                        width: thumbSize,
                        height: thumbSize,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => Container(
                          width: thumbSize,
                          height: thumbSize,
                          color: AppTheme.border,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppTheme.textSub,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEditingLayout(String? avatar, String currentNickname) {
    final nicknameLen = _nicknameController.text.characters.length;
    final statusLen = _statusController.text.characters.length;
    final canSave = nicknameLen >= 2 && !_saving;

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : _cancelEditing,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withOpacity(0.85),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    minimumSize: const Size(60, 36),
                  ),
                  child: const Text('취소',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      '프로필 편집',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: canSave ? _saveProfile : null,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      constraints: const BoxConstraints(
                          minWidth: 60, minHeight: 36),
                      decoration: BoxDecoration(
                        gradient: canSave
                            ? LinearGradient(
                                colors: [
                                  AppTheme.primary,
                                  AppTheme.primary.withOpacity(0.85),
                                ],
                              )
                            : null,
                        color: canSave
                            ? null
                            : Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: canSave
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary
                                      .withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(
                              '저장',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: canSave
                                    ? Colors.white
                                    : Colors.white
                                        .withOpacity(0.4),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryLight,
                            AppTheme.primary,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: Container(
                          color: AppTheme.bg,
                          padding: const EdgeInsets.all(2),
                          child: ClipOval(
                            child: AvatarWidget(
                              url: avatar,
                              name: currentNickname,
                              size: 98,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _saving ? null : _changeAvatar,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primary,
                                AppTheme.primary.withOpacity(0.85),
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.bg, width: 3),
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
                const SizedBox(height: 8),
                Text(
                  '프로필 사진을 눌러 변경',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 28),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter:
                          ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(
                            18, 18, 18, 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color:
                                  Colors.white.withOpacity(0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _FieldLabel(
                              label: '닉네임',
                              count: nicknameLen,
                              max: 20,
                            ),
                            const SizedBox(height: 8),
                            _GlassTextField(
                              controller: _nicknameController,
                              hintText: '예: 교진',
                              maxLength: 20,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(20),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                  top: 6, left: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    nicknameLen < 2
                                        ? Icons.info_outline_rounded
                                        : Icons
                                            .check_circle_outline_rounded,
                                    size: 11,
                                    color: nicknameLen < 2
                                        ? const Color(0xFFFCA5A5)
                                        : Colors.white
                                            .withOpacity(0.5),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    nicknameLen < 2
                                        ? '2자 이상 입력해주세요'
                                        : '한국어, 영문, 숫자 모두 가능해요',
                                    style: TextStyle(
                                      color: nicknameLen < 2
                                          ? const Color(0xFFFCA5A5)
                                          : Colors.white
                                              .withOpacity(0.5),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _FieldLabel(
                              label: '상태 메시지',
                              count: statusLen,
                              max: 50,
                              optional: true,
                            ),
                            const SizedBox(height: 8),
                            _GlassTextField(
                              controller: _statusController,
                              hintText: '오늘의 기분이나 짧은 한마디',
                              maxLength: 50,
                              textInputAction: TextInputAction.done,
                              maxLines: 2,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(50),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const List<String> _emojiList = [
    '❤️', '💖', '💕', '💗', '💓', '💝', '💘', '💞',
    '😀', '😁', '😂', '🤣', '😊', '😇', '🙂', '😉',
    '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛',
    '🤩', '🤗', '🤔', '🤨', '😎', '🥳', '🥺', '😢',
    '🌟', '✨', '💫', '⭐', '🌙', '☀️', '🌈', '🔥',
    '🍀', '🌸', '🌺', '🌷', '🌹', '🌻', '🌼', '💐',
    '🎀', '🎁', '🎂', '🎉', '🎊', '🎈', '🍰', '🍭',
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
    '👑', '💎', '💍', '👗', '👠', '🎩', '🕶️', '💄',
    '☕', '🍵', '🧃', '🍹', '🍸', '🥂', '🍷', '🍾',
  ];
}

// ═══════════════════════════════════════════════════
// 전체 화면 이미지 뷰어
// ═══════════════════════════════════════════════════
class _FullscreenImageViewer extends StatelessWidget {
  final String url;

  const _FullscreenImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              color: Colors.black,
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _GlassIconButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A1655),
            const Color(0xFF1E1B3A),
            const Color(0xFF0F0F1F),
            AppTheme.bg,
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.15),
          shape: CircleBorder(
            side: BorderSide(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GlassTextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.15),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MultiProfileButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MultiProfileButton({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _GlassIconButton(
          icon: Icons.theater_comedy_outlined,
          onTap: onTap,
        ),
        if (count > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withOpacity(0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.bg, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints:
                  const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                '$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final int count;
  final int max;
  final bool optional;

  const _FieldLabel({
    required this.label,
    required this.count,
    required this.max,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '선택',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const Spacer(),
        Text(
          '$count',
          style: TextStyle(
            color: count > 0
                ? Colors.white.withOpacity(0.8)
                : Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          ' / $max',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final int maxLines;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  const _GlassTextField({
    required this.controller,
    required this.hintText,
    required this.maxLength,
    this.maxLines = 1,
    this.textInputAction,
    this.inputFormatters,
  });

  @override
  State<_GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<_GlassTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(_focused ? 0.55 : 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? AppTheme.primaryLight.withOpacity(0.7)
              : Colors.white.withOpacity(0.15),
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          cursorColor: AppTheme.primaryLight,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1),
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontWeight: FontWeight.w500,
            ),
            counterText: '',
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _DraggableSticker extends StatefulWidget {
  final String emoji;
  final double initialX;
  final double initialY;
  final double scale;
  final bool editMode;
  final void Function(double x, double y) onPositionChanged;
  final VoidCallback? onTap;

  const _DraggableSticker({
    super.key,
    required this.emoji,
    required this.initialX,
    required this.initialY,
    required this.scale,
    required this.editMode,
    required this.onPositionChanged,
    this.onTap,
  });

  @override
  State<_DraggableSticker> createState() => _DraggableStickerState();
}

class _DraggableStickerState extends State<_DraggableSticker> {
  late double _x;
  late double _y;

  @override
  void initState() {
    super.initState();
    _x = widget.initialX;
    _y = widget.initialY;
  }

  @override
  void didUpdateWidget(_DraggableSticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialX != widget.initialX ||
        oldWidget.initialY != widget.initialY) {
      _x = widget.initialX;
      _y = widget.initialY;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = 60.0 * widget.scale;

    return Positioned(
      left: _x - size / 2,
      top: _y - size / 2,
      child: GestureDetector(
        onTap: widget.onTap,
        onPanUpdate: widget.editMode
            ? (details) {
                setState(() {
                  _x += details.delta.dx;
                  _y += details.delta.dy;
                });
              }
            : null,
        onPanEnd: widget.editMode
            ? (_) => widget.onPositionChanged(_x, _y)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: widget.editMode
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.primaryLight.withOpacity(0.6),
                      width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                )
              : null,
          child: Center(
            child: Text(widget.emoji,
                style: TextStyle(fontSize: size * 0.7)),
          ),
        ),
      ),
    );
  }
}