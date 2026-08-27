import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _database;

  // Owner email - the only person who can initially manage access
  static const String ownerEmail = 'krishnamurali20085@gmail.com';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'medly.db');
    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  static Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS db_access (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT NOT NULL UNIQUE,
          granted_by TEXT NOT NULL,
          granted_at TEXT NOT NULL
        )
      ''');
      await db.insert('db_access', {
        'email': ownerEmail,
        'granted_by': 'SYSTEM',
        'granted_at': DateTime.now().toIso8601String(),
      });
    }
    if (oldVersion < 3) {
      // Add email column to medicine_reminders if missing
      try {
        await db.execute('ALTER TABLE medicine_reminders ADD COLUMN email TEXT DEFAULT ""');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      // Family members table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS family_members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            caregiver_email TEXT NOT NULL,
            patient_name TEXT NOT NULL,
            patient_email TEXT,
            relationship TEXT DEFAULT 'Family',
            blood_group TEXT,
            allergies TEXT,
            weight TEXT,
            height TEXT,
            age TEXT,
            phone TEXT,
            added_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS family_health_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            family_member_id INTEGER NOT NULL,
            caregiver_email TEXT NOT NULL,
            date_key TEXT NOT NULL,
            blood_pressure TEXT,
            blood_sugar TEXT,
            heart_rate TEXT,
            sleep_hours TEXT,
            notes TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      // Accounts table for persistent login
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            password TEXT NOT NULL,
            role TEXT DEFAULT 'User',
            patient_name TEXT,
            blood_group TEXT,
            allergies TEXT,
            diseases TEXT,
            weight TEXT,
            height TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      // Add diseases column to accounts
      try {
        await db.execute('ALTER TABLE accounts ADD COLUMN diseases TEXT DEFAULT ""');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      // Add steps column to health_snapshots
      try {
        await db.execute('ALTER TABLE health_snapshots ADD COLUMN steps INTEGER DEFAULT 0');
      } catch (_) {}
    }
  }

  static Future<void> _createDB(Database db, int version) async {
    // Login audit table
    await db.execute('''
      CREATE TABLE login_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL,
        successful INTEGER NOT NULL DEFAULT 0,
        role TEXT,
        timestamp TEXT NOT NULL
      )
    ''');

    // Daily health snapshots
    await db.execute('''
      CREATE TABLE health_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_name TEXT NOT NULL,
        date_key TEXT NOT NULL,
        blood_pressure TEXT,
        blood_sugar TEXT,
        heart_rate TEXT,
        sleep_hours TEXT,
        steps INTEGER DEFAULT 0,
        timestamp TEXT NOT NULL
      )
    ''');

    // SOS call log
    await db.execute('''
      CREATE TABLE sos_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_name TEXT NOT NULL,
        contact_name TEXT,
        contact_phone TEXT,
        latitude REAL,
        longitude REAL,
        timestamp TEXT NOT NULL
      )
    ''');

    // SOS locations (marked with X for 4 hours)
    await db.execute('''
      CREATE TABLE sos_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        patient_name TEXT,
        timestamp TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    ''');

    // Medicine reminders
    await db.execute('''
      CREATE TABLE medicine_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT DEFAULT '',
        name TEXT NOT NULL,
        time TEXT NOT NULL,
        taken INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Database access control
    await db.execute('''
      CREATE TABLE db_access (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        granted_by TEXT NOT NULL,
        granted_at TEXT NOT NULL
      )
    ''');

    // Add owner as first entry
    await db.insert('db_access', {
      'email': ownerEmail,
      'granted_by': 'SYSTEM',
      'granted_at': DateTime.now().toIso8601String(),
    });

    // Family members (caregiver can track multiple patients)
    await db.execute('''
      CREATE TABLE family_members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        caregiver_email TEXT NOT NULL,
        patient_name TEXT NOT NULL,
        patient_email TEXT,
        relationship TEXT DEFAULT 'Family',
        blood_group TEXT,
        allergies TEXT,
        weight TEXT,
        height TEXT,
        age TEXT,
        phone TEXT,
        added_at TEXT NOT NULL
      )
    ''');

    // Family health snapshots
    await db.execute('''
      CREATE TABLE family_health_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        family_member_id INTEGER NOT NULL,
        caregiver_email TEXT NOT NULL,
        date_key TEXT NOT NULL,
        blood_pressure TEXT,
        blood_sugar TEXT,
        heart_rate TEXT,
        sleep_hours TEXT,
        notes TEXT,
        timestamp TEXT NOT NULL
      )
    ''');

    // Accounts table for persistent local login
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        password TEXT NOT NULL,
        role TEXT DEFAULT 'User',
        patient_name TEXT,        blood_group TEXT,
        allergies TEXT,
        diseases TEXT,
        weight TEXT,
        height TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }


  // ---- Account persistence (local SQLite login) ----
  static Future<void> saveAccount({
    required String email,
    required String name,
    required String password,
    String role = 'User',
    String? patientName,
    String? bloodGroup,
    String? allergies,
    String? diseases,
    String? weight,
    String? height,
  }) async {
    try {
      final db = await database;
      await db.insert('accounts', {
        'email': email.toLowerCase().trim(),
        'name': name,
        'password': password,
        'role': role,
        'patient_name': patientName,
        'blood_group': bloodGroup,
        'allergies': allergies,
        'diseases': diseases,
        'weight': weight,
        'height': height,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      print('[DB] Account saved locally: $email');
    } catch (e) {
      print('[DB] saveAccount error: $e');
    }
  }

  static Future<void> updateAccount(String email, Map<String, dynamic> updates) async {
    try {
      final db = await database;
      await db.update('accounts', updates,
        where: 'email = ?', whereArgs: [email.toLowerCase().trim()]);
      print('[DB] Account updated locally: $email');
    } catch (e) {
      print('[DB] updateAccount error: $e');
    }
  }

  static Future<Map<String, dynamic>?> getAccount(String email) async {
    try {
      final db = await database;
      final rows = await db.query('accounts',
        where: 'email = ?', whereArgs: [email.toLowerCase().trim()], limit: 1);
      return rows.isNotEmpty ? rows.first : null;
    } catch (e) {
      print('[DB] getAccount error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> loginLocal(String email, String password) async {
    try {
      final db = await database;
      final rows = await db.query('accounts',
        where: 'email = ? AND password = ?',
        whereArgs: [email.toLowerCase().trim(), password],
        limit: 1);
      return rows.isNotEmpty ? rows.first : null;
    } catch (e) {
      print('[DB] loginLocal error: $e');
      return null;
    }
  }

  // ---- Access Control ----
  static bool isOwner(String email) {
    return email.toLowerCase() == ownerEmail.toLowerCase();
  }

  static Future<bool> hasDbAccess(String email) async {
    // Owner always has access
    if (isOwner(email)) return true;

    final db = await database;
    final result = await db.query(
      'db_access',
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    return result.isNotEmpty;
  }

  static Future<List<Map<String, dynamic>>> getAuthorizedUsers() async {
    final db = await database;
    return await db.query('db_access', orderBy: 'granted_at DESC');
  }

  static Future<bool> grantAccess(String email, String grantedBy) async {
    final db = await database;
    try {
      await db.insert('db_access', {
        'email': email.toLowerCase(),
        'granted_by': grantedBy,
        'granted_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      return false; // Already exists
    }
  }

  static Future<bool> revokeAccess(String email) async {
    if (isOwner(email)) return false; // Cannot revoke owner
    final db = await database;
    final deleted = await db.delete(
      'db_access',
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    return deleted > 0;
  }

  // ---- Login Audit ----
  static Future<void> logLogin({
    required String email,
    required bool successful,
    String? role,
  }) async {
    final db = await database;
    await db.insert('login_audit', {
      'email': email,
      'successful': successful ? 1 : 0,
      'role': role,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getLoginAudit() async {
    final db = await database;
    return await db.query('login_audit', orderBy: 'timestamp DESC', limit: 50);
  }

  // ---- Health Snapshots ----
  static Future<void> saveHealthSnapshot({
    required String patientName,
    required String dateKey,
    String? bloodPressure,
    String? bloodSugar,
    String? heartRate,
    String? sleepHours,
    int? steps,
  }) async {
    final db = await database;
    final existing = await db.query(
      'health_snapshots',
      where: 'patient_name = ? AND date_key = ?',
      whereArgs: [patientName, dateKey],
    );
    final data = {
      'patient_name': patientName,
      'date_key': dateKey,
      'blood_pressure': bloodPressure,
      'blood_sugar': bloodSugar,
      'heart_rate': heartRate,
      'sleep_hours': sleepHours,
      'steps': steps ?? 0,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (existing.isNotEmpty) {
      await db.update('health_snapshots', data,
          where: 'id = ?', whereArgs: [existing.first['id']]);
    } else {
      await db.insert('health_snapshots', data);
    }
  }

  static Future<List<Map<String, dynamic>>> getHealthSnapshots(String patientName) async {
    final db = await database;
    return await db.query(
      'health_snapshots',
      where: 'patient_name = ?',
      whereArgs: [patientName],
      orderBy: 'timestamp DESC',
      limit: 30,
    );
  }

  // ---- SOS Log ----
  static Future<void> logSosCall({
    required String patientName,
    String? contactName,
    String? contactPhone,
    double? latitude,
    double? longitude,
  }) async {
    final db = await database;
    await db.insert('sos_log', {
      'patient_name': patientName,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getSosLog() async {
    final db = await database;
    return await db.query('sos_log', orderBy: 'timestamp DESC', limit: 50);
  }

  // ---- SOS Locations (marked X for 4 hours) ----
  static Future<void> markSosLocation({
    required double latitude,
    required double longitude,
    String? patientName,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 4));
    await db.insert('sos_locations', {
      'latitude': latitude,
      'longitude': longitude,
      'patient_name': patientName,
      'timestamp': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getActiveSosLocations() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.query(
      'sos_locations',
      where: 'expires_at > ?',
      whereArgs: [now],
      orderBy: 'timestamp DESC',
    );
  }

  static Future<void> cleanupExpiredSosLocations() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.delete('sos_locations', where: 'expires_at < ?', whereArgs: [now]);
  }

  // ---- Medicine Reminders ----
  static Future<void> saveMedicineReminder({
    required String email,
    required String name,
    required String time,
    bool taken = false,
  }) async {
    final db = await database;
    await db.insert('medicine_reminders', {
      'email': email,
      'name': name,
      'time': time,
      'taken': taken ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getMedicineReminders() async {
    final db = await database;
    return await db.query('medicine_reminders', orderBy: 'time ASC');
  }

  static Future<void> updateMedicineTaken(int id, bool taken) async {
    final db = await database;
    await db.update('medicine_reminders', {'taken': taken ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteMedicineReminder(int id) async {
    final db = await database;
    await db.delete('medicine_reminders', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearAllReminders() async {
    final db = await database;
    await db.delete('medicine_reminders');
  }

  // ---- Family Members ----
  static Future<int> addFamilyMember({
    required String caregiverEmail,
    required String patientName,
    String? patientEmail,
    String relationship = 'Family',
    String? bloodGroup,
    String? allergies,
    String? weight,
    String? height,
    String? age,
    String? phone,
  }) async {
    final db = await database;
    return await db.insert('family_members', {
      'caregiver_email': caregiverEmail,
      'patient_name': patientName,
      'patient_email': patientEmail,
      'relationship': relationship,
      'blood_group': bloodGroup,
      'allergies': allergies,
      'weight': weight,
      'height': height,
      'age': age,
      'phone': phone,
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getFamilyMembers(String caregiverEmail) async {
    final db = await database;
    return await db.query(
      'family_members',
      where: 'caregiver_email = ?',
      whereArgs: [caregiverEmail],
      orderBy: 'added_at DESC',
    );
  }

  static Future<void> updateFamilyMember(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('family_members', data, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteFamilyMember(int id) async {
    final db = await database;
    await db.delete('family_members', where: 'id = ?', whereArgs: [id]);
    await db.delete('family_health_snapshots', where: 'family_member_id = ?', whereArgs: [id]);
  }

  // ---- Family Health Snapshots ----
  static Future<void> saveFamilyHealthSnapshot({
    required int familyMemberId,
    required String caregiverEmail,
    required String dateKey,
    String? bloodPressure,
    String? bloodSugar,
    String? heartRate,
    String? sleepHours,
    String? notes,
  }) async {
    final db = await database;
    final existing = await db.query(
      'family_health_snapshots',
      where: 'family_member_id = ? AND date_key = ?',
      whereArgs: [familyMemberId, dateKey],
    );
    final data = {
      'family_member_id': familyMemberId,
      'caregiver_email': caregiverEmail,
      'date_key': dateKey,
      'blood_pressure': bloodPressure,
      'blood_sugar': bloodSugar,
      'heart_rate': heartRate,
      'sleep_hours': sleepHours,
      'notes': notes,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (existing.isNotEmpty) {
      await db.update('family_health_snapshots', data,
          where: 'id = ?', whereArgs: [existing.first['id']]);
    } else {
      await db.insert('family_health_snapshots', data);
    }
  }

  static Future<List<Map<String, dynamic>>> getFamilyHealthSnapshots(int familyMemberId) async {
    final db = await database;
    return await db.query(
      'family_health_snapshots',
      where: 'family_member_id = ?',
      whereArgs: [familyMemberId],
      orderBy: 'timestamp DESC',
      limit: 30,
    );
  }

  static Future<Map<String, dynamic>?> getLatestFamilyHealthSnapshot(int familyMemberId) async {
    final db = await database;
    final results = await db.query(
      'family_health_snapshots',
      where: 'family_member_id = ?',
      whereArgs: [familyMemberId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }
}
