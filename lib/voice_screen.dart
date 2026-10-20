import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice to Text',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const VoiceToTextPage(),
    );
  }
}

class VoiceToTextPage extends StatefulWidget {
  const VoiceToTextPage({super.key});

  @override
  State<VoiceToTextPage> createState() => _VoiceToTextPageState();
}

class _VoiceToTextPageState extends State<VoiceToTextPage> {
  final SpeechToText _speechToText = SpeechToText();

  // TextEditingController so the user can edit the recognized text
  final TextEditingController _textController = TextEditingController();

  bool _speechEnabled = false;
  bool _isListening = false;
  String _statusMessage = 'Tap "Start Listening" to begin';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // Initialize speech recognition
  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (error) {
        setState(() {
          if (error.errorMsg == 'error_no_match') {
            _statusMessage = 'Could not hear you. Try again!';
          } else {
            _statusMessage = 'Error: ${error.errorMsg}';
          }
          _isListening = false;
        });
      },
      onStatus: (status) {
        setState(() {
          _isListening = _speechToText.isListening;
          if (status == 'done' || status == 'notListening') {
            _statusMessage = 'Tap "Start Listening" to begin';
            _isListening = false;
          }
        });
      },
      debugLogging: true,
    );
    setState(() {});
  }

  Future<void> _startListening() async {
    setState(() {
      _statusMessage = 'Listening...';
      _isListening = true;
      _textController.clear(); // clear previous text when starting fresh
    });

    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_US',
      cancelOnError: false,
      partialResults: true,
    );
  }

  // Stop listening
  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _statusMessage = 'Tap "Start Listening" to begin';
      _isListening = false;
    });
  }

  // Called every time speech is recognized (partial or final)
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _textController.text = result.recognizedWords;
      // Move cursor to end
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    });
  }

  // Copy text to clipboard
  Future<void> _copyText() async {
    if (_textController.text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _textController.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Text copied to clipboard!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Clear text
  void _clearText() {
    setState(() {
      _textController.clear();
      _statusMessage = 'Tap "Start Listening" to begin';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool hasText = _textController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Voice to Text'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear Text',
            onPressed: hasText ? _clearText : null,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ── Status Bar ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isListening
                    ? Colors.green.shade100
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _isListening ? Icons.mic : Icons.mic_off,
                    color: _isListening ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      color:
                      _isListening ? Colors.green.shade800 : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Editable Text Area ───────────────────────────────────────
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 18, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Your speech will appear here...\nYou can also type or edit directly.',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 16),
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                    BorderSide(color: Colors.deepPurple.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: Colors.deepPurple.shade400, width: 2),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Start / Stop Listening Buttons ───────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                    (_speechEnabled && !_isListening) ? _startListening : null,
                    icon: const Icon(Icons.mic),
                    label: const Text('Start Listening'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isListening ? _stopListening : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop Listening'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Copy Button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasText ? _copyText : null,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Text'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade100,
                  foregroundColor: Colors.deepPurple.shade900,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
