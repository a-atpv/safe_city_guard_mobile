import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'route_model.dart';
import 'route_service.dart';
import 'call_repository.dart';
import 'call_controller.dart';

class ActiveCallScreen extends ConsumerStatefulWidget {
  final int callId;
  const ActiveCallScreen({super.key, required this.callId});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  CallRouteData? _callRoute;
  bool _isLoading = true;
  Timer? _refreshTimer;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  bool _hasAutoRedirected = false;
  final MapController _mapController = MapController();
  final RouteService _routeService = RouteService();
  final CallRepository _callRepo = CallRepository();

  @override
  void initState() {
    super.initState();
    _loadRoute();

    // Refresh route every 30 seconds (guard is moving)
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadRoute();
    });

    // Elapsed timer (the "02:34" counter in your UI)
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _elapsedTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    try {
      final data = await _routeService.getRouteToCall(widget.callId);
      if (mounted) {
        setState(() {
          _callRoute = data;
          _isLoading = false;
        });

        // If route is not available, auto-redirect once to chat
        if (data.route == null && !_hasAutoRedirected) {
          _hasAutoRedirected = true;
          context.push('/call-chat', extra: widget.callId.toString());
        }
      }
    } catch (e) {
      debugPrint('Route loading failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);

        // Even on error, redirect to chat as a fallback communication channel
        if (!_hasAutoRedirected) {
          _hasAutoRedirected = true;
          context.push('/call-chat', extra: widget.callId.toString());
        }
      }
    }
  }

  Future<void> _handleStatusAction(String action) async {
    final idStr = widget.callId.toString();
    try {
      setState(() => _isLoading = true);
      switch (action) {
        case 'en_route':
          await _callRepo.enRoute(idStr);
          break;
        case 'arrived':
          await _callRepo.arrived(idStr);
          break;
        case 'complete':
          await _callRepo.complete(idStr);
          if (mounted) Navigator.pop(context);
          return;
      }
      await _loadRoute(); // Re-fetch the route to update status
    } catch (e) {
      debugPrint('Status action failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callControllerProvider);
    final activeCall = callState.activeCall;

    // Show indicator only on very first load if we have no fallback data
    if (_isLoading && _callRoute == null && activeCall == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          // ===== MAP =====
          _buildMap(activeCall),

          // ===== BACK BUTTON =====
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ===== ETA BADGE on map =====
          if (_callRoute?.route != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 50,
              right: 60,
              child: _buildETABadge(_callRoute!.route!.etaMinutes),
            ),

          // ===== ERROR BANNER if route failed =====
          if (_callRoute == null && activeCall != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 20,
              right: 20,
              child: _buildRouteErrorBanner(),
            ),

          // ===== BOTTOM SHEET =====
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomSheet(activeCall),
          ),
          
          if (_isLoading)
            const Positioned(
              top: 40,
              right: 20,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRouteErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Маршрут недоступен. Используйте чат для связи.',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // MAP with polyline + markers
  // ─────────────────────────────────────────────
  Widget _buildMap(Map<String, dynamic>? activeCall) {
    final route = _callRoute;
    LatLng? userPos;
    LatLng? guardPos;
    List<LatLng> polylinePoints = [];

    if (route != null) {
      userPos = LatLng(route.userLatitude, route.userLongitude);
      guardPos = route.guardLatitude != null && route.guardLongitude != null
          ? LatLng(route.guardLatitude!, route.guardLongitude!)
          : null;
      polylinePoints = route.route?.coordinates.map((c) => LatLng(c[0], c[1])).toList() ?? [];
    } else if (activeCall != null) {
      final loc = activeCall['location'];
      if (loc != null) {
        userPos = LatLng(loc['latitude'], loc['longitude']);
      }
    }

    if (userPos == null) {
      return Container(color: const Color(0xFF1A1A2E));
    }

    // Calculate map bounds to fit both points
    final allPoints = [...polylinePoints];
    if (guardPos != null) allPoints.add(guardPos);
    allPoints.add(userPos);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: userPos,
        initialZoom: 14,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        backgroundColor: const Color(0xFF1A1A2E),
        onMapReady: () {
          if (allPoints.length >= 2) {
            final bounds = LatLngBounds.fromPoints(allPoints);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(80),
              ),
            );
          }
        },
      ),
      children: [
        // ── Dark tile layer ──
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'kz.safecity.guard',
        ),

        // ── Route polyline (the blue line) ──
        if (polylinePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: polylinePoints,
                strokeWidth: 5.0,
                color: const Color(0xFF4A90FF), // Blue route line
              ),
            ],
          ),

        // ── Markers ──
        MarkerLayer(
          markers: [
            // User location (red pin) — destination
            Marker(
              point: userPos,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),

            // Guard location (blue dot) — origin
            if (guardPos != null)
              Marker(
                point: guardPos,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90FF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF4A90FF,
                        ).withAlpha(102), // 0.4 opacity
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // ETA badge ("~4 мин")
  // ─────────────────────────────────────────────
  Widget _buildETABadge(int minutes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D44),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '~$minutes мин',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BOTTOM SHEET (status + guard info + address + comment)
  // ─────────────────────────────────────────────
  Widget _buildBottomSheet(Map<String, dynamic>? fallback) {
    final route = _callRoute;
    final address = route?.userAddress ?? fallback?['address'] ?? 'Адрес не определен';
    final status = route?.callStatus ?? fallback?['status'] ?? 'pending';
    final guardName = route?.guardName ?? 'Охранник';
    final callerName = fallback?['caller']?['name'] ?? 'Пользователь';

    final elapsed =
        '${_elapsed.inMinutes.toString().padLeft(2, '0')}:'
        '${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E32),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Status row ──
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status == 'accepted' ? 'Принято' : status == 'en-route' ? 'В пути' : status == 'arrived' ? 'На месте' : 'Активно',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                elapsed,
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Guard info row (showing Guard name) ──
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.blueGrey,
                child: Text(guardName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  guardName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              
              // CHAT BUTTON
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90FF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF4A90FF)),
                  onPressed: () => context.push('/call-chat', extra: widget.callId.toString()),
                ),
              ),
              const SizedBox(width: 8),
              
              // Call button (placeholder)
              Container(
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.phone, color: Colors.green),
                  onPressed: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Address ──
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white54, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Место происшествия:',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      address,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Action Buttons ──
          if (status == 'accepted')
            _buildActionButton(
              'Выехать (En Route)',
              const Color(0xFF4A90FF),
              false,
              () => _handleStatusAction('en_route'),
            ),
          if (status == 'en-route' || status == 'en_route')
            _buildActionButton(
              'На месте (Arrived)',
              Colors.orange,
              false,
              () => _handleStatusAction('arrived'),
            ),
          if (status == 'arrived')
            _buildActionButton(
              'Завершить вызов',
              Colors.green,
              false,
              () => _handleStatusAction('complete'),
            ),

          const SizedBox(height: 8),
          _buildActionButton(
            'На карту',
            Colors.white24,
            true,
            () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String text,
    Color color,
    bool isOutlined,
    VoidCallback onPressed,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      child: isOutlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(text, style: TextStyle(color: color, fontSize: 16)),
            )
          : ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
