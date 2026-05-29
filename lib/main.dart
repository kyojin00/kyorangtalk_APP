import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/notifications/fcm_service.dart';
import 'core/services/deep_link_service.dart';
import 'features/call/models/call_model.dart';
import 'features/call/screens/active_call_screen.dart';
import 'features/call/services/call_kit_service.dart';
import 'features/call/services/call_service.dart';
import 'features/chat/models/chat_room_model.dart';
import 'features/chat/services/message_cache_service.dart';
import 'features/chat/services/revenuecat_service.dart';
import 'features/voice_room/screens/voice_room_screen.dart';
import 'features/voice_room/services/voice_room_notification_service.dart';
import 'features/voice_room/services/voice_room_service.dart';
import 'firebase_options.dart';


final navigatorKey = GlobalKey<NavigatorState>();

// 알림 탭 pending
String? pendingRoomId;
String? pendingSenderId;
CallInvite? pendingAcceptedCall;

// 보이스 룸 푸시 알림 탭 pending
String? pendingVoiceRoomId;
String? pendingVoiceRoomTitle;

// 포그라운드 서비스 알림 탭 stream 구독
StreamSubscription<String>? _voiceRoomTapSub;

const String _sentryDsn = 'https://744b3e255fa47b21eb265d1fba18f0dc@o4511373790478336.ingest.us.sentry.io/4511373797359616';

// ═══════════════════════════════════════════════════
// ⭐ Release 빌드 에러 시각화
// 회색 화면 대신 실제 에러 메시지를 표시해 디버깅 가능하게 함
// Sentry에도 자동 보고
// ═══════════════════════════════════════════════════
void _setupErrorHandlers() {
  // Flutter framework 에러 → 화면에 보이는 위젯 트리 안에서 발생한 에러
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // 에러 자동 보고
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );

    return Material(
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFFCA5A5), size: 48),
              const SizedBox(height: 16),
              const Text(
                '화면을 표시하는 중 오류가 발생했어요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '아래 내용을 캡쳐해서 개발자에게 알려주세요',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exception:',
                          style: TextStyle(
                            color: const Color(0xFFFCA5A5),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          details.exception.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                        if (details.stack != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Stack trace:',
                            style: TextStyle(
                              color: const Color(0xFFFCA5A5),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            details.stack.toString(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 10,
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // 이전 화면으로 돌아가기
                    final context = navigatorKey.currentContext;
                    if (context != null && Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '이전 화면으로',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Flutter framework 에러 추가 핸들링 (콘솔 출력 + Sentry)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );
  };

  // 비동기 처리되지 않은 에러 (Dart 레벨)
  PlatformDispatcher.instance.onError = (error, stack) {
    Sentry.captureException(error, stackTrace: stack);
    debugPrint('🔴 [PlatformDispatcher] $error');
    return true;
  };
}

void main() async {
  if (_sentryDsn.isEmpty) {
    await _runWithoutSentry();
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.environment = kDebugMode ? 'debug' : 'production';
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
        options.enableAutoSessionTracking = true;
        options.enableAutoNativeBreadcrumbs = true;
        options.sendDefaultPii = false;
        options.debug = kDebugMode;

        options.beforeSend = (event, hint) {
          final exception = event.throwable;
          if (exception != null) {
            final message = exception.toString();
            if (message.contains('AgoraRtcException(-3')) return null;
            if (message.contains('SocketException')) return null;
            if (message.contains('TimeoutException')) return null;
            if (message.contains('User canceled')) return null;
          }
          return event;
        };
      },
      appRunner: () async {
        await _initializeApp();
        // ⭐ ErrorWidget 설정 (Sentry 초기화 후)
        _setupErrorHandlers();
        runApp(
          DefaultAssetBundle(
            bundle: SentryAssetBundle(),
            child: const ProviderScope(child: KyorangTalkApp()),
          ),
        );
        _scheduleBackgroundInit();
      },
    );
  }
}

Future<void> _runWithoutSentry() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeApp();
  _setupErrorHandlers();
  runApp(const ProviderScope(child: KyorangTalkApp()));
  _scheduleBackgroundInit();
}

