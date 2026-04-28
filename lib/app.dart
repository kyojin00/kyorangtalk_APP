import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/notifications/fcm_service.dart';
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
        // ✅ 1. AppTheme._isDark 동기화
        final brightness = Theme.of(context).brightness;
        final isDark = brightness == Brightness.dark;
        AppTheme.setDark(isDark);
        
        // ✅ 2. KeyedSubtree로 brightness 바뀌면 전체 트리 강제 재생성
        return KeyedSubtree(
          key: ValueKey<bool>(isDark),
          child: child ?? const SizedBox(),
        );
      },
    );
  }
}

void markProfileCreated() {
  _hasProfileCache = true;
}