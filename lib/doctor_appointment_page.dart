import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'services/doctor_service.dart';
import 'video_call_page.dart';

class DoctorAppointmentPage extends StatefulWidget {
  const DoctorAppointmentPage({super.key});

  @override
  State<DoctorAppointmentPage> createState() => _DoctorAppointmentPageState();
}

class _DoctorAppointmentPageState extends State<DoctorAppointmentPage> {
  List<DoctorInfo> _doctors = [];
  bool _loading = true;
  String? _error;
  String _filter = 'All';
  String _sortBy = 'distance';

  @override
  void initState() {
    super.initState();
    _fetchDoctors();
  }

  Future<void> _fetchDoctors() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Check location permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        setState(() {
          _error = 'Location permission required to find nearby doctors';
          _loading = false;
        });
        return;
      }

      final doctors = await DoctorService.fetchNearbyDoctors(radiusKm: 5);
      if (mounted) {
        setState(() {
          _doctors = doctors;
          _loading = false;
          if (doctors.isEmpty) {
            _error = 'No doctors found within 5km. Try expanding your search.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error finding doctors: $e';
          _loading = false;
        });
      }
    }
  }

  List<DoctorInfo> get _filteredDoctors {
    var list = _doctors.where((d) {
      if (_filter == 'All') return true;
      if (_filter == 'Hospital') return d.specialty.contains('Hospital');
      if (_filter == 'Clinic') return d.specialty.contains('Clinic');
      if (_filter == 'Doctor') return d.specialty.contains('Doctor');
      return true;
    }).toList();

    if (_sortBy == 'distance') {
      list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    } else if (_sortBy == 'name') {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  void _callDoctor(String phone) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available for this doctor'), backgroundColor: Colors.orange),
      );
      return;
    }
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _videoCall(DoctorInfo doctor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallPage(
          doctorName: doctor.name,
          doctorPhone: doctor.phone,
        ),
      ),
    );
  }

  void _openMap(DoctorInfo doctor) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${doctor.latitude},${doctor.longitude}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Appointments'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'distance', child: Text('Sort by Distance')),
              const PopupMenuItem(value: 'name', child: Text('Sort by Name')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _filterChip('All', Icons.all_inclusive),
                const SizedBox(width: 8),
                _filterChip('Hospital', Icons.local_hospital),
                const SizedBox(width: 8),
                _filterChip('Clinic', Icons.medical_services),
                const SizedBox(width: 8),
                _filterChip('Doctor', Icons.person),
              ],
            ),
          ),
          // Results count
          if (!_loading && _doctors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    '${_filteredDoctors.length} doctors/clinics within 5km',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Doctor list
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF6C63FF)),
                        SizedBox(height: 16),
                        Text('Finding nearby doctors...'),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_off, size: 64, color: Colors.orange),
                              const SizedBox(height: 16),
                              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _fetchDoctors,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try Again'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C63FF),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredDoctors.isEmpty
                        ? const Center(child: Text('No doctors match the filter'))
                        : RefreshIndicator(
                            onRefresh: _fetchDoctors,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _filteredDoctors.length,
                              itemBuilder: (ctx, i) => _buildDoctorCard(_filteredDoctors[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, IconData icon) {
    final isSelected = _filter == label;
    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorCard(DoctorInfo doctor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPhone = doctor.phone.isNotEmpty;

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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF6C63FF).withOpacity(0.15),
                  child: Text(
                    doctor.name.isNotEmpty ? doctor.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        doctor.specialty,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${doctor.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ),
              ],
            ),
            if (doctor.address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      doctor.address,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (hasPhone) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.phone, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    doctor.phone,
                    style: const TextStyle(fontSize: 13, color: Colors.green),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                // Call button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasPhone ? () => _callDoctor(doctor.phone) : null,
                    icon: const Icon(Icons.phone, size: 16),
                    label: const Text('Call', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: BorderSide(color: hasPhone ? Colors.green : Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Video call button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _videoCall(doctor),
                    icon: const Icon(Icons.videocam, size: 16),
                    label: const Text('Video Call', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Directions button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openMap(doctor),
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Directions', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
