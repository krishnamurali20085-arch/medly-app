import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bluetooth Heart Rate Service
/// Connects to BLE smartwatches and reads heart rate data
class BluetoothHRService {
  static final BluetoothHRService _instance = BluetoothHRService._();
  factory BluetoothHRService() => _instance;
  BluetoothHRService._();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _heartRateCharacteristic;
  StreamSubscription<List<int>>? _subscription;
  final StreamController<int> _heartRateController = StreamController<int>.broadcast();

  Stream<int> get heartRateStream => _heartRateController.stream;
  bool get isConnected => _connectedDevice != null;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // Standard BLE Heart Rate Service UUID
  static final Guid heartRateServiceUuid = Guid('0000180d-0000-1000-8000-00805f9b34fb');
  static final Guid heartRateMeasurementUuid = Guid('00002a37-0000-1000-8000-00805f9b34fb');

  /// Check and request Bluetooth permissions
  Future<bool> requestPermissions() async {
    // Android 12+ needs these
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final location = await Permission.locationWhenInUse.request();
    return scan.isGranted && connect.isGranted && location.isGranted;
  }

  /// Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// Scan for nearby BLE devices that have heart rate service
  Future<List<ScanResult>> scanForDevices({Duration timeout = const Duration(seconds: 8)}) async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) return [];

    final isOn = await isBluetoothAvailable();
    if (!isOn) return [];

    // Stop any previous scan
    try { await FlutterBluePlus.stopScan(); } catch (_) {}

    final results = <ScanResult>[];
    final subscription = FlutterBluePlus.onScanResults.listen((scanResults) {
      results.clear();
      for (final r in scanResults) {
        // Include devices that advertise heart rate service
        final hasHR = r.advertisementData.serviceUuids.any(
          (uuid) => uuid.toString().toLowerCase().contains('180d'),
        );
        if (hasHR || r.advertisementData.advName.isNotEmpty) {
          results.add(r);
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: timeout);
    await subscription.cancel();

    // Sort: devices with HR service first, then by signal strength
    results.sort((a, b) {
      final aHR = a.advertisementData.serviceUuids.any(
        (uuid) => uuid.toString().toLowerCase().contains('180d'),
      );
      final bHR = b.advertisementData.serviceUuids.any(
        (uuid) => uuid.toString().toLowerCase().contains('180d'),
      );
      if (aHR && !bHR) return -1;
      if (!aHR && bHR) return 1;
      return b.rssi.compareTo(a.rssi);
    });

    return results;
  }

  /// Connect to a device and subscribe to heart rate measurements
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      // Disconnect from previous device
      await disconnect();

      // Connect
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;

      // Discover services
      final services = await device.discoverServices();

      // Find heart rate service
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains('180d')) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase().contains('2a37')) {
              _heartRateCharacteristic = characteristic;

              // Enable notifications
              await characteristic.setNotifyValue(true);

              // Listen to heart rate data
              _subscription = characteristic.onValueReceived.listen((data) {
                final hr = _parseHeartRate(data);
                if (hr > 0 && hr < 250) {
                  _heartRateController.add(hr);
                }
              });

              return true;
            }
          }
        }
      }

      // If no standard HR service found, try to listen to ALL characteristics
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.properties.notify || characteristic.properties.indicate) {
            try {
              await characteristic.setNotifyValue(true);
              _subscription = characteristic.onValueReceived.listen((data) {
                if (data.isNotEmpty && data[0] > 0 && data[0] < 250) {
                  _heartRateController.add(data[0]);
                }
              });
              _heartRateCharacteristic = characteristic;
              return true;
            } catch (_) {}
          }
        }
      }

      return false;
    } catch (e) {
      print('[BLE] Connection error: $e');
      return false;
    }
  }

  /// Parse heart rate from BLE data (Bluetooth Heart Rate Measurement format)
  int _parseHeartRate(List<int> data) {
    if (data.isEmpty) return 0;

    final flags = data[0];
    final is16Bit = (flags & 0x01) != 0;

    if (is16Bit && data.length >= 3) {
      return data[1] | (data[2] << 8);
    } else if (data.length >= 2) {
      return data[1];
    }
    return 0;
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
      _heartRateCharacteristic = null;
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
      }
    } catch (_) {}
  }

  /// Get the last known connected device name
  String? get connectedDeviceName => _connectedDevice?.platformName;

  void dispose() {
    _subscription?.cancel();
    _heartRateController.close();
  }
}
