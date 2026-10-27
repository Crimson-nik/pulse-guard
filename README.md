# PulseGuard — PPG Heart Rate & Blood Pressure Monitor

> **Android 15+ (API 35)** | Flutter + Kotlin CameraX + On-Device FFT + SQLite/Drift
>
> Based on: *"Heart rate and blood pressure measurement based on photoplethysmogram signal using fast Fourier transform"*
> — Sharma et al., Computers & Electrical Engineering, Vol. 101, 2022 (Elsevier)

---

## 🚀 Setup Instructions

### Prerequisites
- **Flutter SDK** ≥ 3.16.0 (with Dart ≥ 3.2.0)
- **Android Studio** with Android SDK 35 (Android 15)
- **JDK 17** (for Gradle)
- A **physical Android device** with a rear camera + LED flash (emulators won't work for PPG)

### Step 1: Install Flutter SDK
```bash
# Download from https://docs.flutter.dev/get-started/install
# Or use FVM (Flutter Version Management)
```

### Step 2: Download Inter Font
Download the Inter font family from [Google Fonts](https://fonts.google.com/specimen/Inter) and place these files in `assets/fonts/`:
- `Inter-Regular.ttf`
- `Inter-Medium.ttf`
- `Inter-SemiBold.ttf`
- `Inter-Bold.ttf`

### Step 3: Install Dependencies
```bash
cd pulse_guard
flutter pub get
```

### Step 4: Generate Drift Code (Optional — already pre-generated)
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```
> The `app_database.g.dart` file is already provided. Only re-run this if you modify `tables.dart` or `app_database.dart`.

### Step 5: Run on Device
```bash
flutter run --release
```
> **⚠ Must use a physical device.** Camera PPG requires the rear camera and flash.

---

## 📱 How to Use

1. **Set up your Profile** (Profile tab) — Enter your Age, Height (cm), and Weight (kg). These are required for Blood Pressure estimation (Algorithm 3).

2. **Start a Measurement** (Dashboard → "Start 30s Check")
   - Place your **index finger** firmly over the **rear camera lens and LED flash**
   - The app will detect your finger and begin a **30-second recording**
   - Stay still! Watch the live PPG waveform on screen

3. **View Results** — After 30 seconds, the app automatically:
   - Runs **Algorithm 2** (Dual-channel FFT) for Heart Rate
   - Runs **Algorithm 1** (Sliding Average) for comparison
   - Runs **Algorithm 3** (Chandrasekaran model) for Blood Pressure
   - Saves everything to local SQLite database

4. **Review History** (History tab) — Browse all past readings with journal notes

---

## 🧠 Algorithms Implemented (from the Paper)

### Algorithm 1: Time-Domain Sliding Window Average
- 4-frame rolling average over red channel intensity
- State-flag peak counter on rising edge crossings
- **Paper finding: ~60% error rate** due to cardiac dicrotic wave double-counting

### Algorithm 2: Dual-Channel FFT (Primary Method)
- Mean subtraction + Hamming windowing
- Cooley-Tukey Radix-2 FFT on both Red and Green channels
- Physiological bandpass: 0.66 Hz – 3.5 Hz (40–210 BPM)
- Parabolic interpolation for sub-bin frequency accuracy
- Fusion: `HR = (bpmRed + bpmGreen) / 2`
- **Paper finding: ~98% accuracy (±2 BPM)**

### Algorithm 3: Cuffless Blood Pressure (Chandrasekaran Model)
```
ET  = 364.5 − 1.23 × HR                                    [Ejection Time, ms]
BSA = 0.007184 × W^0.425 × H^0.725                          [Body Surface Area, m²]
SV  = −6.6 + 0.25(ET−35) − 0.62×HR + 40.4×BSA − 0.51×Age   [Stroke Volume, mL]
PP  = SV / (0.013W − 0.007Age − 0.004HR + 1.307)            [Pulse Pressure, mmHg]
SBP = 83.25 + (2/3) × PP                                    [Systolic BP, mmHg]
DBP = 83.25 − (1/3) × PP                                    [Diastolic BP, mmHg]
```

---

## 🏗 Project Structure

```
pulse_guard/
├── android/
│   └── app/src/main/
│       ├── kotlin/com/pulseguard/app/
│       │   └── MainActivity.kt          ← CameraX ImageAnalysis + Torch + Platform Channels
│       ├── AndroidManifest.xml          ← Camera/Flash permissions
│       └── res/                         ← Launch theme
├── lib/
│   ├── main.dart                        ← App entry point + Provider setup
│   ├── database/
│   │   ├── tables.dart                  ← Drift table schemas
│   │   ├── app_database.dart            ← Database class + DAOs
│   │   └── app_database.g.dart          ← Generated Drift code
│   ├── services/
│   │   ├── dsp_engine.dart              ← ALL 3 ALGORITHMS (core DSP)
│   │   ├── camera_service.dart          ← Flutter ↔ Native bridge
│   │   └── measurement_provider.dart    ← State management (capture lifecycle)
│   ├── screens/
│   │   ├── dashboard_screen.dart        ← Home with latest vitals
│   │   ├── measurement_screen.dart      ← Live 30s capture + oscilloscope
│   │   ├── results_screen.dart          ← Results + algorithm comparison
│   │   ├── history_screen.dart          ← Measurement log
│   │   └── profile_screen.dart          ← Age/Height/Weight settings
│   ├── widgets/
│   │   ├── ppg_wave_painter.dart        ← Real-time waveform renderer
│   │   └── vitals_card.dart             ← Metric display cards
│   └── theme/
│       └── app_theme.dart               ← Dark healthcare design system
└── pubspec.yaml
```

---

## 📚 Academic Reference

```
@article{sharma2022heart,
  title={Heart rate and blood pressure measurement based on photoplethysmogram
         signal using fast Fourier transform},
  author={Sharma, Ashish and others},
  journal={Computers and Electrical Engineering},
  volume={101},
  pages={108086},
  year={2022},
  publisher={Elsevier}
}
```

---

## ⚠ Disclaimer

This application is built for **educational and research purposes** as part of a DSP mini-project. It is **NOT a certified medical device**. Do not use it for clinical diagnosis. Always consult a healthcare professional for medical advice.
