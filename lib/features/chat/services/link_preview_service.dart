import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;

// ═══════════════════════════════════════════════════
// 🔗 링크 OG 미리보기 서비스
// ═══════════════════════════════════════════════════
//
// 사용:
//   final preview = await LinkPreviewService.fetch(url);
//   if (preview != null) { ...preview.title, .image, .description }
//
// 인메모리 캐시 (앱 종료 시 사라짐) + 동시 요청 합치기.
// 같은 URL을 여러 메시지가 동시에 요청해도 한 번만 fetch.
// ═══════════════════════════════════════════════════

class LinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;

  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.siteName,
  });

  bool get isEmpty =>
      (title == null || title!.trim().isEmpty) &&
      (description == null || description!.trim().isEmpty) &&
      (image == null || image!.trim().isEmpty);

  bool get isNotEmpty => !isEmpty;

  String get hostName {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }
}

class LinkPreviewService {
  // url → 캐시된 결과
  static final Map<String, LinkPreview?> _cache = {};
  // url → 진행 중인 fetch
  static final Map<String, Future<LinkPreview?>> _inflight = {};

  // 너무 큰 페이지 본문은 잘라냄 (HTML 파싱 부하 회피)
  static const _maxBytes = 200000;
  static const _timeout = Duration(seconds: 6);

  /// URL의 OG 메타 가져오기. 실패/빈 응답이면 null.
  static Future<LinkPreview?> fetch(String url) async {
    // 캐시 hit
    if (_cache.containsKey(url)) return _cache[url];
    // 진행 중인 같은 요청 합치기
    if (_inflight.containsKey(url)) return _inflight[url]!;

    // ⭐ 디버그: 첫 요청 시 다른 도메인도 같이 테스트해서 비교
    if (_cache.isEmpty) {
      _debugDnsTest();
    }

    final future = _doFetch(url);
    _inflight[url] = future;
    try {
      final result = await future;
      _cache[url] = result;
      return result;
    } finally {
      _inflight.remove(url);
    }
  }

  /// 디버그: 다른 도메인 DNS 테스트 (한 번만)
  static Future<void> _debugDnsTest() async {
    print('🔬 DNS 테스트 시작...');
    final hosts = [
      'www.naver.com',
      'github.com',
      'google.com',
      'open.kyorang.com',
    ];
    for (final h in hosts) {
      try {
        final addrs = await InternetAddress.lookup(h)
            .timeout(const Duration(seconds: 3));
        print('🔬 ✅ $h → ${addrs.map((a) => a.address).join(", ")}');
      } catch (e) {
        print('🔬 ❌ $h → $e');
      }
    }
  }

  static Future<LinkPreview?> _doFetch(String url) async {
    // DNS 실패는 종종 일시적 — 1회 재시도
    for (int attempt = 0; attempt < 2; attempt++) {
      HttpClient? client;
      try {
        final uri = Uri.parse(url);

        // ⭐ 명시적 DNS lookup으로 캐시 갱신 유도
        // 일부 안드로이드 환경에서 호스트가 NXDOMAIN으로 negative cache 되어 있는
        // 경우, 이렇게 직접 호출하면 새로 fetch가 되어 풀리는 경우가 있음.
        try {
          final addrs = await InternetAddress.lookup(uri.host)
              .timeout(const Duration(seconds: 4));
          print('🔗 [Preview] DNS resolved ${uri.host}: '
              '${addrs.map((a) => a.address).join(", ")}');
        } catch (e) {
          print('🔗 [Preview] DNS lookup 실패 (${uri.host}): $e');
          // 실패해도 계속 진행 — HttpClient가 어쩌면 풀 수도 있으니
        }

        // ⭐ dart:io HttpClient 직접 사용
        client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5)
          ..idleTimeout = const Duration(seconds: 5)
          ..userAgent =
              'Mozilla/5.0 (compatible; KYORANGTalkBot/1.0; +https://open.kyorang.com)';

        final request = await client.getUrl(uri).timeout(_timeout);
        request.headers.set('Accept', 'text/html,application/xhtml+xml');
        request.headers.set('Accept-Language', 'ko-KR,ko;q=0.9,en;q=0.8');
        request.followRedirects = true;
        request.maxRedirects = 5;

        final response = await request.close().timeout(_timeout);

        if (response.statusCode != 200) {
          print('🔗 [Preview] ${response.statusCode} $url');
          return null;
        }

        // 본문 읽기 (최대 _maxBytes)
        final bytesBuilder = BytesBuilder();
        var totalBytes = 0;
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
          totalBytes += chunk.length;
          if (totalBytes >= _maxBytes) break;
        }

        // 인코딩 처리 (charset 헤더 또는 기본 utf8)
        var body = '';
        try {
          body = utf8.decode(bytesBuilder.toBytes(), allowMalformed: true);
        } catch (_) {
          body = String.fromCharCodes(bytesBuilder.toBytes());
        }

        if (body.length > _maxBytes) {
          body = body.substring(0, _maxBytes);
        }

        final doc = html_parser.parse(body);

        String? meta(String property) {
          final og = doc.querySelector('meta[property="$property"]');
          final ogContent = og?.attributes['content']?.trim();
          if (ogContent != null && ogContent.isNotEmpty) return ogContent;
          final tw = doc.querySelector('meta[name="$property"]');
          final twContent = tw?.attributes['content']?.trim();
          if (twContent != null && twContent.isNotEmpty) return twContent;
          return null;
        }

        final ogTitle = meta('og:title') ?? meta('twitter:title');
        final docTitle = doc.querySelector('title')?.text.trim();
        final title =
            (ogTitle != null && ogTitle.isNotEmpty) ? ogTitle : docTitle;

        final description = meta('og:description') ??
            meta('twitter:description') ??
            meta('description');

        var image = meta('og:image') ?? meta('twitter:image');
        if (image != null && image.isNotEmpty) {
          try {
            final imgUri = Uri.parse(image);
            if (!imgUri.hasScheme) {
              image = uri.resolve(image).toString();
            }
          } catch (_) {}
        }

        final siteName = meta('og:site_name');

        final preview = LinkPreview(
          url: url,
          title: title,
          description: description,
          image: image,
          siteName: siteName,
        );

        print('🔗 [Preview] 성공 $url '
            'title="${preview.title}" image="${preview.image != null}"');

        if (preview.isEmpty) return null;
        return preview;
      } catch (e) {
        final isLastAttempt = attempt == 1;
        print('🔗 [Preview] '
            '${isLastAttempt ? "실패 (최종)" : "실패 (재시도 예정)"} '
            '($url): $e');
        if (isLastAttempt) return null;
        await Future.delayed(const Duration(milliseconds: 500));
      } finally {
        client?.close(force: true);
      }
    }
    return null;
  }

  /// 캐시 비우기 (테스트용)
  static void clearCache() {
    _cache.clear();
  }
}

// ═══════════════════════════════════════════════════
// URL 추출 유틸
// ═══════════════════════════════════════════════════

final _urlRegex = RegExp(
  // 간단한 URL 매칭. http(s):// 시작 + 공백/줄바꿈 전까지.
  r'(https?:\/\/[^\s<>"]+)',
  caseSensitive: false,
);

/// 텍스트에서 URL 토큰들 추출
List<RegExpMatch> extractUrls(String text) {
  return _urlRegex.allMatches(text).toList();
}

/// 텍스트에서 첫 URL 추출 (미리보기용)
String? extractFirstUrl(String text) {
  final m = _urlRegex.firstMatch(text);
  if (m == null) return null;
  return m.group(0);
}