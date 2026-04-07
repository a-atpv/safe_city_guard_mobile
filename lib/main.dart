import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/app_theme.dart';
import 'core/app_colors.dart';
import 'core/notifications/push_notification_service.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/home/home_screen.dart';
import 'features/incidents/incident_detail_screen.dart';
import 'features/calls/call_report_screen.dart';
import 'features/calls/call_history_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/support/support_screen.dart';
import 'features/calls/active_call_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    
    // Initialize Push Notifications
    final pushService = PushNotificationService();
    await pushService.initialize();
    
    log('Firebase and Push Notifications initialized');
  } catch (e) {
    log('Firebase initialization failed: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D1530),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInitialized = ref.watch(
      authControllerProvider.select((s) => s.isInitialized),
    );
    final isLoggedIn = ref.watch(
      authControllerProvider.select((s) => s.isLoggedIn),
    );

    // Show splash while checking stored tokens
    if (!isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _SplashScreen(),
      );
    }

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: isLoggedIn ? '/home' : '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/otp',
          builder: (context, state) {
            final email =
                state.extra is String ? state.extra as String : '';
            return OtpScreen(email: email);
          },
        ),
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/incident-detail',
          builder: (context, state) => const IncidentDetailScreen(),
        ),
        GoRoute(
          path: '/call-report',
          builder: (context, state) {
            final callId = state.extra as String? ?? '';
            return CallReportScreen(callId: callId);
          },
        ),
        GoRoute(
          path: '/call-history',
          builder: (context, state) => const CallHistoryScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/support',
          builder: (context, state) => const SupportScreen(),
        ),
        GoRoute(
          path: '/active-call',
          builder: (context, state) {
            final callId = state.extra as int? ?? 0;
            return ActiveCallScreen(callId: callId);
          },
        ),
      ],
      redirect: (context, state) {
        final currentPath = state.uri.toString();

        final publicPaths = ['/login', '/otp'];
        final isPublic = publicPaths.any((p) => currentPath.startsWith(p));

        if (!isLoggedIn && !isPublic) return '/login';
        if (isLoggedIn && currentPath == '/login') return '/home';

        return null;
      },
    );

    return MaterialApp.router(
      routerConfig: router,
      title: 'Safe City Guard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );
  }
}
