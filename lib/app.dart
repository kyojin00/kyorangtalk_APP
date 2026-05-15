import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/notifications/fcm_service.dart';
import 'core/security/app_lock_guard.dart';                  // ⭐ NEW
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/chat/models/chat_room_model.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/chat/screens/chat_room_screen.dart';
import 'features/friends/screens/friends_screen.dart';
import 'features/group_chat/models/group_room_model.dart';
import 'features/group_chat/providers/group_chat_provider.dart';
import 'features/group_chat/screens/group_chat_room_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'main.dart';
import 'shared/screens/main_screen.dart';
import 'shared/screens/splash_screen.dart';
import 'features/call/widgets/call_router.dart';

bool? _hasProfileCache;

Future<bool> _checkHasProfile() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return false;

  try {
    final data = await supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname')
        .eq('id', user.id)
        .maybeSingle();

    final has = data != null &&
        (data['nickname'] as String?)?.isNotEmpty == true;
    _hasProfileCache = has;
    return has;
  } catch (e) {
    print('프로필 체크 오류: $e');
    return false;
  }
}

class _AuthNotifier extends ChangeNotifier {
  final Ref ref;

  _AuthNotifier(this.ref) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) FcmService.saveTokenAfterLogin();

    Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      if (state.event == AuthChangeEvent.signedIn) {
        FcmService.saveTokenAfterLogin();
        _invalidateAllProviders();
        await _checkHasProfile();
      } else if (state.event == AuthChangeEvent.signedOut) {
        _invalidateAllProviders();
        _hasProfileCache = null;
      }
      notifyListeners();
    });
  }

  void _invalidateAllProviders() {
    try {
      ref.invalidate(myProfileProvider);
      ref.invalidate(friendsProvider);
      ref.invalidate(pendingRequestsProvider);
      ref.invalidate(sentRequestsProvider);
      ref.invalidate(chatRoomsProvider);
      ref.invalidate(groupRoomsProvider);
      ref.invalidate(openRoomsProvider);
    } catch (e) {
      print('Provider invalidate 오류: $e');
    }
  }
}

final _authNotifierProvider = Provider<_AuthNotifier>((ref) {
  return _AuthNotifier(ref);
});

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(_authNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    navigatorKey: navigatorKey,
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final session    = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      final loc        = state.matchedLocation;
      final fullPath   = state.uri.toString();
      final uriPath    = state.uri.path;
      final uriScheme  = state.uri.scheme;
      final uriHost    = state.uri.host;

      // ⭐ 디버그 로그 (어떤 URI가 들어오는지 확인용)
      print('🔗 [Router redirect] '
          'matched=$loc | full=$fullPath | '
          'scheme=$uriScheme | host=$uriHost | path=$uriPath');

      // ⭐⭐⭐ 딥링크 URI 가로채기
      // path에 'join' 단어가 들어가거나 scheme/host가 우리 딥링크면 → /main으로
      final isDeepLink =
          uriScheme == 'kyorangtalk' ||
          uriHost == 'open.kyorang.com' ||
          uriPath.contains('/join/') ||
          loc.contains('/join/') ||
          fullPath.contains('://join');

      if (isDeepLink) {
        print('🔗 [Router] 딥링크 가로채기 → ${isLoggedIn ? "/main" : "/login"}');
        return isLoggedIn ? '/main' : '/login';
      }

      if (loc == '/') return null;

      if (!isLoggedIn) {
        if (loc != '/login') return '/login';
        return null;
      }

      if (loc == '/login') {
        final hasProfile = _hasProfileCache ?? await _checkHasProfile();
        return hasProfile ? '/main' : '/onboarding';
      }

      if (loc.startsWith('/main')) {
        final hasProfile = _hasProfileCache ?? await _checkHasProfile();
        if (!hasProfile) return '/onboarding';
      }

      if (loc == '/onboarding') {
        final hasProfile = _hasProfileCache ?? await _checkHasProfile();
        if (hasProfile) return '/main';
      }

      return null;
    },
    // ⭐ 라우트 매칭 실패 시 (페이지 낫 파운드 예외 가로채기)
    onException: (context, state, router) {
      print('🔗 [Router] onException: ${state.uri}');
      // 딥링크인지 확인
      final uri = state.uri;
      final isDeepLink = uri.scheme == 'kyorangtalk' ||
          uri.host == 'open.kyorang.com' ||
          uri.path.contains('/join/');
      if (isDeepLink) {
        // DeepLinkService가 알아서 처리할 거니까 그냥 메인으로
        final session = Supabase.instance.client.auth.currentSession;
        router.go(session != null ? '/main' : '/login');
      } else {
        router.go('/');
      }
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen()),
      GoRoute(
        path: '/main',
        builder: (_, state) {
          final index = state.extra as int? ?? 0;
          return MainScreen(initialIndex: index);
        },
        routes: [
          GoRoute(
            path: 'chat/:roomId',
            builder: (_, state) {
              final room = state.extra as ChatRoomModel;
              return ChatRoomScreen(room: room);
            },
          ),
          GoRoute(
            path: 'group/:roomId',
            builder: (_, state) {
              final room = state.extra as GroupRoomModel;
              return GroupChatRoomScreen(room: room);
            },
          ),
        ],
      ),
    ],
  );
});

class KyorangTalkApp extends ConsumerWidget {
  const KyorangTalkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: '교랑톡',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final isDark = brightness == Brightness.dark;
        AppTheme.setDark(isDark);

        // ⭐ CallRouter를 최상위 Stack에 배치 — 어디서든 들어오는 통화 감지
        // ⭐ AppLockGuard로 감싸서 라이프사이클 가드 (백그라운드 → 잠금)
        return KeyedSubtree(
          key: ValueKey<bool>(isDark),
          child: AppLockGuard(
            child: Stack(
              children: [
                child ?? const SizedBox(),
                const CallRouter(),
              ],
            ),
          ),
        );
      },
    );
  }
}

void markProfileCreated() {
  _hasProfileCache = true;
}