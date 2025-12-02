import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/websocket_controller.dart';
import 'dart:io';
import 'package:xml/xml.dart';

enum Device { test, siteOne, siteTwo }

class DeviceControlPage extends StatefulWidget {
  const DeviceControlPage({super.key});

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  late WebSocketService ws;
  String deviceId = "controllerFlutter";
  String uiState = "";
  bool isConnected = false;
  bool automationRunning = false;
  bool initialConnectionComplete = false;

  Timer? _automationTimer;
  Duration _remainingDuration = Duration.zero;
  Duration _sessionDuration = Duration.zero;

  XmlElement? _openMenuNode;
  bool _isSynced = false;

  bool _readyToFinishScan = false;

  Device? selectedDevice;
  final TextEditingController _hoursController = TextEditingController(
    text: '0',
  );
  final TextEditingController _minutesController = TextEditingController(
    text: '0',
  );
  final TextEditingController _secondsController = TextEditingController(
    text: '0',
  );
  final TextEditingController _delayController = TextEditingController(
    text: '5',
  );

  final Map<Device, String> deviceIdMap = {
    Device.test: 'testAndroid',
    Device.siteOne: 'otherAndroid',
    Device.siteTwo: 'anotherAndroid',
  };

  @override
  void initState() {
    super.initState();

    ws = WebSocketService(deviceId: deviceId);
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

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _delayController.dispose();
    _automationTimer?.cancel();
    ws.disconnect();
    super.dispose();
  }

  String decodeZippedXml(String b64) {
    final compressedBytes = base64.decode(b64);
    final decompressed = GZipCodec().decode(compressedBytes);
    return utf8.decode(decompressed);
  }

  String getSelectedDeviceId() {
    return selectedDevice != null
        ? deviceIdMap[selectedDevice]!
        : 'testAndroid';
  }

  /*
  void _requestUiStateDump() {
    final cmd = {
      "action": "dumpUi",
      "deviceId": getSelectedDeviceId(),
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Requested UI state dump.");
  }
  */

