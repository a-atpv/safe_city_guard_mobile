import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../auth/auth_controller.dart';
import 'profile_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileControllerProvider);
    final profile = profileState.profile;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: profileState.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : profileState.error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Ошибка: ${profileState.error}', style: TextStyle(color: AppColors.danger)),
                        TextButton(
                          onPressed: () => ref.read(profileControllerProvider.notifier).fetchData(),
                          child: const Text('Повторить', style: TextStyle(color: AppColors.accent)),
                        )
                      ],
                    ),
                  )
                : SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Text(
                'Профиль',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 32),

              // Avatar
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent.withValues(alpha: 0.6),
                      AppColors.info.withValues(alpha: 0.6),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.person, color: Colors.white, size: 44),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                profile?['name'] ?? 'Имя не указано',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Охранник',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Info cards
              _buildInfoTile(Icons.email_outlined, 'Email', profile?['email'] ?? ''),
              _buildInfoTile(Icons.phone_outlined, 'Телефон', profile?['phone'] ?? 'Не указан'),
              _buildInfoTile(Icons.badge_outlined, 'ID', profile?['id']?.toString() ?? ''),
              _buildInfoTile(Icons.calendar_today_outlined, 'Дата регистрации', profile?['created_at']?.substring(0, 10) ?? ''),

              const SizedBox(height: 24),


              _buildNavTile(
                context,
                Icons.headset_mic_outlined,
                'Поддержка',
                () => context.push('/support'),
              ),

              const SizedBox(height: 16),

              // Logout
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(authControllerProvider.notifier).logout();
                    context.go('/login');
                  },
                  icon: const Icon(Icons.logout, color: AppColors.danger, size: 20),
                  label: const Text(
                    'Выйти',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                const Icon(Icons.chevron_right,
                    color: AppColors.textHint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
