import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../services/supabase_service.dart';

class SosHistoryPage extends StatefulWidget {
  final String language;
  final String currentUserEmail;

  const SosHistoryPage({
    super.key,
    required this.language,
    required this.currentUserEmail,
  });

  @override
  State<SosHistoryPage> createState() => _SosHistoryPageState();
}

class _SosHistoryPageState extends State<SosHistoryPage> {
  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _filteredLogs = [];
  bool _loading = true;
  String _filterPatient = 'All';
  DateTimeRange? _dateRange;
  bool _useSupabase = false;
  String? _error;

  String _t(String key) => AppLocalizations(widget.language).text(key);

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Try Supabase first (gets all users' SOS logs for admin)
      if (DatabaseService.isOwner(widget.currentUserEmail)) {
        try {
          final result = await SupabaseService.find('sos_log');
          if (result.isNotEmpty) {
            _allLogs = result;
            _useSupabase = true;
          }
        } catch (_) {
          // Fall back to local
        }
      }

      // Fallback to local SQLite
      if (_allLogs.isEmpty) {
        _allLogs = await DatabaseService.getSosLog();
        _useSupabase = false;
      }

      // Sort by timestamp descending
      _allLogs.sort((a, b) {
        final aTime = a['timestamp']?.toString() ?? '';
        final bTime = b['timestamp']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });

      _applyFilters();
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_allLogs);

    if (_filterPatient != 'All') {
      filtered = filtered.where((l) => l['patient_name'] == _filterPatient).toList();
    }

