import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../core/app_colors.dart';
import '../home/shift_controller.dart';
import '../calls/call_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  LatLng _currentPosition = const LatLng(51.1282, 71.4307); // fallback: Astana
  String _currentAddress = 'Определение адреса...';
  bool _locationLoaded = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        // Use fallback coordinates
        _reverseGeocode(_currentPosition);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _locationLoaded = true;
        });
        _mapController.move(_currentPosition, 16.5);
        _reverseGeocode(_currentPosition);
      }
    } catch (e) {
      // Fallback to default
      _reverseGeocode(_currentPosition);
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&addressdetails=1&accept-language=ru',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'SafeCityGuard/1.0',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'];
        String label = '';

        // Build a concise address: street + house number, or road
        final road = address?['road'] ?? address?['street'] ?? '';
        final house = address?['house_number'] ?? '';

        if (road.isNotEmpty) {
          label = road;
          if (house.isNotEmpty) label += ' $house';
        } else {
          // fallback to display_name
          label = data['display_name']?.split(',')?.take(2)?.join(', ') ?? '';
        }

        if (mounted && label.isNotEmpty) {
          setState(() => _currentAddress = label);
        }
      }
    } catch (_) {
      // Keep the fallback text
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftState = ref.watch(shiftControllerProvider);
    final isOnDuty = shiftState.isOnline;
    final isLoadingShift = shiftState.isLoading;
    final callState = ref.watch(callControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ─── Shift Toggle ───
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.divider, width: 1),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleOption(
                        label: 'Офлайн',
                        isSelected: !isOnDuty && !isLoadingShift,
                        onTap: isLoadingShift
                            ? null
                            : () {
                                if (isOnDuty) {
                                  ref
                                      .read(shiftControllerProvider.notifier)
                                      .toggleShift(false);
                                }
                              },
                      ),
                      _buildToggleOption(
                        label: 'На смене',
                        isSelected: isOnDuty && !isLoadingShift,
                        isAccent: true,
                        isLoading: isLoadingShift,
                        onTap: isLoadingShift
                            ? null
                            : () {
                                if (!isOnDuty) {
                                  ref
                                      .read(shiftControllerProvider.notifier)
                                      .toggleShift(true);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ─── Map Card ───
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 280,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _currentPosition,
                          initialZoom: _locationLoaded ? 16.5 : 15.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.safecity.guard',
                          ),
                          // Current location marker
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _currentPosition,
                                width: 44,
                                height: 44,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(
                                        color: AppColors.info,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.navigation,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Address label
                      Positioned(
                        top: 100,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.cardDark.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _currentAddress,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ─── Calls Section ───
              const Text(
                'Вызовы:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Call cards — only from API
              if (callState.activeCall != null)
                _buildCallCard(callState.activeCall!)
              else
                _buildEmptyCallsState(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Toggle Button ───
  Widget _buildToggleOption({
    required String label,
    required bool isSelected,
    bool isAccent = false,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isAccent ? AppColors.accent : AppColors.cardLight)
              : AppColors.cardDark.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(26),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  // ─── Call Card (from API) ───
  Widget _buildCallCard(Map<String, dynamic> call) {
    final name = call['caller']?['name'] ?? 'Неизвестный';
    final address = call['address'] ?? 'Нет адреса';
    final callId = call['id'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.6),
                      AppColors.info.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
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
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.phone, color: AppColors.info, size: 22),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                ref.read(callControllerProvider.notifier).acceptCall(callId);
                context.push('/incident-detail');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Принять',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty state (no active calls) ───
  Widget _buildEmptyCallsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(
            Icons.phone_disabled_outlined,
            size: 48,
            color: AppColors.textHint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Нет активных вызовов',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
