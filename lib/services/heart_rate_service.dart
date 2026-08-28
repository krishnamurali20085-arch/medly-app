import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Heart Rate Monitor using camera torch PPG (Photoplethysmography).
///
/// The technique works by:
/// 1. Turning ON the flashlight to illuminate the fingertip
/// 2. The camera detects subtle brightness changes as blood pulses
/// 3. Signal processing extracts the heart rate from these changes
class HeartRateService {
  // Signal processing
  final List<double> _redValues = [];
  final List<double> _greenValues = [];
  final List<double> _blueValues = [];

  // Timing
  DateTime? _startTime;
  Timer? _processingTimer;

  // State
  bool _isMeasuring = false;
  double _currentBpm = 0;
  int _sampleCount = 0;

  // Callbacks
  Function(double bpm)? onBpmUpdated;
  Function(String error)? onError;
  Function()? onMeasurementComplete;

  bool get isMeasuring => _isMeasuring;
  double get currentBpm => _currentBpm;
  int get sampleCount => _sampleCount;

  /// Start measuring - call this when camera frames arrive
  void startMeasuring() {
    _redValues.clear();
    _greenValues.clear();
    _blueValues.clear();
    _startTime = DateTime.now();
    _sampleCount = 0;
    _currentBpm = 0;
    _isMeasuring = true;
  }

  /// Process a camera frame - extract RGB values from the center region
  void processFrame(double red, double green, double blue) {
    if (!_isMeasuring) return;

    _redValues.add(red);
    _greenValues.add(green);
    _blueValues.add(blue);
    _sampleCount++;

    // Need at least 3 seconds of data to calculate BPM
    final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
    if (elapsed < 3000) return;

    // Calculate BPM every second after initial 3 seconds
    if (_sampleCount % 30 == 0) {
      _calculateBpm();
    }
  }

  /// Calculate BPM from the collected signal using peak detection
  void _calculateBpm() {
    if (_redValues.length < 30) return;

    // Use green channel (most sensitive to blood volume changes)
    final signal = List<double>.from(_greenValues);

    // Apply bandpass filter (0.75Hz - 3Hz = 45-180 BPM range)
    final filtered = _bandpassFilter(signal, 30.0); // ~30 fps assumed

    // Find peaks
    final peaks = _findPeaks(filtered);

    if (peaks.length >= 2) {
      // Calculate average interval between peaks
      double totalInterval = 0;
      for (int i = 1; i < peaks.length; i++) {
        totalInterval += peaks[i] - peaks[i - 1];
      }
      final avgInterval = totalInterval / (peaks.length - 1);

      if (avgInterval > 0) {
        // Convert to BPM (assuming ~30 fps sample rate)
        final fps = _sampleCount / (_startTime != null
            ? DateTime.now().difference(_startTime!).inSeconds.clamp(1, 999)
            : 30);
        _currentBpm = (60.0 * fps / avgInterval).clamp(30, 220);

        // Smooth the reading
        _currentBpm = double.parse(_currentBpm.toStringAsFixed(0));

        onBpmUpdated?.call(_currentBpm);
      }
    }
  }

  /// Simple bandpass filter to isolate heart rate frequencies
  List<double> _bandpassFilter(List<double> signal, double sampleRate) {
    if (signal.length < 10) return signal;

    // Remove DC offset (subtract mean)
    final mean = signal.reduce((a, b) => a + b) / signal.length;
    final centered = signal.map((v) => v - mean).toList();

    // Simple moving average to smooth
    final smoothed = <double>[];
    final windowSize = max(2, (sampleRate * 0.1).toInt());
    for (int i = 0; i < centered.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = max(0, i - windowSize); j <= min(centered.length - 1, i + windowSize); j++) {
        sum += centered[j];
        count++;
      }
      smoothed.add(sum / count);
    }

    // Differentiate to find peaks better
    final differentiated = <double>[];
    for (int i = 1; i < smoothed.length; i++) {
      differentiated.add(smoothed[i] - smoothed[i - 1]);
    }

