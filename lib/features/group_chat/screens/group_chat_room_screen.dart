import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
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
import '../../chat/widgets/failed_message_bubble.dart';
import '../../chat/services/pending_message_store.dart';
import '../../chat/services/draft_store.dart';
import '../../chat/providers/reaction_provider.dart';
import '../../polls/widgets/create_poll_sheet.dart';
import '../../reports/providers/report_provider.dart'; // ⭐ NEW
import '../../reports/widgets/report_dialog.dart';      // ⭐ NEW
import '../../voice_room/widgets/voice_room_banner.dart';
import '../models/group_room_model.dart';
import '../models/group_message_model.dart';
import '../providers/group_chat_provider.dart';
import '../widgets/group_chat_app_bar.dart';
import '../widgets/group_message_bubble.dart';
import '../widgets/group_reply_preview.dart';
import '../widgets/group_disabled_input.dart';
import '../widgets/group_empty_state.dart';
import '../widgets/system_message.dart';
import 'group_members_screen.dart';
import 'group_room_info_screen.dart';
import '../../location/widgets/location_share_start_sheet.dart';
import '../../schedule/widgets/schedule_create_sheet.dart';
import '../../call/widgets/call_return_bubble.dart';


class GroupChatRoomScreen extends ConsumerStatefulWidget {
  final GroupRoomModel room;
  const GroupChatRoomScreen({super.key, required this.room});

  @override
  ConsumerState<GroupChatRoomScreen> createState() =>
      _GroupChatRoomScreenState();
}

