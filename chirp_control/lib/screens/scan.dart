import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/websocket_controller.dart';
import 'dart:io';
import 'package:xml/xml.dart';

class DeviceControlPage extends StatefulWidget {
  const DeviceControlPage({super.key});

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  late WebSocketService ws;
  String uiState = "";
  bool isConnected = false;
  bool automationRunning = false;

  @override
  void initState() {
    super.initState();
    ws = WebSocketService(deviceId: "controllerFlutter");
    ws.connect().then((_) {
      setState(() => isConnected = true);
    });

    ws.messages.listen((data) {
      print("Received: $data");

      if (data.containsKey("ui_state_zip_b64")) {
        setState(() => uiState = "");
        final xml = decodeZippedXml(data["ui_state_zip_b64"]);
        setState(() => uiState = xml);
        if (automationRunning) {
          analyzeUiXml(xml);
        }
      }
    });
  }

  String decodeZippedXml(String b64) {
    final compressedBytes = base64.decode(b64);
    final decompressed = GZipCodec().decode(compressedBytes);
    return utf8.decode(decompressed);
  }

  /// Analyze XML and direct the agent to click specific text
  void analyzeUiXml(String xml) {
    final doc = XmlDocument.parse(xml);
    final nodes = doc.findAllElements('node');

    bool updateFound = false;
    bool laterFound = false;
    bool connectFound = false;
    //bool boatFound = false;
    bool quickSettingsFound = false;
    bool pauseFound = false;
    bool resumeFound = false;

    for (final node in nodes) {
      final textAttr = node.getAttribute('text') ?? '';
      final resourceIdAttr = node.getAttribute('resource-id') ?? '';
      if (textAttr.contains('Update Available')) updateFound = true;
      if (textAttr.trim() == 'Later') laterFound = true;
      if (textAttr.trim() == 'Connect') connectFound = true;
      //if (textAttr.trim() == 'Boat') boatFound = true;
      if (textAttr.trim() == 'Pause') pauseFound = true;
      if (textAttr.trim() == 'Resume') resumeFound = true;
      if (resourceIdAttr.trim() == 'quickSettingsButton') {
        quickSettingsFound = true;
      }
    }

    if (updateFound && laterFound) {
      print('Detected Update dialog → clicking Later button');
      _clickByText('Later');
      return; // wait for next UI update
    }

    if (connectFound) {
      print('Clicking Connect button');
      _clickByText('Connect');
      return; // wait for next UI update
    }

    /*
    if (boatFound) {
      print('Clicking Boat button');
      _clickByText('Boat');
      print('Automation complete ✅');
      return;
    }
*/
    if (quickSettingsFound) {
      print('Clicking Quick Settings');
      _clickById('quickSettingsButton');
      return;
    }

    if (pauseFound) {
      print('Clicking Pause text container directly');
      _clickByTextDirect('Pause'); // new function
      return;
    }

    if (resumeFound) {
      print('Clicking Resume text container directly');
      _clickByTextDirect('Resume'); // new function
      return;
    }
  }

  void _clickById(String resourceId) {
    final cmd = {
      "action": "clickById",
      "resourceId": resourceId,
      "deviceId": "testAndroid",
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Sent clickById for '$resourceId'");
  }

  /// Sends a semantic clickText command
  void _clickByText(String label) {
    final cmd = {
      "action": "clickText",
      "text": label,
      "deviceId": "testAndroid",
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Sent clickText for '$label'");
  }

  void _clickByTextDirect(String label) {
    final cmd = {
      "action": "clickTextDirect",
      "text": label,
      "deviceId": "testAndroid",
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Sent clickTextDirect for '$label'");
  }

  /// Sends the command to launch the app, starting the sequence
  void startAutomation() {
    if (!isConnected) return;

    automationRunning = true;

    final launchCmd = {
      "action": "launch",
      "package":
          "eu.deeper.fishdeeper/eu.deeper.app.scan.live.MainScreenActivity",
      "deviceId": "testAndroid",
      "sender": "controllerFlutter",
    };

    ws.sendCommand(launchCmd);
    print("Sent launch command — automation started");
  }

  @override
  void dispose() {
    ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Deeper Auto Connector")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (isConnected)
              const Text("Connected ✅", style: TextStyle(color: Colors.green))
            else
              const Text("Connecting...", style: TextStyle(color: Colors.red)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: startAutomation,
              child: const Text("Start Automation"),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  uiState.isNotEmpty ? uiState : "No UI state yet",
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
