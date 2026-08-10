import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_colors.dart';
import '../../core/basemap.dart';
import '../../core/map_config.dart';
import '../../core/services/reverse_geocoder.dart';
import '../home/shift_controller.dart';
import '../calls/call_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

/// Почему геопозиции нет — чтобы подпись на карте говорила правду.
///
/// Раньше любая неудача (выключенный GPS, отказ в разрешении, не поймавшийся
/// фикс) молча заканчивалась резервной точкой Актобе, и её адрес выводился так
/// же, как настоящий. Охранник в другом районе видел «улица Братьев Жубановых
/// 289» и верил ему: экран не отличал «вот твой адрес» от «я не знаю, где ты».
enum _LocationStatus {
  resolving,
  ok,
  serviceDisabled,
  denied,
  deniedForever,
  failed,
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  /// Куда смотрит камера до первого фикса — Актобе, город, который обслуживаем
  /// (раньше здесь была Астана, и охранник в Актобе успевал увидеть чужой
  /// город). Это ТОЛЬКО камера: ни маркер «я здесь», ни подпись адреса от
  /// резервной точки не берутся.
  LatLng _cameraCenter =
      const LatLng(MapConfig.fallbackLat, MapConfig.fallbackLng);

  /// Настоящий фикс от GPS. null — местоположение неизвестно или недоступно;
  /// пока он null, синий маркер не рисуется вообще.
  LatLng? _myPosition;

  /// Адрес, который показываем: либо для [_myPosition], либо для центра карты,
  /// если охранник увёл её руками. null — подписи нет, и в чипе висит причина
  /// из [_locationStatus].
  String? _resolvedAddress;

  _LocationStatus _locationStatus = _LocationStatus.resolving;

  /// Камера ходит за охранником, пока он сам её не потянул. После этого он
  /// выбирает точку руками, и поток фиксов не должен дёргать карту обратно.
  bool _followMe = true;

  bool _isAccepting = false;
  final MapController _mapController = MapController();

  /// flutter_map бросает исключение на `move()` до первой отрисовки карты.
  bool _mapReady = false;

  /// Первое центрирование ставит рабочий зум, дальше уважаем зум охранника.
  bool _hasCenteredOnce = false;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  Timer? _reverseGeocodeDebounce;

  /// Точка последнего запроса в геокодер и счётчик запросов: ответ на уехавшую
  /// точку выбрасываем, иначе поздний ответ перезапишет свежую подпись.
  LatLng? _lastGeocoded;
  int _geocodeSeq = 0;

  /// Не даём `_startLocation` запуститься дважды: его дёргают и возврат
  /// приложения из фона, и поток статуса службы, и тап по чипу.
  bool _starting = false;

  final Map<String, Future<String>> _callAddressFutureCache = {};

  static const double _followZoom = 16.5;
  static const double _overviewZoom = 15.0;

  /// Первый фикс без ограничения по времени висел бесконечно: в помещении
  /// high-accuracy может не прийти никогда, и подпись оставалась «Определение
  /// адреса...» до перезапуска.
  static const Duration _firstFixTimeout = Duration(seconds: 20);
  static const Duration _geocodeDebounce = Duration(milliseconds: 450);

