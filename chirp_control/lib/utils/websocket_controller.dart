import 'dart:async'; // Added import for Future.delayed
import 'dart:convert';
import 'package:http/http.dart' as http;

class WebSocketController {
  final String _lambdaUrl =
      "https://12bhis2tui.execute-api.us-east-2.amazonaws.com/test/send-command";

  // --- ELEMENT IDENTIFIERS (IDs or Text) ---
  // 1. Initial Launch Wait: Resource ID for the "Later" button on the update prompt.
  static const String _launchWaitId = "android:id/button2";

  // 2. Wait for Connect: Text for the "Connect" button on the main screen (No resource-id found).
  static const String _connectButtonText = "Connect";

  // 3. Scan Running Wait: Text for the button that appears when scanning.
  //    *** CRITICAL: YOU MUST CONFIRM THIS TEXT (e.g., "Stop", "Scanning...") ***
  static const String _scanRunningWaitText = "Stop";

  // --- COORDINATES (Based on your system's resolution/DPI and XML analysis) ---
  // The center coordinates for each interactive element.
  // 1. Coordinates to tap the "Later" button.
  static const int _laterButtonX = 331;
  static const int _laterButtonY = 893;

  // 2. Coordinates to tap the "Connect" button.
  static const int _connectButtonX = 361;
  static const int _connectButtonY = 1195;

  final List<Map<String, dynamic>> _renameCommands = [
    // ... (unchanged rename logic)
    {
      "type": "launch",
      "package": "eu.deeper.fishdeeper/eu.deeper.app.splash.SplashActivity",
      "delay": 13,
    },
    {"type": "tap", "x": 70, "y": 140, "delay": 1},
    {"type": "tap", "x": 300, "y": 250, "delay": 2},
    {"type": "tap", "x": 670, "y": 250, "delay": 2},
  ];

  final List<Map<String, dynamic>> _test = [
    {"type": "tap", "x": 650, "y": 148, "delay": 3},
  ];

  // --- UPDATED SCAN COMMANDS WITH EXPLICIT WAIT STEPS ---
  final List<Map<String, dynamic>> _scanCommands = [
    // Launch the app
    {
      "type": "launch",
      "package": "eu.deeper.fishdeeper/eu.deeper.app.splash.SplashActivity",
      "delay": 5,
    },

    // 1. WAIT FOR UPDATE DIALOG ("Later" button)
    {
      "type": "wait_id",
      "value": _launchWaitId, // "android:id/button2"
      "timeout": 60, // Wait up to 60 seconds
    },
    // Tap the "Later" button
    {"type": "tap", "x": _laterButtonX, "y": _laterButtonY, "delay": 3},

    {"type": "tap", "x": 650, "y": 148, "delay": 3},

    // 2. WAIT FOR MAIN SCREEN ("Connect" text)
    {
      "type": "wait_text",
      "value": _connectButtonText, // "Connect"
      "timeout": 30, // Wait up to 30 seconds
    },
    // Tap the "Connect" button
    {"type": "tap", "x": _connectButtonX, "y": _connectButtonY, "delay": 3},

    // 3. WAIT FOR SCANNER INITIALIZATION ("Stop" text)
    {
      "type": "wait_text",
      "value": _scanRunningWaitText, // "Stop"
      "timeout": 30, // Wait up to 30 seconds
    },

    // 4. Tap the scan toggle button (your original x:212, y:550)
    {"type": "tap", "x": 212, "y": 550, "delay": 20},

    // --- Restart App ---
    {
      "type": "restart",
      "package": "eu.deeper.fishdeeper",
      "activity": "eu.deeper.app.splash.SplashActivity",
      "delay":
          13, // This delay is the time after restart before the next command
    },

    // The new logic (repeat steps 1-3 after restart):
    // 1. WAIT FOR UPDATE DIALOG ("Later" button)
    {"type": "wait_id", "value": _launchWaitId, "timeout": 60},
    // Tap the "Later" button
    {"type": "tap", "x": _laterButtonX, "y": _laterButtonY, "delay": 3},

    // 2. WAIT FOR MAIN SCREEN ("Connect" text)
    {"type": "wait_text", "value": _connectButtonText, "timeout": 30},
    // Tap the "Connect" button
    {"type": "tap", "x": _connectButtonX, "y": _connectButtonY, "delay": 3},

    // 3. WAIT FOR SCANNER INITIALIZATION ("Stop" text)
    {"type": "wait_text", "value": _scanRunningWaitText, "timeout": 30},
  ];

  int _resolveDelaySeconds(Map<String, dynamic> cmd, int scanDurationSec) {
    // ... (unchanged logic)
    final d = cmd['delay'];
    if (d == null) return 0;
    if (d is int && d == -1) return scanDurationSec; // use the passed duration
    if (d is int) return d;
    return int.tryParse(d.toString()) ?? 0;
  }

  Future<bool> _sendCommand(
    Map<String, dynamic> command,
    String deviceId,
  ) async {
    // ... (unchanged logic)
    final payload = {"deviceId": deviceId, "command": command};

    try {
      print(Uri.parse(_lambdaUrl));
      final response = await http.post(
        Uri.parse(_lambdaUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        print("❌ Failed to send: ${command['type']}");
        print("⛔ Status: ${response.statusCode}");
        print("📦 Response body: ${response.body}");
        return false; // Failure
      } else {
        print("✅ Sent: ${command['type']}");
        return true; // Success
      }
    } catch (e) {
      print("🔥 Exception sending ${command['type']}: $e");
      return false; // Failure
    }
  }

  Future<void> testScan(
    String name,
    int durationSeconds,
    String deviceId,
  ) async {
    print("Sending scan commands with explicit waits...");
    for (final command in _test) {
      final ok = await _sendCommand(command, deviceId);
      if (!ok) {
        print("🚫 Stopping scan because a command failed.");
        break;
      }

      final wait = _resolveDelaySeconds(command, durationSeconds);
      if (wait > 0) {
        await Future.delayed(Duration(seconds: wait));
      }
    }
  }

  // --- Other functions (unchanged) ---
  Future<void> renameScan() async {
    for (var command in _renameCommands) {
      await Future.delayed(Duration(seconds: command['delay']));
    }
  }

  Future<void> pauseScan() async {}

  Future<void> endScan() async {}
}
