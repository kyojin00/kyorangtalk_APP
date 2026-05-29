import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../../group_chat/models/group_message_model.dart';
import 'message_cache_service.dart';

// ═══════════════════════════════════════════════════
// ☁️ MessageBackupService v3 — 미디어 포함 ZIP 백업
//
// 위치: lib/features/chat/services/message_backup_service.dart
//
// Pro 사용자 전용. 로컬 Hive 캐시 + DM 방 메타 + 미디어 파일을
// Supabase Storage 에 통째로 백업.
//
// ⭐ v3 변경:
//   - 백업 포맷: .json.gz → .zip (Archive 패키지)
//   - 메시지 JSON + 미디어 파일(이미지/동영상/파일) 함께 압축
//   - 복원 시 미디어를 앱 로컬 디렉토리에 저장,
//     메시지의 image_url/audio_url/file_url을 file:// 경로로 치환
//   - 옛 .json.gz 백업도 그대로 복원 가능 (v1/v2 호환)
//
// 호환성:
//   - v1, v2 (.json.gz): 메시지만, 미디어 URL 그대로
//   - v3 (.zip): 메시지 + 미디어 파일, URL은 로컬 file:// 로 치환
//
// 주의:
//   - 이미지/파일 표시 위젯이 file:// 스킴을 처리해야 함
//     (CachedNetworkImage는 https만 지원 — file://은 Image.file 사용)
//   - Supabase Storage 단일 파일 max size (기본 50MB) 초과 시 업로드 실패
//     → 프로젝트 설정에서 한도 늘리기 필요
// ═══════════════════════════════════════════════════
class MessageBackupService {
  static const String _bucketName = 'kyorangtalk_backups';
  static const String _backupFormatVersion = '3';

  // 동시 다운로드 제한 (서버 부하 + 안정성)
  static const int _downloadBatchSize = 5;

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
      onProgress?.call(0.02, '메시지 모으는 중...');

      final dms = MessageCacheService.exportAllDMs();
      final groups = MessageCacheService.exportAllGroups();
      final stats = MessageCacheService.getStats();

      if (stats.totalMessages == 0) {
        return BackupResult.error('백업할 메시지가 없어요');
      }

      onProgress?.call(0.05, 'DM 방 정보 모으는 중...');

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

      onProgress?.call(0.08, '메시지 직렬화 중...');

      final dmsSerialized =
          dms.map((roomId, snap) => MapEntry(roomId, {
                'messages': snap.messages.map(_dmToMap).toList(),
                'hiddenAt': snap.hiddenAt?.toUtc().toIso8601String(),
                'hasMore': snap.hasMore,
                'savedAt': snap.savedAt.toIso8601String(),
              }));

      final groupsSerialized =
          groups.map((roomId, snap) => MapEntry(roomId, {
                'messages': snap.messages.map(_groupToMap).toList(),
                'joinedAt': snap.joinedAt?.toUtc().toIso8601String(),
                'hasMore': snap.hasMore,
                'savedAt': snap.savedAt.toIso8601String(),
              }));

      // ⭐ NEW: 미디어 URL 추출
      final mediaItems = _extractMediaItems(
        dms: dmsSerialized,
        groups: groupsSerialized,
      );

      onProgress?.call(
        0.10,
        mediaItems.isEmpty
            ? '미디어 없음, 메시지만 패키징...'
            : '미디어 ${mediaItems.length}개 다운로드 준비...',
      );

      // ⭐ NEW: 미디어 다운로드 (병렬, 5개씩)
      final downloadedMedia = <String, Uint8List>{};
      final manifestEntries = <Map<String, dynamic>>[];
      int downloaded = 0;
      int failed = 0;

      for (int i = 0; i < mediaItems.length; i += _downloadBatchSize) {
        final batch =
            mediaItems.skip(i).take(_downloadBatchSize).toList();
        final results = await Future.wait(
          batch.map((item) async {
            final bytes = await _downloadMedia(item.url);
            return MapEntry(item, bytes);
          }),
        );

        for (final entry in results) {
          final item = entry.key;
          final bytes = entry.value;
          if (bytes != null) {
            downloadedMedia[item.archivePath] = bytes;
            manifestEntries.add({
              'url': item.url,
              'archive_path': item.archivePath,
              'message_id': item.messageId,
              'room_id': item.roomId,
              'room_type': item.roomType,
              'kind': item.kind,
              if (item.urlIndex != null) 'url_index': item.urlIndex,
              'size': bytes.length,
            });
            downloaded++;
          } else {
            failed++;
          }
        }

        if (mediaItems.isNotEmpty) {
          final ratio = (i + batch.length) / mediaItems.length;
          final progress = 0.10 + ratio * 0.55;
          onProgress?.call(
            progress.clamp(0.10, 0.65),
            '미디어 다운로드 중 $downloaded/${mediaItems.length}'
            '${failed > 0 ? ' ($failed개 실패)' : ''}',
          );
        }
      }

