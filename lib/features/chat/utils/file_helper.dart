import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════
// 📎 파일 선택 + 업로드 헬퍼
// ═══════════════════════════════════════════════════

final _supabase = Supabase.instance.client;

/// 최대 파일 크기 (50MB)
const int kMaxFileSize = 50 * 1024 * 1024;

/// 차단 확장자 (보안)
const List<String> kBlockedExtensions = [
  'exe', 'bat', 'cmd', 'com', 'scr', 'msi',  // Windows 실행
  'sh', 'bash',                                // Unix 스크립트
  'app',                                       // macOS 실행
];

// ═══════════════════════════════════════════════════
// 📂 파일 선택 결과
// ═══════════════════════════════════════════════════
class PickedFileInfo {
  final File file;
  final String name;
  final int size;
  final String? mimeType;
  final String extension;

  PickedFileInfo({
    required this.file,
    required this.name,
    required this.size,
    this.mimeType,
    required this.extension,
  });
}

// ═══════════════════════════════════════════════════
// 📂 파일 선택하기
// ═══════════════════════════════════════════════════
/// 파일 선택 다이얼로그 표시
/// 
/// 반환값:
/// - null: 사용자가 취소
/// - PickedFileInfo: 선택된 파일 정보
Future<PickedFileInfo?> pickFile(BuildContext context) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,  // 파일 전체를 메모리에 로드하지 않음
    );

    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;
    if (picked.path == null) {
      _showError(context, '파일을 읽을 수 없어요');
      return null;
    }

    final file = File(picked.path!);
    final size = await file.length();
    final name = picked.name;
    final ext = picked.extension?.toLowerCase() ?? '';

    // 크기 검증
    if (size > kMaxFileSize) {
      _showError(context, 
        '파일이 너무 커요 (최대 ${_formatSize(kMaxFileSize)})');
      return null;
    }

    if (size == 0) {
      _showError(context, '빈 파일은 전송할 수 없어요');
      return null;
    }

    // 차단 확장자 검증
    if (kBlockedExtensions.contains(ext)) {
      _showError(context, '보안상 .$ext 파일은 전송할 수 없어요');
      return null;
    }

    return PickedFileInfo(
      file: file,
      name: name,
      size: size,
      extension: ext,
    );
  } catch (e) {
    if (context.mounted) {
      _showError(context, '파일 선택 실패: $e');
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════
// ☁️ 파일 업로드
// ═══════════════════════════════════════════════════
/// Supabase Storage에 파일 업로드
/// 
/// 파라미터:
/// - file: 로컬 파일
/// - fileName: 저장할 파일명
/// - roomId: 채팅방 ID
/// - roomType: 'dm' or 'group'
/// 
/// 반환값: 업로드된 파일의 public URL
Future<String> uploadFile({
  required File file,
  required String fileName,
  required String roomId,
  required String roomType,
}) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  
  // 파일명 안전하게 처리 (특수문자 제거)
  final safeName = _sanitizeFileName(fileName);
  
  // 경로: files/dm/{roomId}/{timestamp}_{filename}
  //       files/group/{roomId}/{timestamp}_{filename}
  final path = 'files/$roomType/$roomId/${timestamp}_$safeName';

  await _supabase.storage
      .from('kyorangtalk')
      .upload(path, file,
          fileOptions: const FileOptions(
            upsert: false,
            cacheControl: '3600',
          ));

  final url = _supabase.storage
      .from('kyorangtalk')
      .getPublicUrl(path);

  return url;
}

// ═══════════════════════════════════════════════════
// 🏷️ 파일 타입 구분
// ═══════════════════════════════════════════════════

/// 파일 확장자로 카테고리 구분
FileCategory getFileCategory(String extension) {
  final ext = extension.toLowerCase();
  
  // 문서
  if (['pdf'].contains(ext))        return FileCategory.pdf;
  if (['doc', 'docx'].contains(ext)) return FileCategory.word;
  if (['xls', 'xlsx', 'csv'].contains(ext)) return FileCategory.excel;
  if (['ppt', 'pptx'].contains(ext)) return FileCategory.ppt;
  if (['hwp', 'hwpx'].contains(ext)) return FileCategory.hwp;
  if (['txt', 'md'].contains(ext))   return FileCategory.text;
  
  // 압축
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return FileCategory.archive;
  }
  
  // 비디오
  if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
    return FileCategory.video;
  }
  
  // 오디오
  if (['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(ext)) {
    return FileCategory.audio;
  }
  
  // 안드로이드
  if (['apk'].contains(ext)) return FileCategory.apk;
  
  // 코드
  if (['js', 'ts', 'py', 'java', 'dart', 'c', 'cpp', 'html', 'css', 'json', 'xml']
      .contains(ext)) {
    return FileCategory.code;
  }
  
  return FileCategory.other;
}

