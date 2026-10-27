/// DSP Engine — Heart Rate & Blood Pressure Algorithms
///
/// Implements the three algorithms from:
/// "Heart rate and blood pressure measurement based on photoplethysmogram
///  signal using fast Fourier transform"
/// Sharma et al., Computers & Electrical Engineering, Vol. 101, 2022
///
/// Algorithm 1: Time-domain sliding-window average (baseline, ~60% error)
/// Algorithm 2: Dual-channel FFT peak detection  (proposed, ~98% accuracy)
/// Algorithm 3: Cuffless blood-pressure estimation (Chandrasekaran model)

import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
// Complex number helper
// ─────────────────────────────────────────────────────────────────────────────
class Complex {
  final double re;
  final double im;
  const Complex(this.re, this.im);

  Complex operator +(Complex o) => Complex(re + o.re, im + o.im);
  Complex operator -(Complex o) => Complex(re - o.re, im - o.im);
  Complex operator *(Complex o) =>
      Complex(re * o.re - im * o.im, re * o.im + im * o.re);

  double get magnitude => math.sqrt(re * re + im * im);

  @override
  String toString() => '($re, ${im}i)';
}

// ─────────────────────────────────────────────────────────────────────────────
// FFT Result Container
// ─────────────────────────────────────────────────────────────────────────────
class FftResult {
  /// BPM from the red channel
  final double bpmRed;

  /// BPM from the green channel
  final double bpmGreen;

  /// Fused (averaged) heart rate
  final double heartRate;

  /// Peak frequency from red channel (Hz)
  final double peakFreqRed;

  /// Peak frequency from green channel (Hz)
  final double peakFreqGreen;

  /// Magnitude spectrum for the red channel (for visualization)
  final List<double> spectrumRed;

  /// Magnitude spectrum for the green channel (for visualization)
  final List<double> spectrumGreen;

  /// Confidence metric: 0.0–1.0 (how closely the two channels agree)
  final double confidence;

