import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/app_haptics.dart';
import '../services/nfc_service.dart';
import '../state/settings_controller.dart';
import 'nfc_scan_sheet.dart';

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

  static const _lastPage = 4;

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
                  _VanPage(),
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
          title: 'No delivery data is uploaded',
          detail:
              'There is no server for your stops, routes or photos. They are '
              'only ever written to this phone.',
        ),
        _Point(
          icon: Icons.public,
          title: 'Two things do use the network',
          detail:
              'Map tiles come from OpenStreetMap, which asks for images and '
              'not your position. The weather card does send your rough '
              'location — switch it off in Settings if you would rather it '
              'did not.',
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

/// Who is driving, and what. Both optional — the app works perfectly with
/// them blank — but a van label is worth asking for once here, because it is
/// what goes on an NFC tag and what the home screen greets you with.
class _VanPage extends StatefulWidget {
  const _VanPage();

  @override
  State<_VanPage> createState() => _VanPageState();
}

class _VanPageState extends State<_VanPage> {
  late final TextEditingController _name;
  late final TextEditingController _van;
  NfcReadiness? _readiness;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>().settings;
    _name = TextEditingController(text: settings.driverName);
    _van = TextEditingController(text: settings.vehicleLabel);
    _checkNfc();
  }

  Future<void> _checkNfc() async {
    final readiness = await context.read<NfcService>().readiness();
    if (mounted) setState(() => _readiness = readiness);
  }

  @override
  void dispose() {
    // Deliberately no saving here: `context.read` in dispose throws once the
    // widget is deactivated, and PageView disposes pages you swipe away from.
    // Both fields save as they are typed instead.
    _name.dispose();
    _van.dispose();
    super.dispose();
  }

  /// Hands the whole thing to the tag sheet, which is where the radar, the
  /// "hold it there" prompt and the three possible answers live.
  Future<void> _writeTag() async {
    final label = _van.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the van a name first.')),
      );
      return;
    }

    setState(() => _writing = true);
    await NfcWriteSheet.show(context, label: label);
    if (mounted) setState(() => _writing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNfc = _readiness == NfcReadiness.ready;

    return _Page(
      icon: Icons.local_shipping_outlined,
      title: 'Your van',
      body: 'Both optional, and both changeable later in Settings.',
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'So the app can say hello',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          onChanged: context.read<SettingsController>().setDriverName,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _van,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Van or round',
            hintText: 'e.g. LT21 KXR, or Round 4',
            prefixIcon: Icon(Icons.local_shipping_outlined),
          ),
          onChanged: (value) {
            context.read<SettingsController>().setVehicleLabel(value);
            // Drives the "write a tag" button's enabled state.
            setState(() {});
          },
        ),
        const SizedBox(height: 24),

        // Only offered when the phone can actually do it. Dangling a disabled
        // button in front of someone whose phone has no NFC is just noise.
        if (hasNfc) ...[
          Text(
            'GOT AN NFC TAG HANDY?',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Write one now and stick it in the van — then tapping it clocks '
            'you on. Entirely optional, and you can do it later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _writing || _van.text.trim().isEmpty ? null : _writeTag,
            icon: const Icon(Icons.nfc),
            label: const Text('Write a tag'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final unit = settings.distanceUnit;

    return _Page(
      icon: Icons.tune,
      title: 'How should it read?',
      body: 'Two quick choices. Both live in Settings if you change your mind.',
      children: [
        Text(
          'UNITS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<DistanceUnit>(
          segments: [
            for (final option in DistanceUnit.values)
              ButtonSegment(
                value: option,
                icon: Icon(
                  option == DistanceUnit.metric
                      ? Icons.straighten
                      : Icons.square_foot,
                ),
                label: Text(option.label),
              ),
          ],
          selected: {unit},
          onSelectionChanged: (selection) {
            AppHaptics.select();
            controller.setDistanceUnit(selection.first);
          },
        ),
        const SizedBox(height: 8),
        // Says what the choice actually does to the readouts, which "Metric"
        // on its own does not.
        Text(
          'Distances and speeds read in ${unit.detail.toLowerCase()}. '
          'The weather card follows this too — temperature in '
          '${settings.usesFahrenheit ? 'Fahrenheit' : 'Celsius'}, wind in '
          '${settings.resolvedWindUnit.detail} — and each of those can be set '
          'on its own later.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
