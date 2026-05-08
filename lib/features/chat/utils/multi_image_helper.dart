import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 📷 다중 이미지 헬퍼
// ═══════════════════════════════════════════════════
//
// 기능
// - pickMultipleImagesFromGallery() : 갤러리 다중 선택 (최대 10장, 원본 그대로)
// - showMultiImagePreview()         : 썸네일 시트 (X 삭제 + 추가 + 원본 토글 + N장 보내기)
// - uploadMultipleImagesWithProgress(): 진행률 다이얼로그 + 동시 업로드 + 토글에 따라 압축
//
// 사용 흐름
//   1) final picked = await pickMultipleImagesFromGallery();
//   2) final result = await showMultiImagePreview(context: ..., initialImages: picked);
//   3) if (result == null || result.isEmpty) return;  // 취소
//   4) final urls = await uploadMultipleImagesWithProgress(
//        ..., isOriginal: result.isOriginal);
// ═══════════════════════════════════════════════════

/// 한 번에 보낼 수 있는 최대 이미지 수
const int kMaxMultiImages = 10;

/// 동시 업로드 개수 (네트워크 부담 줄이기)
const int kMaxConcurrentUploads = 3;

/// 일반 전송 화질 (원본 토글 OFF일 때) - 카톡 일반 전송 수준
const int kCompressedMaxSize = 2048;
const int kCompressedQuality = 90;

// ═══════════════════════════════════════════════════
// 결과 타입 - 파일 + 원본 여부
// ═══════════════════════════════════════════════════
class MultiImagePickResult {
  final List<File> files;
  final bool isOriginal;

  const MultiImagePickResult({
    required this.files,
    required this.isOriginal,
  });

  bool get isEmpty => files.isEmpty;
  bool get isNotEmpty => files.isNotEmpty;
  int get length => files.length;
}

// ═══════════════════════════════════════════════════
// 1) 갤러리 다중 선택 (원본으로 받음)
// ═══════════════════════════════════════════════════
/// 픽 단계에선 원본 그대로 받음.
/// 압축은 업로드 단계에서 토글 상태에 따라 결정.
Future<List<XFile>> pickMultipleImagesFromGallery() async {
  final picker = ImagePicker();
  try {
    final images = await picker.pickMultiImage();
    if (images.length > kMaxMultiImages) {
      return images.sublist(0, kMaxMultiImages);
    }
    return images;
  } catch (e) {
    return [];
  }
}

// ═══════════════════════════════════════════════════
// 2) 미리보기 시트 (원본 토글 포함)
// ═══════════════════════════════════════════════════
/// 미리보기 시트를 띄우고 사용자가 "N장 보내기"를 누르면 결과 반환
/// 취소하거나 모두 삭제하면 null 반환
Future<MultiImagePickResult?> showMultiImagePreview({
  required BuildContext context,
  required List<XFile> initialImages,
}) {
  if (initialImages.isEmpty) return Future.value(null);
  return showModalBottomSheet<MultiImagePickResult>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _MultiImagePreviewSheet(initial: initialImages),
  );
}

class _MultiImagePreviewSheet extends StatefulWidget {
  final List<XFile> initial;
  const _MultiImagePreviewSheet({required this.initial});

  @override
  State<_MultiImagePreviewSheet> createState() =>
      _MultiImagePreviewSheetState();
}

class _MultiImagePreviewSheetState extends State<_MultiImagePreviewSheet> {
  late List<XFile> _images;
  bool _isOriginal = false;

  @override
  void initState() {
    super.initState();
    _images = List<XFile>.from(widget.initial);
  }

  Future<void> _addMore() async {
    if (_images.length >= kMaxMultiImages) {
      _showSnack('최대 $kMaxMultiImages장까지 선택할 수 있어요');
      return;
    }
    final more = await pickMultipleImagesFromGallery();
    if (more.isEmpty) return;
    setState(() {
      final available = kMaxMultiImages - _images.length;
      _images.addAll(more.take(available));
    });
  }

