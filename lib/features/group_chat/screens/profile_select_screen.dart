import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ═══════════════════════════════════════════════
// 🎭 ProfileSelectScreen — 리디자인
//
// 변경:
// - 헤더: 원형 글래스 버튼 + 26pt 큰 타이틀
// - 안내 카드: 그라데이션 + 큰 이모지
// - 프로필 타일: 그라데이션 보더 (선택 시 글로우)
// - 라디오 체크: primary 그라데이션 + 그림자
// - 추가 버튼: 더 화려한 그라데이션 카드
// - 입장 버튼: primary 그라데이션 + 그림자
// - 새 프로필 시트: 글래스 + 그라데이션
// ═══════════════════════════════════════════════

// ═══════════════════════════════════════════════
// 모델 (유지)
// ═══════════════════════════════════════════════
class ProfileSelection {
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

  String get displayName =>
      nickname?.isNotEmpty == true ? nickname! : name;
}

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
// Providers (유지)
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
// 메인 화면
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
  String? _selectedSubProfileId;
  bool _defaultSelected = true;

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
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
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
      body: SafeArea(
        child: Column(
          children: [
            // ─── 헤더 ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  _CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                    iconColor: AppTheme.primaryLight,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '프로필 선택',
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: mainProfileAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary)),
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
                            style: TextStyle(
                                color: AppTheme.textSub))),
                    data: (subProfiles) {
                      return Column(
                        children: [
                          // ─── 안내 카드 ────────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                16, 4, 16, 16),
                            child: _InfoCard(roomName: widget.roomName),
                          ),

                          // ─── 프로필 목록 ──────────────────
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 16),
                              physics: const BouncingScrollPhysics(),
                              children: [
                                // 기본 프로필
                                if (mainProfile != null) ...[
                                  _SectionLabel(
                                    icon: Icons.star_rounded,
                                    label: '기본 프로필',
                                  ),
                                  const SizedBox(height: 10),
                                  _ProfileTile(
                                    name: mainProfile.nickname,
                                    subtitle: mainProfile
                                                .statusMessage
                                                ?.isNotEmpty ==
                                            true
                                        ? mainProfile.statusMessage!
                                        : '내 본 프로필',
                                    avatarUrl: mainProfile.avatarUrl,
                                    isSelected: _defaultSelected,
                                    isDefault: true,
                                    onTap: _selectDefault,
                                  ),
                                ],

                                // 서브 프로필
                                if (subProfiles.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  _SectionLabel(
                                    icon: Icons.theater_comedy_rounded,
                                    label: '서브 프로필',
                                    count: subProfiles.length,
                                  ),
                                  const SizedBox(height: 10),
                                  ...subProfiles.map((profile) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 10),
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
                                        onTap: () =>
                                            _selectSub(profile.id),
                                      ),
                                    );
                                  }),
                                ],

                                // 추가 버튼
                                const SizedBox(height: 16),
                                _AddProfileButton(
                                  isFirst: subProfiles.isEmpty,
                                  onTap: _showCreateProfileSheet,
                                ),

                                const SizedBox(height: 40),
                              ],
                            ),
                          ),

                          // ─── 하단 입장 버튼 ───────────────
                          SafeArea(
                            top: false,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 12, 16, 12),
                              decoration: BoxDecoration(
                                color: AppTheme.bg,
                                border: Border(
                                  top: BorderSide(
                                    color: AppTheme.border
                                        .withOpacity(0.5),
                                    width: 0.8,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withOpacity(0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: _JoinButton(
                                enabled: (_defaultSelected &&
                                        mainProfile != null) ||
                                    _selectedSubProfileId != null,
                                onTap: () => _confirm(
                                    mainProfile, subProfiles),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 원형 글래스 버튼
// ═══════════════════════════════════════════════
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(icon, color: iconColor, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 안내 카드 (헤더 아래)
// ═══════════════════════════════════════════════
class _InfoCard extends StatelessWidget {
  final String roomName;

  const _InfoCard({required this.roomName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.12),
            AppTheme.primary.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withOpacity(0.25),
                  AppTheme.primary.withOpacity(0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('🎭', style: TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '어떤 프로필로 참여할까요?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMain,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '"$roomName"에 입장할 프로필을 선택해주세요',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSub,
                    height: 1.4,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFBBF24).withOpacity(0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_rounded,
                          color: Color(0xFFFBBF24), size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '한 번 선택하면 변경할 수 없어요',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: const Color(0xFFFBBF24),
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
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
    );
  }
}

// ═══════════════════════════════════════════════
// 섹션 라벨
// ═══════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;

  const _SectionLabel({
    required this.icon,
    required this.label,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textSub),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSub,
              letterSpacing: 0.2,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.primaryLight,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 프로필 타일
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary.withOpacity(0.15),
                      AppTheme.primary.withOpacity(0.05),
                    ],
                  )
                : null,
            color: isSelected ? null : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primary.withOpacity(0.6)
                  : AppTheme.border,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.2),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // 아바타 (선택 시 글로우)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.3),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: AvatarWidget(
                  url: avatarUrl,
                  name: name,
                  size: 52,
                ),
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
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textMain,
                              letterSpacing: -0.3,
                            ),
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
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primary.withOpacity(0.2),
                                  AppTheme.primary.withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color:
                                    AppTheme.primary.withOpacity(0.3),
                                width: 0.6,
                              ),
                            ),
                            child: Text('기본',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: AppTheme.primaryLight,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.1)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub,
                          letterSpacing: -0.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 체크 라디오
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.85),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : AppTheme.border,
                    width: 2,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 프로필 추가 버튼
