class ApiConstants {
  static const String baseUrl = 'https://safe-city-back-7c8ed50edd7d.herokuapp.com/api/v1/';
  static const String guardBaseUrl = '${baseUrl}guard/';
  static const String wsGuardUrl = 'wss://safe-city-back-7c8ed50edd7d.herokuapp.com/api/v1/ws/guard';
  
  // Auth (relative to guardBaseUrl)
  static const String login = 'auth/request-otp';
  static const String verifyOtp = 'auth/verify-otp';
  static const String refresh = 'auth/refresh';
  
  // Device (relative to guardBaseUrl)
  static const String registerDevice = 'device/register';
  static const String unregisterDevice = 'device/'; // + device_token

  // Profile (relative to guardBaseUrl)
  static const String me = 'me';
  static const String settings = 'settings';

  // Shift & Location (relative to guardBaseUrl)
  static const String currentShift = 'shift/current';
  static const String startShift = 'shift/start';
  static const String endShift = 'shift/end';
  static const String location = 'location';

  // Calls (relative to guardBaseUrl)
  static const String activeCall = 'call/active';
  static const String availableCalls = 'calls/available';
  static const String callHistory = 'history';
  // Note: These require ID insertion:
  // call/{id}/accept, call/{id}/decline, etc.
  static String acceptCall(String id) => 'call/$id/accept';
  static String declineCall(String id) => 'call/$id/decline';
  static String enRoute(String id) => 'call/$id/en-route';
  static String arrived(String id) => 'call/$id/arrived';
  static String completeCall(String id) => 'call/$id/complete';
  static String redirectCall(String id) => 'call/$id/redirect';
  static String callReport(String id) => 'call/$id/report';
  static String callMessages(String id) => 'call/$id/messages';
  static String sendMessage(String id) => 'call/$id/message';

  // Notifications (relative to baseUrl)
  static const String notifications = 'notifications';
  static String readNotification(int id) => 'notifications/$id/read';
  static const String readAllNotifications = 'notifications/read-all';

  // Support (relative to baseUrl)
  static const String supportContacts = 'support/contacts';
  static const String supportFaq = 'support/faq';

  // Routes (relative to guardBaseUrl)
  static String routeToCall(int id) => 'route/call/$id';
  static const String routeEta = 'route/eta';
  static const String routeCalculate = 'route/calculate';
}


