import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/websocket/websocket_service.dart';
import '../../core/app_colors.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/notifications/sos_siren.dart';
import '../../core/router/app_router.dart'; // import rootNavigatorKey
import 'widgets/call_offer_sheet.dart';
import 'call_controller.dart';
import '../home/shift_controller.dart';

final callOfferListenerProvider = Provider<CallOfferListener>((ref) {
  return CallOfferListener(ref);
});

class CallOfferListener {
  StreamSubscription? _subscription;
  AppLifecycleListener? _lifecycleListener;
  final Ref _ref;
  bool _isOfferSheetOpen = false;

  CallOfferListener(this._ref) {
    _startListening();

    // Register FCM callback for terminal notification taps
    PushNotificationService().setOnTerminalStatusReceived((status, callId) {
      handleTerminalStatus(status, callId);
    });

    // An SOS push landing while the app is on screen: the siren is already
    // playing, make sure the call list catches up even if the socket is down.
    PushNotificationService().setOnSosPush((_) {
      _ref.read(callControllerProvider.notifier).refresh();
    });

    // The guard tapped the siren notification and the app came forward — hand
    // the alert over from the system notification to the in-app siren so it
    // keeps sounding until they accept or decline.
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!_isOfferSheetOpen) return;
        SosSiren.cancelNotification();
        SosSiren.startInApp();
      },
    );
  }

  bool get _isAppInForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _startListening() {
    debugPrint('CallOfferListener: Starting');
    _subscription = webSocketServiceProvider.messageStream.listen((message) {
      final type = message['type'];
      if (type == 'call_offer') {
        _handleCallOffer(message);
      } else if (type == 'call_cancelled') {
        _handleCallCancelled(message);
      } else if (type == 'call_status_update') {
        _handleStatusUpdate(message);
      }
    });
  }

  void _handleStatusUpdate(Map<String, dynamic> message) {
    final status = message['status']?.toString();
    final callIdStr = message['call_id']?.toString();
    
    if (status != null && callIdStr != null) {
      final statusLower = status.toLowerCase();
      
      // Check if this matches our active call
      final activeCall = _ref.read(callControllerProvider).activeCall;
      final activeCallId = activeCall?['id']?.toString();
      final isOurActiveCall = activeCallId != null && activeCallId == callIdStr;

      if (statusLower == 'completed' ||
          statusLower == 'cancelled_by_user' ||
          statusLower == 'cancelled_by_system') {
        final callId = int.tryParse(callIdStr) ?? 0;
        
        if (isOurActiveCall) {
          debugPrint('CallOfferListener: Terminal status update received for active call: $status');
          handleTerminalStatus(statusLower, callId);
          return;
        }
      }

      // Original behavior for non-terminal status updates:
      if (statusLower != 'pending' && statusLower != 'offered') {
        if (isOurActiveCall) {
          debugPrint('CallOfferListener: Non-terminal status update for our active call: $statusLower. Ignoring to prevent incorrect pop.');
          return;
        }
        debugPrint('CallOfferListener: Call status updated to $statusLower, closing offer if open');
        _closeOfferSheet();
      }
    }
  }

  void _handleCallCancelled(Map<String, dynamic> message) {
    debugPrint('CallOfferListener: Call cancelled by user: $message');
    _closeOfferSheet();
  }

  void _closeOfferSheet() {
    SosSiren.stop();
    if (!_isOfferSheetOpen) return;
    final context = rootNavigatorKey.currentContext;
    if (context != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      _isOfferSheetOpen = false;
    }
  }

  void _handleCallOffer(Map<String, dynamic> offer) {
    debugPrint('CallOfferListener: Handling offer: $offer');

    if (_isAppInForeground) {
      // On screen: the app owns the siren. Drop any notification the FCM
      // background isolate may have already posted so the two do not overlap.
      SosSiren.cancelNotification();
      SosSiren.startInApp();
    } else {
      // Свёрнуто, но сокет жив. Раньше сирена здесь доверялась FCM-пушу, и это
      // была дыра: приёмник firebase_messaging решает «на переднем ли плане
      // приложение» по importance процесса и на свёрнутом приложении регулярно
      // ошибается — тогда сообщение уезжает в LiveData под неактивного
      // наблюдателя и лежит там до возобновления активности, а следующий пуш
      // его ещё и перезаписывает (наблюдали на Samsung A51, 2026-08-12).
      // Поэтому уведомление с сиреной постим сами, не дожидаясь пуша: id
      // фиксированный, так что если фоновый обработчик всё же дорисует своё,
      // оно заменит это же уведомление, а не задвоит сирену.
      unawaited(SosSiren.showNotification(
        title: '🚨 Экстренный вызов!',
        body: offer['address']?.toString() ??
            'Нужна ваша помощь. Откройте приложение и примите вызов.',
        payload: jsonEncode(offer),
      ));
    }

    // Show Bottom Sheet using the root navigator key
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      _isOfferSheetOpen = true;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        isDismissible: false, // Force reaction to SOS
        builder: (context) => CallOfferSheet(offer: offer),
      ).then((_) {
        _isOfferSheetOpen = false;
        // Stop alert when sheet is closed (accepted or declined)
        SosSiren.stop();
      });
    } else {
      debugPrint('CallOfferListener: Context is null, cannot show bottom sheet');
    }
  }

  void handleTerminalStatus(String status, int callId) async {
    debugPrint('CallOfferListener: Handling terminal status $status for call $callId');
    
    // 1. Stop alert/siren sounds and vibration
    SosSiren.stop();
    
    // 2. Clear active call state locally
    _ref.read(callControllerProvider.notifier).clearActiveCall();
    
    // 3. Trigger backend refresh to sync list of available/active calls
    _ref.read(callControllerProvider.notifier).refresh();
    
    // 4. Update shift status to ensure the guard is marked ready/online
    _ref.read(shiftControllerProvider.notifier).checkCurrentShift();
 
    // 5. Navigate back to map screen and show dialog
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        // Pop all overlays/dialogs/sheets (only PopupRoutes, keeping PageRoutes intact)
        Navigator.of(context).popUntil((route) => route is PageRoute);
        
        // Navigate to /home
        GoRouter.of(context).go('/home');
        
        // Delay showing the dialog slightly to allow navigation transition to complete
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (context.mounted) {
          final isCancellation = status == 'cancelled_by_user' || status == 'cancelled_by_system';
          final isRedirect = status == 'redirected';
          String messageText = 'Вызов завершен';
          if (status == 'cancelled_by_user') {
            messageText = 'Пользователь отменил вызов.';
          } else if (status == 'cancelled_by_system') {
            messageText = 'Вызов был отменен системой.';
          } else if (status == 'completed') {
            messageText = 'Вызов завершен, отчет отправлен.';
          } else if (status == 'redirected') {
            messageText = 'Вызов перенаправлен другой службе.';
          }

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isCancellation
                        ? Icons.warning_amber_rounded
                        : isRedirect
                            ? Icons.alt_route
                            : Icons.check_circle_outline,
                    color: isCancellation ? AppColors.danger : AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isCancellation
                        ? 'Вызов отменен'
                        : isRedirect
                            ? 'Вызов перенаправлен'
                            : 'Вызов завершен',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Text(
                messageText,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _lifecycleListener?.dispose();
  }
}
