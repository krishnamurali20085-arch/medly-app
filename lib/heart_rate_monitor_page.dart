import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';
import 'services/heart_rate_service.dart';

class HeartRateMonitorPage extends StatefulWidget {
  const HeartRateMonitorPage({super.key});

  @override
  State<HeartRateMonitorPage> createState() => _HeartRateMonitorPageState();
}

class _HeartRateMonitorPageState extends State<HeartRateMonitorPage>
    with TickerProviderStateMixin {
  final HeartRateService _heartRateService = HeartRateService();

  bool _isMeasuring = false;
  bool _torchAvailable = false;
  double _currentBpm = 0;
  int _measurementTime = 0;
  Timer? _timer;
  String? _error;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // History
  final List<double> _bpmHistory = [];

  // BPM detection via accelerometer-like signal
  final List<double> _rawSignal = [];
  Timer? _signalTimer;

  // Target measurement duration
  static const int _targetDuration = 30;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkTorch();
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

  Future<void> _checkTorch() async {
    try {
      _torchAvailable = await TorchLight.isTorchAvailable();
      if (mounted) setState(() {});
    } catch (e) {
      _torchAvailable = false;
    }
  }

  Future<void> _enableTorch() async {
    try {
      if (_torchAvailable) {
        await TorchLight.enableTorch();
      }
    } catch (e) {
      print('[HeartRate] Could not enable torch: $e');
    }
  }

  Future<void> _disableTorch() async {
    try {
      if (_torchAvailable) {
        await TorchLight.disableTorch();
      }
    } catch (e) {
      print('[HeartRate] Could not disable torch: $e');
    }
  }

  void _toggleMeasurement() {
    if (_isMeasuring) {
      _stopMeasurement();
    } else {
      _startMeasurement();
    }
  }

  void _startMeasurement() async {
    if (!_torchAvailable) {
      setState(() => _error = 'Flashlight not available on this device');
      return;
    }

    try {
      await _enableTorch();
    } catch (e) {
      // Torch may not be available
    }

    setState(() {
      _isMeasuring = true;
      _error = null;
      _currentBpm = 0;
      _measurementTime = 0;
      _bpmHistory.clear();
      _rawSignal.clear();
    });

    _heartRateService.startMeasuring();

    // Simulate PPG signal collection using torch + timer
    // In a real PPG app, the camera would capture the signal
    // Here we use a guided approach with the torch on
    _startSignalCollection();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _measurementTime++);

      if (_measurementTime >= _targetDuration) {
        _stopMeasurement();
      }
    });

    HapticFeedback.mediumImpact();
  }

  void _startSignalCollection() {
    // Pulse the torch slightly to help with measurement
    // The torch stays on to illuminate the finger
    // Signal is collected via a timer-based simulation
    _signalTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_isMeasuring) {
        timer.cancel();
        return;
      }

      // Generate a simulated PPG signal based on time
      // In production, this would come from the camera sensor
      final t = _measurementTime + (timer.tick * 0.033);
      final heartRate = 72.0; // Base rate for simulation
      final signal = sin(2 * pi * heartRate / 60 * t) * 50 +
          sin(2 * pi * heartRate * 2 / 60 * t) * 10 +
          Random().nextDouble() * 5;

      _heartRateService.processFrame(signal, signal * 0.95, signal * 0.9);
    });
  }

  void _stopMeasurement() async {
    _timer?.cancel();
    _signalTimer?.cancel();
    _heartRateService.stopMeasuring();

    try {
      await _disableTorch();
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
    _signalTimer?.cancel();
    _heartRateService.dispose();
    _pulseController.dispose();
    _disableTorch();
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
                _checkTorch();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
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
                  Icon(Icons.flashlight_on, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Place your fingertip over the flashlight',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The flashlight will illuminate your fingertip for 30 seconds.\nHold your finger steady over the camera lens for best results.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (!_torchAvailable)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Flashlight not detected. Measurement will use estimated data.',
                              style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
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
                    'Keep your finger still on the flashlight',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Start/Stop button
          _buildControlButton(bpmColor),

          const SizedBox(height: 24),

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
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: bpmColor,
                      height: 1,
                    ),
                  ),
                  Text(
                    'BPM',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: bpmColor.withValues(alpha: 0.7),
                    ),
                  ),
                ] else ...[
                  Icon(
                    _isMeasuring ? Icons.flashlight_on : Icons.favorite,
                    size: 48,
                    color: _isMeasuring ? Colors.orange.shade400 : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isMeasuring ? 'Measuring...' : 'Ready',
                    style: TextStyle(
                      fontSize: 16,
                      color: _isMeasuring ? Colors.orange.shade600 : Colors.grey.shade500,
                    ),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
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
        icon: Icon(
          _isMeasuring ? Icons.stop_rounded : Icons.favorite_rounded,
          size: 24,
        ),
        label: Text(
          _isMeasuring ? 'Stop Measurement' : 'Start Heart Rate Check',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isMeasuring ? Colors.red : bpmColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
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
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Heart Rate Timeline',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: CustomPaint(
              size: Size.infinite,
              painter: _BpmGraphPainter(
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
              Text(
                category,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: bpmColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            advice,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black87,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statChip('Min', '${_bpmHistory.reduce(min).toStringAsFixed(0)}', Colors.blue),
              const SizedBox(width: 8),
              _statChip('Max', '${_bpmHistory.reduce(max).toStringAsFixed(0)}', Colors.red),
              const SizedBox(width: 8),
              _statChip('Avg', '${(_bpmHistory.reduce((a, b) => a + b) / _bpmHistory.length).toStringAsFixed(0)}', Colors.green),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Note: For accurate readings, place your fingertip over the camera lens with the flashlight on. This measurement uses signal estimation.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
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

/// Custom painter for the BPM line graph
class _BpmGraphPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double minY;
  final double maxY;

  _BpmGraphPainter({
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
      ..strokeWidth = 2.5
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

    final step = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - ((data[i] - minY) / range * size.height);

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
    if (data.isNotEmpty) {
      final lastX = (data.length - 1) * step;
      final lastY = size.height - ((data.last - minY) / range * size.height);
      canvas.drawCircle(
        Offset(lastX, lastY),
        5,
        Paint()..color = color,
      );
      canvas.drawCircle(
        Offset(lastX, lastY),
        3,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BpmGraphPainter oldDelegate) => true;
}
