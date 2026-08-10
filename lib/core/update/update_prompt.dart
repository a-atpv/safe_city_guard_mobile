import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_constants.dart';
import '../app_colors.dart';

/// Сообщает, что в сторе появилась новая версия.
///
/// Спрашивает у бэкенда (`GET /app/update`), не устарела ли текущая сборка, и
/// показывает диалог. Два режима, и разница между ними принципиальная:
///
///  * **обновление доступно** — предложение, которое можно отложить. Повторно
///    напомним не раньше чем через сутки: охранник открывает приложение в
///    начале смены, и баннер при каждом запуске он просто научится закрывать
///    не глядя;
///  * **обновление обязательно** — сборка несовместима с сервером, диалог не
///    закрывается. Включается сменой `APP_GUARD_MIN_VERSION` на бэкенде и
///    выключает ГБР из работы, пока та не обновится, — поэтому только тогда,
///    когда старая сборка действительно не может принять вызов.
///
/// Любая ошибка (нет сети, бэкенд молчит) проходит молча: проверка версии —
/// вежливость, а не функция, и мешать запуску она не имеет права.
class UpdatePrompt {
  UpdatePrompt._();

  static const String _snoozeKey = 'update_prompt_snoozed_at';
  static const Duration _snoozeFor = Duration(hours: 24);

  /// Один раз за запуск: экран может пересоздаваться, диалог — нет.
  static bool _askedThisLaunch = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (_askedThisLaunch) return;
    _askedThisLaunch = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final response = await Dio().get(
        '${ApiConstants.baseUrl}app/update',
        queryParameters: {
          'version': info.version,
          'app': 'guard',
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final data = response.data;
      if (data is! Map) return;

      final isRequired = data['update_required'] == true;
      final isAvailable = data['update_available'] == true;
      if (!isRequired && !isAvailable) return;
      if (!isRequired && await _snoozed()) return;

      if (!context.mounted) return;
      await _show(
        context,
        latestVersion: data['latest_version']?.toString() ?? '',
        storeUrl: data['store_url']?.toString() ?? '',
        message: data['message']?.toString(),
        isRequired: isRequired,
      );
    } catch (_) {
      // Молча: обновление подождёт до следующего запуска.
    }
  }

  static Future<bool> _snoozed() async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_snoozeKey);
    if (at == null) return false;
    final shownAt = DateTime.fromMillisecondsSinceEpoch(at);
    return DateTime.now().difference(shownAt) < _snoozeFor;
  }

  static Future<void> _snooze() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> _show(
    BuildContext context, {
    required String latestVersion,
    required String storeUrl,
    required bool isRequired,
    String? message,
  }) {
    final text = message?.isNotEmpty == true
        ? message!
        : 'Вышла новая версия приложения.';

    return showDialog<void>(
      context: context,
      barrierDismissible: !isRequired,
      builder: (ctx) => PopScope(
        // Обязательное обновление не обойти системной кнопкой «назад».
        canPop: !isRequired,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: AppColors.accent, size: 28),
              const SizedBox(width: 8),
              Text(
                isRequired ? 'Нужно обновиться' : 'Вышло обновление',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: Text(
            latestVersion.isEmpty ? text : '$text\n\nВерсия $latestVersion.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            if (!isRequired)
              TextButton(
                onPressed: () {
                  _snooze();
                  Navigator.pop(ctx);
                },
                child: const Text(
                  'Позже',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ElevatedButton(
              onPressed: storeUrl.isEmpty
                  ? null
                  : () => launchUrl(
                        Uri.parse(storeUrl),
                        mode: LaunchMode.externalApplication,
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Обновить', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
