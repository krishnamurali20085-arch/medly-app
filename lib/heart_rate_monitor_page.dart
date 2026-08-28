import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'services/heart_rate_service.dart';

class HeartRateMonitorPage extends StatefulWidget {
  const HeartRateMonitorPage({super.key});

  @override
  State<HeartRateMonitorPage> createState() => _HeartRateMonitorPageState();
}

class _HeartRateMonitorPageState extends State<HeartRateMonitorPage>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  final HeartRateService _heartRateService = HeartRateService();

  bool _isMeasuring = false;
  bool _cameraInitialized = false;
  double _currentBpm = 0;
  int _measurementTime = 0;
  Timer? _timer;
  String? _error;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // History
  final List<double> _bpmHistory = [];
  final List<double> _rawGreenSignal = [];

  // Target measurement duration
  static const int _targetDuration = 30;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCamera();
    _heartRateService.onBpmUpdated = (bpm) {
      if (mounted) {
        setState(() {
          _currentBpm = bpm;
          _bpmHistory.add(bpm);
        });
        _updatePulseAnimation();
      }
    };
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _updatePulseAnimation() {
    if (_currentBpm > 0) {
      final period = (60000 / _currentBpm).toInt();
      _pulseController.stop();
      _pulseController.duration = Duration(milliseconds: period.clamp(300, 2000));
      _pulseController.repeat(reverse: true);
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device');
        return;
      }

      // Use the back camera (where the torch is)
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.low, // Low res for fast processing
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _cameraInitialized = true);
      }
    } catch (e) {
      setState(() => _error = 'Camera initialization failed: $e');
    }
  }

  void _startImageStream() {
    _cameraController?.startImageStream((CameraImage image) {
      if (!_heartRateService.isMeasuring) return;

      final planes = image.planes;
      if (planes.isEmpty) return;

      // YUV420 format: Y plane is the luminance
      // For PPG, we use the average brightness of the center region
      final yPlane = planes[0].bytes;
      final width = image.width;
      final height = image.height;

      // Sample center 40% of the frame (where fingertip should be)
      final startX = (width * 0.3).toInt();
      final endX = (width * 0.7).toInt();
      final startY = (height * 0.3).toInt();
      final endY = (height * 0.7).toInt();

      double sum = 0;
      int count = 0;

      // Sample every 3rd pixel for speed
      for (int y = startY; y < endY; y += 3) {
        for (int x = startX; x < endX; x += 3) {
          final index = y * width + x;
          if (index < yPlane.length) {
            sum += yPlane[index];
            count++;
          }
        }
      }

      if (count > 0) {
        final avgBrightness = sum / count;
        _rawGreenSignal.add(avgBrightness);

        // Keep signal buffer manageable (last 300 samples ~ 10 seconds at 30fps)
        if (_rawGreenSignal.length > 300) {
          _rawGreenSignal.removeAt(0);
        }

        // Feed to heart rate service (use brightness as all channels for YUV)
        _heartRateService.processFrame(avgBrightness, avgBrightness, avgBrightness);
      }
    });
  }

  void _stopImageStream() {
    _cameraController?.stopImageStream();
  }

  void _toggleMeasurement() {
    if (_isMeasuring) {
      _stopMeasurement();
    } else {
      _startMeasurement();
    }
  }

  void _startMeasurement() async {
    if (!_cameraInitialized || _cameraController == null) {
      setState(() => _error = 'Camera not ready. Please restart the app.');
      return;
    }

    try {
      // Enable torch to illuminate the fingertip
      await _cameraController!.setFlashMode(FlashMode.torch);

      setState(() {
        _isMeasuring = true;
        _error = null;
        _currentBpm = 0;
        _measurementTime = 0;
        _bpmHistory.clear();
        _rawGreenSignal.clear();
      });

      _heartRateService.startMeasuring();

      // Start camera image stream for PPG signal
      _startImageStream();

      // Start timer
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => _measurementTime++);

        if (_measurementTime >= _targetDuration) {
          _stopMeasurement();
        }
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() => _error = 'Could not start measurement: $e');
    }
  }

  void _stopMeasurement() async {
    _timer?.cancel();
    _heartRateService.stopMeasuring();

    try {
      _stopImageStream();
      await _cameraController?.setFlashMode(FlashMode.off);
    } catch (_) {}

    _pulseController.stop();

    if (mounted) {
      setState(() => _isMeasuring = false);
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heartRateService.dispose();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart Rate Monitor'),
        backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
      ),
      body: _error != null
          ? _buildErrorView()
          : !_cameraInitialized
              ? _buildLoadingView()
              : _buildMainView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _error = null);
                _initCamera();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initializing camera...'),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _measurementTime / _targetDuration;
    final bpmColor = HeartRateService.getBpmColor(_currentBpm);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Camera preview with finger overlay
          if (_isMeasuring) ...[
            _buildCameraPreview(),
            const SizedBox(height: 16),
          ],

          // Instructions
          if (!_isMeasuring && _currentBpm == 0) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.fingerprint, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Place your fingertip over the camera lens',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The flashlight will illuminate your fingertip. The camera detects blood volume changes (rPPG) to measure your heart rate.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _instructionStep('1', 'Cover camera'),
                      const SizedBox(width: 12),
                      _instructionStep('2', 'Flashlight on'),
                      const SizedBox(width: 12),
                      _instructionStep('3', 'Stay still'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // BPM Display
          _buildBpmDisplay(bpmColor, isDark),

          const SizedBox(height: 24),

          // Measurement progress
          if (_isMeasuring) ...[
            _buildProgressRing(progress, bpmColor),
            const SizedBox(height: 16),
            Text(
              '$_measurementTime / $_targetDuration seconds',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Keep your finger still on the camera',
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Start/Stop button
          _buildControlButton(bpmColor),

          const SizedBox(height: 24),

          // Raw PPG signal graph
          if (_rawGreenSignal.length > 10 && !_isMeasuring) ...[
            _buildRawSignalGraph(bpmColor, isDark),
            const SizedBox(height: 16),
          ],

          // BPM History graph
          if (_bpmHistory.isNotEmpty) ...[
            _buildHistoryGraph(bpmColor, isDark),
            const SizedBox(height: 20),
          ],

          // Result card
          if (!_isMeasuring && _currentBpm > 0) ...[
            _buildResultCard(bpmColor, isDark),
          ],
        ],
      ),
    );
  }

  Widget _instructionStep(String number, String label) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.red.shade400,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera preview (mirrored to show finger placement)
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(-1.0, 1.0),
            child: CameraPreview(_cameraController!),
          ),
          // Finger placement guide
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
            ),
          ),
          // Label
          Positioned(
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Place finger here',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBpmDisplay(Color bpmColor, bool isDark) {
    return AnimatedBuilder(
      animation: _isMeasuring ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
      builder: (context, child) {
        return Transform.scale(
          scale: _isMeasuring ? _pulseAnimation.value : 1.0,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  bpmColor.withValues(alpha: 0.1),
                  bpmColor.withValues(alpha: 0.3),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: bpmColor.withValues(alpha: _isMeasuring ? 0.4 : 0.15),
                  blurRadius: _isMeasuring ? 30 : 15,
                  spreadRadius: _isMeasuring ? 5 : 0,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_currentBpm > 0) ...[
                  Text(
                    _currentBpm.toStringAsFixed(0),
                    style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: bpmColor, height: 1),
                  ),
                  Text(
                    'BPM',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bpmColor.withValues(alpha: 0.7)),
                  ),
                ] else ...[
                  Icon(
                    _isMeasuring ? Icons.favorite : Icons.favorite_border,
                    size: 48,
                    color: _isMeasuring ? Colors.red.shade300 : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isMeasuring ? 'Detecting...' : 'Ready',
                    style: TextStyle(fontSize: 16, color: _isMeasuring ? Colors.red.shade400 : Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressRing(double progress, Color color) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 5,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Center(
            child: Text(
              '${(_targetDuration - _measurementTime)}s',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(Color bpmColor) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _toggleMeasurement,
        icon: Icon(_isMeasuring ? Icons.stop_rounded : Icons.favorite_rounded, size: 24),
        label: Text(
          _isMeasuring ? 'Stop Measurement' : 'Start Heart Rate Check',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isMeasuring ? Colors.red : bpmColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildRawSignalGraph(Color color, bool isDark) {
    final signal = _rawGreenSignal;
    if (signal.length < 10) return const SizedBox.shrink();

    final minY = signal.reduce(min);
    final maxY = signal.reduce(max);
    final range = maxY - minY;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, size: 16, color: color),
              const SizedBox(width: 6),
              const Text('Raw PPG Signal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SignalGraphPainter(
                data: signal,
                color: color,
                minY: range > 0 ? minY - 2 : minY,
                maxY: range > 0 ? maxY + 2 : maxY + 5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryGraph(Color bpmColor, bool isDark) {
    if (_bpmHistory.length < 2) return const SizedBox.shrink();

    final minY = _bpmHistory.reduce(min).clamp(30.0, 220.0);
    final maxY = _bpmHistory.reduce(max).clamp(30.0, 220.0);
    final range = maxY - minY;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline, size: 16, color: bpmColor),
              const SizedBox(width: 6),
              const Text('Heart Rate Timeline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SignalGraphPainter(
                data: _bpmHistory,
                color: bpmColor,
                minY: range > 0 ? minY - 5 : minY,
                maxY: range > 0 ? maxY + 5 : maxY + 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Color bpmColor, bool isDark) {
    final category = HeartRateService.getBpmCategory(_currentBpm);
    final advice = HeartRateService.getBpmAdvice(_currentBpm);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bpmColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bpmColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: bpmColor, size: 20),
              const SizedBox(width: 8),
              Text(category, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: bpmColor)),
            ],
          ),
          const SizedBox(height: 12),
          Text(advice, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87, height: 1.4)),
          const SizedBox(height: 16),
          Row(
            children: [
              _statChip('Min', '${_bpmHistory.reduce(min).toStringAsFixed(0)}', Colors.blue),
              const SizedBox(width: 8),
              _statChip('Max', '${_bpmHistory.reduce(max).toStringAsFixed(0)}', Colors.red),
              const SizedBox(width: 8),
              _statChip('Avg', '${(_bpmHistory.reduce((a, b) => a + b) / _bpmHistory.length).toStringAsFixed(0)}', Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: color)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for both raw signal and BPM graphs
class _SignalGraphPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double minY;
  final double maxY;

  _SignalGraphPainter({
    required this.data,
    required this.color,
    required this.minY,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();
    final range = maxY - minY;

    // Use last 200 points max for display
    final displayData = data.length > 200 ? data.sublist(data.length - 200) : data;
    final step = size.width / (displayData.length - 1);

    for (int i = 0; i < displayData.length; i++) {
      final x = i * step;
      final y = size.height - ((displayData[i] - minY) / range * size.height).clamp(0.0, size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw last point as a dot
    if (displayData.isNotEmpty) {
      final lastX = (displayData.length - 1) * step;
      final lastY = size.height - ((displayData.last - minY) / range * size.height).clamp(0.0, size.height);
      canvas.drawCircle(Offset(lastX, lastY), 5, Paint()..color = color);
      canvas.drawCircle(Offset(lastX, lastY), 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalGraphPainter oldDelegate) => true;
}
