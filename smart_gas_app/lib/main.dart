import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => MonitoringSystem(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return NeumorphicApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Gas Monitor',
      themeMode: ThemeMode.light,
      theme: NeumorphicThemeData(
        baseColor: Color(0xFFE0E5EC),
        lightSource: LightSource.topLeft,
        depth: 10,
        intensity: 0.5,
      ),
      darkTheme: NeumorphicThemeData(
        baseColor: Color(0xFF3E3E3E),
        lightSource: LightSource.topLeft,
        depth: 6,
        intensity: 0.3,
      ),
      home: DeviceConnectionScreen(),
    );
  }
}

class MonitoringSystem extends ChangeNotifier {
  bool _connected = false;
  IOWebSocketChannel? _channel;
  String _deviceIP = '';
  String _deviceID = '';
  
  // Sensor data
  double _temperature = 0.0;
  double _humidity = 0.0;
  double _gasLevel = 0.0;
  bool _alarmActive = false;
  bool _relayState = false;
  bool _autoMode = true;
  double _gasThreshold = 500.0;
  double _tempThreshold = 35.0;
  
  // Historical data for charts
  List<SensorReading> _temperatureHistory = [];
  List<SensorReading> _gasHistory = [];
  
  // Getters
  bool get connected => _connected;
  String get deviceIP => _deviceIP;
  String get deviceID => _deviceID;
  double get temperature => _temperature;
  double get humidity => _humidity;
  double get gasLevel => _gasLevel;
  bool get alarmActive => _alarmActive;
  bool get relayState => _relayState;
  bool get autoMode => _autoMode;
  double get gasThreshold => _gasThreshold;
  double get tempThreshold => _tempThreshold;
  List<SensorReading> get temperatureHistory => _temperatureHistory;
  List<SensorReading> get gasHistory => _gasHistory;
  
  // Connect to device
  Future<bool> connectToDevice(String ip) async {
    _deviceIP = ip;
    
    // First try HTTP connection to verify device is reachable
    try {
      final response = await http.get(
        Uri.parse('http://$_deviceIP/api/status'),
      ).timeout(Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _updateFromJson(data);
        
        // If HTTP connection successful, establish WebSocket
        _connected = true;
        _setupWebSocket();
        notifyListeners();
        
        // Save last connected device
        _saveLastConnectedDevice();
        
        return true;
      }
    } catch (e) {
      print('HTTP connection error: $e');
    }
    
    return false;
  }
  
  void _setupWebSocket() {
    try {
      _channel = IOWebSocketChannel.connect('ws://$_deviceIP:81');
      
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          _updateFromJson(data);
          notifyListeners();
        },
        onDone: () {
          _connected = false;
          notifyListeners();
        },
        onError: (error) {
          print('WebSocket error: $error');
          _connected = false;
          notifyListeners();
        },
      );
      
      // Request initial status
      _channel!.sink.add(jsonEncode({'command': 'getStatus'}));
    } catch (e) {
      print('WebSocket connection error: $e');
      _connected = false;
      notifyListeners();
    }
  }
  
  void _updateFromJson(dynamic data) {
    if (data.containsKey('temperature')) _temperature = data['temperature'].toDouble();
    if (data.containsKey('humidity')) _humidity = data['humidity'].toDouble();
    if (data.containsKey('gasLevel')) _gasLevel = data['gasLevel'].toDouble();
    if (data.containsKey('alarmActive')) _alarmActive = data['alarmActive'];
    if (data.containsKey('relayState')) _relayState = data['relayState'];
    if (data.containsKey('autoMode')) _autoMode = data['autoMode'];
    if (data.containsKey('gasThreshold')) _gasThreshold = data['gasThreshold'].toDouble();
    if (data.containsKey('tempThreshold')) _tempThreshold = data['tempThreshold'].toDouble();
    if (data.containsKey('deviceID')) _deviceID = data['deviceID'];
    
    // Add historical data points (limit to 20 points)
    final now = DateTime.now();
    _temperatureHistory.add(SensorReading(time: now, value: _temperature));
    _gasHistory.add(SensorReading(time: now, value: _gasLevel));
    
    if (_temperatureHistory.length > 20) {
      _temperatureHistory.removeAt(0);
    }
    
    if (_gasHistory.length > 20) {
      _gasHistory.removeAt(0);
    }
  }
  
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    _connected = false;
    notifyListeners();
  }
  
  // Control functions
  void toggleRelay() {
    if (_connected && _channel != null) {
      final newState = !_relayState;
      _channel!.sink.add(jsonEncode({
        'command': 'setRelay',
        'state': newState
      }));
    }
  }
  
  void toggleAutoMode() {
    if (_connected && _channel != null) {
      final newState = !_autoMode;
      _channel!.sink.add(jsonEncode({
        'command': 'setAutoMode',
        'state': newState
      }));
    }
  }
  
  void updateThresholds(double gas, double temp) {
    if (_connected && _channel != null) {
      _channel!.sink.add(jsonEncode({
        'command': 'setThresholds',
        'gas': gas,
        'temp': temp
      }));
    }
  }
  
  void resetAlarm() {
    if (_connected && _channel != null) {
      _channel!.sink.add(jsonEncode({
        'command': 'reset',
        'alarm': true
      }));
    }
  }
  
  Future<void> _saveLastConnectedDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastDeviceIP', _deviceIP);
      await prefs.setString('lastDeviceID', _deviceID);
    } catch (e) {
      print('Error saving device info: $e');
    }
  }
  
  Future<Map<String, String>> getLastConnectedDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString('lastDeviceIP') ?? '';
      final id = prefs.getString('lastDeviceID') ?? '';
      return {'ip': ip, 'id': id};
    } catch (e) {
      print('Error loading device info: $e');
      return {'ip': '', 'id': ''};
    }
  }
}

