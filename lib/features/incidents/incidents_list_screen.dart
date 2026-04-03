import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../calls/call_repository.dart';

final incidentsRepoProvider = Provider((ref) => CallRepository());

/// Calls list shown on the "Incidents" tab.
/// Uses the same loading/error/refresh pattern as `CallHistoryScreen`,
/// but keeps the incidents card design.
final incidentsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.read(incidentsRepoProvider);
  return repo.getCallHistory(limit: 50, offset: 0);
});

class IncidentsListScreen extends ConsumerWidget {
  const IncidentsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncIncidents = ref.watch(incidentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Вызовы',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Incidents list
            Expanded(
              child: asyncIncidents.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48,
                          color:
                              AppColors.textHint.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text(
                        'Не удалось загрузить вызовы',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(incidentsProvider),
                        child: const Text('Повторить',
                            style: TextStyle(color: AppColors.accent)),
                      ),
                    ],
                  ),
                ),
                data: (data) {
                  final calls = (data['calls'] as List?) ?? [];

                  if (calls.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 64,
                              color:
                                  AppColors.textHint.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          const Text(
                            'Нет вызовов',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(incidentsProvider);
                    },
                    color: AppColors.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: calls.length,
                      itemBuilder: (context, index) {
                        final call = calls[index] as Map<String, dynamic>;
                        return _IncidentCard(
                          call: call,
                          onTap: () => context.push('/incident-detail'),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final Map<String, dynamic> call;
  final VoidCallback onTap;

  const _IncidentCard({required this.call, required this.onTap});

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.accent;
      case 'cancelled_by_user':
      case 'cancelled_by_system':
        return AppColors.warning;
      case 'accepted':
      case 'en_route':
      case 'arrived':
        return AppColors.info;
      default:
        return AppColors.danger;
    }
  }

  String _timeFromCreatedAt(String createdAt) {
    if (createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final callerName = (call['caller']?['name'] as String?)?.trim();
    final name = (callerName == null || callerName.isEmpty)
        ? 'Неизвестный'
        : callerName;

    final category = (call['category'] as String?)?.trim();
    final type = (category == null || category.isEmpty) ? 'Вызов' : category;

    final createdAt = (call['created_at'] as String?) ?? '';
    final time = _timeFromCreatedAt(createdAt);

    final status = (call['status'] as String?) ?? 'unknown';
    final statusColor = _statusColor(status);

    final address =
        (call['location']?['address'] as String?)?.trim() ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        statusColor.withValues(alpha: 0.7),
                        statusColor.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (time.isNotEmpty)
                            Text(
                              time,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type,
                        style: TextStyle(
                          fontSize: 13,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            address,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