      onProgress?.call(0.66, 'ZIP 패키징 중...');

      // payload 구성
      final payload = <String, dynamic>{
        'format_version': _backupFormatVersion,
        'user_id': user.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'app_version': await _getAppVersion(),
        'device_label': await _getDeviceLabel(),
        'message_count': stats.totalMessages,
        'room_count': stats.totalRooms,
        'media_count': downloaded,
        'media_failed': failed,
        'media_manifest': manifestEntries,
        'dm_rooms_meta': dmRoomsMeta,
        'dms': dmsSerialized,
        'groups': groupsSerialized,
      };

      final jsonStr = jsonEncode(payload);
      final jsonBytes = utf8.encode(jsonStr);

      // ZIP 만들기
      final archive = Archive();

      // 메시지 JSON
      archive.addFile(
        ArchiveFile('messages.json', jsonBytes.length, jsonBytes),
      );

      // 미디어 파일들
      for (final entry in downloadedMedia.entries) {
        final path = 'media/${entry.key}';
        final bytes = entry.value;
        final file = ArchiveFile(path, bytes.length, bytes);
        // 이미 압축된 미디어(jpg/mp4/...)는 재압축 효과 미미 → 빠르게
        file.compress = false;
        archive.addFile(file);
      }

      onProgress?.call(0.72, 'ZIP 인코딩 중...');

      final zipBytesRaw = ZipEncoder().encode(archive)!;
      final zipBytes = Uint8List.fromList(zipBytesRaw);

      onProgress?.call(0.80, '업로드 중...');

      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final filePath = '${user.id}/$timestamp.zip';

      await _supabase.storage.from(_bucketName).uploadBinary(
            filePath,
            zipBytes,
            fileOptions: const FileOptions(
              contentType: 'application/zip',
              upsert: false,
            ),
          );

      onProgress?.call(0.95, '기록 중...');

      await _supabase.from('kyorangtalk_message_backups').insert({
        'user_id': user.id,
        'file_path': filePath,
        'file_size': zipBytes.length,
        'message_count': stats.totalMessages,
        'room_count': stats.totalRooms,
        'device_label': await _getDeviceLabel(),
        'app_version': await _getAppVersion(),
      });

      onProgress?.call(1.0, '완료');

