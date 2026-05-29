import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../services/my_profile_service.dart';
import '../sheets/photo_visibility_sheet.dart';
import '../widgets/my_profile_widgets.dart';
import '../widgets/profile_gallery_section.dart';
import 'photo_viewer_screen.dart';
import 'sub_profiles_screen.dart';

// ═══════════════════════════════════════════════════
// MyProfileScreen — 안전 최종본
// ⭐ 배경 cacheWidth 축소 (OOM 방지)
// ⭐ 스티커 좌표 clamp (무한 레이아웃 방지)
// ⭐ 배경 BackdropFilter 제거 (편집 시 단순 반투명)
// ⭐ currentUser! → _myId 안전 패턴
// ═══════════════════════════════════════════════════

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() =>
      _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  String? _myId;
  MyProfileService? _service;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _stickers = [];
  List<Map<String, dynamic>> _photos = [];
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
    _initialize();
  }

  Future<void> _initialize() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      await Future.delayed(const Duration(milliseconds: 500));
      final retryUser = Supabase.instance.client.auth.currentUser;
      if (retryUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인 정보를 불러올 수 없어요')),
          );
          Navigator.of(context).pop();
        }
        return;
      }
      _myId = retryUser.id;
    } else {
      _myId = user.id;
    }
    _service = MyProfileService(myId: _myId!);
    await _loadData();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_service == null) return;
    try {
      await Future.wait([
        _loadProfile(),
        _loadStickers(),
        _loadSubProfilesCount(),
        _loadPhotos(),
      ]);
    } catch (e) {
      debugPrint('🔴 _loadData 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile() async {
    if (_service == null) return;
    try {
      final data = await _service!.loadProfile();
      if (mounted && data != null) {
        setState(() {
          _profile = data;
          _nicknameController.text = data['nickname'] as String? ?? '';
          _statusController.text =
              data['status_message'] as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint('🔴 _loadProfile 실패: $e');
    }
  }

  Future<void> _loadStickers() async {
    if (_service == null) return;
    try {
      final data = await _service!.loadStickers();
      if (mounted) setState(() => _stickers = data);
    } catch (e) {
      debugPrint('🔴 _loadStickers 실패: $e');
    }
  }

  Future<void> _loadSubProfilesCount() async {
    if (_service == null) return;
    try {
      final count = await _service!.loadSubProfilesCount();
      if (mounted) setState(() => _subProfilesCount = count);
    } catch (e) {
      debugPrint('🔴 _loadSubProfilesCount 실패: $e');
    }
  }

  Future<void> _loadPhotos() async {
    if (_service == null) return;
    try {
      final data = await _service!.loadPhotos();
      if (mounted) setState(() => _photos = data);
    } catch (e) {
      debugPrint('🔴 _loadPhotos 실패: $e');
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

  Future<void> _changeAvatar() async {
    if (_service == null) return;
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
      final file = File(picked.path);
      final ext = picked.path.split('.').last.toLowerCase();
      await _service!.changeAvatar(
        file: file,
        ext: ext,
        currentPhotos: _photos,
      );
      await _loadProfile();
      await _loadPhotos();
      _showSnack('프로필 사진이 변경됐어요!');
    } catch (e) {
      _showSnack('사진 업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _changeBackground() async {
    if (_service == null) return;
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
            ListTile(
              leading: Icon(Icons.camera_alt_rounded,
                  color: AppTheme.textMain),
              title: Text('카메라로 촬영',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded,
                  color: AppTheme.primary),
              title: Text('갤러리에서 원본 선택',
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w700)),
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
        await _service!.removeBackground();
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
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (picked == null) return;
      file = File(picked.path);
      ext = picked.path.split('.').last.toLowerCase();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;
      file = File(filePath);
      ext = filePath.split('.').last.toLowerCase();
    }

    setState(() => _saving = true);
    try {
      final sizeMB = (await file.length()) / 1024 / 1024;
      if (sizeMB > 50) {
        _showSnack('파일이 너무 커요 (${sizeMB.toStringAsFixed(1)}MB)');
        setState(() => _saving = false);
        return;
      }

      await _service!.changeBackground(file: file, ext: ext);
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

  Future<void> _addGalleryPhoto() async {
    if (_service == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.first.path;
    if (filePath == null) return;

    final file = File(filePath);
    final ext = filePath.split('.').last.toLowerCase();

    setState(() => _saving = true);
    try {
      final sizeMB = (await file.length()) / 1024 / 1024;
      if (sizeMB > 50) {
        _showSnack('파일이 너무 커요 (${sizeMB.toStringAsFixed(1)}MB)');
        setState(() => _saving = false);
        return;
      }

      await _service!.addGalleryPhoto(
        file: file,
        ext: ext,
        currentPhotos: _photos,
      );
      await _loadPhotos();
      _showSnack('사진이 추가됐어요!');
    } catch (e) {
      _showSnack('업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteGalleryPhoto(int index) async {
    if (_service == null) return;
    if (index < 0 || index >= _photos.length) return;
    try {
      await _service!
          .deleteGalleryPhoto(_photos[index]['id'] as String);
      await _loadPhotos();
      _showSnack('사진이 삭제됐어요');
    } catch (e) {
      _showSnack('삭제 실패: $e');
    }
  }

  Future<void> _changePhotoVisibility(int index) async {
    if (_myId == null) return;
    if (index < 0 || index >= _photos.length) return;
    final photo = _photos[index];
    final result = await showPhotoVisibilitySheet(
      context: context,
      photoId: photo['id'] as String,
      currentVisibility: photo['visibility'] as String? ?? 'friends',
      myId: _myId!,
    );

    if (result != null) {
      await _loadPhotos();
      _showSnack('공개 범위가 변경됐어요');
    }
  }

  Future<void> _setPhotoAsAvatar(int index) async {
    if (_service == null) return;
    if (index < 0 || index >= _photos.length) return;
    setState(() => _saving = true);
    try {
      await _service!
          .setPhotoAsAvatar(_photos[index]['photo_url'] as String);
      imageCache.clear();
      imageCache.clearLiveImages();
      await _loadProfile();
      _showSnack('프로필 사진으로 설정됐어요!');
    } catch (e) {
      _showSnack('설정 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _addSticker() async {
    if (_service == null) return;
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
                children: kProfileEmojiList.map((emoji) {
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
      await _service!.addSticker(emoji);
      await _loadStickers();
      _showSnack('스티커가 추가됐어요! 드래그해서 위치를 조정하세요');
    } catch (e) {
      _showSnack('추가 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showStickerOptions(Map<String, dynamic> sticker) {
    if (_service == null) return;
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
                  margin: const EdgeInsets.symmetric(vertical: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
                            onChanged: (v) => setS(() => scale = v),
                            onChangeEnd: (v) async {
                              await _service!
                                  .updateStickerScale(id, v);
                              await _loadStickers();
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
                    await _service!.deleteSticker(id);
                    await _loadStickers();
                    _showSnack('스티커가 삭제됐어요');
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
    if (_service == null) return;
    final nickname = _nicknameController.text.trim();
    if (nickname.length < 2) {
      _showSnack('닉네임은 2자 이상이어야 해요');
      return;
    }

    setState(() => _saving = true);
    try {
      await _service!.saveProfile(
        nickname: nickname,
        statusMessage: _statusController.text.trim(),
      );
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
        pageBuilder: (_, __, ___) => PhotoViewerScreen(
          imageUrls: [url],
          initialIndex: 0,
          isOwner: false,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _showBackgroundFullscreen(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => PhotoViewerScreen(
          imageUrls: [url],
          initialIndex: 0,
          isOwner: false,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _nicknameController.text = _profile?['nickname'] as String? ?? '';
      _statusController.text =
          _profile?['status_message'] as String? ?? '';
    });
    FocusScope.of(context).unfocus();
  }

  // ═══════════════════════════════════════════════════
  // build
  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_myId == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    final nickname = _profile?['nickname'] as String? ?? '';
    final avatar = _profile?['avatar_url'] as String?;
    final background = _profile?['background_url'] as String?;
    final statusMessage = _profile?['status_message'] as String?;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bgCacheWidth = (screenWidth * 1.5).round();
    final bgCacheHeight = (screenHeight * 1.5).round();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: _editing,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : Stack(
              children: [
                // ─── 배경 + 그라데이션 오버레이를 하나로 합침 (레이어 축소) ───
                Positioned.fill(
                  child: GestureDetector(
                    onTap: (background != null &&
                            !_editing &&
                            !_stickerMode)
                        ? () => _showBackgroundFullscreen(background)
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 배경 이미지 or 기본 배경
                        if (background != null)
                          Image.network(
                            background,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            cacheWidth: bgCacheWidth,
                            cacheHeight: bgCacheHeight,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                const DefaultBackground(),
                          )
                        else
                          const DefaultBackground(),
                        // 그라데이션 오버레이 (같은 Stack 안에 통합)
                        IgnorePointer(
                          child: DecoratedBox(
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
                        // 편집 모드 어두운 오버레이
                        if (_editing)
                          IgnorePointer(
                            child: ColoredBox(
                              color: Colors.black.withOpacity(0.65),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ─── 스티커 ───
                ..._buildStickers(screenWidth, screenHeight),

                // ─── 본문 ───
                SafeArea(
                  child: _editing
                      ? _buildEditingLayout(avatar, nickname)
                      : _buildViewingLayout(
                          avatar: avatar,
                          nickname: nickname,
                          statusMessage: statusMessage,
                        ),
                ),
              ],
            ),
    );
  }

  List<Widget> _buildStickers(double screenWidth, double screenHeight) {
    return _stickers.map((sticker) {
      final id = sticker['id'] as String? ?? '';
      final emoji = sticker['emoji'] as String? ?? '⭐';

      // ⭐ 좌표 검증: null/NaN/Infinity/범위초과 방어
      double x = (sticker['pos_x'] as num?)?.toDouble() ?? 0.5;
      double y = (sticker['pos_y'] as num?)?.toDouble() ?? 0.4;
      double scale = (sticker['scale'] as num?)?.toDouble() ?? 1.0;

      if (!x.isFinite) x = 0.5;
      if (!y.isFinite) y = 0.4;
      if (!scale.isFinite) scale = 1.0;
      x = x.clamp(0.0, 1.0);
      y = y.clamp(0.0, 1.0);
      scale = scale.clamp(0.5, 2.5);

      return DraggableSticker(
        key: ValueKey(id),
        emoji: emoji,
        initialX: x * screenWidth,
        initialY: y * screenHeight,
        scale: scale,
        editMode: _stickerMode,
        onPositionChanged: (newX, newY) {
          if (_service != null && screenWidth > 0 && screenHeight > 0) {
            final px = (newX / screenWidth).clamp(0.0, 1.0);
            final py = (newY / screenHeight).clamp(0.0, 1.0);
            _service!.updateStickerPosition(id, px, py);
          }
        },
        onTap: _stickerMode ? () => _showStickerOptions(sticker) : null,
      );
    }).toList();
  }


  // ═══════════════════════════════════════════════════
  // 보기 레이아웃
  // ═══════════════════════════════════════════════════
  Widget _buildViewingLayout({
    required String? avatar,
    required String nickname,
    required String? statusMessage,
  }) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                GlassIconButton(
                  icon: Icons.close_rounded,
                  onTap: _stickerMode
                      ? () => setState(() => _stickerMode = false)
                      : () => Navigator.pop(context),
                ),
                const Spacer(),
                if (_stickerMode) ...[
                  GlassIconButton(
                    icon: Icons.add_reaction_outlined,
                    onTap: _saving ? () {} : _addSticker,
                  ),
                  const SizedBox(width: 8),
                  GlassTextButton(
                    label: '완료',
                    onTap: () => setState(() => _stickerMode = false),
                  ),
                ] else ...[
                  MultiProfileButton(
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
                  GlassIconButton(
                    icon: Icons.emoji_emotions_outlined,
                    onTap: () => setState(() => _stickerMode = true),
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.wallpaper_rounded,
                    onTap: _saving ? () {} : _changeBackground,
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.edit_rounded,
                    onTap: () => setState(() => _editing = true),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
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
                      ),
                      child: _saving
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
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
            Text(
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
            if (statusMessage != null && statusMessage.isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
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
            ],
            const SizedBox(height: 32),
          ],
          if (!_stickerMode) ...[
            ProfileGallerySection(
              photos: _photos,
              isOwner: true,
              onAddPhoto: _saving ? null : _addGalleryPhoto,
              onDelete: _deleteGalleryPhoto,
              onVisibilityChange: _changePhotoVisibility,
              onSetAsAvatar: _setPhotoAsAvatar,
            ),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 편집 레이아웃 (BackdropFilter 제거됨)
  // ═══════════════════════════════════════════════════
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
                  child: const Text('취소',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      '프로필 편집',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
                      decoration: BoxDecoration(
                        gradient: canSave
                            ? LinearGradient(colors: [
                                AppTheme.primary,
                                AppTheme.primary.withOpacity(0.85),
                              ])
                            : null,
                        color: canSave
                            ? null
                            : Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text('저장',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: canSave
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.4),
                              )),
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
                            gradient: LinearGradient(colors: [
                              AppTheme.primary,
                              AppTheme.primary.withOpacity(0.85),
                            ]),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.bg, width: 3),
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: Colors.white, size: 14),
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
                  child: Container(
                    padding:
                        const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FieldLabel(
                          label: '닉네임',
                          count: nicknameLen,
                          max: 20,
                        ),
                        const SizedBox(height: 8),
                        GlassTextField(
                          controller: _nicknameController,
                          hintText: '예: 교진',
                          maxLength: 20,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(20),
                          ],
                        ),
                        const SizedBox(height: 20),
                        FieldLabel(
                          label: '상태 메시지',
                          count: statusLen,
                          max: 50,
                          optional: true,
                        ),
                        const SizedBox(height: 8),
                        GlassTextField(
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}