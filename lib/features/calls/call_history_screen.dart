import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import 'call_repository.dart';

final callHistoryRepoProvider = Provider((ref) => CallRepository());

final callHistoryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.read(callHistoryRepoProvider);
  return repo.getCallHistory();
});

class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHistory = ref.watch(callHistoryProvider);

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
                      'История вызовов',
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
            const Divider(height: 1, color: AppColors.divider),

            // Content
            Expanded(
              child: asyncHistory.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: AppColors.textHint.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text(
                        'Не удалось загрузить историю',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(callHistoryProvider),
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
                          Icon(Icons.history,
                              size: 64,
                              color: AppColors.textHint.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          const Text(
                            'Нет вызовов в истории',
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
                      ref.invalidate(callHistoryProvider);
                    },
                    color: AppColors.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: calls.length,
                      itemBuilder: (context, index) {
                        final call = calls[index];
                        return _HistoryCard(call: call);
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

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> call;

  const _HistoryCard({required this.call});

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

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Завершён';
      case 'cancelled_by_user':
        return 'Отменён пользователем';
      case 'cancelled_by_system':
        return 'Отменён системой';
      case 'accepted':
        return 'Принят';
      case 'en_route':
        return 'В пути';
      case 'arrived':
        return 'Прибыл';
      case 'created':
      case 'searching':
      case 'offer_sent':
        return 'Ожидание';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = call['status'] ?? 'unknown';
    final createdAt = call['created_at'] ?? '';
    final durationSec = call['duration_seconds'];
    final callId = call['id'];

    // Format date
    String formattedDate = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        formattedDate =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      } catch (_) {
        formattedDate = createdAt;
      }
    }

    // Format duration
    String durationStr = '';
    if (durationSec != null) {
      final minutes = (durationSec as int) ~/ 60;
      durationStr = '$minutes мин';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _statusColor(status),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _statusColor(status).withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вызов #$callId',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (durationStr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          durationStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _statusColor(status),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
