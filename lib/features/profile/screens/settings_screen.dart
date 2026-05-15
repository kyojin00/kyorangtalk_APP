import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../friends/screens/friends_screen.dart';
import '../../subscription/screens/drawer_screen.dart';
import '../../subscription/screens/subscription_screen.dart';
import '../../subscription/services/subscription_service.dart';
import 'app_lock_settings_screen.dart';                       // ⭐ NEW
import 'my_profile_screen.dart';
import 'notification_settings_screen.dart';
import 'blocked_users_screen.dart';
import 'inquiry_screen.dart';
import 'policy_screen.dart';
import 'privacy_management_screen.dart';

// ═══════════════════════════════════════════════════
// ⚙️ SettingsScreen — 리디자인
//
// 변경:
// - 헤더: 큰 타이틀 (26pt w900)
// - 프로필 카드: 그라데이션 + 화살표 원
// - 섹션 헤더: 아이콘 + 카운트 스타일
// - 메뉴 아이템: 원형 아이콘 컨테이너 + 라운드 카드
// - 그룹화: 섹션별 카드 묶음 (그룹 구분 명확)
// - 서랍 메뉴: 더 부각된 디자인
// - 로그아웃: 빨간 톤 강조
// - ⭐ 개인정보 섹션에 "앱 잠금" 메뉴 추가
// ═══════════════════════════════════════════════════

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
              icon: Icons.light_mode_rounded,
              label: '라이트',
            ),
            _themeTile(
              ctx: ctx,
              mode: ThemeMode.dark,
              currentMode: currentMode,
              icon: Icons.dark_mode_rounded,
              label: '다크',
            ),
            _themeTile(
              ctx: ctx,
              mode: ThemeMode.system,
              currentMode: currentMode,
              icon: Icons.settings_brightness_rounded,
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
        color: selected
            ? AppTheme.primary.withOpacity(0.08)
            : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withOpacity(0.15)
                    : AppTheme.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textSub,
                  size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.textMain,
                      fontWeight: selected
                          ? FontWeight.w800
                          : FontWeight.w600)),
            ),
            if (selected)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check,
                    color: Colors.white, size: 12),
              ),
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
    final avatar = _profile?['avatar_url'] as String?;
    final statusMessage =
        _profile?['status_message'] as String?;
    final themeMode = ref.watch(themeProvider);
    final subAsync = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ─── 헤더 ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Text(
                    '설정',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMain,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                physics: const BouncingScrollPhysics(),
                children: [
                  // ═══════════════════════════════════════
                  // 프로필 카드 (그라데이션)
                  // ═══════════════════════════════════════
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
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
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(
                            14, 14, 18, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary.withOpacity(0.10),
                              AppTheme.primary.withOpacity(0.03),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.primary.withOpacity(0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                AvatarWidget(
                                  url: avatar,
                                  name: nickname,
                                  size: 56,
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          nickname,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight:
                                                FontWeight.w800,
                                            color:
                                                AppTheme.textMain,
                                            letterSpacing: -0.3,
                                          ),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (statusMessage != null &&
                                      statusMessage.isNotEmpty)
                                    Text(
                                      statusMessage,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSub,
                                      ),
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    )
                                  else if (email != null)
                                    Text(
                                      email,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSub,
                                      ),
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: AppTheme.textSub,
                                size: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ═══════════════════════════════════════
                  // 메시지 서랍
                  // ═══════════════════════════════════════
                  _SectionLabel(
                    icon: Icons.archive_rounded,
                    title: '메시지 서랍',
                  ),
                  _SectionCard(
                    children: [
                      _DrawerMenuItem(
                        subAsync: subAsync,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DrawerScreen(),
                            ),
                          );
                          ref.invalidate(subscriptionProvider);
                          ref.invalidate(
                              hasActiveSubscriptionProvider);
                        },
                      ),
                      _Divider(),
                      _MenuItem(
                        icon: Icons.workspace_premium_rounded,
                        iconColor: AppTheme.primary,
                        iconBg: AppTheme.primary.withOpacity(0.15),
                        label: '구독 관리',
                        trailing: subAsync.when(
                          loading: () => const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.primary,
                            ),
                          ),
                          error: (_, __) => Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textSub,
                              size: 20),
                          data: (sub) {
                            final active = sub?.isActive ?? false;
                            if (active) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primary,
                                      AppTheme.primary
                                          .withOpacity(0.85),
                                    ],
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary
                                          .withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  '구독 중',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              );
                            }
                            return Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.textSub,
                                size: 20);
                          },
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const SubscriptionScreen(),
                            ),
                          );
                          ref.invalidate(subscriptionProvider);
                          ref.invalidate(
                              hasActiveSubscriptionProvider);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ═══════════════════════════════════════
                  // 화면
                  // ═══════════════════════════════════════
                  _SectionLabel(
                    icon: Icons.palette_rounded,
                    title: '화면',
                  ),
                  _SectionCard(
                    children: [
                      _MenuItem(
                        icon: Icons.palette_outlined,
                        label: '테마',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _themeModeLabel(themeMode),
                            style: TextStyle(
                              color: AppTheme.textMain,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        onTap: _showThemeDialog,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ═══════════════════════════════════════
                  // 알림
                  // ═══════════════════════════════════════
                  _SectionLabel(
                    icon: Icons.notifications_rounded,
                    title: '알림',
                  ),
                  _SectionCard(
                    children: [
                      _MenuItem(
                        icon: Icons.notifications_outlined,
                        label: '알림 설정',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const NotificationSettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ═══════════════════════════════════════
                  // 개인정보
                  // ═══════════════════════════════════════
                  _SectionLabel(
                    icon: Icons.shield_rounded,
                    title: '개인정보',
                  ),
                  _SectionCard(
                    children: [
                      _MenuItem(
                        icon: Icons.shield_outlined,
                        iconColor: AppTheme.primary,
                        iconBg: AppTheme.primary.withOpacity(0.15),
                        label: '개인정보 관리',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const PrivacyManagementScreen(),
                          ),
                        ),
                      ),
                      _Divider(),
                      // ⭐ NEW: 앱 잠금
                      _MenuItem(
                        icon: Icons.lock_outline_rounded,
                        iconColor: AppTheme.primary,
                        iconBg: AppTheme.primary.withOpacity(0.15),
                        label: '앱 잠금',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AppLockSettingsScreen(),
                          ),
                        ),
                      ),
                      _Divider(),
                      _MenuItem(
                        icon: Icons.block_rounded,
                        label: '차단한 친구 관리',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const BlockedUsersScreen(),
                          ),
                        ),
                      ),
                      _Divider(),
                      _MenuItem(
                        icon: Icons.privacy_tip_outlined,
                        label: '개인정보 처리방침',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PolicyScreen(
                                type: PolicyType.privacy),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ═══════════════════════════════════════
                  // 앱 정보
                  // ═══════════════════════════════════════
                  _SectionLabel(
                    icon: Icons.info_rounded,
                    title: '앱 정보',
                  ),
                  _SectionCard(
                    children: [
                      _MenuItem(
                        icon: Icons.info_outline_rounded,
                        label: '버전 정보',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'v$_version',
                            style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        onTap: () {},
                      ),
                      _Divider(),
                      _MenuItem(
                        icon: Icons.description_outlined,
                        label: '이용약관',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PolicyScreen(
                                type: PolicyType.terms),
                          ),
                        ),
                      ),
                      _Divider(),
                      _MenuItem(
                        icon: Icons.mail_outline_rounded,
                        label: '문의하기',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const InquiryScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ═══════════════════════════════════════
                  // 계정
                  // ═══════════════════════════════════════
                  _SectionLabel(
                    icon: Icons.person_rounded,
                    title: '계정',
                  ),
                  _SectionCard(
                    children: [
                      _MenuItem(
                        icon: Icons.logout_rounded,
                        iconColor: const Color(0xFFEF4444),
                        iconBg: const Color(0xFFEF4444)
                            .withOpacity(0.15),
                        label: '로그아웃',
                        labelColor: const Color(0xFFEF4444),
                        labelWeight: FontWeight.w700,
                        showChevron: false,
                        onTap: _logout,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 하단 로고
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'KYORANG TALK',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'v$_version',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
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
// ✨ 보조 위젯들
// ═══════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionLabel({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textSub),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSub,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;

  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 58),
      color: AppTheme.border,
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Color? iconBg;
  final String label;
  final Color? labelColor;
  final FontWeight? labelWeight;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showChevron;

  const _MenuItem({
    required this.icon,
    this.iconColor,
    this.iconBg,
    required this.label,
    this.labelColor,
    this.labelWeight,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg ?? AppTheme.bg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? AppTheme.textMain,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: labelColor ?? AppTheme.textMain,
                    fontWeight: labelWeight ?? FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (trailing != null)
                trailing!
              else if (showChevron)
                Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSub, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 메시지 서랍 메뉴
// ═══════════════════════════════════════════════════
class _DrawerMenuItem extends StatelessWidget {
  final AsyncValue<SubscriptionModel?> subAsync;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.subAsync,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.25),
                      AppTheme.primary.withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.archive_rounded,
                  color: AppTheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '내 서랍',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    subAsync.when(
                      loading: () => Text(
                        '불러오는 중...',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSub,
                        ),
                      ),
                      error: (_, __) => Text(
                        '나간 채팅방 보관함',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSub,
                        ),
                      ),
                      data: (sub) {
                        final active = sub?.isActive ?? false;
                        return Text(
                          active
                              ? '서랍이 열려있어요'
                              : '나간 채팅방의 옛 메시지를 다시 보세요',
                          style: TextStyle(
                            fontSize: 11,
                            color: active
                                ? AppTheme.primary
                                : AppTheme.textSub,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSub, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}