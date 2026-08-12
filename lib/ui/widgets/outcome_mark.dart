import 'package:flutter/material.dart';

/// The tick or cross at the top of the outcome sheet, drawn rather than set as
/// a static icon.
///
/// The stroke is animated on: the mark draws itself the way someone would sign
/// it off, which reads as "this happened just now" in a way a glyph appearing
/// at full size does not.
///
/// The colours are fixed rather than taken from the scheme. Green means
/// delivered and red means not, in every accent — pulling `tertiary` here made
/// a successful drop look orange under Hi-vis and red under Cargo red, which
/// is worse than not colouring it at all.
class OutcomeMark extends StatefulWidget {
  const OutcomeMark({super.key, required this.failed, this.size = 88});

  final bool failed;
  final double size;

  /// Delivered. Readable on both light and dark surfaces.
  static const success = Color(0xFF2E7D32);
  static const successDark = Color(0xFF66BB6A);

  static const failure = Color(0xFFC62828);
  static const failureDark = Color(0xFFEF5350);

  static Color colorFor({
    required bool failed,
    required Brightness brightness,
  }) {
    final dark = brightness == Brightness.dark;
    if (failed) return dark ? failureDark : failure;
    return dark ? successDark : success;
  }

  @override
  State<OutcomeMark> createState() => _OutcomeMarkState();
}

class _OutcomeMarkState extends State<OutcomeMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    // Long enough to read as a gesture, short enough not to delay a driver
    // who does eighty of these a day.
    duration: const Duration(milliseconds: 620),
    vsync: this,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = OutcomeMark.colorFor(
      failed: widget.failed,
      brightness: brightness,
    );

    // The ring scales in first, then the stroke draws inside it.
    final ring = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.45, curve: Curves.easeOutBack),
    );
    final stroke = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _MarkPainter(
            failed: widget.failed,
            color: color,
            ringProgress: ring.value,
            strokeProgress: stroke.value,
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.failed,
    required this.color,
    required this.ringProgress,
    required this.strokeProgress,
  });

  final bool failed;
  final Color color;
  final double ringProgress;
  final double strokeProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * ringProgress.clamp(0.0, 1.0);
    if (radius <= 0) return;

    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = color.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      centre,
      radius - 1.5,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    if (strokeProgress <= 0) return;

    final brush = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final path in failed ? _crossPaths(size) : [_tickPath(size)]) {
      canvas.drawPath(_partial(path, strokeProgress), brush);
    }
  }

  /// A tick, in fractions of the box: down to the elbow, then up.
  Path _tickPath(Size size) => Path()
    ..moveTo(size.width * 0.28, size.height * 0.52)
    ..lineTo(size.width * 0.44, size.height * 0.68)
    ..lineTo(size.width * 0.73, size.height * 0.34);

  /// Two strokes so the cross draws as an X rather than as one folded line.
  List<Path> _crossPaths(Size size) => [
    Path()
      ..moveTo(size.width * 0.33, size.height * 0.33)
      ..lineTo(size.width * 0.67, size.height * 0.67),
    Path()
      ..moveTo(size.width * 0.67, size.height * 0.33)
      ..lineTo(size.width * 0.33, size.height * 0.67),
  ];

  /// The first [progress] of [path] by arc length, which is what makes the
  /// stroke look drawn rather than faded in.
  Path _partial(Path path, double progress) {
    if (progress >= 1) return path;
    final drawn = Path();
    for (final metric in path.computeMetrics()) {
      drawn.addPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        Offset.zero,
      );
    }
    return drawn;
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.ringProgress != ringProgress ||
      old.strokeProgress != strokeProgress ||
      old.color != color ||
      old.failed != failed;
}
