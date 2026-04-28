import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../features/chat/screens/image_viewer_screen.dart';
import '../../../features/profile/screens/user_profile_screen.dart';
import '../../../features/chat/services/audio_service.dart';
import '../../../features/chat/utils/file_helper.dart';
import '../../../features/chat/widgets/voice_record_screen.dart';
import '../../../features/chat/widgets/voice_message_bubble.dart';
import '../../chat/widgets/game_select_sheet.dart';
// ✨ 공통 위젯 import
import '../../chat/widgets/attachment_menu.dart';
import '../../chat/widgets/game_bubble.dart';
import '../../chat/widgets/file_bubble.dart';
// ✨ 투표 import
import '../../polls/widgets/create_poll_sheet.dart';
import '../../polls/widgets/poll_bubble.dart';
import '../models/group_room_model.dart';
import '../models/group_message_model.dart';
import '../providers/group_chat_provider.dart';
import 'group_members_screen.dart';
import 'group_room_info_screen.dart';

class GroupChatRoomScreen extends ConsumerStatefulWidget {
  final GroupRoomModel room;
  const GroupChatRoomScreen({super.key, required this.room});

  @override
  ConsumerState<GroupChatRoomScreen> createState() =>
      _GroupChatRoomScreenState();
}

class _GroupChatRoomScreenState
    extends ConsumerState<GroupChatRoomScreen> {
  final _inputController  = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _myId =
      Supabase.instance.client.auth.currentUser!.id;
  bool _sending = false;
  bool _disposed = false;
  bool _isMuted = false;

  GroupMessageModel? _replyTo;

  final Map<String, GlobalKey> _messageKeys = {};
  List<GroupMessageModel>? _lastMessages;
  List<_MessageGroup> _cachedGroups = [];

  @override
  void initState() {
    super.initState();
    currentOpenGroupRoomId = widget.room.id;
    _markAsRead();
    _loadMuteStatus();
    
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _scrollToBottom();
        });
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    currentOpenGroupRoomId = null;
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMuteStatus() async {
    final muted = await NotificationService.isMuted(
        groupRoomId: widget.room.id);
    if (!_disposed && mounted) {
      setState(() => _isMuted = muted);
    }
  }

  Future<void> _markAsRead() async {
    try {
      await markGroupRoomRead(widget.room.id);
      if (!_disposed && mounted) {
        ref.invalidate(groupRoomsProvider);
      }
    } catch (e) {
      print('markAsRead 오류: $e');
    }
  }

  void _scrollToBottom(
      {bool animate = true, int delayMs = 150}) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (_disposed || !mounted) return;
      if (!_scrollController.hasClients) return;
      if (animate) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent);
      }
    });
  }

  // ═══════════════════════════════════════════════════
  // 📎 첨부 메뉴 (공통 함수 사용)
  // ═══════════════════════════════════════════════════
  Future<void> _handleAttachment() async {
    final action = await showAttachmentMenu(context);
    if (!mounted || action == null) return;

    switch (action) {
      case 'gallery':
        await _pickAndSendImage(ImageSource.gallery);
        break;
      case 'camera':
        await _pickAndSendImage(ImageSource.camera);
        break;
      case 'voice':
        await _recordVoice();
        break;
      case 'game':
        await _sendGame();
        break;
      case 'poll':
        await _sendPoll();
        break;
      case 'file':
        await _sendFile();
        break;
    }
  }

  // ═══════════════════════════════════════════════════
  // 🎮 게임 전송
  // ═══════════════════════════════════════════════════
  Future<void> _sendGame() async {
    if (!mounted) return;

    final gameData = await showGameSheet(context);
    if (gameData == null || !mounted) return;

    final previewText = _getGamePreviewText(gameData);

    try {
      await sendGroupMessage(
        roomId:   widget.room.id,
        senderId: _myId,
        content:  previewText,
        gameData: gameData,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('게임 전송 실패: $e')),
        );
      }
    }
  }

  String _getGamePreviewText(Map<String, dynamic> gameData) {
    final type = gameData['type'] as String?;
    switch (type) {
      case 'dice':     return '🎲 주사위';
      case 'coin':     return '🪙 동전';
      case 'rps':      return '✂️ 가위바위보';
      case 'roulette': return '🎡 룰렛';
      default:         return '🎮 게임';
    }
  }

  // ═══════════════════════════════════════════════════
  // 📊 투표 전송
  // ═══════════════════════════════════════════════════
  Future<void> _sendPoll() async {
    if (!mounted) return;

    final pollId = await showCreatePollDialog(
      context,
      roomId: widget.room.id,
      roomType: 'group',
    );

    if (pollId == null || !mounted) return;

    try {
      await sendGroupMessage(
        roomId:   widget.room.id,
        senderId: _myId,
        content:  '투표가 생성됐어요',
        pollId:   pollId,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('투표 전송 실패: $e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════
  // 📎 파일 전송 ⭐ NEW
  // ═══════════════════════════════════════════════════
  Future<void> _sendFile() async {
    if (!mounted) return;

    // 1) 파일 선택
    final picked = await pickFile(context);
    if (picked == null || !mounted) return;

    // 2) 업로드 로딩
    setState(() => _sending = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '파일 업로드 중...',
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                picked.name,
                style: TextStyle(
                  color: AppTheme.textSub,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // 3) 파일 업로드
      final fileUrl = await uploadFile(
        file: picked.file,
        fileName: picked.name,
        roomId: widget.room.id,
        roomType: 'group',
      );

      // 4) 메시지 전송
      await sendGroupMessage(
        roomId:   widget.room.id,
        senderId: _myId,
        content:  '[파일]',
        fileUrl:  fileUrl,
        fileName: picked.name,
        fileSize: picked.size,
        fileType: picked.extension,
      );

      if (mounted) {
        Navigator.pop(context);
        setState(() => _sending = false);
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 전송 실패: $e')),
        );
      }
    }
  }

  Future<void> _recordVoice() async {
    final result = await showVoiceRecordSheet(context);
    if (result == null) return;

    if (!_disposed && mounted) setState(() => _sending = true);

    try {
      final audioUrl = await uploadAudioFile(
        localPath: result.path,
        roomId: widget.room.id,
      );

      sendGroupMessage(
        roomId: widget.room.id,
        senderId: _myId,
        content: '[음성 메시지]',
        audioUrl: audioUrl,
        audioDuration: result.duration,
      );

      if (!_disposed && mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 전송 실패: $e')),
        );
      }
    }
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _sending) return;

    _inputController.clear();
    final reply = _replyTo;
    setState(() => _replyTo = null);

    sendGroupMessage(
      roomId:         widget.room.id,
      senderId:       _myId,
      content:        content,
      replyToId:      reply?.id,
      replyToContent: reply?.content,
    ).catchError((e) {
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    });

    _scrollToBottom();
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _sending = true);

    try {
      final file = File(picked.path);
      final ext  = picked.path.split('.').last;
      final path =
          'group/${widget.room.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from('kyorangtalk')
          .upload(path, file,
              fileOptions: const FileOptions(upsert: true));

      final url = Supabase.instance.client.storage
          .from('kyorangtalk')
          .getPublicUrl(path);

      sendGroupMessage(
        roomId:   widget.room.id,
        senderId: _myId,
        content:  '[이미지]',
        imageUrl: url,
      );

      if (!_disposed && mounted) {
        setState(() => _sending = false);
        _scrollToBottom(delayMs: 500);
      }
    } catch (e) {
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    await Supabase.instance.client
        .from('kyorangtalk_group_messages')
        .update({'is_deleted': true, 'content': '삭제된 메시지예요'})
        .eq('id', messageId)
        .eq('sender_id', _myId);
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('메시지가 복사됐어요'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showMessageOptions(GroupMessageModel msg) {
    final isMe = msg.senderId == _myId;
    final isVoice = msg.audioUrl != null;
    final isImage = msg.imageUrl != null;
    final isGame  = msg.gameData != null;
    final isPoll  = msg.pollId != null;
    final isFile  = msg.fileUrl != null;  // ⭐ 파일 체크
    final isSpecial = isVoice || isImage || isGame || isPoll || isFile;
    
    showModalBottomSheet(
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
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Icon(Icons.reply_rounded,
                  color: AppTheme.textMain),
              title: Text('답장',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyTo = msg);
                _focusNode.requestFocus();
              },
            ),
            if (!isSpecial && !msg.isDeleted)
              ListTile(
                leading: Icon(Icons.copy_outlined,
                    color: AppTheme.textMain),
                title: Text('복사',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () {
                  Navigator.pop(context);
                  _copyMessage(msg.content);
                },
              ),
            if (isMe && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFEF4444)),
                title: const Text('삭제',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(msg.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openRoomInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupRoomInfoScreen(room: widget.room),
      ),
    ).then((_) {
      if (!_disposed && mounted) {
        _loadMuteStatus();
      }
    });
  }

  String _timeStr(DateTime dt) {
    final h    = dt.hour;
    final m    = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? '오전' : '오후';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$ampm $hour:$m';
  }

  String _dateLabel(DateTime dt) {
    final now  = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${dt.year}.${dt.month}.${dt.day}';
  }

  List<_MessageGroup> _getGroupedMessages(List<GroupMessageModel> messages) {
    if (_lastMessages != null &&
        _lastMessages!.length == messages.length &&
        identical(_lastMessages!.last, messages.last)) {
      return _cachedGroups;
    }

    final sorted = [...messages]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final groups = <_MessageGroup>[];
    String? currentLabel;
    List<GroupMessageModel> currentItems = [];

    for (final msg in sorted) {
      final label = _dateLabel(msg.createdAt);
      if (label != currentLabel) {
        if (currentItems.isNotEmpty) {
          groups.add(_MessageGroup(currentLabel!, currentItems));
        }
        currentLabel = label;
        currentItems = [msg];
      } else {
        currentItems.add(msg);
      }
    }
    if (currentItems.isNotEmpty) {
      groups.add(_MessageGroup(currentLabel!, currentItems));
    }

    _lastMessages = messages;
    _cachedGroups = groups;
    return groups;
  }

  GlobalKey _getKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    final msgsAsync =
        ref.watch(groupMessagesProvider(widget.room.id));
    
    final hasAdminAsync = ref.watch(hasRoomAdminProvider(widget.room.id));
    final hasAdmin = hasAdminAsync.value ?? true;

    ref.listen(groupMessagesProvider(widget.room.id),
        (prev, next) {
      if (_disposed) return;
      next.whenData((msgs) {
        if (_disposed) return;
        if (prev?.value?.length != msgs.length) {
          _scrollToBottom(delayMs: 300);
          _markAsRead();
        }
      });
    });

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _openRoomInfo,
          child: Row(
            children: [
              AvatarWidget(
                  url:  widget.room.avatarUrl,
                  name: widget.room.name,
                  size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(widget.room.name,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textMain),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (_isMuted) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.notifications_off,
                              color: AppTheme.textSub,
                              size: 14),
                        ],
                      ],
                    ),
                    Text('${widget.room.memberCount}명',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSub)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.menu,
                color: AppTheme.textSub),
            onPressed: _openRoomInfo,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),

      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: msgsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary)),
                error: (e, _) => Center(
                    child: Text('오류: $e',
                        style: TextStyle(
                            color: AppTheme.textSub))),
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Text('💬',
                              style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 12),
                          Text(
                              '${widget.room.name}에서 대화를 시작해보세요!',
                              style: TextStyle(
                                  color: AppTheme.textSub,
                                  fontSize: 13)),
                        ],
                      ),
                    );
                  }

                  final groups = _getGroupedMessages(messages);

                  WidgetsBinding.instance
                      .addPostFrameCallback((_) =>
                          _scrollToBottom(animate: false));

                  final items = <_ListItem>[];
                  for (final group in groups) {
                    items.add(_ListItem.dateDivider(group.label));
                    for (int i = 0; i < group.items.length; i++) {
                      final msg = group.items[i];
                      final prev = i > 0 ? group.items[i - 1] : null;
                      items.add(_ListItem.message(msg, prev));
                    }
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: items.length,
                    cacheExtent: 1000,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemBuilder: (ctx, index) {
                      final item = items[index];
                      
                      if (item.isDivider) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            Expanded(child: Divider(color: AppTheme.border)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(item.dateLabel!,
                                  style: TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 11)),
                            ),
                            Expanded(child: Divider(color: AppTheme.border)),
                          ]),
                        );
                      }
                      
                      final msg = item.message!;
                      
                      if (msg.msgType == 'system') {
                        return _SystemMessage(content: msg.content);
                      }
                      
                      final prev = item.prevMessage;
                      final isMe = msg.senderId == _myId;
                      final isPrevSystem = prev?.msgType == 'system';
                      final showSenderInfo = !isMe &&
                          (prev?.senderId != msg.senderId || isPrevSystem);
                      final key = _getKeyFor(msg.id);

                      return GestureDetector(
                        key: key,
                        onLongPress: () =>
                            _showMessageOptions(msg),
                        child: _GroupMessageBubble(
                          msg:            msg,
                          isMe:           isMe,
                          showSenderInfo: showSenderInfo,
                          timeStr:        _timeStr(msg.createdAt),
                          onImageTap: (url) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ImageViewerScreen(
                                  imageUrl:   url,
                                  senderName: isMe
                                      ? '나'
                                      : (msg.senderNickname ??
                                          '알 수 없음'),
                                  time: _timeStr(
                                      msg.createdAt),
                                ),
                              ),
                            );
                          },
                          onAvatarTap: isMe
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          UserProfileScreen(
                                        userId: msg.senderId,
                                        nickname: msg
                                                .senderNickname ??
                                            '알 수 없음',
                                        avatarUrl:
                                            msg.senderAvatar,
                                      ),
                                    ),
                                  );
                                },
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            if (_replyTo != null && hasAdmin)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  border: Border(
                      top: BorderSide(color: AppTheme.border),
                      bottom: BorderSide(
                          color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3, height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            _replyTo!.senderNickname ?? '알 수 없음',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _replyTo!.content,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSub),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: AppTheme.textSub, size: 18),
                      onPressed: () =>
                          setState(() => _replyTo = null),
                    ),
                  ],
                ),
              ),

            SafeArea(
              top: false,
              child: !hasAdmin
                  ? _buildDisabledInput()
                  : _buildActiveInput(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisabledInput() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: AppTheme.border)),
        color: AppTheme.bgCard,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_outline,
                    color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '방장이 나가서 더 이상 대화할 수 없어요',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '이전 대화 내용은 계속 볼 수 있어요',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSub),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveInput() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: AppTheme.border)),
        color: AppTheme.bg,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: _sending ? null : _handleAttachment,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(Icons.add,
                  color: AppTheme.textSub, size: 24),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                maxLines: 4, minLines: 1,
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '메시지 보내기...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _sending
                    ? AppTheme.border
                    : AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 헬퍼 클래스들
