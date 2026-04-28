import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/skeleton_widget.dart';
import '../../friends/screens/friends_screen.dart';
import '../../reports/widgets/report_dialog.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import 'image_viewer_screen.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../services/audio_service.dart';
import '../utils/file_helper.dart';
import '../widgets/voice_record_screen.dart';
import '../widgets/attachment_menu.dart';
import '../widgets/game_select_sheet.dart';
// ✨ 분리된 위젯들
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_blocked_banner.dart';
import '../widgets/chat_app_bar.dart';
import '../widgets/chat_room_sheets.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_pinned_reply.dart';
// ✨ 투표
import '../../polls/widgets/create_poll_sheet.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  final ChatRoomModel room;
  const ChatRoomScreen({super.key, required this.room});

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _myId = Supabase.instance.client.auth.currentUser!.id;

  bool _sending = false;
  bool _searchMode = false;
  String _searchQuery = '';
  int _searchIndex = 0;
  List<int> _searchResults = [];
  MessageModel? _replyTo;
  bool _initialScrolled = false;
  String? _pinnedMessage;
  bool _isMuted = false;
  bool _disposed = false;
  
  // 🔒 스크롤 잠금 (투표 등 외부 요인으로 스크롤 안 변하게)
  double? _lockedScrollPos;
  bool _scrollLocked = false;

  bool? _isBlocked;
  bool? _isBlockedByPartner;
  String? _friendStatus;
  bool _friendRequestSending = false;

  RealtimeChannel? _blockChannel;

  final Map<String, GlobalKey> _messageKeys = {};
  List<MessageModel>? _lastMessages;
  List<MessageGroup> _cachedGroups = [];

  bool get _isStatusLoaded =>
      _isBlocked != null &&
      _isBlockedByPartner != null &&
      _friendStatus != null;

  @override
  void initState() {
    super.initState();
    currentOpenRoomId = widget.room.roomId;
    _pinnedMessage = widget.room.pinnedMessage;
    _markAllRead();
    _loadMuteStatus();
    _loadAllStatus();
    _listenBlockChanges();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _isNearBottom()) {
        Future.delayed(const Duration(milliseconds: 300), _animateToBottom);
      }
    });

    // 사용자 스크롤 감지 → 위로 올리면 잠금!
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      final pos = _scrollController.position.pixels;
      final maxPos = _scrollController.position.maxScrollExtent;
      final fromBottom = maxPos - pos;

      // 하단에서 100px 이상 떨어져 있으면 → 잠금!
      if (fromBottom > 100) {
        _lockedScrollPos = pos;
        _scrollLocked = true;
      } else {
        _lockedScrollPos = null;
        _scrollLocked = false;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    currentOpenRoomId = null;
    _inputController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    if (_blockChannel != null) {
      Supabase.instance.client.removeChannel(_blockChannel!);
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════
  // 🎯 스크롤
  // ═══════════════════════════════════════════════════

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 300;
  }

  void _jumpToBottom() {
    if (_scrollLocked) return;
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _forceScrollToBottom() {
    if (_initialScrolled) return;
    _initialScrolled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_disposed && mounted) _jumpToBottom();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_disposed && mounted) _jumpToBottom();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!_disposed && mounted) _jumpToBottom();
    });
  }

  void _animateToBottom() {
    if (_scrollLocked) return;
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_disposed || !mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ═══════════════════════════════════════════════════
  // 📥 데이터 로드
  // ═══════════════════════════════════════════════════

  Future<void> _loadAllStatus() async {
    try {
      final results = await Future.wait([
        _fetchBlockStatus(),
        _fetchFriendStatus(),
      ]);
      if (!_disposed && mounted) {
        setState(() {
          final b = results[0] as Map<String, bool>;
          _isBlocked = b['myBlock'];
          _isBlockedByPartner = b['partnerBlock'];
          _friendStatus = results[1] as String;
        });
      }
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() {
          _isBlocked ??= false;
          _isBlockedByPartner ??= false;
          _friendStatus ??= 'none';
        });
      }
    }
  }

  Future<Map<String, bool>> _fetchBlockStatus() async {
    final sb = Supabase.instance.client;
    final my = await sb
        .from('kyorangtalk_blocks')
        .select('id')
        .eq('blocker_id', _myId)
        .eq('blocked_id', widget.room.partnerId)
        .maybeSingle();
    final partner = await sb
        .from('kyorangtalk_blocks')
        .select('id')
        .eq('blocker_id', widget.room.partnerId)
        .eq('blocked_id', _myId)
        .maybeSingle();
    return {'myBlock': my != null, 'partnerBlock': partner != null};
  }

  Future<String> _fetchFriendStatus() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_friends')
        .select('status')
        .or('and(requester_id.eq.$_myId,receiver_id.eq.${widget.room.partnerId}),'
            'and(requester_id.eq.${widget.room.partnerId},receiver_id.eq.$_myId)')
        .maybeSingle();
    return data?['status'] as String? ?? 'none';
  }

  Future<void> _reloadBlockStatus() async {
    try {
      final b = await _fetchBlockStatus();
      if (!_disposed && mounted) {
        setState(() {
          _isBlocked = b['myBlock'];
          _isBlockedByPartner = b['partnerBlock'];
        });
      }
    } catch (_) {}
  }

  Future<void> _reloadFriendStatus() async {
    try {
      final s = await _fetchFriendStatus();
      if (!_disposed && mounted) setState(() => _friendStatus = s);
    } catch (_) {}
  }

  Future<void> _loadMuteStatus() async {
    final muted =
        await NotificationService.isMuted(roomId: widget.room.roomId);
    if (!_disposed && mounted) setState(() => _isMuted = muted);
  }

  Future<void> _markAllRead() async {
    try {
      await Supabase.instance.client
          .from('kyorangtalk_messages')
          .update({'is_read': true})
          .eq('room_id', widget.room.roomId)
          .neq('sender_id', _myId)
          .eq('is_read', false);
      if (!_disposed && mounted) ref.invalidate(chatRoomsProvider);
    } catch (_) {}
  }

  void _listenBlockChanges() {
    try {
      _blockChannel = Supabase.instance.client
          .channel('blocks_${widget.room.roomId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'kyorangtalk_blocks',
            callback: (_) {
              if (!_disposed && mounted) _reloadBlockStatus();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════
  // 🤝 친구/차단
  // ═══════════════════════════════════════════════════

  Future<void> _sendFriendRequest() async {
    if (_friendRequestSending) return;
    setState(() => _friendRequestSending = true);

    try {
      await Supabase.instance.client.from('kyorangtalk_friends').insert({
        'requester_id': _myId,
        'receiver_id': widget.room.partnerId,
        'status': 'pending',
      });
      if (!_disposed && mounted) {
        setState(() {
          _friendStatus = 'pending';
          _friendRequestSending = false;
        });
        _showSnack('${widget.room.partnerName}님에게 친구 요청을 보냈어요');
        ref.invalidate(friendsProvider);
        ref.invalidate(sentRequestsProvider);
      }
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() => _friendRequestSending = false);
        _showSnack('친구 요청 실패: $e');
      }
    }
  }

  Future<void> _blockUser() async {
    final ok =
        await showBlockConfirmDialog(context, widget.room.partnerName);
    if (!ok) return;

    try {
      final sb = Supabase.instance.client;
      await sb.from('kyorangtalk_blocks').insert({
        'blocker_id': _myId,
        'blocked_id': widget.room.partnerId,
      });
      await sb
          .from('kyorangtalk_friends')
          .delete()
          .or('and(requester_id.eq.$_myId,receiver_id.eq.${widget.room.partnerId}),'
              'and(requester_id.eq.${widget.room.partnerId},receiver_id.eq.$_myId)');

      if (!_disposed && mounted) {
        setState(() {
          _isBlocked = true;
          _friendStatus = 'none';
        });
        ref.invalidate(chatRoomsProvider);
        ref.invalidate(friendsProvider);
        _showSnack('${widget.room.partnerName}님을 차단했어요');
      }
    } catch (e) {
      if (!_disposed && mounted) _showSnack('차단 실패: $e');
    }
  }

  Future<void> _unblockUser() async {
    final ok =
        await showUnblockConfirmDialog(context, widget.room.partnerName);
    if (!ok) return;

    try {
      await Supabase.instance.client
          .from('kyorangtalk_blocks')
          .delete()
          .eq('blocker_id', _myId)
          .eq('blocked_id', widget.room.partnerId);
      if (!_disposed && mounted) {
        setState(() => _isBlocked = false);
        ref.invalidate(chatRoomsProvider);
        _showSnack('${widget.room.partnerName}님의 차단을 해제했어요');
      }
    } catch (e) {
      if (!_disposed && mounted) _showSnack('해제 실패: $e');
    }
  }

  Future<void> _reportUser() async {
    await showReportUserDialog(
      context: context,
      reportedUserId: widget.room.partnerId,
      reportedNickname: widget.room.partnerName,
    );
  }

  Future<void> _reportMessage(MessageModel msg) async {
    await showReportMessageDialog(
      context: context,
      messageId: msg.id,
      senderId: msg.senderId,
      roomId: widget.room.roomId,
      messageContent: msg.content,
      senderNickname: widget.room.partnerName,
    );
  }

  // ═══════════════════════════════════════════════════
  // 🔍 검색
  // ═══════════════════════════════════════════════════

  void _onSearch(String query, List<MessageModel> messages) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchIndex = 0;
      });
      return;
    }
    final results = <int>[];
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]
          .content
          .toLowerCase()
          .contains(query.toLowerCase())) {
        results.add(i);
      }
    }
    setState(() {
      _searchResults = results;
      _searchIndex = results.isEmpty ? 0 : results.length - 1;
    });
    if (results.isNotEmpty) {
      _scrollToMessageById(messages[results.last].id);
    }
  }

  void _scrollToMessageById(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _messageKeys[id];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  List<MessageModel> _getSortedMessages() {
    final msgs = ref.read(messagesProvider(widget.room.roomId)).value ?? [];
    return [...msgs]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  // ═══════════════════════════════════════════════════
  // 📎 첨부 메뉴
  // ═══════════════════════════════════════════════════

  Future<void> _handleAttachment() async {
    if (_isBlocked == true || _isBlockedByPartner == true) return;

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

    try {
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: _getGamePreviewText(gameData),
        gameData: gameData,
      );
      _animateToBottom();
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
      roomId: widget.room.roomId,
      roomType: 'dm',
    );
    if (pollId == null || !mounted) return;

    try {
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: '투표가 생성됐어요',
        pollId: pollId,
      );
      _animateToBottom();
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
        roomId: widget.room.roomId,
        roomType: 'dm',
      );
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: '[파일]',
        fileUrl: fileUrl,
        fileName: picked.name,
        fileSize: picked.size,
        fileType: picked.extension,
      );
      if (mounted) {
        Navigator.pop(context);
        setState(() => _sending = false);
        _animateToBottom();
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
              Text(fileName,
                  style:
                      TextStyle(color: AppTheme.textSub, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recordVoice() async {
    if (_isBlocked == true || _isBlockedByPartner == true) return;
    final result = await showVoiceRecordSheet(context);
    if (result == null) return;

    if (!_disposed && mounted) setState(() => _sending = true);

    try {
      final audioUrl = await uploadAudioFile(
        localPath: result.path,
        roomId: widget.room.roomId,
      );
      sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: '[음성 메시지]',
        audioUrl: audioUrl,
        audioDuration: result.duration,
      );
      if (!_disposed && mounted) {
        setState(() => _sending = false);
        _animateToBottom();
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
    if (content.isEmpty || _sending) return;
    if (_isBlocked == true || _isBlockedByPartner == true) return;

    _inputController.clear();
    final reply = _replyTo;
    setState(() => _replyTo = null);

    sendMessage(
      myId: _myId,
      roomId: widget.room.roomId,
      content: content,
      replyToId: reply?.id,
      replyToContent: reply?.content,
    ).catchError((e) {
      if (!_disposed && mounted) _showSnack('전송 실패: $e');
    });
    _animateToBottom();
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_isBlocked == true || _isBlockedByPartner == true) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _sending = true);

    try {
      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final path =
          'dm/${widget.room.roomId}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from('kyorangtalk')
          .upload(path, file,
              fileOptions: const FileOptions(upsert: true));

      final url = Supabase.instance.client.storage
          .from('kyorangtalk')
          .getPublicUrl(path);

      sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: '[이미지]',
        imageUrl: url,
      );
      if (!_disposed && mounted) {
        setState(() => _sending = false);
        _animateToBottom();
      }
    } catch (e) {
      if (!_disposed && mounted) {
        _showSnack('이미지 전송 실패: $e');
        setState(() => _sending = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════
  // 💬 메시지 액션
  // ═══════════════════════════════════════════════════

  Future<void> _deleteMessage(String messageId) async {
    await Supabase.instance.client
        .from('kyorangtalk_messages')
        .update({'is_deleted': true, 'content': '삭제된 메시지예요'})
        .eq('id', messageId)
        .eq('sender_id', _myId);
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    _showSnack('메시지가 복사됐어요');
  }

  Future<void> _pinMessage(String content) async {
    await setPinnedMessage(widget.room.roomId, content);
    if (!_disposed && mounted) {
      setState(() => _pinnedMessage = content);
      _showSnack('메시지를 고정했어요');
    }
  }

  Future<void> _unpinMessage() async {
    await setPinnedMessage(widget.room.roomId, null);
    if (!_disposed && mounted) setState(() => _pinnedMessage = null);
  }

  Future<void> _leaveChatRoom() async {
    final ok = await showLeaveChatConfirmDialog(context);
    if (!ok) return;
    await hideChatRoom(widget.room.roomId);
    if (!_disposed && mounted) {
      ref.invalidate(chatRoomsProvider);
      Navigator.pop(context);
    }
  }

  Future<void> _handleMute() async {
    final result = await showMuteOptionsSheet(context, isMuted: _isMuted);
    if (result == null || _disposed || !mounted) return;

    if (result == 'unmute') {
      await NotificationService.unmute(roomId: widget.room.roomId);
      if (!_disposed && mounted) {
        setState(() => _isMuted = false);
        _showSnack('알림이 켜졌어요');
      }
    } else {
      Duration? duration;
      String label;
      switch (result) {
        case '1h':  duration = const Duration(hours: 1);  label = '1시간'; break;
        case '8h':  duration = const Duration(hours: 8);  label = '8시간'; break;
        case '24h': duration = const Duration(hours: 24); label = '24시간'; break;
        default:    duration = null;                      label = '계속';
      }
      await NotificationService.mute(
          roomId: widget.room.roomId, duration: duration);
      if (!_disposed && mounted) {
        setState(() => _isMuted = true);
        _showSnack('$label 알림을 껐어요');
      }
    }
    if (!_disposed && mounted) ref.invalidate(mutedRoomsProvider);
  }

  void _showSnack(String msg) {
    if (_disposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _handleMessageOptions(MessageModel msg) {
    showMessageOptionsSheet(
      context,
      msg: msg,
      isMe: msg.senderId == _myId,
      isAnyBlocked: _isBlocked == true || _isBlockedByPartner == true,
      onReply: () {
        setState(() => _replyTo = msg);
        _focusNode.requestFocus();
      },
      onCopy: () => _copyMessage(msg.content),
      onPin: () => _pinMessage(msg.content),
      onReport: () => _reportMessage(msg),
      onDelete: () => _deleteMessage(msg.id),
    );
  }

  void _openPartnerProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: widget.room.partnerId,
          nickname: widget.room.partnerName,
          avatarUrl: widget.room.partnerAvatar,
        ),
      ),
    ).then((_) {
      if (!_disposed && mounted) {
        _reloadBlockStatus();
        _reloadFriendStatus();
      }
    });
  }

  void _handleNotFriendTap() {
    showNotFriendActions(
      context,
      partnerName: widget.room.partnerName,
      partnerAvatar: widget.room.partnerAvatar,
      friendStatus: _friendStatus ?? 'none',
      onAddFriend: _sendFriendRequest,
      onBlock: _blockUser,
    );
  }

  // ═══════════════════════════════════════════════════
  // 🕒 포맷
  // ═══════════════════════════════════════════════════

  String _timeStr(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final ampm = local.hour < 12 ? '오전' : '오후';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$ampm $hour:${local.minute.toString().padLeft(2, '0')}';
  }

  String _dateLabel(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${local.year}.${local.month}.${local.day}';
  }

  List<MessageGroup> _getGroupedMessages(List<MessageModel> messages) {
    if (_lastMessages != null &&
        _lastMessages!.length == messages.length &&
        identical(_lastMessages!.last, messages.last)) {
      return _cachedGroups;
    }

    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final groups = <MessageGroup>[];
    String? currentLabel;
    List<MessageModel> currentItems = [];

    for (final msg in sorted) {
      final label = _dateLabel(msg.createdAt);
      if (label != currentLabel) {
        if (currentItems.isNotEmpty) {
          groups.add(MessageGroup(currentLabel!, currentItems));
        }
        currentLabel = label;
        currentItems = [msg];
      } else {
        currentItems.add(msg);
      }
    }
    if (currentItems.isNotEmpty) {
      groups.add(MessageGroup(currentLabel!, currentItems));
    }

    _lastMessages = messages;
    _cachedGroups = groups;
    return groups;
  }

  GlobalKey _getKeyFor(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  // ═══════════════════════════════════════════════════
  // 🏗️ Build
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final msgsAsync = ref.watch(messagesProvider(widget.room.roomId));

    // 메시지 변경 감지: ID 비교로 진짜 새 메시지만!
    ref.listen(messagesProvider(widget.room.roomId), (prev, next) {
      if (_disposed) return;
      next.whenData((msgs) {
        if (_disposed) return;

        if (prev?.value == null) {
          _forceScrollToBottom();
          return;
        }

        final prevIds = prev!.value!.map((m) => m.id).toSet();
        final newMessages =
            msgs.where((m) => !prevIds.contains(m.id)).toList();

        if (newMessages.isNotEmpty) {
          final lastMsg = newMessages.last;
          final isMyMessage = lastMsg.senderId == _myId;

          if (isMyMessage || _isNearBottom()) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!_disposed && mounted) _animateToBottom();
            });
          }

          final unread =
              msgs.where((m) => m.senderId != _myId && !m.isRead).toList();
          if (unread.isNotEmpty) _markAllRead();
        }
      });
    });

    final isAnyBlocked = _isBlocked == true || _isBlockedByPartner == true;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      appBar: _searchMode ? _buildSearchBar() : _buildNormalBar(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_pinnedMessage != null)
              PinnedMessageBanner(
                pinnedMessage: _pinnedMessage!,
                onUnpin: _unpinMessage,
              ),

            Expanded(
              child: msgsAsync.when(
                loading: () => const MessageSkeleton(),
                error: (e, _) => Center(
                  child: Text('오류: $e',
                      style: TextStyle(color: AppTheme.textSub)),
                ),
                data: _buildMessageList,
              ),
            ),

            if (_replyTo != null && !isAnyBlocked)
              ReplyPreview(
                replyTo: _replyTo!,
                isMyReply: _replyTo!.senderId == _myId,
                partnerName: widget.room.partnerName,
                onCancel: () => setState(() => _replyTo = null),
              ),

            if (!_searchMode)
              if (!_isStatusLoaded)
                ChatInputBar(
                  controller: _inputController,
                  focusNode: _focusNode,
                  enabled: false,
                  sending: false,
                  onAttachment: () {},
                  onSend: () {},
                )
              else if (isAnyBlocked)
                BlockedBanner(
                  isBlockedByMe: _isBlocked == true,
                  partnerName: widget.room.partnerName,
                  onUnblock: _isBlocked == true ? _unblockUser : null,
                )
              else
                ChatInputBar(
                  controller: _inputController,
                  focusNode: _focusNode,
                  enabled: true,
                  sending: _sending,
                  onAttachment: _handleAttachment,
                  onSend: _send,
                ),
          ],
        ),
      ),
    );
  }

  AppBar _buildNormalBar() => buildChatAppBar(
        context: context,
        room: widget.room,
        isStatusLoaded: _isStatusLoaded,
        isBlocked: _isBlocked,
        isBlockedByPartner: _isBlockedByPartner,
        friendStatus: _friendStatus,
        isMuted: _isMuted,
        onProfileTap: _openPartnerProfile,
        onSearchTap: () {
          setState(() {
            _searchMode = true;
            _searchQuery = '';
            _searchResults = [];
          });
        },
        onLeave: _leaveChatRoom,
        onMute: _handleMute,
        onUnblock: _unblockUser,
        onAddFriend: _sendFriendRequest,
        onBlock: _blockUser,
        onReport: _reportUser,
        onNotFriendTap: _handleNotFriendTap,
      );

  PreferredSizeWidget _buildSearchBar() {
    final sorted = _getSortedMessages();
    return buildChatSearchAppBar(
      context: context,
      searchController: _searchController,
      messages: sorted,
      searchIndex: _searchIndex,
      searchResults: _searchResults,
      onClose: () {
        setState(() {
          _searchMode = false;
          _searchQuery = '';
          _searchResults = [];
          _searchIndex = 0;
        });
        _searchController.clear();
      },
      onSearch: (v) {
        setState(() => _searchQuery = v);
        _onSearch(v, sorted);
      },
      onPrev: () {
        if (_searchResults.isEmpty) return;
        setState(() =>
            _searchIndex = (_searchIndex + 1) % _searchResults.length);
        _scrollToMessageById(sorted[_searchResults[_searchIndex]].id);
      },
      onNext: () {
        if (_searchResults.isEmpty) return;
        setState(() => _searchIndex =
            (_searchIndex - 1 + _searchResults.length) %
                _searchResults.length);
        _scrollToMessageById(sorted[_searchResults[_searchIndex]].id);
      },
    );
  }

  Widget _buildMessageList(List<MessageModel> messages) {
    if (messages.isEmpty) {
      return EmptyChatState(partnerName: widget.room.partnerName);
    }

    final groups = _getGroupedMessages(messages);

    if (_searchMode && _searchQuery.isNotEmpty) {
      final sorted = groups.expand((g) => g.items).toList();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted) _onSearch(_searchQuery, sorted);
      });
    }

    final items = <MessageListItem>[];
    for (final group in groups) {
      items.add(MessageListItem.dateDivider(group.label));
      for (final msg in group.items) {
        items.add(MessageListItem.message(msg));
      }
    }

    // 🔒 매 빌드마다 스크롤 잠금 위치 강제 복구!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      if (!_scrollController.hasClients) return;

      if (_scrollLocked && _lockedScrollPos != null) {
        final currentPos = _scrollController.position.pixels;
        final diff = (currentPos - _lockedScrollPos!).abs();

        if (diff > 5) {
          _scrollController.jumpTo(_lockedScrollPos!);
        }
      }
    });

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      cacheExtent: 1000,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (ctx, index) {
        final item = items[index];

        if (item.isDivider) {
          return DateDivider(label: item.dateLabel!);
        }

        final msg = item.message!;
        final isMe = msg.senderId == _myId;
        final isHighlighted = _searchMode &&
            _searchQuery.isNotEmpty &&
            msg.content
                .toLowerCase()
                .contains(_searchQuery.toLowerCase());

        return RepaintBoundary(
          key: ValueKey('msg_${msg.id}'),
          child: GestureDetector(
            key: _getKeyFor(msg.id),
            onLongPress: () => _handleMessageOptions(msg),
            child: MessageBubble(
              msg: msg,
              isMe: isMe,
              timeStr: _timeStr(msg.createdAt),
              isHighlighted: isHighlighted,
              searchQuery: _searchQuery,
              partnerName: widget.room.partnerName,
              partnerAvatar: widget.room.partnerAvatar,
              onImageLoad: () {
                if (_disposed) return;
                if (_isNearBottom()) _jumpToBottom();
              },
              onImageTap: (url) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImageViewerScreen(
                      imageUrl: url,
                      senderName: isMe ? '나' : widget.room.partnerName,
                      time: _timeStr(msg.createdAt),
                    ),
                  ),
                );
              },
              onAvatarTap: isMe ? null : _openPartnerProfile,
            ),
          ),
        );
      },
    );
  }
}