  void _removeAt(int index) {
    setState(() => _images.removeAt(index));
    if (_images.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  void _send() {
    final files = _images.map((x) => File(x.path)).toList();
    Navigator.pop(
      context,
      MultiImagePickResult(files: files, isOriginal: _isOriginal),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─ 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ─ 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '${_images.length}장 선택됨',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '취소',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ─ 썸네일 가로 스크롤
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _images.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  if (i == _images.length) {
                    // + 추가 버튼
                    return GestureDetector(
                      onTap: _addMore,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.border,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add,
                                color: AppTheme.textSub, size: 28),
                            const SizedBox(height: 4),
                            Text(
                              '추가',
                              style: TextStyle(
                                color: AppTheme.textSub,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_images[i].path),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeAt(i),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                      // 순번 배지
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // ─ ⭐ 원본 화질 토글
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: InkWell(
                onTap: () => setState(() => _isOriginal = !_isOriginal),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _isOriginal
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _isOriginal
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '원본 화질로 보내기',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isOriginal ? '(용량이 커요)' : '(자동 압축됨)',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ─ 보내기 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _images.isEmpty ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.border,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isOriginal
                        ? '원본 ${_images.length}장 보내기'
                        : '${_images.length}장 보내기',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 3) 다중 업로드 (isOriginal에 따라 압축 분기)
// ═══════════════════════════════════════════════════
/// roomType: 'dm' 또는 'group'
/// isOriginal: false면 업로드 전 2048px/90% 압축, true면 그대로 업로드
/// 성공 시 업로드된 URL 리스트 반환, 실패 시 null
Future<List<String>?> uploadMultipleImagesWithProgress({
  required BuildContext context,
  required List<File> files,
  required String roomId,
  required String roomType,
  bool isOriginal = false,
}) async {
  if (files.isEmpty) return null;

  final supabase = Supabase.instance.client;
  final progress = ValueNotifier<int>(0);
  final total = files.length;

  // 다이얼로그 표시
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _UploadProgressDialog(
        progress: progress,
        total: total,
        isOriginal: isOriginal,
      ),
    ),
  );

  try {
    final uploaded = List<String?>.filled(files.length, null);

    for (int i = 0; i < files.length; i += kMaxConcurrentUploads) {
      final batchEnd = (i + kMaxConcurrentUploads).clamp(0, files.length);
      final batchIndices = List.generate(batchEnd - i, (k) => i + k);

      await Future.wait(batchIndices.map((idx) async {
        // ⭐ 토글에 따라 압축 분기
        final source = files[idx];
        final toUpload =
            isOriginal ? source : await _compressForUpload(source);

        final ext = toUpload.path.split('.').last;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = '$roomType/$roomId/${ts}_$idx.$ext';

        await supabase.storage.from('kyorangtalk').upload(
              path,
              toUpload,
              fileOptions: const FileOptions(upsert: true),
            );

        uploaded[idx] = supabase.storage
            .from('kyorangtalk')
            .getPublicUrl(path);

        progress.value = progress.value + 1;
      }));
    }

    if (context.mounted) Navigator.pop(context);
    progress.dispose();
    return uploaded.whereType<String>().toList();
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이미지 업로드 실패: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    progress.dispose();
    return null;
  }
}

// ═══════════════════════════════════════════════════
// 압축 헬퍼 (private)
// ═══════════════════════════════════════════════════
/// 2048px / quality 90으로 JPEG 압축
/// 임시 폴더에 저장해 새 File 반환. 실패 시 원본 그대로 반환 (전송은 성공시킴)
Future<File> _compressForUpload(File source) async {
  try {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final hash = source.path.hashCode;
    final targetPath = '${dir.path}/_kyc_${ts}_$hash.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      targetPath,
      minWidth: kCompressedMaxSize,
      minHeight: kCompressedMaxSize,
      quality: kCompressedQuality,
      format: CompressFormat.jpeg,
    );

    if (result == null) return source;
    return File(result.path);
  } catch (_) {
    return source;
  }
}

// ═══════════════════════════════════════════════════
// 진행률 다이얼로그
// ═══════════════════════════════════════════════════
class _UploadProgressDialog extends StatelessWidget {
  final ValueNotifier<int> progress;
  final int total;
  final bool isOriginal;

  const _UploadProgressDialog({
    required this.progress,
    required this.total,
    this.isOriginal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, value, __) {
            final pct = total == 0 ? 0.0 : value / total;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_upload_outlined,
                    size: 28,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  isOriginal ? '원본 보내는 중' : '이미지 보내는 중',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$value / $total',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSub,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppTheme.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(pct * 100).toInt()}%',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}