import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 🔒 비밀번호 입력 / 변경 / 공유 다이얼로그 모음
// ═══════════════════════════════════════════════════
//
// 입장 시:        showRoomPasswordDialog(context, roomName: ...)
// 비번 변경:      showChangePasswordDialog(context, hasPassword: ...)
// 비번 설정 카드: PasswordSettingsCard(...)
// 초대 공유 시트: showInviteShareSheet(context, roomName, inviteCode, hasPassword)
// ═══════════════════════════════════════════════════

/// 입장 시 비밀번호 입력. 취소 시 null.
Future<String?> showRoomPasswordDialog(
  BuildContext context, {
  required String roomName,
  String? errorMessage,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PasswordDialog(
      roomName: roomName,
      controller: controller,
      initialError: errorMessage,
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  final String roomName;
  final TextEditingController controller;
  final String? initialError;

  const _PasswordDialog({
    required this.roomName,
    required this.controller,
    this.initialError,
  });

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  void _submit() {
    final pw = widget.controller.text.trim();
    if (pw.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요');
      return;
    }
    Navigator.pop(context, pw);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline,
                  color: AppTheme.primary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              '비밀번호 입력',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '"${widget.roomName}"는 비밀번호로 보호된 방이에요',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 12.5,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: widget.controller,
              autofocus: true,
              obscureText: _obscure,
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              decoration: InputDecoration(
                hintText: '비밀번호',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.bg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppTheme.textSub,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Color(0xFFEF4444), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('취소',
                        style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('입장',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
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

// ═══════════════════════════════════════════════════
// 비밀번호 설정 카드 (방 만들기 시트에서 사용)
// ═══════════════════════════════════════════════════
class PasswordSettingsCard extends StatefulWidget {
  final bool enabled;
  final TextEditingController controller;
  final ValueChanged<bool> onToggle;

  const PasswordSettingsCard({
    super.key,
    required this.enabled,
    required this.controller,
    required this.onToggle,
  });

  @override
  State<PasswordSettingsCard> createState() => _PasswordSettingsCardState();
}

class _PasswordSettingsCardState extends State<PasswordSettingsCard> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.enabled
              ? AppTheme.primary.withOpacity(0.4)
              : AppTheme.border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.enabled
                      ? AppTheme.primary.withOpacity(0.15)
                      : AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.lock_outline,
                  color: widget.enabled
                      ? AppTheme.primary
                      : AppTheme.textSub,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '비밀번호 설정',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.enabled
                          ? '입장 시 비밀번호를 물어봐요'
                          : '비밀번호 없이 누구나 입장 가능',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSub,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: widget.enabled,
                activeColor: AppTheme.primary,
                onChanged: widget.onToggle,
              ),
            ],
          ),
          if (widget.enabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: widget.controller,
              obscureText: _obscure,
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLength: 32,
              decoration: InputDecoration(
                hintText: '4자 이상 입력',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.bgCard,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                counterStyle:
                    TextStyle(color: AppTheme.textSub, fontSize: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.primary, width: 1.2),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppTheme.textSub,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 🔧 비밀번호 변경/제거 시트 (방장 전용)
// ═══════════════════════════════════════════════════
//
// 반환값:
//   - String "" (빈 문자열) : 비번 제거 요청
//   - String 비번값         : 새 비번으로 변경 요청
//   - null                  : 취소
//
// 호출 후 provider의 updateRoomPassword()로 전달.
// ═══════════════════════════════════════════════════

Future<String?> showChangePasswordDialog(
  BuildContext context, {
  required bool hasPassword,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ChangePasswordSheet(hasPassword: hasPassword),
  );
}

class _ChangePasswordSheet extends StatefulWidget {
  final bool hasPassword;
  const _ChangePasswordSheet({required this.hasPassword});

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _controller = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final pw = _controller.text.trim();
    if (pw.length < 4) {
      setState(() => _error = '4자 이상 입력해주세요');
      return;
    }
    Navigator.pop(context, pw);
  }

  Future<void> _confirmRemove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('비밀번호 제거',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text(
          '비밀번호를 제거하면 누구나 자유롭게 입장할 수 있어요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('제거',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      Navigator.pop(context, ''); // 빈 문자열 = 제거
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.lock_outline,
                        color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.hasPassword
                              ? '비밀번호 변경'
                              : '비밀번호 설정',
                          style: TextStyle(
                              color: AppTheme.textMain,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.hasPassword
                              ? '새 비밀번호를 입력해주세요'
                              : '입장 시 사용할 비밀번호를 정해주세요',
                          style: TextStyle(
                              color: AppTheme.textSub, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: _obscure,
                maxLength: 32,
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3),
                decoration: InputDecoration(
                  hintText: '4자 이상 입력',
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                  filled: true,
                  fillColor: AppTheme.bg,
                  counterStyle:
                      TextStyle(color: AppTheme.textSub, fontSize: 10),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppTheme.textSub,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.hasPassword ? '비밀번호 변경' : '비밀번호 설정',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
              if (widget.hasPassword) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _confirmRemove,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    '비밀번호 제거',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 📤 초대 공유 시트 (복사 / 외부 공유)
// ═══════════════════════════════════════════════════

Future<void> showInviteShareSheet(
  BuildContext context, {
  required String roomName,
  required String inviteCode,
  required bool hasPassword,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _InviteShareSheet(
      roomName: roomName,
      inviteCode: inviteCode,
      hasPassword: hasPassword,
    ),
  );
}

class _InviteShareSheet extends StatelessWidget {
  final String roomName;
  final String inviteCode;
  final bool hasPassword;

  const _InviteShareSheet({
    required this.roomName,
    required this.inviteCode,
    required this.hasPassword,
  });

  String _buildShareText() {
    final inviteUrl = 'https://open.kyorang.com/join/$inviteCode';
    final lines = <String>[
      '"$roomName" 채팅방에 초대합니다',
      '',
      '👇 아래 링크를 누르면 입장돼요',
      inviteUrl,
      '',
      '초대코드: $inviteCode',
    ];
    if (hasPassword) {
      lines.add('');
      lines.add('* 이 채팅방은 비밀번호가 필요해요. 방장에게 비밀번호를 받아주세요.');
    }
    return lines.join('\n');
  }

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: inviteCode));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대코드가 복사됐어요')),
    );
  }

  void _copyAll(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _buildShareText()));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대 메시지가 복사됐어요')),
    );
  }

  Future<void> _shareExternal(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _buildShareText();
    Navigator.pop(context);

    // 시트 닫는 애니메이션 끝나고 호출
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      print('📤 Share 시도: ${text.length}자');
      await Share.share(text, subject: '$roomName 채팅방 초대');
      print('📤 Share 호출 완료');
    } catch (e, st) {
      print('📤 Share 실패: $e\n$st');
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(
        SnackBar(content: Text('공유 실패: 메시지를 복사했어요')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.share_outlined,
                      color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('채팅방 초대',
                          style: TextStyle(
                              color: AppTheme.textMain,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        hasPassword
                            ? '비밀번호 보호 채팅방이에요'
                            : '초대코드로 누구나 입장할 수 있어요',
                        style: TextStyle(
                            color: AppTheme.textSub, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 초대코드 박스
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('초대코드',
                            style: TextStyle(
                                color: AppTheme.textSub, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(
                          inviteCode,
                          style: const TextStyle(
                              color: AppTheme.primaryLight,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.5),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyCode(context),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('복사',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (hasPassword) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Color(0xFFFBBF24), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '비밀번호는 별도로 알려주세요',
                        style: TextStyle(
                          color: AppTheme.textSub,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.send_rounded,
                  color: AppTheme.primary, size: 18),
            ),
            title: Text('다른 앱으로 공유',
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            subtitle: Text('카톡, 문자, 메일 등',
                style: TextStyle(
                    color: AppTheme.textSub, fontSize: 12)),
            onTap: () => _shareExternal(context),
          ),
          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.text_snippet_outlined,
                  color: AppTheme.textSub, size: 18),
            ),
            title: Text('초대 메시지 복사',
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            subtitle: Text('이름, 코드 포함된 안내 메시지',
                style: TextStyle(
                    color: AppTheme.textSub, fontSize: 12)),
            onTap: () => _copyAll(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}