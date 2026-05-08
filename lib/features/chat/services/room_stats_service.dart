import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════
// 채팅방 통계/미디어 서비스
// ═══════════════════════════════════════════════════
//
// 갤러리 화면용:
//   - fetchPhotos()  : 방 내 모든 사진 (단일 + 다중 포함)
//   - fetchFiles()   : 방 내 모든 파일
//   - fetchLinks()   : 방 메시지에 등장한 모든 URL
//
// 추억 화면용:
//   - fetchMemoryStats(): 통합 통계 한 방 (사람별 분해 포함)
//
// 모든 fetch 함수에 senderFilter 옵션:
//   - null      : 전체
//   - userId    : 해당 유저가 보낸 것만
// ═══════════════════════════════════════════════════

class RoomPhoto {
  final String messageId;
  final String url;
  final String senderId;
  final DateTime createdAt;

  const RoomPhoto({
    required this.messageId,
    required this.url,
    required this.senderId,
    required this.createdAt,
  });
}

class RoomFile {
  final String messageId;
  final String url;
  final String name;
  final int? size;
  final String? type;
  final String senderId;
  final DateTime createdAt;

  const RoomFile({
    required this.messageId,
    required this.url,
    required this.name,
    this.size,
    this.type,
    required this.senderId,
    required this.createdAt,
  });
}

class RoomLink {
  final String messageId;
  final String url;
  final String snippet;
  final String senderId;
  final DateTime createdAt;

  const RoomLink({
    required this.messageId,
    required this.url,
    required this.snippet,
    required this.senderId,
    required this.createdAt,
  });
}

class RoomMemoryStats {
  final DateTime? firstMessageAt;
  final String? firstMessageContent;
  final String? firstMessageSenderId;
  final int totalMessages;
  final int totalPhotos;
  final int totalVoices;
  final int totalFiles;
  final Map<int, int> hourlyActivity;
  final List<MapEntry<DateTime, int>> dailyActivity;
  final List<MapEntry<String, int>> topWords;

  // 사람별 분해 (DM 기준)
  final Map<String, int> messagesBySender;
  final Map<String, int> photosBySender;
  final Map<String, int> voicesBySender;
  final Map<String, int> filesBySender;
  final Map<String, Map<String, int>> wordsBySender; // sender → word → count

  const RoomMemoryStats({
    required this.firstMessageAt,
    required this.firstMessageContent,
    required this.firstMessageSenderId,
    required this.totalMessages,
    required this.totalPhotos,
    required this.totalVoices,
    required this.totalFiles,
    required this.hourlyActivity,
    required this.dailyActivity,
    required this.topWords,
    this.messagesBySender = const {},
    this.photosBySender = const {},
    this.voicesBySender = const {},
    this.filesBySender = const {},
    this.wordsBySender = const {},
  });

  /// 함께한 일수
  int get daysTogether {
    if (firstMessageAt == null) return 0;
    final now = DateTime.now();
    final first = firstMessageAt!.toLocal();
    final f = DateTime(first.year, first.month, first.day);
    final t = DateTime(now.year, now.month, now.day);
    return t.difference(f).inDays + 1;
  }

  MapEntry<DateTime, int>? get mostActiveDay {
    if (dailyActivity.isEmpty) return null;
    return dailyActivity.reduce((a, b) => a.value > b.value ? a : b);
  }

  int get hourlyMax {
    if (hourlyActivity.isEmpty) return 1;
    return hourlyActivity.values.reduce((a, b) => a > b ? a : b);
  }

  // ─── 사람별 토픽 단어 (Top 5) ───
  List<MapEntry<String, int>> topWordsBy(String senderId) {
    final m = wordsBySender[senderId];
    if (m == null) return const [];
    final list = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(10).toList();
  }
}

class RoomStatsService {
  static final _sb = Supabase.instance.client;

  static String _tableFor(bool isGroup) =>
      isGroup ? 'kyorangtalk_group_messages' : 'kyorangtalk_messages';

  static final _urlRegex =
      RegExp(r'(https?:\/\/[^\s<>"]+)', caseSensitive: false);

