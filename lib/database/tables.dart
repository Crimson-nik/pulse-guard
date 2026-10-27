/// Database Schema — Drift (SQLite) tables
///
/// Stores measurement history and user profile locally.
/// Zero network dependency; fully offline.

import 'package:drift/drift.dart';

// ─────────────────────────────────────────────────────────────────────────────
// User profile table
// ─────────────────────────────────────────────────────────────────────────────
class UserProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant('User'))();
  IntColumn get age => integer()();
  RealColumn get heightCm => real()();
  RealColumn get weightKg => real()();
  DateTimeColumn get updatedAt => dateTime()();
}

// ─────────────────────────────────────────────────────────────────────────────
// Measurement history table
// ─────────────────────────────────────────────────────────────────────────────
class Measurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime()();

  // Algorithm 2 results (primary)
  RealColumn get heartRateFft => real()();
  RealColumn get bpmRed => real()();
  RealColumn get bpmGreen => real()();
  RealColumn get confidence => real()();

  // Algorithm 1 results (baseline comparison)
  RealColumn get heartRateSliding => real()();

  // Algorithm 3 results (blood pressure)
  RealColumn get systolic => real().nullable()();
  RealColumn get diastolic => real().nullable()();
  RealColumn get pulsePressure => real().nullable()();
  RealColumn get strokeVolume => real().nullable()();
  TextColumn get bpStage => text().nullable()();

  // Measurement metadata
  IntColumn get totalFrames => integer()();
  RealColumn get effectiveFps => real()();
  RealColumn get durationSeconds => real()();

  // User journal
  TextColumn get notes => text().nullable()();
}
