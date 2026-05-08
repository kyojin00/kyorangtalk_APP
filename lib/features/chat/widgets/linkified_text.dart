import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../services/link_preview_service.dart';

// ═══════════════════════════════════════════════════
// 🔗 URL을 자동으로 감지하고 클릭 가능하게 만드는 텍스트
// ═══════════════════════════════════════════════════
//
// 사용법:
//   LinkifiedText(
//     text: msg.content,
//     baseStyle: TextStyle(color: AppTheme.textMain, fontSize: 14),
//     searchQuery: searchQuery,                  // 선택: 검색 하이라이트
//     deletedStyle: ...,                         // 선택: 삭제 표시 시
//   )
//
// 동작:
//   - URL 부분만 색상 + 밑줄 + onTap에서 외부 브라우저 또는 우리 딥링크 처리
//   - 검색 쿼리가 있으면 노란 하이라이트도 같이 적용
// ═══════════════════════════════════════════════════

class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle baseStyle;
  final String searchQuery;
  final Color linkColor;

  const LinkifiedText({
    super.key,
    required this.text,
    required this.baseStyle,
    this.searchQuery = '',
    this.linkColor = const Color(0xFF60A5FA), // 밝은 파랑 (다크 테마용)
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    try {
      // 우리 딥링크 도메인이면 in-app으로 처리하고 싶지만,
      // launchUrl로 던지면 OS가 우리 앱한테 다시 던져줘서 동일하게 동작함.
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      print('🔗 launchUrl 실패: $e');
    }
  }

  TapGestureRecognizer _makeRecognizer(String url) {
    final r = TapGestureRecognizer()..onTap = () => _openUrl(url);
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final spans = _buildSpans();
    // ⭐ Text.rich 사용 — SelectableText.rich는 부모 width를 강제로 채워서
    // 메시지 버블 크기가 콘텐츠에 맞춰지지 않는 문제가 있음.
    // URL 클릭은 TapGestureRecognizer로 처리되므로 selectable 안 해도 됨.
    return Text.rich(
      TextSpan(children: spans),
      style: widget.baseStyle,
    );
  }

  List<InlineSpan> _buildSpans() {
    // 새 빌드마다 recognizer 재할당
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final text = widget.text;
    final query = widget.searchQuery.toLowerCase();

    // URL 매칭들 추출
    final matches = extractUrls(text);

    if (matches.isEmpty) {
      // URL 없으면 검색 하이라이트만 적용
      return _highlightOnly(text, query);
    }

    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final m in matches) {
      // URL 앞부분 (일반 텍스트)
      if (m.start > cursor) {
        final plain = text.substring(cursor, m.start);
        spans.addAll(_highlightOnly(plain, query));
      }

      // URL 부분
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: widget.baseStyle.copyWith(
          color: widget.linkColor,
          decoration: TextDecoration.underline,
          decorationColor: widget.linkColor.withOpacity(0.5),
          fontWeight: FontWeight.w600,
        ),
        recognizer: _makeRecognizer(url),
      ));

      cursor = m.end;
    }

    // 마지막 URL 뒤 텍스트
    if (cursor < text.length) {
      spans.addAll(_highlightOnly(text.substring(cursor), query));
    }

    return spans;
  }

  /// 검색 쿼리 하이라이트만 적용 (URL은 이미 처리된 후)
  List<InlineSpan> _highlightOnly(String text, String query) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: widget.baseStyle)];
    }

    final lowerText = text.toLowerCase();
    final spans = <InlineSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(query, start);
      if (idx == -1) {
        spans.add(TextSpan(
          text: text.substring(start),
          style: widget.baseStyle,
        ));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
          text: text.substring(start, idx),
          style: widget.baseStyle,
        ));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: widget.baseStyle.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          backgroundColor: const Color(0xFFFBBF24),
        ),
      ));
      start = idx + query.length;
    }

    return spans;
  }
}