  void _startTimer(int totalSeconds) {
    _sessionDuration = Duration(seconds: totalSeconds);
    _remainingDuration = _sessionDuration;

    _automationTimer?.cancel();

    _automationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingDuration.inSeconds <= 0) {
        timer.cancel();
        setState(() {
          _readyToFinishScan = true;
          print("Automation timer finished. Ready to open menu.");
          //_requestUiStateDump();

          ws.sendCommand({
            "action": "restart",
            "deviceId": getSelectedDeviceId(),
            "sender": deviceId,
          });
        });
      } else {
        setState(() {
          _remainingDuration = _remainingDuration - const Duration(seconds: 1);
        });
      }
    });
  }

  /// NEW: Find clickable parent/ancestor for a given node
  XmlElement? _findClickableAncestor(XmlElement node) {
    XmlElement? current = node;

    while (current != null) {
      final clickable = current.getAttribute('clickable');
      if (clickable == 'true') {
        return current;
      }
      // Move up to parent
      final parent = current.parent;
      if (parent is XmlElement) {
        current = parent;
      } else {
        break;
      }
    }
    return null;
  }

  /// NEW: Smart click that finds the element and its clickable parent
  void _clickElementSmart(
    XmlDocument doc, {
    String? text,
    String? contentDesc,
    String? resourceId,
  }) {
    final nodes = doc.findAllElements('node');

    for (final node in nodes) {
      bool matches = false;

      if (text != null && node.getAttribute('text') == text) {
        matches = true;
      } else if (contentDesc != null &&
          node.getAttribute('content-desc') == contentDesc) {
        matches = true;
      } else if (resourceId != null &&
          node.getAttribute('resource-id') == resourceId) {
        matches = true;
      }

      if (matches) {
        // Check if this node itself is clickable
        if (node.getAttribute('clickable') == 'true') {
          _clickByXmlNode(node);
          return;
        }

        // Find clickable ancestor
        final clickableParent = _findClickableAncestor(node);
        if (clickableParent != null) {
          print("Found clickable parent for target element");
          _clickByXmlNode(clickableParent);
          return;
        }

        // Fallback: click the node itself even if not marked clickable
        print("No clickable parent found, clicking target node directly");
        _clickByXmlNode(node);
        return;
      }
    }

    print("Element not found: text=$text, desc=$contentDesc, id=$resourceId");
  }

  bool _hasFabImageDescendant(XmlElement xmlNode, String contentDescription) {
    // Check the children and all descendants recursively
    for (final child in xmlNode.children.whereType<XmlElement>()) {
      String contentDescAttr = child.getAttribute('content-desc') ?? '';
      String contentDesc = contentDescAttr.trim();

      if (contentDesc == contentDescription) {
        return true;
      }

      if (_hasFabImageDescendant(child, contentDescription)) {
        return true;
      }
    }
    return false;
  }

  void analyzeUiXml(String xml) {
    final doc = XmlDocument.parse(xml);
    final nodes = doc.findAllElements('node');

    bool updateFound = false;
    bool laterFound = false;
    bool connectFound = false;
    bool scanOptionsFound = false;
    bool pauseFound = false;
    bool resumeFound = false;
    bool cancelFound = false;
    bool boatScanIconFound = false;
    bool openMenuFound = false;
    bool navigateWithoutMapFound = false;
    bool paused = false;
    bool historyFound = false;
    bool syncScansFound = false;
    bool notConnectedFound = false;
    String scanOptionsIndex = '';
    String openMenuIndex = '';

    _openMenuNode = null;

    for (final node in nodes) {
      final textAttr = node.getAttribute('text') ?? '';
      final resourceIdAttr = node.getAttribute('resource-id') ?? '';
      final contentDescAttr = node.getAttribute('content-desc') ?? '';
      final indexAttr = node.getAttribute('index') ?? '';
      final clickableAttr = node.getAttribute('clickable') ?? '';

      if (textAttr.contains('Update Available')) updateFound = true;
      if (textAttr.trim() == 'Later') laterFound = true;
      if (textAttr.trim() == 'Connect') connectFound = true;
      if (textAttr.trim() == 'Pause') pauseFound = true;
      if (textAttr.trim() == 'Resume') resumeFound = true;
      if (textAttr.trim() == 'Cancel') cancelFound = true;
      if (textAttr.trim() == 'Navigate Without Map') {
        navigateWithoutMapFound = true;
      }
      if (textAttr.trim() == 'Power save') paused = true;

      if (textAttr.trim() == 'Not Connected') notConnectedFound = true;

      if (contentDescAttr.trim() == 'Boat scan icon') boatScanIconFound = true;

      scanOptionsIndex = paused == true ? '2' : '1';
      if (indexAttr.trim() == scanOptionsIndex &&
          clickableAttr.trim() == 'true') {
        scanOptionsFound = true;
      }

      openMenuIndex = notConnectedFound == true ? '3' : '3';
      if (indexAttr.trim() == openMenuIndex && clickableAttr.trim() == 'true') {
        bool hasFabImageChild = _hasFabImageDescendant(node, 'Fab Image');

        if (hasFabImageChild) {
          openMenuFound = true;
          _openMenuNode = node;
        }
      }
      if (textAttr.trim() == 'History') historyFound = true;
      if (resourceIdAttr.trim() == 'syncScansButton') syncScansFound = true;
    }

    if (updateFound && laterFound) {
      print('Detected Update dialog → clicking Later button');
      _clickElementSmart(doc, text: 'Later');
      return;
    }

    if (navigateWithoutMapFound) {
      print('Clicking navigate without map');
      _clickElementSmart(doc, text: 'Navigate Without Map');
      return;
    }

    if (!initialConnectionComplete) {
      if (boatScanIconFound) {
        print('Initial setup found Boat Scan Icon → clicking it');
        _clickElementSmart(doc, contentDesc: 'Boat scan icon');

        final hours = int.tryParse(_hoursController.text) ?? 0;
        final minutes = int.tryParse(_minutesController.text) ?? 0;
        final seconds = int.tryParse(_secondsController.text) ?? 0;
        final totalSeconds = hours * 3600 + minutes * 60 + seconds;
        _startTimer(totalSeconds);

        setState(() => initialConnectionComplete = true);
        print(
          'Initial connection complete. Starting timer and Pause/Resume cycle.',
        );
        return;
      }

      if (connectFound) {
        print('Initial setup clicking Connect button');
        _clickElementSmart(doc, text: 'Connect');
        return;
      }

      if (cancelFound) {
        print('Detected Cancel dialog → clicking Cancel');
        _clickElementSmart(doc, text: 'Cancel');
        return;
      }
    }

    if (_readyToFinishScan) {
      if (_isSynced) {
        print('Finished, closing app');
        setState(() {
          automationRunning = false;
          _isSynced = false;
        });
        ws.sendCommand({
          "action": "close",
          "deviceId": getSelectedDeviceId(),
          "sender": deviceId,
        });
        return;
      }

      if (historyFound) {
        print('Opening History');
        _clickElementSmart(doc, text: 'History');
        return;
      }

      if (syncScansFound) {
        print('Syncing Scans');
        _clickElementSmart(doc, resourceId: 'syncScansButton');
        setState(() {
          _isSynced = true;
        });

        return;
      }

      if (openMenuFound) {
        print('Timer over, Pause/Resume cleared. Clicking Menu (Fab Image).');
        if (_openMenuNode != null) {
          _clickByXmlNode(_openMenuNode!);
          return;
        }
      }
    }

    // 4. Automation Cycle: Pause/Resume
    /*
    if (initialConnectionComplete && !_readyToFinishScan) {
      if (pauseFound) {
        print('Automation cycle: Clicking Pause');
        _clickElementSmart(doc, text: 'Pause');
        return;
      }

      if (resumeFound) {
        print('Automation cycle: Clicking Resume');
        _clickElementSmart(doc, text: 'Resume');
        return;
      }
    }

    // 5. Fallback: Scan Options button
    if (scanOptionsFound && !_readyToFinishScan) {
      print('Clicking Scan Options Button index: ' + scanOptionsIndex);
      _clickByIndex(scanOptionsIndex);
      return;
    }

    */

    print('No actionable elements found in the current UI state');
  }

  /// Send clickByXml command with the full XML node
  void _clickByXmlNode(XmlElement node) {
    final xmlString = node.toXmlString();
    final cmd = {
      "action": "clickByXml",
      "xmlNode": xmlString,
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    };
    ws.sendCommand(cmd);
    print(
      "Sent clickByXml for node: ${node.getAttribute('text') ?? node.getAttribute('content-desc') ?? 'unknown'}",
    );
  }

  void _clickByIndex(String index) {
    final cmd = {
      "action": "clickByIndex",
      "index": index,
      "deviceId": getSelectedDeviceId(),
      "sender": deviceId,
    };
    ws.sendCommand(cmd);
    print("Sent clickByIndex for index='$index' to ${getSelectedDeviceId()}");
  }

  void startAutomation() {
    if (!isConnected) {
      print("Not connected to WebSocket.");
      return;
    }

    if (selectedDevice == null) {
      print("Please select a device before starting automation.");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a device.')));
      return;
    }

    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final seconds = int.tryParse(_secondsController.text) ?? 0;
    final totalSeconds = hours * 3600 + minutes * 60 + seconds;

    if (totalSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a duration greater than 0.')),
      );
      return;
    }

    setState(() {
      initialConnectionComplete = false;
      automationRunning = true;
      _readyToFinishScan = false;
    });

    final scanDeviceId = getSelectedDeviceId();

    print("Automation for device '$scanDeviceId' started");

    final launchCmd = {
      "action": "launch",
      "package":
          "eu.deeper.fishdeeper/eu.deeper.app.scan.live.MainScreenActivity",
      "deviceId": scanDeviceId,
      "sender": deviceId,
    };

    ws.sendCommand(launchCmd);
    print("Sent launch command — automation started");
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  Widget _buildTimerDisplay() {
    if (!automationRunning && _sessionDuration.inSeconds > 0) {
      return Column(
        children: [
          const Divider(),
          Text(
            "Finished, find scans on Fish Deeper website",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 10),
        ],
      );
    } else if (_readyToFinishScan) {
      return Column(
        children: [
          const Divider(),
          Text(
            "Scanning Finished, Uploading to Fish Deeper website",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    if (!automationRunning || !initialConnectionComplete) {
      return const SizedBox.shrink();
    }

    Color timerColor = Colors.blue.shade700;
    if (_remainingDuration.inSeconds <= 10 &&
        _remainingDuration.inSeconds > 0) {
      timerColor = Colors.orange;
    } else if (_remainingDuration.inSeconds <= 0) {
      timerColor = Colors.red;
    }

    return Column(
      children: [
        const Divider(),
        Text(
          "Scan Time Remaining:",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: timerColor,
          ),
        ),
        Text(
          _formatDuration(_remainingDuration),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: timerColor,
          ),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildDeviceSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Device:",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: Device.values.map((device) {
            return ElevatedButton(
              onPressed: () {
                setState(() {
                  selectedDevice = device;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedDevice == device
                    ? Colors.blue
                    : Colors.grey[300],
                foregroundColor: selectedDevice == device
                    ? Colors.white
                    : Colors.black,
              ),
              child: Text(device.toString().split('.').last),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTimeInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Scan Session Length:",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTextField(_hoursController, "Hours"),
            _buildTextField(_minutesController, "Minutes"),
            _buildTextField(_secondsController, "Seconds"),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return SizedBox(
      width: 80,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Initiate Scan")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                isConnected
                    ? "Connected to WebSocket as "
                    : "Connecting to WebSocket...",
                style: TextStyle(
                  color: isConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildDeviceSelection(),
            const SizedBox(height: 20),
            _buildTimeInput(),
            const SizedBox(height: 20),
            const SizedBox(height: 30),
            _buildTimerDisplay(),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: automationRunning ? null : startAutomation,
              icon: Icon(
                automationRunning ? Icons.hourglass_full : Icons.play_arrow,
              ),
              label: Text(
                automationRunning ? "Automation Running" : "Initiate Scan",
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: automationRunning
                    ? Colors.orange.shade700
                    : selectedDevice != null
                    ? Colors.blue.shade700
                    : Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const Text(
              "Received UI State XML:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  uiState.isNotEmpty ? uiState : "No UI state yet",
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