// ═══════════════════════════════════════════════
class _AddProfileButton extends StatelessWidget {
  final bool isFirst;
  final VoidCallback onTap;

  const _AddProfileButton({
    required this.isFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withOpacity(0.12),
                AppTheme.primary.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.35),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.85),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        isFirst ? '새 서브 프로필 만들기' : '프로필 추가하기',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 3),
                    Text('다른 닉네임과 아바타로 활동해요',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSub,
                            letterSpacing: -0.2)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 입장 버튼
// ═══════════════════════════════════════════════
class _JoinButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _JoinButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54,
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withOpacity(0.85),
                ],
              )
            : null,
        color: enabled ? null : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(15),
        border: enabled
            ? null
            : Border.all(color: AppTheme.border),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.login_rounded,
                    color: enabled
                        ? Colors.white
                        : AppTheme.textMuted,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '선택한 프로필로 입장',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: enabled
                          ? Colors.white
                          : AppTheme.textMuted,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
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
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_rounded,
                  color: AppTheme.textMain),
              title: Text('카메라로 촬영',
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w600)),
              onTap: () =>
                  Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded,
                  color: AppTheme.textMain),
              title: Text('갤러리에서 선택',
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w600)),
              onTap: () =>
                  Navigator.pop(context, ImageSource.gallery),
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
        final path = 'sub-profiles/${user.id}_$timestamp.$ext';

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
        'status_message': _statusController.text.trim().isEmpty
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
    final canCreate =
        _nameController.text.trim().isNotEmpty && !_creating;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20)),
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
                  borderRadius: BorderRadius.circular(2)),
            ),
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.25),
                          AppTheme.primary.withOpacity(0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.theater_comedy_rounded,
                        color: AppTheme.primary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text('새 서브 프로필',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMain,
                        letterSpacing: -0.3,
                      )),
                  const Spacer(),
                  // 완료 버튼
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canCreate ? _create : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: canCreate
                              ? LinearGradient(
                                  colors: [
                                    AppTheme.primary,
                                    AppTheme.primary.withOpacity(0.85),
                                  ],
                                )
                              : null,
                          color:
                              canCreate ? null : AppTheme.bg,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: canCreate
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primary
                                        .withOpacity(0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: _creating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : Text('완료',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: canCreate
                                      ? Colors.white
                                      : AppTheme.textMuted,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                )),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                children: [
                  // 아바타 선택
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _avatarFile == null
                                  ? LinearGradient(
                                      colors: [
                                        AppTheme.primary
                                            .withOpacity(0.15),
                                        AppTheme.primary
                                            .withOpacity(0.05),
                                      ],
                                    )
                                  : null,
                              color: _avatarFile == null
                                  ? null
                                  : AppTheme.bg,
                              border: Border.all(
                                color: AppTheme.primary
                                    .withOpacity(0.4),
                                width: 2,
                              ),
                              image: _avatarFile != null
                                  ? DecorationImage(
                                      image: FileImage(
                                          _avatarFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary
                                      .withOpacity(0.2),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: _avatarFile == null
                                ? Icon(
                                    Icons.camera_alt_rounded,
                                    color: AppTheme.primary,
                                    size: 32)
                                : null,
                          ),
                          if (_avatarFile != null)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primary,
                                      AppTheme.primary
                                          .withOpacity(0.85),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppTheme.bgCard,
                                      width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary
                                          .withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                    Icons.edit_rounded,
                                    color: Colors.white,
                                    size: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      _avatarFile == null
                          ? '아바타 추가 (선택)'
                          : '아바타 변경',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  _FieldLabel(label: '프로필 이름', required: true),
                  const SizedBox(height: 8),
                  _StyledTextField(
                    controller: _nameController,
                    hint: '예) 게임 캐릭터, 익명',
                    maxLength: 20,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  _FieldLabel(label: '닉네임', optional: true),
                  const SizedBox(height: 8),
                  _StyledTextField(
                    controller: _nicknameController,
                    hint: '채팅방에 표시될 이름',
                    maxLength: 15,
                  ),
                  const SizedBox(height: 16),

                  _FieldLabel(label: '상태 메시지', optional: true),
                  const SizedBox(height: 8),
                  _StyledTextField(
                    controller: _statusController,
                    hint: '나를 표현해보세요',
                    maxLength: 30,
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

// ═══════════════════════════════════════════════
// 필드 라벨
// ═══════════════════════════════════════════════
class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  final bool optional;

  const _FieldLabel({
    required this.label,
    this.required = false,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppTheme.textMain,
            letterSpacing: -0.2,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFFEF4444),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        if (optional) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '선택',
              style: TextStyle(
                fontSize: 9,
                color: AppTheme.textSub,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// 스타일 텍스트 필드 (포커스 효과)
// ═══════════════════════════════════════════════
class _StyledTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final ValueChanged<String>? onChanged;

  const _StyledTextField({
    required this.controller,
    required this.hint,
    required this.maxLength,
    this.onChanged,
  });

  @override
  State<_StyledTextField> createState() => _StyledTextFieldState();
}

class _StyledTextFieldState extends State<_StyledTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted && _focused != _focusNode.hasFocus) {
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
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? AppTheme.primary.withOpacity(0.5)
              : AppTheme.border,
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        style: TextStyle(
          color: AppTheme.textMain,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        cursorColor: AppTheme.primary,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w400,
          ),
          counterStyle: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 10,
          ),
          filled: false,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}