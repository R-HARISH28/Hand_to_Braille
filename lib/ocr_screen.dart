import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'gcode_screen.dart';
import 'braille_preview_screen.dart';

class OCRScreen extends StatefulWidget {
  const OCRScreen({super.key});

  @override
  State<OCRScreen> createState() => _OCRScreenState();
}

class _OCRScreenState extends State<OCRScreen> {
  File? selectedImage;
  bool isLoading = false;

  final ImagePicker picker = ImagePicker();
  final String apiKey = "AIzaSyCfbAu23HdbMGOpID1FvNCi9QZOW601ous";
  final TextEditingController textController = TextEditingController();

  int monthlyCount = 0;
  final int monthlyLimit = 1000;

  @override
  void initState() {
    super.initState();
    loadCounter();
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COUNTER
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> loadCounter() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final savedMonth = prefs.getInt("month") ?? now.month;
    if (savedMonth != now.month) {
      await prefs.setInt("count", 0);
      await prefs.setInt("month", now.month);
    }
    setState(() => monthlyCount = prefs.getInt("count") ?? 0);
  }

  Future<void> incrementCounter() async {
    final prefs = await SharedPreferences.getInstance();
    monthlyCount++;
    await prefs.setInt("count", monthlyCount);
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // IMAGE PICKING
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> pickFromGallery() async {
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null) return;
    setState(() {
      selectedImage = File(image.path);
      textController.clear();
    });
  }

