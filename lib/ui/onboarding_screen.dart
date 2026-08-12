import 'package:flutter/material.dart';

/// Shown once, before the first permission prompt.
///
/// Android's own dialog says nothing about *why* an app wants a location, and
/// a permanent denial is expensive to undo — so the reason goes here, in front
/// of the system prompt.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.onEnable,
    required this.onSkip,
    this.isBusy = false,
  });

  final VoidCallback onEnable;
  final VoidCallback onSkip;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.local_shipping_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Track your round',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This app records where you drive while a delivery is in '
                'progress, so every stop has a route, a distance and a time '
                'against it.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              const _Point(
                icon: Icons.play_circle_outline,
                title: 'Only while a trip is running',
                detail:
                    'Nothing is recorded until you start a stop, and it stops '
                    'the moment you close it out.',
              ),
              const _Point(
                icon: Icons.phone_android,
                title: 'Stays on this device',
                detail:
                    'Positions are written to local storage. Nothing is '
                    'uploaded anywhere.',
              ),
              const _Point(
                icon: Icons.notifications_active_outlined,
                title: 'Visible while it runs',
                detail:
                    'A notification stays up for as long as tracking is '
                    'active, so it can never run unnoticed.',
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: isBusy ? null : onEnable,
                icon: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: const Text('Enable location'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              TextButton(
                onPressed: isBusy ? null : onSkip,
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
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
