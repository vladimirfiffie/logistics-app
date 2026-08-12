import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/app_haptics.dart';
import '../state/settings_controller.dart';

/// First-run flow: what the app does, what it records, the choices worth
/// making up front, and only then the permission prompt.
///
/// The permission ask is deliberately last. Android's own dialog explains
/// nothing about *why*, and a permanent denial is expensive to undo — so the
/// reasoning goes in front of it, and by the time the driver taps Enable they
/// have already seen what is being recorded and that it stays on the device.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onEnable,
    required this.onSkip,
    this.isBusy = false,
  });

  /// Finish, requesting location permission.
  final VoidCallback onEnable;

  /// Finish without asking. Tracking simply will not work until they grant it
  /// later from Settings.
  final VoidCallback onSkip;

  final bool isBusy;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _lastPage = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    AppHaptics.select();
    if (_page >= _lastPage) {
      widget.onEnable();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    AppHaptics.select();
    _pages.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _page == _lastPage;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.isBusy ? null : widget.onSkip,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) {
                  AppHaptics.select();
                  setState(() => _page = page);
                },
                children: const [
                  _WelcomePage(),
                  _TrackingPage(),
                  _PrivacyPage(),
                  _PreferencesPage(),
                ],
              ),
            ),
            _Dots(count: _lastPage + 1, active: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 20),
              child: Column(
                children: [
                  FilledButton.icon(
                    onPressed: widget.isBusy ? null : _next,
                    icon: widget.isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isLast ? Icons.my_location : Icons.arrow_forward,
                          ),
                    label: Text(isLast ? 'Enable location' : 'Next'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: _page == 0
                        ? null
                        : TextButton(
                            onPressed: widget.isBusy ? null : _back,
                            child: const Text('Back'),
                          ),
                  ),
                  if (isLast)
                    Text(
                      'You can change any of this later in Settings.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

/// Shared layout so every page lines up as you swipe between them.
class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Icon(icon, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _Page(
      icon: Icons.local_shipping_outlined,
      title: 'Track your round',
      body:
          'A delivery app that records where you drive, so every stop has a '
          'route, a distance and a time against it.',
      children: [
        _Point(
          icon: Icons.list_alt,
          title: 'A manifest for the day',
          detail: 'Every stop, sortable by time slot or by which is nearest.',
        ),
        _Point(
          icon: Icons.route_outlined,
          title: 'A recorded trail',
          detail: 'See where you went and how far it actually was.',
        ),
        _Point(
          icon: Icons.photo_camera_outlined,
          title: 'Proof at the door',
          detail: 'A name and a photo, or a reason it could not be left.',
        ),
      ],
    );
  }
}

class _TrackingPage extends StatelessWidget {
  const _TrackingPage();

  @override
  Widget build(BuildContext context) {
    return const _Page(
      icon: Icons.radar,
      title: 'Only while a trip runs',
      body:
          'Nothing is recorded until you start a stop, and recording ends the '
          'moment you close it out.',
      children: [
        _Point(
          icon: Icons.play_circle_outline,
          title: 'You start it',
          detail: 'Pick a stop and tap start. Never before that.',
        ),
        _Point(
          icon: Icons.notifications_active_outlined,
          title: 'Visible the whole time',
          detail:
              'A notification stays up while tracking runs, so it can never '
              'run unnoticed.',
        ),
        _Point(
          icon: Icons.stop_circle_outlined,
          title: 'You stop it',
          detail: 'Completing the stop ends recording automatically.',
        ),
      ],
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    return const _Page(
      icon: Icons.phone_android,
      title: 'It stays on this phone',
      body:
          'Positions, photos and delivery records are written to local '
          'storage on this device.',
      children: [
        _Point(
          icon: Icons.cloud_off,
          title: 'No uploads',
          detail: 'There is no server. Nothing leaves the device.',
        ),
        _Point(
          icon: Icons.map_outlined,
          title: 'Maps are the exception',
          detail:
              'Map tiles are fetched from OpenStreetMap, which means it asks '
              'for map images — never your position.',
        ),
        _Point(
          icon: Icons.delete_outline,
          title: 'Uninstall removes it',
          detail: 'Everything goes with the app.',
        ),
      ],
    );
  }
}

/// Units and haptics up front, because getting units wrong makes every
/// readout in the app unreadable to half the world.
class _PreferencesPage extends StatelessWidget {
  const _PreferencesPage();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return _Page(
      icon: Icons.tune,
      title: 'How should it read?',
      body: 'Two quick choices. Both live in Settings if you change your mind.',
      children: [
        Text(
          'DISTANCE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<DistanceUnit>(
          segments: [
            for (final unit in DistanceUnit.values)
              ButtonSegment(value: unit, label: Text(unit.detail)),
          ],
          selected: {settings.distanceUnit},
          onSelectionChanged: (selection) {
            AppHaptics.select();
            controller.setDistanceUnit(selection.first);
          },
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.vibration),
          title: const Text('Haptics'),
          subtitle: const Text('Buzz on start, delivery and errors.'),
          value: settings.hapticsEnabled,
          onChanged: (value) async {
            await controller.setHapticsEnabled(value);
            if (value) await AppHaptics.delivered();
          },
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