      return BackupResult.success(
        filePath: filePath,
        fileSize: zipBytes.length,
        messageCount: stats.totalMessages,
        roomCount: stats.totalRooms,
        mediaCount: downloaded,
        mediaFailed: failed,
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

      final fileBytes =
          await _supabase.storage.from(_bucketName).download(filePath);

      onProgress?.call(0.20, '파일 분석 중...');

      // 확장자로 포맷 판별
      final isZip = filePath.toLowerCase().endsWith('.zip');

      String jsonStr;
      Archive? archive;

      if (isZip) {
        // v3: ZIP
        archive = ZipDecoder().decodeBytes(fileBytes);
        final messagesFile = archive.findFile('messages.json');
        if (messagesFile == null) {
          return RestoreResult.error(
              '백업 파일에 메시지 데이터가 없어요');
        }
        jsonStr = utf8.decode(messagesFile.content as List<int>);
      } else {
        // v1/v2: GZIP
        final jsonBytes = GZipDecoder().decodeBytes(fileBytes);
        jsonStr = utf8.decode(jsonBytes);
      }

      onProgress?.call(0.28, '데이터 검증 중...');

      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

      final fmtVer = payload['format_version'] as String?;
      if (fmtVer != '1' && fmtVer != '2' && fmtVer != '3') {
        return RestoreResult.error('지원하지 않는 백업 버전이에요');
      }

      final backupUserId = payload['user_id'] as String?;
      if (backupUserId != user.id) {
        return RestoreResult.error('다른 계정의 백업이에요');
      }

      // ⭐ NEW v3: 미디어 추출
      final urlToLocalPath = <String, String>{};
      int mediaExtracted = 0;

      if (archive != null && fmtVer == '3') {
        onProgress?.call(0.32, '미디어 추출 준비 중...');

        final mediaDir = await _getMediaRestoreDir(user.id);

        // 전체 교체 모드면 기존 미디어 다 지움
        if (!mergeWithLocal) {
          try {
            if (await mediaDir.exists()) {
              await mediaDir.delete(recursive: true);
            }
          } catch (_) {}
        }
        await mediaDir.create(recursive: true);

        final manifest = (payload['media_manifest'] as List?)
                ?.cast<dynamic>()
                .map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];

        final total = manifest.length;

        for (int i = 0; i < manifest.length; i++) {
          final entry = manifest[i];
          final archivePath = entry['archive_path'] as String?;
          final originalUrl = entry['url'] as String?;

          if (archivePath == null || originalUrl == null) continue;

          final file = archive.findFile('media/$archivePath');
          if (file == null) continue;

          try {
            final localFile = File('${mediaDir.path}/$archivePath');
            await localFile.parent.create(recursive: true);
            await localFile.writeAsBytes(file.content as List<int>);

            urlToLocalPath[originalUrl] = localFile.path;
            mediaExtracted++;
          } catch (e) {
            print('🟡 [Restore] 미디어 저장 실패 ($archivePath): $e');
          }

          // 진행률 (10개마다 갱신)
          if (i % 10 == 0 || i == manifest.length - 1) {
            final ratio = (i + 1) / total;
            final progress = 0.32 + ratio * 0.28;
            onProgress?.call(
              progress.clamp(0.32, 0.60),
              '미디어 저장 중 ${i + 1}/$total',
            );
          }
        }
      }

      onProgress?.call(0.62, '준비 중...');

      if (!mergeWithLocal) {
        await MessageCacheService.clearAll();
      }

      final dmKeysFromBackup =
          (payload['dms'] as Map<String, dynamic>?)?.keys.toList() ?? [];

      // ── 서버 측 처리 ──
      onProgress?.call(0.65, 'DM 방 복구 중...');

      // 1) 모든 DM 방 hidden_by에서 내 ID 제거
      final hiddenByRestored =
          await _clearHiddenByForRooms(dmKeysFromBackup, user.id);

      // 2) hidden_at 해제
      await _clearHiddenAtForRooms(
        roomIds: dmKeysFromBackup,
        userId: user.id,
      );

      // 3) 백업엔 있고 서버엔 없는 방 새로 생성 (v2/v3 백업만)
      int newRoomsCreated = 0;
      if (fmtVer == '2' || fmtVer == '3') {
        final dmRoomsMeta =
            payload['dm_rooms_meta'] as Map<String, dynamic>? ?? {};
        newRoomsCreated =
            await _createMissingDmRooms(dmRoomsMeta, user.id);
      }

      final restoredRoomsServer = hiddenByRestored + newRoomsCreated;

      // ── Hive 캐시 ──
      int restoredMessages = 0;
      int restoredRooms = 0;

      onProgress?.call(0.72, 'DM 메시지 복원 중...');

      final dms = payload['dms'] as Map<String, dynamic>? ?? {};
      for (final entry in dms.entries) {
        final roomId = entry.key;
        final snap = entry.value as Map<String, dynamic>;
        final msgsJson = (snap['messages'] as List).cast<dynamic>();

        final messages = msgsJson.map((rawJson) {
          final json = rawJson as Map<String, dynamic>;
          // ⭐ 미디어 URL을 로컬 file:// 경로로 치환
          final rewritten = urlToLocalPath.isEmpty
              ? json
              : _rewriteMessageMediaUrls(json, urlToLocalPath);
          return MessageModel.fromJson(rewritten);
        }).toList();

        final hasMore = snap['hasMore'] as bool? ?? false;

        await MessageCacheService.saveDM(
          roomId: roomId,
          messages: messages,
          hiddenAt: null,
          hasMore: hasMore,
        );

        restoredMessages += messages.length;
        restoredRooms++;
      }

      onProgress?.call(0.88, '그룹 메시지 복원 중...');

