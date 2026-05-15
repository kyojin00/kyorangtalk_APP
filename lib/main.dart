import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';            // ⭐ NEW
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/notifications/fcm_service.dart';
import 'core/services/deep_link_service.dart';
import 'features/call/models/call_model.dart';
import 'features/call/screens/active_call_screen.dart';
import 'features/call/services/call_kit_service.dart';
import 'features/chat/models/chat_room_model.dart';
import 'features/chat/services/revenuecat_service.dart';
import 'firebase_options.dart';
import 'core/security/app_lock_guard.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// 알림 탭 pending
String? pendingRoomId;
String? pendingSenderId;
CallInvite? pendingAcceptedCall;

// ⭐⭐⭐ Sentry DSN — 가입 후 발급받은 값으로 교체
//
// 위치: Sentry 프로젝트 → Settings → Client Keys (DSN)
// 형식: https://<key>@<org>.ingest.sentry.io/<project_id>
//
// 빈 문자열이면 Sentry 비활성화 (그냥 일반 runApp으로 실행)
const String _sentryDsn = 'https://744b3e255fa47b21eb265d1fba18f0dc@o4511373790478336.ingest.us.sentry.io/4511373797359616';   // ← 여기에 DSN 붙여넣기

void main() async {
  // SentryFlutter.init이 자체적으로 ensureInitialized 호출함
  // 하지만 명시적으로 한 번 더 호출해도 무해

  // ⭐ Sentry로 감싸서 main 실행
  // DSN이 비어 있으면 일반 모드로 실행
  if (_sentryDsn.isEmpty) {
    await _runWithoutSentry();
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;

        // 환경 구분 (디버그 vs 프로덕션)
        options.environment = kDebugMode ? 'debug' : 'production';

        // 성능 트레이싱 샘플 비율 (0.0 ~ 1.0)
        // 1.0이면 모든 트랜잭션 추적 (비용 ↑)
        // 0.1이면 10%만 추적
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;

        // 세션 추적
        options.enableAutoSessionTracking = true;

        // breadcrumb (사용자 액션 흔적) 자동 수집
        options.enableAutoNativeBreadcrumbs = true;

        // ⭐ 사용자 정보 자동 첨부
        options.sendDefaultPii = false;  // 개인정보 자동 전송 차단

        // 디버그 모드에서는 콘솔에 로그 출력
        options.debug = kDebugMode;

        // ⭐ 일부 에러 무시 (소음 줄이기)
        options.beforeSend = (event, hint) {
          final exception = event.throwable;
          if (exception != null) {
            final message = exception.toString();

            // Agora 비치명적 에러 무시
            if (message.contains('AgoraRtcException(-3')) return null;

            // 네트워크 일시 단절 무시
            if (message.contains('SocketException')) return null;
            if (message.contains('TimeoutException')) return null;

            // 사용자 취소 무시
            if (message.contains('User canceled')) return null;
          }
          return event;
        };
      },
      appRunner: () async {
        await _initializeApp();
        runApp(
          DefaultAssetBundle(
            // SentryAssetBundle로 asset 로드도 추적 (선택)
            bundle: SentryAssetBundle(),
            child: const ProviderScope(child: KyorangTalkApp()),
          ),
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          DeepLinkService.instance.init(navigatorKey: navigatorKey);

          if (pendingAcceptedCall != null) {
            _handleCallAccept(pendingAcceptedCall!);
            pendingAcceptedCall = null;
          }
        });
      },
    );
  }
}

// ═══════════════════════════════════════════════════
// Sentry 없이 실행 (DSN 미설정 시)
// ═══════════════════════════════════════════════════

Future<void> _runWithoutSentry() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeApp();
  runApp(const ProviderScope(child: KyorangTalkApp()));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    DeepLinkService.instance.init(navigatorKey: navigatorKey);

    if (pendingAcceptedCall != null) {
      _handleCallAccept(pendingAcceptedCall!);
      pendingAcceptedCall = null;
    }
  });
}

// ═══════════════════════════════════════════════════
// 앱 초기화 (Sentry 유무 공통)
// ═══════════════════════════════════════════════════

