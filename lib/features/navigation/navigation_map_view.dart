import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as mb;
import '../../core/map_config.dart';
import 'nav_models.dart';

/// Thin MapLibre rendering adapter. It only draws — the route line, the guard
/// dot, the target dot — and drives the first-person camera from [state]. All
/// decisions live in [NavigationEngine]/[NavigationController]; swapping this for
/// another renderer wouldn't touch the navigation logic.
class NavigationMapView extends StatefulWidget {
  const NavigationMapView({
    super.key,
    required this.state,
    required this.routeLine,
    required this.guard,
    required this.target,
  });

  final ValueListenable<NavState?> state;
  final ValueListenable<List<ll.LatLng>> routeLine;
  final ValueListenable<ll.LatLng?> guard;
  final ValueListenable<ll.LatLng?> target;

  @override
  State<NavigationMapView> createState() => _NavigationMapViewState();
}

class _NavigationMapViewState extends State<NavigationMapView> {
  mb.MapLibreMapController? _map;
  mb.Line? _route;
  mb.Circle? _guardDot;
  mb.Circle? _targetDot;
  bool _styleReady = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    widget.routeLine.addListener(_onRoute);
    widget.guard.addListener(_onGuard);
    widget.target.addListener(_onTarget);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    widget.routeLine.removeListener(_onRoute);
    widget.guard.removeListener(_onGuard);
    widget.target.removeListener(_onTarget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return mb.MapLibreMap(
      // Растровая подложка 2ГИС (переход на 2gis): прежний MapTiler-стиль
      // требовал ключ, который так и не был выписан, и карта была пустой.
      styleString: MapConfig.navStyle,
      initialCameraPosition: const mb.CameraPosition(
        target: mb.LatLng(MapConfig.fallbackLat, MapConfig.fallbackLng),
        zoom: 15,
      ),
      trackCameraPosition: true,
      myLocationEnabled: false,
      compassEnabled: false,
      onMapCreated: (c) => _map = c,
      onStyleLoadedCallback: _onStyleLoaded,
    );
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    await _onRoute();
    await _onTarget();
    await _onGuard();
    await _onState();
  }

  mb.LatLng _mb(ll.LatLng p) => mb.LatLng(p.latitude, p.longitude);

  Future<void> _onRoute() async {
    final c = _map;
    if (c == null || !_styleReady) return;
    if (_route != null) {
      await c.removeLine(_route!);
      _route = null;
    }
    final pts = widget.routeLine.value.map(_mb).toList();
    if (pts.length >= 2) {
      _route = await c.addLine(mb.LineOptions(
        geometry: pts,
        lineColor: '#2E7DF6',
        lineWidth: 6.0,
        lineJoin: 'round',
        lineOpacity: 0.9,
      ));
    }
  }

  Future<void> _onGuard() async {
    final c = _map;
    final g = widget.guard.value;
    if (c == null || !_styleReady || g == null) return;
    final opts = mb.CircleOptions(
      geometry: _mb(g),
      circleRadius: 8.0,
      circleColor: '#2E7DF6',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2.0,
    );
    if (_guardDot == null) {
      _guardDot = await c.addCircle(opts);
    } else {
      await c.updateCircle(_guardDot!, opts);
    }
  }

  Future<void> _onTarget() async {
    final c = _map;
    final t = widget.target.value;
    if (c == null || !_styleReady || t == null) return;
    final opts = mb.CircleOptions(
      geometry: _mb(t),
      circleRadius: 9.0,
      circleColor: '#E5484D',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2.0,
    );
    if (_targetDot == null) {
      _targetDot = await c.addCircle(opts);
    } else {
      await c.updateCircle(_targetDot!, opts);
    }
  }

  Future<void> _onState() async {
    final c = _map;
    final st = widget.state.value;
    if (c == null || !_styleReady || st == null) return;
    await c.animateCamera(
      mb.CameraUpdate.newCameraPosition(mb.CameraPosition(
        target: _mb(st.camera.center),
        bearing: st.camera.bearing,
        tilt: st.camera.tilt,
        zoom: st.camera.zoom,
      )),
    );
  }
}
