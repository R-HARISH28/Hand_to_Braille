import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GCodeScreen extends StatefulWidget {

  final String gcode;

  const GCodeScreen({
    super.key,
    required this.gcode,
  });

  @override
  State<GCodeScreen> createState() => _GCodeScreenState();
}

class _GCodeScreenState extends State<GCodeScreen> {

  late TextEditingController gcodeController;

  bool isSending = false;

  final String espIp = "192.168.4.1";

  // =========================
  // JOG COMMANDS
  // =========================

  final String jogXP = """
G91
G1 X10 F1000
G90
""";

  final String jogXN = """
G91
G1 X-10 F1000
G90
""";

  final String jogYP = """
G91
G1 Y10 F1000
G90
""";

  final String jogYN = """
G91
G1 Y-10 F1000
G90
""";

  @override
  void initState() {

    super.initState();

    gcodeController = TextEditingController(
      text: widget.gcode,
    );
  }

  @override
  void dispose() {

    gcodeController.dispose();

    super.dispose();
  }


  // =========================
  // SEND SINGLE LINE
  // =========================
  Future<bool> sendLineAndWaitOk(
      String line
      ) async {

    try {

      final response = await http.post(

        Uri.parse(
            "http://$espIp/send"
        ),

        headers: {
          "Content-Type": "text/plain",
        },

        body: line,
      );

      String res =
      response.body.toLowerCase();

      print("TX : $line");
      print("RX : $res");

      if (

      response.statusCode == 200 &&

          (
              res.contains("ok") ||
                  res.contains("idle")
          )

      ) {

        return true;
      }

    } catch (e) {

      print(e);
    }

    return false;
  }


  // =========================
  // SEND ENTIRE GCODE
  // =========================
  Future<void> sendLineByLine() async {

    setState(() {

      isSending = true;
    });

    List<String> lines =

    gcodeController.text

        .split("\n")

        .map((e) => e.trim())

        .where((e) => e.isNotEmpty)

        .toList();

    for (String line in lines) {

      bool success =
      await sendLineAndWaitOk(line);

      if (!success) {

        _showMessage(
            "FAILED : $line"
        );

        setState(() {

          isSending = false;
        });

        return;
      }

      await Future.delayed(

        const Duration(
            milliseconds: 80
        ),
      );
    }

    _showMessage(
        "Finished Sending ✅"
    );

    setState(() {

      isSending = false;
    });
  }


  // =========================
  // SEND JOG
  // =========================
  Future<void> sendJog(
      String command
      ) async {

    List<String> lines =

    command

        .split("\n")

        .map((e) => e.trim())

        .where((e) => e.isNotEmpty)

        .toList();

    for (String line in lines) {

      bool ok =
      await sendLineAndWaitOk(line);

      if (!ok) {

        _showMessage(
            "Jog Failed"
        );

        return;
      }

      await Future.delayed(

        const Duration(
            milliseconds: 80
        ),
      );
    }

    _showMessage(
        "Jog Sent ✅"
    );
  }


  // =========================
  // MESSAGE
  // =========================
  void _showMessage(String msg) {

    ScaffoldMessenger.of(context)
        .showSnackBar(

      SnackBar(
        content: Text(msg),
      ),
    );
  }


  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: const Text(
            "Wireless CNC"
        ),
      ),

      body: Padding(

        padding:
        const EdgeInsets.all(12),

        child: Column(

          children: [

            // =====================
            // GCODE EDITOR
            // =====================
            Expanded(

              child: TextField(

                controller:
                gcodeController,

                maxLines: null,

                expands: true,

                style: const TextStyle(

                  fontFamily:
                  "monospace",

                  fontSize: 14,
                ),

                decoration:
                const InputDecoration(

                  border:
                  OutlineInputBorder(),

                  labelText:
                  "Edit G-code",

                  alignLabelWithHint:
                  true,
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // =====================
            // SEND BUTTON
            // =====================
            SizedBox(

              width: double.infinity,

              height: 50,

              child: ElevatedButton.icon(

                onPressed:

                isSending
                    ? null
                    : sendLineByLine,

                icon: const Icon(
                    Icons.send
                ),

                label: const Text(
                    "Send G-code"
                ),
              ),
            ),

            const SizedBox(
              height: 25,
            ),

            // =====================
            // JOG TITLE
            // =====================
            const Text(

              "Manual Jog Control",

              style: TextStyle(

                fontSize: 18,

                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            // =====================
            // JOG UI
            // =====================
            Column(

              children: [

                ElevatedButton(

                  onPressed:
                      () => sendJog(jogYP),

                  child:
                  const Text("+Y"),
                ),

                Row(

                  mainAxisAlignment:
                  MainAxisAlignment.center,

                  children: [

                    ElevatedButton(

                      onPressed:
                          () => sendJog(jogXN),

                      child:
                      const Text("-X"),
                    ),

                    const SizedBox(
                      width: 20,
                    ),

                    ElevatedButton(

                      onPressed:
                          () => sendJog(jogXP),

                      child:
                      const Text("+X"),
                    ),
                  ],
                ),

                ElevatedButton(

                  onPressed:
                      () => sendJog(jogYN),

                  child:
                  const Text("-Y"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}