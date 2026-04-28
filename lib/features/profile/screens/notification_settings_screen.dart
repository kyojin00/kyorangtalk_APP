import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/notification_prefs_provider.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('알림 설정',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionLabel('전체 알림'),
          _switchTile(
            icon: Icons.notifications_outlined,
            label: '알림 받기',
            subtitle: '모든 알림을 받거나 끕니다',
            value: prefs.notificationsEnabled,
            onChanged: (v) =>
                notifier.update(notificationsEnabled: v),
          ),

          const SizedBox(height: 16),
          _sectionLabel('알림 방식'),
          _switchTile(
            icon: Icons.volume_up_outlined,
            label: '소리',
            subtitle: '알림 올 때 소리로 알려요',
            value: prefs.soundEnabled,
            enabled: prefs.notificationsEnabled,
            onChanged: (v) => notifier.update(soundEnabled: v),
          ),
          _switchTile(
            icon: Icons.vibration,
            label: '진동',
            subtitle: '알림 올 때 진동으로 알려요',
            value: prefs.vibrationEnabled,
            enabled: prefs.notificationsEnabled,
            onChanged: (v) => notifier.update(vibrationEnabled: v),
          ),

          const SizedBox(height: 16),
          _sectionLabel('미리보기'),
          _switchTile(
            icon: Icons.preview_outlined,
            label: '메시지 내용 표시',
            subtitle: '알림에 메시지 내용이 보여요',
            value: prefs.messagePreviewEnabled,
            enabled: prefs.notificationsEnabled,
            onChanged: (v) =>
                notifier.update(messagePreviewEnabled: v),
          ),

          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '각 채팅방 알림은 채팅방에서 따로 설정할 수 있어요',
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
        ],
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

  Widget _switchTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(icon,
              color: enabled
                  ? AppTheme.textSub
                  : AppTheme.textMuted,
              size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        color: enabled
                            ? AppTheme.textMain
                            : AppTheme.textMuted,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSub)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}