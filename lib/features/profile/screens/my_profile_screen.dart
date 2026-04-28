import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import 'sub_profiles_screen.dart';

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
  List<Map<String, dynamic>> _stickers      = [];
  int _subProfilesCount = 0;
  bool _loading = true;
  bool _editing = false;
  bool _stickerMode = false;
  bool _saving  = false;

  final _nicknameController = TextEditingController();
  final _statusController   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
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
        _nicknameController.text =
            data['nickname'] as String? ?? '';
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
          content: Text(msg,
              style: TextStyle(color: AppTheme.textMain)),
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
    final picker = ImagePicker();
    final source = await _showImageSourceDialog();
    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024, maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      final file = File(picked.path);
      final ext  = picked.path.split('.').last;
      final path =
          'avatars/$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage
          .from('kyorangtalk')
          .upload(path, file,
              fileOptions: const FileOptions(upsert: true));

      final url = supabase.storage
          .from('kyorangtalk').getPublicUrl(path);

      await supabase
          .from('kyorangtalk_profiles')
          .update({'avatar_url': url})
          .eq('id', _myId);

      await supabase.from('kyorangtalk_avatar_history').insert({
        'user_id':    _myId,
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

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20))),
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
              onTap: () =>
                  Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
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

  Future<void> _changeBackground() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20))),
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
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('배경화면',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined,
                  color: AppTheme.textMain),
              title: Text('카메라로 촬영',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppTheme.textMain),
              title: Text('갤러리에서 선택',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_profile?['background_url'] != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFEF4444)),
                title: const Text('배경화면 제거',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600)),
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

    final source = action == 'camera'
        ? ImageSource.camera : ImageSource.gallery;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1920, maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      final file = File(picked.path);
      final ext  = picked.path.split('.').last;
      final path =
          'backgrounds/$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage
          .from('kyorangtalk')
          .upload(path, file,
              fileOptions: const FileOptions(upsert: true));

      final url = supabase.storage
          .from('kyorangtalk').getPublicUrl(path);

      await supabase
          .from('kyorangtalk_profiles')
          .update({'background_url': url})
          .eq('id', _myId);

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
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            Container(
              width: 36, height: 4,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
              ),
            ),
            Expanded(
              child: GridView.count(
                controller: sc,
                crossAxisCount: 6,
                padding: const EdgeInsets.all(16),
                children: _emojiList.map((emoji) {
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, emoji),
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
        'user_id':  _myId,
        'emoji':    emoji,
        'pos_x':    0.5,
        'pos_y':    0.4,
        'scale':    1.0,
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

  Future<void> _updateStickerPosition(String id,
      double x, double y) async {
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
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          double scale = currentScale;
          return SafeArea(
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
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Text(sticker['emoji'] as String,
                          style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 12),
                      Text('스티커 편집',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain)),
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
                              fontSize: 13)),
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
                  leading: const Icon(Icons.delete_outline,
                      color: Color(0xFFEF4444)),
                  title: const Text('삭제',
                      style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w600)),
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
      final existing = await supabase
          .from('kyorangtalk_profiles')
          .select('id')
          .eq('nickname', nickname)
          .neq('id', _myId)
          .maybeSingle();

      if (existing != null) {
        setState(() => _saving = false);
        _showSnack('이미 사용 중인 닉네임이에요');
        return;
      }

      final status = _statusController.text.trim();
      await supabase.from('kyorangtalk_profiles').upsert({
        'id':             _myId,
        'nickname':       nickname,
        'status_message': status.isEmpty ? null : status,
      });

      await _loadProfile();
      setState(() { _editing = false; _saving = false; });
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
        pageBuilder: (_, __, ___) => Scaffold(
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
                      child: Image.network(url,
                          fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nickname = _profile?['nickname'] as String? ?? '';
    final avatar   = _profile?['avatar_url'] as String?;
    final background = _profile?['background_url'] as String?;
    final statusMessage =
        _profile?['status_message'] as String?;

    final List<Map<String, dynamic>> pastAvatars = [];
    if (_avatarHistory.length > 1) {
      pastAvatars.addAll(_avatarHistory.sublist(1));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final thumbSize = (screenWidth - 40 - 30) / 4;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary))
          : Stack(
              children: [
                Positioned.fill(
                  child: background != null
                      ? Image.network(background,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(
                                  color:
                                      const Color(0xFF1E1B3A)))
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF1E1B3A),
                                AppTheme.bg,
                              ],
                            ),
                          ),
                        ),
                ),

                if (background != null)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.black.withOpacity(0.1),
                            AppTheme.bg.withOpacity(0.3),
                            AppTheme.bg,
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),

                ..._stickers.map((sticker) {
                  final id = sticker['id'] as String;
                  final emoji = sticker['emoji'] as String;
                  final x =
                      (sticker['pos_x'] as num?)?.toDouble() ?? 0.5;
                  final y =
                      (sticker['pos_y'] as num?)?.toDouble() ?? 0.4;
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
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white, size: 24),
                              onPressed: _stickerMode
                                  ? () => setState(
                                      () => _stickerMode = false)
                                  : () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            if (_stickerMode) ...[
                              IconButton(
                                icon: const Icon(
                                    Icons.add_reaction_outlined,
                                    color: Colors.white,
                                    size: 24),
                                onPressed:
                                    _saving ? null : _addSticker,
                              ),
                              TextButton(
                                onPressed: () => setState(
                                    () => _stickerMode = false),
                                child: const Text('완료',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight:
                                            FontWeight.w800)),
                              ),
                            ] else if (!_editing) ...[
                              _MultiProfileButton(
                                count: _subProfilesCount,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SubProfilesScreen(),
                                    ),
                                  );
                                  _loadSubProfilesCount();
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                    Icons.emoji_emotions_outlined,
                                    color: Colors.white,
                                    size: 22),
                                onPressed: () => setState(
                                    () => _stickerMode = true),
                                tooltip: '스티커',
                              ),
                              IconButton(
                                icon: const Icon(
                                    Icons.wallpaper_outlined,
                                    color: Colors.white,
                                    size: 22),
                                onPressed: _saving
                                    ? null
                                    : _changeBackground,
                                tooltip: '배경화면',
                              ),
                              IconButton(
                                icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Colors.white,
                                    size: 22),
                                onPressed: () {
                                  setState(
                                      () => _editing = true);
                                },
                              ),
                            ] else ...[
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        setState(() {
                                          _editing = false;
                                          _nicknameController
                                                  .text =
                                              _profile?[
                                                      'nickname']
                                                  as String? ??
                                                  '';
                                          _statusController
                                                  .text =
                                              _profile?[
                                                      'status_message']
                                                  as String? ??
                                                  '';
                                        });
                                      },
                                child: const Text('취소',
                                    style: TextStyle(
                                        color: Colors.white70)),
                              ),
                              TextButton(
                                onPressed:
                                    _saving ? null : _saveProfile,
                                child: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child:
                                            CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color:
                                                    Colors.white))
                                    : const Text('저장',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight:
                                                FontWeight.w800)),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const Spacer(flex: 2),

                      if (!_stickerMode)
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: avatar != null
                                  ? () =>
                                      _showAvatarFullscreen(avatar)
                                  : null,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary
                                          .withOpacity(0.3),
                                      blurRadius: 20,
                                    ),
                                  ],
                                  border: Border.all(
                                      color: Colors.white
                                          .withOpacity(0.2),
                                      width: 2),
                                ),
                                child: AvatarWidget(
                                  url:  avatar,
                                  name: nickname,
                                  size: 100,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: GestureDetector(
                                onTap: _saving
                                    ? null
                                    : _changeAvatar,
                                child: Container(
                                  width: 34, height: 34,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: AppTheme.bg,
                                        width: 3),
                                  ),
                                  child: _saving
                                      ? const Padding(
                                          padding:
                                              EdgeInsets.all(8),
                                          child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color:
                                                      Colors.white),
                                        )
                                      : const Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                          size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),

                      if (!_stickerMode) ...[
                        const SizedBox(height: 16),

                        if (!_editing)
                          Text(
                            nickname,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black
                                        .withOpacity(0.5),
                                    blurRadius: 8,
                                  ),
                                ]),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 48),
                            child: TextField(
                              controller: _nicknameController,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                              maxLength: 20,
                              decoration: InputDecoration(
                                hintText: '닉네임',
                                hintStyle: TextStyle(
                                    color: Colors.white
                                        .withOpacity(0.3)),
                                counterStyle: TextStyle(
                                    color: Colors.white
                                        .withOpacity(0.4),
                                    fontSize: 10),
                                enabledBorder:
                                    UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: Colors.white
                                          .withOpacity(0.2)),
                                ),
                                focusedBorder:
                                    const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppTheme
                                          .primaryLight),
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 8),

                        if (!_editing) ...[
                          if (statusMessage != null &&
                              statusMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets
                                  .symmetric(horizontal: 40),
                              child: Text(
                                statusMessage,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white
                                        .withOpacity(0.85),
                                    shadows: [
                                      Shadow(
                                        color: Colors.black
                                            .withOpacity(0.5),
                                        blurRadius: 6,
                                      ),
                                    ]),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 48),
                            child: TextField(
                              controller: _statusController,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white
                                      .withOpacity(0.8)),
                              maxLength: 50,
                              decoration: InputDecoration(
                                hintText: '상태 메시지 (선택)',
                                hintStyle: TextStyle(
                                    color: Colors.white
                                        .withOpacity(0.3)),
                                counterStyle: TextStyle(
                                    color: Colors.white
                                        .withOpacity(0.4),
                                    fontSize: 10),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                      ],

                      const Spacer(flex: 3),

                      if (_stickerMode)
                        Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.touch_app,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '스티커를 드래그해서 이동, 탭해서 편집하세요',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (!_stickerMode && !_editing &&
                          pastAvatars.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              20, 8, 20, 10),
                          child: Row(
                            children: [
                              Icon(Icons.history_rounded,
                                  color: AppTheme.textSub,
                                  size: 15),
                              const SizedBox(width: 6),
                              Text(
                                '이전 프로필 사진 ${pastAvatars.length}개',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSub,
                                    fontWeight:
                                        FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: thumbSize,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                            itemCount: pastAvatars.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final item = pastAvatars[i];
                              final url =
                                  item['avatar_url'] as String;
                              return GestureDetector(
                                onTap: () =>
                                    _showAvatarFullscreen(url),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  child: Image.network(
                                    url,
                                    width: thumbSize,
                                    height: thumbSize,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (_, __, ___) =>
                                            Container(
                                      width: thumbSize,
                                      height: thumbSize,
                                      color: AppTheme.border,
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
                  ),
                ),
              ],
            ),
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

class _MultiProfileButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MultiProfileButton({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          Center(
            child: IconButton(
              icon: const Icon(Icons.theater_comedy_outlined,
                  color: Colors.white, size: 22),
              onPressed: onTap,
              tooltip: '멀티 프로필',
            ),
          ),
          if (count > 0)
            Positioned(
              top: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.bg, width: 1.5),
                ),
                constraints: const BoxConstraints(
                    minWidth: 16, minHeight: 16),
                child: Text(
                  '$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
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
  State<_DraggableSticker> createState() =>
      _DraggableStickerState();
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
      top:  _y - size / 2,
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
        child: Container(
          width:  size,
          height: size,
          decoration: widget.editMode
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.primaryLight
                          .withOpacity(0.5),
                      width: 2),
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