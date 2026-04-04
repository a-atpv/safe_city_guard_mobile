import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/websocket/websocket_service.dart';
import 'widgets/call_offer_sheet.dart';
import 'sos_alert_manager.dart';
import '../../main.dart'; // import rootNavigatorKey

final callOfferListenerProvider = Provider<CallOfferListener>((ref) {
  return CallOfferListener(ref);
});

class CallOfferListener {
  StreamSubscription? _subscription;

  CallOfferListener(Ref ref) {
    _startListening();
  }

  void _startListening() {
    debugPrint('CallOfferListener: Starting');
    _subscription = webSocketServiceProvider.messageStream.listen((message) {
      if (message['type'] == 'call_offer') {
        _handleCallOffer(message);
      }
    });
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

  void dispose() {
    _subscription?.cancel();
  }
}
