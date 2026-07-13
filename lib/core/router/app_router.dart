import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/incidents/incident_detail_screen.dart';
import '../../features/calls/call_report_screen.dart';
import '../../features/calls/call_history_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/support/support_screen.dart';
import '../../features/navigation/navigation_screen.dart';
import '../../features/calls/active_call_screen.dart';
import '../../features/calls/call_chat_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final isLoggedIn = ref.watch(authControllerProvider.select((s) => s.isLoggedIn));

  return GoRouter(
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
          final email = state.extra is String ? state.extra as String : '';
          return OtpScreen(email: email);
        },
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/incident-detail',
        builder: (context, state) {
          final callData = state.extra as Map<String, dynamic>?;
          return IncidentDetailScreen(callData: callData);
        },
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
      GoRoute(
        path: '/navigation',
        builder: (context, state) {
          final callId = state.extra as int? ?? 0;
          return NavigationScreen(callId: callId);
        },
      ),
      GoRoute(
        path: '/call-chat',
        builder: (context, state) {
          final callId = state.extra as String? ?? '';
          return CallChatScreen(callId: callId);
        },
      ),
    ],
    redirect: (context, state) {
      final currentPath = state.uri.toString();
      log('Redirect: isLoggedIn=$isLoggedIn, path=$currentPath');

      final publicPaths = ['/login', '/otp'];
      final isPublic = publicPaths.any((p) => currentPath.startsWith(p));

      if (!isLoggedIn && !isPublic) {
        log('Redirect: Not logged in, sending to /login');
        return '/login';
      }
      if (isLoggedIn && (currentPath == '/login' || currentPath == '/')) {
        log('Redirect: Logged in, sending to /home');
        return '/home';
      }

      return null;
    },
  );
});
