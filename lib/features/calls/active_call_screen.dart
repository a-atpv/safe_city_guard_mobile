import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'route_model.dart';
import 'route_service.dart';
import 'call_repository.dart';
import 'call_controller.dart';
import 'call_offer_listener.dart';
import '../../core/app_colors.dart';
import '../../core/map_config.dart';
import '../../core/services/reverse_geocoder.dart';
import '../../core/websocket/websocket_service.dart';

class ActiveCallScreen extends ConsumerStatefulWidget {
  final int callId;
  const ActiveCallScreen({super.key, required this.callId});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen>
    with SingleTickerProviderStateMixin {
  CallRouteData? _callRoute;
  bool _isLoading = true;
  Timer? _refreshTimer;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  bool _hasAutoRedirected = false;
  final MapController _mapController = MapController();
  final RouteService _routeService = RouteService();
  final CallRepository _callRepo = CallRepository();

  // Real-time positions. `_target*` is the latest known coordinate; `_display*`
  // is eased toward the target each frame so markers glide instead of jumping.
  LatLng? _targetUserPos, _displayUserPos;
  // Own-marker quality gate: once we have a position, ignore coarse cell/Wi-Fi
  // fixes so the blue dot stays put instead of easing to a bad fix and back.
  // Matches the backend's acceptance bar for a good fix.
  static const _maxFixAccuracyM = 35.0;

  // ── Freshness of the caller's point ──────────────────────────────────────
  // The backend never swaps a stale position for the call's creation-time
  // coordinates behind our back: it hands over the freshest point it has plus
  // its age, and the guard is told outright when that point stopped updating.
  // A confident dot on a place the caller left ten minutes ago is the one error
  // the guard cannot spot from the screen.
  DateTime? _userFixAt;
  double? _userAccuracyM;
  String _userPosSource = 'call';
  /// Дольше этого — точка считается устаревшей (клиент шлёт координаты раз в 5 с).
  static const _staleAfter = Duration(seconds: 30);
  LatLng? _targetGuardPos, _displayGuardPos;
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  static const Distance _distance = Distance();

  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  StreamSubscription<Position>? _guardPosSub;

  String? _geocodedAddress;
  double? _lastGeocodedLat;
  double? _lastGeocodedLng;

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _triggerReverseGeocode(double lat, double lng) async {
    if (_lastGeocodedLat == lat && _lastGeocodedLng == lng) return;
    _lastGeocodedLat = lat;
    _lastGeocodedLng = lng;

    // Адрес приходит с нашего бэкенда (2ГИС, фолбэк Nominatim).
    final label = await ReverseGeocoder.shortAddress(lat, lng);
    if (mounted && label != null && label.isNotEmpty) {
      setState(() {
        _geocodedAddress = label;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRoute();

    // Proactively refresh the call controller to sync the local state with the backend
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(callControllerProvider.notifier).refresh();
      }
    });

    // Refresh route every 15 seconds (guard is moving)
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadRoute();
    });