    if (_dateRange != null) {
      filtered = filtered.where((l) {
        final ts = l['timestamp']?.toString();
        if (ts == null) return false;
        final dt = DateTime.tryParse(ts);
        if (dt == null) return false;
        return !dt.isBefore(_dateRange!.start) && !dt.isAfter(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    _filteredLogs = filtered;
  }

  List<String> get _patientNames {
    final names = _allLogs.map((l) => l['patient_name']?.toString() ?? 'Unknown').toSet().toList();
    names.sort();
    return ['All', ...names];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('SOS History')),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: _t('Refresh'),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: _t('Filters'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadLogs, child: Text(_t('Retry'))),
                    ],
                  ),
                )
              : _filteredLogs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                          const SizedBox(height: 16),
                          Text(_t('No SOS events recorded'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(_t('Emergency calls will appear here'), style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Summary bar
                        _buildSummaryBar(),
                        // Filter chips
                        if (_dateRange != null || _filterPatient != 'All')
                          _buildActiveFilters(),
                        // Log list
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadLogs,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredLogs.length,
                              itemBuilder: (context, index) => _buildLogCard(_filteredLogs[index], index),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildSummaryBar() {
    final patients = _allLogs.map((l) => l['patient_name']?.toString() ?? 'Unknown').toSet().length;
    final today = DateTime.now();
    final todayCount = _allLogs.where((l) {
      final ts = l['timestamp']?.toString();
      if (ts == null) return false;
      final dt = DateTime.tryParse(ts);
      return dt != null && dt.year == today.year && dt.month == today.month && dt.day == today.day;
    }).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.red.shade600, Colors.red.shade800]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem(Icons.warning_amber_rounded, '${_allLogs.length}', _t('Total SOS')),
          Container(width: 1, height: 30, color: Colors.white38),
          _summaryItem(Icons.person, '$patients', _t('Patients')),
          Container(width: 1, height: 30, color: Colors.white38),
          _summaryItem(Icons.today, '$todayCount', _t('Today')),
          Container(width: 1, height: 30, color: Colors.white38),
          _summaryItem(
            _useSupabase ? Icons.cloud_done : Icons.phone_android,
            _useSupabase ? 'Cloud' : 'Local',
            _useSupabase ? _t('Cloud') : _t('Device'),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildActiveFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (_filterPatient != 'All')
            Chip(
              label: Text(_filterPatient, style: const TextStyle(fontSize: 12)),
              onDeleted: () {
                setState(() {
                  _filterPatient = 'All';
                  _applyFilters();
                });
              },
              backgroundColor: Colors.red.shade100,
              deleteIcon: const Icon(Icons.close, size: 16),
            ),
          if (_dateRange != null) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(
                '${_dateRange!.start.day}/${_dateRange!.start.month} - ${_dateRange!.end.day}/${_dateRange!.end.month}',
                style: const TextStyle(fontSize: 12),
              ),
              onDeleted: () {
                setState(() {
                  _dateRange = null;
                  _applyFilters();
                });
              },
              backgroundColor: Colors.blue.shade100,
              deleteIcon: const Icon(Icons.close, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, int index) {
    final timestamp = log['timestamp']?.toString() ?? '';
    DateTime? dt;
    try {
      dt = DateTime.parse(timestamp);
    } catch (_) {}

    final patientName = log['patient_name']?.toString() ?? 'Unknown';
    final contactName = log['contact_name']?.toString() ?? '';
    final contactPhone = log['contact_phone']?.toString() ?? '';
    final lat = log['latitude'];
    final lng = log['longitude'];
    final hasLocation = lat != null && lng != null;

    // Group consecutive entries from the same SOS event (same patient, within 5 min)
    final isGroupStart = index == 0 ||
        _filteredLogs[index - 1]['patient_name'] != patientName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date separator
        if (isGroupStart)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
            child: Text(
              dt != null ? _formatDate(dt) : 'Unknown Date',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        // SOS event card
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: hasLocation ? () => _showOnMap(lat, lng, patientName, dt) : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Red SOS icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              dt != null ? _formatTime(dt) : timestamp,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (hasLocation)
                        Icon(Icons.map_rounded, color: Colors.blue.shade400, size: 20),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Contact info
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_rounded, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(contactName.isNotEmpty ? contactName : _t('Emergency Contact'),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(contactPhone.isNotEmpty ? contactPhone : '--',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (contactPhone.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.call, color: Colors.green, size: 20),
                            onPressed: () => _callContact(contactPhone),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                  // Location info
                  if (hasLocation) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.blue.shade600, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_t('Location')}: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                            ),
                          ),
                          Text(
                            _t('Tap to view'),
                            style: TextStyle(fontSize: 10, color: Colors.blue.shade400),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return _t('Today');
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) return _t('Yesterday');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  void _showOnMap(double lat, double lng, String patientName, DateTime? dt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$patientName - ${_t('SOS Location')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (dt != null)
                          Text(_formatTime(dt), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(lat, lng),
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.medly',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(lat, lng),
                        width: 50,
                        height: 50,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)],
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 20),
                            ),
                            Container(
                              width: 2,
                              height: 8,
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      label: Text(_t('Close')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Open in external map
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(_t('Open in Maps')),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _callContact(String phone) {
    // Use url_launcher to call
    // For now, just show the number
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Call Contact')),
        content: Text(phone),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Cancel'))),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    String tempPatient = _filterPatient;
    DateTimeRange? tempRange = _dateRange;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(_t('Filter SOS History')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('Patient'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: tempPatient,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: _patientNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                onChanged: (v) => setDialogState(() => tempPatient = v ?? 'All'),
              ),
              const SizedBox(height: 16),
              Text(_t('Date Range'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: tempRange,
                    );
                    if (picked != null) setDialogState(() => tempRange = picked);
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(tempRange != null
                      ? '${tempRange!.start.day}/${tempRange!.start.month}/${tempRange!.start.year} - ${tempRange!.end.day}/${tempRange!.end.month}/${tempRange!.end.year}'
                      : _t('Select date range')),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  tempPatient = 'All';
                  tempRange = null;
                });
              },
              child: Text(_t('Clear')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Cancel'))),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _filterPatient = tempPatient;
                  _dateRange = tempRange;
                  _applyFilters();
                });
              },
              child: Text(_t('Apply')),
            ),
          ],
        ),
      ),
    );
  }
}
