// =============================
// GCODE GENERATOR (Dart port of Python script)
// =============================

class GCodeGenerator {
  // Page settings (mm)
  static const double pageWidth = 210;
  static const double pageHeight = 297;
  static const double leftMargin = 5;
  static const double rightMargin = 5;
  static const double topMargin = 5;
  static const double bottomMargin = 20;
  static const double dotStep = 2.5;
  static const double dotDiameter = 1.4;

  static int get maxWidth =>
      ((pageWidth - leftMargin - rightMargin) / dotStep).floor();
  static int get maxHeight =>
      ((pageHeight - topMargin - bottomMargin) / dotStep).floor();

  /// Converts a flat RGBA pixel list into emboss dot points.
  /// [pixels]  – Uint8List from image.toByteData(format: ImageByteFormat.rawRgba)
  /// [srcW]    – original image width in pixels
  /// [srcH]    – original image height in pixels
  static List<List<double>> imagePixelsToPoints({
    required List<int> pixels,
    required int srcW,
    required int srcH,
  }) {
    // We work on a grid of (maxWidth × maxHeight) samples
    final int gridW = maxWidth;
    final int gridH = maxHeight;

    final List<List<double>> points = [];

    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        // Map grid cell → source pixel (nearest-neighbour)
        final int srcX = ((gx / gridW) * srcW).floor().clamp(0, srcW - 1);
        final int srcY = ((gy / gridH) * srcH).floor().clamp(0, srcH - 1);

        final int idx = (srcY * srcW + srcX) * 4; // RGBA
        final int r = pixels[idx];
        final int g = pixels[idx + 1];
        final int b = pixels[idx + 2];
        // greyscale luminance
        final double lum = 0.299 * r + 0.587 * g + 0.114 * b;

        if (lum < 120) {
          // "black" pixel → emboss point
          final double px = -rightMargin - gx * dotStep;
          final double py = -topMargin - gy * dotStep;
          points.add([px, py]);
        }
      }
    }
    return points;
  }

  /// Generates G-code string from dot points (mirrors Python logic exactly).
  static String generateGCode(List<List<double>> points) {
    // Sort: top rows first (descending y), then left-to-right
    final sorted = List<List<double>>.from(points)
      ..sort((a, b) {
        final cmp = b[1].compareTo(a[1]);
        return cmp != 0 ? cmp : b[0].compareTo(a[0]);
      });

    final buf = StringBuffer();
    buf.writeln('G21');
    buf.writeln('G90');
    buf.writeln('F10000');
    buf.writeln('G92 X0 Y0');
    buf.writeln();

    const punch = 'M3\nG4 P0.1\nM5';

    for (final p in sorted) {
      final double xp = p[0].abs();
      final double yp = p[1];
      buf.writeln('G1 X${xp.toStringAsFixed(2)} Y${yp.toStringAsFixed(2)}');
      buf.writeln(punch);
      buf.writeln();
    }

    buf.writeln('G1 X0 Y-310');
    return buf.toString();
  }
}
