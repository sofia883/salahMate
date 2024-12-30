import 'package:cloud_firestore/cloud_firestore.dart';

class QazaNamaz {
  final String? id;
  final String prayerName;
  final DateTime date;
  bool isCompleted;
  final bool isDeleted; // Add this field

  QazaNamaz({
    this.id,
    required this.prayerName,
    required this.date,
    this.isCompleted = false,
    this.isDeleted = false, // Default to false
  });

  Map<String, dynamic> toMap() => {
        'prayerName': prayerName,
        'date': date.toIso8601String(),
        'isCompleted': isCompleted,
        'isDeleted': isDeleted,
      };

  static QazaNamaz fromMap(Map<String, dynamic> map, String id) {
    return QazaNamaz(
      id: id,
      prayerName: map['prayerName'],
      date: DateTime.parse(map['date']),
      isCompleted: map['isCompleted'] ?? false,
      isDeleted: map['isDeleted'] ?? false,
    );
  }
}
