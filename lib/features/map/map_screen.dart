import 'dart:convert';
import 'dart:async';
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
  LatLng _selectedPosition = const LatLng(51.1282, 71.4307);
  String _currentAddress = 'Определение адреса...';
  bool _locationLoaded = false;
  final MapController _mapController = MapController();
  Timer? _reverseGeocodeDebounce;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  @override
  void dispose() {
    _reverseGeocodeDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
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
        _selectedPosition = _currentPosition;
        _reverseGeocode(_selectedPosition);
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
          _selectedPosition = _currentPosition;
          _locationLoaded = true;
        });
        _mapController.move(_currentPosition, 16.5);
        _reverseGeocode(_selectedPosition);
      }
    } catch (e) {
      // Fallback to default
      _selectedPosition = _currentPosition;
      _reverseGeocode(_selectedPosition);
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

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    // When the user drags/zooms the map, treat the map CENTER as the selected location.
    if (!hasGesture) return;
    final center = camera.center;
    setState(() => _selectedPosition = center);

    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _reverseGeocode(center);
    });
  }

  void _zoomBy(double delta) {
    final cam = _mapController.camera;
    final nextZoom = (cam.zoom + delta).clamp(3.0, 19.0);
    _mapController.move(cam.center, nextZoom);
  }

  Future<void> _openFullScreenMap() async {
    final cam = _mapController.camera;
    final result = await Navigator.of(context).push<_FullScreenMapResult>(
      MaterialPageRoute(
        builder: (_) => _FullScreenMapScreen(
          initialCenter: _selectedPosition,
          initialZoom: cam.zoom,
          initialAddress: _currentAddress,
        ),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || result == null) return;
    setState(() {
      _selectedPosition = result.center;
      _currentAddress = result.address;
    });
    _mapController.move(result.center, result.zoom);
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
                          onPositionChanged: _onMapPositionChanged,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.safecity.guard',
                          ),
                          // GPS location marker (user position)
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
                      // Center pin (selected location). This stays in the middle while you pan the map.
                      const Center(
                        child: IgnorePointer(
                          child: Icon(
                            Icons.location_pin,
                            size: 44,
                            color: AppColors.danger,
                          ),
                        ),
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

                      // Zoom controls (right)
                      Positioned(
                        top: 14,
                        right: 12,
                        child: Column(
                          children: [
                            _MapControlButton(
                              icon: Icons.add,
                              onTap: () => _zoomBy(1),
                            ),
                            const SizedBox(height: 10),
                            _MapControlButton(
                              icon: Icons.remove,
                              onTap: () => _zoomBy(-1),
                            ),
                          ],
                        ),
                      ),

                      // Full screen (bottom-right)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _MapControlButton(
                          icon: Icons.fullscreen,
                          onTap: _openFullScreenMap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ─── Calls Section ───
              const Text(
                'Доступные вызовы:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              if (callState.isLoading)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.divider, width: 0.5),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                )
              else ...[
                // Show active call first if it exists
                if (callState.activeCall != null)
                  _buildCallCard(callState.activeCall!, isActive: true),

                // Show available calls
                if (callState.availableCalls.isNotEmpty)
                  ...callState.availableCalls.map((c) => _buildCallCard(c, isActive: false))
                else if (callState.activeCall == null)
                  _buildEmptyCallsState(),
              ],

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
  Widget _buildCallCard(Map<String, dynamic> call, {bool isActive = false}) {
    final name = call['caller']?['name'] ?? 'Неизвестный';
    final address = (call['address'] as String?) ??
        (call['location']?['address'] as String?) ??
        (call['latitude'] != null && call['longitude'] != null
            ? '${call['latitude']}, ${call['longitude']}'
            : 'Нет адреса');
    final callId = call['id'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? AppColors.accent.withValues(alpha: 0.5) : AppColors.divider,
          width: isActive ? 1.5 : 0.5,
        ),
        boxShadow: isActive ? [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isActive)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'ТЕКУЩИЙ ВЫЗОВ',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                      isActive ? AppColors.accent : AppColors.accent.withValues(alpha: 0.6),
                      isActive ? AppColors.info : AppColors.info.withValues(alpha: 0.6),
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
                if (!isActive) {
                  ref.read(callControllerProvider.notifier).acceptCall(callId);
                }
                final int id = int.tryParse(callId) ?? 0;
                context.push('/active-call', extra: id);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? AppColors.info : AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                isActive ? 'Перейти' : 'Принять',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardDark.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: AppColors.textPrimary, size: 22),
        ),
      ),
    );
  }
}

class _FullScreenMapResult {
  final LatLng center;
  final double zoom;
  final String address;

  const _FullScreenMapResult({
    required this.center,
    required this.zoom,
    required this.address,
  });
}

class _FullScreenMapScreen extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final String initialAddress;

  const _FullScreenMapScreen({
    required this.initialCenter,
    required this.initialZoom,
    required this.initialAddress,
  });

  @override
  State<_FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<_FullScreenMapScreen> {
  final MapController _controller = MapController();
  Timer? _debounce;
  LatLng _center = const LatLng(0, 0);
  String _address = 'Определение адреса...';

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _address = widget.initialAddress;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    setState(() => _center = camera.center);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      // Just keep the label responsive; no hard failure if reverse geocode fails.
      final next = await _reverseGeocode(camera.center);
      if (!mounted || next == null) return;
      setState(() => _address = next);
    });
  }

  void _zoomBy(double delta) {
    final cam = _controller.camera;
    final nextZoom = (cam.zoom + delta).clamp(3.0, 19.0);
    _controller.move(cam.center, nextZoom);
  }

  Future<String?> _reverseGeocode(LatLng pos) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&addressdetails=1&accept-language=ru',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'SafeCityGuard/1.0',
      });
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      final address = data['address'];

      final road = address?['road'] ?? address?['street'] ?? '';
      final house = address?['house_number'] ?? '';
      if (road is String && road.isNotEmpty) {
        var label = road;
        if (house is String && house.isNotEmpty) label += ' $house';
        return label;
      }
      final display = data['display_name'];
      if (display is String && display.isNotEmpty) {
        return display.split(',').take(2).join(', ');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _submit() {
    final cam = _controller.camera;
    Navigator.of(context).pop(
      _FullScreenMapResult(center: _center, zoom: cam.zoom, address: _address),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: widget.initialCenter,
                initialZoom: widget.initialZoom,
                onPositionChanged: _onPositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.safecity.guard',
                ),
              ],
            ),
            const Center(
              child: IgnorePointer(
                child: Icon(
                  Icons.location_pin,
                  size: 48,
                  color: AppColors.danger,
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _MapControlButton(
                icon: Icons.close,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  _MapControlButton(icon: Icons.add, onTap: () => _zoomBy(1)),
                  const SizedBox(height: 10),
                  _MapControlButton(icon: Icons.remove, onTap: () => _zoomBy(-1)),
                ],
              ),
            ),
            Positioned(
              top: 68,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _address,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Выбрать',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
