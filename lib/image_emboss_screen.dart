import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'gcode_generator.dart';

class ImageEmbossScreen extends StatefulWidget {
  const ImageEmbossScreen({super.key});

  @override
  State<ImageEmbossScreen> createState() => _ImageEmbossScreenState();
}

class _ImageEmbossScreenState extends State<ImageEmbossScreen> {
  // ── State ────────────────────────────────────────────────────────────────
  Uint8List? _imageBytes;       // raw file bytes (for display)
  ui.Image? _decodedImage;      // decoded for pixel access
  List<List<double>> _points = [];
  String _gcode = '';
  bool _processing = false;
  bool _gcodeReady = false;
  String _statusMsg = 'Select an image to begin';

  final ImagePicker _picker = ImagePicker();
  final ScrollController _gcodeScroll = ScrollController();

  @override
  void dispose() {
    _gcodeScroll.dispose();
    super.dispose();
  }

  // ── Pick image ───────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(source: source);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    setState(() {
      _imageBytes = bytes;
      _decodedImage = frame.image;
      _points = [];
      _gcode = '';
      _gcodeReady = false;
      _statusMsg = 'Image loaded — tap "Extract & Preview" to process';
    });
  }

  // ── Process image → points ───────────────────────────────────────────────
  Future<void> _extractPoints() async {
    if (_decodedImage == null) return;

    setState(() {
      _processing = true;
      _statusMsg = 'Processing image…';
    });

    // Read raw RGBA bytes from the decoded image
    final byteData = await _decodedImage!
        .toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      setState(() {
        _processing = false;
        _statusMsg = 'Failed to read image pixels';
      });
      return;
    }

    final pixels = byteData.buffer.asUint8List();
    final points = GCodeGenerator.imagePixelsToPoints(
      pixels: pixels,
      srcW: _decodedImage!.width,
      srcH: _decodedImage!.height,
    );

    setState(() {
      _points = points;
      _processing = false;
      _statusMsg =
      '${points.length} emboss points found — tap "Generate G-code"';
    });
  }

  // ── Generate G-code ──────────────────────────────────────────────────────
  void _generateGCode() {
    if (_points.isEmpty) return;
    setState(() {
      _processing = true;
      _statusMsg = 'Generating G-code…';
    });

    // Run synchronously (fast enough for typical dot counts)
    final code = GCodeGenerator.generateGCode(_points);

    setState(() {
      _gcode = code;
      _gcodeReady = true;
      _processing = false;
      _statusMsg = 'G-code ready — ${_gcode.split('\n').length} lines';
    });
  }

  // ── Copy G-code ──────────────────────────────────────────────────────────
  Future<void> _copyGCode() async {
    await Clipboard.setData(ClipboardData(text: _gcode));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('G-code copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Preview painter ──────────────────────────────────────────────────────
  Widget _buildPreview() {
    return LayoutBuilder(builder: (context, constraints) {
      return CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _DotPreviewPainter(
          points: _points,
          pageWidth: GCodeGenerator.pageWidth,
          pageHeight: GCodeGenerator.pageHeight,
          dotDiameter: GCodeGenerator.dotDiameter,
        ),
      );
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F0FB),
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: const Text('Image Emboss → G-code'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image preview / placeholder ─────────────────────────
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.deepPurple.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _imageBytes != null
                  ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                  : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined,
                        size: 48, color: Colors.deepPurple),
                    SizedBox(height: 8),
                    Text('No image selected',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Gallery / Camera buttons ────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: Colors.deepPurple,
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    color: Colors.deepPurple,
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Extract & Preview button ────────────────────────────
            _ActionButton(
              icon: Icons.auto_fix_high,
              label: 'Extract & Preview',
              color: Colors.indigo,
              onPressed: _imageBytes != null && !_processing
                  ? _extractPoints
                  : null,
            ),

            const SizedBox(height: 16),

            // ── Status ──────────────────────────────────────────────
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_processing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.deepPurple),
                    )
                  else
                    const Icon(Icons.info_outline,
                        size: 18, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_statusMsg,
                        style: TextStyle(
                            color: Colors.deepPurple.shade800,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),

            // ── Dot Preview canvas ───────────────────────────────────
            if (_points.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Emboss Preview',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.deepPurple)),
              const SizedBox(height: 8),
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.deepPurple.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildPreview(),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Generate G-code button ───────────────────────────────
            if (_points.isNotEmpty)
              _ActionButton(
                icon: Icons.code,
                label: 'Generate G-code',
                color: Colors.deepPurple.shade700,
                onPressed: !_processing ? _generateGCode : null,
              ),

            // ── G-code output ────────────────────────────────────────
            if (_gcodeReady) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Generated G-code',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.deepPurple)),
                  TextButton.icon(
                    onPressed: _copyGCode,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.deepPurple),
                  ),
                ],
              ),
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Scrollbar(
                  controller: _gcodeScroll,
                  child: SingleChildScrollView(
                    controller: _gcodeScroll,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _gcode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF89DDFF),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Large copy button at bottom
              _ActionButton(
                icon: Icons.copy_all,
                label: 'Copy G-code',
                color: Colors.teal.shade700,
                onPressed: _copyGCode,
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Reusable action button ────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle:
        const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Dot preview CustomPainter ─────────────────────────────────────────────────
class _DotPreviewPainter extends CustomPainter {
  final List<List<double>> points;
  final double pageWidth;
  final double pageHeight;
  final double dotDiameter;

  _DotPreviewPainter({
    required this.points,
    required this.pageWidth,
    required this.pageHeight,
    required this.dotDiameter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw page background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    if (points.isEmpty) return;

    // Scale: map [-pageWidth..0] x [-pageHeight..0] → [0..size.width] x [0..size.height]
    final double scaleX = size.width / pageWidth;
    final double scaleY = size.height / pageHeight;
    final double dotR = (dotDiameter * ((scaleX + scaleY) / 2)) / 2;

    final paint = Paint()
      ..color = Colors.deepPurple.shade700
      ..style = PaintingStyle.fill;

    for (final p in points) {
      // px is negative (−rightMargin − x*step), map to canvas x
      final double cx = (p[0].abs()) * scaleX;
      // py is negative (−topMargin − y*step), map to canvas y
      final double cy = (p[1].abs()) * scaleY;
      canvas.drawCircle(Offset(cx, cy), dotR.clamp(0.5, 4.0), paint);
    }
  }

  @override
  bool shouldRepaint(_DotPreviewPainter old) => old.points != points;
}