      final groups = payload['groups'] as Map<String, dynamic>? ?? {};
      for (final entry in groups.entries) {
        final roomId = entry.key;
        final snap = entry.value as Map<String, dynamic>;
        final msgsJson = (snap['messages'] as List).cast<dynamic>();

        final messages = msgsJson.map((rawJson) {
          final json = rawJson as Map<String, dynamic>;
          final rewritten = urlToLocalPath.isEmpty
              ? json
              : _rewriteMessageMediaUrls(json, urlToLocalPath);
          return GroupMessageModel.fromJson(rewritten);
        }).toList();

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
        restoredMediaFiles: mediaExtracted,
      );
    } on StorageException catch (e) {
      return RestoreResult.error('다운로드 실패: ${e.message}');
    } catch (e) {
      return RestoreResult.error('복원 실패: $e');
    }
  }

  // ───────────────────────────────────────────────
  // ⭐ NEW v3: 미디어 URL 추출
  // ───────────────────────────────────────────────
  static List<_MediaItem> _extractMediaItems({
    required Map<String, Map<String, dynamic>> dms,
    required Map<String, Map<String, dynamic>> groups,
  }) {
    final items = <_MediaItem>[];

    void processMessages(
      Map<String, Map<String, dynamic>> roomsData,
      String roomType,
    ) {
      for (final roomEntry in roomsData.entries) {
        final roomId = roomEntry.key;
        final snap = roomEntry.value;
        final msgs = (snap['messages'] as List).cast<dynamic>();
        for (final raw in msgs) {
          final m = raw as Map<String, dynamic>;
          final messageId = m['id'] as String?;
          if (messageId == null) continue;

          // image_url
          final imageUrl = m['image_url'] as String?;
          if (imageUrl != null && imageUrl.startsWith('http')) {
            items.add(_MediaItem(
              url: imageUrl,
              messageId: messageId,
              roomId: roomId,
              roomType: roomType,
              kind: 'image',
            ));
          }

          // image_urls[]
          final imageUrls = (m['image_urls'] as List?)?.cast<dynamic>();
          if (imageUrls != null) {
            for (int i = 0; i < imageUrls.length; i++) {
              final url = imageUrls[i] as String?;
              if (url != null && url.startsWith('http')) {
                items.add(_MediaItem(
                  url: url,
                  messageId: messageId,
                  roomId: roomId,
                  roomType: roomType,
                  kind: 'image',
                  urlIndex: i,
                ));
              }
            }
          }

          // audio_url
          final audioUrl = m['audio_url'] as String?;
          if (audioUrl != null && audioUrl.startsWith('http')) {
            items.add(_MediaItem(
              url: audioUrl,
              messageId: messageId,
              roomId: roomId,
              roomType: roomType,
              kind: 'audio',
            ));
          }

          // file_url
          final fileUrl = m['file_url'] as String?;
          if (fileUrl != null && fileUrl.startsWith('http')) {
            items.add(_MediaItem(
              url: fileUrl,
              messageId: messageId,
              roomId: roomId,
              roomType: roomType,
              kind: 'file',
              filename: m['file_name'] as String?,
            ));
          }
        }
      }
    }

    processMessages(dms, 'dm');
    processMessages(groups, 'group');

    return items;
  }

  // ───────────────────────────────────────────────
  // ⭐ NEW v3: 단일 미디어 다운로드
  // ───────────────────────────────────────────────
  static Future<Uint8List?> _downloadMedia(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      print('🟡 [Backup] 다운로드 실패 ($url): ${response.statusCode}');
    } catch (e) {
      print('🟡 [Backup] 다운로드 오류 ($url): $e');
    }
    return null;
  }

  // ───────────────────────────────────────────────
  // ⭐ NEW v3: 메시지 안의 미디어 URL을 로컬 file:// 로 치환
  // ───────────────────────────────────────────────
  static Map<String, dynamic> _rewriteMessageMediaUrls(
    Map<String, dynamic> json,
    Map<String, String> urlToLocalPath,
  ) {
    final result = Map<String, dynamic>.from(json);

    void rewriteSingle(String key) {
      final v = result[key] as String?;
      if (v != null && urlToLocalPath.containsKey(v)) {
        result[key] = 'file://${urlToLocalPath[v]}';
      }
    }

    rewriteSingle('image_url');
    rewriteSingle('audio_url');
    rewriteSingle('file_url');

    final imageUrls = (result['image_urls'] as List?)?.cast<dynamic>();
    if (imageUrls != null) {
      result['image_urls'] = imageUrls.map((u) {
        final s = u as String?;
        if (s != null && urlToLocalPath.containsKey(s)) {
          return 'file://${urlToLocalPath[s]}';
        }
        return s;
      }).toList();
    }

    return result;
  }

  // ───────────────────────────────────────────────
  // ⭐ NEW v3: 복원 미디어 저장 디렉토리
  // ───────────────────────────────────────────────
  static Future<Directory> _getMediaRestoreDir(String userId) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/kt_restored_media/$userId');
  }

  // ───────────────────────────────────────────────
  // 모든 DM 방 hidden_by에서 내 ID 일괄 제거
  // ───────────────────────────────────────────────
  static Future<int> _clearHiddenByForRooms(
    List<String> roomIds,
    String myId,
  ) async {
    if (roomIds.isEmpty) return 0;

    int restored = 0;

    try {
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
        final existing = await _supabase
            .from('kyorangtalk_rooms')
            .select('id')
            .eq('id', roomId)
            .maybeSingle();

        if (existing != null) continue;

        final partnerId = user1Id == myId ? user2Id : user1Id;
        final alt = await _supabase
            .from('kyorangtalk_rooms')
            .select('id')
            .or('and(user1_id.eq.$myId,user2_id.eq.$partnerId),'
                'and(user1_id.eq.$partnerId,user2_id.eq.$myId)')
            .maybeSingle();

        if (alt != null) continue;

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
// ⭐ NEW v3: 미디어 아이템 내부 모델
// ═══════════════════════════════════════════════════
class _MediaItem {
  final String url;
  final String messageId;
  final String roomId;
  final String roomType; // 'dm' or 'group'
  final String kind; // 'image', 'audio', 'file'
  final int? urlIndex; // image_urls[] 안의 인덱스
  final String? filename;

  _MediaItem({
    required this.url,
    required this.messageId,
    required this.roomId,
    required this.roomType,
    required this.kind,
    this.urlIndex,
    this.filename,
  });

  // ZIP 안의 경로 (media/ 접두사 제외)
  // 예: dm/roomA/msg123_image.jpg
  //     dm/roomA/msg123_image_0.jpg (image_urls의 첫 번째)
  //     group/roomB/msg456_audio.mp3
  String get archivePath {
    final ext = _extractExt(url, filename);
    final indexSuffix = urlIndex != null ? '_$urlIndex' : '';
    return '$roomType/$roomId/${messageId}_$kind$indexSuffix$ext';
  }

  static String _extractExt(String url, String? filename) {
    // 파일명에 확장자가 있으면 우선
    if (filename != null && filename.contains('.')) {
      return filename.substring(filename.lastIndexOf('.'));
    }
    // URL 에서 추출
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.contains('.')) {
        var ext = path.substring(path.lastIndexOf('.'));
        // 쿼리/프래그먼트 제거
        ext = ext.split('?').first.split('#').first;
        return ext;
      }
    } catch (_) {}
    return '';
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
  final int? mediaCount;
  final int? mediaFailed;

  BackupResult._({
    required this.isSuccess,
    this.errorMessage,
    this.filePath,
    this.fileSize,
    this.messageCount,
    this.roomCount,
    this.mediaCount,
    this.mediaFailed,
  });

  factory BackupResult.success({
    required String filePath,
    required int fileSize,
    required int messageCount,
    required int roomCount,
    int? mediaCount,
    int? mediaFailed,
  }) =>
      BackupResult._(
        isSuccess: true,
        filePath: filePath,
        fileSize: fileSize,
        messageCount: messageCount,
        roomCount: roomCount,
        mediaCount: mediaCount,
        mediaFailed: mediaFailed,
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
  final int restoredMediaFiles;

  RestoreResult._({
    required this.isSuccess,
    this.errorMessage,
    this.restoredMessages = 0,
    this.restoredRooms = 0,
    this.restoredRoomsOnServer = 0,
    this.restoredMediaFiles = 0,
  });

  factory RestoreResult.success({
    required int restoredMessages,
    required int restoredRooms,
    int restoredRoomsOnServer = 0,
    int restoredMediaFiles = 0,
  }) =>
      RestoreResult._(
        isSuccess: true,
        restoredMessages: restoredMessages,
        restoredRooms: restoredRooms,
        restoredRoomsOnServer: restoredRoomsOnServer,
        restoredMediaFiles: restoredMediaFiles,
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