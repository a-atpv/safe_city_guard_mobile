class ApiConstants {
  static const String baseUrl = 'https://safe-city-back-7c8ed50edd7d.herokuapp.com/api/v1/';
  static const String guardBaseUrl = '${baseUrl}guard/';
  static const String wsGuardUrl = 'wss://safe-city-back-7c8ed50edd7d.herokuapp.com/api/v1/ws/guard';
  
  // Auth endpoints
  static const String login = 'auth/request-otp';
  static const String verifyOtp = 'auth/verify-otp';
  static const String refresh = 'auth/refresh';
  
  // Device registration
  static const String registerDevice = 'device/register';
  static const String unregisterDevice = 'device/'; // + device_token
}
