import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;

import 'core/app_theme.dart';
import 'core/app_colors.dart';
import 'core/location/location_service.dart';
import 'core/map_config.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/router/app_router.dart';
import 'features/auth/auth_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Register the background-geolocation headless task so the heartbeat keeps
  // reporting a stationary guard's position even after the app is killed. Must
  // run before runApp and reference a top-level, vm:entry-point function.
  bg.BackgroundGeolocation.registerHeadlessTask(backgroundGeolocationHeadlessTask);

  // 1. Initialize Firebase with timeout and options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));
    log('Firebase initialized successfully');
  } catch (e) {
    log('ERROR: Firebase initialization failed or timed out: $e');
  }

  // 2. Initialize Push Notifications with timeout
  try {
    final pushService = PushNotificationService();
    await pushService.initialize().timeout(const Duration(seconds: 10));
    log('PushNotificationService initialized successfully');
  } catch (e) {
    log('ERROR: Push Notifications failed to initialize or timed out: $e');
  }

  // Set status bar and navigation bar styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark, // For iOS
      systemNavigationBarColor: Color(0xFF0D1530),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Lock orientation to portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Релиз без ключа подложки — след в логе устройства, а не молчание: именно
  // так в TestFlight уехала сборка с неоплаченными тайлами и серой картой.
  MapConfig.warnIfUnlicensed();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInitialized = ref.watch(
      authControllerProvider.select((s) => s.isInitialized),
    );
    
    // Show splash while checking stored tokens
    if (!isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _SplashScreen(),
      );
    }

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      routerConfig: router,
      title: 'Safe City Guard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child ?? const SizedBox.shrink(),
      ),
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