  Future<void> pickFromCamera() async {
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null) return;
    setState(() {
      selectedImage = File(image.path);
      textController.clear();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OCR
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> extractText() async {
    if (selectedImage == null) {
      _showError("Please select an image first");
      return;
    }
    if (monthlyCount >= monthlyLimit) {
      _showError("Monthly OCR limit reached");
      return;
    }

    setState(() => isLoading = true);

    try {
      final bytes = selectedImage!.readAsBytesSync();
      final base64Image = base64Encode(bytes);
      final url = Uri.parse(
          "https://vision.googleapis.com/v1/images:annotate?key=$apiKey");
      final body = jsonEncode({
        "requests": [
          {
            "image": {"content": base64Image},
            "features": [
              {"type": "TEXT_DETECTION"}
            ]
          }
        ]
      });

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["responses"][0].containsKey("error")) {
          _showError(
              "API Error: ${data["responses"][0]["error"]["message"]}");
          return;
        }
        textController.text =
            data["responses"][0]["textAnnotations"]?[0]["description"] ??
                "No text detected";
        await incrementCounter();
      } else if (response.statusCode == 403) {
        _showError(
            "API Key Error: Please check your Google Cloud Vision API setup\n"
                "1. Enable Cloud Vision API in Google Cloud Console\n"
                "2. Check API key restrictions\n"
                "3. Verify billing is enabled");
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData["error"]?["message"] ?? "Unknown error";
        _showError("OCR failed (${response.statusCode}): $errorMsg");
      }
    } catch (e) {
      _showError("Error during OCR: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHEET CONFIG  (mirrors Python make_sheet)
  // ─────────────────────────────────────────────────────────────────────────
  static const double _dotDistance = 2.7;
  static const double _cellGap     = 3.8;
  static const double _lineSpacing = 5.7;
  static const double _cellWidth   = _dotDistance + _cellGap;  // 6.5
  static const double _cellHeight  = (2 * _dotDistance) + _lineSpacing; // 11.1

  Map<String, dynamic> _makeSheet({
    required double width,
    required double height,
    double leftMargin   = 5,
    double rightMargin  = 5,
    double topMargin    = 5,
    double bottomMargin = 20,
  }) {
    final int cols =
    ((width - leftMargin - rightMargin) / _cellWidth).floor();
    final int rows =
    ((height - topMargin - bottomMargin) / _cellHeight).floor();
    return {
      "width":         width,
      "height":        height,
      "leftMargin":    leftMargin,
      "rightMargin":   rightMargin,
      "topMargin":     topMargin,
      "bottomMargin":  bottomMargin,
      "cols":          cols,
      "rows":          rows,
      "capacity":      cols * rows,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHEET PICKER DIALOG
  // ─────────────────────────────────────────────────────────────────────────

  // Controllers for custom sheet inputs
  final _wCtrl  = TextEditingController(text: "210");
  final _hCtrl  = TextEditingController(text: "297");
  final _lmCtrl = TextEditingController(text: "5");
  final _rmCtrl = TextEditingController(text: "5");
  final _tmCtrl = TextEditingController(text: "5");
  final _bmCtrl = TextEditingController(text: "20");

  Future<Map<String, dynamic>?> _showSheetPicker() async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        int selected = 0; // 0=A4, 1=A5, 2=Letter, 3=Custom
        bool showCustom = false;

        return StatefulBuilder(builder: (ctx, setS) {
          return AlertDialog(
            title: const Text(
              "Select Sheet Size",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.deepPurple),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Preset buttons ──────────────────────────────
                  _SheetOption(
                    label: "A4",
                    subtitle: "210 × 297 mm",
                    selected: selected == 0,
                    onTap: () => setS(() {
                      selected = 0;
                      showCustom = false;
                    }),
                  ),
                  _SheetOption(
                    label: "A5",
                    subtitle: "148 × 210 mm",
                    selected: selected == 1,
                    onTap: () => setS(() {
                      selected = 1;
                      showCustom = false;
                    }),
                  ),
                  _SheetOption(
                    label: "Letter",
                    subtitle: "216 × 279 mm",
                    selected: selected == 2,
                    onTap: () => setS(() {
                      selected = 2;
                      showCustom = false;
                    }),
                  ),
                  _SheetOption(
                    label: "Custom",
                    subtitle: "Enter your own dimensions",
                    selected: selected == 3,
                    onTap: () => setS(() {
                      selected = 3;
                      showCustom = true;
                    }),
                  ),

                  // ── Custom fields ───────────────────────────────
                  if (showCustom) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                            child: _NumField(
                                ctrl: _wCtrl, label: "Width (mm)")),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _NumField(
                                ctrl: _hCtrl, label: "Height (mm)")),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _NumField(
                                ctrl: _lmCtrl, label: "Left margin")),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _NumField(
                                ctrl: _rmCtrl, label: "Right margin")),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _NumField(
                                ctrl: _tmCtrl, label: "Top margin")),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _NumField(
                                ctrl: _bmCtrl, label: "Bottom margin")),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white),
                onPressed: () {
                  Map<String, dynamic> sheet;
                  switch (selected) {
                    case 0:
                      sheet = _makeSheet(width: 210, height: 297);
                      break;
                    case 1:
                      sheet = _makeSheet(width: 148, height: 210);
                      break;
                    case 2:
                      sheet = _makeSheet(width: 216, height: 279);
                      break;
                    default:
                      sheet = _makeSheet(
                        width:        double.tryParse(_wCtrl.text)  ?? 210,
                        height:       double.tryParse(_hCtrl.text)  ?? 297,
                        leftMargin:   double.tryParse(_lmCtrl.text) ?? 5,
                        rightMargin:  double.tryParse(_rmCtrl.text) ?? 5,
                        topMargin:    double.tryParse(_tmCtrl.text) ?? 5,
                        bottomMargin: double.tryParse(_bmCtrl.text) ?? 20,
                      );
                  }
                  Navigator.pop(ctx, sheet);
                },
                child: const Text("Generate"),
              ),
            ],
          );
        });
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BRAILLE G-CODE (updated to accept sheet config — mirrors Python exactly)
  // ─────────────────────────────────────────────────────────────────────────
  // Returns ({List<List<double>> points, String gcode})
  ({List<List<double>> points, String gcode}) generateBrailleGcode(
      String text, Map<String, dynamic> sheet) {
    const Map<int, List<double>> dotPosition = {
      1: [0, 0],
      2: [0, -_dotDistance],
      3: [0, -2 * _dotDistance],
      4: [-_dotDistance, 0],
      5: [-_dotDistance, -_dotDistance],
      6: [-_dotDistance, -2 * _dotDistance],
    };

    const Map<int, int> mirrorMap = {
      1: 4, 2: 5, 3: 6, 4: 1, 5: 2, 6: 3
    };

    const Map<String, List<int>> brailleMap = {
      'A': [4],       'B': [4, 5],     'C': [1, 4],     'D': [1, 2, 4],
      'E': [2, 4],    'F': [1, 4, 5],  'G': [1, 2, 4, 5],'H': [2, 4, 5],
      'I': [1, 5],    'J': [1, 2, 5],  'K': [4, 6],     'L': [4, 5, 6],
      'M': [1, 4, 6], 'N': [1, 2, 4, 6],'O': [2, 4, 6], 'P': [1, 4, 5, 6],
      'Q': [1, 2, 4, 5, 6], 'R': [2, 4, 5, 6], 'S': [1, 5, 6],
      'T': [1, 2, 5, 6], 'U': [3, 4, 6], 'V': [3, 4, 5, 6],
      'W': [1, 2, 3, 5], 'X': [1, 3, 4, 6], 'Y': [1, 2, 3, 4, 6],
      'Z': [2, 3, 4, 6],
    };

    const Map<String, List<int>> special = {
      '<': [1, 3, 5], '>': [2, 4, 6], '?': [3, 5, 6], ':': [2, 5],
      '-': [3, 6],    ';': [5, 6],    ')': [1, 2, 6],  '(': [3, 4, 5],
      '/': [1, 6],    '.': [2, 3, 5],
    };

    const Map<String, String> numMap = {
      '1': 'A', '2': 'B', '3': 'C', '4': 'D', '5': 'E',
      '6': 'F', '7': 'G', '8': 'H', '9': 'I', '0': 'J',
    };

    const Map<String, List<int>> wordContractions = {
      "for":  [1, 2, 3, 4, 5, 6], "but":  [4, 5],
      "the":  [1, 3, 5, 6],        "like": [4, 5, 6],
      "from": [1, 4, 5],           "do":   [1, 2, 4],
      "just": [1, 2, 5],           "that": [1, 2, 5, 6],
      "will": [1, 2, 3, 5],        "you":  [1, 2, 3, 4, 6],
      "not":  [1, 2, 4, 6],        "more": [1, 4, 6],
    };

    const List<int> capital = [3];
    const List<int> number  = [1, 2, 3, 6];

    // ── Sheet values ──────────────────────────────────────────────────────
    final int    cols         = sheet["cols"];
    final int    rows         = sheet["rows"];
    final double rightMargin  = sheet["rightMargin"];
    final double topMargin    = sheet["topMargin"];

    // ── Clean text (same valid set as Python) ─────────────────────────────
    const String validChars =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "0123456789 <>?:-;()/.";
    text = text.split('').where((c) => validChars.contains(c)).join();

    // ── Text → cells ──────────────────────────────────────────────────────
    List<List<int>> cells = [];
    bool inNumber = false;
    final List<String> words = text.split(" ");

    for (int w = 0; w < words.length; w++) {
      final String word  = words[w];
      final String lower = word.toLowerCase();

      if (wordContractions.containsKey(lower)) {
        if (word == word.toUpperCase() && word.isNotEmpty) {
          cells.add(List<int>.from(capital));
        }
        cells.add(List<int>.from(wordContractions[lower]!));
      } else {
        for (final ch in word.split('')) {
          if (RegExp(r'\d').hasMatch(ch)) {
            if (!inNumber) {
              cells.add(List<int>.from(number));
              inNumber = true;
            }
            cells.add(List<int>.from(brailleMap[numMap[ch]!]!));
          } else if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
            inNumber = false;
            if (ch == ch.toUpperCase()) {
              cells.add(List<int>.from(capital));
              cells.add(List<int>.from(brailleMap[ch]!));
            } else {
              cells.add(List<int>.from(brailleMap[ch.toUpperCase()]!));
            }
          } else if (special.containsKey(ch)) {
            inNumber = false;
            cells.add(List<int>.from(special[ch]!));
          }
        }
      }

      if (w < words.length - 1) cells.add([]);
    }

    // ── Layout cells on sheet ─────────────────────────────────────────────
    List<List<double>> points = [];
    int col = 0;
    int row = 0;

    final double startX = -rightMargin;
    final double startY = -topMargin;

    for (final cell in cells) {
      if (col >= cols) {
        col = 0;
        row++;
      }
      // Overflow: stop if beyond page rows
      if (row >= rows) break;

      final double baseX = startX - col * _cellWidth;
      final double baseY = startY - row * _cellHeight;

      for (int dot in cell) {
        dot = mirrorMap[dot]!;
        final pos = dotPosition[dot]!;
        points.add([baseX + pos[0], baseY + pos[1]]);
      }

      col++;
    }

    // ── Sort: top rows first, then left-to-right ──────────────────────────
    points.sort((a, b) {
      if (a[1] != b[1]) return b[1].compareTo(a[1]);
      return b[0].compareTo(a[0]);
    });

    // ── Build G-code (matches Python output exactly) ──────────────────────
    final buf = StringBuffer();
    buf.writeln("G21");
    buf.writeln("G90");
    buf.writeln("F10000");
    buf.writeln("G92 X0 Y0\nG1 Y-80\nG92 X0 Y0");
    buf.writeln();

    const String punch = "M3\nG4 P0.1\nM5";

    for (final p in points) {
      final double xp = p[0].abs();
      final double yp = p[1];
      buf.writeln("G1 X${xp.toStringAsFixed(1)} Y${yp.toStringAsFixed(1)}");
      buf.writeln(punch);
      buf.writeln();
    }

    buf.writeln("G1 X0 Y-310");
    return (points: points, gcode: buf.toString());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GENERATE G-CODE — shows sheet picker first
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> generateGcode() async {
    if (textController.text.isEmpty) {
      _showError("No text to generate G-code from");
      return;
    }

    // Show sheet size picker dialog
    final sheet = await _showSheetPicker();
    if (sheet == null) return; // user cancelled

    final result = generateBrailleGcode(textController.text, sheet);

    if (!mounted) return;

    // Navigate to print preview first — user can proceed to G-code from there
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BraillePreviewScreen(
          data: BraillePreviewData(
            points: result.points,
            sheet: sheet,
            gcode: result.gcode,
            originalText: textController.text,
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Handwritten to Text"),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(
                "$monthlyCount / $monthlyLimit",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Image Preview
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: selectedImage != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(selectedImage!, fit: BoxFit.contain),
                  )
                      : const Center(
                    child: Text("No image selected",
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),

                const SizedBox(height: 16),

                // Gallery / Camera
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : pickFromGallery,
                          icon: const Icon(Icons.photo),
                          label: const Text("Gallery"),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : pickFromCamera,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text("Camera"),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Extract Text
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : extractText,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: isLoading
                        ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text("Extracting Text..."),
                      ],
                    )
                        : const Text("Extract Text"),
                  ),
                ),

                const SizedBox(height: 16),

                // Editable text field
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                      hintText: "Extracted text will appear here...",
                      labelText: "Editable Text (Correct spelling)",
                      labelStyle: TextStyle(fontSize: 14),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Generate G-code button (opens sheet picker)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : generateGcode,
                    icon: const Icon(Icons.code),
                    label: const Text("Generate G-code"),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets for the sheet picker dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SheetOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SheetOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.deepPurple : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Colors.white : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: selected ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;

  const _NumField({required this.ctrl, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
