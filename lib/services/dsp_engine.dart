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
///
/// ─────────────────────────────────────────────────────────────────────────
/// JOURNAL FIDELITY NOTES (what is exactly as printed, and what is not)
/// ─────────────────────────────────────────────────────────────────────────
/// Algorithm 1 (paper, lines 12–24 of the listing):
///   * rolling average of the last 4 frames
///   * `if current > average and flag == 0  → count++, flag = 1`
///   * `else if current <= average and flag == 1 → flag = 0`
///   * `Beats = count * 2`   (because the video is 30 s)
///   → reproduced literally below. No extra peak validation is added.
///
/// Algorithm 2 (paper, lines 13–18 of the listing):
///   * `SamplingFreq = Frames / totalTimeInSecs`
///   * `GreenFreq = FFT(GreenArray, frames, SamplingFreq)`
///   * `bpmGreen  = ceil(GreenFreq * 60)`
///   * `bpmRed    = ceil(RedFreq   * 60)`
///   * `Beats     = (bpmGreen + bpmRed) / 2`
///   → reproduced literally: `ceil(freq * 60)` is used, NOT an interpolated
///     value. Mean removal + Hamming window are pre-processing, not a change
///     of the printed formula.
///
/// Additional pre-processing that is NOT in the paper and why it is needed:
///   The paper records a 30 s *video file* and analyses it, so every frame is
///   exactly `1/Fs` apart. This app streams live frames instead, and the
///   camera drops frames whenever the analyser is busy, so the samples are
///   NOT equally spaced. `resampleUniform()` restores the paper's own
///   assumption (`T = 1/Fs`, `t = (0:L-1) * T`) before the FFT. It does not
///   change any formula — it only makes the real sampling rate equal to the
///   nominal one.
///
/// The paper says "analysis has been started after 35 Hz frequency". 35 Hz is
/// ≈ 2100 BPM, which is impossible, so this is a units misprint. The search
/// band used here is the physiological 40–210 BPM (0.667–3.5 Hz).

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
// One spectral peak (diagnostics only)
// ─────────────────────────────────────────────────────────────────────────────
class SpectralPeak {
  final double hz;
  final double magnitude;
  const SpectralPeak(this.hz, this.magnitude);

  double get bpm => hz * 60.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// FFT Result Container
// ─────────────────────────────────────────────────────────────────────────────
class FftResult {
  /// BPM from the red channel — `ceil(RedFreq * 60)` exactly as printed
  final double bpmRed;

  /// BPM from the green channel — `ceil(GreenFreq * 60)` exactly as printed
  final double bpmGreen;

  /// Fused heart rate — `(bpmGreen + bpmRed) / 2`, exactly as printed
  final double heartRate;

  /// Peaks used for the two BPM values (Hz)
  final double peakFreqRed;
  final double peakFreqGreen;

  /// Magnitude spectrum for each channel (for visualization)
  final List<double> spectrumRed;
  final List<double> spectrumGreen;

  /// Channel agreement: 1 − |bpmRed − bpmGreen| / max(bpm). This is NOT in the
  /// paper; it is only a display aid to show that the two channels disagree.
  final double confidence;

  /// Peak-to-median ratio inside the search band, per channel.
  /// A real pulse gives roughly 3–20; a flat / noise-only channel gives ≈ 1.
  /// NOT in the paper — used only to warn the user, never to alter the result.
  final double redPulseRatio;
  final double greenPulseRatio;

  /// The three strongest spectral peaks in each channel (diagnostics only).
  final List<SpectralPeak> redPeaks;
  final List<SpectralPeak> greenPeaks;

  const FftResult({
    required this.bpmRed,
    required this.bpmGreen,
    required this.heartRate,
    required this.peakFreqRed,
    required this.peakFreqGreen,
    required this.spectrumRed,
    required this.spectrumGreen,
    required this.confidence,
    this.redPulseRatio = 0,
    this.greenPulseRatio = 0,
    this.redPeaks = const <SpectralPeak>[],
    this.greenPeaks = const <SpectralPeak>[],
  });

  /// True when the green channel carried no usable pulse energy.
  bool get greenChannelFlat => greenPulseRatio < 2.0;

  /// True when the red channel carried no usable pulse energy.
  bool get redChannelFlat => redPulseRatio < 2.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sliding Average Result (Algorithm 1)
// ─────────────────────────────────────────────────────────────────────────────
class SlidingAverageResult {
  /// Number of peaks detected in the 30-second window
  final int peakCount;

  /// Heart rate — `count * 2` exactly as printed in Algorithm 1
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

  // ─── Diagnostics (display only, never feed the algorithms) ────────────
  /// Mean camera level of each channel over the recording (0–255)
  final double meanRed;
  final double meanGreen;