Future<void> _initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase 초기화 성공');
  } catch (e, st) {
    print('Firebase 초기화 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 40),
  );

  // RevenueCat
  if (!kIsWeb) {
    try {
      await RevenueCatService.initialize();
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        await RevenueCatService.login(currentUser.id);
      }
    } catch (e, st) {
      print('RevenueCat 초기화 오류: $e');
      await Sentry.captureException(e, stackTrace: st);
    }
  }

  // ⭐ Sentry에 유저 정보 등록 + 변화 감지
  Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
    final event = data.event;
    final session = data.session;

    if (event == AuthChangeEvent.signedIn && session?.user != null) {
      if (!kIsWeb) {
        await RevenueCatService.login(session!.user.id);
      }
      // ⭐ Sentry 유저 컨텍스트 등록 (개인정보 최소)
      Sentry.configureScope((scope) {
        scope.setUser(SentryUser(
          id: session!.user.id,
          // email/username은 sendDefaultPii=false이므로 제외 가능
        ));
      });
    } else if (event == AuthChangeEvent.signedOut) {
      if (!kIsWeb) {
        await RevenueCatService.logout();
      }
      // 유저 컨텍스트 제거
      Sentry.configureScope((scope) {
        scope.setUser(null);
      });
    } else if (event == AuthChangeEvent.userUpdated && session?.user != null) {
      if (!kIsWeb) {
        await RevenueCatService.login(session!.user.id);
      }
    }
  });

  // FCM
  try {
    await FcmService.initialize();
    print('FCM 초기화 성공');
  } catch (e, st) {
    print('FCM 초기화 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }

  // CallKit
  if (!kIsWeb) {
    try {
      CallKitService.instance.initialize();
      _registerCallKitCallbacks();

      final activeCall = await CallKitService.instance.getActiveCall();
      if (activeCall != null) {
        print('🟢 앱 종료 상태에서 통화 받기로 시작: ${activeCall.callId}');
        pendingAcceptedCall = activeCall;
      }

      print('CallKit 초기화 성공');
    } catch (e, st) {
      print('CallKit 초기화 오류: $e');
      await Sentry.captureException(e, stackTrace: st);
    }
  }

  // 알림 탭 콜백
  FcmService.setOnNotificationTap((roomId, senderId) async {
    print('알림 탭! roomId: $roomId, senderId: $senderId');
    final supabase = Supabase.instance.client;

    int retry = 0;
    while (supabase.auth.currentUser == null && retry < 6) {
      await Future.delayed(const Duration(milliseconds: 500));
      retry++;
    }

    final myId = supabase.auth.currentUser?.id;
    if (myId == null) {
      pendingRoomId = roomId;
      pendingSenderId = senderId;
      return;
    }

    await _navigateToChatRoom(roomId, senderId);
  });
}

// ═══════════════════════════════════════════════════
// CallKit 콜백
// ═══════════════════════════════════════════════════

void _registerCallKitCallbacks() {
  CallKitService.instance.onAccept = (CallInvite invite) {
    print('📞 통화 받기: ${invite.callId}');
    _handleCallAccept(invite);
  };

  CallKitService.instance.onDecline = (String callId) {
    print('📞 통화 거절: $callId');
    declineCallRpc(callId);
  };

  CallKitService.instance.onTimeout = (String callId) {
    print('📞 통화 부재중: $callId');
  };
}

Future<void> _handleCallAccept(CallInvite invite) async {
  final supabase = Supabase.instance.client;
  int retry = 0;
  while (supabase.auth.currentUser == null && retry < 6) {
    await Future.delayed(const Duration(milliseconds: 500));
    retry++;
  }

  if (supabase.auth.currentUser == null) {
    print('🔴 통화 받기 — 유저 없음');
    return;
  }

  retry = 0;
  while (navigatorKey.currentContext == null && retry < 6) {
    await Future.delayed(const Duration(milliseconds: 500));
    retry++;
  }

  final context = navigatorKey.currentContext;
  if (context == null) {
    print('🔴 통화 받기 — context 없음');
    return;
  }

  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ActiveCallScreen(
        callId: invite.callId,
        isVideo: invite.isVideo,
        isInitiator: false,
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 채팅방 이동
// ═══════════════════════════════════════════════════

Future<void> _navigateToChatRoom(String roomId, String senderId) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return;

  try {
    final roomData = await supabase
        .from('kyorangtalk_rooms')
        .select('*')
        .eq('id', roomId)
        .maybeSingle();

    if (roomData == null) {
      print('room 없음');
      return;
    }

    final partnerId = roomData['user1_id'] == myId
        ? roomData['user2_id'] as String
        : roomData['user1_id'] as String;

    final profile = await supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url')
        .eq('id', partnerId)
        .maybeSingle();

    if (profile == null) {
      print('profile 없음');
      return;
    }

    final room = ChatRoomModel(
      partnerId:       partnerId,
      partnerUsername: profile['nickname'] as String? ?? '',
      partnerName:     profile['nickname'] as String? ?? '알 수 없음',
      partnerAvatar:   profile['avatar_url'] as String?,
      lastMessage:     roomData['last_message'] as String? ?? '',
      lastTime:        DateTime.parse(
          roomData['last_message_at'] as String? ??
          roomData['created_at'] as String),
      unreadCount:     0,
      isSent:          false,
      roomId:          roomId,
      pinnedMessage:   roomData['pinned_message'] as String?,
    );

    int retry = 0;
    while (navigatorKey.currentContext == null && retry < 4) {
      await Future.delayed(const Duration(milliseconds: 500));
      retry++;
    }

    final context = navigatorKey.currentContext;
    if (context != null) {
      print('채팅방 이동: ${room.partnerName}');
      context.push('/main/chat/${room.roomId}', extra: room);
    } else {
      print('context 없음');
    }
  } catch (e, st) {
    print('채팅방 이동 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }
}

Future<void> handlePendingNotification() async {
  if (pendingRoomId != null && pendingSenderId != null) {
    final roomId = pendingRoomId!;
    final senderId = pendingSenderId!;
    pendingRoomId = null;
    pendingSenderId = null;
    await _navigateToChatRoom(roomId, senderId);
  }
}