    return differentiated;
  }

  /// Find peaks in the signal
  List<int> _findPeaks(List<double> signal) {
    if (signal.length < 5) return [];

    final peaks = <int>[];
    final threshold = _calculateThreshold(signal);

    for (int i = 2; i < signal.length - 2; i++) {
      if (signal[i] > signal[i - 1] &&
          signal[i] > signal[i - 2] &&
          signal[i] > signal[i + 1] &&
          signal[i] > signal[i + 2] &&
          signal[i] > threshold) {
        // Ensure minimum distance between peaks (0.5s = ~15 samples at 30fps)
        if (peaks.isEmpty || (i - peaks.last) > 15) {
          peaks.add(i);
        }
      }
    }

    return peaks;
  }

  /// Calculate adaptive threshold for peak detection
  double _calculateThreshold(List<double> signal) {
    if (signal.isEmpty) return 0;
    final sorted = List<double>.from(signal)..sort();
    // Use 60th percentile as threshold
    final index = (sorted.length * 0.6).toInt().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  /// Stop measuring
  void stopMeasuring() {
    _isMeasuring = false;
    _processingTimer?.cancel();
    _processingTimer = null;

    // Final BPM calculation
    if (_redValues.length >= 30) {
      _calculateBpm();
    }

    onMeasurementComplete?.call();
  }

  /// Dispose resources
  void dispose() {
    stopMeasuring();
    _redValues.clear();
    _greenValues.clear();
    _blueValues.clear();
  }

  /// Get BPM category label
  static String getBpmCategory(double bpm) {
    if (bpm < 40) return 'Very Low';
    if (bpm < 60) return 'Low (Bradycardia)';
    if (bpm < 100) return 'Normal';
    if (bpm < 120) return 'Elevated';
    if (bpm < 140) return 'High';
    return 'Very High';
  }

  /// Get BPM category color
  static Color getBpmColor(double bpm) {
    if (bpm < 40) return Colors.blue;
    if (bpm < 60) return Colors.orange;
    if (bpm < 100) return Colors.green;
    if (bpm < 120) return Colors.yellow.shade700;
    if (bpm < 140) return Colors.orange.shade700;
    return Colors.red;
  }

  /// Get advice based on BPM
  static String getBpmAdvice(double bpm) {
    if (bpm < 40) return 'Very low heart rate detected. If you are not an athlete, this may require medical attention.';
    if (bpm < 60) return 'Slightly low heart rate. This is normal for athletes and active individuals.';
    if (bpm < 100) return 'Your heart rate is in the normal resting range. Great job!';
    if (bpm < 120) return 'Slightly elevated. This can happen after physical activity or stress.';
    if (bpm < 140) return 'Heart rate is high. Try to relax and breathe deeply. Rest for a few minutes.';
    return 'Heart rate is very high. If you are at rest, please sit down and try to relax. Seek medical help if it persists.';
  }

  /// Calculate BMI from weight (kg) and height (cm)
  static Map<String, dynamic> calculateBMI(String weightStr, String heightStr) {
    final weight = double.tryParse(weightStr);
    final height = double.tryParse(heightStr);

    if (weight == null || height == null || weight <= 0 || height <= 0) {
      return {
        'bmi': 0.0,
        'category': 'Unknown',
        'color': Colors.grey,
        'advice': 'Enter your weight and height to calculate BMI.',
      };
    }

    // Convert height from cm to meters
    final heightM = height / 100;
    final bmi = weight / (heightM * heightM);

    String category;
    Color color;
    String advice;

    if (bmi < 16) {
      category = 'Severe Underweight';
      color = Colors.blue;
      advice = 'Your BMI indicates severe underweight. Please consult a doctor for nutritional guidance.';
    } else if (bmi < 18.5) {
      category = 'Underweight';
      color = Colors.orange;
      advice = 'You are underweight. Consider increasing calorie intake with nutritious foods.';
    } else if (bmi < 23) {
      category = 'Normal';
      color = Colors.green;
      advice = 'Your BMI is in the healthy range. Keep maintaining a balanced diet and regular exercise!';
    } else if (bmi < 25) {
      category = 'Slightly Overweight';
      color = Colors.yellow.shade700;
      advice = 'You are slightly above the normal range. A healthy diet and exercise can help.';
    } else if (bmi < 30) {
      category = 'Overweight';
      color = Colors.orange;
      advice = 'You are overweight. Regular physical activity and a balanced diet are recommended.';
    } else if (bmi < 35) {
      category = 'Obese (Class I)';
      color = Colors.deepOrange;
      advice = 'You fall in the obese category. Please consider consulting a healthcare professional.';
    } else if (bmi < 40) {
      category = 'Obese (Class II)';
      color = Colors.red.shade700;
      advice = 'You are in Class II obesity. Medical guidance is strongly recommended.';
    } else {
      category = 'Obese (Class III)';
      color = Colors.red.shade900;
      advice = 'You are in the highest obesity category. Please seek medical advice urgently.';
    }

    return {
      'bmi': double.parse(bmi.toStringAsFixed(1)),
      'category': category,
      'color': color,
      'advice': advice,
    };
  }
}
