import 'package:cloud_firestore/cloud_firestore.dart';

class HealthRecord {
  final String uid;
  final String? bloodGroup;
  final List<String> allergies;
  final List<String> medications;
  final List<String> medicalConditions;
  final List<String> previousSurgeries;
  final List<Map<String, String>> emergencyContacts; // {name, phone}
  final String? weight;
  final String? height;
  final Timestamp updatedAt;

  HealthRecord({
    required this.uid,
    this.bloodGroup,
    List<String>? allergies,
    List<String>? medications,
    List<String>? medicalConditions,
    List<String>? previousSurgeries,
    List<Map<String, String>>? emergencyContacts,
    this.weight,
    this.height,
    Timestamp? updatedAt,
  })  : allergies = allergies ?? [],
        medications = medications ?? [],
        medicalConditions = medicalConditions ?? [],
        previousSurgeries = previousSurgeries ?? [],
        emergencyContacts = emergencyContacts ?? [],
        updatedAt = updatedAt ?? Timestamp.now();

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'bloodGroup': bloodGroup,
        'allergies': allergies,
        'medications': medications,
        'medicalConditions': medicalConditions,
        'previousSurgeries': previousSurgeries,
        'emergencyContacts': emergencyContacts,
        'weight': weight,
        'height': height,
        'updatedAt': updatedAt,
      };

  factory HealthRecord.fromMap(Map<String, dynamic> map) {
    return HealthRecord(
      uid: map['uid'] as String,
      bloodGroup: map['bloodGroup'] as String?,
      allergies: List<String>.from(map['allergies'] ?? []),
      medications: List<String>.from(map['medications'] ?? []),
      medicalConditions: List<String>.from(map['medicalConditions'] ?? []),
      previousSurgeries: List<String>.from(map['previousSurgeries'] ?? []),
      emergencyContacts: List<Map<String, String>>.from(
          map['emergencyContacts'] ?? []),
      weight: map['weight'] as String?,
      height: map['height'] as String?,
      updatedAt: map['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }
}