  const FftResult({
    required this.bpmRed,
    required this.bpmGreen,
    required this.heartRate,
    required this.peakFreqRed,
    required this.peakFreqGreen,
    required this.spectrumRed,
    required this.spectrumGreen,
    required this.confidence,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Sliding Average Result (Algorithm 1)
// ─────────────────────────────────────────────────────────────────────────────
class SlidingAverageResult {
  /// Number of peaks detected in the 30-second window
  final int peakCount;

  /// Estimated heart rate (peaks × 2 for 30s window → BPM)
  final double heartRate;

  const SlidingAverageResult({
    required this.peakCount,
    required this.heartRate,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Blood Pressure Result (Algorithm 3)
// ─────────────────────────────────────────────────────────────────────────────
class BloodPressureResult {
  /// Systolic blood pressure (mmHg)
  final double systolic;

  /// Diastolic blood pressure (mmHg)
  final double diastolic;

  /// Pulse pressure  PP = SBP − DBP (mmHg)
  final double pulsePressure;

  /// Stroke volume (mL)
  final double strokeVolume;

  /// Left ventricular ejection time (ms)
  final double ejectionTime;

  /// Body surface area (m²)
  final double bodySurfaceArea;

  /// Clinical stage based on AHA/ACC classification
  final String stage;

  /// Color code for the stage (hex string)
  final int stageColor;

  const BloodPressureResult({
    required this.systolic,
    required this.diastolic,
    required this.pulsePressure,
    required this.strokeVolume,
    required this.ejectionTime,
    required this.bodySurfaceArea,
    required this.stage,
    required this.stageColor,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Complete measurement result
// ─────────────────────────────────────────────────────────────────────────────
class MeasurementResult {
  final FftResult fftResult;
  final SlidingAverageResult slidingResult;
  final BloodPressureResult? bpResult;
  final DateTime timestamp;
  final int totalFrames;
  final double effectiveFps;
  final double durationSeconds;

  const MeasurementResult({
    required this.fftResult,
    required this.slidingResult,
    this.bpResult,
    required this.timestamp,
    required this.totalFrames,
    required this.effectiveFps,
    required this.durationSeconds,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// DSP ENGINE
// ═════════════════════════════════════════════════════════════════════════════
class DspEngine {
  // ─── Algorithm 1: Time-Domain Sliding Window Average ──────────────────
  /// Paper Algorithm 1 (Section III-A):
  /// Uses a 4-frame rolling average over the red-channel intensity array.
  /// A state-flag counter detects rising-edge crossings.
  ///
  /// Returns: estimated BPM = peakCount × (60 / durationSeconds)
  static SlidingAverageResult algorithm1SlidingAverage(
    List<double> redSignal,
    double durationSeconds,
  ) {
    if (redSignal.length < 5) {
      return const SlidingAverageResult(peakCount: 0, heartRate: 0);
    }

    int count = 0;
    int flag = 0;

    // Paper: "Average of current and past three values"
    for (int i = 3; i < redSignal.length; i++) {
      final double avg = (redSignal[i] +
              redSignal[i - 1] +
              redSignal[i - 2] +
              redSignal[i - 3]) /
          4.0;

      if (redSignal[i] > avg && flag == 0) {
        count++;
        flag = 1;
      } else if (redSignal[i] <= avg && flag == 1) {
        flag = 0;
      }
    }

    // Paper: "The heart beat value multiplied by 2 will give the
    //         beats per minute since video is recorded for 30 sec"
    // Generalized: count × (60 / actualDuration)
    final double bpm = count * (60.0 / durationSeconds);

    return SlidingAverageResult(
      peakCount: count,
      heartRate: bpm,
    );
  }

  // ─── Algorithm 2: Dual-Channel FFT Heart Rate ─────────────────────────
  /// Paper Algorithm 2 (Section III-B):
  /// 1. Compute mean-subtracted, Hamming-windowed signals for Red and Green.
  /// 2. Zero-pad to nearest power-of-2.
  /// 3. Compute FFT; search for peak magnitude in the physiological band.
  /// 4. Average red-channel BPM and green-channel BPM.
  ///
  /// The paper states "analysis starts after 35 Hz" — this is a misprint.
  /// 35 Hz ≈ 2100 BPM which is physiologically impossible.
  /// The authors meant FFT bin index 35 (≈ 35 BPM) or ~0.58 Hz.
  /// We use a physiological bandpass of 0.66 Hz – 3.5 Hz (40–210 BPM).
  static FftResult algorithm2DualFft(
    List<double> redSignal,
    List<double> greenSignal,
    double samplingFreq,
  ) {
    final redResult = _channelFft(redSignal, samplingFreq);
    final greenResult = _channelFft(greenSignal, samplingFreq);

    // Dual-channel fusion (paper: "Average Beats = (bpmRed + bpmGreen) / 2")
    final double fusedBpm = (redResult.bpm + greenResult.bpm) / 2.0;

    // Confidence: how closely the two channels agree (1.0 = perfect agreement)
    final double maxBpm = math.max(redResult.bpm, greenResult.bpm);
    final double diff = (redResult.bpm - greenResult.bpm).abs();
    final double confidence =
        maxBpm > 0 ? (1.0 - (diff / maxBpm)).clamp(0.0, 1.0) : 0.0;

    return FftResult(
      bpmRed: redResult.bpm,
      bpmGreen: greenResult.bpm,
      heartRate: fusedBpm,
      peakFreqRed: redResult.peakFreq,
      peakFreqGreen: greenResult.peakFreq,
      spectrumRed: redResult.spectrum,
      spectrumGreen: greenResult.spectrum,
      confidence: confidence,
    );
  }

  // ─── Algorithm 3: Cuffless Blood Pressure ─────────────────────────────
  /// Paper Algorithm 3 (Section III-C):
  /// Adapted from Chandrasekaran et al. (IEEE TBME, 2013).
  ///
  /// Input:  Heart Rate (BPM), Weight (kg), Height (cm), Age (years)
  /// Output: Systolic and Diastolic Blood Pressure (mmHg)
  ///
  /// Formulas (exact from paper):
  ///   ET  = 364.5 − 1.23 × HR
  ///   BSA = 0.007184 × Weight^0.425 × Height^0.725
  ///   SV  = −6.6 + 0.25×(ET−35) − 0.62×HR + 40.4×BSA − 0.51×Age
  ///   PP  = SV / ((0.013×W − 0.007×Age − 0.004×HR) + 1.307)
  ///   SBP = 83.25 + (2/3) × PP
  ///   DBP = 83.25 − (1/3) × PP
  static BloodPressureResult algorithm3BloodPressure({
    required double heartRate,
    required double weightKg,
    required double heightCm,
    required int age,
  }) {
    // 1. Left ventricular ejection time (ms)
    final double et = 364.5 - (1.23 * heartRate);

    // 2. Body surface area — Du Bois formula (m²)
    final double bsa =
        0.007184 * math.pow(weightKg, 0.425) * math.pow(heightCm, 0.725);

    // 3. Stroke volume (mL)
    final double sv = -6.6 +
        (0.25 * (et - 35)) -
        (0.62 * heartRate) +
        (40.4 * bsa) -
        (0.51 * age);

    // 4. Pulse pressure (mmHg)
    final double ppDenom =
        (0.013 * weightKg) - (0.007 * age) - (0.004 * heartRate) + 1.307;
    final double pp = ppDenom != 0 ? sv / ppDenom : 0;

    // 5. Systolic & diastolic (mmHg)
    final double sbp = 83.25 + ((2.0 / 3.0) * pp);
    final double dbp = 83.25 - ((1.0 / 3.0) * pp);

    // 6. AHA / ACC classification
    String stage;
    int color;
    if (sbp < 120 && dbp < 80) {
      stage = 'Normal';
      color = 0xFF4CAF50; // green
    } else if (sbp < 130 && dbp < 80) {
      stage = 'Elevated';
      color = 0xFFFFC107; // amber
    } else if (sbp < 140 || dbp < 90) {
      stage = 'Hypertension Stage 1';
      color = 0xFFFF9800; // orange
    } else if (sbp >= 140 || dbp >= 90) {
      stage = 'Hypertension Stage 2';
      color = 0xFFF44336; // red
    } else {
      stage = 'Unknown';
      color = 0xFF9E9E9E;
    }

    return BloodPressureResult(
      systolic: sbp,
      diastolic: dbp,
      pulsePressure: pp,
      strokeVolume: sv,
      ejectionTime: et,
      bodySurfaceArea: bsa,
      stage: stage,
      stageColor: color,
    );
  }

  // ─── Complete measurement pipeline ────────────────────────────────────
  /// Runs all three algorithms on the captured frame buffers.
  static MeasurementResult runFullPipeline({
    required List<double> redSignal,
    required List<double> greenSignal,
    required double durationSeconds,
    double? weightKg,
    double? heightCm,
    int? age,
  }) {
    final double fps = redSignal.length / durationSeconds;

    // Algorithm 1 — baseline comparison
    final sliding = algorithm1SlidingAverage(redSignal, durationSeconds);

    // Algorithm 2 — primary method
    final fft = algorithm2DualFft(redSignal, greenSignal, fps);

    // Algorithm 3 — blood pressure (requires user profile)
    BloodPressureResult? bp;
    if (weightKg != null && heightCm != null && age != null) {
      bp = algorithm3BloodPressure(
        heartRate: fft.heartRate,
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
      );
    }

    return MeasurementResult(
      fftResult: fft,
      slidingResult: sliding,
      bpResult: bp,
      timestamp: DateTime.now(),
      totalFrames: redSignal.length,
      effectiveFps: fps,
      durationSeconds: durationSeconds,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Process a single color channel through FFT and extract peak BPM.
  static ({double bpm, double peakFreq, List<double> spectrum}) _channelFft(
    List<double> signal,
    double samplingFreq,
  ) {
    if (signal.isEmpty) {
      return (bpm: 0.0, peakFreq: 0.0, spectrum: <double>[]);
    }

    // Zero-pad to next power of 2
    int n = 1;
    while (n < signal.length) {
      n <<= 1;
    }

    // Mean subtraction (remove DC offset) + Hamming window
    final double mean = signal.reduce((a, b) => a + b) / signal.length;
    final int origLen = signal.length;

    final List<Complex> complexSignal = List<Complex>.generate(n, (i) {
      if (i < origLen) {
        // Hamming window: w(n) = 0.54 − 0.46·cos(2πn / (N−1))
        final double hamming =
            0.54 - 0.46 * math.cos(2.0 * math.pi * i / (origLen - 1));
        return Complex((signal[i] - mean) * hamming, 0.0);
      }
      return const Complex(0.0, 0.0); // zero padding
    });

    // Cooley-Tukey radix-2 FFT
    final List<Complex> spectrum = _fft(complexSignal);

    // Magnitude spectrum (only first half — Nyquist)
    final int halfN = n ~/ 2;
    final List<double> magnitudes =
        List<double>.generate(halfN, (k) => spectrum[k].magnitude);

    // Physiological bandpass: 40 BPM (0.667 Hz) to 210 BPM (3.5 Hz)
    final int minBin = (0.667 * n / samplingFreq).floor();
    final int maxBin = math.min((3.5 * n / samplingFreq).ceil(), halfN - 1);

    int peakBin = minBin;
    double maxAmp = -1.0;

    for (int k = minBin; k <= maxBin; k++) {
      if (magnitudes[k] > maxAmp) {
        maxAmp = magnitudes[k];
        peakBin = k;
      }
    }

    // Quadratic (parabolic) interpolation for sub-bin accuracy
    double peakFreq;
    if (peakBin > 0 && peakBin < halfN - 1) {
      final double alpha = magnitudes[peakBin - 1];
      final double beta = magnitudes[peakBin];
      final double gamma = magnitudes[peakBin + 1];
      final double denom = alpha - 2 * beta + gamma;
      final double delta = denom != 0 ? 0.5 * (alpha - gamma) / denom : 0;
      peakFreq = (peakBin + delta) * samplingFreq / n;
    } else {
      peakFreq = peakBin * samplingFreq / n;
    }

    final double bpm = peakFreq * 60.0;

    return (bpm: bpm, peakFreq: peakFreq, spectrum: magnitudes);
  }

  /// Cooley-Tukey radix-2 in-place FFT.
  static List<Complex> _fft(List<Complex> x) {
    final int n = x.length;
    if (n == 1) return [x[0]];

    // Bit-reversal permutation + iterative butterfly
    final List<Complex> a = List<Complex>.from(x);
    final int bits = (math.log(n) / math.ln2).round();

    for (int i = 0; i < n; i++) {
      final int j = _bitReverse(i, bits);
      if (j > i) {
        final Complex temp = a[i];
        a[i] = a[j];
        a[j] = temp;
      }
    }

    for (int len = 2; len <= n; len <<= 1) {
      final double angle = -2.0 * math.pi / len;
      final Complex wLen = Complex(math.cos(angle), math.sin(angle));
      for (int i = 0; i < n; i += len) {
        Complex w = const Complex(1.0, 0.0);
        for (int j = 0; j < len ~/ 2; j++) {
          final Complex u = a[i + j];
          final Complex v = w * a[i + j + len ~/ 2];
          a[i + j] = u + v;
          a[i + j + len ~/ 2] = u - v;
          w = w * wLen;
        }
      }
    }

    return a;
  }

  /// Reverses the lower [bits] bits of [x].
  static int _bitReverse(int x, int bits) {
    int result = 0;
    for (int i = 0; i < bits; i++) {
      result = (result << 1) | (x & 1);
      x >>= 1;
    }
    return result;
  }
}
