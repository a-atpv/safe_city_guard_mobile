import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
import '../call_repository.dart';
import '../call_controller.dart';
import '../../../core/router/app_router.dart';

class CallOfferSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> offer;

  const CallOfferSheet({super.key, required this.offer});

  @override
  ConsumerState<CallOfferSheet> createState() => _CallOfferSheetState();
}

class _CallOfferSheetState extends ConsumerState<CallOfferSheet> {
  bool _isAccepting = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.offer['user'] ?? {};
    final callId = widget.offer['call_id'];
    
    var address = widget.offer['address'] as String?;
    if (address == null || address.trim().isEmpty || address == 'Unknown location' || address == 'Адрес не определен') {
      final lat = widget.offer['latitude'];
      final lng = widget.offer['longitude'];
      if (lat != null && lng != null) {
        address = '${lat is num ? lat.toStringAsFixed(6) : lat}, ${lng is num ? lng.toStringAsFixed(6) : lng}';
      } else {
        address = 'Адрес не определен';
      }
    }

    var fullName = user['full_name'] as String?;
    if (fullName == null || fullName.trim().isEmpty || fullName == 'Пользователь') {
      fullName = user['phone'] as String?;
      if (fullName == null || fullName.trim().isEmpty) {
        fullName = 'Анонимный пользователь';
      }
    }

    final distance = widget.offer['distance_km'] ?? 0.0;
    final eta = widget.offer['eta_minutes'] ?? 0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F36).withValues(alpha: 0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull Bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // SOS Title
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'НОВЫЙ ВЫЗОВ SOS!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // User Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      backgroundImage: user['image_url'] != null
                          ? NetworkImage(user['image_url'])
                          : null,
                      child: user['image_url'] == null
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user['phone'] ?? 'Нет номера',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Details
              Row(
                children: [
                  _buildDetailIcon(Icons.location_on, Colors.orangeAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildDetailRow(
                        Icons.social_distance, '$distance км', 'Дистанция'),
                  ),
                  Expanded(
                    child:
                        _buildDetailRow(Icons.timer, '$eta мин', 'Прибытие'),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isAccepting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Отклонить',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isAccepting ? null : () => _acceptCall(context, callId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                        shadowColor: Colors.redAccent.withValues(alpha: 0.5),
                      ),
                      child: _isAccepting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Принять SOS',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildDetailRow(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _acceptCall(BuildContext context, dynamic callId) async {
    if (_isAccepting) return;
    setState(() {
      _isAccepting = true;
    });

    try {
      final repo = CallRepository();
      await repo.acceptCall(callId.toString());

      // Refresh the call controller state so that the active call is updated locally
      await ref.read(callControllerProvider.notifier).refresh();

      if (context.mounted) {
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          Navigator.pop(context); // Close the bottom sheet safely
        }
      }
      
      // Navigate to active call screen using the root context to prevent errors if the sheet was popped
      final rootContext = rootNavigatorKey.currentContext;
      if (rootContext != null && rootContext.mounted) {
        final int id = callId is int ? callId : int.tryParse(callId.toString()) ?? 0;
        GoRouter.of(rootContext).push('/active-call', extra: id);
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }
}
