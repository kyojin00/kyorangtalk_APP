import 'package:flutter/material.dart';
import '../../../core/security/app_lock_service.dart';
import '../../../core/theme/app_theme.dart';
import 'app_lock_setup_screen.dart';

// ═══════════════════════════════════════════════════
// 🔐 AppLockSettingsScreen — 앱 잠금 전용 설정
//
// 위치: lib/features/profile/screens/app_lock_settings_screen.dart
//
// 항목
//   1) 앱 잠금 사용 (토글)
//   2) PIN 변경 (잠금 ON 일 때만)
//   3) 지문으로 잠금 해제 (잠금 ON + 기기 지원 + PIN 있음)
//
// 동작
//   - 토글 ON  → PIN 설정 화면 push → 성공 시 잠금 활성화
//   - 토글 OFF → 확인 다이얼로그 → setLockEnabled(false) (PIN/생체 자동 삭제)
// ═══════════════════════════════════════════════════

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() =>
      _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  bool _loading = true;
  bool _enabled = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await AppLockService.isLockEnabled();
    final biometricAvailable =
        await AppLockService.canUseBiometric();
    final biometricEnabled =
        await AppLockService.isBiometricEnabled();

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _biometricAvailable = biometricAvailable;
      _biometricEnabled = biometricEnabled;
      _loading = false;
    });
  }

  // ─────────────────────────────────────────────
  // 잠금 토글
  // ─────────────────────────────────────────────
  Future<void> _toggleLock(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      if (value) {
        // ON: PIN 설정 화면 push
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => const AppLockSetupScreen(
              mode: AppLockSetupMode.newPin,
            ),
          ),
        );

        if (ok == true) {
          // PIN 설정 화면 안에서 setLockEnabled(true)까지 처리됨
          if (!mounted) return;
          setState(() => _enabled = true);
          _showSnack('앱 잠금이 활성화됐어요');
        }
      } else {
        // OFF: 확인 다이얼로그
        final confirm = await _confirmDisable();
        if (!confirm) return;

        await AppLockService.setLockEnabled(false);
        if (!mounted) return;
        setState(() {
          _enabled = false;
          _biometricEnabled = false;
        });
        _showSnack('앱 잠금이 해제됐어요');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDisable() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '앱 잠금 해제',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          '잠금을 해제하면 PIN과 지문 설정도 함께 삭제돼요.\n계속할까요?',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: TextStyle(color: AppTheme.textSub),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '해제',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ─────────────────────────────────────────────
  // PIN 변경
  // ─────────────────────────────────────────────
  Future<void> _changePin() async {
    if (_busy) return;

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AppLockSetupScreen(
          mode: AppLockSetupMode.changePin,
        ),
      ),
    );

    if (ok == true && mounted) {
      _showSnack('PIN이 변경됐어요');
    }
  }

  // ─────────────────────────────────────────────
  // 지문 토글
  // ─────────────────────────────────────────────
  Future<void> _toggleBiometric(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      if (value) {
        // 활성화 전 한 번 검증 (사용자가 실제로 지문 등록돼 있는지)
        final ok = await AppLockService.authenticateBiometric(
          reason: '지문 인증으로 잠금 해제를 활성화해주세요',
        );
        if (!ok) {
          _showSnack('지문 인증에 실패했어요');
          return;
        }
      }

      await AppLockService.setBiometricEnabled(value);
      if (!mounted) return;
      setState(() => _biometricEnabled = value);
      _showSnack(
        value ? '지문 잠금 해제를 켰어요' : '지문 잠금 해제를 껐어요',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textMain,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '앱 잠금',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primary,
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // 안내 카드
                  _InfoCard(),

                  const SizedBox(height: 20),

                  // 메인 토글 카드
                  _SettingCard(
                    children: [
                      _ToggleRow(
                        icon: Icons.lock_outline_rounded,
                        title: '앱 잠금 사용',
                        subtitle: '앱 진입 시 PIN으로 잠금 해제',
                        value: _enabled,
                        onChanged: _busy ? null : _toggleLock,
                      ),
                    ],
                  ),

                  if (_enabled) ...[
                    const SizedBox(height: 12),

                    _SettingCard(
                      children: [
                        _ActionRow(
                          icon: Icons.password_rounded,
                          title: 'PIN 변경',
                          onTap: _busy ? null : _changePin,
                        ),
                        if (_biometricAvailable) ...[
                          Divider(
                            color: AppTheme.border,
                            height: 1,
                            indent: 56,
                          ),
                          _ToggleRow(
                            icon: Icons.fingerprint_rounded,
                            title: '지문으로 잠금 해제',
                            subtitle: '지문이 빠르고 편해요',
                            value: _biometricEnabled,
                            onChanged: _busy ? null : _toggleBiometric,
                          ),
                        ],
                      ],
                    ),
                  ],

                  if (_enabled && !_biometricAvailable) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '이 기기는 지문 인증을 지원하지 않거나, 등록된 지문이 없어요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 안내 카드 (잠금 사용 시 미리 알아둘 점)
// ═══════════════════════════════════════════════════
class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.10),
            AppTheme.primary.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.shield_outlined,
              color: AppTheme.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '앱 진입을 잠금으로 보호해요',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'PIN을 잊으면 앱을 재설치해야 잠금을 풀 수 있어요. '
                  '잠금을 해제하면 PIN과 지문 설정도 함께 삭제돼요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSub,
                    height: 1.5,
                    letterSpacing: -0.1,
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

// ═══════════════════════════════════════════════════
// 설정 카드 (한 묶음)
// ═══════════════════════════════════════════════════
class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: children),
    );
  }
}

// ═══════════════════════════════════════════════════
// 토글 행
// ═══════════════════════════════════════════════════
class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
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
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSub,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 액션 행 (탭 시 이동)
// ═══════════════════════════════════════════════════
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: AppTheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.textSub,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}