  // ═══════════════════════════════════════════════════
  // 갤러리: 사진
  // ═══════════════════════════════════════════════════
  static Future<List<RoomPhoto>> fetchPhotos({
    required String roomId,
    required bool isGroup,
    String? senderFilter,
  }) async {
    final table = _tableFor(isGroup);
    var q = _sb
        .from(table)
        .select('id, sender_id, image_url, image_urls, created_at')
        .eq('room_id', roomId)
        .eq('is_deleted', false)
        .or('image_url.not.is.null,image_urls.not.is.null');
    if (senderFilter != null) {
      q = q.eq('sender_id', senderFilter);
    }
    final rows = await q.order('created_at', ascending: false);

    final photos = <RoomPhoto>[];
    for (final row in rows as List) {
      final mid = row['id'] as String;
      final sid = row['sender_id'] as String;
      final ts = DateTime.parse(row['created_at'] as String);

      final urls = (row['image_urls'] as List?)?.cast<String>();
      if (urls != null && urls.isNotEmpty) {
        for (final u in urls) {
          photos.add(RoomPhoto(
              messageId: mid, url: u, senderId: sid, createdAt: ts));
        }
      } else if (row['image_url'] != null) {
        photos.add(RoomPhoto(
          messageId: mid,
          url: row['image_url'] as String,
          senderId: sid,
          createdAt: ts,
        ));
      }
    }
    return photos;
  }

  // ═══════════════════════════════════════════════════
  // 갤러리: 파일
  // ═══════════════════════════════════════════════════
  static Future<List<RoomFile>> fetchFiles({
    required String roomId,
    required bool isGroup,
    String? senderFilter,
  }) async {
    final table = _tableFor(isGroup);
    var q = _sb
        .from(table)
        .select(
            'id, sender_id, file_url, file_name, file_size, file_type, created_at')
        .eq('room_id', roomId)
        .eq('is_deleted', false)
        .not('file_url', 'is', null);
    if (senderFilter != null) {
      q = q.eq('sender_id', senderFilter);
    }
    final rows = await q.order('created_at', ascending: false);

    return (rows as List)
        .map((r) => RoomFile(
              messageId: r['id'] as String,
              url: r['file_url'] as String,
              name: (r['file_name'] as String?) ?? '파일',
              size: r['file_size'] as int?,
              type: r['file_type'] as String?,
              senderId: r['sender_id'] as String,
              createdAt: DateTime.parse(r['created_at'] as String),
            ))
        .toList();
  }

  // ═══════════════════════════════════════════════════
  // 갤러리: 링크
  // ═══════════════════════════════════════════════════
  static Future<List<RoomLink>> fetchLinks({
    required String roomId,
    required bool isGroup,
    String? senderFilter,
  }) async {
    final table = _tableFor(isGroup);
    var q = _sb
        .from(table)
        .select('id, sender_id, content, created_at')
        .eq('room_id', roomId)
        .eq('is_deleted', false)
        .ilike('content', '%http%');
    if (senderFilter != null) {
      q = q.eq('sender_id', senderFilter);
    }
    final rows = await q.order('created_at', ascending: false);

    final links = <RoomLink>[];
    for (final r in rows as List) {
      final content = (r['content'] as String?) ?? '';
      final matches = _urlRegex.allMatches(content);
      for (final m in matches) {
        links.add(RoomLink(
          messageId: r['id'] as String,
          url: m.group(0)!,
          snippet: content,
          senderId: r['sender_id'] as String,
          createdAt: DateTime.parse(r['created_at'] as String),
        ));
      }
    }
    return links;
  }

