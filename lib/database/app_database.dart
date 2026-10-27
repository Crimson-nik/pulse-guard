/// App Database — Drift database definition and DAOs
///
/// Uses Drift's code-generation for type-safe SQLite access.
/// All data stays on-device (no cloud, no account required).

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [UserProfiles, Measurements])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ─── User Profile Operations ──────────────────────────────────────────

  /// Get the current user profile (there's always exactly one).
  Future<UserProfile?> getUserProfile() async {
    return (select(userProfiles)..limit(1)).getSingleOrNull();
  }

  /// Insert or update the user profile.
  Future<void> saveUserProfile({
    required String name,
    required int age,
    required double heightCm,
    required double weightKg,
  }) async {
    final existing = await getUserProfile();
    if (existing != null) {
      await (update(userProfiles)..where((t) => t.id.equals(existing.id)))
          .write(UserProfilesCompanion(
        name: Value(name),
        age: Value(age),
        heightCm: Value(heightCm),
        weightKg: Value(weightKg),
        updatedAt: Value(DateTime.now()),
      ));
    } else {
      await into(userProfiles).insert(UserProfilesCompanion(
        name: Value(name),
        age: Value(age),
        heightCm: Value(heightCm),
        weightKg: Value(weightKg),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  // ─── Measurement Operations ───────────────────────────────────────────

  /// Insert a new measurement.
  Future<int> insertMeasurement(MeasurementsCompanion entry) {
    return into(measurements).insert(entry);
  }

  /// Get all measurements, newest first.
  Future<List<Measurement>> getAllMeasurements() {
    return (select(measurements)
          ..orderBy(
              [(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get the latest N measurements.
  Future<List<Measurement>> getRecentMeasurements(int count) {
    return (select(measurements)
          ..orderBy(
              [(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)])
          ..limit(count))
        .get();
  }

  /// Watch measurements as a reactive stream.
  Stream<List<Measurement>> watchAllMeasurements() {
    return (select(measurements)
          ..orderBy(
              [(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Delete a measurement by ID.
  Future<int> deleteMeasurement(int id) {
    return (delete(measurements)..where((t) => t.id.equals(id))).go();
  }

  /// Update notes on a measurement.
  Future<void> updateMeasurementNotes(int id, String notes) {
    return (update(measurements)..where((t) => t.id.equals(id)))
        .write(MeasurementsCompanion(notes: Value(notes)));
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'pulse_guard.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
