import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/group_chat/models/group_room_model.dart';
import '../../features/group_chat/providers/group_chat_provider.dart';
import '../../features/group_chat/widgets/password_dialog.dart';

// ═══════════════════════════════════════════════════
// 🔗 딥링크 서비스
// ═══════════════════════════════════════════════════
//
// 받는 링크:
//   1) 채팅방 초대
//      https://open.kyorang.com/join/{INVITE_CODE}
//      kyorangtalk://join/{INVITE_CODE}
//
//   2) 이메일 인증 완료
//      https://open.kyorang.com/verified?access_token=...&refresh_token=...
//      kyorangtalk://verified?access_token=...&refresh_token=...
//
// 사용:
//   main.dart의 main() 끝부분에서:
//     DeepLinkService.instance.init(
//       navigatorKey: navigatorKey,
//       container: ProviderScope.containerOf(...),
//     );
// ═══════════════════════════════════════════════════

class DeepLinkService {
  DeepLinkService._();
  static final instance = DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  GlobalKey<NavigatorState>? _navigatorKey;
  ProviderContainer? _container;

  Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    ProviderContainer? container,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;
    _container = container;

    // 1) cold start (앱 종료 상태에서 링크로 실행)
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        print('🔗 [DeepLink] initial: $initial');
        Future.delayed(const Duration(milliseconds: 800), () {
          _handle(initial);
        });
      }
    } catch (e) {
      print('🔗 [DeepLink] initial 실패: $e');
    }

    // 2) running 중에 링크 받기
    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        print('🔗 [DeepLink] stream: $uri');
        _handle(uri);
      },
      onError: (e) {
        print('🔗 [DeepLink] stream 에러: $e');
      },
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }

  // ═══════════════════════════════════════════════════
  // URL 분기
  // ═══════════════════════════════════════════════════
  void _handle(Uri uri) {
    final segments = uri.pathSegments;

    // ⭐⭐⭐ 이메일 인증 완료
    //   https://open.kyorang.com/verified?access_token=...&refresh_token=...
    //   kyorangtalk://verified?access_token=...&refresh_token=...
    final isVerifiedHttps = uri.host == 'open.kyorang.com' &&
        segments.isNotEmpty &&
        segments[0] == 'verified';
    final isVerifiedScheme = uri.scheme == 'kyorangtalk' && uri.host == 'verified';

    if (isVerifiedHttps || isVerifiedScheme) {
      final accessToken = uri.queryParameters['access_token'];
      final refreshToken = uri.queryParameters['refresh_token'];

      print('🔗 [DeepLink] 이메일 인증 완료 수신');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processVerified(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      });
      return;
    }

    // 채팅방 초대
    String? code;

    // https://open.kyorang.com/join/CODE
    if (uri.host == 'open.kyorang.com' &&
        segments.length >= 2 &&
        segments[0] == 'join') {
      code = segments[1];
    }
    // kyorangtalk://join/CODE
    else if (uri.scheme == 'kyorangtalk' && uri.host == 'join') {
      if (segments.isNotEmpty) {
        code = segments[0];
      }
    }

    if (code == null || code.isEmpty) {
      print('🔗 [DeepLink] 코드 추출 실패: $uri');
      return;
    }

    final cleanCode = code.trim();
    print('🔗 [DeepLink] 코드: $cleanCode');

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('🔗 [DeepLink] 미로그인 — 처리 스킵');
      _showSnack('로그인 후 다시 시도해주세요');
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processInvite(cleanCode);
    });
  }

  BuildContext? get _ctx => _navigatorKey?.currentContext;

  // ═══════════════════════════════════════════════════
  // ⭐ 이메일 인증 완료 처리
  // ═══════════════════════════════════════════════════
  Future<void> _processVerified({
    String? accessToken,
    String? refreshToken,
  }) async {
    final ctx = _ctx;
    if (ctx == null) {
      print('🔗 [DeepLink] context 없음 (verified)');
      return;
    }

    final messenger = ScaffoldMessenger.of(ctx);

    if (refreshToken == null || refreshToken.isEmpty) {
      print('🔗 [DeepLink] refresh_token 없음');
      messenger.showSnackBar(
        const SnackBar(content: Text('인증 정보가 누락되었어요')),
      );
      return;
    }

    try {
      // Supabase 세션 복원 → 자동 로그인
      await Supabase.instance.client.auth.setSession(refreshToken);

      print('🔗 [DeepLink] 세션 복원 성공');

      messenger.showSnackBar(
        const SnackBar(content: Text('이메일 인증이 완료되었어요')),
      );

      // 홈으로 이동
      final ctx2 = _ctx;
      if (ctx2 != null) {
        ctx2.go('/main');
      }
    } catch (e) {
      print('🔗 [DeepLink] 세션 복원 실패: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('인증 처리에 실패했어요. 다시 로그인해주세요')),
      );
      final ctx2 = _ctx;
      if (ctx2 != null) {
        ctx2.go('/login');
      }
    }
  }

  Future<void> _processInvite(String code) async {
    final ctx = _ctx;
    if (ctx == null) {
      print('🔗 [DeepLink] context 없음');
      return;
    }

    final messenger = ScaffoldMessenger.of(ctx);

    // 비번 보호 여부
    final needsPw = await codeRequiresPassword(code);

    String? errorMsg;

    if (needsPw) {
      while (true) {
        final ctx2 = _ctx;
        if (ctx2 == null) return;

        final password = await showRoomPasswordDialog(
          ctx2,
          roomName: '초대받은 채팅방',
          errorMessage: errorMsg,
        );
        if (password == null) return;

        final result = await joinByCodeWithPassword(
          inviteCode: code,
          password: password,
        );
        if (result == JoinResult.ok) break;
        if (result == JoinResult.notFound) {
          messenger.showSnackBar(
            const SnackBar(content: Text('유효하지 않은 초대코드예요')),
          );
          return;
        }
        if (result == JoinResult.wrongPassword) {
          errorMsg = '비밀번호가 틀렸어요';
          continue;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('입장에 실패했어요')),
        );
        return;
      }
    } else {
      final result = await joinByCodeWithPassword(
        inviteCode: code,
        password: null,
      );
      if (result != JoinResult.ok) {
        if (result == JoinResult.notFound) {
          messenger.showSnackBar(
            const SnackBar(content: Text('유효하지 않은 초대코드예요')),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('입장에 실패했어요')),
          );
        }
        return;
      }
    }

    // provider 새로고침
    _container?.invalidate(groupRoomsProvider);
    _container?.invalidate(openRoomsProvider);

    // 방 전체 정보 조회 → GroupRoomModel 만들어서 extra로 점프
    try {
      final r = await Supabase.instance.client
          .from('kyorangtalk_group_rooms')
          .select('*')
          .eq('invite_code', code)
          .maybeSingle();

      if (r == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('채팅방에 입장했어요! (목록에서 확인하세요)')),
        );
        return;
      }

      final tagsRaw = r['tags'] as List<dynamic>?;
      final tags = tagsRaw?.map((t) => t as String).toList() ?? [];

      final room = GroupRoomModel(
        id:            r['id'] as String,
        name:          r['name'] as String,
        description:   r['description'] as String?,
        avatarUrl:     r['avatar_url'] as String?,
        createdBy:     r['created_by'] as String,
        inviteCode:    r['invite_code'] as String? ?? '',
        memberCount:   r['member_count'] as int? ?? 0,
        roomType:      r['room_type'] as String? ?? 'group',
        lastMessage:   r['last_message'] as String?,
        lastMessageAt: r['last_message_at'] != null
            ? DateTime.parse(r['last_message_at'] as String).toLocal()
            : null,
        category:      r['category'] as String? ?? '일반',
        createdAt:     r['created_at'] as String,
        myRole:        'member',
        likeCount:     r['like_count'] as int? ?? 0,
        tags:          tags,
        hasPassword:   r['password_hash'] != null,
      );

      final ctx3 = _ctx;
      if (ctx3 != null) {
        // ⭐ extra로 GroupRoomModel 같이 넘김 - 라우터가 기대하는 형식
        ctx3.push('/main/group/${room.id}', extra: room);
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('채팅방에 입장했어요!')),
      );
    } catch (e) {
      print('🔗 [DeepLink] 방 정보 조회 실패: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('채팅방에 입장했어요! (목록에서 확인하세요)')),
      );
    }
  }

  void _showSnack(String msg) {
    final ctx = _ctx;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ═══════════════════════════════════════════════════
  // 공유용 링크 빌더
  // ═══════════════════════════════════════════════════
  static String buildInviteUrl(String inviteCode) {
    return 'https://open.kyorang.com/join/$inviteCode';
  }
}