import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'route_model.dart';
import 'route_service.dart';
import 'call_repository.dart';

class ActiveCallScreen extends StatefulWidget {
  final int callId;
  const ActiveCallScreen({super.key, required this.callId});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  CallRouteData? _callRoute;
  bool _isLoading = true;
  Timer? _refreshTimer;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
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
      }
    } catch (e) {
      debugPrint('Route loading failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // ===== MAP =====
                _buildMap(),

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

                // ===== BOTTOM SHEET =====
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomSheet(),
                ),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────
  // MAP with polyline + markers
  // ─────────────────────────────────────────────
  Widget _buildMap() {
    final route = _callRoute;
    if (route == null) return const SizedBox();

    // Convert decoded coordinates to LatLng list → this IS the polyline
    final polylinePoints =
        route.route?.coordinates.map((c) => LatLng(c[0], c[1])).toList() ?? [];

    final userPos = LatLng(route.userLatitude, route.userLongitude);
    final guardPos = route.guardLatitude != null && route.guardLongitude != null
        ? LatLng(route.guardLatitude!, route.guardLongitude!)
        : null;

    // Calculate map bounds to fit both points
    final allPoints = [...polylinePoints];
    if (guardPos != null) allPoints.add(guardPos);
    allPoints.add(userPos);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: userPos,
        initialZoom: 14,
        // Dark map style
        backgroundColor: const Color(0xFF1A1A2E),
        onMapReady: () {
          if (allPoints.length >= 2) {
            final bounds = LatLngBounds.fromPoints(allPoints);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(60),
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
  Widget _buildBottomSheet() {
    final route = _callRoute;
    if (route == null) return const SizedBox();

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
              const Text(
                'В работе',
                style: TextStyle(
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

          // ── Guard info row ──
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundImage: route.guardAvatarUrl != null
                    ? NetworkImage(route.guardAvatarUrl!)
                    : null,
                child: route.guardAvatarUrl == null
                    ? Text(
                        route.guardName?.isNotEmpty == true
                            ? route.guardName!.substring(0, 1)
                            : 'G',
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Name + rating
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.guardName ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${route.guardRating?.toStringAsFixed(1) ?? "5.0"} '
                          '(${route.guardTotalReviews ?? 0} отзывов)',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Call button
              if (route.guardPhone != null)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(38), // 0.15 opacity
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.phone, color: Colors.green),
                    onPressed: () {
                      // launchUrl(Uri.parse('tel:${route.guardPhone}'));
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Address ──
          if (route.userAddress != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.location_city,
                  color: Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Адрес:',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    Text(
                      route.userAddress!,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Action Buttons ──
          if (route.callStatus == 'accepted')
            _buildActionButton(
              'В пути (En Route)',
              Colors.blue,
              false,
              () => _handleStatusAction('en_route'),
            ),
          if (route.callStatus == 'en_route')
            _buildActionButton(
              'На месте (Arrived)',
              Colors.orange,
              false,
              () => _handleStatusAction('arrived'),
            ),
          if (route.callStatus == 'arrived')
            _buildActionButton(
              'Завершить (Complete)',
              Colors.green,
              false,
              () => _handleStatusAction('complete'),
            ),

          const SizedBox(height: 12),
          // ── Cancel/Close button ──
          _buildActionButton(
            'Закрыть',
            Colors.redAccent,
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
