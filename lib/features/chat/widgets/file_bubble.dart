import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../utils/file_helper.dart';

// ═══════════════════════════════════════════════════
// 📎 파일 메시지 버블
// ═══════════════════════════════════════════════════
// 
// ⭐ 스크롤 안정화: AutomaticKeepAliveClientMixin 사용!
// ═══════════════════════════════════════════════════

class FileBubble extends StatefulWidget {
  final String fileUrl;
  final String fileName;
  final int? fileSize;
  final String? fileType;
  final bool isMe;

  const FileBubble({
    super.key,
    required this.fileUrl,
    required this.fileName,
    this.fileSize,
    this.fileType,
    required this.isMe,
  });

  @override
  State<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends State<FileBubble>
    with AutomaticKeepAliveClientMixin {
  bool _downloading = false;
  double _progress = 0;

  // ⭐ KeepAlive로 스크롤 시 위젯 유지!
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);  // ⭐ 필수!

    final extension = widget.fileName.split('.').last.toLowerCase();
    final category = getFileCategory(extension);
    final icon = getFileIcon(category);
    final color = getFileColor(category);
    final label = getFileCategoryLabel(category);

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _downloading ? null : _handleTap,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
            bottomRight: Radius.circular(widget.isMe ? 4 : 18),
          ),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 220,
              maxWidth: 260,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isMe ? AppTheme.primary : AppTheme.bgCard,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
                bottomRight: Radius.circular(widget.isMe ? 4 : 18),
              ),
              border: widget.isMe
                  ? null
                  : Border.all(color: AppTheme.border, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 파일 아이콘 + 정보
                Row(
                  children: [
                    // 아이콘 박스
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.isMe
                            ? Colors.white.withOpacity(0.2)
                            : color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: widget.isMe ? Colors.white : color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 파일명 + 크기
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.fileName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: widget.isMe
                                  ? Colors.white
                                  : AppTheme.textMain,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: widget.isMe
                                      ? Colors.white.withOpacity(0.2)
                                      : color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: widget.isMe
                                        ? Colors.white
                                        : color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (widget.fileSize != null)
                                Text(
                                  formatFileSize(widget.fileSize!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: widget.isMe
                                        ? Colors.white.withOpacity(0.8)
                                        : AppTheme.textSub,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 다운로드 버튼 / 진행률
                _buildActionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (_downloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 진행률 바
          Stack(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: widget.isMe
                      ? Colors.white.withOpacity(0.3)
                      : AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: _progress,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: widget.isMe
                        ? Colors.white
                        : AppTheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: widget.isMe
                      ? Colors.white
                      : AppTheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '다운로드 중... ${(_progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  color: widget.isMe
                      ? Colors.white
                      : AppTheme.textSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? Colors.white.withOpacity(0.2)
            : AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_outlined,
            size: 14,
            color: widget.isMe ? Colors.white : AppTheme.primary,
          ),
          const SizedBox(width: 5),
          Text(
            '다운로드',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: widget.isMe ? Colors.white : AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 🎯 탭 핸들러
  // ═══════════════════════════════════════════════
  Future<void> _handleTap() async {
    if (_downloading) return;
    final action = await _showActionSheet();
    if (action == null || !mounted) return;

    if (action == 'open') {
      await _downloadAndOpen();
    }
  }

  Future<String?> _showActionSheet() async {
    return await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final extension =
            widget.fileName.split('.').last.toLowerCase();
        final category = getFileCategory(extension);
        final icon = getFileIcon(category);
        final color = getFileColor(category);

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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.fileName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          if (widget.fileSize != null)
                            Text(
                              formatFileSize(widget.fileSize!),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSub,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: AppTheme.border, height: 1),
              ListTile(
                leading: Icon(Icons.open_in_new,
                    color: AppTheme.primary),
                title: Text(
                  '열기',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '다운로드 후 앱에서 열기',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSub),
                ),
                onTap: () => Navigator.pop(context, 'open'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════
  // 📥 다운로드 + 열기
  // ═══════════════════════════════════════════════
  Future<void> _downloadAndOpen() async {
    if (!mounted) return;

    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${widget.fileName}';
      final file = File(filePath);

      // 이미 있으면 바로 열기
      if (await file.exists()) {
        final stat = await file.stat();
        if (stat.size > 0) {
          await _openFile(filePath);
          if (mounted) {
            setState(() => _downloading = false);
          }
          return;
        }
      }

      // HTTP 스트림으로 다운로드
      final request = http.Request('GET', Uri.parse(widget.fileUrl));
      final response = await http.Client().send(request);
      final total = response.contentLength ?? 0;

      if (response.statusCode != 200) {
        throw Exception('다운로드 실패: ${response.statusCode}');
      }

      final sink = file.openWrite();
      int received = 0;

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() {
            _progress = received / total;
          });
        }
      });

      await sink.close();

      await _openFile(filePath);

      if (mounted) {
        setState(() => _downloading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('다운로드 실패: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('열기 실패: ${result.message}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파일 열기 실패: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}