class SensorReading {
  final DateTime time;
  final double value;
  
  SensorReading({required this.time, required this.value});
}

class DeviceConnectionScreen extends StatefulWidget {
  @override
  _DeviceConnectionScreenState createState() => _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState extends State<DeviceConnectionScreen> {
  final _ipController = TextEditingController();
  bool _isConnecting = false;
  String _lastDeviceID = '';
  String _lastDeviceIP = '';
  bool _showLastDevice = false;
  
  @override
  void initState() {
    super.initState();
    _loadLastDevice();
  }
  
  Future<void> _loadLastDevice() async {
    final system = Provider.of<MonitoringSystem>(context, listen: false);
    final lastDevice = await system.getLastConnectedDevice();
    
    if (lastDevice['ip']!.isNotEmpty) {
      setState(() {
        _lastDeviceIP = lastDevice['ip']!;
        _lastDeviceID = lastDevice['id']!;
        _showLastDevice = true;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final system = Provider.of<MonitoringSystem>(context);
    
    if (system.connected) {
      return DashboardScreen();
    }
    
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Neumorphic(
                  style: NeumorphicStyle(
                    depth: -2,
                    intensity: 0.8,
                    boxShape: NeumorphicBoxShape.circle(),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Icon(
                      Icons.gas_meter_outlined,
                      size: 80,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'Smart Gas Monitor',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12),
                Text(
                  'Connect to your monitoring device',
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),
                Neumorphic(
                  style: NeumorphicStyle(
                    depth: -3,
                    intensity: 0.7,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter device IP address',
                      prefixIcon: Icon(Icons.wifi),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                SizedBox(height: 24),
                NeumorphicButton(
                  onPressed: _isConnecting 
                    ? null 
                    : () async {
                        setState(() {
                          _isConnecting = true;
                        });
                        
                        final success = await system.connectToDevice(_ipController.text);
                        
                        setState(() {
                          _isConnecting = false;
                        });
                        
                        if (!success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to connect to device. Check IP and try again.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                  style: NeumorphicStyle(
                    depth: _isConnecting ? 0 : 4,
                    intensity: 0.8,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                    color: Colors.blue[700],
                  ),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: _isConnecting
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'Connect',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                  ),
                ),
                SizedBox(height: 32),
                if (_showLastDevice)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Last Connected Device',
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      Neumorphic(
                        style: NeumorphicStyle(
                          depth: 3,
                          intensity: 0.6,
                          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                        ),
                        padding: EdgeInsets.all(16),
                        child: InkWell(
                          onTap: _isConnecting
                            ? null
                            : () async {
                                setState(() {
                                  _isConnecting = true;
                                });
                                
                                final success = await system.connectToDevice(_lastDeviceIP);
                                
                                setState(() {
                                  _isConnecting = false;
                                });
                                
                                if (!success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to connect to last device.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.devices, color: Colors.blue[700]),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'ID: $_lastDeviceID',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(height: 4),
                                        Text('IP: $_lastDeviceIP'),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios, size: 16),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final system = Provider.of<MonitoringSystem>(context);
    
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: Neumorphic(
          style: NeumorphicStyle(
            depth: 4,
            intensity: 0.8,
            boxShape: NeumorphicBoxShape.rect(),
            color: NeumorphicTheme.baseColor(context),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  NeumorphicButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: NeumorphicTheme.baseColor(context),
                          title: Text('Disconnect'),
                          content: Text('Do you want to disconnect from this device?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                system.disconnect();
                              },
                              child: Text('Disconnect'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: NeumorphicStyle(
                      depth: 2,
                      boxShape: NeumorphicBoxShape.circle(),
                    ),
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, size: 20),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Device ID: ${system.deviceID}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'IP: ${system.deviceIP}',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  system.alarmActive
                    ? _buildAlarmIndicator()
                    : Container(),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Neumorphic(
            margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
            style: NeumorphicStyle(
              depth: -2,
              intensity: 0.7,
              boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(25)),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade700, Colors.blue.shade500],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                  ),
                ],
              ),
              unselectedLabelColor: Colors.grey.shade700,
              labelColor: Colors.white,
              tabs: [
                Tab(text: 'Dashboard'),
                Tab(text: 'Charts'),
                Tab(text: 'Settings'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDashboardTab(system),
                _buildChartsTab(system),
                _buildSettingsTab(system),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAlarmIndicator() {
    return NeumorphicButton(
      style: NeumorphicStyle(
        depth: 2,
        boxShape: NeumorphicBoxShape.circle(),
        color: Colors.red,
      ),
      padding: EdgeInsets.all(8),
      onPressed: () {
        final system = Provider.of<MonitoringSystem>(context, listen: false);
        system.resetAlarm();
      },
      child: Icon(
        Icons.warning_amber_outlined,
        color: Colors.white,
      ),
    );
  }
  
  Widget _buildDashboardTab(MonitoringSystem system) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (system.alarmActive)
            Neumorphic(
              style: NeumorphicStyle(
                depth: 4,
                intensity: 0.8,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                color: Colors.red[600],
              ),
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ALERT!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          system.gasLevel > system.gasThreshold 
                            ? 'Gas leak detected!' 
                            : 'High temperature detected!',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  NeumorphicButton(
                    style: NeumorphicStyle(
                      depth: 2,
                      intensity: 0.7,
                      boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
                      color: Colors.white.withOpacity(0.2),
                    ),
                    onPressed: () {
                      system.resetAlarm();
                    },
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _buildSensorCard(
                  title: 'Temperature',
                  value: '${system.temperature.toStringAsFixed(1)}°C',
                  icon: Icons.thermostat_outlined,
                  color: _getTemperatureColor(system.temperature),
                  subtitle: system.temperature > system.tempThreshold
                    ? 'Above threshold!'
                    : 'Normal',
                  isWarning: system.temperature > system.tempThreshold,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildSensorCard(
                  title: 'Humidity',
                  value: '${system.humidity.toStringAsFixed(1)}%',
                  icon: Icons.water_drop_outlined,
                  color: Colors.blue[700]!,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildSensorCard(
            title: 'Gas Level',
            value: system.gasLevel.toStringAsFixed(0),
            subtitle: system.gasLevel > system.gasThreshold 
              ? 'Gas leak detected!' 
              : 'Normal',
            isWarning: system.gasLevel > system.gasThreshold,
            icon: Icons.local_fire_department_outlined,
            color: _getGasLevelColor(system.gasLevel, system.gasThreshold),
            showProgress: true,
            progress: _calculateGasLevelProgress(system.gasLevel),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildControlButton(
                  title: 'Exhaust Fan',
                  icon: Icons.podcasts_outlined,
                  isActive: system.relayState,
                  onPressed: () {
                    system.toggleRelay();
                  },
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildControlButton(
                  title: 'Auto Mode',
                  icon: Icons.auto_mode_outlined,
                  isActive: system.autoMode,
                  onPressed: () {
                    system.toggleAutoMode();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildChartsTab(MonitoringSystem system) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Neumorphic(
              style: NeumorphicStyle(
                depth: 4,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
              ),
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Temperature History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Expanded(
                    child: system.temperatureHistory.length < 2
                      ? Center(child: Text('Collecting data...'))
                      : LineChart(
                          LineChartData(
                            gridData: FlGridData(show: false),
                            titlesData: FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: _getTemperatureSpots(system.temperatureHistory),
                                isCurved: true,
                                color: Colors.orange,
                                barWidth: 3,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.orange.withOpacity(0.2),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Neumorphic(
              style: NeumorphicStyle(
                depth: 4,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
              ),
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gas Level History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Expanded(
                    child: system.gasHistory.length < 2
                      ? Center(child: Text('Collecting data...'))
                      : LineChart(
                          LineChartData(
                            gridData: FlGridData(show: false),
                            titlesData: FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: _getGasSpots(system.gasHistory),
                                isCurved: true,
                                color: Colors.blue[700],
                                barWidth: 3,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.blue[700]!.withOpacity(0.2),
                                ),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                              ),
                            ),
                            extraLinesData: ExtraLinesData(
                              horizontalLines: [
                                HorizontalLine(
                                  y: system.gasThreshold,
                                  color: Colors.red.withOpacity(0.8),
                                  strokeWidth: 2,
                                  dashArray: [5, 5],
                                ),
                              ],
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  





                        Widget _buildSettingsTab(MonitoringSystem system) {
    final gasThresholdController = TextEditingController(text: system.gasThreshold.toStringAsFixed(0));
    final tempThresholdController = TextEditingController(text: system.tempThreshold.toStringAsFixed(1));
    
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Neumorphic(
            style: NeumorphicStyle(
              depth: 4,
              intensity: 0.6,
              boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
              // padding: EdgeInsets.all(16),
              ),
          
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alarm Thresholds',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                Text('Gas Level Threshold'),
                SizedBox(height: 8),
                Neumorphic(
                  style: NeumorphicStyle(
                    depth: -3,
                    intensity: 0.7,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: gasThresholdController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      suffixText: 'PPM',
                      suffixStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text('Temperature Threshold'),
                SizedBox(height: 8),
                Neumorphic(
                  style: NeumorphicStyle(
                    depth: -3,
                    intensity: 0.7,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: tempThresholdController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      suffixText: '°C',
                      suffixStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                NeumorphicButton(
                  onPressed: () {
                    final gasThreshold = double.tryParse(gasThresholdController.text);
                    final tempThreshold = double.tryParse(tempThresholdController.text);
                    
                    if (gasThreshold != null && tempThreshold != null) {
                      system.updateThresholds(gasThreshold, tempThreshold);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Thresholds updated successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Invalid input. Please enter valid numbers.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: NeumorphicStyle(
                    depth: 4,
                    intensity: 0.8,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                    color: Colors.blue[700],
                  ),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Update Thresholds',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Neumorphic(
            style: NeumorphicStyle(
              depth: 4,
              intensity: 0.6,
              boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
            ),
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                Text('Device ID: ${system.deviceID}'),
                SizedBox(height: 8),
                Text('IP Address: ${system.deviceIP}'),
                SizedBox(height: 8),
                Text('Connection Status: ${system.connected ? 'Connected' : 'Disconnected'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _getTemperatureSpots(List<SensorReading> history) {
    return history
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value))
        .toList();
  }

  List<FlSpot> _getGasSpots(List<SensorReading> history) {
    return history
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value))
        .toList();
  }

  double _calculateGasLevelProgress(double gasLevel) {
    return gasLevel / 1000; // Assuming max gas level is 1000 PPM
  }

  Color _getTemperatureColor(double temperature) {
    if (temperature > 35) {
      return Colors.red;
    } else if (temperature > 30) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  Color _getGasLevelColor(double gasLevel, double threshold) {
    if (gasLevel > threshold) {
      return Colors.red;
    } else if (gasLevel > threshold * 0.8) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String subtitle = '',
    bool isWarning = false,
    bool showProgress = false,
    double progress = 0.0,
  }) {
    return Neumorphic(
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isWarning ? Colors.red : Colors.black,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: isWarning ? Colors.red : Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (showProgress)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: NeumorphicProgress(
                height: 8,
                percent: progress,
                style: ProgressStyle(
                  accent: color,
                  variant: color.withOpacity(0.2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return NeumorphicButton(
      onPressed: onPressed,
      style: NeumorphicStyle(
        depth: isActive ? 4 : -4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
        color: isActive ? Colors.blue[700] : Colors.grey[300],
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isActive ? Colors.white : Colors.grey[700], size: 32),
          SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}