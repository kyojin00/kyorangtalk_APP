import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

class SubProfilesScreen extends ConsumerStatefulWidget {
  const SubProfilesScreen({super.key});

  @override
  ConsumerState<SubProfilesScreen> createState() =>
      _SubProfilesScreenState();
}

class _SubProfilesScreenState
    extends ConsumerState<SubProfilesScreen> {
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  List<Map<String, dynamic>> _subProfiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_sub_profiles')
        .select('*')
        .eq('user_id', _myId)
        .order('created_at', ascending: true);
    if (mounted) {
      setState(() {
        _subProfiles = List.from(data);
        _loading = false;
      });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
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
  }

  Future<void> _createSubProfile() async {
    final name = await _showNameDialog();
    if (name == null || name.trim().isEmpty) return;

    try {
      await Supabase.instance.client
          .from('kyorangtalk_sub_profiles')
          .insert({
        'user_id': _myId,
        'name':    name.trim(),
      });
      await _load();
      _showSnack('부캐 프로필이 생성됐어요!');
    } catch (e) {
      _showSnack('생성 실패: $e');
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('새 부캐 프로필',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppTheme.textMain),
          maxLength: 20,
          decoration: InputDecoration(
            hintText: '예: 회사용, 친구용, 가족용',
            hintStyle: TextStyle(color: AppTheme.textSub),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.border),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text),
            child: const Text('만들기',
                style: TextStyle(
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSubProfile(
      String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('부캐 프로필 삭제',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text(
          '"$name"을(를) 삭제할까요?\n이 프로필을 보던 친구들은 기본 프로필을 보게 돼요.',
          style: TextStyle(
              color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('kyorangtalk_sub_profiles')
          .delete()
          .eq('id', id);
      await _load();
      _showSnack('삭제됐어요');
    } catch (e) {
      _showSnack('삭제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('멀티 프로필',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add,
                color: AppTheme.primary),
            onPressed: _createSubProfile,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary))
          : _subProfiles.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.primary
                                .withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppTheme.primaryLight,
                              size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '부캐별로 닉네임/사진/배경을 다르게 설정하고,\n친구마다 다른 프로필을 보여줄 수 있어요',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSub,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    ..._subProfiles.map((sp) {
                      return _buildProfileCard(sp);
                    }),

                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: _createSubProfile,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppTheme.primary
                                  .withOpacity(0.3),
                              style: BorderStyle.solid,
                              width: 1.5),
                        ),
                        child: const Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline,
                                color: AppTheme.primaryLight,
                                size: 20),
                            SizedBox(width: 8),
                            Text('새 부캐 프로필 만들기',
                                style: TextStyle(
                                    color: AppTheme
                                        .primaryLight,
                                    fontSize: 14,
                                    fontWeight:
                                        FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎭', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 20),
          Text('부캐 프로필이 없어요',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              '친구마다 다른 프로필을 보여줄 수 있어요\n회사용, 친구용, 가족용 등 자유롭게 만들어보세요',
              style: TextStyle(
                  color: AppTheme.textSub,
                  fontSize: 13,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _createSubProfile,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add,
                      color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('새 부캐 만들기',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> sp) {
    final id       = sp['id'] as String;
    final name     = sp['name'] as String;
    final nickname = sp['nickname'] as String?;
    final avatar   = sp['avatar_url'] as String?;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SubProfileDetailScreen(subProfileId: id),
          ),
        );
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            AvatarWidget(
                url: avatar,
                name: nickname ?? name,
                size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary
                              .withOpacity(0.15),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryLight,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nickname ?? '닉네임 미설정',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: nickname != null
                            ? AppTheme.textMain
                            : AppTheme.textSub),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: AppTheme.bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              icon: Icon(Icons.more_vert,
                  color: AppTheme.textSub, size: 20),
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteSubProfile(id, name);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          color: Color(0xFFEF4444), size: 18),
                      SizedBox(width: 10),
                      Text('삭제',
                          style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SubProfileDetailScreen extends ConsumerStatefulWidget {
  final String subProfileId;
  const SubProfileDetailScreen({
    super.key,
    required this.subProfileId,
  });

  @override
  ConsumerState<SubProfileDetailScreen> createState() =>
      _SubProfileDetailScreenState();
}

class _SubProfileDetailScreenState
    extends ConsumerState<SubProfileDetailScreen> {
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  Map<String, dynamic>? _subProfile;
  List<Map<String, dynamic>> _viewers = [];
  bool _loading = true;
  bool _saving  = false;
  bool _editing = false;

  final _nameController     = TextEditingController();
  final _nicknameController = TextEditingController();
  final _statusController   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadProfile(),
      _loadViewers(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadProfile() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_sub_profiles')
        .select('*')
        .eq('id', widget.subProfileId)
        .maybeSingle();
    if (mounted && data != null) {
      setState(() {
        _subProfile = data;
        _nameController.text =
            data['name'] as String? ?? '';
        _nicknameController.text =
            data['nickname'] as String? ?? '';
        _statusController.text =
            data['status_message'] as String? ?? '';
      });
    }
  }

  Future<void> _loadViewers() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_sub_profile_viewers')
        .select('viewer_id')
        .eq('sub_profile_id', widget.subProfileId);

    if (data.isEmpty) {
      if (mounted) setState(() => _viewers = []);
      return;
    }

    final viewerIds =
        data.map((v) => v['viewer_id'] as String).toList();
    final profiles = await Supabase.instance.client
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url')
        .inFilter('id', viewerIds);

    if (mounted) setState(() => _viewers = List.from(profiles));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
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
          'sub-avatars/$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage
          .from('kyorangtalk')
          .upload(path, file,
              fileOptions: const FileOptions(upsert: true));

      final url = supabase.storage
          .from('kyorangtalk').getPublicUrl(path);

      await supabase
          .from('kyorangtalk_sub_profiles')
          .update({'avatar_url': url})
          .eq('id', widget.subProfileId);

      await _loadProfile();
      _showSnack('프로필 사진이 변경됐어요!');
    } catch (e) {
      _showSnack('업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppTheme.textMain),
              title: Text('갤러리에서 선택',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_subProfile?['background_url'] != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFEF4444)),
                title: const Text('배경 제거',
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
            .from('kyorangtalk_sub_profiles')
            .update({'background_url': null})
            .eq('id', widget.subProfileId);
        await _loadProfile();
        _showSnack('배경화면이 제거됐어요');
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
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
          'sub-backgrounds/$_myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage
          .from('kyorangtalk')
          .upload(path, file,
              fileOptions: const FileOptions(upsert: true));

      final url = supabase.storage
          .from('kyorangtalk').getPublicUrl(path);

      await supabase
          .from('kyorangtalk_sub_profiles')
          .update({'background_url': url})
          .eq('id', widget.subProfileId);

      await _loadProfile();
      _showSnack('배경화면이 변경됐어요!');
    } catch (e) {
      _showSnack('업로드 실패: $e');
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('kyorangtalk_sub_profiles')
          .update({
        'name':           _nameController.text.trim(),
        'nickname':       _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        'status_message': _statusController.text.trim().isEmpty
            ? null
            : _statusController.text.trim(),
      }).eq('id', widget.subProfileId);

      await _loadProfile();
      setState(() { _editing = false; _saving = false; });
      _showSnack('저장됐어요!');
    } catch (e) {
      setState(() => _saving = false);
      _showSnack('저장 실패: $e');
    }
  }

  Future<void> _manageViewers() async {
    final friendsData = await Supabase.instance.client
        .from('kyorangtalk_friends')
        .select('*')
        .or('requester_id.eq.$_myId,receiver_id.eq.$_myId')
        .eq('status', 'accepted');

    if (friendsData.isEmpty) {
      _showSnack('친구가 없어요. 먼저 친구를 추가하세요!');
      return;
    }

    final friendIds = friendsData.map((f) {
      return f['requester_id'] == _myId
          ? f['receiver_id'] as String
          : f['requester_id'] as String;
    }).toList();

    final profiles = await Supabase.instance.client
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url')
        .inFilter('id', friendIds);

    final currentViewers = _viewers
        .map((v) => v['id'] as String)
        .toSet();

    final otherSubProfiles = await Supabase.instance.client
        .from('kyorangtalk_sub_profiles')
        .select('id')
        .eq('user_id', _myId)
        .neq('id', widget.subProfileId);

    final otherSubIds = otherSubProfiles
        .map((s) => s['id'] as String)
        .toList();

    Map<String, String> assignedTo = {};
    if (otherSubIds.isNotEmpty) {
      final assignedData = await Supabase.instance.client
          .from('kyorangtalk_sub_profile_viewers')
          .select('viewer_id, sub_profile_id')
          .inFilter('sub_profile_id', otherSubIds);

      for (final a in assignedData) {
        assignedTo[a['viewer_id'] as String] =
            a['sub_profile_id'] as String;
      }
    }

    final allSubProfiles = await Supabase.instance.client
        .from('kyorangtalk_sub_profiles')
        .select('id, name')
        .eq('user_id', _myId);

    final subProfileNames = {
      for (final s in allSubProfiles)
        s['id'] as String: s['name'] as String
    };

    if (!mounted) return;

    final selectedIds = Set<String>.from(currentViewers);

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('이 프로필을 볼 친구 선택',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMain)),
                          const SizedBox(height: 2),
                          Text('선택 안 한 친구는 기본 프로필을 봐요',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSub)),
                        ],
                      ),
                    ),
                    Text('${selectedIds.length}명',
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.primaryLight,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Divider(
                  color: AppTheme.border, height: 1),
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  itemCount: profiles.length,
                  itemBuilder: (_, i) {
                    final prof = profiles[i];
                    final id = prof['id'] as String;
                    final isSelected =
                        selectedIds.contains(id);
                    final otherSubId = assignedTo[id];
                    final otherSubName = otherSubId != null
                        ? subProfileNames[otherSubId]
                        : null;

                    return InkWell(
                      onTap: () {
                        setLocalState(() {
                          if (isSelected) {
                            selectedIds.remove(id);
                          } else {
                            selectedIds.add(id);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            AvatarWidget(
                                url: prof['avatar_url']
                                    as String?,
                                name: prof['nickname']
                                    as String?,
                                size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    prof['nickname']
                                            as String? ??
                                        '알 수 없음',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                            FontWeight.w600,
                                        color: AppTheme
                                            .textMain),
                                  ),
                                  if (otherSubName != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets
                                              .only(top: 2),
                                      child: Text(
                                        '현재: $otherSubName',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme
                                                .textSub),
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
                                      color: Colors.white,
                                      size: 14)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20,
                    MediaQuery.of(ctx).padding.bottom + 12),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.bg,
                            borderRadius:
                                BorderRadius.circular(14),
                            border: Border.all(
                                color: AppTheme.border),
                          ),
                          child: Center(
                            child: Text('취소',
                                style: TextStyle(
                                    color: AppTheme.textSub,
                                    fontWeight:
                                        FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            Navigator.pop(ctx, selectedIds),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                                '저장 (${selectedIds.length})',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('kyorangtalk_sub_profile_viewers')
          .delete()
          .eq('sub_profile_id', widget.subProfileId);

      if (result.isNotEmpty) {
        await Supabase.instance.client
            .from('kyorangtalk_sub_profile_viewers')
            .delete()
            .inFilter('viewer_id', result.toList());

        final inserts = result.map((id) => {
              'sub_profile_id': widget.subProfileId,
              'viewer_id':      id,
            }).toList();

        await Supabase.instance.client
            .from('kyorangtalk_sub_profile_viewers')
            .insert(inserts);
      }

      await _loadViewers();
      _showSnack(result.isEmpty
          ? '아무도 이 프로필을 볼 수 없어요'
          : '${result.length}명이 이 프로필을 봐요');
    } catch (e) {
      _showSnack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _subProfile == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: const Center(
            child: CircularProgressIndicator(
                color: AppTheme.primary)),
      );
    }

    final name = _subProfile!['name'] as String;
    final nickname =
        _subProfile!['nickname'] as String? ?? '';
    final avatar =
        _subProfile!['avatar_url'] as String?;
    final background =
        _subProfile!['background_url'] as String?;
    final statusMessage =
        _subProfile!['status_message'] as String?;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: background != null
                ? Image.network(background,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF1E1B3A)))
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

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios,
                            color: Colors.white, size: 20),
                        onPressed: () =>
                            Navigator.pop(context),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight:
                                    FontWeight.w800)),
                      ),
                      const Spacer(),
                      if (!_editing) ...[
                        IconButton(
                          icon: const Icon(
                              Icons.wallpaper_outlined,
                              color: Colors.white, size: 22),
                          onPressed: _saving
                              ? null
                              : _changeBackground,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white, size: 22),
                          onPressed: () =>
                              setState(() => _editing = true),
                        ),
                      ] else ...[
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() {
                                    _editing = false;
                                    _nameController.text =
                                        _subProfile!['name']
                                                as String? ??
                                            '';
                                    _nicknameController.text =
                                        _subProfile![
                                                    'nickname']
                                                as String? ??
                                            '';
                                    _statusController.text =
                                        _subProfile![
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
                          onPressed: _saving ? null : _save,
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

                Stack(
                  children: [
                    Container(
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
                        name: nickname.isEmpty ? name : nickname,
                        size: 100,
                      ),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: GestureDetector(
                        onTap: _saving ? null : _changeAvatar,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.bg, width: 3),
                          ),
                          child: _saving
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child:
                                      CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                )
                              : const Icon(Icons.camera_alt,
                                  color: Colors.white,
                                  size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (!_editing)
                  Text(
                    nickname.isEmpty ? '닉네임 미설정' : nickname,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: nickname.isEmpty
                            ? Colors.white.withOpacity(0.5)
                            : Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 8,
                          ),
                        ]),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70),
                          maxLength: 20,
                          decoration: InputDecoration(
                            hintText: '부캐 이름 (회사용, 친구용)',
                            hintStyle: TextStyle(
                                color: Colors.white
                                    .withOpacity(0.3),
                                fontSize: 12),
                            counterStyle: TextStyle(
                                color: Colors.white
                                    .withOpacity(0.4),
                                fontSize: 10),
                            border: InputBorder.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
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
                                  color:
                                      AppTheme.primaryLight),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),

                if (!_editing) ...[
                  if (statusMessage != null &&
                      statusMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40),
                      child: Text(
                        statusMessage,
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white
                                .withOpacity(0.85),
                            shadows: [
                              Shadow(
                                color:
                                    Colors.black.withOpacity(0.5),
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
                          color: Colors.white.withOpacity(0.8)),
                      maxLength: 50,
                      decoration: InputDecoration(
                        hintText: '상태 메시지 (선택)',
                        hintStyle: TextStyle(
                            color:
                                Colors.white.withOpacity(0.3)),
                        counterStyle: TextStyle(
                            color:
                                Colors.white.withOpacity(0.4),
                            fontSize: 10),
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                const Spacer(flex: 3),

                if (!_editing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        20, 8, 20, 20),
                    child: GestureDetector(
                      onTap: _manageViewers,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius:
                              BorderRadius.circular(14),
                          border: Border.all(
                              color: AppTheme.primaryLight
                                  .withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                                Icons.people_outline,
                                color:
                                    AppTheme.primaryLight,
                                size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  const Text(
                                      '이 프로필을 볼 친구',
                                      style: TextStyle(
                                          color:
                                              Colors.white,
                                          fontSize: 13,
                                          fontWeight:
                                              FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _viewers.isEmpty
                                        ? '아직 설정 안 함'
                                        : '${_viewers.length}명',
                                    style: TextStyle(
                                        color: _viewers.isEmpty
                                            ? Colors.white70
                                            : AppTheme
                                                .primaryLight,
                                        fontSize: 12,
                                        fontWeight:
                                            FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            if (_viewers.isNotEmpty)
                              SizedBox(
                                width: 60,
                                height: 32,
                                child: Stack(
                                  children: _viewers
                                      .take(3)
                                      .toList()
                                      .asMap()
                                      .entries
                                      .map((e) {
                                    return Positioned(
                                      right: e.key * 18.0,
                                      child: Container(
                                        decoration:
                                            BoxDecoration(
                                          shape:
                                              BoxShape.circle,
                                          border: Border.all(
                                              color: AppTheme
                                                  .bgCard,
                                              width: 2),
                                        ),
                                        child: AvatarWidget(
                                          url: e.value[
                                                  'avatar_url']
                                              as String?,
                                          name: e.value[
                                                  'nickname']
                                              as String?,
                                          size: 28,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            const SizedBox(width: 8),
                            const Icon(
                                Icons.chevron_right,
                                color: Colors.white54,
                                size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}