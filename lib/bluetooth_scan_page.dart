import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'services/bluetooth_hr_service.dart';

class BluetoothScanPage extends StatefulWidget {
  const BluetoothScanPage({super.key});

  @override
  State<BluetoothScanPage> createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage> {
  final BluetoothHRService _bleService = BluetoothHRService();
  List<ScanResult> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  BluetoothDevice? _connectingDevice;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    final hasPermission = await _bleService.requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth and Location permissions are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isScanning = false);
      return;
    }

    final isOn = await _bleService.isBluetoothAvailable();
    if (!isOn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Bluetooth'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      setState(() => _isScanning = false);
      return;
    }

    final devices = await _bleService.scanForDevices(timeout: const Duration(seconds: 10));
    if (mounted) {
      setState(() {
        _devices = devices;
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _connectingDevice = device;
    });

    final success = await _bleService.connectToDevice(device);

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _connectingDevice = null;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.platformName}!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${device.platformName}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan for Smartwatch'),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text('⌚', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(
                  'Connect your smartwatch to read heart rate',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Make sure your watch is in pairing mode',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          // Connected device indicator
          if (_bleService.isConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_connected, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Connected: ${_bleService.connectedDeviceName ?? "Unknown"}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Device list
          Expanded(
            child: _isScanning
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF6C63FF)),
                        SizedBox(height: 16),
                        Text('Scanning for devices...'),
                      ],
                    ),
                  )
                : _devices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🔍', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 16),
                            const Text('No devices found', style: TextStyle(fontSize: 18)),
                            const SizedBox(height: 8),
                            Text(
                              'Make sure your smartwatch is on and nearby',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _startScan,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Scan Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6C63FF),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _devices.length,
                        itemBuilder: (ctx, i) {
                          final device = _devices[i];
                          final name = device.advertisementData.advName.isNotEmpty
                              ? device.advertisementData.advName
                              : device.device.platformName.isNotEmpty
                                  ? device.device.platformName
                                  : 'Unknown Device';
                          final hasHR = device.advertisementData.serviceUuids.any(
                            (uuid) => uuid.toString().toLowerCase().contains('180d'),
                          );
                          final isConnecting = _isConnecting && _connectingDevice == device.device;
                          final signalStrength = device.rssi;
                          String signalIcon;
                          Color signalColor;
                          if (signalStrength > -50) {
                            signalIcon = '📶';
                            signalColor = Colors.green;
                          } else if (signalStrength > -70) {
                            signalIcon = '📶';
                            signalColor = Colors.orange;
                          } else {
                            signalIcon = '📶';
                            signalColor = Colors.red;
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: hasHR
                                    ? const Color(0xFF6C63FF).withOpacity(0.15)
                                    : Colors.grey.withOpacity(0.15),
                                child: Text(
                                  hasHR ? '⌚' : '📱',
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Row(
                                children: [
                                  if (hasHR)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '❤️ Heart Rate',
                                        style: TextStyle(fontSize: 10, color: Colors.green),
                                      ),
                                    ),
                                  Text(
                                    '$signalStrength dBm',
                                    style: TextStyle(fontSize: 11, color: signalColor),
                                  ),
                                ],
                              ),
                              trailing: isConnecting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.bluetooth, color: Color(0xFF6C63FF)),
                                      onPressed: () => _connectToDevice(device.device),
                                    ),
                              onTap: () => _connectToDevice(device.device),
                            ),
                          );
                        },
                      ),
          ),

          // Scan button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching),
                label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
