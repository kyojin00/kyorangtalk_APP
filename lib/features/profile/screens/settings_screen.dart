import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../friends/screens/friends_screen.dart';
import 'my_profile_screen.dart';
import 'notification_settings_screen.dart';
import 'blocked_users_screen.dart';
import 'inquiry_screen.dart';
import 'policy_screen.dart';
import 'privacy_management_screen.dart';


class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() =>
      _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  Map<String, dynamic>? _profile;
  String _version = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadVersion();
  }

  Future<void> _loadProfile() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_profiles')
        .select('nickname, avatar_url, status_message')
        .eq('id', _myId)
        .maybeSingle();
    if (mounted) setState(() => _profile = data);
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = info.version);
      }
    } catch (e) {
      print('버전 로드 실패: $e');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('로그아웃',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text('정말 로그아웃하시겠어요?',
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
            child: const Text('로그아웃',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    ref.invalidate(myProfileProvider);
    ref.invalidate(friendsProvider);
    ref.invalidate(pendingRequestsProvider);
    ref.invalidate(sentRequestsProvider);

    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/login');
  }

  void _showThemeDialog() {
    final currentMode = ref.read(themeProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('테마 설정',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeTile(
              ctx: ctx,
              mode: ThemeMode.light,
              currentMode: currentMode,
              icon: Icons.light_mode_outlined,
              label: '라이트',
            ),
            _themeTile(
              ctx: ctx,
              mode: ThemeMode.dark,
              currentMode: currentMode,
              icon: Icons.dark_mode_outlined,
              label: '다크',
            ),
            _themeTile(
              ctx: ctx,
              mode: ThemeMode.system,
              currentMode: currentMode,
              icon: Icons.settings_brightness_outlined,
              label: '시스템 설정 따라가기',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('닫기',
                style: TextStyle(color: AppTheme.textSub)),
          ),
        ],
      ),
    );
  }

  Widget _themeTile({
    required BuildContext ctx,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required IconData icon,
    required String label,
  }) {
    final selected = mode == currentMode;
    return InkWell(
      onTap: () {
        ref.read(themeProvider.notifier).setTheme(mode);
        Navigator.pop(ctx);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? AppTheme.primary
                    : AppTheme.textSub,
                size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.textMain,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.normal)),
            ),
            if (selected)
              Icon(Icons.check,
                  color: AppTheme.primary, size: 18),
          ],
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '라이트';
      case ThemeMode.dark:
        return '다크';
      case ThemeMode.system:
        return '시스템 설정';
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final nickname = _profile?['nickname'] as String? ?? '';
    final avatar   = _profile?['avatar_url'] as String?;
    final themeMode = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Text('설정',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain)),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyProfileScreen(),
                        ),
                      );
                      _loadProfile();
                      ref.invalidate(myProfileProvider);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          AvatarWidget(
                            url:  avatar,
                            name: nickname,
                            size: 54,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(nickname,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textMain)),
                                const SizedBox(height: 2),
                                if (email != null)
                                  Text(email,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSub)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: AppTheme.textSub),
                        ],
                      ),
                    ),
                  ),

                  Divider(color: AppTheme.border, height: 1),
                  const SizedBox(height: 8),

                  _sectionLabel('화면'),
                  _menuItem(
                    icon:  Icons.palette_outlined,
                    label: '테마',
                    trailing: Text(_themeModeLabel(themeMode),
                        style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 13)),
                    onTap: _showThemeDialog,
                  ),

                  const SizedBox(height: 16),

                  _sectionLabel('알림'),
                  _menuItem(
                    icon:  Icons.notifications_outlined,
                    label: '알림 설정',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const NotificationSettingsScreen(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _sectionLabel('개인정보'),
                  // ✨ 개인정보 관리 메뉴 추가
                  _menuItem(
                    icon: Icons.shield_outlined,
                    label: '개인정보 관리',
                    iconColor: AppTheme.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const PrivacyManagementScreen(),
                      ),
                    ),
                  ),
                  _menuItem(
                    icon:  Icons.block,
                    label: '차단한 친구 관리',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const BlockedUsersScreen(),
                      ),
                    ),
                  ),
                  _menuItem(
                    icon:  Icons.privacy_tip_outlined,
                    label: '개인정보 처리방침',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PolicyScreen(
                            type: PolicyType.privacy),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _sectionLabel('앱 정보'),
                  _menuItem(
                    icon:  Icons.info_outline,
                    label: '버전 정보',
                    trailing: Text(_version,
                        style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 13)),
                    onTap: () {},
                  ),
                  _menuItem(
                    icon:  Icons.description_outlined,
                    label: '이용약관',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PolicyScreen(
                            type: PolicyType.terms),
                      ),
                    ),
                  ),
                  _menuItem(
                    icon:  Icons.mail_outline,
                    label: '문의하기',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InquiryScreen(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _sectionLabel('계정'),
                  _menuItem(
                    icon:  Icons.logout,
                    label: '로그아웃',
                    labelColor: const Color(0xFFEF4444),
                    iconColor:  const Color(0xFFEF4444),
                    onTap: _logout,
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

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSub,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3)),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    Color? labelColor,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon,
                color: iconColor ?? AppTheme.textSub, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      color: labelColor ?? AppTheme.textMain,
                      fontWeight: FontWeight.w500)),
            ),
            if (trailing != null)
              trailing
            else
              Icon(Icons.chevron_right,
                  color: AppTheme.textSub, size: 20),
          ],
        ),
      ),
    );
  }
}