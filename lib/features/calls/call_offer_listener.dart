import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/websocket/websocket_service.dart';
import '../../core/app_colors.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/router/app_router.dart'; // import rootNavigatorKey
import 'widgets/call_offer_sheet.dart';
import 'sos_alert_manager.dart';
import 'call_controller.dart';
import '../home/shift_controller.dart';

final callOfferListenerProvider = Provider<CallOfferListener>((ref) {
  return CallOfferListener(ref);
});

class CallOfferListener {
  StreamSubscription? _subscription;
  final Ref _ref;

  CallOfferListener(this._ref) {
    _startListening();
    
    // Register FCM callback for terminal notification taps
    PushNotificationService().setOnTerminalStatusReceived((status, callId) {
      _handleTerminalStatus(status, callId);
    });
  }

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
      if (statusLower == 'completed' ||
          statusLower == 'cancelled_by_user' ||
          statusLower == 'cancelled_by_system') {
        final callId = int.tryParse(callIdStr) ?? 0;
        
        // Check if this matches our active call
        final activeCall = _ref.read(callControllerProvider).activeCall;
        final activeCallId = activeCall?['id']?.toString();
        
        if (activeCallId != null && activeCallId == callIdStr) {
          debugPrint('CallOfferListener: Terminal status update received for active call: $status');
          _handleTerminalStatus(statusLower, callId);
          return;
        }
      }
    }

    final statusVal = message['status'];
    // Original behavior for non-terminal status updates:
    if (statusVal != 'pending' && statusVal != 'offered') {
      debugPrint('CallOfferListener: Call status updated to $statusVal, closing offer if open');
      _closeOfferSheet();
    }
  }

  void _handleCallCancelled(Map<String, dynamic> message) {
    debugPrint('CallOfferListener: Call cancelled by user: $message');
    _closeOfferSheet();
  }

  void _closeOfferSheet() {
    SOSAlertManager.stopAlert();
    final context = rootNavigatorKey.currentContext;
    if (context != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleCallOffer(Map<String, dynamic> offer) {
    debugPrint('CallOfferListener: Handling offer: $offer');

    // Trigger Sound/Vibration
    SOSAlertManager.triggerAlert();

    // Show Bottom Sheet using the root navigator key
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        isDismissible: false, // Force reaction to SOS
        builder: (context) => CallOfferSheet(offer: offer),
      ).then((_) {
        // Stop alert when sheet is closed (accepted or declined)
        SOSAlertManager.stopAlert();
      });
    } else {
      debugPrint('CallOfferListener: Context is null, cannot show bottom sheet');
    }
  }

  void _handleTerminalStatus(String status, int callId) async {
    debugPrint('CallOfferListener: Handling terminal status $status for call $callId');
    
    // 1. Stop alert/siren sounds and vibration
    SOSAlertManager.stopAlert();
    
    // 2. Clear active call state locally
    _ref.read(callControllerProvider.notifier).clearActiveCall();
    
    // 3. Trigger backend refresh to sync list of available/active calls
    _ref.read(callControllerProvider.notifier).refresh();
    
    // 4. Update shift status to ensure the guard is marked ready/online
    _ref.read(shiftControllerProvider.notifier).checkCurrentShift();

    // 5. Navigate back to map screen and show dialog
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      // Pop all overlays/dialogs/sheets
      while (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      // Navigate to /home
      GoRouter.of(context).go('/home');
      
      // Delay showing the dialog slightly to allow navigation transition to complete
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (context.mounted) {
        final isCancellation = status == 'cancelled_by_user' || status == 'cancelled_by_system';
        String messageText = 'Вызов завершен';
        if (status == 'cancelled_by_user') {
          messageText = 'Пользователь отменил вызов.';
        } else if (status == 'cancelled_by_system') {
          messageText = 'Вызов был отменен системой.';
        } else if (status == 'completed') {
          messageText = 'Вызов завершен, отчет отправлен.';
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
                  isCancellation ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: isCancellation ? AppColors.danger : AppColors.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  isCancellation ? 'Вызов отменен' : 'Вызов завершен',
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
  }

  void dispose() {
    _subscription?.cancel();
  }
}
