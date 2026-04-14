import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../map/map_screen.dart';
import '../incidents/incidents_list_screen.dart';
import '../profile/profile_screen.dart';
import '../calls/call_offer_listener.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    MapScreen(),
    IncidentsListScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Initialize global call offer listener
    ref.watch(callOfferListenerProvider);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bottomBar,
          border: const Border(
            top: BorderSide(color: AppColors.divider, width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.shield_outlined, Icons.shield),
                _buildNavItem(1, Icons.access_time_outlined, Icons.access_time_filled),
                _buildNavItem(2, Icons.person_outline, Icons.person),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        height: 40,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppColors.accent : AppColors.textHint,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

