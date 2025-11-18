import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/websocket_controller.dart';
import 'dart:io';
import 'package:xml/xml.dart';

// Assuming these are the device IDs for selection
enum Device { test, siteOne, siteTwo }

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
  // Flag to track if the initial 'Boat Scan Icon' selection has been made
  bool initialConnectionComplete = false;

  // New Timer/Duration State
  Timer? _automationTimer;
  Duration _remainingDuration = Duration.zero;
  Duration _sessionDuration = Duration.zero; // Stores the total duration

  // Flag to manage the transition to the final menu click
  bool _readyToOpenMenu = false;

  // New state variables for UI
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
  ); // Default 5 seconds

  // Define device IDs
  final Map<Device, String> deviceIdMap = {
    Device.test: 'testAndroid', // Example device A ID
    Device.siteOne: 'otherAndroid', // Example device B ID
    Device.siteTwo: 'anotherAndroid', // Example device C ID
  };

  @override
  void initState() {
    super.initState();
    // Initialize with a default device ID if needed, or keep it as 'controllerFlutter'
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

  // Dispose controllers and timer
  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _delayController.dispose();
    _automationTimer?.cancel(); // Cancel timer on dispose
    ws.disconnect();
    super.dispose();
  }

  // --- Utility and Automation Logic (Retained/Modified) ---

  String decodeZippedXml(String b64) {
    final compressedBytes = base64.decode(b64);
    // Assuming GZipCodec is available (check your imports if this fails)
    final decompressed = GZipCodec().decode(compressedBytes);
    return utf8.decode(decompressed);
  }

  String getSelectedDeviceId() {
    return selectedDevice != null
        ? deviceIdMap[selectedDevice]!
        : 'testAndroid'; // Default device ID
  }

  void _requestUiStateDump() {
    final cmd = {
      "action": "dumpUi",
      "deviceId": getSelectedDeviceId(),
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Requested UI state dump.");
  }

  void _startTimer(int totalSeconds) {
    _sessionDuration = Duration(seconds: totalSeconds);
    _remainingDuration = _sessionDuration;

    _automationTimer?.cancel(); // Cancel any existing timer

    _automationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingDuration.inSeconds <= 0) {
        timer.cancel();
        setState(() {
          _readyToOpenMenu = true; // Timer is over, allow menu click
          // Note: automationRunning remains true until the menu is clicked
          print("Automation timer finished. Ready to open menu.");
        });
        // Request a new dump to immediately check the UI state and click the menu
        _requestUiStateDump();
      } else {
        setState(() {
          _remainingDuration = _remainingDuration - const Duration(seconds: 1);
        });
      }
    });
  }

  /// Analyze XML and direct the agent to click specific text
  void analyzeUiXml(String xml) {
    final doc = XmlDocument.parse(xml);
    final nodes = doc.findAllElements('node');

    bool updateFound = false;
    bool laterFound = false;
    bool connectFound = false;
    bool quickSettingsFound = false;
    bool pauseFound = false;
    bool resumeFound = false;
    bool cancelFound = false;
    bool boatScanIconFound = false;
    bool openMenuFound = false; // Check for menu button
    bool navigateWithoutMapFound = false;

    for (final node in nodes) {
      final textAttr = node.getAttribute('text') ?? '';
      final resourceIdAttr = node.getAttribute('resource-id') ?? '';
      final contentDescAttr = node.getAttribute('content-desc') ?? '';

      // Look for all potential buttons
      if (textAttr.contains('Update Available')) updateFound = true;
      if (textAttr.trim() == 'Later') laterFound = true;
      if (textAttr.trim() == 'Connect') connectFound = true;
      if (textAttr.trim() == 'Pause') pauseFound = true;
      if (textAttr.trim() == 'Resume') resumeFound = true;
      if (textAttr.trim() == 'Cancel') cancelFound = true;
      if (textAttr.trim() == 'Navigate Without Map')
        navigateWithoutMapFound = true;

      if (contentDescAttr.trim() == 'Boat scan icon') {
        boatScanIconFound = true;
      }
      if (resourceIdAttr.trim() == 'quickSettingsButton') {
        quickSettingsFound = true;
      }
      if (contentDescAttr.trim() == 'Open navigation drawer') {
        openMenuFound = true;
      }
    }

    // --- Sequence Logic ---

    // 1. Dismiss Update dialog (highest priority)
    if (updateFound && laterFound) {
      print('Detected Update dialog → clicking Later button');
      _clickByText('Later');
      return;
    }

    if (navigateWithoutMapFound) {
      print('Clicking navigate without map');
      _clickByTextDirect('Navigate Without Map');
      return;
    }

    // 2. Initial Setup: Connect → Boat Scan Icon (remains the same)
    if (!initialConnectionComplete) {
      // Check for Boat Scan Icon first
      if (boatScanIconFound) {
        print(
          'Initial setup found Boat Scan Icon → clicking element by content-desc',
        );
        _clickByDescription('Boat scan icon');

        // START TIMER HERE AFTER BOAT ICON CLICK
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

      // Keep clicking Connect until Boat Scan Icon is found
      if (connectFound) {
        print('Initial setup clicking Connect button');
        _clickByText('Connect');
        return;
      }

      // Handle Cancel dialog (often appears near Connect/Boat flow)
      if (cancelFound) {
        print('Detected Cancel dialog → clicking Cancel');
        _clickByText('Cancel');
        return;
      }
    }

    // 3. POST-TIMER PRIORITY ACTION: Clear Pause/Resume screen first
    if (_readyToOpenMenu) {
      // If EITHER Pause or Resume is present, click it to clear the scan screen
      if (pauseFound) {
        print('Timer over but menu not open. Opening menu.');
        _clickByTextDirect('Resume');
      }
      if (pauseFound) {
        _clickByTextDirect('Pause');
        return;
      }

      // 3b. Open Navigation Drawer (Only runs if Pause/Resume were not found above)
      if (openMenuFound) {
        print(
          'Timer over, Pause/Resume cleared. Clicking Open navigation drawer.',
        );
        _clickByDescription('Open navigation drawer');
        // Final action done, stop automation and reset flag
        setState(() => automationRunning = false);
        _readyToOpenMenu = false;
        return;
      }
    }

    // 4. Automation Cycle: Pause/Resume (only after initial connection AND while timer is running)
    // This section is skipped if _readyToOpenMenu is true.
    if (initialConnectionComplete && !_readyToOpenMenu) {
      // If Pause is found, click it to resume the cycle
      if (pauseFound) {
        print('Automation cycle: Clicking Pause text container directly');
        _clickByTextDirect('Pause');
        return;
      }

      // If Resume is found, click it to continue the cycle
      if (resumeFound) {
        print('Automation cycle: Clicking Resume text container directly');
        _clickByTextDirect('Resume');
        return;
      }
    }

    // 5. Fallback actions (e.g., Quick Settings)
    if (quickSettingsFound && !_readyToOpenMenu) {
      print('Clicking Quick Settings');
      _clickById('quickSettingsButton');
      return;
    }

    print('No actionable elements found in the current UI state.');
  }

  void _clickById(String resourceId) {
    final cmd = {
      "action": "clickById",
      "resourceId": resourceId,
      "deviceId": getSelectedDeviceId(),
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Sent clickById for '$resourceId' to ${getSelectedDeviceId()}");
  }

  /// Sends a semantic clickText command
  void _clickByText(String label) {
    final cmd = {
      "action": "clickText",
      "text": label,
      "deviceId": getSelectedDeviceId(),
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Sent clickText for '$label' to ${getSelectedDeviceId()}");
  }

  void _clickByTextDirect(String label) {
    final cmd = {
      "action": "clickTextDirect",
      "text": label,
      "deviceId": getSelectedDeviceId(),
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print("Sent clickTextDirect for '$label' to ${getSelectedDeviceId()}");
  }

  void _clickByDescription(String description) {
    final cmd = {
      "action": "clickByDescription", // NEW ACTION TYPE
      "description": description,
      "deviceId": getSelectedDeviceId(),
      "sender": "controllerFlutter",
    };
    ws.sendCommand(cmd);
    print(
      "Sent clickByDescription for '$description' to ${getSelectedDeviceId()}",
    );
  }

  /// Sends the command to launch the app, starting the sequence
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

    // Calculate total seconds to check for valid duration
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

    // Reset flags and state for new run
    setState(() {
      initialConnectionComplete = false;
      automationRunning = true; // Automation starts immediately
      _readyToOpenMenu = false;
    });

    final deviceId = getSelectedDeviceId();
    final delay = int.tryParse(_delayController.text) ?? 5; // Default 5 seconds

    print(
      "Automation for device '$deviceId' started with delay: $delay s, duration: $totalSeconds s",
    );

    final launchCmd = {
      "action": "launch",
      "package":
          "eu.deeper.fishdeeper/eu.deeper.app.scan.live.MainScreenActivity",
      "deviceId": deviceId,
      "sender": "controllerFlutter",
      "delay": delay, // Send delay with command
    };

    ws.sendCommand(launchCmd);
    print("Sent launch command — automation started");

    // The timer will now be started by analyzeUiXml when the 'Boat scan icon' is clicked.
  }

  // Helper to format duration for display
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  Widget _buildTimerDisplay() {
    // Show "Automation Finished" if the timer is over and it was a valid session
    if (!automationRunning && _sessionDuration.inSeconds > 0) {
      return Column(
        children: [
          const Divider(),
          Text(
            "Automation Finished",
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

    // Only display the countdown if it's running AND the initial connection is complete (i.e., the timer has started)
    if (!automationRunning || !initialConnectionComplete) {
      return const SizedBox.shrink();
    }

    // Determine color based on remaining time
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

  // --- UI Building Methods (Retained) ---

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

  Widget _buildDelayInput() {
    return Row(
      children: [
        const Text(
          "Delay between scans (s):",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: TextField(
            controller: _delayController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
            ),
          ),
        ),
      ],
    );
  }

  // --- Main Widget Build (Modified) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Deeper Auto Connector")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Status
            Center(
              child: Text(
                isConnected
                    ? "Connected to WebSocket"
                    : "Connecting to WebSocket...",
                style: TextStyle(
                  color: isConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 1. Device Selection Buttons
            _buildDeviceSelection(),
            const SizedBox(height: 20),

            // 2. Hours, Minutes, Seconds Inputs
            _buildTimeInput(),
            const SizedBox(height: 20),

            // 3. Delay Input
            _buildDelayInput(),
            const SizedBox(height: 30),

            // NEW: Timer Display
            _buildTimerDisplay(),
            const SizedBox(height: 10),

            // 4. Initiate Scan Automation Button
            ElevatedButton.icon(
              onPressed: automationRunning
                  ? null
                  : startAutomation, // Disable button if running
              icon: Icon(
                automationRunning ? Icons.hourglass_full : Icons.play_arrow,
              ),
              label: Text(
                automationRunning
                    ? "Automation Running"
                    : "Initiate Scan Automation",
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: automationRunning
                    ? Colors
                          .orange
                          .shade700 // Change color when running
                    : selectedDevice != null
                    ? Colors.blue.shade700
                    : Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // UI State Viewer (Optional - kept for debug/context)
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