// ═══════════════════════════════════════════════
class _MessageGroup {
  final String label;
  final List<GroupMessageModel> items;
  _MessageGroup(this.label, this.items);
}

class _ListItem {
  final String? dateLabel;
  final GroupMessageModel? message;
  final GroupMessageModel? prevMessage;
  
  _ListItem.dateDivider(this.dateLabel) 
      : message = null, prevMessage = null;
  _ListItem.message(this.message, this.prevMessage) : dateLabel = null;
  
  bool get isDivider => dateLabel != null;
}

class _SystemMessage extends StatelessWidget {
  final String content;
  const _SystemMessage({required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.bgCard.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          content,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 그룹 메시지 버블 (깔끔해짐!)
// ═══════════════════════════════════════════════
class _GroupMessageBubble extends StatelessWidget {
  final GroupMessageModel msg;
  final bool isMe;
  final bool showSenderInfo;
  final String timeStr;
  final void Function(String url) onImageTap;
  final VoidCallback? onAvatarTap;

  const _GroupMessageBubble({
    required this.msg,
    required this.isMe,
    required this.showSenderInfo,
    required this.timeStr,
    required this.onImageTap,
    this.onAvatarTap,
  });

  Widget _buildContent(BuildContext context) {
    // ⭐ 투표 메시지 (가장 먼저!)
    if (msg.pollId != null && !msg.isDeleted) {
      return PollBubble(
        pollId: msg.pollId!,
        isMe: isMe,
      );
    }

    // ⭐ 📎 파일 메시지
    if (msg.fileUrl != null && !msg.isDeleted) {
      return FileBubble(
        fileUrl: msg.fileUrl!,
        fileName: msg.fileName ?? '파일',
        fileSize: msg.fileSize,
        fileType: msg.fileType,
        isMe: isMe,
      );
    }

    // ⭐ 🎮 게임 메시지 (공통 위젯 사용!)
    if (msg.gameData != null && !msg.isDeleted) {
      return GameBubble(
        gameData: msg.gameData!,
        isMe: isMe,
        content: msg.content,
      );
    }

    if (msg.audioUrl != null && !msg.isDeleted) {
      return VoiceMessageBubble(
        messageId: msg.id,
        audioUrl: msg.audioUrl!,
        duration: msg.audioDuration ?? 0,
        isMe: isMe,
      );
    }
    
    if (msg.isDeleted) {
      return Container(
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : AppTheme.border,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          '삭제된 메시지예요',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 14,
            height: 1.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    if (msg.imageUrl != null) {
      return Container(
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : AppTheme.border,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: GestureDetector(
          onTap: () => onImageTap(msg.imageUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            child: Stack(
              children: [
                Image.network(
                  msg.imageUrl!,
                  width: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 200,
                      height: 150,
                      color: AppTheme.border,
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.primary,
                              strokeWidth: 2)),
                    );
                  },
                ),
                Positioned(
                  bottom: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.zoom_in,
                        color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: isMe ? AppTheme.primary : AppTheme.border,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        msg.content,
        style: TextStyle(
          color: AppTheme.textMain,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe && showSenderInfo)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 2),
                child: Text(
                  msg.senderNickname ?? '알 수 없음',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSub,
                      fontWeight: FontWeight.w600),
                ),
              ),

            if (msg.replyToContent != null)
              Padding(
                padding: EdgeInsets.only(
                    left: isMe ? 0 : 36, bottom: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 2, height: 28,
                        color: AppTheme.primary,
                        margin: const EdgeInsets.only(right: 8),
                      ),
                      Flexible(
                        child: Text(
                          msg.replyToContent!,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSub),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  SizedBox(
                    width: 30,
                    child: showSenderInfo
                        ? GestureDetector(
                            onTap: onAvatarTap,
                            child: AvatarWidget(
                                url:  msg.senderAvatar,
                                name: msg.senderNickname,
                                size: 28),
                          )
                        : null,
                  ),
                if (!isMe) const SizedBox(width: 6),

                if (isMe) ...[
                  Text(timeStr,
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted)),
                  const SizedBox(width: 4),
                ],

                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.of(context).size.width *
                              0.7,
                    ),
                    child: _buildContent(context),
                  ),
                ),

                if (!isMe) ...[
                  const SizedBox(width: 4),
                  Text(timeStr,
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}