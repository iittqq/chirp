import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/websocket_controller.dart';

class ScanScreen extends StatefulWidget {
  final WebSocketController wsController;

  const ScanScreen({super.key, required this.wsController});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

bool showLoading = false;
bool showPreparing = false;

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController hoursController = TextEditingController();
  final TextEditingController minutesController = TextEditingController();
  final TextEditingController secondsController = TextEditingController();

  Timer? _countdownTimer;
  int remainingSeconds = 0;

  final List<String> devices = [
    "testAndroid",
    "Bayou Bonfouca",
    "Lost Lake",
    "Mid Bretton",
    "Cole's Bayou",
    "Northwest Turtle Bayou",
  ];

  String? selectedDevice;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    nameController.dispose();
    hoursController.dispose();
    minutesController.dispose();
    secondsController.dispose();
    super.dispose();
  }

  void startScan() {
    if (selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a device first")),
      );
      return;
    }

    final name = nameController.text.trim();
    final hours = int.tryParse(hoursController.text) ?? 0;
    final minutes = int.tryParse(minutesController.text) ?? 0;
    final seconds = int.tryParse(secondsController.text) ?? 0;
    final totalSeconds = Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    ).inSeconds;

    if (totalSeconds <= 0) return;

    _countdownTimer?.cancel();

    setState(() {
      showPreparing = true;
      showLoading = false;
      remainingSeconds = 0;
    });

    widget.wsController.testScan(name, totalSeconds, selectedDevice!);

    const warmup = Duration(seconds: 5);
    Future.delayed(warmup, () {
      if (!mounted) return;
      setState(() {
        showPreparing = false;
        showLoading = true;
        remainingSeconds = totalSeconds;
      });

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (remainingSeconds <= 1) {
          timer.cancel();
          endScan();
        } else {
          setState(() => remainingSeconds--);
        }
      });
    });
  }

  void endScan() {
    _countdownTimer?.cancel();
    setState(() {
      showLoading = false;
      remainingSeconds = 0;
      nameController.clear();
      hoursController.clear();
      minutesController.clear();
      secondsController.clear();
    });
    widget.wsController.endScan();
  }

  String formatCountdown(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!showLoading && !showPreparing)
                const Text(
                  'Devices',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 15),
              if (!showLoading && !showPreparing)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: devices.map((device) {
                      final isSelected = selectedDevice == device;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: ChoiceChip(
                          label: Text(device),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                          selected: isSelected,
                          selectedColor: Colors.indigo,
                          onSelected: (_) {
                            setState(() {
                              selectedDevice = device;
                            });
                          },
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.indigo
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 20),

              if (!showLoading && !showPreparing)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: Text(
                        'Scan Name',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: 'Enter scan name',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'Duration',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Center(child: Text('Hours')),
                              const SizedBox(height: 4),
                              TextField(
                                controller: hoursController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: '0',
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            children: [
                              const Center(child: Text('Minutes')),
                              const SizedBox(height: 4),
                              TextField(
                                controller: minutesController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: '0',
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            children: [
                              const Center(child: Text('Seconds')),
                              const SizedBox(height: 4),
                              TextField(
                                controller: secondsController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: '0',
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

              if (!showLoading) const SizedBox(height: 24),

              if (showPreparing) ...[
                const SizedBox(height: 16),
                const Text(
                  'Getting scan ready...',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
              if (showPreparing) const SizedBox(height: 24),
              if (showLoading) ...[
                const SizedBox(height: 16),
                const Text(
                  'Scan status: Running scan...',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  formatCountdown(remainingSeconds),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.lightGreen,
                  ),
                ),
              ],

              ManageScanButtons(
                onPressedStart: startScan,
                onPressedFinish: endScan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManageScanButtons extends StatelessWidget {
  final VoidCallback onPressedStart;
  final VoidCallback onPressedFinish;

  const ManageScanButtons({
    super.key,
    required this.onPressedStart,
    required this.onPressedFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!showLoading && !showPreparing)
          ElevatedButton(
            onPressed: onPressedStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text('Start Scan'),
          ),
        const SizedBox(height: 24),
        if (showLoading || showPreparing)
          ElevatedButton(
            onPressed: onPressedFinish,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text('Finish Scan'),
          ),
      ],
    );
  }
}