// ═══════════════════════════════════════════════════
// ⭐ Stage 1: 필수 초기화 (화면 그리기 전 반드시 필요)
//   - Firebase + Supabase + Hive만 병렬 실행
//   - 합산 ~500ms (가장 느린 한 개만큼만)
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

  // ⭐ 핵심 의존성 병렬 초기화 (직렬 → 병렬: ~1초 → ~500ms)
  //   - Firebase, Supabase, MessageCache(Hive)는 다른 서비스가 의존하므로
  //     화면 그리기 전 반드시 끝나야 함
  await Future.wait([
    _initFirebase(),
    _initSupabaseAndCache(),
  ]);

  // ⭐ Auth 리스너는 일찍 등록 (signedIn/signedOut 이벤트 놓치지 않게)
  //   콜백 내부의 무거운 작업은 비동기라 화면을 막지 않음
  Supabase.instance.client.auth.onAuthStateChange.listen(_handleAuthChange);
}

// ═══════════════════════════════════════════════════
// ⭐ Stage 2: 첫 프레임 그린 후 백그라운드 초기화
//   - RevenueCat, FCM, CallKit, 보이스 룸 알림
//   - 모두 병렬 fire-and-forget → 화면 표시를 막지 않음
// ═══════════════════════════════════════════════════
void _scheduleBackgroundInit() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    DeepLinkService.instance.init(navigatorKey: navigatorKey);

    _initBackgroundServices();

    // pending 보이스 룸 알림 처리
    if (pendingVoiceRoomId != null) {
      _navigateToVoiceRoom(pendingVoiceRoomId!, pendingVoiceRoomTitle);
      pendingVoiceRoomId = null;
      pendingVoiceRoomTitle = null;
    }
  });
}

void _initBackgroundServices() {
  // 토큰 워밍업 (fire-and-forget)
  CallService.instance.warmupTokenFunction();

  if (!kIsWeb) {
    // 모두 fire-and-forget, 병렬 실행
    _initVoiceRoomNotification();
    _initRevenueCat();
    _initFcm();
    _initCallKit();
  }
}