  /// Fraction of clipped pixels, averaged over the recording (0–1)
  final double clipRatio;

  /// Pearson correlation between the red and green sample series.
  /// ≈1.0 means the two "channels" are the same physical signal seen through
  /// two colour projections (in YUV both R and G are ~90 % luma).
  final double channelCorrelation;

  /// Decimated recorded waveforms, for the results screen graph
  final List<double> redWave;
  final List<double> greenWave;

  const MeasurementResult({
    required this.fftResult,
    required this.slidingResult,
    this.bpResult,
    required this.timestamp,
    required this.totalFrames,
    required this.effectiveFps,
    required this.durationSeconds,
    this.meanRed = 0,
    this.meanGreen = 0,
    this.clipRatio = 0,
    this.channelCorrelation = 0,
    this.redWave = const <double>[],
    this.greenWave = const <double>[],
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// DSP ENGINE
// ═════════════════════════════════════════════════════════════════════════════
class DspEngine {
  /// Search band used by Algorithm 2, in Hz (40 BPM … 210 BPM).
  static const double bandLowHz = 40.0 / 60.0;
  static const double bandHighHz = 210.0 / 60.0;

  // ─── Algorithm 1: Time-Domain Sliding Window Average ──────────────────
  /// Paper Algorithm 1 (Section III-A), reproduced line by line.
  ///
  /// Rolling average of the current and the past three samples; a rising edge
  /// past that average increments `count`; `Beats = count * 2`.
  static SlidingAverageResult algorithm1SlidingAverage(
    List<double> redSignal,
    double durationSeconds,
  ) {
    if (redSignal.length < 5) {
      return const SlidingAverageResult(peakCount: 0, heartRate: 0);
    }

    int count = 0;
    int flag = 0;

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

    // Paper: "𝐵𝑒𝑎𝑡𝑠 = 𝑐𝑜𝑢𝑛𝑡 * 2" — total peaks in the 30 s window × 2.
    final double bpm = count * 2.0;

    return SlidingAverageResult(peakCount: count, heartRate: bpm);
  }

  // ─── Algorithm 2: Dual-Channel FFT Heart Rate ─────────────────────────
  /// Paper Algorithm 2 (Section III-B), reproduced line by line.
  ///
  /// 1. `SamplingFreq = Frames / totalTimeInSecs`
  /// 2. FFT of the green average array → `bpmGreen = ceil(GreenFreq * 60)`
  /// 3. FFT of the red average array   → `bpmRed   = ceil(RedFreq   * 60)`
  /// 4. `Beats = (bpmGreen + bpmRed) / 2`
  static FftResult algorithm2DualFft(
    List<double> redSignal,
    List<double> greenSignal,
    double samplingFreq,
  ) {
    final redResult = _channelFft(redSignal, samplingFreq);
    final greenResult = _channelFft(greenSignal, samplingFreq);

    // Dual-channel fusion (paper: "Beats = (bpmGreen + bpmRed) / 2")
    final double fusedBpm = (redResult.bpm + greenResult.bpm) / 2.0;

    // Display-only agreement metric — never used to compute the heart rate.
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
      redPulseRatio: redResult.peakRatio,
      greenPulseRatio: greenResult.peakRatio,
      redPeaks: redResult.peaks,
      greenPeaks: greenResult.peaks,
    );
  }

  // ─── Algorithm 3: Cuffless Blood Pressure ─────────────────────────────
  /// Paper Algorithm 3 (Section III-C) — Eq. (3)–(8), unchanged.
  ///
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
    // Eq. (3) — left ventricular ejection time (ms)
    final double et = 364.5 - (1.23 * heartRate);

    // Eq. (4) — body surface area (m²)
    final double bsa =
        0.007184 * math.pow(weightKg, 0.425) * math.pow(heightCm, 0.725);

    // Eq. (5) — stroke volume (mL)
    final double sv = -6.6 +
        (0.25 * (et - 35)) -
        (0.62 * heartRate) +
        (40.4 * bsa) -
        (0.51 * age);

    // Eq. (6) — pulse pressure (mmHg)
    final double ppDenom =
        (0.013 * weightKg) - (0.007 * age) - (0.004 * heartRate) + 1.307;
    final double pp = ppDenom != 0 ? sv / ppDenom : 0;

    // Eq. (7) & (8)
    final double sbp = 83.25 + ((2.0 / 3.0) * pp);
    final double dbp = 83.25 - ((1.0 / 3.0) * pp);

    // Display classification only (AHA/ACC), not part of the paper.
    String stage;
    int color;
    if (sbp < 120 && dbp < 80) {
      stage = 'Normal';
      color = 0xFF4CAF50;
    } else if (sbp < 130 && dbp < 80) {
      stage = 'Elevated';
      color = 0xFFFFC107;
    } else if (sbp < 140 || dbp < 90) {
      stage = 'Hypertension Stage 1';
      color = 0xFFFF9800;
    } else if (sbp >= 140 || dbp >= 90) {
      stage = 'Hypertension Stage 2';
      color = 0xFFF44336;
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
  ///
  /// [redTimestampsNs] / [greenTimestampsNs] are the camera sensor timestamps
  /// of every frame. When supplied, the two arrays are first resampled onto an
  /// equal-spacing grid so that the paper's `SamplingFreq = Frames / Time`
  /// relationship is actually true. Pass null to use the raw arrays.
  static MeasurementResult runFullPipeline({
    required List<double> redSignal,
    required List<double> greenSignal,
    required double durationSeconds,
    List<int>? timestampsNs,
    double? weightKg,
    double? heightCm,
    int? age,
    double clipRatio = 0,
  }) {
    // ── Step 0: restore the paper's equal-spacing assumption ────────────
    List<double> red = redSignal;
    List<double> green = greenSignal;
    double duration = durationSeconds;

    if (timestampsNs != null &&
        timestampsNs.length == redSignal.length &&
        redSignal.length > 8) {
      final int t0 = timestampsNs.first;
      final double span = (timestampsNs.last - t0) / 1e9;
      if (span > 1.0) {
        // SamplingFreq = Frames / totalTimeInSecs  (paper, line 13)
        final double fs = (redSignal.length - 1) / span;
        red = resampleUniform(redSignal, timestampsNs, fs);
        green = resampleUniform(greenSignal, timestampsNs, fs);
        duration = span;
      }
    }

    final double fps = duration > 0 ? red.length / duration : 0.0;

    // Diagnostics (display only)
    final double meanRed = _mean(redSignal);
    final double meanGreen = _mean(greenSignal);
    final double corr = _pearson(red, green);

    // Algorithm 1 — baseline comparison
    final sliding = algorithm1SlidingAverage(red, duration);

    // Algorithm 2 — primary method
    final fft = algorithm2DualFft(red, green, fps);

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
      totalFrames: red.length,
      effectiveFps: fps,
      durationSeconds: duration,
      meanRed: meanRed,
      meanGreen: meanGreen,
      clipRatio: clipRatio,
      channelCorrelation: corr,
      redWave: _decimate(red, 320),
      greenWave: _decimate(green, 320),
    );
  }

  // ─── Small numeric helpers (diagnostics) ──────────────────────────────
  static double _mean(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  static double _pearson(List<double> a, List<double> b) {
    final int n = math.min(a.length, b.length);
    if (n < 4) return 0;
    final double ma = a.take(n).reduce((x, y) => x + y) / n;
    final double mb = b.take(n).reduce((x, y) => x + y) / n;
    double sab = 0, saa = 0, sbb = 0;
    for (int i = 0; i < n; i++) {
      final double da = a[i] - ma;
      final double db = b[i] - mb;
      sab += da * db;
      saa += da * da;
      sbb += db * db;
    }
    final double den = math.sqrt(saa * sbb);
    return den > 0 ? (sab / den).clamp(-1.0, 1.0) : 0;
  }

  static List<double> _decimate(List<double> v, int maxPoints) {
    if (v.length <= maxPoints) return List<double>.from(v);
    final int step = (v.length / maxPoints).ceil();
    final List<double> out = <double>[];
    for (int i = 0; i < v.length; i += step) {
      out.add(v[i]);
    }
    return out;
  }

  // ─── Uniform resampling helper ────────────────────────────────────────
  /// Linearly resamples [signal] onto a perfectly uniform grid of rate
  /// [targetFs], using the per-frame camera timestamps.
  ///
  /// The live camera does not deliver frames at a constant interval (frames
  /// are dropped while the analyser is busy). An FFT assumes equally spaced
  /// samples, so this restores exactly the assumption the paper made by
  /// analysing a 30 s video file. It does not alter any of the printed
  /// formulas — it only makes `Fs` real.
  static List<double> resampleUniform(
    List<double> signal,
    List<int> timestampsNs,
    double targetFs,
  ) {
    final int n = signal.length;
    if (n < 8 || timestampsNs.length != n || targetFs <= 0) return signal;

    final int t0 = timestampsNs.first;
    final List<double> t = List<double>.generate(
      n,
      (i) => (timestampsNs[i] - t0) / 1e9,
      growable: false,
    );

    final double span = t[n - 1] - t[0];
    if (span <= 0) return signal;

    final int m = (span * targetFs).round();
    if (m < 8 || m > 100000) return signal;

    final List<double> out = List<double>.filled(m, signal[0], growable: false);
    int j = 0;
    for (int k = 0; k < m; k++) {
      final double tk = t[0] + k / targetFs;
      while (j < n - 2 && t[j + 1] < tk) {
        j++;
      }
      final double dt = t[j + 1] - t[j];
      final double w = dt > 0 ? ((tk - t[j]) / dt).clamp(0.0, 1.0) : 0.0;
      out[k] = signal[j] + (signal[j + 1] - signal[j]) * w;
    }
    return out;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Process a single colour channel through the FFT and extract the BPM that
  /// Algorithm 2 prescribes: `ceil(freq_of_max_amplitude * 60)`.
  static ({
    double bpm,
    double peakFreq,
    List<double> spectrum,
    double peakRatio,
    List<SpectralPeak> peaks,
  }) _channelFft(
    List<double> signal,
    double samplingFreq,
  ) {
    if (signal.length < 4 || samplingFreq <= 0) {
      return (
        bpm: 0.0,
        peakFreq: 0.0,
        spectrum: <double>[],
        peakRatio: 0.0,
        peaks: const <SpectralPeak>[],
      );
    }

    // Zero-pad to next power of 2 (FFT size N in the paper's Eq. (2))
    int n = 1;
    while (n < signal.length) {
      n <<= 1;
    }

    // Mean subtraction (remove the DC component) + Hamming window
    final double mean = signal.reduce((a, b) => a + b) / signal.length;
    final int origLen = signal.length;
    final double denom = origLen > 1 ? (origLen - 1).toDouble() : 1.0;

    final List<Complex> complexSignal = List<Complex>.generate(n, (i) {
      if (i < origLen) {
        // Hamming window: w(n) = 0.54 − 0.46·cos(2πn / (N−1))
        final double hamming =
            0.54 - 0.46 * math.cos(2.0 * math.pi * i / denom);
        return Complex((signal[i] - mean) * hamming, 0.0);
      }
      return const Complex(0.0, 0.0); // zero padding
    });

    // Cooley-Tukey radix-2 FFT
    final List<Complex> spectrum = _fft(complexSignal);

    // Magnitude spectrum (first half — up to Nyquist)
    final int halfN = n ~/ 2;
    final List<double> magnitudes =
        List<double>.generate(halfN, (k) => spectrum[k].magnitude);

    // Physiological bandpass: 0.667 Hz (40 BPM) … 3.5 Hz (210 BPM)
    int minBin = (bandLowHz * n / samplingFreq).floor();
    int maxBin = (bandHighHz * n / samplingFreq).ceil();
    if (minBin < 1) minBin = 1;
    if (maxBin > halfN - 2) maxBin = halfN - 2;
    if (maxBin <= minBin) {
      return (
        bpm: 0.0,
        peakFreq: 0.0,
        spectrum: <double>[],
        peakRatio: 0.0,
        peaks: const <SpectralPeak>[],
      );
    }

    int peakBin = minBin;
    double maxAmp = -1.0;
    final List<double> band = <double>[];

    for (int k = minBin; k <= maxBin; k++) {
      band.add(magnitudes[k]);
      if (magnitudes[k] > maxAmp) {
        maxAmp = magnitudes[k];
        peakBin = k;
      }
    }

    // Peak frequency — Eq. (2) of the paper: f = k · Fs / N
    final double peakFreq = peakBin * samplingFreq / n;

    // Paper: 𝑏𝑝𝑚 = ceil(𝑓𝑟𝑒𝑞 × 60)
    final double bpm = (peakFreq * 60.0).ceilToDouble();

    // Display-only: how far the peak stands above the band's median noise.
    band.sort();
    final double median = band[band.length ~/ 2];
    final double peakRatio = median > 0 ? maxAmp / median : 0.0;

    // Display-only: the three strongest local maxima inside the band, so a
    // wrong reading can be traced to a specific interfering frequency.
    final List<SpectralPeak> peaks = <SpectralPeak>[];
    for (int k = minBin + 1; k < maxBin; k++) {
      final double m = magnitudes[k];
      if (m > magnitudes[k - 1] && m >= magnitudes[k + 1]) {
        peaks.add(SpectralPeak(k * samplingFreq / n, m));
      }
    }
    peaks.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    final List<SpectralPeak> topPeaks =
        peaks.length > 3 ? peaks.sublist(0, 3) : peaks;

    return (
      bpm: bpm,
      peakFreq: peakFreq,
      // Display slice: only the 40–210 BPM search band, so the pulse peak is
      // not crushed by the near-DC bins when the graph auto-scales.
      spectrum: magnitudes.sublist(minBin, maxBin + 1),
      peakRatio: peakRatio,
      peaks: topPeaks,
    );
  }

  /// Cooley-Tukey radix-2 in-place FFT.
  static List<Complex> _fft(List<Complex> x) {
    final int n = x.length;
    if (n == 1) return [x[0]];

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