  /// Шаг, с которого имеет смысл перезапрашивать адрес. Геокодер 2ГИС платный —
  /// на каждый фикс из потока в него ходить незачем.
  static const double _minGeocodeMoveM = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLocation();
    // Охранник может включить геолокацию, не уходя из приложения.
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.enabled) {
        _startLocation();
      } else {
        _setStatus(_LocationStatus.serviceDisabled);
      }
    }, onError: (e) => debugPrint('MapScreen: поток статуса службы: $e'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reverseGeocodeDebounce?.cancel();
    _positionSub?.cancel();
    _serviceStatusSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Разрешение выдают в системных настройках — вернувшись, пробуем снова.
    if (state == AppLifecycleState.resumed &&
        _locationStatus != _LocationStatus.ok) {
      _startLocation();
    }
  }

  /// Разрешения → мгновенный последний известный фикс → поток → свежий фикс.
  /// На любой неудаче выставляет честный статус и НЕ подставляет резервную
  /// точку: лучше «не удалось определить», чем чужой адрес.
  Future<void> _startLocation() async {
    if (_starting || !mounted) return;
    _starting = true;
    try {
      // Без сравнения здесь был бы setState синхронно из initState — Flutter
      // ругается на markNeedsBuild во время сборки. На первом проходе статус и
      // так resolving, так что трогать его незачем.
      if (_locationStatus != _LocationStatus.resolving) {
        setState(() => _locationStatus = _LocationStatus.resolving);
      }

      // Проверки, которой здесь не было вовсе: с выключенным GPS
      // getCurrentPosition сразу бросает, и экран уходил в резервную точку.
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setStatus(_LocationStatus.serviceDisabled);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _setStatus(_LocationStatus.deniedForever);
        return;
      }
      if (permission == LocationPermission.denied) {
        _setStatus(_LocationStatus.denied);
        return;
      }

      // Последний известный фикс приходит мгновенно: карта сразу оказывается
      // примерно там, где охранник, пока GPS ловит спутники.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) _applyFix(last);
      } catch (e) {
        debugPrint('MapScreen: последний известный фикс недоступен: $e');
      }

      _listenToPositionStream();

      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: _firstFixTimeout,
          ),
        );
        _applyFix(fresh);
      } catch (e) {
        debugPrint('MapScreen: свежий фикс не получен: $e');
        // Поток мог уже что-то принести — тогда статус трогать нельзя.
        if (_myPosition == null) _setStatus(_LocationStatus.failed);
      }
    } finally {
      _starting = false;
    }
  }

  /// Живой поток фиксов. Экран карты был единственным, кто читал позицию
  /// однократно в initState: он живёт в IndexedStack, initState отрабатывает
  /// раз за запуск приложения — и маркер с адресом навсегда застывали там, где
  /// охранник был при старте.
  void _listenToPositionStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      _applyFix,
      onError: (e) {
        debugPrint('MapScreen: поток геопозиции: $e');
        if (_myPosition == null) _setStatus(_LocationStatus.failed);
      },
    );
  }

  void _applyFix(Position pos) {
    if (!mounted) return;
    final next = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _myPosition = next;
      _locationStatus = _LocationStatus.ok;
      if (_followMe) _cameraCenter = next;
    });
    if (!_followMe) return;
    _moveCamera(next);
    _scheduleReverseGeocode(next);
  }

  void _setStatus(_LocationStatus status) {
    if (!mounted) return;
    setState(() {
      _locationStatus = status;
      if (status == _LocationStatus.ok) return;
      _myPosition = null;
      // Нет своей точки — нет и подписи: иначе на экране остаётся адрес,
      // который уже ничего не значит. Точку, выбранную руками, не трогаем —
      // её адрес охранник запросил сам.
      if (_followMe) _resolvedAddress = null;
    });
  }

  void _moveCamera(LatLng target) {
    if (!_mapReady) return;
    final zoom = _hasCenteredOnce ? _mapController.camera.zoom : _followZoom;
    _hasCenteredOnce = true;
    _mapController.move(target, zoom);
  }

  void _scheduleReverseGeocode(LatLng point) {
    final last = _lastGeocoded;
    if (last != null &&
        Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              point.latitude,
              point.longitude,
            ) <
            _minGeocodeMoveM) {
      return;
    }
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(_geocodeDebounce, () {
      if (mounted) _reverseGeocode(point);
    });
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    // Адрес приходит с нашего бэкенда (2ГИС, фолбэк Nominatim).
    _lastGeocoded = pos;
    final seq = ++_geocodeSeq;
    final label = await ReverseGeocoder.shortAddress(pos.latitude, pos.longitude);
    if (!mounted || seq != _geocodeSeq) return;
    setState(() {
      // Геокодер недоступен — показываем координаты этой же точки, а не
      // прошлую подпись: устаревшая улица выглядит как рабочий ответ.
      _resolvedAddress = (label != null && label.isNotEmpty)
          ? label
          : '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    });
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    // When the user drags/zooms the map, treat the map CENTER as the selected location.
    if (!hasGesture) return;
    final center = camera.center;
    setState(() {
      _followMe = false;
      _cameraCenter = center;
    });
    _lastGeocoded = null; // выбор руками геокодим всегда, без порога в 30 м
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(_geocodeDebounce, () {
      if (mounted) _reverseGeocode(center);
    });
  }

  /// Вернуть карту к охраннику после того, как он её потянул.
  Future<void> _recenterOnMe() async {
    setState(() => _followMe = true);
    final me = _myPosition;
    if (me == null) {
      await _startLocation();
      return;
    }
    _hasCenteredOnce = false; // вернуть рабочий зум
    _moveCamera(me);
    _lastGeocoded = null;
    _scheduleReverseGeocode(me);
  }

  /// Текст чипа: адрес, когда он есть, иначе — причина, почему его нет.
  String get _addressLabel {
    final resolved = _resolvedAddress;
    if (resolved != null) return resolved;
    switch (_locationStatus) {
      case _LocationStatus.resolving:
        return 'Определение адреса...';
      case _LocationStatus.serviceDisabled:
        return 'Геолокация выключена — включить';
      case _LocationStatus.denied:
        return 'Нет доступа к геолокации — разрешить';
      case _LocationStatus.deniedForever:
        return 'Доступ к геолокации запрещён — настройки';
      case _LocationStatus.failed:
        return 'Не удалось определить адрес — повторить';
      case _LocationStatus.ok:
        return 'Определение адреса...';
    }
  }

  bool get _addressChipIsActionable =>
      _resolvedAddress == null &&
      _locationStatus != _LocationStatus.resolving &&
      _locationStatus != _LocationStatus.ok;

  Future<void> _onAddressChipTap() async {
    switch (_locationStatus) {
      case _LocationStatus.serviceDisabled:
        await Geolocator.openLocationSettings();
        break;
      case _LocationStatus.deniedForever:
        await Geolocator.openAppSettings();
        break;
      case _LocationStatus.denied:
      case _LocationStatus.failed:
        await _startLocation();
        break;
      case _LocationStatus.resolving:
      case _LocationStatus.ok:
        break;
    }
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<String> _resolveCallAddress(Map<String, dynamic> call) async {
    final directAddress = (call['address'] as String?)?.trim();
    if (directAddress != null && directAddress.isNotEmpty) {
      return directAddress;
    }

    final locationAddress = (call['location']?['address'] as String?)?.trim();
    if (locationAddress != null && locationAddress.isNotEmpty) {
      return locationAddress;
    }

    final lat = _asDouble(call['latitude']) ?? _asDouble(call['location']?['latitude']);
    final lng = _asDouble(call['longitude']) ?? _asDouble(call['location']?['longitude']);
    if (lat == null || lng == null) {
      return 'Адрес не указан';
    }

    final label = await ReverseGeocoder.shortAddress(lat, lng);
    if (label != null && label.isNotEmpty) return label;

    return 'Адрес не указан';
  }

  Future<String> _addressFutureForCall(Map<String, dynamic> call) {
    final key = call['id']?.toString() ??
        '${call['latitude']}_${call['longitude']}_${call['location']?['latitude']}_${call['location']?['longitude']}';
    return _callAddressFutureCache.putIfAbsent(key, () => _resolveCallAddress(call));
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
          initialCenter: _myPosition ?? _cameraCenter,
          initialZoom: cam.zoom,
          initialAddress: _resolvedAddress,
        ),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || result == null) return;
    // Точку выбрали руками — перестаём ходить за GPS, пока не нажмут «к себе».
    setState(() {
      _followMe = false;
      _cameraCenter = result.center;
      _resolvedAddress = result.address;
    });
    _lastGeocoded = result.center;
    if (_mapReady) _mapController.move(result.center, result.zoom);
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
                          initialCenter: _cameraCenter,
                          initialZoom:
                              _myPosition != null ? _followZoom : _overviewZoom,
                          onPositionChanged: _onMapPositionChanged,
                          onMapReady: () {
                            _mapReady = true;
                            final me = _myPosition;
                            if (me != null && _followMe) _moveCamera(me);
                          },
                        ),
                        children: [
                          const BaseMapLayer(),
                          // Маркер «я здесь» — только когда позиция реально
                          // известна. На резервной точке он врал охраннику.
                          if (_myPosition != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _myPosition!,
                                  width: 44,
                                  height: 44,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.info.withValues(alpha: 0.2),
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
                        left: 12,
                        right: 12,
                        child: Center(
                          child: GestureDetector(
                            onTap: _addressChipIsActionable
                                ? _onAddressChipTap
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.cardDark.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                                border: _addressChipIsActionable
                                    ? Border.all(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.7),
                                      )
                                    : null,
                              ),
                              child: Text(
                                _addressLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _addressChipIsActionable
                                      ? AppColors.warning
                                      : AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
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

                      // Вернуться к себе после ручного перетаскивания карты.
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _MapControlButton(
                          icon: _followMe
                              ? Icons.my_location
                              : Icons.location_searching,
                          onTap: _recenterOnMe,
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
              Text(
                callState.activeCall != null ? 'Активный вызов:' : 'Доступные вызовы:',
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
                if (callState.activeCall != null)
                  _buildCallCard(callState.activeCall!, isActive: true)
                else if (callState.availableCalls.isNotEmpty)
                  ...callState.availableCalls
                      .map((c) => _buildCallCard(c, isActive: false))
                else
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
    final name = call['user']?['full_name'] ?? call['caller']?['name'] ?? 'Неизвестный';
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
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
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
                    FutureBuilder<String>(
                      future: _addressFutureForCall(call),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? 'Определение адреса...',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        );
                      },
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
                  onPressed: () async {
                    final phone = call['user']?['phone'];
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
              onPressed: _isAccepting
                  ? null
                  : () async {
                      if (!isActive) {
                        setState(() {
                          _isAccepting = true;
                        });
                        try {
                          await ref.read(callControllerProvider.notifier).acceptCall(callId);
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка при принятии вызова: $e')),
                          );
                          return;
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isAccepting = false;
                            });
                          }
                        }
                      }
                      if (!mounted) return;
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
              child: _isAccepting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
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

  /// null — адрес для выбранной точки так и не определился.
  final String? address;

  const _FullScreenMapResult({
    required this.center,
    required this.zoom,
    required this.address,
  });
}

class _FullScreenMapScreen extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;

  /// Подпись, уже посчитанная на обзорной карте. null — считаем заново здесь.
  final String? initialAddress;

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
  String? _address;

  /// Ответ на уехавшую точку выбрасываем — иначе поздний ответ геокодера
  /// перезаписывает подпись уже другого места.
  int _geocodeSeq = 0;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _address = widget.initialAddress;
    if (_address == null) _resolve(_center);
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
    _debounce = Timer(const Duration(milliseconds: 450), () => _resolve(camera.center));
  }

  /// Подпись для точки. Геокодер недоступен — показываем координаты ЭТОЙ точки,
  /// а не прошлую улицу: устаревшая подпись выглядит как рабочий ответ.
  Future<void> _resolve(LatLng point) async {
    final seq = ++_geocodeSeq;
    final next = await _reverseGeocode(point);
    if (!mounted || seq != _geocodeSeq) return;
    setState(() {
      _address = (next != null && next.isNotEmpty)
          ? next
          : '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    });
  }

  void _zoomBy(double delta) {
    final cam = _controller.camera;
    final nextZoom = (cam.zoom + delta).clamp(3.0, 19.0);
    _controller.move(cam.center, nextZoom);
  }

  Future<String?> _reverseGeocode(LatLng pos) =>
      ReverseGeocoder.shortAddress(pos.latitude, pos.longitude);

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
                const BaseMapLayer(),
              ],
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
                    _address ?? 'Определение адреса...',
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
