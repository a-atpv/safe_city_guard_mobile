import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'nav_models.dart';
import 'navigation_controller.dart';
import 'navigation_map_view.dart';

/// Full-screen first-person navigation to a moving SOS caller.
/// Open after the guard goes en-route: `NavigationScreen(callId: call.id)`.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key, required this.callId});
  final int callId;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final NavigationController _nav;

  @override
  void initState() {
    super.initState();
    _nav = NavigationController(callId: widget.callId);
    _nav.start();
  }

  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1530),
      body: Stack(
        children: [
          Positioned.fill(
            child: NavigationMapView(
              state: _nav.state,
              routeLine: _nav.routeLine,
              guard: _nav.guard,
              target: _nav.target,
            ),
          ),
          _TopBanner(state: _nav.state),
          _CloseApproachArrow(state: _nav.state),
          _BottomBar(state: _nav.state),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _RoundBtn(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({required this.state});
  final ValueListenable<NavState?> state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<NavState?>(
        valueListenable: state,
        builder: (_, st, __) {
          if (st == null) {
            return _card(const Icon(Icons.route, color: Colors.white),
                'Строим маршрут…', '');
          }
          if (st.mode == NavMode.arrived) {
            return _card(const Icon(Icons.flag, color: Colors.white),
                'Вы на месте', '');
          }
          if (st.mode == NavMode.closeApproach) {
            final d = (st.distanceToTargetM ?? 0).round();
            return _card(const Icon(Icons.my_location, color: Colors.white),
                'Цель рядом', '$d м · по стрелке');
          }
          final m = st.nextManeuver;
          if (m == null) return const SizedBox.shrink();
          return _card(
            Icon(_iconFor(m.bannerText), color: Colors.white, size: 30),
            m.bannerText,
            '${_dist(st.distanceToManeuverM)}${m.roadName.isNotEmpty ? " · ${m.roadName}" : ""}',
            offRoute: st.offRoute,
          );
        },
      ),
    );
  }

  Widget _card(Widget icon, String title, String subtitle,
      {bool offRoute = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: offRoute ? const Color(0xFFB23B3B) : const Color(0xFF16203F),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            SizedBox(width: 40, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(offRoute ? 'Пересчёт маршрута' : title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dist(double m) => m >= 1000
      ? '${(m / 100).round() / 10} км'.replaceAll('.', ',')
      : '${(m / 10).round() * 10} м';

  static IconData _iconFor(String banner) {
    switch (banner) {
      case 'Налево':
      case 'Левее':
        return Icons.turn_left;
      case 'Направо':
      case 'Правее':
        return Icons.turn_right;
      case 'Резко налево':
        return Icons.turn_sharp_left;
      case 'Резко направо':
        return Icons.turn_sharp_right;
      case 'Разворот':
        return Icons.u_turn_left;
      case 'Кольцо':
        return Icons.roundabout_left;
      case 'Старт':
        return Icons.my_location;
      default:
        return Icons.straight;
    }
  }
}

/// Big arrow to the live target when street routing gives way at close range.
class _CloseApproachArrow extends StatelessWidget {
  const _CloseApproachArrow({required this.state});
  final ValueListenable<NavState?> state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NavState?>(
      valueListenable: state,
      builder: (_, st, __) {
        if (st == null ||
            st.mode != NavMode.closeApproach ||
            st.bearingToTargetDeg == null) {
          return const SizedBox.shrink();
        }
        // The map is rotated so screen-up = camera bearing; point the arrow at
        // the target relative to that.
        final deg = (st.bearingToTargetDeg! - st.camera.bearing);
        return IgnorePointer(
          child: Center(
            child: Transform.rotate(
              angle: deg * math.pi / 180.0,
              child: const Icon(Icons.navigation,
                  color: Color(0xFFE5484D), size: 96),
            ),
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state});
  final ValueListenable<NavState?> state;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: ValueListenableBuilder<NavState?>(
          valueListenable: state,
          builder: (_, st, __) {
            if (st == null) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF16203F),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metric(st.mode == NavMode.arrived ? '—' : st.etaText, 'осталось'),
                  Container(width: 1, height: 28, color: Colors.white24),
                  _metric(st.remainingDistanceText, 'дистанция'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _metric(String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