    // Elapsed timer (the "02:34" counter in your UI)
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });

    // Live user position pushed from the backend over WebSocket.
    _wsSubscription = webSocketServiceProvider.messageStream.listen((msg) {
      if (msg['type'] == 'user_location_update' &&
          msg['call_id'] == widget.callId) {
        final lat = (msg['latitude'] as num?)?.toDouble();
        final lng = (msg['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null && mounted) {
          // Возраст считаем от момента самого GPS-фикса, а не от прихода пуша:
          // телефон может переслать старый фикс, и он не должен выглядеть свежим.
          final ageMs =
              (((msg['age_seconds'] as num?)?.toDouble() ?? 0) * 1000).round();
          setState(() {
            _userFixAt =
                DateTime.now().subtract(Duration(milliseconds: ageMs));
            _userAccuracyM = (msg['accuracy'] as num?)?.toDouble();
            _userPosSource = 'live';
          });
          _setUserTarget(LatLng(lat, lng));
        }
      }
    });

    // Guard's own position straight from the device GPS — instant and smooth,
    // with no server round-trip (the route only refreshes the blue dot every 15s).
    _guardPosSub = Geolocator.getPositionStream(
      // bestForNavigation + нулевой фильтр расстояния: во время выезда важнее
      // точность и непрерывность потока, чем экономия батареи.
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(
      (pos) {
        if (!mounted) return;
        // Accept the first fix unconditionally so the dot bootstraps; after that,
        // drop coarse fixes rather than let them yank the marker.
        if (_targetGuardPos != null &&
            pos.accuracy > 0 &&
            pos.accuracy > _maxFixAccuracyM) {
          return;
        }
        _setGuardTarget(LatLng(pos.latitude, pos.longitude));
      },
      onError: (_) {},
    );
  }

  @override
  void didUpdateWidget(ActiveCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.callId != widget.callId) {
      _loadRoute();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _elapsedTimer?.cancel();
    _wsSubscription?.cancel();
    _guardPosSub?.cancel();
    _ticker?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Smooth marker movement (each frame eases the display toward the target) ──
  void _setUserTarget(LatLng p) {
    _targetUserPos = p;
    _displayUserPos ??= p; // first fix: snap into place
    _startTicker();
  }

  void _setGuardTarget(LatLng p) {
    _targetGuardPos = p;
    _displayGuardPos ??= p;
    _startTicker();
  }

  void _startTicker() {
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) {
      _lastElapsed = Duration.zero;
      _ticker!.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    // Exponential smoothing toward the target (tau ≈ 0.5s).
    final k = 1 - math.exp(-dt / 0.5);
    var moving = false;

    if (_displayUserPos != null && _targetUserPos != null) {
      if (_distance(_displayUserPos!, _targetUserPos!) > 0.5) {
        _displayUserPos = _lerpLatLng(_displayUserPos!, _targetUserPos!, k);
        moving = true;
      } else {
        _displayUserPos = _targetUserPos;
      }
    }
    if (_displayGuardPos != null && _targetGuardPos != null) {
      if (_distance(_displayGuardPos!, _targetGuardPos!) > 0.5) {
        _displayGuardPos = _lerpLatLng(_displayGuardPos!, _targetGuardPos!, k);
        moving = true;
      } else {
        _displayGuardPos = _targetGuardPos;
      }
    }

    if (mounted) setState(() {});
    if (!moving) _ticker?.stop();
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  Future<void> _loadRoute() async {
    try {
      final data = await _routeService.getRouteToCall(widget.callId);
      if (mounted) {
        final isFirstLoad = _callRoute == null;
        setState(() {
          _callRoute = data;
          _isLoading = false;
          // Пуш по вебсокету приходит чаще, чем перезагружается маршрут, поэтому
          // серверным возрастом перебиваем только если он свежее локального.
          final age = data.userLocationAgeSeconds;
          if (age != null) {
            final serverFixAt = DateTime.now().subtract(Duration(seconds: age));
            if (_userFixAt == null || serverFixAt.isAfter(_userFixAt!)) {
              _userFixAt = serverFixAt;
              _userAccuracyM = data.userLocationAccuracy;
              _userPosSource = data.userLocationSource;
            }
          }
        });

        // Seed / refresh smooth-movement targets from the freshest route data.
        // The backend returns the user's live position; the guard's own dot is
        // driven by device GPS once available, so only seed it initially.
        _setUserTarget(LatLng(data.userLatitude, data.userLongitude));
        if (_targetGuardPos == null &&
            data.guardLatitude != null &&
            data.guardLongitude != null) {
          _setGuardTarget(LatLng(data.guardLatitude!, data.guardLongitude!));
        }

        // If route is not available, auto-redirect once to chat
        if (data.route == null && !_hasAutoRedirected) {
          _hasAutoRedirected = true;
          context.push('/call-chat', extra: widget.callId.toString());
        }

        // On first load, fit the camera bounds if we have points
        if (isFirstLoad && data.route != null) {
          final allPoints = <LatLng>[];
          if (data.guardLatitude != null && data.guardLongitude != null) {
            allPoints.add(LatLng(data.guardLatitude!, data.guardLongitude!));
          }
          allPoints.add(LatLng(data.userLatitude, data.userLongitude));
          if (data.route != null) {
            allPoints.addAll(data.route!.coordinates.map((c) => LatLng(c[0], c[1])));
          }

          if (allPoints.length >= 2) {
            final bounds = LatLngBounds.fromPoints(allPoints);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.only(top: 80, bottom: 280, left: 50, right: 50),
                    maxZoom: 16.5,
                  ),
                );
              }
            });
          }
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

  // Ask the guard to confirm before ending the call. The guard may instead
  // tick "Перенаправить вызов" to hand the call off to other services.
  Future<void> _confirmEndCall() async {
    bool redirect = false;
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    redirect ? Icons.alt_route : Icons.warning_amber_rounded,
                    color: redirect ? AppColors.accent : AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      redirect ? 'Перенаправить вызов?' : 'Завершить вызов?',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    redirect
                        ? 'Вызов будет передан другим службам — его примет ближайший свободный сотрудник.'
                        : 'Вы действительно хотите завершить вызов?',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  // Redirect toggle
                  InkWell(
                    onTap: () => setDialogState(() => redirect = !redirect),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: redirect,
                              onChanged: (v) =>
                                  setDialogState(() => redirect = v ?? false),
                              activeColor: AppColors.accent,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Перенаправить вызов другой службе',
                              style: TextStyle(color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Optional hand-off note, shown only when redirecting
                  if (redirect) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      maxLength: 200,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Комментарий другой службе (необязательно)',
                        hintStyle:
                            const TextStyle(color: AppColors.textSecondary),
                        counterStyle:
                            const TextStyle(color: AppColors.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.textSecondary),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.accent),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text(
                    'Отмена',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(
                    redirect ? 'Перенаправить' : 'Завершить',
                    style: TextStyle(
                      color: redirect ? AppColors.accent : AppColors.danger,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    final shouldRedirect = redirect;
    final note = noteController.text.trim();
    noteController.dispose();

    if (confirmed == true) {
      if (shouldRedirect) {
        await _handleRedirect(note);
      } else {
        await _handleStatusAction('complete');
      }
    }
  }

  // Redirect (hand off) the active call to other security services.
  Future<void> _handleRedirect(String note) async {
    final idStr = widget.callId.toString();
    try {
      setState(() => _isLoading = true);
      await _callRepo.redirect(idStr, note: note.isEmpty ? null : note);
      if (mounted) {
        // Clears local active-call state, returns to map, shows confirmation.
        ref
            .read(callOfferListenerProvider)
            .handleTerminalStatus('redirected', widget.callId);
      }
    } catch (e) {
      debugPrint('Redirect failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
          if (mounted) {
            ref.read(callOfferListenerProvider).handleTerminalStatus('completed', widget.callId);
          }
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

    // Пересчитывается каждую секунду вместе с таймером вызова, поэтому текст
    // «устарела N мин назад» идёт по времени, а не по приходу новых данных.
    final staleBanner = _buildStaleLocationBanner();

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

          // ===== STALE LOCATION BANNER =====
          if (staleBanner != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 92,
              left: 20,
              right: 20,
              child: staleBanner,
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

  // ─────────────────────────────────────────────
  // Свежесть точки вызывающего
  // ─────────────────────────────────────────────

  /// Сколько прошло с момента самого GPS-фикса (не с момента доставки пуша).
  Duration? get _userFixAge =>
      _userFixAt == null ? null : DateTime.now().difference(_userFixAt!);

  static String _formatAge(Duration age) {
    final seconds = age.inSeconds;
    if (seconds < 60) return '$seconds с назад';
    final minutes = age.inMinutes;
    if (minutes < 60) return '$minutes мин назад';
    return '${age.inHours} ч ${minutes % 60} мин назад';
  }

  /// Строка под адресом: «Обновлено 4 с назад · ±8 м» либо предупреждение.
  /// Пустой её не делаем никогда — охранник должен видеть, живая точка или нет,
  /// не додумывая по косвенным признакам.
  Widget _buildFreshnessLine() {
    final age = _userFixAge;
    if (age == null) {
      return const Text(
        'Свежесть координат неизвестна',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      );
    }

    final stale = age > _staleAfter;
    final accuracy = _userAccuracyM;
    final accuracyText =
        accuracy != null ? ' · ±${accuracy.round()} м' : '';
    final sourceText = _userPosSource == 'live'
        ? 'Обновлено ${_formatAge(age)}'
        : 'Точка вызова, ${_formatAge(age)}';

    return Row(
      children: [
        Icon(
          stale ? Icons.gps_off : Icons.gps_fixed,
          size: 12,
          color: stale ? Colors.orangeAccent : Colors.greenAccent,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$sourceText$accuracyText',
            style: TextStyle(
              color: stale ? Colors.orangeAccent : Colors.white54,
              fontSize: 11,
              fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  /// Баннер поверх карты. Появляется только когда точке нельзя доверять как
  /// текущей: координаты перестали приходить. Молчаливой подмены на место
  /// нажатия SOS больше нет — вместо неё честное «устарела N мин назад».
  Widget? _buildStaleLocationBanner() {
    final age = _userFixAge;
    if (age == null || age <= _staleAfter) return null;

    final critical = age.inMinutes >= 2;
    final color = critical ? Colors.redAccent : Colors.orange;
    final headline = _userPosSource == 'live'
        ? 'Точка устарела: ${_formatAge(age)}'
        : 'Координаты не обновляются: точка с момента вызова, ${_formatAge(age)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.gps_off, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'Человек мог сместиться. Свяжитесь по связи и уточните место.',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
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
      // Use the smoothly-eased display position; fall back to the latest target
      // or the raw route coordinates before the first frame has been eased.
      userPos = _displayUserPos ??
          _targetUserPos ??
          LatLng(route.userLatitude, route.userLongitude);
      guardPos = _displayGuardPos ??
          _targetGuardPos ??
          (route.guardLatitude != null && route.guardLongitude != null
              ? LatLng(route.guardLatitude!, route.guardLongitude!)
              : null);
      polylinePoints = route.route?.coordinates.map((c) => LatLng(c[0], c[1])).toList() ?? [];
    } else if (activeCall != null) {
      final lat = _asDouble(activeCall['latitude']) ?? _asDouble(activeCall['location']?['latitude']);
      final lng = _asDouble(activeCall['longitude']) ?? _asDouble(activeCall['location']?['longitude']);
      if (lat != null && lng != null) {
        userPos = _displayUserPos ?? LatLng(lat, lng);
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
        initialZoom: 16.5,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        backgroundColor: const Color(0xFFE8E8E8),
        onMapReady: () {
          if (allPoints.length >= 2) {
            final bounds = LatLngBounds.fromPoints(allPoints);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.only(top: 80, bottom: 280, left: 50, right: 50),
                maxZoom: 16.5,
              ),
            );
          }
        },
      ),
      children: [
        // ── 2ГИС tile layer (matches the map preview) ──
        TileLayer(
          urlTemplate: MapConfig.tileUrlTemplate,
          subdomains: MapConfig.tileSubdomains,
          maxNativeZoom: MapConfig.tileMaxNativeZoom,
          userAgentPackageName: 'kz.safecity.guard',
        ),
        const SimpleAttributionWidget(
          source: Text(MapConfig.attribution),
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

        // ── Круг погрешности вокруг вызывающего ──
        // Точка на карте всегда выглядит точной до метра; круг показывает
        // реальный разброс фикса, чтобы охранник не искал человека там, где
        // его гарантированно нет.
        if (_userAccuracyM != null && _userAccuracyM! > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: userPos,
                radius: _userAccuracyM!,
                useRadiusInMeter: true,
                color: Colors.red.withValues(alpha: 0.10),
                borderColor: Colors.red.withValues(alpha: 0.35),
                borderStrokeWidth: 1,
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
    
    // Resolve caller name with multiple fallbacks
    String callerName = 'Пользователь';
    final nameCandidates = [
      route?.userName?.trim(),
      (fallback?['user']?['full_name'] as String?)?.trim(),
      (fallback?['caller']?['name'] as String?)?.trim(),
    ];
    for (final c in nameCandidates) {
      if (c != null && c.isNotEmpty && c != 'Пользователь') {
        callerName = c;
        break;
      }
    }
    // If name is still default or empty, try phone number
    if (callerName == 'Пользователь') {
      final phoneCandidates = [
        route?.userPhone?.trim(),
        (fallback?['user']?['phone'] as String?)?.trim(),
        (fallback?['caller']?['phone'] as String?)?.trim(),
      ];
      for (final p in phoneCandidates) {
        if (p != null && p.isNotEmpty) {
          callerName = p;
          break;
        }
      }
    }

    // Resolve address with multiple fallbacks
    String address = 'Адрес не определен';
    final addressCandidates = [
      route?.userAddress?.trim(),
      (fallback?['address'] as String?)?.trim(),
      (fallback?['location']?['address'] as String?)?.trim(),
    ];
    for (final a in addressCandidates) {
      if (a != null && a.isNotEmpty && a != 'Адрес не определен') {
        address = a;
        break;
      }
    }

    final lat = route?.userLatitude ?? _asDouble(fallback?['latitude']) ?? _asDouble(fallback?['location']?['latitude']);
    final lng = route?.userLongitude ?? _asDouble(fallback?['longitude']) ?? _asDouble(fallback?['location']?['longitude']);

    if (address == 'Адрес не определен') {
      if (_geocodedAddress != null && _geocodedAddress!.isNotEmpty) {
        address = _geocodedAddress!;
      } else if (lat != null && lng != null) {
        address = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
      }
    }

    // Trigger async geocoding if address is coordinate-based or not determined
    if ((address == 'Адрес не определен' || address.contains(',')) && lat != null && lng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _triggerReverseGeocode(lat, lng);
        }
      });
    }

    final status = route?.callStatus ?? fallback?['status'] ?? 'pending';
 
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
 
          // ── Caller info row ──
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.blueGrey,
                child: Text(
                  callerName.isNotEmpty ? callerName[0].toUpperCase() : 'П',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  callerName,
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
              
              // Call button
              Container(
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.phone, color: Colors.green),
                  onPressed: () async {
                    final phone = route?.userPhone ?? fallback?['user']?['phone'];
                    if (phone != null && phone.isNotEmpty) {
                      final uri = Uri.parse('tel:$phone');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Не удалось набрать номер')),
                          );
                        }
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Номер пользователя не указан')),
                        );
                      }
                    }
                  },
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
                    const SizedBox(height: 4),
                    _buildFreshnessLine(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Action Buttons ──
          if (status == 'accepted' || status == 'en-route' || status == 'en_route' || status == 'arrived')
            _buildActionButton(
              'Завершить вызов',
              Colors.green,
              false,
              () => _confirmEndCall(),
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
