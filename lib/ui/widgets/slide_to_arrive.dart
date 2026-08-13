import 'package:flutter/material.dart';

import '../../services/app_haptics.dart';
import 'outcome_colors.dart';

/// Slide to complete a delivery.
///
/// A tap is easy to hit by accident on a phone bouncing around a van, and
/// closing out the wrong stop is a nuisance to undo — so completing takes a
/// deliberate gesture across the whole width of the panel.
///
/// Written here rather than taken from the haptics package because the handle
/// has a job to do while it moves: the arrow becomes a tick as the driver
/// slides, so the gesture shows its own outcome rather than switching from
/// one glyph to another at the end. The package's version only swaps the icon
/// once the slide is already over, which tells the driver nothing while they
/// are doing it.
class SlideToArrive extends StatefulWidget {
  const SlideToArrive({
    super.key,
    required this.onConfirmed,
    this.label = 'Slide when you have arrived',
    this.height = 60,
    this.enabled = true,
  });

  final VoidCallback onConfirmed;
  final String label;
  final double height;
  final bool enabled;

  @override
  State<SlideToArrive> createState() => SlideToArriveState();
}

class SlideToArriveState extends State<SlideToArrive>
    with SingleTickerProviderStateMixin {
  /// 0 is parked at the left, 1 is confirmed.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Quarter-way buzzes, so the driver can feel the slide working without
  /// watching it.
  static const _ticks = [0.25, 0.5, 0.75];
  final _felt = <double>{};

  bool _dragging = false;
  bool _confirmed = false;
  double _trackWidth = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Re-arms after a confirmation the caller decided not to act on — the
  /// driver cancelled the completion sheet, or a required photo blocked it.
  void reset() {
    if (_dragging) return;
    setState(() {
      _confirmed = false;
      _felt.clear();
    });
    _controller.animateBack(0, curve: Curves.easeOut);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _confirmed || _trackWidth <= 0) return;
    _dragging = true;

    final next = (_controller.value + details.delta.dx / _trackWidth).clamp(
      0.0,
      1.0,
    );
    _controller.value = next;

    for (final tick in _ticks) {
      if (next >= tick && _felt.add(tick)) AppHaptics.select();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    if (!widget.enabled || _confirmed) return;

    // Most of the way is enough. Demanding the last few pixels means a
    // gloved thumb that runs out of screen has to start again.
    if (_controller.value >= 0.9) {
      setState(() => _confirmed = true);
      _controller.animateTo(1, curve: Curves.easeOut);
      AppHaptics.delivered();
      widget.onConfirmed();
      return;
    }

    _felt.clear();
    _controller.animateBack(0, curve: Curves.easeOutBack);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.enabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final handleSize = widget.height - 8;
        _trackWidth = constraints.maxWidth - handleSize - 8;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            // The track fills with the delivered green as the slide goes on,
            // so the colour arrives at the same time the tick does.
            final fill = Color.lerp(
              scheme.surfaceContainerHighest,
              context.deliveredContainer,
              progress,
            )!;

            return GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: enabled ? fill : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(widget.height / 2),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // The instruction fades out as the handle covers it.
                    Center(
                      child: Opacity(
                        opacity: (1 - progress * 1.6).clamp(0.0, 1.0),
                        child: Text(
                          widget.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Transform.translate(
                        offset: Offset(progress * _trackWidth, 0),
                        child: Container(
                          width: handleSize,
                          height: handleSize,
                          decoration: BoxDecoration(
                            color: enabled
                                ? Color.lerp(
                                    scheme.primary,
                                    context.delivered,
                                    progress,
                                  )!
                                : scheme.outline,
                            shape: BoxShape.circle,
                          ),
                          child: CustomPaint(
                            painter: _ArrowToTickPainter(
                              progress: progress,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Draws an arrow that becomes a tick.
///
/// Both marks are the same three-point stroke, so morphing between them is a
/// matter of moving three points: the arrowhead's chevron opens out and drops
/// into the tick's angle while the shaft behind it fades. That reads as one
/// mark changing its mind rather than two glyphs swapping over.
class _ArrowToTickPainter extends CustomPainter {
  const _ArrowToTickPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  /// The chevron of an arrow: up-right, point, down-right.
  static const _arrow = [
    Offset(0.46, 0.28),
    Offset(0.72, 0.5),
    Offset(0.46, 0.72),
  ];

  /// A tick: down to the elbow, then up and away.
  static const _tick = [
    Offset(0.26, 0.52),
    Offset(0.44, 0.70),
    Offset(0.76, 0.30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Eased so most of the change happens in the second half of the slide,
    // where the driver is already committed.
    final t = Curves.easeInOutCubic.transform(progress.clamp(0.0, 1.0));
    final stroke = size.width * 0.09;

    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // The shaft belongs to the arrow only, so it thins away as the tick forms.
    final shaftOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
    if (shaftOpacity > 0) {
      canvas.drawLine(
        Offset(size.width * 0.24, size.height * 0.5),
        Offset(size.width * 0.66, size.height * 0.5),
        Paint()
          ..color = color.withValues(alpha: shaftOpacity)
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    final path = Path();
    for (var i = 0; i < _arrow.length; i++) {
      final point = Offset.lerp(_arrow[i], _tick[i], t)!;
      final at = Offset(point.dx * size.width, point.dy * size.height);
      i == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowToTickPainter old) =>
      old.progress != progress || old.color != color;
}
