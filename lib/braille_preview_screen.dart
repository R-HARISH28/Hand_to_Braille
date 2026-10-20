import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'gcode_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

class BraillePreviewData {
  final List<List<double>> points; // dot coordinates in mm (negative quadrant)
  final Map<String, dynamic> sheet;
  final String gcode;
  final String originalText;

  const BraillePreviewData({
    required this.points,
    required this.sheet,
    required this.gcode,
    required this.originalText,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PREVIEW SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class BraillePreviewScreen extends StatefulWidget {
  final BraillePreviewData data;

  const BraillePreviewScreen({super.key, required this.data});

  @override
  State<BraillePreviewScreen> createState() => _BraillePreviewScreenState();
}

class _BraillePreviewScreenState extends State<BraillePreviewScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
  TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _resetAnimation;

  // Info panel toggle
  bool _showInfo = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
      if (_resetAnimation != null) {
        _transformController.value = _resetAnimation!.value;
      }
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _resetAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward(from: 0);
  }

  void _proceedToGCode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GCodeScreen(gcode: widget.data.gcode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.data.sheet;
    final double sheetW = sheet["width"] as double;
    final double sheetH = sheet["height"] as double;
    final int totalDots = widget.data.points.length;
    final int cols = sheet["cols"] as int;
    final int rows = sheet["rows"] as int;

    return Scaffold(
      backgroundColor: const Color(0xFF2A2A3E),
      appBar: AppBar(
        backgroundColor: Colors.deepPurple.shade800,
        foregroundColor: Colors.white,
        title: const Text(
          'Print Preview',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        centerTitle: true,
        actions: [
          // Info toggle
          IconButton(
            icon: Icon(_showInfo ? Icons.info : Icons.info_outline),
            tooltip: 'Sheet info',
            onPressed: () => setState(() => _showInfo = !_showInfo),
          ),
          // Reset zoom
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Reset zoom',
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Info panel ──────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _showInfo
                ? _InfoPanel(
              sheetW: sheetW,
              sheetH: sheetH,
              cols: cols,
              rows: rows,
              totalDots: totalDots,
              text: widget.data.originalText,
            )
                : const SizedBox.shrink(),
          ),

          // ── Paper preview (pinch/zoom/pan) ──────────────────────────────
          Expanded(
            child: Container(
              color: const Color(0xFF1E1E2E),
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.3,
                maxScale: 8.0,
                boundaryMargin: const EdgeInsets.all(120),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _PaperWidget(data: widget.data),
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom action bar ───────────────────────────────────────────
          _BottomBar(onProceed: _proceedToGCode),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO PANEL
// ─────────────────────────────────────────────────────────────────────────────

class _InfoPanel extends StatelessWidget {
  final double sheetW, sheetH;
  final int cols, rows, totalDots;
  final String text;

  const _InfoPanel({
    required this.sheetW,
    required this.sheetH,
    required this.cols,
    required this.rows,
    required this.totalDots,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final preview = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.deepPurple.shade900,
      child: Wrap(
        spacing: 20,
        runSpacing: 6,
        children: [
          _Chip(label: 'Sheet', value: '${sheetW.toInt()}×${sheetH.toInt()} mm'),
          _Chip(label: 'Grid', value: '$cols cols × $rows rows'),
          _Chip(label: 'Dots', value: '$totalDots'),
          _Chip(label: 'Text', value: '"$preview"'),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, value;
  const _Chip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
              text: '$label: ',
              style: TextStyle(color: Colors.deepPurple.shade200)),
          TextSpan(
              text: value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAPER WIDGET — white sheet with dots painted on it
// ─────────────────────────────────────────────────────────────────────────────

class _PaperWidget extends StatelessWidget {
  final BraillePreviewData data;

  const _PaperWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final sheet = data.sheet;
    final double sheetW = sheet["width"] as double;
    final double sheetH = sheet["height"] as double;

    // Render the paper at 2px per mm for sharpness
    const double pxPerMm = 2.0;
    final double paperPxW = sheetW * pxPerMm;
    final double paperPxH = sheetH * pxPerMm;

    return Container(
      width: paperPxW,
      height: paperPxH,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 4,
            offset: const Offset(4, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          size: Size(paperPxW, paperPxH),
          painter: _BraillePainter(
            points: data.points,
            sheet: sheet,
            pxPerMm: pxPerMm,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _BraillePainter extends CustomPainter {
  final List<List<double>> points;
  final Map<String, dynamic> sheet;
  final double pxPerMm;

  static const double dotDiameter = 1.4; // mm

  _BraillePainter({
    required this.points,
    required this.sheet,
    required this.pxPerMm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double sheetW = sheet["width"] as double;
    final double sheetH = sheet["height"] as double;
    final double lm     = sheet["leftMargin"]   as double;
    final double rm     = sheet["rightMargin"]  as double;
    final double tm     = sheet["topMargin"]    as double;
    final double bm     = sheet["bottomMargin"] as double;

    // ── White page background ─────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // ── Margin border (red dashed) ────────────────────────────────────────
    final marginPaint = Paint()
      ..color = Colors.red.withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Printable area on canvas: rm from left, lm from right, tm from top, bm from bottom
    final double pLeft  = rm * pxPerMm;
    final double pRight = (sheetW - lm) * pxPerMm;
    final double pTop   = tm * pxPerMm;
    final double pBot   = (sheetH - bm) * pxPerMm;

    _drawDashedRect(canvas, Rect.fromLTRB(pLeft, pTop, pRight, pBot), marginPaint, 6, 4);

    // ── Dots ──────────────────────────────────────────────────────────────
    final dotPaint = Paint()
      ..color = Colors.deepPurple.shade700
      ..style = PaintingStyle.fill;

    final double dotR = (dotDiameter / 2) * pxPerMm;

    for (final p in points) {
      // Coordinate mapping:
      // p[0] is in range [−sheetW .. 0]  → canvas x = (sheetW + p[0]) * pxPerMm
      // p[1] is in range [−sheetH .. 0]  → canvas y = (sheetH + p[1]) * pxPerMm  --- WRONG
      // Actually p[1] = −topMargin − row*cellHeight, so:
      // canvas x = abs(p[0]) ... but p[0] = −rightMargin − col*cellWidth
      // so canvas x = (sheetW - abs(p[0])) * pxPerMm  →  mirrored left
      // Simpler: canvas_x = (sheetW + p[0]) * pxPerMm  (p[0] is negative)
      //          canvas_y = -p[1] * pxPerMm            (p[1] is negative)
      // p[0] = −rightMargin − col*cellWidth  (negative)  → canvas x = abs(p[0]) * pxPerMm
      // p[1] = −topMargin   − row*cellHeight (negative)  → canvas y = abs(p[1]) * pxPerMm
      final double cx = p[0].abs() * pxPerMm;
      final double cy = p[1].abs() * pxPerMm;
      canvas.drawCircle(Offset(cx, cy), dotR.clamp(1.5, 5.0), dotPaint);
    }

    // ── Corner crop marks ─────────────────────────────────────────────────
    final cropPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 0.8;

    const double cropLen = 8.0;
    // top-left
    canvas.drawLine(const Offset(0, 0), Offset(cropLen, 0), cropPaint);
    canvas.drawLine(const Offset(0, 0), Offset(0, cropLen), cropPaint);
    // top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cropLen, 0), cropPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cropLen), cropPaint);
    // bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(cropLen, size.height), cropPaint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cropLen), cropPaint);
    // bottom-right
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - cropLen, size.height), cropPaint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - cropLen), cropPaint);
  }

  /// Draws a dashed rectangle
  void _drawDashedRect(
      Canvas canvas, Rect rect, Paint paint, double dash, double gap) {
    final path = Path();
    // top
    _dashLine(path, Offset(rect.left, rect.top), Offset(rect.right, rect.top), dash, gap);
    // right
    _dashLine(path, Offset(rect.right, rect.top), Offset(rect.right, rect.bottom), dash, gap);
    // bottom
    _dashLine(path, Offset(rect.right, rect.bottom), Offset(rect.left, rect.bottom), dash, gap);
    // left
    _dashLine(path, Offset(rect.left, rect.bottom), Offset(rect.left, rect.top), dash, gap);
    canvas.drawPath(path, paint);
  }

  void _dashLine(Path path, Offset start, Offset end, double dash, double gap) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = (Offset(dx, dy)).distance;
    final nx = dx / len;
    final ny = dy / len;
    double d = 0;
    bool drawing = true;
    double x = start.dx;
    double y = start.dy;
    while (d < len) {
      final step = drawing ? dash : gap;
      final next = (d + step).clamp(0, len);
      final nx2 = start.dx + nx * next;
      final ny2 = start.dy + ny * next;
      if (drawing) {
        path.moveTo(x, y);
        path.lineTo(nx2, ny2);
      }
      x = nx2;
      y = ny2;
      d += step;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(_BraillePainter old) => old.points != points;
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM BAR
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final VoidCallback onProceed;
  const _BottomBar({required this.onProceed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade900,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Row(
        children: [
          // Legend
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text('Emboss dot',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 16),
              Container(
                width: 12,
                height: 3,
                color: Colors.red.withOpacity(0.5),
              ),
              const SizedBox(width: 6),
              const Text('Margin',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),

          const Spacer(),

          // Proceed button
          ElevatedButton.icon(
            onPressed: onProceed,
            icon: const Icon(Icons.code, size: 18),
            label: const Text('View G-code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
