import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoCallPage extends StatefulWidget {
  final String doctorName;
  final String doctorPhone;

  const VideoCallPage({
    super.key,
    required this.doctorName,
    required this.doctorPhone,
  });

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  CameraController? _cameraController;
  bool _isFrontCamera = true;
  bool _isMuted = false;
  bool _isVideoOn = true;
  bool _isInitialized = false;
  String? _error;
  Timer? _callTimer;
  int _callDuration = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found');
        return;
      }

      final camera = _isFrontCamera
          ? cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => cameras.first,
            )
          : cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: !_isMuted,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        _startCallTimer();
      }
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  String get _formattedDuration {
    final mins = (_callDuration ~/ 60).toString().padLeft(2, '0');
    final secs = (_callDuration % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _switchCamera() async {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isInitialized = false;
    });
    await _cameraController?.dispose();
    _cameraController = null;
    await _initCamera();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleVideo() {
    setState(() => _isVideoOn = !_isVideoOn);
  }

  void _endCall() {
    _callTimer?.cancel();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main video feed
          if (_isInitialized && _cameraController != null && _isVideoOn)
            Center(
              child: CameraPreview(_cameraController!),
            )
          else if (_isVideoOn && _error == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _isFrontCamera ? 'Starting front camera...' : 'Starting back camera...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF2E7D32),
                    child: Text(
                      widget.doctorName.isNotEmpty ? widget.doctorName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.doctorName,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.doctorPhone.isNotEmpty ? widget.doctorPhone : 'No number available',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

          // Top bar - doctor info
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                left: 20,
                right: 20,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF2E7D32),
                    child: Text(
                      widget.doctorName.isNotEmpty ? widget.doctorName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.doctorName,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _formattedDuration,
                          style: const TextStyle(color: Colors.green, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 8),
                        SizedBox(width: 4),
                        Text('LIVE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // PiP - small camera preview
          if (_isInitialized && _cameraController != null && _isVideoOn)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              right: 20,
              child: GestureDetector(
                onTap: _switchCamera,
                child: Container(
                  width: 100,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: 20,
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 40,
                right: 40,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute
                  _controlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    onTap: _toggleMute,
                    active: !_isMuted,
                  ),
                  // Switch camera
                  _controlButton(
                    icon: Icons.cameraswitch,
                    label: 'Flip',
                    onTap: _switchCamera,
                  ),
                  // Video on/off
                  _controlButton(
                    icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
                    label: _isVideoOn ? 'Video On' : 'Video Off',
                    onTap: _toggleVideo,
                    active: _isVideoOn,
                  ),
                  // End call
                  _controlButton(
                    icon: Icons.call_end,
                    label: 'End',
                    onTap: _endCall,
                    isEndCall: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = true,
    bool isEndCall = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isEndCall
                  ? Colors.red
                  : active
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isEndCall ? Colors.white : (active ? Colors.white : Colors.white54),
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isEndCall ? Colors.red : Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
