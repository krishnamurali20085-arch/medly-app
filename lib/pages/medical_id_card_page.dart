import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/app_localizations.dart';

class MedicalIdCardPage extends StatefulWidget {
  const MedicalIdCardPage({
    super.key,
    required this.language,
    required this.name,
    required this.email,
    required this.bloodGroup,
    required this.allergies,
    required this.diseases,
    required this.weight,
    required this.height,
    required this.emergencyContacts,
  });

  final String language;
  final String name;
  final String email;
  final String? bloodGroup;
  final String? allergies;
  final String? diseases;
  final String? weight;
  final String? height;
  final List<Map<String, String>> emergencyContacts;

  @override
  State<MedicalIdCardPage> createState() => _MedicalIdCardPageState();
}

class _MedicalIdCardPageState extends State<MedicalIdCardPage> {
  String _t(String v) => AppLocalizations(widget.language).text(v);
  final ScreenshotController _screenshotController = ScreenshotController();

  /// Build QR code data as JSON
  String _buildQrData() {
    final data = {
      'type': 'MEDLY_MEDICAL_ID',
      'name': widget.name,
      'blood_group': widget.bloodGroup ?? 'N/A',
      'allergies': widget.allergies ?? 'None',
      'diseases': widget.diseases ?? 'None',
      'weight': widget.weight ?? 'N/A',
      'height': widget.height ?? 'N/A',
      'emergency_contacts': widget.emergencyContacts.map((c) => {
        'name': c['name'] ?? '',
        'phone': c['phone'] ?? '',
        'tier': c['tier'] ?? '1',
      }).toList(),
      'email': widget.email,
    };
    return jsonEncode(data);
  }

  /// Save the card as image and share
  Future<void> _shareCard() async {
    try {
      final image = await _screenshotController.capture();
      if (image == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/medly_medical_id.png');
      await file.writeAsBytes(image);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '${_t('My Medical ID')} - ${widget.name}',
        text: _t('My Medical ID Card from Medly'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('Error sharing')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qrData = _buildQrData();

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Medical ID Card')),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _shareCard,
            tooltip: _t('Share Card'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // The shareable card
            Screenshot(
              controller: _screenshotController,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.medical_services_rounded, color: Colors.white, size: 36),
                          const SizedBox(height: 4),
                          Text('MEDLY', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 3)),
                          Text(_t('Medical ID Card'), style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),

                    // Patient Info
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Name and photo
                          CircleAvatar(
                            radius: 35,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            child: Text(
                              widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(widget.email, style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 16),

                          // Blood Group (prominent)
                          if (widget.bloodGroup != null && widget.bloodGroup!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bloodtype_rounded, color: Colors.white, size: 22),
                                  const SizedBox(width: 8),
                                  Text('${_t('Blood Group')}: ${widget.bloodGroup}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),

                          // Info cards
                          _buildInfoRow(Icons.warning_amber_rounded, _t('Allergies'), widget.allergies ?? _t('None'), Colors.amber),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.sick_rounded, _t('Diseases / Conditions'), widget.diseases ?? _t('None'), Colors.orange),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.monitor_weight_rounded, _t('Weight (kg)'), widget.weight ?? 'N/A', Colors.teal),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.height_rounded, _t('Height (cm)'), widget.height ?? 'N/A', Colors.blue),

                          // Emergency contacts
                          if (widget.emergencyContacts.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.emergency_rounded, color: Colors.red, size: 18),
                                      const SizedBox(width: 6),
                                      Text(_t('Emergency Contacts'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...widget.emergencyContacts.take(3).map((c) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      'Tier ${c['tier'] ?? '1'}: ${c['name']} - ${c['phone']}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  )),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // QR Code
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          Text(_t('Scan for medical info'), style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            size: 160,
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1B5E20),
                          ),
                          const SizedBox(height: 4),
                          Text('Medly Medical ID', style: TextStyle(color: Colors.grey.shade400, fontSize: 9)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Share button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _shareCard,
                icon: const Icon(Icons.share_rounded),
                label: Text(_t('Share Medical ID Card')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Info text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t('Anyone can scan this QR code to get your emergency medical information. Share it with family and doctors.'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white60, fontSize: 11)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
