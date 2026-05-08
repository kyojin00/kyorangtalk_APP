import 'app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'core/config/supabase_config.dart';
import 'core/notifications/fcm_service.dart';
import 'core/services/deep_link_service.dart';                  // ⭐ NEW
import 'features/chat/models/chat_room_model.dart';
import 'features/chat/services/revenuecat_service.dart';
import 'firebase_options.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// 알림 탭으로 열릴 때 pending roomId 저장
String? pendingRoomId;
String? pendingSenderId;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // 세로 모드 고정 (모바일만 — 웹에서는 오류 발생)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // Firebase 초기화 — options 필수 (특히 웹)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase 초기화 성공');
  } catch (e) {
    print('Firebase 초기화 오류: $e');
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 40),
  );

  // ⭐ RevenueCat 초기화 (모바일에서만, 웹에서는 미지원)
  if (!kIsWeb) {
    try {
      await RevenueCatService.initialize();

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        await RevenueCatService.login(currentUser.id);
      }
    } catch (e) {
      print('RevenueCat 초기화 오류: $e');
    }
  }

  // ⭐ Supabase 인증 상태 변화 감지 → RC 로그인/로그아웃 자동 동기화
  if (!kIsWeb) {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session?.user != null) {
        await RevenueCatService.login(session!.user.id);
      } else if (event == AuthChangeEvent.signedOut) {
        await RevenueCatService.logout();
      } else if (event == AuthChangeEvent.userUpdated &&
          session?.user != null) {
        await RevenueCatService.login(session!.user.id);
      }
    });
  }

  // FCM 초기화
  try {
    await FcmService.initialize();
    print('FCM 초기화 성공');
  } catch (e) {
    print('FCM 초기화 오류: $e');
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
      print('유저 없음 - pending 저장');
      pendingRoomId   = roomId;
      pendingSenderId = senderId;
      return;
    }

    await _navigateToChatRoom(roomId, senderId);
  });

  runApp(const ProviderScope(child: KyorangTalkApp()));

  // ⭐⭐⭐ 딥링크 서비스 시작 (앱 빌드 후)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    DeepLinkService.instance.init(navigatorKey: navigatorKey);
  });
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
  } catch (e) {
    print('채팅방 이동 오류: $e');
  }
}

// splash_screen 또는 chat_list에서 pending 처리용
Future<void> handlePendingNotification() async {
  if (pendingRoomId != null && pendingSenderId != null) {
    final roomId   = pendingRoomId!;
    final senderId = pendingSenderId!;
    pendingRoomId   = null;
    pendingSenderId = null;
    await _navigateToChatRoom(roomId, senderId);
  }
}