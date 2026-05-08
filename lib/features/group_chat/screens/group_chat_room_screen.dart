import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../features/chat/screens/multi_image_viewer_screen.dart';
import '../../../features/profile/screens/user_profile_screen.dart';
import '../../../features/chat/services/audio_service.dart';
import '../../../features/chat/utils/file_helper.dart';
import '../../../features/chat/utils/multi_image_helper.dart';
import '../../../features/chat/widgets/voice_record_screen.dart';
import '../../chat/widgets/chat_input_bar.dart';
import '../../chat/widgets/game_select_sheet.dart';
import '../../chat/widgets/attachment_menu.dart';
import '../../chat/widgets/reaction_picker_bar.dart';
import '../../chat/widgets/summary_banner.dart';
import '../../chat/widgets/smart_reply_bar.dart';
import '../../chat/widgets/plan_card_widget.dart';
import '../../chat/widgets/failed_message_bubble.dart';
import '../../chat/services/plan_service.dart';
import '../../chat/services/pending_message_store.dart';
import '../../chat/services/draft_store.dart';
import '../../chat/providers/reaction_provider.dart';
import '../../polls/widgets/create_poll_sheet.dart';
import '../models/group_room_model.dart';
import '../models/group_message_model.dart';
import '../providers/group_chat_provider.dart';
import '../widgets/group_message_bubble.dart';
import '../widgets/system_message.dart';
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
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  bool _sending = false;
  bool _disposed = false;
  bool _isMuted = false;
  bool _summaryDismissed = false;

  String? _smartReplyDismissedFor;
  bool _inputIsEmpty = true;

  final Map<String, PlanModel> _detectedPlans = <String, PlanModel>{};
  final Set<String> _planExtractInProgress = <String>{};

  bool _isPaginating = false;
  bool _noMoreMessages = false;

  GroupMessageModel? _replyTo;

  final Map<String, GlobalKey> _messageKeys = {};
  List<GroupMessageModel>? _lastMessages;
  List<_MessageGroup> _cachedGroups = [];

  // ⭐ 실패한 메시지
  List<PendingMessage> _failedMessages = [];
  final Set<String> _retryingIds = <String>{};

  // ⭐ Draft 자동 저장
  Timer? _draftSaveDebouncer;

  @override
  void initState() {
    super.initState();
    currentOpenGroupRoomId = widget.room.id;
    _markAsRead();
    _loadMuteStatus();
    _loadFailedMessages();
    _loadDraft();

    _inputController.addListener(_onInputChanged);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _scrollToBottom();
        });
      }
    });

    _scrollController.addListener(_handleScroll);
  }

  void _onInputChanged() {
    final text = _inputController.text;
    final isEmpty = text.trim().isEmpty;
    if (isEmpty != _inputIsEmpty) {
      setState(() => _inputIsEmpty = isEmpty);
    }

    _draftSaveDebouncer?.cancel();
    _draftSaveDebouncer = Timer(const Duration(milliseconds: 500), () {
      DraftStore.save(
        roomId: widget.room.id,
        isGroup: true,
        text: text,
      );
    });
  }

  Future<void> _loadDraft() async {
    final draft = await DraftStore.load(
      roomId: widget.room.id,
      isGroup: true,
    );
    if (!_disposed && mounted && draft.isNotEmpty) {
      _inputController.text = draft;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: draft.length),
      );
      setState(() => _inputIsEmpty = draft.trim().isEmpty);
    }
  }

  Future<void> _loadFailedMessages() async {
    final messages = await PendingMessageStore.getForRoom(
      roomId: widget.room.id,
      isGroup: true,
    );
    if (!_disposed && mounted) {
      setState(() => _failedMessages = messages);
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position.pixels;
    if (pos < 200 && !_isPaginating && !_noMoreMessages) {
      _triggerPagination();
    }
  }

  Future<void> _triggerPagination() async {
    if (_isPaginating || _noMoreMessages) return;
    setState(() => _isPaginating = true);

    final beforeMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    final loaded = await loadOlderGroupMessages(widget.room.id);

    if (!_disposed && mounted) {
      setState(() {
        _isPaginating = false;
        if (!loaded) _noMoreMessages = true;
      });

      if (loaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_disposed || !mounted) return;
          if (!_scrollController.hasClients) return;
          final afterMaxExtent =
              _scrollController.position.maxScrollExtent;
          final diff = afterMaxExtent - beforeMaxExtent;
          if (diff > 0) {
            _scrollController.jumpTo(
              _scrollController.position.pixels + diff,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    currentOpenGroupRoomId = null;
    _draftSaveDebouncer?.cancel();
    DraftStore.save(
      roomId: widget.room.id,
      isGroup: true,
      text: _inputController.text,
    );
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.removeListener(_handleScroll);
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

  void _scrollToBottom({bool animate = true, int delayMs = 150}) {
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
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 300;
  }

  List<String> _getRecentMessagesForContext() {
    final msgs =
        ref.read(groupMessagesProvider(widget.room.id)).value ?? [];
    final recent = msgs.reversed
        .where((m) =>
            !m.isDeleted &&
            m.msgType != 'system' &&
            !m.isImageMessage &&
            m.audioUrl == null &&
            m.fileUrl == null &&
            m.gameData == null &&
            m.pollId == null &&
            m.content.trim().isNotEmpty)
        .take(5)
        .toList()
        .reversed
        .toList();

    return recent.map((m) {
      final speaker =
          m.senderId == _myId ? '나' : (m.senderNickname ?? '익명');
      return '$speaker: ${m.content}';
    }).toList();
  }

  Future<void> _tryExtractPlan(GroupMessageModel msg) async {
    if (_disposed) return;
    if (msg.isDeleted) return;
    if (msg.msgType == 'system') return;
    if (msg.isImageMessage ||
        msg.fileUrl != null ||
        msg.gameData != null ||
        msg.pollId != null) return;

    final text = msg.audioUrl != null
        ? (msg.audioTranscript ?? '')
        : msg.content;
    if (text.trim().length < 10) return;

    if (_planExtractInProgress.contains(msg.id)) return;
    if (_detectedPlans.containsKey(msg.id)) return;

    _planExtractInProgress.add(msg.id);

    try {
      final cached = await PlanService.fetchByMessageId(msg.id);
      if (cached != null) {
        if (!_disposed && mounted && !cached.isDismissed) {
          setState(() => _detectedPlans[msg.id] = cached);
        }
        return;
      }

      final senderName =
          msg.senderId == _myId ? '나' : (msg.senderNickname ?? '익명');
      final plan = await PlanService.extractFromMessage(
        roomId: widget.room.id,
        isGroup: true,
        messageId: msg.id,
        messageText: text,
        senderName: senderName,
        context: _getRecentMessagesForContext(),
      );

      if (plan != null && !_disposed && mounted) {
        setState(() => _detectedPlans[msg.id] = plan);
      }
    } finally {
      _planExtractInProgress.remove(msg.id);
    }
  }

  void _extractPlansForRecentMessages(List<GroupMessageModel> messages) {
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final recent =
        sorted.length > 30 ? sorted.sublist(sorted.length - 30) : sorted;

    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final candidates = recent.where((m) => m.createdAt.isAfter(cutoff));

    for (final msg in candidates) {
      _tryExtractPlan(msg);
    }
  }

  GroupMessageModel? _getSmartReplyTargetMessage() {
    if (!_inputIsEmpty) return null;

    final msgs =
        ref.read(groupMessagesProvider(widget.room.id)).value ?? [];
    if (msgs.isEmpty) return null;

    final sorted = [...msgs]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final last = sorted.last;

    if (last.senderId == _myId) return null;
    if (last.isDeleted) return null;
    if (last.msgType == 'system') return null;
    if (_smartReplyDismissedFor == last.id) return null;

    final diff = DateTime.now().difference(last.createdAt);
    if (diff.inMinutes >= 1) return null;

    final hasText = last.audioUrl != null
        ? (last.audioTranscript?.isNotEmpty ?? false)
        : (!last.isImageMessage &&
            last.fileUrl == null &&
            last.gameData == null &&
            last.pollId == null &&
            last.content.trim().isNotEmpty);
    if (!hasText) return null;

    return last;
  }

  String _getSmartReplyText(GroupMessageModel msg) {
    if (msg.audioUrl != null && msg.audioTranscript != null) {
      return msg.audioTranscript!;
    }
    return msg.content;
  }

  Future<void> _handleAttachment() async {
    final action = await showAttachmentMenu(context);
    if (!mounted || action == null) return;

    switch (action) {
      case 'gallery': await _pickAndSendImage(ImageSource.gallery); break;
      case 'camera':  await _pickAndSendImage(ImageSource.camera);  break;
      case 'voice':   await _recordVoice();                          break;
      case 'game':    await _sendGame();                             break;
      case 'poll':    await _sendPoll();                             break;
      case 'file':    await _sendFile();                             break;
    }
  }

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

  Future<void> _sendFile() async {
    if (!mounted) return;
    final picked = await pickFile(context);
    if (picked == null || !mounted) return;
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
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text('파일 업로드 중...',
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(picked.name,
                  style: TextStyle(color: AppTheme.textSub, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );

    try {
      final fileUrl = await uploadFile(
        file: picked.file,
        fileName: picked.name,
        roomId: widget.room.id,
        roomType: 'group',
      );
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

  // ═══════════════════════════════════════════════════
  // ⭐ 메시지 전송
  // ═══════════════════════════════════════════════════
  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _sending) return;

    final reply = _replyTo;

    final pending = PendingMessage(
      id: PendingMessageStore.generateLocalId(),
      roomId: widget.room.id,
      isGroup: true,
      content: content,
      replyToId: reply?.id,
      replyToContent: reply?.content,
      createdAt: DateTime.now(),
    );

    _inputController.clear();
    setState(() => _replyTo = null);

    DraftStore.clear(roomId: widget.room.id, isGroup: true);

    try {
      await sendGroupMessage(
        roomId:         widget.room.id,
        senderId:       _myId,
        content:        content,
        replyToId:      reply?.id,
        replyToContent: reply?.content,
      );
      if (!_disposed && mounted) {
        ref.invalidate(groupMessagesProvider(widget.room.id));
        ref.invalidate(groupRoomsProvider);
      }
      _scrollToBottom();
    } catch (e) {
      if (_disposed) return;
      final failed = pending.copyWith(errorMessage: e.toString());
      await PendingMessageStore.upsert(failed);
      if (mounted) {
        setState(() => _failedMessages = [..._failedMessages, failed]);
        _scrollToBottom();
      }
    }
  }

  Future<void> _retryFailedMessage(PendingMessage msg) async {
    if (_retryingIds.contains(msg.id)) return;

    setState(() => _retryingIds.add(msg.id));

    try {
      await sendGroupMessage(
        roomId:         msg.roomId,
        senderId:       _myId,
        content:        msg.content,
        replyToId:      msg.replyToId,
        replyToContent: msg.replyToContent,
      );
      await PendingMessageStore.remove(msg.id);
      if (!_disposed && mounted) {
        setState(() {
          _failedMessages.removeWhere((m) => m.id == msg.id);
          _retryingIds.remove(msg.id);
        });
        ref.invalidate(groupMessagesProvider(widget.room.id));
        ref.invalidate(groupRoomsProvider);
        _scrollToBottom();
      }
    } catch (e) {
      if (_disposed) return;
      final updated = msg.copyWith(
        retryCount: msg.retryCount + 1,
        errorMessage: e.toString(),
      );
      await PendingMessageStore.upsert(updated);
      if (mounted) {
        setState(() {
          final idx = _failedMessages.indexWhere((m) => m.id == msg.id);
          if (idx >= 0) _failedMessages[idx] = updated;
          _retryingIds.remove(msg.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('재전송에 실패했어요. 잠시 후 다시 시도해주세요'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _cancelFailedMessage(PendingMessage msg) async {
    await PendingMessageStore.remove(msg.id);
    if (!_disposed && mounted) {
      setState(() {
        _failedMessages.removeWhere((m) => m.id == msg.id);
        _retryingIds.remove(msg.id);
      });
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
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
        await sendGroupMessage(
          roomId:   widget.room.id,
          senderId: _myId,
          content:  '[이미지]',
          imageUrl: url,
        );
        if (!_disposed && mounted) {
          ref.invalidate(groupMessagesProvider(widget.room.id));
          ref.invalidate(groupRoomsProvider);
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
      return;
    }

    final picked = await pickMultipleImagesFromGallery();
    if (picked.isEmpty || !mounted) return;

    final result = await showMultiImagePreview(
      context: context,
      initialImages: picked,
    );
    if (result == null || result.isEmpty || !mounted) return;

    final urls = await uploadMultipleImagesWithProgress(
      context: context,
      files: result.files,
      roomId: widget.room.id,
      roomType: 'group',
      isOriginal: result.isOriginal,
    );
    if (urls == null || urls.isEmpty || !mounted) return;

    try {
      await sendGroupMessage(
        roomId:    widget.room.id,
        senderId:  _myId,
        content:   urls.length == 1 ? '[이미지]' : '[이미지 ${urls.length}장]',
        imageUrls: urls,
      );
      if (!_disposed && mounted) {
        ref.invalidate(groupMessagesProvider(widget.room.id));
        ref.invalidate(groupRoomsProvider);
        _scrollToBottom(delayMs: 500);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 전송 실패: $e')),
        );
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
    final isImage = msg.isImageMessage;
    final isGame  = msg.gameData != null;
    final isPoll  = msg.pollId != null;
    final isFile  = msg.fileUrl != null;
    final isSpecial = isVoice || isImage || isGame || isPoll || isFile;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
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

            if (!msg.isDeleted)
              ReactionPickerBar(
                onSelected: (emoji) {
                  Navigator.pop(sheetCtx);
                  toggleReaction(
                    messageId: msg.id,
                    roomId: widget.room.id,
                    emoji: emoji,
                    isGroup: true,
                  );
                },
              ),

            if (!msg.isDeleted)
              ListTile(
                leading: Icon(Icons.reply_rounded,
                    color: AppTheme.textMain),
                title: Text('답장',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () {
                  Navigator.pop(sheetCtx);
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
                  Navigator.pop(sheetCtx);
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
                  Navigator.pop(sheetCtx);
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
    final msgsAsync = ref.watch(groupMessagesProvider(widget.room.id));
    final hasAdminAsync = ref.watch(hasRoomAdminProvider(widget.room.id));
    final hasAdmin = hasAdminAsync.value ?? true;

    ref.listen(groupMessagesProvider(widget.room.id), (prev, next) {
      if (_disposed) return;
      next.whenData((msgs) {
        if (_disposed) return;
        if (prev?.value == null) {
          _extractPlansForRecentMessages(msgs);
          return;
        }
        final prevIds = prev!.value!.map((m) => m.id).toSet();
        final newMessages =
            msgs.where((m) => !prevIds.contains(m.id)).toList();

        if (newMessages.isNotEmpty) {
          final sortedNew = [...newMessages]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final latestNew = sortedNew.last;
          final allSorted = [...msgs]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final isAtBottom = allSorted.last.id == latestNew.id;

          if (isAtBottom) {
            if (_isNearBottom() || latestNew.senderId == _myId) {
              _scrollToBottom(delayMs: 300);
            }
            _markAsRead();
          }

          for (final msg in newMessages) {
            _tryExtractPlan(msg);
          }
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              color: AppTheme.textSub, size: 14),
                        ],
                      ],
                    ),
                    Text('${widget.room.memberCount}명',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textSub)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.menu, color: AppTheme.textSub),
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
            if (!_summaryDismissed)
              SummaryBanner(
                roomId: widget.room.id,
                isGroup: true,
                unreadCount: widget.room.unreadCount,
                onDismiss: () =>
                    setState(() => _summaryDismissed = true),
              ),

            Expanded(
              child: msgsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary)),
                error: (e, _) => Center(
                    child: Text('오류: $e',
                        style: TextStyle(color: AppTheme.textSub))),
                data: (messages) {
                  if (messages.isEmpty && _failedMessages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('💬', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 12),
                          Text('${widget.room.name}에서 대화를 시작해보세요!',
                              style: TextStyle(
                                  color: AppTheme.textSub, fontSize: 13)),
                        ],
                      ),
                    );
                  }

                  final groups = _getGroupedMessages(messages);

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_isPaginating) {
                      _scrollToBottom(animate: false);
                    }
                  });

                  final items = <_ListItem>[];

                  if (_isPaginating) {
                    items.add(_ListItem.loadingIndicator());
                  } else if (_noMoreMessages) {
                    items.add(_ListItem.startOfChatMarker());
                  }

                  for (final group in groups) {
                    items.add(_ListItem.dateDivider(group.label));
                    for (int i = 0; i < group.items.length; i++) {
                      final msg = group.items[i];
                      final prev = i > 0 ? group.items[i - 1] : null;
                      items.add(_ListItem.message(msg, prev));
                    }
                  }

                  if (_failedMessages.isNotEmpty) {
                    final sortedFailed = [..._failedMessages]
                      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                    for (final f in sortedFailed) {
                      items.add(_ListItem.failedMessage(f));
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

                      if (item.isLoadingIndicator) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        );
                      }

                      if (item.isStartOfChatMarker) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              '대화의 시작이에요',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      }

                      if (item.isDivider) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            Expanded(child: Divider(color: AppTheme.border)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(item.dateLabel!,
                                  style: TextStyle(
                                      color: AppTheme.textMuted, fontSize: 11)),
                            ),
                            Expanded(child: Divider(color: AppTheme.border)),
                          ]),
                        );
                      }

                      if (item.isFailedMessage) {
                        final f = item.failedMessage!;
                        return RepaintBoundary(
                          key: ValueKey('failed_${f.id}'),
                          child: FailedMessageBubble(
                            message: f,
                            timeStr: _timeStr(f.createdAt),
                            isRetrying: _retryingIds.contains(f.id),
                            onRetry: () => _retryFailedMessage(f),
                            onCancel: () => _cancelFailedMessage(f),
                          ),
                        );
                      }

                      final msg = item.message!;

                      if (msg.msgType == 'system') {
                        return SystemMessage(content: msg.content);
                      }

                      final prev = item.prevMessage;
                      final isMe = msg.senderId == _myId;
                      final isPrevSystem = prev?.msgType == 'system';
                      final showSenderInfo = !isMe &&
                          (prev?.senderId != msg.senderId || isPrevSystem);
                      final key = _getKeyFor(msg.id);

                      final detectedPlan = _detectedPlans[msg.id];

                      return Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            key: key,
                            onLongPress: () => _showMessageOptions(msg),
                            child: GroupMessageBubble(
                              msg:            msg,
                              roomId:         widget.room.id,
                              isMe:           isMe,
                              showSenderInfo: showSenderInfo,
                              timeStr:        _timeStr(msg.createdAt),
                              onAvatarTap: isMe
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => UserProfileScreen(
                                            userId: msg.senderId,
                                            nickname:
                                                msg.senderNickname ?? '알 수 없음',
                                            avatarUrl: msg.senderAvatar,
                                          ),
                                        ),
                                      );
                                    },
                            ),
                          ),
                          if (detectedPlan != null)
                            Padding(
                              padding: EdgeInsets.only(
                                left: isMe ? 40 : 36,
                                right: isMe ? 4 : 40,
                                top: 4,
                                bottom: 4,
                              ),
                              child: PlanCard(
                                plan: detectedPlan,
                                onDismissed: () {
                                  if (!_disposed && mounted) {
                                    setState(() =>
                                        _detectedPlans.remove(msg.id));
                                  }
                                },
                                onUpdated: (updated) {
                                  if (!_disposed && mounted) {
                                    setState(() =>
                                        _detectedPlans[msg.id] = updated);
                                  }
                                },
                              ),
                            ),
                        ],
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
                      bottom: BorderSide(color: AppTheme.border)),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                fontSize: 12, color: AppTheme.textSub),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: AppTheme.textSub, size: 18),
                      onPressed: () => setState(() => _replyTo = null),
                    ),
                  ],
                ),
              ),

            if (!hasAdmin) _buildDisabledInput() else _buildActiveInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildDisabledInput() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
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
                            fontSize: 11, color: AppTheme.textSub),
                      ),
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

  Widget _buildActiveInput() {
    final smartReplyTarget = _getSmartReplyTargetMessage();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (smartReplyTarget != null)
          SmartReplyBar(
            key: ValueKey('smart_reply_${smartReplyTarget.id}'),
            roomId: widget.room.id,
            isGroup: true,
            lastMessageId: smartReplyTarget.id,
            lastMessageText: _getSmartReplyText(smartReplyTarget),
            senderName: smartReplyTarget.senderNickname ?? '익명',
            contextMessages: _getRecentMessagesForContext(),
            onSelected: (text) {
              _inputController.text = text;
              _inputController.selection = TextSelection.fromPosition(
                TextPosition(offset: text.length),
              );
              _focusNode.requestFocus();
              setState(() =>
                  _smartReplyDismissedFor = smartReplyTarget.id);
            },
            onDismiss: () {
              setState(() =>
                  _smartReplyDismissedFor = smartReplyTarget.id);
            },
          ),
        ChatInputBar(
          controller: _inputController,
          focusNode: _focusNode,
          enabled: true,
          sending: _sending,
          onAttachment: _handleAttachment,
          onSend: _send,
        ),
      ],
    );
  }
}

class _MessageGroup {
  final String label;
  final List<GroupMessageModel> items;
  _MessageGroup(this.label, this.items);
}

class _ListItem {
  final String? dateLabel;
  final GroupMessageModel? message;
  final GroupMessageModel? prevMessage;
  final PendingMessage? failedMessage;
  final bool isLoadingIndicator;
  final bool isStartOfChatMarker;

  _ListItem.dateDivider(this.dateLabel)
      : message = null,
        prevMessage = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.message(this.message, this.prevMessage)
      : dateLabel = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.failedMessage(this.failedMessage)
      : dateLabel = null,
        message = null,
        prevMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.loadingIndicator()
      : dateLabel = null,
        message = null,
        prevMessage = null,
        failedMessage = null,
        isLoadingIndicator = true,
        isStartOfChatMarker = false;

  _ListItem.startOfChatMarker()
      : dateLabel = null,
        message = null,
        prevMessage = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = true;

  bool get isDivider =>
      dateLabel != null &&
      !isLoadingIndicator &&
      !isStartOfChatMarker;

  bool get isFailedMessage => failedMessage != null;
}