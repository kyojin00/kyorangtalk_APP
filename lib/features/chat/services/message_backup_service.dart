import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../../group_chat/models/group_message_model.dart';
import 'message_cache_service.dart';

// ═══════════════════════════════════════════════════
// ☁️ MessageBackupService
//
// 위치: lib/features/chat/services/message_backup_service.dart
//
// Pro 사용자 전용 — 로컬 Hive 캐시 + DM 방 메타를 Supabase Storage에 백업.
// 기기 변경 / 앱 재설치 후 복원 가능.
//
// ⭐ v4 변경:
//   - 복원 시 백업 안의 모든 DM 방 ID에 대해 hidden_by에서 내 ID 일괄 제거
//     (메타 없어도 작동 — Hive에 있는 방 ID 전체 처리)
//   - kyorangtalk_room_user_state의 hidden_at도 일괄 해제
// ═══════════════════════════════════════════════════
class MessageBackupService {
  static const String _bucketName = 'kyorangtalk_backups';
  static const String _backupFormatVersion = '2';

  static final _supabase = Supabase.instance.client;

  // ───────────────────────────────────────────────
  // 백업 생성
  // ───────────────────────────────────────────────
  static Future<BackupResult> createBackup({
    void Function(double progress, String status)? onProgress,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return BackupResult.error('로그인이 필요해요');
    }

    try {
      onProgress?.call(0.05, '메시지 모으는 중...');

      final dms = MessageCacheService.exportAllDMs();
      final groups = MessageCacheService.exportAllGroups();
      final stats = MessageCacheService.getStats();

      if (stats.totalMessages == 0) {
        return BackupResult.error('백업할 메시지가 없어요');
      }

      onProgress?.call(0.15, 'DM 방 정보 모으는 중...');

      final dmRoomIds = dms.keys.toList();
      final dmRoomsMeta = <String, Map<String, dynamic>>{};

      if (dmRoomIds.isNotEmpty) {
        try {
          final data = await _supabase
              .from('kyorangtalk_rooms')
              .select('id, user1_id, user2_id, created_at')
              .inFilter('id', dmRoomIds);

          for (final row in (data as List)) {
            final m = row as Map<String, dynamic>;
            dmRoomsMeta[m['id'] as String] = {
              'user1_id': m['user1_id'],
              'user2_id': m['user2_id'],
              'created_at': m['created_at'],
            };
          }
        } catch (e) {
          print('🟡 [Backup] 방 메타 일부 조회 실패: $e');
        }
      }

      onProgress?.call(0.30, 'JSON 변환 중...');

      final payload = <String, dynamic>{
        'format_version': _backupFormatVersion,
        'user_id': user.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'app_version': await _getAppVersion(),
        'device_label': await _getDeviceLabel(),
        'message_count': stats.totalMessages,
        'room_count': stats.totalRooms,
        'dm_rooms_meta': dmRoomsMeta,
        'dms': dms.map((roomId, snap) => MapEntry(roomId, {
              'messages': snap.messages.map(_dmToMap).toList(),
              'hiddenAt': snap.hiddenAt?.toUtc().toIso8601String(),
              'hasMore': snap.hasMore,
              'savedAt': snap.savedAt.toIso8601String(),
            })),
        'groups': groups.map((roomId, snap) => MapEntry(roomId, {
              'messages': snap.messages.map(_groupToMap).toList(),
              'joinedAt': snap.joinedAt?.toUtc().toIso8601String(),
              'hasMore': snap.hasMore,
              'savedAt': snap.savedAt.toIso8601String(),
            })),
      };

      final jsonStr = jsonEncode(payload);
      final jsonBytes = utf8.encode(jsonStr);

      onProgress?.call(0.50, '압축 중...');

      final gzippedRaw = GZipEncoder().encode(jsonBytes)!;
      final gzipped = Uint8List.fromList(gzippedRaw);

      onProgress?.call(0.65, '업로드 중...');

      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final filePath = '${user.id}/$timestamp.json.gz';

      await _supabase.storage.from(_bucketName).uploadBinary(
            filePath,
            gzipped,
            fileOptions: const FileOptions(
              contentType: 'application/gzip',
              upsert: false,
            ),
          );

      onProgress?.call(0.90, '기록 중...');

      await _supabase.from('kyorangtalk_message_backups').insert({
        'user_id': user.id,
        'file_path': filePath,
        'file_size': gzipped.length,
        'message_count': stats.totalMessages,
        'room_count': stats.totalRooms,
        'device_label': await _getDeviceLabel(),
        'app_version': await _getAppVersion(),
      });

      onProgress?.call(1.0, '완료');

      return BackupResult.success(
        filePath: filePath,
        fileSize: gzipped.length,
        messageCount: stats.totalMessages,
        roomCount: stats.totalRooms,
      );
    } on StorageException catch (e) {
      return BackupResult.error('업로드 실패: ${e.message}');
    } on PostgrestException catch (e) {
      if (e.message.contains('backup_requires_pro')) {
        return BackupResult.error('Pro 구독이 필요해요');
      }
      return BackupResult.error('저장 실패: ${e.message}');
    } catch (e) {
      return BackupResult.error('백업 실패: $e');
    }
  }

