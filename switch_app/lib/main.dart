import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Switch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFE0E5EC),
      ),
      home: const SmartSwitchPage(),
    );
  }
}

class SmartSwitchPage extends StatefulWidget {
  const SmartSwitchPage({super.key});

  @override
  State<SmartSwitchPage> createState() => _SmartSwitchPageState();
}

class _SmartSwitchPageState extends State<SmartSwitchPage> {
  bool switchState = false;
  bool autoMode = false;
  bool pirActive = false;
  bool isConnected = false;
  String ipAddress = "192.168.4.1"; // Default ESP01 IP in AP mode
  Timer? statusTimer;

  @override
  void initState() {
    super.initState();
    fetchStatus();
    // Poll status every 3 seconds
    statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      fetchStatus();
    });
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchStatus() async {
    try {
      final response = await http
          .get(Uri.parse('http://$ipAddress/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          switchState = data['state'];
          autoMode = data['auto'];
          pirActive = data['pir'];
          isConnected = true;
        });
      } else {
        setState(() {
          isConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        isConnected = false;
      });
    }
  }

  Future<void> toggleSwitch() async {
    // Don't allow manual toggle in auto mode
    if (autoMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot toggle in automatic mode')),
      );
      return;
    }

    try {
      final response = await http
          .get(Uri.parse('http://$ipAddress/toggle'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 302) {
        fetchStatus();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to toggle switch')));
    }
  }

  Future<void> toggleMode(bool setAuto) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://$ipAddress/setmode?auto=${setAuto ? 'true' : 'false'}',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 302) {
        fetchStatus();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to change mode')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Switch Control'),
        backgroundColor: const Color(0xFFE0E5EC),
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _showSettingsDialog();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Connection status indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(
                  isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 18,
                    color: isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Mode selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NeomorphicButton(
                  onPressed: () => toggleMode(false),
                  width: 150,
                  child: Text(
                    'Manual Mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: !autoMode ? Colors.blue : Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                NeomorphicButton(
                  onPressed: () => toggleMode(true),
                  width: 150,
                  child: Text(
                    'Auto Mode (PIR)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: autoMode ? Colors.blue : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Status indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Switch state indicator
                Column(
                  children: [
                    Text(
                      'Switch',
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 70,
                      height: 30,
                      decoration: BoxDecoration(
                        color:
                            switchState
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade400,
                            offset: const Offset(2, 2),
                            blurRadius: 4,
                            spreadRadius: 0,
                          ),
                          const BoxShadow(
                            color: Colors.white,
                            offset: Offset(-2, -2),
                            blurRadius: 4,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          switchState ? 'ON' : 'OFF',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                switchState
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 30),

                // PIR sensor indicator (only show in auto mode)
                if (autoMode)
                  Column(
                    children: [
                      Text(
                        'Motion',
                        style: TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: 70,
                        height: 30,
                        decoration: BoxDecoration(
                          color:
                              pirActive
                                  ? Colors.amber.shade200
                                  : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade400,
                              offset: const Offset(2, 2),
                              blurRadius: 4,
                              spreadRadius: 0,
                            ),
                            const BoxShadow(
                              color: Colors.white,
                              offset: Offset(-2, -2),
                              blurRadius: 4,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            pirActive ? 'DETECTED' : 'NONE',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color:
                                  pirActive
                                      ? Colors.amber.shade800
                                      : Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 50),

            // Main switch button
            GestureDetector(
              onTap: autoMode ? null : toggleSwitch,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E5EC),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    // Outer shadow
                    BoxShadow(
                      color:
                          switchState
                              ? (autoMode
                                  ? Colors.amber.withOpacity(0.5)
                                  : Colors.blue.withOpacity(0.5))
                              : Colors.grey.shade400,
                      offset: const Offset(4, 4),
                      blurRadius: 15,
                      spreadRadius: 1,
                    ),
                    // Inner shadow (light)
                    const BoxShadow(
                      color: Colors.white,
                      offset: Offset(-4, -4),
                      blurRadius: 15,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E5EC),
                      borderRadius: BorderRadius.circular(80),
                      gradient:
                          switchState
                              ? (autoMode
                                  ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFFFD54F),
                                      Color(0xFFFFA000),
                                    ],
                                  )
                                  : const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF90CAF9),
                                      Color(0xFF42A5F5),
                                    ],
                                  ))
                              : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFE0E5EC), Color(0xFFD1D9E6)],
                              ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              switchState
                                  ? (autoMode
                                      ? Colors.amber.shade200
                                      : Colors.blue.shade200)
                                  : Colors.grey.shade400,
                          offset: const Offset(4, 4),
                          blurRadius: 8,
                          spreadRadius: -2,
                        ),
                        const BoxShadow(
                          color: Colors.white,
                          offset: Offset(-4, -4),
                          blurRadius: 8,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Icon(
                      autoMode ? Icons.sensors : Icons.power_settings_new,
                      size: 60,
                      color: switchState ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 50),

            // Control button (only active in manual mode)
            if (!autoMode)
              NeomorphicButton(
                onPressed: toggleSwitch,
                child: Text(
                  switchState ? 'Turn OFF' : 'Turn ON',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),

            // Status text for auto mode
            if (autoMode)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Automatic mode active\nMotion detection will control the switch',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    final ipController = TextEditingController(text: ipAddress);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFFE0E5EC),
            title: const Text('Connection Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ipController,
                  decoration: const InputDecoration(
                    labelText: 'ESP01 IP Address',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                const Text(
                  'Default credentials:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('SSID: SmartSwitch'),
                const Text('Password: switch1234'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              NeomorphicButton(
                onPressed: () {
                  setState(() {
                    ipAddress = ipController.text;
                  });
                  fetchStatus();
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }
}

class NeomorphicButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final double width;
  final double height;

  const NeomorphicButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.width = 200,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE0E5EC),
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFFD1D9E6),
              offset: Offset(4, 4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.white,
              offset: Offset(-4, -4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}
