import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/delivery_repository.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import '../services/location_service.dart';
import '../state/delivery_controller.dart';
import '../state/tracking_controller.dart';
import 'delivery_actions.dart';
import 'formatters.dart';
import 'widgets/app_sheet.dart';
import 'widgets/status_chip.dart';
import 'widgets/trip_map.dart';

/// Everything about one stop, plus the actions that move it forward.
///
/// Resolves to true when the driver started tracking from here, so the shell
/// can jump to the live view.
Future<bool?> showDeliveryDetail(BuildContext context, String deliveryId) {
  return showAppSheet<bool>(
    context,
    builder: (_) => DeliveryDetailSheet(deliveryId: deliveryId),
  );
}

class DeliveryDetailSheet extends StatefulWidget {
  const DeliveryDetailSheet({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  State<DeliveryDetailSheet> createState() => _DeliveryDetailSheetState();
}

class _DeliveryDetailSheetState extends State<DeliveryDetailSheet> {
  Trip? _trip;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    final trip = await context.read<DeliveryRepository>().tripForDelivery(
      widget.deliveryId,
    );
    if (mounted) setState(() => _trip = trip);
  }

  @override
  Widget build(BuildContext context) {
    final delivery = context.watch<DeliveryController>().byId(
      widget.deliveryId,
    );

    if (delivery == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Text('This stop is no longer on the run.'),
      );
    }

    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: SheetHeader(
            title: delivery.customerName,
            subtitle: delivery.reference,
            trailing: StatusChip(delivery.status),
          ),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 170,
                    // Non-interactive so dragging over the map scrolls the
                    // sheet instead of panning the map underneath it.
                    child: TripMap(
                      destination: LatLng(
                        delivery.latitude,
                        delivery.longitude,
                      ),
                      followDriver: false,
                      interactive: false,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(delivery.address, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    _InfoRow(
                      icon: Icons.schedule,
                      label: 'Scheduled',
                      value: formatDateTime(delivery.scheduledFor),
                    ),
                    _InfoRow(
                      icon: Icons.inventory_2_outlined,
                      label: 'Parcels',
                      value: '${delivery.parcelCount}',
                    ),
                    _InfoRow(
                      icon: Icons.my_location,
                      label: 'Coordinates',
                      value: formatCoordinates(
                        delivery.latitude,
                        delivery.longitude,
                      ),
                      onCopy: () => _copyCoordinates(delivery),
                    ),
                    if (delivery.notes case final String notes) ...[
                      const SizedBox(height: 10),
                      _NotesCard(notes: notes),
                    ],
                    if (_trip case final Trip trip) ...[
                      const SizedBox(height: 10),
                      _TripSummary(trip: trip),
                    ],
                    if (!delivery.status.isOpen) ...[
                      const SizedBox(height: 10),
                      _OutcomeCard(delivery: delivery),
                    ],
                    const SizedBox(height: 22),
                    ..._buildActions(context, delivery),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context, Delivery delivery) {
    final tracking = context.watch<TrackingController>();
    final isThisStopLive =
        tracking.isTracking && tracking.trip?.deliveryId == delivery.id;
    final otherStopLive = tracking.isTracking && !isThisStopLive;

    return [
      OutlinedButton.icon(
        onPressed: () => _openInMaps(delivery),
        icon: const Icon(Icons.directions_outlined),
        label: const Text('Navigate with maps app'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      ),
      const SizedBox(height: 10),

      if (delivery.status == DeliveryStatus.pending)
        FilledButton.icon(
          onPressed: tracking.isBusy || otherStopLive
              ? null
              : () => _startTrip(delivery),
          icon: tracking.isBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(
            otherStopLive
                ? 'Another stop is being tracked'
                : 'Start trip & track location',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),

      if (isThisStopLive)
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.radar),
          label: const Text('Open live tracking'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),

      if (delivery.status.isOpen) ...[
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => _complete(delivery),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Mark delivered'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => _fail(delivery),
          icon: const Icon(Icons.report_gmailerrorred_outlined),
          label: const Text("Couldn't deliver"),
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    ];
  }

  Future<void> _startTrip(Delivery delivery) async {
    final tracking = context.read<TrackingController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final started = await tracking.start(delivery);
    if (!mounted) return;

    if (started) {
      await _loadTrip();
      navigator.pop(true);
      return;
    }

    final readiness = tracking.readiness;
    messenger.showSnackBar(
      SnackBar(
        content: Text(tracking.error?.toString() ?? readiness.message),
        duration: const Duration(seconds: 6),
        action: readiness.isFixableInSettings
            ? SnackBarAction(
                label: readiness == LocationReadiness.serviceDisabled
                    ? 'Turn on'
                    : 'Settings',
                onPressed: tracking.openRelevantSettings,
              )
            : null,
      ),
    );
  }

  Future<void> _complete(Delivery delivery) async {
    final navigator = Navigator.of(context);
    final closed = await completeDelivery(context, delivery);
    // The stop is done; leaving its detail sheet open serves no purpose.
    if (closed && navigator.canPop()) {
      navigator.pop();
    } else if (mounted) {
      await _loadTrip();
    }
  }

  Future<void> _fail(Delivery delivery) async {
    final navigator = Navigator.of(context);
    final closed = await failDelivery(context, delivery);
    if (closed && navigator.canPop()) {
      navigator.pop();
    } else if (mounted) {
      await _loadTrip();
    }
  }

  Future<void> _copyCoordinates(Delivery delivery) async {
    await Clipboard.setData(
      ClipboardData(text: '${delivery.latitude},${delivery.longitude}'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Coordinates copied')));
  }

  Future<void> _openInMaps(Delivery delivery) async {
    final label = Uri.encodeComponent(delivery.customerName);
    final coordinates = '${delivery.latitude},${delivery.longitude}';
    // `geo:` hands off to whichever nav app the driver actually uses; the web
    // URL is the fallback when no such app is installed.
    final candidates = [
      Uri.parse('geo:$coordinates?q=$coordinates($label)'),
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$coordinates'),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } on PlatformException {
        continue;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No maps app could handle this address.')),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy',
            ),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 18,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                notes,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trip.isActive ? 'Trip in progress' : 'Recorded trip',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text('Started ${formatDateTime(trip.startedAt)}'),
            if (trip.endedAt case final DateTime endedAt)
              Text('Finished ${formatDateTime(endedAt)}'),
            Text(
              'Distance driven ${formatDistance(trip.distanceMeters)} '
              'over ${formatDuration(trip.duration)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = delivery.status == DeliveryStatus.failed;
    final scheme = theme.colorScheme;
    final foreground = failed
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: failed ? scheme.errorContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed ? 'Not delivered' : 'Delivered',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            const SizedBox(height: 6),
            if (delivery.completedAt case final DateTime at)
              Text(formatDateTime(at), style: TextStyle(color: foreground)),
            if (delivery.recipientName case final String name)
              Text('Received by $name', style: TextStyle(color: foreground)),
            if (delivery.failureReason case final String reason)
              Text('Reason: $reason', style: TextStyle(color: foreground)),
            if (delivery.proofPhotoPath case final String path) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(path),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text(
                    'Proof photo is no longer on this device.',
                    style: TextStyle(color: foreground),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