  // ───────────────────────────────────────────────
  // 백업 목록 조회
  // ───────────────────────────────────────────────
  static Future<List<BackupInfo>> listBackups() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final data = await _supabase
          .from('kyorangtalk_message_backups')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return (data as List)
          .map((row) => BackupInfo.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('🔴 [Backup] listBackups 실패: $e');
      return [];
    }
  }

  // ───────────────────────────────────────────────
  // 복원
  // ───────────────────────────────────────────────
  static Future<RestoreResult> restoreBackup({
    required String filePath,
    void Function(double progress, String status)? onProgress,
    bool mergeWithLocal = true,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return RestoreResult.error('로그인이 필요해요');
    }

    try {
      onProgress?.call(0.05, '다운로드 중...');

      final gzipped =
          await _supabase.storage.from(_bucketName).download(filePath);

      onProgress?.call(0.25, '압축 해제 중...');

      final jsonBytes = GZipDecoder().decodeBytes(gzipped);
      final jsonStr = utf8.decode(jsonBytes);

      onProgress?.call(0.40, '데이터 검증 중...');

      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

      final fmtVer = payload['format_version'] as String?;
      if (fmtVer != '1' && fmtVer != '2') {
        return RestoreResult.error('지원하지 않는 백업 버전이에요');
      }

      final backupUserId = payload['user_id'] as String?;
      if (backupUserId != user.id) {
        return RestoreResult.error('다른 계정의 백업이에요');
      }

      onProgress?.call(0.50, '준비 중...');

      if (!mergeWithLocal) {
        await MessageCacheService.clearAll();
      }

      // ⭐ NEW v4: 백업 안의 모든 DM 방 ID 추출
      //   (메타가 있든 없든, 메시지가 있는 모든 방을 처리)
      final dmKeysFromBackup =
          (payload['dms'] as Map<String, dynamic>?)?.keys.toList() ?? [];

      // ── 서버 측 처리 ──
      onProgress?.call(0.55, 'DM 방 복구 중...');

      // 1) 모든 DM 방 hidden_by에서 내 ID 제거 (메타 필요 없음)
      final hiddenByRestored =
          await _clearHiddenByForRooms(dmKeysFromBackup, user.id);

      // 2) hidden_at 해제 (cleared_at 채움)
      await _clearHiddenAtForRooms(
        roomIds: dmKeysFromBackup,
        userId: user.id,
      );

      // 3) 백업 안에만 있고 서버엔 없는 방은 새로 생성 (v2 백업만)
      int newRoomsCreated = 0;
      if (fmtVer == '2') {
        final dmRoomsMeta =
            payload['dm_rooms_meta'] as Map<String, dynamic>? ?? {};
        newRoomsCreated =
            await _createMissingDmRooms(dmRoomsMeta, user.id);
      }

      final restoredRoomsServer = hiddenByRestored + newRoomsCreated;

      // ── Hive 캐시 ──
      int restoredMessages = 0;
      int restoredRooms = 0;

      onProgress?.call(0.65, 'DM 메시지 복원 중...');

      final dms = payload['dms'] as Map<String, dynamic>? ?? {};
      for (final entry in dms.entries) {
        final roomId = entry.key;
        final snap = entry.value as Map<String, dynamic>;
        final msgsJson = (snap['messages'] as List).cast<dynamic>();
        final messages = msgsJson
            .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
            .toList();

        final hasMore = snap['hasMore'] as bool? ?? false;

        // hiddenAt은 무조건 null로 (캐시 측 필터 해제)
        await MessageCacheService.saveDM(
          roomId: roomId,
          messages: messages,
          hiddenAt: null,
          hasMore: hasMore,
        );

        restoredMessages += messages.length;
        restoredRooms++;
      }

      onProgress?.call(0.85, '그룹 메시지 복원 중...');

      final groups = payload['groups'] as Map<String, dynamic>? ?? {};
      for (final entry in groups.entries) {
        final roomId = entry.key;
        final snap = entry.value as Map<String, dynamic>;
        final msgsJson = (snap['messages'] as List).cast<dynamic>();
        final messages = msgsJson
            .map((m) =>
                GroupMessageModel.fromJson(m as Map<String, dynamic>))
            .toList();

        final joinedAtStr = snap['joinedAt'] as String?;
        final hasMore = snap['hasMore'] as bool? ?? false;

        await MessageCacheService.saveGroup(
          roomId: roomId,
          messages: messages,
          joinedAt: joinedAtStr != null
              ? DateTime.parse(joinedAtStr).toLocal()
              : null,
          hasMore: hasMore,
        );

        restoredMessages += messages.length;
        restoredRooms++;
      }

      onProgress?.call(1.0, '완료');

      return RestoreResult.success(
        restoredMessages: restoredMessages,
        restoredRooms: restoredRooms,
        restoredRoomsOnServer: restoredRoomsServer,
      );
    } on StorageException catch (e) {
      return RestoreResult.error('다운로드 실패: ${e.message}');
    } catch (e) {
      return RestoreResult.error('복원 실패: $e');
    }
  }

  // ───────────────────────────────────────────────
  // ⭐ NEW v4: 모든 DM 방 hidden_by에서 내 ID 일괄 제거
  //   메타 없어도 작동 — Hive에 있는 방 ID 기준
  // ───────────────────────────────────────────────
  static Future<int> _clearHiddenByForRooms(
    List<String> roomIds,
    String myId,
  ) async {
    if (roomIds.isEmpty) return 0;

    int restored = 0;

    try {
      // 한 번에 가져와서 클라이언트에서 필터 (RLS와 안전)
      final data = await _supabase
          .from('kyorangtalk_rooms')
          .select('id, hidden_by')
          .inFilter('id', roomIds);

      for (final row in (data as List)) {
        final m = row as Map<String, dynamic>;
        final roomId = m['id'] as String;
        final hiddenBy =
            (m['hidden_by'] as List?)?.cast<String>() ?? [];

        if (hiddenBy.contains(myId)) {
          hiddenBy.remove(myId);
          try {
            await _supabase
                .from('kyorangtalk_rooms')
                .update({'hidden_by': hiddenBy})
                .eq('id', roomId);
            restored++;
          } catch (e) {
            print('🟡 [Restore] hidden_by 갱신 실패 ($roomId): $e');
          }
        }
      }
    } catch (e) {
      print('🟡 [Restore] hidden_by 복구 오류: $e');
    }

    return restored;
  }

  // ───────────────────────────────────────────────
  // kyorangtalk_room_user_state의 hidden_at 해제
  // ───────────────────────────────────────────────
  static Future<void> _clearHiddenAtForRooms({
    required List<String> roomIds,
    required String userId,
  }) async {
    if (roomIds.isEmpty) return;

    try {
      await _supabase
          .from('kyorangtalk_room_user_state')
          .update({
            'cleared_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId)
          .inFilter('room_id', roomIds)
          .not('hidden_at', 'is', null);
    } catch (e) {
      print('🟡 [Restore] hidden_at 해제 일부 실패: $e');
    }
  }

  // ───────────────────────────────────────────────
  // 백업엔 있고 서버엔 없는 방을 새로 INSERT
  //   (v2 백업만, dm_rooms_meta 필요)
  // ───────────────────────────────────────────────
  static Future<int> _createMissingDmRooms(
    Map<String, dynamic> dmRoomsMeta,
    String myId,
  ) async {
    int created = 0;

    for (final entry in dmRoomsMeta.entries) {
      final roomId = entry.key;
      final meta = entry.value as Map<String, dynamic>;
      final user1Id = meta['user1_id'] as String?;
      final user2Id = meta['user2_id'] as String?;

      if (user1Id == null || user2Id == null) continue;
      if (user1Id != myId && user2Id != myId) continue;

      try {
        // 같은 ID로 방 존재 확인
        final existing = await _supabase
            .from('kyorangtalk_rooms')
            .select('id')
            .eq('id', roomId)
            .maybeSingle();

        if (existing != null) continue; // 이미 있으면 skip (hidden_by 처리는 위에서 함)

        // 같은 상대와 다른 ID 방 있는지
        final partnerId = user1Id == myId ? user2Id : user1Id;
        final alt = await _supabase
            .from('kyorangtalk_rooms')
            .select('id')
            .or('and(user1_id.eq.$myId,user2_id.eq.$partnerId),'
                'and(user1_id.eq.$partnerId,user2_id.eq.$myId)')
            .maybeSingle();

        if (alt != null) continue; // 다른 방으로 이미 있음

        // 정말 없으면 새로 생성
        await _supabase.from('kyorangtalk_rooms').insert({
          'user1_id': user1Id,
          'user2_id': user2Id,
        });
        created++;
      } catch (e) {
        print('🟡 [Restore] 새 방 생성 실패 ($roomId): $e');
      }
    }

    return created;
  }

  // ───────────────────────────────────────────────
  // 백업 삭제
  // ───────────────────────────────────────────────
  static Future<bool> deleteBackup(String filePath) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.storage.from(_bucketName).remove([filePath]);

      await _supabase
          .from('kyorangtalk_message_backups')
          .delete()
          .eq('user_id', user.id)
          .eq('file_path', filePath);

      return true;
    } catch (e) {
      print('🔴 [Backup] deleteBackup 실패: $e');
      return false;
    }
  }

  // ───────────────────────────────────────────────
  // 기기 라벨 / 앱 버전
  // ───────────────────────────────────────────────
  static String? _cachedAppVersion;
  static String? _cachedDeviceLabel;

  static Future<String> _getAppVersion() async {
    if (_cachedAppVersion != null) return _cachedAppVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedAppVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _cachedAppVersion = 'unknown';
    }
    return _cachedAppVersion!;
  }

  static Future<String> _getDeviceLabel() async {
    if (_cachedDeviceLabel != null) return _cachedDeviceLabel!;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        _cachedDeviceLabel = '${a.brand} ${a.model}';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _cachedDeviceLabel = '${i.name} (${i.model})';
      } else {
        _cachedDeviceLabel = Platform.operatingSystem;
      }
    } catch (_) {
      _cachedDeviceLabel = 'Unknown device';
    }
    return _cachedDeviceLabel!;
  }

  // ───────────────────────────────────────────────
  // 직렬화 헬퍼
  // ───────────────────────────────────────────────
  static Map<String, dynamic> _dmToMap(MessageModel m) {
    return {
      'id': m.id,
      'sender_id': m.senderId,
      'room_id': m.receiverId,
      'content': m.content,
      'is_read': m.isRead,
      'is_deleted': m.isDeleted,
      'created_at': m.createdAt.toUtc().toIso8601String(),
      if (m.imageUrl != null) 'image_url': m.imageUrl,
      if (m.imageUrls != null) 'image_urls': m.imageUrls,
      if (m.replyToId != null) 'reply_to_id': m.replyToId,
      if (m.replyToContent != null) 'reply_to_content': m.replyToContent,
      if (m.audioUrl != null) 'audio_url': m.audioUrl,
      if (m.audioDuration != null) 'audio_duration': m.audioDuration,
      if (m.audioTranscript != null)
        'audio_transcript': m.audioTranscript,
      if (m.audioTranscriptStatus != null)
        'audio_transcript_status': m.audioTranscriptStatus,
      if (m.gameData != null) 'game_data': m.gameData,
      if (m.pollId != null) 'poll_id': m.pollId,
      if (m.fileUrl != null) 'file_url': m.fileUrl,
      if (m.fileName != null) 'file_name': m.fileName,
      if (m.fileSize != null) 'file_size': m.fileSize,
      if (m.fileType != null) 'file_type': m.fileType,
      if (m.locationShareId != null)
        'location_share_id': m.locationShareId,
      if (m.scheduleEventId != null)
        'schedule_event_id': m.scheduleEventId,
    };
  }

  static Map<String, dynamic> _groupToMap(GroupMessageModel m) {
    return {
      'id': m.id,
      'room_id': m.roomId,
      'sender_id': m.senderId,
      'content': m.content,
      'is_deleted': m.isDeleted,
      'created_at': m.createdAt.toUtc().toIso8601String(),
      'msg_type': m.msgType,
      if (m.imageUrl != null) 'image_url': m.imageUrl,
      if (m.imageUrls != null) 'image_urls': m.imageUrls,
      if (m.replyToId != null) 'reply_to_id': m.replyToId,
      if (m.replyToContent != null) 'reply_to_content': m.replyToContent,
      if (m.senderNickname != null) 'sender_nickname': m.senderNickname,
      if (m.senderAvatar != null) 'sender_avatar': m.senderAvatar,
      if (m.audioUrl != null) 'audio_url': m.audioUrl,
      if (m.audioDuration != null) 'audio_duration': m.audioDuration,
      if (m.audioTranscript != null)
        'audio_transcript': m.audioTranscript,
      if (m.audioTranscriptStatus != null)
        'audio_transcript_status': m.audioTranscriptStatus,
      if (m.gameData != null) 'game_data': m.gameData,
      if (m.pollId != null) 'poll_id': m.pollId,
      if (m.fileUrl != null) 'file_url': m.fileUrl,
      if (m.fileName != null) 'file_name': m.fileName,
      if (m.fileSize != null) 'file_size': m.fileSize,
      if (m.fileType != null) 'file_type': m.fileType,
      if (m.locationShareId != null)
        'location_share_id': m.locationShareId,
      if (m.scheduleEventId != null)
        'schedule_event_id': m.scheduleEventId,
    };
  }
}