enum FileCategory {
  pdf,
  word,
  excel,
  ppt,
  hwp,
  text,
  archive,
  video,
  audio,
  apk,
  code,
  other,
}

/// 카테고리별 아이콘
IconData getFileIcon(FileCategory category) {
  switch (category) {
    case FileCategory.pdf:     return Icons.picture_as_pdf;
    case FileCategory.word:    return Icons.description;
    case FileCategory.excel:   return Icons.table_chart;
    case FileCategory.ppt:     return Icons.slideshow;
    case FileCategory.hwp:     return Icons.article;
    case FileCategory.text:    return Icons.text_snippet;
    case FileCategory.archive: return Icons.folder_zip;
    case FileCategory.video:   return Icons.video_file;
    case FileCategory.audio:   return Icons.audio_file;
    case FileCategory.apk:     return Icons.android;
    case FileCategory.code:    return Icons.code;
    case FileCategory.other:   return Icons.insert_drive_file;
  }
}

/// 카테고리별 색상
Color getFileColor(FileCategory category) {
  switch (category) {
    case FileCategory.pdf:     return const Color(0xFFEF4444);  // 빨강
    case FileCategory.word:    return const Color(0xFF2563EB);  // 파랑
    case FileCategory.excel:   return const Color(0xFF10B981);  // 초록
    case FileCategory.ppt:     return const Color(0xFFF97316);  // 주황
    case FileCategory.hwp:     return const Color(0xFF6366F1);  // 인디고
    case FileCategory.text:    return const Color(0xFF6B7280);  // 회색
    case FileCategory.archive: return const Color(0xFF8B5CF6);  // 보라
    case FileCategory.video:   return const Color(0xFFA855F7);  // 퍼플
    case FileCategory.audio:   return const Color(0xFFEC4899);  // 핑크
    case FileCategory.apk:     return const Color(0xFF10B981);  // 초록
    case FileCategory.code:    return const Color(0xFF0EA5E9);  // 하늘
    case FileCategory.other:   return const Color(0xFF6B7280);  // 회색
  }
}

/// 카테고리별 라벨
String getFileCategoryLabel(FileCategory category) {
  switch (category) {
    case FileCategory.pdf:     return 'PDF';
    case FileCategory.word:    return 'Word';
    case FileCategory.excel:   return 'Excel';
    case FileCategory.ppt:     return 'PowerPoint';
    case FileCategory.hwp:     return '한글';
    case FileCategory.text:    return '텍스트';
    case FileCategory.archive: return '압축';
    case FileCategory.video:   return '동영상';
    case FileCategory.audio:   return '음악';
    case FileCategory.apk:     return 'APK';
    case FileCategory.code:    return '코드';
    case FileCategory.other:   return '파일';
  }
}

// ═══════════════════════════════════════════════════
// 🔧 유틸 함수
// ═══════════════════════════════════════════════════

/// 파일 크기 포맷 (1.5 MB)
String formatFileSize(int bytes) {
  return _formatSize(bytes);
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// 파일명 안전하게 (경로 분리자 제거)
String _sanitizeFileName(String name) {
  return name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(' ', '_');
}

void _showError(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}