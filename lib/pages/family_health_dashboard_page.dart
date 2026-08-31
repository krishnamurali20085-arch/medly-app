import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../services/supabase_service.dart';

class FamilyHealthDashboardPage extends StatefulWidget {
  const FamilyHealthDashboardPage({
    super.key,
    required this.caregiverEmail,
    required this.caregiverName,
    this.language = 'English',
  });

  final String caregiverEmail;
  final String caregiverName;
  final String language;

  @override
  State<FamilyHealthDashboardPage> createState() => _FamilyHealthDashboardPageState();
}

class _FamilyHealthDashboardPageState extends State<FamilyHealthDashboardPage> {
  List<Map<String, dynamic>> _familyMembers = [];
  List<Map<String, dynamic>> _sosAlerts = [];
  bool _loading = true;
  Timer? _refreshTimer;
  DateTime _lastRefresh = DateTime.now();

  String _t(String v) => AppLocalizations(widget.language).text(v);

  final List<Color> _cardColors = [
    const Color(0xFF6366F1),
    const Color(0xFFEC4899),
    const Color(0xFF14B8A6),
    const Color(0xFFF59E0B),
    const Color(0xFF3B82F6),
    const Color(0xFF10B981),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every 30 seconds for real-time monitoring
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!_loading && mounted) setState(() => _loading = true);
    try {
      final members = await DatabaseService.getFamilyMembers(widget.caregiverEmail);
      // Load active SOS alerts from Supabase
      List<Map<String, dynamic>> alerts = [];
      try {
        final sosLocations = await SupabaseService.find('sos_locations');
        final now = DateTime.now();
        alerts = sosLocations.where((s) {
          final expires = DateTime.tryParse(s['expires_at']?.toString() ?? '');
          return expires != null && expires.isAfter(now);
        }).toList();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _familyMembers = members;
          _sosAlerts = alerts;
          _loading = false;
          _lastRefresh = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101827) : const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.family_restroom_rounded, size: 22),
            const SizedBox(width: 8),
            Text(_t('Family Health Dashboard')),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          // Real-time indicator
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(_t('Live'), style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: _t('Refresh'),
          ),
          IconButton(
            onPressed: _showAddFamilyMemberDialog,
            icon: const Icon(Icons.person_add_rounded),
            tooltip: _t('Add family member'),
          ),
        ],
      ),
      body: _loading && _familyMembers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // SOS Alert Banner
                  if (_sosAlerts.isNotEmpty) _buildSosAlertBanner(),
                  // Summary Stats
                  _buildSummaryStats(),
                  const SizedBox(height: 16),
                  // Family Members
                  if (_familyMembers.isEmpty)
                    _buildEmptyState()
                  else
                    ...List.generate(_familyMembers.length, (index) {
                      final member = _familyMembers[index];
                      final color = _cardColors[index % _cardColors.length];
                      return _buildEnhancedMemberCard(member, color, isDark);
                    }),
                  // Last refreshed
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '${_t("Last updated")}: ${_lastRefresh.hour}:${_lastRefresh.minute.toString().padLeft(2, '0')}:${_lastRefresh.second.toString().padLeft(2, '0')} • ${_t("Auto-refreshes every 30s")}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSosAlertBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.red.shade600, Colors.red.shade800]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                '🚨 ${_t("Active SOS Alert")}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._sosAlerts.map((alert) {
            final name = alert['patient_name']?.toString() ?? 'Unknown';
            final lat = alert['latitude'];
            final lng = alert['longitude'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('$name — ${lat != null ? "${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}" : "Location unknown"}',
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  if (lat != null && lng != null)
                    TextButton(
                      onPressed: () => _showSosLocation(lat, lng, name),
                      child: const Text('View Map', style: TextStyle(color: Colors.yellowAccent, fontSize: 12)),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryStats() {
    final total = _familyMembers.length;
    // Count members with recent health data
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(Icons.people_rounded, '$total', _t('Members'), const Color(0xFF6366F1)),
          Container(width: 1, height: 30, color: Colors.grey.shade200),
          _statItem(Icons.warning_amber_rounded, '${_sosAlerts.length}', _t('SOS Alerts'), Colors.red),
          Container(width: 1, height: 30, color: Colors.grey.shade200),
          _statItem(Icons.monitor_heart_rounded, '$total', _t('Monitoring'), const Color(0xFF14B8A6)),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.family_restroom_rounded, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(_t('No family members yet'), style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_t('Add family members to monitor their health'), style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddFamilyMemberDialog,
            icon: const Icon(Icons.person_add_rounded),
            label: Text(_t('Add Family Member')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              minimumSize: const Size(240, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedMemberCard(Map<String, dynamic> member, Color color, bool isDark) {
    final name = member['patient_name'] ?? 'Unknown';
    final relationship = member['relationship'] ?? 'Family';
    final bloodGroup = member['blood_group'] ?? 'Unknown';
    final allergies = member['allergies'] ?? 'None';
    final age = member['age'] ?? '--';
    final phone = member['phone'] ?? '';
    final weight = member['weight'] ?? '--';
    final height = member['height'] ?? '--';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(relationship, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          Text('Age: $age', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(width: 6),
                          // Online indicator
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _showEditFamilyMemberDialog(member);
                    if (v == 'add_health') _showAddHealthDataDialog(member);
                    if (v == 'call' && phone.isNotEmpty) _makePhoneCall(phone);
                    if (v == 'location' && member['patient_email'] != null) _showMemberLocation(member);
                    if (v == 'delete') _deleteFamilyMember(member);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 18), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'add_health', child: Row(children: [Icon(Icons.monitor_heart_rounded, size: 18), SizedBox(width: 8), Text('Add Health Data')])),
                    if (phone.isNotEmpty)
                      const PopupMenuItem(value: 'call', child: Row(children: [Icon(Icons.phone_rounded, size: 18, color: Colors.green), SizedBox(width: 8), Text('Call', style: TextStyle(color: Colors.green))])),
                    const PopupMenuItem(value: 'location', child: Row(children: [Icon(Icons.location_on_rounded, size: 18, color: Colors.blue), SizedBox(width: 8, ), Text('View Location', style: TextStyle(color: Colors.blue))])),
                    PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_rounded, size: 18, color: Colors.red), const SizedBox(width: 8), Text(_t('Remove'), style: const TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            ),
          ),
          // Health Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info pills row
                Row(
                  children: [
                    _healthPill('🩸 ${_t('Blood')}', bloodGroup, isDark),
                    const SizedBox(width: 8),
                    _healthPill('⚠️ ${_t('Allergies')}', allergies, isDark),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _healthPill('⚖️ ${_t('Weight')}', '$weight kg', isDark),
                    const SizedBox(width: 8),
                    _healthPill('📏 ${_t('Height')}', '$height cm', isDark),
                  ],
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _healthPill('📞 ${_t('Phone')}', phone, isDark),
                ],
                const SizedBox(height: 12),
                // Quick action buttons
                Row(
                  children: [
                    if (phone.isNotEmpty) ...[
                      Expanded(
                        child: _quickActionButton(
                          Icons.phone_rounded, _t('Call'), Colors.green,
                          () => _makePhoneCall(phone),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: _quickActionButton(
                        Icons.add_chart_rounded, _t('Add Data'), color,
                        () => _showAddHealthDataDialog(member),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _quickActionButton(
                        Icons.history_rounded, _t('History'), Colors.teal,
                        () => _showHealthHistory(member),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Latest health snapshot
                FutureBuilder<Map<String, dynamic>?>(
                  future: DatabaseService.getLatestFamilyHealthSnapshot(member['id']),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    final snapshot = snap.data;
                    if (snapshot == null) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: Colors.grey.shade500),
                            const SizedBox(width: 8),
                            Text(_t('No health data yet. Tap menu to add.'), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
                      );
                    }
                    return _buildLatestHealthCard(snapshot, color, isDark);
                  },
                ),
                const SizedBox(height: 8),
                // Health alerts
                _buildHealthAlerts(member),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthAlerts(Map<String, dynamic> member) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: DatabaseService.getLatestFamilyHealthSnapshot(member['id']),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
        final s = snap.data!;
        final alerts = <String>[];

        // Check blood pressure
        final bp = s['blood_pressure']?.toString() ?? '';
        if (bp.isNotEmpty) {
          final systolic = int.tryParse(bp.split('/').first) ?? 0;
          if (systolic >= 140) alerts.add('⚠️ High Blood Pressure ($bp)');
          else if (systolic <= 90) alerts.add('⚠️ Low Blood Pressure ($bp)');
        }

        // Check blood sugar
        final sugar = double.tryParse(s['blood_sugar']?.toString() ?? '') ?? 0;
        if (sugar >= 200) alerts.add('⚠️ High Blood Sugar ($sugar mg/dL)');
        else if (sugar <= 60) alerts.add('⚠️ Low Blood Sugar ($sugar mg/dL)');

        // Check heart rate
        final hr = int.tryParse(s['heart_rate']?.toString() ?? '') ?? 0;
        if (hr >= 100) alerts.add('⚠️ High Heart Rate ($hr bpm)');
        else if (hr <= 50 && hr > 0) alerts.add('⚠️ Low Heart Rate ($hr bpm)');

        // Check sleep
        final sleep = double.tryParse(s['sleep_hours']?.toString() ?? '') ?? 0;
        if (sleep > 0 && sleep < 5) alerts.add('⚠️ Insufficient Sleep (${sleep}h)');

        if (alerts.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.health_and_safety_rounded, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text(_t('Health Alerts'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                ],
              ),
              const SizedBox(height: 6),
              ...alerts.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(a, style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _healthPill(String label, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.black54)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestHealthCard(Map<String, dynamic> snapshot, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Text('${_t("Latest")}: ${snapshot['date_key'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniMetric('BP', snapshot['blood_pressure'] ?? '--', isDark),
              _miniMetric('Sugar', snapshot['blood_sugar'] ?? '--', isDark),
              _miniMetric('HR', snapshot['heart_rate'] ?? '--', isDark),
              _miniMetric(_t('Sleep'), snapshot['sleep_hours'] ?? '--', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  void _makePhoneCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showMemberLocation(Map<String, dynamic> member) async {
    // Try to get location from Supabase SOS data
    try {
      final sosData = await SupabaseService.find('sos_locations', filter: {'patient_name': member['patient_name']});
      if (sosData.isNotEmpty) {
        final lat = sosData.first['latitude'];
        final lng = sosData.first['longitude'];
        if (lat != null && lng != null) {
          _showSosLocation(lat, lng, member['patient_name']);
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('No location data available for this member'))),
      );
    }
  }

  void _showSosLocation(double lat, double lng, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$name - ${_t("Location")}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ],
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 15),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.medly'),
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(lat, lng),
                      width: 50, height: 50,
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ]),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Add / Edit / Delete dialogs (same as before) ----

  void _showAddFamilyMemberDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final ageController = TextEditingController();
    final phoneController = TextEditingController();
    final bloodGroupController = TextEditingController();
    final allergiesController = TextEditingController();
    final weightController = TextEditingController();
    final heightController = TextEditingController();
    String selectedRelationship = 'Family';
    final relationships = ['Family', 'Spouse', 'Parent', 'Child', 'Sibling', 'Grandparent', 'Friend', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(_t('Add Family Member')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: InputDecoration(labelText: _t('Full Name'), border: const OutlineInputBorder()), textCapitalization: TextCapitalization.words),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRelationship,
                  decoration: InputDecoration(labelText: _t('Relationship'), border: const OutlineInputBorder()),
                  items: relationships.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) { if (v != null) setDialogState(() => selectedRelationship = v); },
                ),
                const SizedBox(height: 12),
                TextField(controller: emailController, decoration: InputDecoration(labelText: _t('Email (optional)'), border: const OutlineInputBorder()), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                TextField(controller: ageController, decoration: InputDecoration(labelText: _t('Age'), border: const OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                TextField(controller: phoneController, decoration: InputDecoration(labelText: _t('Phone'), border: const OutlineInputBorder()), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: bloodGroupController, decoration: InputDecoration(labelText: _t('Blood Group'), border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: allergiesController, decoration: InputDecoration(labelText: _t('Allergies'), border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: weightController, decoration: InputDecoration(labelText: _t('Weight (kg)'), border: const OutlineInputBorder()), keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: heightController, decoration: InputDecoration(labelText: _t('Height (cm)'), border: const OutlineInputBorder()), keyboardType: TextInputType.number)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Cancel'))),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('Name is required'))));
                  return;
                }
                await DatabaseService.addFamilyMember(
                  caregiverEmail: widget.caregiverEmail,
                  patientName: nameController.text.trim(),
                  patientEmail: emailController.text.trim().isNotEmpty ? emailController.text.trim() : null,
                  relationship: selectedRelationship,
                  bloodGroup: bloodGroupController.text.trim().isNotEmpty ? bloodGroupController.text.trim() : null,
                  allergies: allergiesController.text.trim().isNotEmpty ? allergiesController.text.trim() : null,
                  weight: weightController.text.trim().isNotEmpty ? weightController.text.trim() : null,
                  height: heightController.text.trim().isNotEmpty ? heightController.text.trim() : null,
                  age: ageController.text.trim().isNotEmpty ? ageController.text.trim() : null,
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                );
                SupabaseService.syncFamilyMember(
                  caregiverEmail: widget.caregiverEmail,
                  patientName: nameController.text.trim(),
                  patientEmail: emailController.text.trim().isNotEmpty ? emailController.text.trim() : null,
                  relationship: selectedRelationship,
                  bloodGroup: bloodGroupController.text.trim().isNotEmpty ? bloodGroupController.text.trim() : null,
                  allergies: allergiesController.text.trim().isNotEmpty ? allergiesController.text.trim() : null,
                  weight: weightController.text.trim().isNotEmpty ? weightController.text.trim() : null,
                  height: heightController.text.trim().isNotEmpty ? heightController.text.trim() : null,
                  age: ageController.text.trim().isNotEmpty ? ageController.text.trim() : null,
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                );
                Navigator.pop(ctx);
                _loadData();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('added to family').replaceAll('{name}', nameController.text.trim()))));
              },
              child: Text(_t('Add Member')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditFamilyMemberDialog(Map<String, dynamic> member) {
    final nameController = TextEditingController(text: member['patient_name'] ?? '');
    final emailController = TextEditingController(text: member['patient_email'] ?? '');
    final ageController = TextEditingController(text: member['age'] ?? '');
    final phoneController = TextEditingController(text: member['phone'] ?? '');
    final bloodGroupController = TextEditingController(text: member['blood_group'] ?? '');
    final allergiesController = TextEditingController(text: member['allergies'] ?? '');
    String selectedRelationship = member['relationship'] ?? 'Family';
    final relationships = ['Family', 'Spouse', 'Parent', 'Child', 'Sibling', 'Grandparent', 'Friend', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${_t('Edit')} ${member['patient_name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRelationship,
                  decoration: InputDecoration(labelText: _t('Relationship'), border: const OutlineInputBorder()),
                  items: relationships.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) { if (v != null) setDialogState(() => selectedRelationship = v); },
                ),
                const SizedBox(height: 12),
                TextField(controller: emailController, decoration: InputDecoration(labelText: _t('Email'), border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: ageController, decoration: InputDecoration(labelText: _t('Age'), border: const OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                TextField(controller: phoneController, decoration: InputDecoration(labelText: _t('Phone'), border: const OutlineInputBorder()), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: bloodGroupController, decoration: InputDecoration(labelText: _t('Blood Group'), border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: allergiesController, decoration: InputDecoration(labelText: _t('Allergies'), border: const OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await DatabaseService.updateFamilyMember(member['id'], {
                  'patient_name': nameController.text.trim(),
                  'patient_email': emailController.text.trim(),
                  'relationship': selectedRelationship,
                  'age': ageController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'blood_group': bloodGroupController.text.trim(),
                  'allergies': allergiesController.text.trim(),
                });
                Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddHealthDataDialog(Map<String, dynamic> member) {
    final bpController = TextEditingController();
    final sugarController = TextEditingController();
    final hrController = TextEditingController();
    final sleepController = TextEditingController();
    final notesController = TextEditingController();
    final todayKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Add Health Data for {name}').replaceAll('{name}', member['patient_name'])),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_t('Date: {date}').replaceAll('{date}', todayKey), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(controller: bpController, decoration: InputDecoration(labelText: _t('Blood Pressure'), hintText: '120/80', border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: sugarController, decoration: InputDecoration(labelText: _t('Blood Sugar'), border: const OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: hrController, decoration: InputDecoration(labelText: _t('Heart Rate'), border: const OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: sleepController, decoration: InputDecoration(labelText: _t('Sleep (hours)'), border: const OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: notesController, decoration: InputDecoration(labelText: _t('Notes (optional)'), border: const OutlineInputBorder()), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await DatabaseService.saveFamilyHealthSnapshot(
                familyMemberId: member['id'],
                caregiverEmail: widget.caregiverEmail,
                dateKey: todayKey,
                bloodPressure: bpController.text.trim().isNotEmpty ? bpController.text.trim() : null,
                bloodSugar: sugarController.text.trim().isNotEmpty ? sugarController.text.trim() : null,
                heartRate: hrController.text.trim().isNotEmpty ? hrController.text.trim() : null,
                sleepHours: sleepController.text.trim().isNotEmpty ? sleepController.text.trim() : null,
                notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
              );
              SupabaseService.syncFamilyHealthSnapshot(
                caregiverEmail: widget.caregiverEmail,
                patientName: member['patient_name'],
                dateKey: todayKey,
                bloodPressure: bpController.text.trim().isNotEmpty ? bpController.text.trim() : null,
                bloodSugar: sugarController.text.trim().isNotEmpty ? sugarController.text.trim() : null,
                heartRate: hrController.text.trim().isNotEmpty ? hrController.text.trim() : null,
                sleepHours: sleepController.text.trim().isNotEmpty ? sleepController.text.trim() : null,
                notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
              );
              Navigator.pop(ctx);
              _loadData();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Health data saved')));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showHealthHistory(Map<String, dynamic> member) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FamilyHealthHistoryPage(
          memberName: member['patient_name'] ?? 'Unknown',
          memberId: member['id'],
          language: widget.language,
        ),
      ),
    );
  }

  void _deleteFamilyMember(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Remove Family Member')),
        content: Text(_t('Remove {name} and all their health data?').replaceAll('{name}', member['patient_name'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await DatabaseService.deleteFamilyMember(member['id']);
              Navigator.pop(ctx);
              _loadData();
            },
            child: Text(_t('Remove')),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Family Health History Page (enhanced)
// ---------------------------------------------------------------------------
class FamilyHealthHistoryPage extends StatelessWidget {
  const FamilyHealthHistoryPage({
    super.key,
    required this.memberName,
    required this.memberId,
    this.language = 'English',
  });

  final String memberName;
  final int memberId;
  final String language;

  String _t(String v) => AppLocalizations(language).text(v);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('$memberName - ${_t("Health History")}'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService.getFamilyHealthSnapshots(memberId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final snapshots = snap.data ?? [];
          if (snapshots.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(_t('No health history yet'), style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshots.length,
            itemBuilder: (ctx, i) {
              final s = snapshots[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.teal.shade600),
                          const SizedBox(width: 6),
                          Text(s['date_key'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _historyMetric('BP', s['blood_pressure'] ?? '--'),
                          _historyMetric('Sugar', s['blood_sugar'] ?? '--'),
                          _historyMetric('HR', s['heart_rate'] ?? '--'),
                          _historyMetric(_t('Sleep'), s['sleep_hours'] ?? '--'),
                        ],
                      ),
                      if (s['notes'] != null && s['notes'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('📝 ${s["notes"]}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _historyMetric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
