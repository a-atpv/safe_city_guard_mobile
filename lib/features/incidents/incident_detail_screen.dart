import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_colors.dart';
import '../calls/call_controller.dart';

class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callControllerProvider);
    final call = callState.activeCall;

    if (call == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
          ),
          title: const Text('Нет активного вызова', style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
        ),
        body: const Center(
          child: Text('В данный момент нет активных вызовов', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final lat = call['location']?['latitude'] ?? 51.1282;
    final lng = call['location']?['longitude'] ?? 71.4307;
    final status = call['status'] ?? 'pending';
    final callId = call['id'].toString();

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
                      'Детали вызова',
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
                    // Caller card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.accent.withValues(alpha: 0.7),
                                  AppColors.info.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                (call['caller']?['name'] ?? 'А')[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  call['caller']?['name'] ?? 'Неизвестный',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  call['caller']?['phone'] ?? 'Нет телефона',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Phone button
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.phone,
                                  color: AppColors.accent, size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mini map
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 200,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(lat, lng),
                            initialZoom: 15.0,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.safecity.guard',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(lat, lng),
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.danger,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.danger
                                              .withValues(alpha: 0.5),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Info rows
                    _buildInfoRow(Icons.category_outlined, 'Тип', call['type'] ?? 'ЧС'),
                    _buildInfoRow(
                        Icons.location_on_outlined, 'Адрес', call['address'] ?? 'Координаты: $lat, $lng'),
                    _buildInfoRow(
                        Icons.access_time, 'Время', call['created_at']?.substring(11, 16) ?? ''),
                    _buildInfoRow(
                        Icons.info_outline, 'Статус', status,
                        valueColor: _getStatusColor(status)),

                    const SizedBox(height: 16),

                    if (call['description'] != null) ...[
                      // Description
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Описание',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              call['description'],
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Action buttons
                    if (status == 'pending') ...[
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton(
                                onPressed: () {
                                  ref.read(callControllerProvider.notifier).declineCall(callId);
                                  context.pop();
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: AppColors.danger, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text(
                                  'Отклонить',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: () {
                                  ref.read(callControllerProvider.notifier).acceptCall(callId);
                                },
                                child: const Text('Принять'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (status == 'accepted') ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(callControllerProvider.notifier).updateStatus(callId, 'en-route');
                          },
                          child: const Text('В пути'),
                        ),
                      ),
                    ] else if (status == 'en-route') ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(callControllerProvider.notifier).updateStatus(callId, 'arrived');
                          },
                          child: const Text('Прибыл'),
                        ),
                      ),
                    ] else if (status == 'arrived') ...[
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton(
                                onPressed: () =>
                                    context.push('/call-chat', extra: callId),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: AppColors.accent, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text(
                                  'Сообщение',
                                  style: TextStyle(color: AppColors.accent),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: () {
                                  ref.read(callControllerProvider.notifier).updateStatus(callId, 'complete');
                                  context.push('/call-report', extra: callId);
                                },
                                child: const Text('Завершить'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return AppColors.warning;
      case 'accepted': return AppColors.info;
      case 'en-route': return AppColors.info;
      case 'arrived': return AppColors.accent;
      default: return AppColors.textPrimary;
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
            Text(
              label,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
