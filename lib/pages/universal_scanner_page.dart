import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_localizations.dart';

class UniversalScannerPage extends StatefulWidget {
  const UniversalScannerPage({super.key, required this.language});
  final String language;

  @override
  State<UniversalScannerPage> createState() => _UniversalScannerPageState();
}

class _UniversalScannerPageState extends State<UniversalScannerPage> {
  String _t(String v) => AppLocalizations(widget.language).text(v);

  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  String? _lastScanResult;
  ScanType? _lastScanType;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!;
    setState(() => _isProcessing = true);

    _handleScanResult(rawValue);
  }

  void _handleScanResult(String rawValue) {
    final scanType = _detectScanType(rawValue);

    setState(() {
      _lastScanResult = rawValue;
      _lastScanType = scanType;
    });

    _showScanResult(rawValue, scanType);
  }

  ScanType _detectScanType(String value) {
    final lower = value.toLowerCase().trim();

    // Medical ID from Medly
    if (lower.contains('"type":"medly_medical_id"') || lower.contains('"type": "medly_medical_id"')) {
      return ScanType.medicalId;
    }

    // URL
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('www.')) {
      return ScanType.url;
    }

    // Phone number (tel:)
    if (lower.startsWith('tel:') || lower.startsWith('tel%3A')) {
      return ScanType.phone;
    }

    // Email (mailto:)
    if (lower.startsWith('mailto:') || lower.startsWith('mail%3A')) {
      return ScanType.email;
    }

    // WiFi credentials
    if (lower.startsWith('wifi:')) {
      return ScanType.wifi;
    }

    // UPI payment
    if (lower.startsWith('upi://') || lower.startsWith('upi://pay')) {
      return ScanType.upi;
    }

    // Plain phone number (10+ digits)
    final phoneRegex = RegExp(r'^[\+]?[\d\s\-\(\)]{10,15}$');
    if (phoneRegex.hasMatch(value.replaceAll(RegExp(r'[^\d+\-\(\)\s]'), ''))) {
      return ScanType.phone;
    }

    // Email pattern
    final emailRegex = RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$');
    if (emailRegex.hasMatch(value)) {
      return ScanType.email;
    }

    // JSON data
    if (lower.startsWith('{') || lower.startsWith('[')) {
      return ScanType.json;
    }

    return ScanType.text;
  }

  Future<void> _launchAction(String rawValue, ScanType type) async {
    try {
      switch (type) {
        case ScanType.url:
          final url = rawValue.startsWith('http') ? rawValue : 'https://$rawValue';
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          break;

        case ScanType.phone:
          final phone = rawValue.replaceFirst('tel:', '').replaceFirst('tel%3A', '');
          await launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);
          break;

        case ScanType.email:
          final email = rawValue.replaceFirst('mailto:', '').replaceFirst('mail%3A', '');
          await launchUrl(Uri.parse('mailto:$email'), mode: LaunchMode.externalApplication);
          break;

        case ScanType.wifi:
          _connectWifi(rawValue);
          break;

        case ScanType.upi:
          await launchUrl(Uri.parse(rawValue), mode: LaunchMode.externalApplication);
          break;

        case ScanType.medicalId:
          _showMedicalIdInfo(rawValue);
          break;

        case ScanType.json:
          _showJsonInfo(rawValue);
          break;

        case ScanType.text:
          // Just show the text — already displayed in dialog
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('Cannot open')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _connectWifi(String wifiString) {
    // Parse WiFi string: WIFI:S:SSID;T:WPA;P:password;;
    try {
      final ssid = _extractWifiField(wifiString, 'S');
      final password = _extractWifiField(wifiString, 'P');
      final type = _extractWifiField(wifiString, 'T');

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.wifi, color: Colors.blue),
              const SizedBox(width: 8),
              Text(_t('WiFi Network')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(_t('Network'), ssid),
              _infoRow(_t('Security'), type.isNotEmpty ? type : 'Open'),
              if (password.isNotEmpty) _infoRow(_t('Password'), password),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_t('Close')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _copyToClipboard('SSID: $ssid\nPassword: $password');
              },
              child: Text(_t('Copy')),
            ),
          ],
        ),
      );
    } catch (_) {
      _showTextDialog(_t('WiFi Data'), wifiString);
    }
  }

  String _extractWifiField(String wifi, String field) {
    final regex = RegExp('$field:([^;]*)');
    final match = regex.firstMatch(wifi);
    return match?.group(1)?.trim() ?? '';
  }

  void _showMedicalIdInfo(String rawValue) {
    try {
      final data = jsonDecode(rawValue);
      final name = data['name'] ?? 'Unknown';
      final bloodGroup = data['blood_group'] ?? 'N/A';
      final allergies = data['allergies'] ?? 'None';
      final diseases = data['diseases'] ?? 'None';
      final contacts = (data['emergency_contacts'] as List?) ?? [];

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.medical_services, color: Colors.red),
              const SizedBox(width: 8),
              Text(_t('Medical ID')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                if (bloodGroup != 'N/A')
                  _infoRow('${_t('Blood Group')}:', bloodGroup),
                _infoRow('${_t('Allergies')}:', allergies),
                _infoRow('${_t('Diseases')}:', diseases),
                if (contacts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_t('Emergency Contacts'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...contacts.map((c) => Text(
                    '${c['name']} - ${c['phone']}',
                    style: const TextStyle(fontSize: 12),
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Close'))),
            if (contacts.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  final phone = contacts[0]['phone'];
                  if (phone != null) launchUrl(Uri.parse('tel:$phone'));
                },
                icon: const Icon(Icons.phone, size: 16),
                label: Text(_t('Call')),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
          ],
        ),
      );
    } catch (_) {
      _showTextDialog(_t('Medical ID'), rawValue);
    }
  }

  void _showJsonInfo(String rawValue) {
    try {
      final data = jsonDecode(rawValue);
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      _showTextDialog(_t('JSON Data'), pretty);
    } catch (_) {
      _showTextDialog(_t('Scanned Data'), rawValue);
    }
  }

  void _showScanResult(String rawValue, ScanType type) {
    final typeName = _scanTypeName(type);
    final icon = _scanTypeIcon(type);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(typeName)),
          ],
        ),
        content: SelectableText(
          rawValue.length > 300 ? '${rawValue.substring(0, 300)}...' : rawValue,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('Close')),
          ),
          if (type == ScanType.url || type == ScanType.phone || type == ScanType.email || type == ScanType.upi)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _launchAction(rawValue, type);
              },
              icon: Icon(
                type == ScanType.phone ? Icons.phone : type == ScanType.email ? Icons.email : Icons.open_in_new,
                size: 16,
              ),
              label: Text(
                type == ScanType.phone ? _t('Call') : type == ScanType.url ? _t('Open') : _t('Open'),
              ),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          if (type == ScanType.text || type == ScanType.json)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_t('Copied to clipboard')), backgroundColor: Colors.green),
                );
              },
              child: Text(_t('Copy')),
            ),
        ],
      ),
    ).then((_) {
      // Reset processing flag after dialog closes
      setState(() => _isProcessing = false);
    });
  }

  void _showTextDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(content, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Close'))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _copyToClipboard(content);
            },
            child: Text(_t('Copy')),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    // Use a simple approach — just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('Copied to clipboard')), backgroundColor: Colors.green),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  IconData _scanTypeIcon(ScanType? type) {
    switch (type) {
      case ScanType.url: return Icons.language;
      case ScanType.phone: return Icons.phone;
      case ScanType.email: return Icons.email;
      case ScanType.wifi: return Icons.wifi;
      case ScanType.upi: return Icons.payment;
      case ScanType.medicalId: return Icons.medical_services;
      case ScanType.json: return Icons.data_object;
      case ScanType.text: return Icons.text_fields;
      default: return Icons.qr_code_scanner;
    }
  }

  String _scanTypeName(ScanType? type) {
    switch (type) {
      case ScanType.url: return 'URL / Website';
      case ScanType.phone: return _t('Phone Number');
      case ScanType.email: return _t('Email Address');
      case ScanType.wifi: return 'WiFi Network';
      case ScanType.upi: return 'UPI Payment';
      case ScanType.medicalId: return _t('Medical ID');
      case ScanType.json: return 'JSON Data';
      case ScanType.text: return _t('Text');
      default: return _t('Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_t('Universal Scanner')),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _scannerController?.torchEnabled == true ? Icons.flash_on : Icons.flash_off,
              color: _scannerController?.torchEnabled == true ? Colors.amber : Colors.grey,
            ),
            onPressed: () => _scannerController?.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera viewfinder
          MobileScanner(
            controller: _scannerController!,
            onDetect: _onDetect,
          ),

          // Scan overlay frame
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green.withOpacity(0.8), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // Corner decorations
          ..._buildCornerDecorations(),

          // Top instruction text
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _t('Point camera at QR code, barcode, or any scanneble text'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Scan type indicators at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Last scan result
                  if (_lastScanResult != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(_scanTypeIcon(_lastScanType), color: Colors.green, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _scanTypeName(_lastScanType),
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                Text(
                                  _lastScanResult!.length > 50
                                      ? '${_lastScanResult!.substring(0, 50)}...'
                                      : _lastScanResult!,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                            onPressed: () {
                              if (_lastScanResult != null && _lastScanType != null) {
                                _launchAction(_lastScanResult!, _lastScanType!);
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Supported scan types
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      _scanTypeChip(Icons.language, 'URL'),
                      _scanTypeChip(Icons.phone, _t('Phone')),
                      _scanTypeChip(Icons.email, _t('Email')),
                      _scanTypeChip(Icons.wifi, 'WiFi'),
                      _scanTypeChip(Icons.payment, 'UPI'),
                      _scanTypeChip(Icons.medical_services, _t('Medical')),
                      _scanTypeChip(Icons.qr_code, 'QR'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanTypeChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  List<Widget> _buildCornerDecorations() {
    const size = 280.0;
    const borderWidth = 3.0;
    const cornerSize = 30.0;
    final color = Colors.green.shade400;

    return [
      // Top-left
      Positioned(
        top: (MediaQuery.of(context).size.height - size) / 2 - 50,
        left: (MediaQuery.of(context).size.width - size) / 2,
        child: CustomPaint(
          size: const Size(cornerSize, cornerSize),
          painter: _CornerPainter(color, borderWidth, Corner.topLeft),
        ),
      ),
      // Top-right
      Positioned(
        top: (MediaQuery.of(context).size.height - size) / 2 - 50,
        right: (MediaQuery.of(context).size.width - size) / 2,
        child: CustomPaint(
          size: const Size(cornerSize, cornerSize),
          painter: _CornerPainter(color, borderWidth, Corner.topRight),
        ),
      ),
      // Bottom-left
      Positioned(
        bottom: (MediaQuery.of(context).size.height - size) / 2 - 140,
        left: (MediaQuery.of(context).size.width - size) / 2,
        child: CustomPaint(
          size: const Size(cornerSize, cornerSize),
          painter: _CornerPainter(color, borderWidth, Corner.bottomLeft),
        ),
      ),
      // Bottom-right
      Positioned(
        bottom: (MediaQuery.of(context).size.height - size) / 2 - 140,
        right: (MediaQuery.of(context).size.width - size) / 2,
        child: CustomPaint(
          size: const Size(cornerSize, cornerSize),
          painter: _CornerPainter(color, borderWidth, Corner.bottomRight),
        ),
      ),
    ];
  }
}

enum ScanType { url, phone, email, wifi, upi, medicalId, json, text }
enum Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final Corner corner;

  _CornerPainter(this.color, this.strokeWidth, this.corner);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (corner) {
      case Corner.topLeft:
        canvas.drawLine(Offset(0, size.height), Offset(0, 0), paint);
        canvas.drawLine(Offset(0, 0), Offset(size.width, 0), paint);
        break;
      case Corner.topRight:
        canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(0, 0), paint);
        break;
      case Corner.bottomLeft:
        canvas.drawLine(Offset(0, 0), Offset(0, size.height), paint);
        canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
        break;
      case Corner.bottomRight:
        canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, size.height), Offset(0, size.height), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