class _GroupChatRoomScreenState
    extends ConsumerState<GroupChatRoomScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  bool _sending = false;
  bool _disposed = false;
  bool _isMuted = false;

  bool _inputIsEmpty = true;

  bool _isPaginating = false;
  bool _noMoreMessages = false;

  bool _initialScrolled = false;

  GroupMessageModel? _replyTo;

  final Map<String, GlobalKey> _messageKeys = {};
  List<GroupMessageModel>? _lastMessages;
  List<_MessageGroup> _cachedGroups = [];

  List<GroupMessageModel> _sortedMessages = const [];

  List<PendingMessage> _failedMessages = [];
  final Set<String> _retryingIds = <String>{};

  final Map<String, _OptimisticMessage> _optimisticMessages = {};

  Timer? _draftSaveDebouncer;
  Timer? _markReadDebouncer;

  // ⭐ 실시간 인원수
  int _memberCount = 0;
  RealtimeChannel? _memberChannel;

  // ⭐ NEW: 슬라이드 인 애니메이션 대상 메시지 ID
  final Set<String> _animatingMessageIds = {};

  @override
  void initState() {
    super.initState();
    currentOpenGroupRoomId = widget.room.id;

    // ⭐ 멤버 카운트 초기화 + 구독
    _memberCount = widget.room.memberCount;
    _subscribeMemberChanges();
    _refreshMemberCount();

    _markAsRead();
    _loadMuteStatus();
    _loadFailedMessages();
    _loadDraft();

    _inputController.addListener(_onInputChanged);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _isNearBottom()) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _scrollToBottom();
        });
      }
    });

    _scrollController.addListener(_handleScroll);

    // ⭐ 보이스 룸 Edge Function 미리 깨우기
    _warmupVoiceRoomTokenFunction();
  }

  // ═══════════════════════════════════════════════════
  // ⭐ 실시간 멤버 카운트
  // ═══════════════════════════════════════════════════
  void _subscribeMemberChanges() {
    try {
      _memberChannel = Supabase.instance.client
          .channel('group_members_${widget.room.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'kyorangtalk_group_members',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: widget.room.id,
            ),
            callback: (_) {
              if (!_disposed && mounted) _refreshMemberCount();
            },
          )
          .subscribe();
    } catch (e) {
      print('멤버 채널 구독 실패: $e');
    }
  }

  Future<void> _refreshMemberCount() async {
    try {
      final result = await Supabase.instance.client
          .from('kyorangtalk_group_members')
          .select('user_id')
          .eq('room_id', widget.room.id);
      if (!_disposed && mounted) {
        setState(() => _memberCount = (result as List).length);
      }
    } catch (e) {
      print('멤버 카운트 새로고침 실패: $e');
    }
  }

  /// ⭐ 그룹 채팅방 진입 후 Edge Function 을 warmup 모드로 호출.
  Future<void> _warmupVoiceRoomTokenFunction() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (_disposed) return;

    try {
      final sw = Stopwatch()..start();
      final res = await Supabase.instance.client.functions.invoke(
        'agora_token_voice_room',
        body: const {'warmup': true},
      ).timeout(const Duration(seconds: 5));
      print('🔥 보이스 룸 함수 warmup 완료 (${sw.elapsedMilliseconds}ms) status=${res.status}');
    } catch (e) {
      print('🔥 보이스 룸 함수 warmup 실패: $e');
    }
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

    if (_memberChannel != null) {
      Supabase.instance.client.removeChannel(_memberChannel!);
    }

    _draftSaveDebouncer?.cancel();
    _markReadDebouncer?.cancel();
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
    } catch (e) {
      print('markAsRead 오류: $e');
    }
  }

  void _scheduleMarkAsRead() {
    _markReadDebouncer?.cancel();
    _markReadDebouncer = Timer(const Duration(seconds: 1), () {
      if (!_disposed && mounted) _markAsRead();
    });
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
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _forceInitialScroll() {
    if (_initialScrolled) return;
    _initialScrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController
          .jumpTo(_scrollController.position.maxScrollExtent);
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_disposed && mounted && _scrollController.hasClients) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_disposed && mounted && _scrollController.hasClients) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 300;
  }

  void _updateMessageCaches(List<GroupMessageModel> msgs) {
    final sorted = [...msgs]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _sortedMessages = sorted;
  }

  Future<void> _handleAttachment() async {
    final action = await showAttachmentMenu(context);
    if (!mounted || action == null) return;

    switch (action) {
      case 'gallery': await _pickAndSendImage(ImageSource.gallery); break;
      case 'camera':  await _pickAndSendImage(ImageSource.camera);  break;
      case 'voice':   await _recordVoice();                         break;
      case 'game':    await _sendGame();                            break;
      case 'poll':    await _sendPoll();                            break;
      case 'file':    await _sendFile();                            break;
      case 'location': await _shareLocation();                      break;
      case 'schedule': await _shareSchedule();                      break;
    }
  }

  Future<void> _shareSchedule() async {
    final event = await showScheduleCreateSheet(
      context,
      roomId:   widget.room.id,
      roomType: 'group',
    );
    if (event == null || !mounted) return;

    await sendGroupMessage(
      roomId:          widget.room.id,
      senderId:        _myId,
      content:         '일정을 잡고 있어요',
      scheduleEventId: event.id,
    );
  }


  Future<void> _shareLocation() async {
    final share = await showLocationShareStartSheet(
      context,
      roomId: widget.room.id,
      roomType: 'group',
    );
    if (share == null || !mounted) return;

    await sendGroupMessage(
      roomId: widget.room.id,
      senderId: _myId,
      content: '실시간 위치를 공유했어요',
      locationShareId: share.id,
    );
  }

  Future<void> _sendGame() async {
    if (!mounted) return;
    final gameData = await showGameSheet(context);
    if (gameData == null || !mounted) return;
    final previewText = _getGamePreviewText(gameData);
    try {
      await sendGroupMessage(
        roomId: widget.room.id,
        senderId: _myId,
        content: previewText,
        gameData: gameData,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) _showSnack('게임 전송 실패: $e');
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
        roomId: widget.room.id,
        senderId: _myId,
        content: '투표가 생성됐어요',
        pollId: pollId,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) _showSnack('투표 전송 실패: $e');
    }
  }

  Future<void> _sendFile() async {
    if (!mounted) return;
    final picked = await pickFile(context);
    if (picked == null || !mounted) return;
    setState(() => _sending = true);

    _showUploadDialog(picked.name);

    try {
      final fileUrl = await uploadFile(
        file: picked.file,
        fileName: picked.name,
        roomId: widget.room.id,
        roomType: 'group',
      );
      await sendGroupMessage(
        roomId: widget.room.id,
        senderId: _myId,
        content: '[파일]',
        fileUrl: fileUrl,
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
        _showSnack('파일 전송 실패: $e');
      }
    }
  }

  void _showUploadDialog(String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
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
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(fileName,
                  style: TextStyle(
                      color: AppTheme.textSub, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
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
        _showSnack('음성 전송 실패: $e');
      }
    }
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty) return;

    final reply = _replyTo;
    final localId = PendingMessageStore.generateLocalId();
    final now = DateTime.now();

    final optimistic = _OptimisticMessage(
      localId: localId,
      content: content,
      replyToId: reply?.id,
      replyToContent: reply?.content,
      createdAt: now,
    );

    _inputController.clear();
    DraftStore.clear(roomId: widget.room.id, isGroup: true);

    setState(() {
      _replyTo = null;
      _optimisticMessages[localId] = optimistic;
    });

    _scrollToBottom();

    try {
      await sendGroupMessage(
        roomId: widget.room.id,
        senderId: _myId,
        content: content,
        replyToId: reply?.id,
        replyToContent: reply?.content,
      );

      if (!_disposed && mounted) {
        setState(() => _optimisticMessages.remove(localId));
      }
    } catch (e) {
      if (_disposed) return;
      final failed = PendingMessage(
        id: localId,
        roomId: widget.room.id,
        isGroup: true,
        content: content,
        replyToId: reply?.id,
        replyToContent: reply?.content,
        createdAt: now,
        errorMessage: e.toString(),
      );
      await PendingMessageStore.upsert(failed);
      if (mounted) {
        setState(() {
          _optimisticMessages.remove(localId);
          _failedMessages = [..._failedMessages, failed];
        });
      }
    }
  }

  Future<void> _retryFailedMessage(PendingMessage msg) async {
    if (_retryingIds.contains(msg.id)) return;

    setState(() => _retryingIds.add(msg.id));

    try {
      await sendGroupMessage(
        roomId: msg.roomId,
        senderId: _myId,
        content: msg.content,
        replyToId: msg.replyToId,
        replyToContent: msg.replyToContent,
      );
      await PendingMessageStore.remove(msg.id);
      if (!_disposed && mounted) {
        setState(() {
          _failedMessages.removeWhere((m) => m.id == msg.id);
          _retryingIds.remove(msg.id);
        });
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
        _showSnack('재전송에 실패했어요. 잠시 후 다시 시도해주세요');
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
        final ext = picked.path.split('.').last;
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
          roomId: widget.room.id,
          senderId: _myId,
          content: '[이미지]',
          imageUrl: url,
        );
        if (!_disposed && mounted) {
          setState(() => _sending = false);
          _scrollToBottom(delayMs: 500);
        }
      } catch (e) {
        if (!_disposed && mounted) {
          _showSnack(e.toString().replaceAll('Exception: ', ''));
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
        roomId: widget.room.id,
        senderId: _myId,
        content:
            urls.length == 1 ? '[이미지]' : '[이미지 ${urls.length}장]',
        imageUrls: urls,
      );
      if (!_disposed && mounted) _scrollToBottom(delayMs: 500);
    } catch (e) {
      if (mounted) _showSnack('이미지 전송 실패: $e');
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    await Supabase.instance.client
        .from('kyorangtalk_messages')
        .update({
          'is_deleted': true,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          // ⭐ content는 덮어쓰지 않음 — 수신자가 24시간 내 복원 가능
        })
        .eq('id', messageId)
        .eq('sender_id', _myId);
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    _showSnack('메시지가 복사됐어요');
  }

  // ⭐ NEW: 메시지 신고 (자동 차단 포함)
  Future<void> _reportMessage(GroupMessageModel msg) async {
    await showReportMessageDialog(
      context: context,
      messageId: msg.id,
      senderId: msg.senderId,
      roomId: widget.room.id,
      messageContent: msg.content,
      senderNickname: msg.senderNickname ?? '알 수 없음',
    );
  }

  void _showSnack(String msg) {
    if (_disposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showMessageOptions(GroupMessageModel msg) {
    final isMe = msg.senderId == _myId;
    final isVoice = msg.audioUrl != null;
    final isImage = msg.isImageMessage;
    final isGame = msg.gameData != null;
    final isPoll = msg.pollId != null;
    final isFile = msg.fileUrl != null;
    final isSpecial = isVoice || isImage || isGame || isPoll || isFile;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
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
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() => _replyTo = msg);
                  _focusNode.requestFocus();
                },
              ),

            if (!isSpecial && !msg.isDeleted)
              ListTile(
                leading: Icon(Icons.copy_rounded,
                    color: AppTheme.textMain),
                title: Text('복사',
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _copyMessage(msg.content);
                },
              ),

            // ⭐ NEW: 신고 (남의 메시지만, 삭제 안 된 것만)
            if (!isMe && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: Color(0xFFFBBF24)),
                title: Text('신고',
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _reportMessage(msg);
                },
              ),

            if (isMe && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444)),
                title: const Text('삭제',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700)),
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
        _refreshMemberCount();
      }
    });
  }

  String _timeStr(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? '오전' : '오후';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$ampm $hour:$m';
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${dt.year}.${dt.month}.${dt.day}';
  }

  List<_MessageGroup> _getGroupedMessages(
      List<GroupMessageModel> messages) {
    if (_lastMessages != null &&
        _lastMessages!.length == messages.length &&
        identical(_lastMessages!.last, messages.last)) {
      return _cachedGroups;
    }
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
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
    final hasAdminAsync =
        ref.watch(hasRoomAdminProvider(widget.room.id));
    final hasAdmin = hasAdminAsync.value ?? true;

    // ⭐ NEW: 차단된 사용자 ID 목록 (실시간)
    final blockedIds =
        ref.watch(blockedUserIdsProvider).value ?? <String>{};

    ref.listen(groupMessagesProvider(widget.room.id), (prev, next) {
      if (_disposed) return;
      next.whenData((msgs) {
        if (_disposed) return;

        // ⭐ 차단된 사용자 메시지 필터링
        final filteredMsgs = msgs
            .where((m) => !blockedIds.contains(m.senderId))
            .toList();

        _updateMessageCaches(filteredMsgs);

        if (prev?.value == null) {
          _forceInitialScroll();
          return;
        }

        final prevFiltered = prev!.value!
            .where((m) => !blockedIds.contains(m.senderId))
            .toList();
        final prevIds = prevFiltered.map((m) => m.id).toSet();
        final newMessages =
            filteredMsgs.where((m) => !prevIds.contains(m.id)).toList();

        if (newMessages.isNotEmpty) {
          if (_optimisticMessages.isNotEmpty) {
            final myNewMessages =
                newMessages.where((m) => m.senderId == _myId).toList();
            if (myNewMessages.isNotEmpty) {
              setState(() {
                for (final newMsg in myNewMessages) {
                  final matchKey = _optimisticMessages.entries
                      .where((e) =>
                          e.value.content == newMsg.content &&
                          newMsg.createdAt
                                  .difference(e.value.createdAt)
                                  .inSeconds
                                  .abs() <
                              30)
                      .map((e) => e.key)
                      .firstOrNull;
                  if (matchKey != null) {
                    _optimisticMessages.remove(matchKey);
                  }
                }
              });
            }
          }

          // ⭐ NEW: 상대방이 보낸 새 메시지에 슬라이드 인 효과
          //   자신 메시지는 옵티미스틱으로 이미 표시되어 있어 제외
          //   system 메시지도 제외 (정적이라 자연스러움)
          final newOtherMessages = newMessages
              .where((m) => m.senderId != _myId && m.msgType != 'system')
              .toList();
          if (newOtherMessages.isNotEmpty) {
            setState(() {
              for (final m in newOtherMessages) {
                _animatingMessageIds.add(m.id);
              }
            });
            Future.delayed(const Duration(milliseconds: 800), () {
              if (!_disposed && mounted) {
                setState(() {
                  _animatingMessageIds
                      .removeAll(newOtherMessages.map((m) => m.id));
                });
              }
            });
          }

          final sortedNew = [...newMessages]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final latestNew = sortedNew.last;
          final allSorted = _sortedMessages;
          final isAtBottom = allSorted.isNotEmpty &&
              allSorted.last.id == latestNew.id;

          if (isAtBottom) {
            if (_isNearBottom() || latestNew.senderId == _myId) {
              _scrollToBottom(delayMs: 300);
            }
            _scheduleMarkAsRead();
          }

          final hasSystemMsg =
              newMessages.any((m) => m.msgType == 'system');
          if (hasSystemMsg) {
            _refreshMemberCount();
          }
        }
      });
    });

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      appBar: buildGroupChatAppBar(
        context: context,
        room: widget.room,
        isMuted: _isMuted,
        onTitleTap: _openRoomInfo,
        onMenuTap: _openRoomInfo,
        memberCount: _memberCount,
      ),

      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            VoiceRoomBanner(groupRoomId: widget.room.id),

            Expanded(
              child: msgsAsync.when(
                // ⭐ 카톡식: 로딩 스피너 대신 빈 채팅창
                loading: () => const SizedBox.expand(),
                error: (e, _) => Center(
                    child: Text('오류: $e',
                        style:
                            TextStyle(color: AppTheme.textSub))),
                data: (rawMessages) {
                  // 차단된 사용자 메시지 필터링
                  final messages = rawMessages
                      .where((m) => !blockedIds.contains(m.senderId))
                      .toList();
                  return _buildMessageList(messages);
                },
              ),
            ),

            CallReturnBubble(roomId: widget.room.id),

            if (_replyTo != null && hasAdmin)
              GroupReplyPreview(
                replyTo: _replyTo!,
                onCancel: () => setState(() => _replyTo = null),
              ),

            if (!hasAdmin)
              const GroupDisabledInput()
            else
              ChatInputBar(
                controller: _inputController,
                focusNode: _focusNode,
                enabled: true,
                sending: false,
                onAttachment: _handleAttachment,
                onSend: _send,
              ),
          ],
        ),
      ),
    );
  }

  // ⭐ NEW: 빈 채팅창 ↔ 메시지 리스트를 AnimatedSwitcher로 부드럽게 전환
  Widget _buildMessageList(List<GroupMessageModel> messages) {
    final isEmpty = messages.isEmpty &&
        _failedMessages.isEmpty &&
        _optimisticMessages.isEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: isEmpty
          ? KeyedSubtree(
              key: const ValueKey('empty_state'),
              child: GroupEmptyState(roomName: widget.room.name),
            )
          : KeyedSubtree(
              key: const ValueKey('message_list'),
              child: _buildListView(messages),
            ),
    );
  }

  Widget _buildListView(List<GroupMessageModel> messages) {
    final groups = _getGroupedMessages(messages);
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

    if (_optimisticMessages.isNotEmpty) {
      final sortedOptimistic =
          _optimisticMessages.values.toList()
            ..sort((a, b) =>
                a.createdAt.compareTo(b.createdAt));
      for (final o in sortedOptimistic) {
        items.add(_ListItem.optimistic(o));
      }
    }

    if (_failedMessages.isNotEmpty) {
      final sortedFailed = [..._failedMessages]
        ..sort((a, b) =>
            a.createdAt.compareTo(b.createdAt));
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
            padding:
                EdgeInsets.symmetric(vertical: 12),
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
            padding: const EdgeInsets.symmetric(
                vertical: 16),
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
          return _DateDivider(label: item.dateLabel!);
        }

        if (item.isOptimistic) {
          final o = item.optimistic!;
          return RepaintBoundary(
            key: ValueKey('opt_${o.localId}'),
            child: _OptimisticBubble(
              content: o.content,
              timeStr: _timeStr(o.createdAt),
            ),
          );
        }

        if (item.isFailedMessage) {
          final f = item.failedMessage!;
          return RepaintBoundary(
            key: ValueKey('failed_${f.id}'),
            child: FailedMessageBubble(
              message: f,
              timeStr: _timeStr(f.createdAt),
              isRetrying:
                  _retryingIds.contains(f.id),
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
            (prev?.senderId != msg.senderId ||
                isPrevSystem);
        final key = _getKeyFor(msg.id);

        final bubble = GestureDetector(
          key: key,
          onLongPress: () => _showMessageOptions(msg),
          child: GroupMessageBubble(
            msg: msg,
            roomId: widget.room.id,
            isMe: isMe,
            showSenderInfo: showSenderInfo,
            timeStr: _timeStr(msg.createdAt),
            onAvatarTap: isMe
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            UserProfileScreen(
                          userId: msg.senderId,
                          nickname:
                              msg.senderNickname ??
                                  '알 수 없음',
                          avatarUrl:
                              msg.senderAvatar,
                        ),
                      ),
                    );
                  },
          ),
        );

        // ⭐ NEW: 막 도착한 메시지에만 슬라이드 인 효과
        final shouldAnimate = _animatingMessageIds.contains(msg.id);

        return RepaintBoundary(
          key: ValueKey('msg_${msg.id}'),
          child: shouldAnimate ? _SlideInWrapper(child: bubble) : bubble,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════
// 날짜 구분선
// ═══════════════════════════════════════════════════
class _DateDivider extends StatelessWidget {
  final String label;

  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.border.withOpacity(0.6),
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Optimistic 메시지
// ═══════════════════════════════════════════════════
class _OptimisticMessage {
  final String localId;
  final String content;
  final String? replyToId;
  final String? replyToContent;
  final DateTime createdAt;

  _OptimisticMessage({
    required this.localId,
    required this.content,
    this.replyToId,
    this.replyToContent,
    required this.createdAt,
  });
}

class _OptimisticBubble extends StatelessWidget {
  final String content;
  final String timeStr;

  const _OptimisticBubble({
    required this.content,
    required this.timeStr,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 5, bottom: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 11,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(height: 2),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Opacity(
              opacity: 0.7,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.88),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
  final _OptimisticMessage? optimistic;
  final bool isLoadingIndicator;
  final bool isStartOfChatMarker;

  _ListItem.dateDivider(this.dateLabel)
      : message = null,
        prevMessage = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.message(this.message, this.prevMessage)
      : dateLabel = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.failedMessage(this.failedMessage)
      : dateLabel = null,
        message = null,
        prevMessage = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.optimistic(this.optimistic)
      : dateLabel = null,
        message = null,
        prevMessage = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.loadingIndicator()
      : dateLabel = null,
        message = null,
        prevMessage = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = true,
        isStartOfChatMarker = false;

  _ListItem.startOfChatMarker()
      : dateLabel = null,
        message = null,
        prevMessage = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = true;

  bool get isDivider =>
      dateLabel != null &&
      !isLoadingIndicator &&
      !isStartOfChatMarker;

  bool get isFailedMessage => failedMessage != null;
  bool get isOptimistic => optimistic != null;
}

// ═══════════════════════════════════════════════════
// ⭐ NEW: 새 메시지 슬라이드 인 애니메이션 wrapper
// 막 도착한 메시지가 살짝 아래에서 떠오르며 fade-in되는 효과
// ═══════════════════════════════════════════════════
class _SlideInWrapper extends StatefulWidget {
  final Widget child;
  const _SlideInWrapper({required this.child});

  @override
  State<_SlideInWrapper> createState() => _SlideInWrapperState();
}

class _SlideInWrapperState extends State<_SlideInWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _opacity = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}