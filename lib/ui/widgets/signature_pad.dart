import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A finger-drawn signature.
///
/// Hand-rolled rather than pulled from a package: it is a few dozen lines of
/// gesture handling and a `CustomPainter`, and a signature is proof of
/// delivery — worth being able to read every line of.
///
/// Strokes are kept as separate polylines rather than one list of points, so
/// lifting a finger between the first and last name does not draw a line
/// across the gap.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    this.height = 180,
    this.strokeWidth = 2.8,
    this.onChanged,
    this.borderColor,
  });

  final double height;
  final double strokeWidth;

  /// Fired with whether the pad now holds a usable signature, so a caller
  /// enforcing "signature required" does not have to poll the state.
  final ValueChanged<bool>? onChanged;

  /// Overrides the border, so a required pad can read as outstanding.
  final Color? borderColor;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;

  bool get isEmpty => _strokes.every((stroke) => stroke.length < 2);

  void clear() {
    setState(_strokes.clear);
    widget.onChanged?.call(false);
  }

  void _start(Offset at) => setState(() => _strokes.add([at]));

  void _extend(Offset at) {
    if (_strokes.isEmpty) return;
    final wasEmpty = isEmpty;
    setState(() => _strokes.last.add(at));
    // Fires on the stroke's second point — the first one alone is a tap, not
    // a signature.
    if (wasEmpty && !isEmpty) widget.onChanged?.call(true);
  }

  /// Rasterises what is on the pad to a PNG beside the proof photos.
  ///
  /// Returns null if nothing was drawn, so an untouched pad does not litter
  /// storage with blank images.
  Future<String?> save({required String reference}) async {
    if (isEmpty || _canvasSize.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White rather than transparent: a signature in black on transparent is
    // invisible in any viewer that defaults to a dark background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _canvasSize.width, _canvasSize.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    _paintStrokes(canvas, const Color(0xFF000000));

    final image = await recorder.endRecording().toImage(
      _canvasSize.width.round(),
      _canvasSize.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;

    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(documents.path, 'proofs'));
    if (!await folder.exists()) await folder.create(recursive: true);

    final target = p.join(
      folder.path,
      '${reference}_signature_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await File(target).writeAsBytes(
      Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return target;
  }

  void _paintStrokes(Canvas canvas, Color color) {
    final brush = Paint()
      ..color = color
      ..strokeWidth = widget.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, brush);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          // Opaque so a drag starting on the pad is not stolen by the
          // scrolling sheet underneath it.
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _start(details.localPosition),
          onPanUpdate: (details) => _extend(details.localPosition),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.borderColor ?? scheme.outlineVariant,
                width: widget.borderColor == null ? 1 : 1.5,
              ),
            ),
            child: CustomPaint(
              painter: _SignaturePainter(
                strokes: _strokes,
                color: scheme.onSurface,
                strokeWidth: widget.strokeWidth,
              ),
              child: isEmpty
                  ? Center(
                      child: Text(
                        'Sign here',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, brush);
    }
  }

  // The stroke list is mutated in place, so identity comparison would miss
  // every new point.
  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