// ═══════════════════════════════════════════════════
// 개별 초기화 함수
// ═══════════════════════════════════════════════════
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase 초기화 성공');
  } catch (e, st) {
    print('🔴 Firebase 초기화 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }
}

Future<void> _initSupabaseAndCache() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 40),
  );
  try {
    await MessageCacheService.init();
    print('✅ Supabase + MessageCache 초기화 성공');
  } catch (e, st) {
    print('🔴 MessageCache 초기화 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }
}

Future<void> _initVoiceRoomNotification() async {
  try {
    await VoiceRoomNotificationService.initialize();
    print('✅ 보이스 룸 알림 초기화 성공');
  } catch (e) {
    print('🔴 보이스 룸 알림 초기화 오류: $e');
  }

  // 알림 탭 stream 구독
  _voiceRoomTapSub?.cancel();
  _voiceRoomTapSub =
      VoiceRoomService.instance.notificationTapStream.listen((voiceRoomId) {
    print('🎙️ 알림 탭 → 보이스 룸 이동: $voiceRoomId');
    _navigateToVoiceRoom(voiceRoomId, null);
  });
}

Future<void> _initRevenueCat() async {
  try {
    await RevenueCatService.initialize();
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      await RevenueCatService.login(currentUser.id);
    }
    print('✅ RevenueCat 초기화 성공');
  } catch (e, st) {
    print('🔴 RevenueCat 초기화 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }
}

Future<void> _initFcm() async {
  try {
    await FcmService.initialize();
    print('✅ FCM 초기화 성공');

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

    FcmService.setOnVoiceRoomTap((voiceRoomId, title) async {
      print('🎙️ 보이스 룸 푸시 알림 탭! voiceRoomId: $voiceRoomId');
      final supabase = Supabase.instance.client;

      int retry = 0;
      while (supabase.auth.currentUser == null && retry < 6) {
        await Future.delayed(const Duration(milliseconds: 500));
        retry++;
      }

      if (supabase.auth.currentUser == null) {
        pendingVoiceRoomId = voiceRoomId;
        pendingVoiceRoomTitle = title;
        return;
      }

      await _navigateToVoiceRoom(voiceRoomId, title);
    });
  } catch (e, st) {
    print('🔴 FCM 초기화 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }
}

Future<void> _initCallKit() async {
  try {
    CallKitService.instance.initialize();
    _registerCallKitCallbacks();

    final activeCall = await CallKitService.instance.getActiveCall();
    if (activeCall != null) {
      print('🟢 앱 종료 상태에서 통화 받기로 시작: ${activeCall.callId}');
      CallService.instance.prefetchToken(activeCall.callId);
      // post-frame이라 navigator context 있음 → 바로 처리
      _handleCallAccept(activeCall);
    }

    print('✅ CallKit 초기화 성공');
  } catch (e, st) {
    print('🔴 CallKit 초기화 오류: $e');
    await Sentry.captureException(e, stackTrace: st);
  }
}

// ═══════════════════════════════════════════════════
// Auth 변경 처리
// ═══════════════════════════════════════════════════
Future<void> _handleAuthChange(AuthState data) async {
  final event = data.event;
  final session = data.session;

  if (event == AuthChangeEvent.signedIn && session?.user != null) {
    if (!kIsWeb) {
      // RevenueCat가 아직 init 안 됐을 수 있으니 try-catch
      try {
        await RevenueCatService.login(session!.user.id);
      } catch (e) {
        print('RevenueCat login 오류 (init 전일 수 있음): $e');
      }
    }
    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: session!.user.id));
    });
  } else if (event == AuthChangeEvent.signedOut) {
    if (!kIsWeb) {
      try {
        await RevenueCatService.logout();
      } catch (e) {
        print('RevenueCat logout 오류: $e');
      }
    }
    // 로그아웃 시 캐시 전체 삭제 (다른 계정 데이터 노출 방지)
    try {
      await MessageCacheService.clearAll();
    } catch (e) {
      print('MessageCache clearAll 오류: $e');
    }
    Sentry.configureScope((scope) {
      scope.setUser(null);
    });
  } else if (event == AuthChangeEvent.userUpdated && session?.user != null) {
    if (!kIsWeb) {
      try {
        await RevenueCatService.login(session!.user.id);
      } catch (e) {
        print('RevenueCat userUpdated 오류: $e');
      }
    }
  }
}

void _registerCallKitCallbacks() {
  CallKitService.instance.onAccept = (CallInvite invite) {
    print('📞 통화 받기: ${invite.callId}');
    CallService.instance.prefetchToken(invite.callId);
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

  CallService.instance.prefetchToken(invite.callId);

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

Future<void> _navigateToVoiceRoom(String voiceRoomId, String? title) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) {
    print('🔴 보이스 룸 이동 — 유저 없음');
    return;
  }

  int retry = 0;
  while (navigatorKey.currentContext == null && retry < 6) {
    await Future.delayed(const Duration(milliseconds: 500));
    retry++;
  }

  final context = navigatorKey.currentContext;
  if (context == null) {
    print('🔴 보이스 룸 이동 — context 없음');
    return;
  }

  print('🎙️ 보이스 룸 이동: $voiceRoomId');

  bool alreadyOnVoiceRoom = false;
  Navigator.popUntil(context, (route) {
    if (route.settings.name == '/voice_room') {
      alreadyOnVoiceRoom = true;
    }
    return true;
  });

  if (alreadyOnVoiceRoom) {
    print('🎙️ 이미 보이스 룸 화면에 있음');
    return;
  }

  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/voice_room'),
      builder: (_) => VoiceRoomScreen(
        voiceRoomId: voiceRoomId,
        title: title,
      ),
    ),
  );
}

Future<void> handlePendingNotification() async {
  if (pendingRoomId != null && pendingSenderId != null) {
    final roomId = pendingRoomId!;
    final senderId = pendingSenderId!;
    pendingRoomId = null;
    pendingSenderId = null;
    await _navigateToChatRoom(roomId, senderId);
  }

  if (pendingVoiceRoomId != null) {
    final voiceRoomId = pendingVoiceRoomId!;
    final title = pendingVoiceRoomTitle;
    pendingVoiceRoomId = null;
    pendingVoiceRoomTitle = null;
    await _navigateToVoiceRoom(voiceRoomId, title);
  }
}