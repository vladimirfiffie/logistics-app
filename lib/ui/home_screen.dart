import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/tracking_controller.dart';
import 'history_tab.dart';
import 'home_tab.dart';
import 'live_tab.dart';
import 'manifest_tab.dart';

/// App shell: manifest, live tracking, history.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _homeTab = 0;
  static const _manifestTab = 1;
  static const _liveTab = 2;

  int _index = _homeTab;

  void _goTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final isTracking = context.select<TrackingController, bool>(
      (controller) => controller.isTracking,
    );

    return Scaffold(
      // IndexedStack rather than swapping children: the live map keeps its
      // camera and the manifest keeps its scroll position across tab changes.
      body: IndexedStack(
        index: _index,
        children: [
          HomeTab(
            onTrackingStarted: () => _goTo(_liveTab),
            onBrowseManifest: () => _goTo(_manifestTab),
            onOpenLive: () => _goTo(_liveTab),
          ),
          ManifestTab(onTrackingStarted: () => _goTo(_liveTab)),
          LiveTab(onBrowseManifest: () => _goTo(_manifestTab)),
          const HistoryTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Manifest',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: isTracking,
              smallSize: 8,
              child: const Icon(Icons.radar_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: isTracking,
              smallSize: 8,
              child: const Icon(Icons.radar),
            ),
            label: 'Live',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