// ═══════════════════════════════════════════════════
// 결과 모델
// ═══════════════════════════════════════════════════
class BackupResult {
  final bool isSuccess;
  final String? errorMessage;
  final String? filePath;
  final int? fileSize;
  final int? messageCount;
  final int? roomCount;

  BackupResult._({
    required this.isSuccess,
    this.errorMessage,
    this.filePath,
    this.fileSize,
    this.messageCount,
    this.roomCount,
  });

  factory BackupResult.success({
    required String filePath,
    required int fileSize,
    required int messageCount,
    required int roomCount,
  }) =>
      BackupResult._(
        isSuccess: true,
        filePath: filePath,
        fileSize: fileSize,
        messageCount: messageCount,
        roomCount: roomCount,
      );

  factory BackupResult.error(String message) =>
      BackupResult._(isSuccess: false, errorMessage: message);
}

class RestoreResult {
  final bool isSuccess;
  final String? errorMessage;
  final int restoredMessages;
  final int restoredRooms;
  final int restoredRoomsOnServer;

  RestoreResult._({
    required this.isSuccess,
    this.errorMessage,
    this.restoredMessages = 0,
    this.restoredRooms = 0,
    this.restoredRoomsOnServer = 0,
  });

  factory RestoreResult.success({
    required int restoredMessages,
    required int restoredRooms,
    int restoredRoomsOnServer = 0,
  }) =>
      RestoreResult._(
        isSuccess: true,
        restoredMessages: restoredMessages,
        restoredRooms: restoredRooms,
        restoredRoomsOnServer: restoredRoomsOnServer,
      );

  factory RestoreResult.error(String message) =>
      RestoreResult._(isSuccess: false, errorMessage: message);
}

class BackupInfo {
  final String id;
  final String filePath;
  final int fileSize;
  final int messageCount;
  final int roomCount;
  final String? deviceLabel;
  final String? appVersion;
  final DateTime createdAt;
  final DateTime expiresAt;

  BackupInfo({
    required this.id,
    required this.filePath,
    required this.fileSize,
    required this.messageCount,
    required this.roomCount,
    this.deviceLabel,
    this.appVersion,
    required this.createdAt,
    required this.expiresAt,
  });

  factory BackupInfo.fromJson(Map<String, dynamic> j) => BackupInfo(
        id: j['id'] as String,
        filePath: j['file_path'] as String,
        fileSize: (j['file_size'] as num).toInt(),
        messageCount: (j['message_count'] as num).toInt(),
        roomCount: (j['room_count'] as num).toInt(),
        deviceLabel: j['device_label'] as String?,
        appVersion: j['app_version'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
      );

  String get formattedSize {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  int get daysUntilExpiry => expiresAt.difference(DateTime.now()).inDays;
}