import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../profile/profile_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Local state for UI responsiveness, initialized from profile in build, but better to just use controller
  bool _pushNotifications = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = false;
  String _language = 'Русский';
  bool _isInit = false;

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileControllerProvider);
    final settings = profileState.settings;

    if (!_isInit && settings != null) {
      _pushNotifications = settings['notifications_enabled'] ?? true;
      _soundEnabled = settings['call_sound_enabled'] ?? true;
      _vibrationEnabled = settings['vibration_enabled'] ?? false;
      _language = settings['language'] ?? 'Русский';
      _isInit = true;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios,
                        color: AppColors.textPrimary, size: 20),
                  ),
                  const Expanded(
                    child: Text(
                      'Настройки',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Notifications section
                    const Text(
                      'Уведомления',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildSwitchTile(
                      Icons.notifications_outlined,
                      'Push-уведомления',
                      _pushNotifications,
                      (v) {
                        setState(() => _pushNotifications = v);
                        ref.read(profileControllerProvider.notifier).updateSettings({'notifications_enabled': v});
                      },
                    ),
                    _buildSwitchTile(
                      Icons.volume_up_outlined,
                      'Звук',
                      _soundEnabled,
                      (v) {
                        setState(() => _soundEnabled = v);
                        ref.read(profileControllerProvider.notifier).updateSettings({'call_sound_enabled': v});
                      },
                    ),
                    _buildSwitchTile(
                      Icons.vibration,
                      'Вибрация',
                      _vibrationEnabled,
                      (v) {
                        setState(() => _vibrationEnabled = v);
                        ref.read(profileControllerProvider.notifier).updateSettings({'vibration_enabled': v});
                      },
                    ),

                    const SizedBox(height: 24),

                    // Language
                    const Text(
                      'Приложение',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.language,
                              color: AppColors.textSecondary, size: 22),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              'Язык',
                              style: TextStyle(
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _language,
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 14,
                              ),
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  color: AppColors.accent, size: 20),
                              items: ['Русский', 'Қазақша', 'English']
                                  .map((l) => DropdownMenuItem(
                                        value: l,
                                        child: Text(l),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _language = v);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoTile(
                        Icons.info_outline, 'Версия', '1.0.0'),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
      IconData icon, String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