  // ═══════════════════════════════════════════════════
  // 추억: 통합 통계 (사람별 분해 포함)
  // ═══════════════════════════════════════════════════
  static Future<RoomMemoryStats> fetchMemoryStats({
    required String roomId,
    required bool isGroup,
  }) async {
    final table = _tableFor(isGroup);

    final rows = await _sb
        .from(table)
        .select(
            'sender_id, content, image_url, image_urls, audio_url, file_url, is_deleted, created_at')
        .eq('room_id', roomId)
        .order('created_at', ascending: true) as List;

    if (rows.isEmpty) {
      return const RoomMemoryStats(
        firstMessageAt: null,
        firstMessageContent: null,
        firstMessageSenderId: null,
        totalMessages: 0,
        totalPhotos: 0,
        totalVoices: 0,
        totalFiles: 0,
        hourlyActivity: {},
        dailyActivity: [],
        topWords: [],
      );
    }

    final first = rows.first as Map;

    int messages = 0, photos = 0, voices = 0, files = 0;
    final byHour = <int, int>{};
    final byDay = <String, int>{};
    final wordCounts = <String, int>{};

    final messagesBySender = <String, int>{};
    final photosBySender = <String, int>{};
    final voicesBySender = <String, int>{};
    final filesBySender = <String, int>{};
    final wordsBySender = <String, Map<String, int>>{};

    for (final r in rows) {
      if (r['is_deleted'] == true) continue;
      final sid = r['sender_id'] as String;
      messages++;
      messagesBySender[sid] = (messagesBySender[sid] ?? 0) + 1;

      final hasMulti = r['image_urls'] is List &&
          (r['image_urls'] as List).isNotEmpty;
      if (hasMulti) {
        final cnt = (r['image_urls'] as List).length;
        photos += cnt;
        photosBySender[sid] = (photosBySender[sid] ?? 0) + cnt;
      } else if (r['image_url'] != null) {
        photos++;
        photosBySender[sid] = (photosBySender[sid] ?? 0) + 1;
      }
      if (r['audio_url'] != null) {
        voices++;
        voicesBySender[sid] = (voicesBySender[sid] ?? 0) + 1;
      }
      if (r['file_url'] != null) {
        files++;
        filesBySender[sid] = (filesBySender[sid] ?? 0) + 1;
      }

      final dt = DateTime.parse(r['created_at'] as String).toLocal();
      byHour[dt.hour] = (byHour[dt.hour] ?? 0) + 1;

      final dayKey =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      byDay[dayKey] = (byDay[dayKey] ?? 0) + 1;

      final isMedia = hasMulti ||
          r['image_url'] != null ||
          r['audio_url'] != null ||
          r['file_url'] != null;
      if (!isMedia) {
        final content = (r['content'] as String?) ?? '';
        final perSender =
            wordsBySender.putIfAbsent(sid, () => <String, int>{});
        for (final w in _tokenize(content)) {
          wordCounts[w] = (wordCounts[w] ?? 0) + 1;
          perSender[w] = (perSender[w] ?? 0) + 1;
        }
      }
    }

    final dailyEntries = byDay.entries.map((e) {
      final p = e.key.split('-').map(int.parse).toList();
      return MapEntry(DateTime(p[0], p[1], p[2]), e.value);
    }).toList();

    final topWords = wordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RoomMemoryStats(
      firstMessageAt: DateTime.parse(first['created_at'] as String),
      firstMessageContent: first['content'] as String?,
      firstMessageSenderId: first['sender_id'] as String?,
      totalMessages: messages,
      totalPhotos: photos,
      totalVoices: voices,
      totalFiles: files,
      hourlyActivity: byHour,
      dailyActivity: dailyEntries,
      topWords: topWords.take(10).toList(),
      messagesBySender: messagesBySender,
      photosBySender: photosBySender,
      voicesBySender: voicesBySender,
      filesBySender: filesBySender,
      wordsBySender: wordsBySender,
    );
  }

  // ═══════════════════════════════════════════════════
  // 한글 친화 토크나이저 (간단)
  // ═══════════════════════════════════════════════════
  static Iterable<String> _tokenize(String text) sync* {
    for (final raw in text.split(RegExp(r'\s+'))) {
      final w = raw.trim();
      if (w.length < 2) continue;
      if (_urlRegex.hasMatch(w)) continue;
      if (RegExp(r'^[0-9]+$').hasMatch(w)) continue;
      yield w;
    }
  }
}