import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'package:flutter/material.dart';
import 'bulk_prayers.dart';

class PrayerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Update the collection references to include the user ID
  CollectionReference get _prayersCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('prayers');
  }

  CollectionReference get _historyCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('history');
  }

  Future<void> deleteFromHistory(String prayerId) async {
    try {
      await _historyCollection.doc(prayerId).update({'isDeleted': true});
    } catch (e) {
      throw Exception('Failed to mark prayer as deleted: $e');
    }
  }

  Future<void> clearAllHistory() async {
    final snapshot =
        await _historyCollection.where('isDeleted', isEqualTo: false).get();

    WriteBatch batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'isDeleted': true});
    }
    await batch.commit();
  }

  // Get only non-deleted history
  Stream<List<QazaNamaz>> getHistory() {
    return _historyCollection
        .where('isDeleted', isEqualTo: false) // Only get non-deleted items
        .snapshots()
        .map((snapshot) {
      final allPrayers = snapshot.docs.map((doc) {
        return QazaNamaz.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();

      final uniquePrayers =
          allPrayers.fold<Map<String, QazaNamaz>>({}, (map, prayer) {
        final key =
            '${prayer.prayerName}-${DateFormat('yyyy-MM-dd').format(prayer.date)}';
        map[key] = prayer;
        return map;
      });

      return uniquePrayers.values.toList();
    });
  }

  // Get deleted history
  Stream<List<QazaNamaz>> getDeletedHistory() {
    return _historyCollection
        .where('isDeleted', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return QazaNamaz.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // Restore a deleted prayer
  Future<void> restorePrayer(String prayerId) async {
    try {
      await _historyCollection.doc(prayerId).update({'isDeleted': false});
    } catch (e) {
      throw Exception('Failed to restore prayer: $e');
    }
  }

  Future<void> addPrayer(QazaNamaz prayer) async {
    try {
      print('Adding prayer for user: ${currentUserId}');
      await _prayersCollection.add(prayer.toMap());
      print('Prayer added successfully');
    } catch (e) {
      print('Error adding prayer: $e');
      throw e;
    }
  }

  // Update a prayer
  Future<void> updatePrayer(QazaNamaz prayer) async {
    if (prayer.id != null) {
      await _prayersCollection.doc(prayer.id).update(prayer.toMap());
    }
  }

  // Delete a prayer
  Future<void> deletePrayer(String prayerId) async {
    await _prayersCollection.doc(prayerId).delete();
  }

  // Get all active prayers
  Stream<List<QazaNamaz>> getPrayers() {
    return _prayersCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return QazaNamaz.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    });
  }

  // Stream<List<QazaNamaz>> getHistory() {
  //   return _historyCollection.snapshots().map((snapshot) {
  //     // Convert Firestore data to a list of QazaNamaz
  //     final allPrayers = snapshot.docs.map((doc) {
  //       return QazaNamaz.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  //     }).toList();

  //     // Remove duplicates based on prayerName and date
  //     final uniquePrayers =
  //         allPrayers.fold<Map<String, QazaNamaz>>({}, (map, prayer) {
  //       final key =
  //           '${prayer.prayerName}-${DateFormat('yyyy-MM-dd').format(prayer.date)}';
  //       map[key] = prayer; // Keep the latest entry with the same key
  //       return map;
  //     });

  //     return uniquePrayers.values.toList();
  //   });
  // }

  // Check for duplicate entries in history
  Future<bool> isDuplicateInHistory(QazaNamaz prayer) async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(prayer.date);

    // Check in history collection
    final historySnapshot = await _historyCollection
        .where('prayerName', isEqualTo: prayer.prayerName)
        .where('date', isEqualTo: formattedDate)
        .where('isDeleted', isEqualTo: false)
        .get();

    // Check in active prayers collection
    final prayersSnapshot = await _prayersCollection
        .where('prayerName', isEqualTo: prayer.prayerName)
        .where('date', isEqualTo: formattedDate)
        .get();

    return historySnapshot.docs.isNotEmpty || prayersSnapshot.docs.isNotEmpty;
  }

  Future<List<QazaNamaz>> getHistoryOnce() async {
    final snapshot = await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('history')
        .get();

    return snapshot.docs
        .map((doc) => QazaNamaz.fromMap(doc.data()..['id'] = doc.id, doc.id))
        .toList();
  }

  Future<void> movePrayerToHistory(QazaNamaz prayer) async {
    try {
      // Check if the prayer is already in the history collection
      final historyQuerySnapshot = await _historyCollection
          .where('prayerName', isEqualTo: prayer.prayerName)
          .where('date', isEqualTo: prayer.date)
          .get();

      if (historyQuerySnapshot.docs.isNotEmpty) {
        // If prayer already exists in history, do nothing

        return; // Exit if prayer is already in history
      }

      // Add prayer to the history collection if not a duplicate
      await _historyCollection.add(prayer.toMap());

      // If prayer has an ID, delete it from the current collection
      if (prayer.id != null) {
        await _prayersCollection.doc(prayer.id).delete();
      }
    } catch (e) {
      // Handle errors
      print('Error moving prayer to history: $e');
    }
  }

  Future<void> clearDeletedHistory() async {
    final deletedDocs = await _deletedHistoryCollection.get();
    for (var doc in deletedDocs.docs) {
      await doc.reference.delete();
    }
  }

  CollectionReference get _deletedHistoryCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('deletedHistory');
  }
}

// Data Models
class DailyPrayers {
  final DateTime date;
  bool fajr;
  bool zuhr;
  bool asr;
  bool maghrib;
  bool isha;
  final String? periodId;

  DailyPrayers({
    required this.date,
    this.fajr = false,
    this.zuhr = false,
    this.asr = false,
    this.maghrib = false,
    this.isha = false,
    this.periodId,
  });

  bool isCompleted() {
    return fajr && zuhr && asr && maghrib && isha;
  }

  void togglePrayer(String prayer) {
    switch (prayer) {
      case 'Fajr':
        fajr = !fajr;
        break;
      case 'Zuhr':
        zuhr = !zuhr;
        break;
      case 'Asr':
        asr = !asr;
        break;
      case 'Maghrib':
        maghrib = !maghrib;
        break;
      case 'Isha':
        isha = !isha;
        break;
    }
  }

  factory DailyPrayers.fromMap(Map<String, dynamic> map) {
    return DailyPrayers(
      date: (map['date'] as Timestamp).toDate(),
      fajr: map['fajr'] ?? false,
      zuhr: map['zuhr'] ?? false,
      asr: map['asr'] ?? false,
      maghrib: map['maghrib'] ?? false,
      isha: map['isha'] ?? false,
      periodId: map['periodId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'fajr': fajr,
      'zuhr': zuhr,
      'asr': asr,
      'maghrib': maghrib,
      'isha': isha,
      'periodId': periodId,
      'isCompleted': isCompleted(),
    };
  }
}

class BulkPeriod {
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final int completedDays;
  final bool isActive;
  final DateTime createdAt;

  BulkPeriod({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.completedDays,
    required this.isActive,
    required this.createdAt,
  });

  factory BulkPeriod.fromMap(Map<String, dynamic> map, String id) {
    return BulkPeriod(
      id: id,
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
      totalDays: map['totalDays'] ?? 0,
      completedDays: map['completedDays'] ?? 0,
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'totalDays': totalDays,
      'completedDays': completedDays,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

class DeletedHistoryBottomSheet extends StatelessWidget {
  final PrayerService prayerService;

  DeletedHistoryBottomSheet({required this.prayerService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QazaNamaz>>(
      stream: prayerService.getDeletedHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: Text('No deleted prayers found')),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Deleted Prayers',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final prayer = snapshot.data![index];
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading:
                          Icon(Icons.restore_from_trash, color: Colors.blue),
                      title: Text(prayer.prayerName),
                      subtitle:
                          Text(DateFormat('MMMM d, yyyy').format(prayer.date)),
                      trailing: TextButton.icon(
                        icon: Icon(Icons.restore),
                        label: Text('Restore'),
                        onPressed: () async {
                          await prayerService.restorePrayer(prayer.id!);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Prayer restored successfully')),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class BulkPrayerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final String? userId = FirebaseAuth.instance.currentUser?.uid;

  String? get currentUserId => _auth.currentUser?.uid;
  // In prayer_service.dart
  // Create a new bulk prayer period
  Future<DailyPrayer> getPrayer(String prayerId) async {
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('prayers')
        .doc(prayerId)
        .get();

    if (!doc.exists) {
      throw Exception('Prayer not found');
    }

    return DailyPrayer.fromMap(doc.data()!, doc.id);
  }

  // Update the main state class to include progress tracking
  Stream<PeriodProgress> getPeriodProgress(String periodId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('bulkPeriods')
        .doc(periodId)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      return PeriodProgress(
        totalPrayers: (data?['totalDays'] ?? 0) * 5, // 5 prayers per day
        completedPrayers: (data?['completedPrayers'] ?? 0),
      );
    });
  }

  Future<DailyPrayer?> getPreviousDayPrayers(
      String periodId, DateTime currentDate) async {
    final previousDate = currentDate.subtract(Duration(days: 1));

    final snapshot = await _firestore
        .collection('users')
        .doc(_auth.currentUser?.uid)
        .collection('bulkPeriods')
        .doc(periodId)
        .collection('prayers')
        .where('date', isEqualTo: Timestamp.fromDate(previousDate))
        .get();

    if (snapshot.docs.isEmpty) return null;

    final data = snapshot.docs.first.data();
    return DailyPrayer.fromMap(data, snapshot.docs.first.id);
  }

// // Add this helper method
//   bool _isAllPrayersCompleted(DailyPrayer prayer) {
//     return prayer.fajr &&
//         prayer.zuhr &&
//         prayer.asr &&
//         prayer.maghrib &&
//         prayer.isha;
//   }

  Future<void> addCompletedPrayer(CompletedPeriod period) {
    return _firestore
        .collection('users')
        .doc(_auth.currentUser?.uid)
        .collection('completedBulkPeriods')
        .add({
      ...period.toMap(),
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removePrayer(String prayerId) {
    return _firestore
        .collection('users')
        .doc(_auth.currentUser?.uid)
        .collection('prayers')
        .doc(prayerId)
        .delete();
  }

  Future<void> updatePeriodProgress(String periodId) async {
    final prayers = await _firestore
        .collection('users')
        .doc(_auth.currentUser?.uid)
        .collection('prayers')
        .where('periodId', isEqualTo: periodId)
        .get();

    for (var doc in prayers.docs) {
      final prayer = DailyPrayer.fromMap(doc.data(), doc.id);
      if (_isAllPrayersCompleted(prayer)) {
        // Add to completed periods
        await addCompletedPrayer(CompletedPeriod(
          startDate: prayer.date,
          endDate: prayer.date,
          days: 1,
        ));

        // Remove from active prayers
        await doc.reference.delete();
      }
    }
  }

  bool _isAllPrayersCompleted(DailyPrayer prayer) {
    return prayer.fajr &&
        prayer.zuhr &&
        prayer.asr &&
        prayer.maghrib &&
        prayer.isha;
  }

  Future<void> updateDailyPrayer(
    String periodId,
    String prayerId,
    String prayerName,
    bool value,
  ) async {
    if (currentUserId == null) throw Exception('User not logged in');

    final prayerRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPrayers')
        .doc(periodId)
        .collection('prayers')
        .doc(prayerId);

    // Start a transaction
    await _firestore.runTransaction((transaction) async {
      final prayerDoc = await transaction.get(prayerRef);
      final periodRef = _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('bulkPrayers')
          .doc(periodId);

      // Update the prayer
      transaction.update(prayerRef, {prayerName: value});

      // Check if all prayers for this day are completed
      Map<String, dynamic> data = prayerDoc.data()!;
      data[prayerName] = value;
      bool allCompleted = ['fajr', 'zuhr', 'asr', 'maghrib', 'isha']
          .every((prayer) => data[prayer] == true);

      // If status changed, update the period's completed count
      if (allCompleted != (data['isCompleted'] ?? false)) {
        final periodDoc = await transaction.get(periodRef);
        int currentCompleted = periodDoc.data()?['completedDays'] ?? 0;

        transaction.update(periodRef, {
          'completedDays':
              allCompleted ? currentCompleted + 1 : currentCompleted - 1
        });

        transaction.update(prayerRef, {'isCompleted': allCompleted});
      }
    });
  }

  Future<String> createBulkPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (currentUserId == null) throw Exception('User not logged in');

    // Create the bulk period document
    final periodRef = await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPrayers')
        .add({
      'startDate': startDate,
      'endDate': endDate,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'totalDays': endDate.difference(startDate).inDays + 1,
      'completedDays': 0,
    });

    // Create prayer documents for each day
    final int days = endDate.difference(startDate).inDays + 1;
    final batch = _firestore.batch();

    for (int i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      final prayerDoc = _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('bulkPrayers')
          .doc(periodRef.id)
          .collection('prayers')
          .doc();

      batch.set(prayerDoc, {
        'date': date,
        'fajr': false,
        'zuhr': false,
        'asr': false,
        'maghrib': false,
        'isha': false,
        'isCompleted': false,
      });
    }

    await batch.commit();
    return periodRef.id;
  }

  // Get active period prayers
  Stream<List<DailyPrayer>> getActivePeriodPrayers(String periodId) {
    if (currentUserId == null) throw Exception('User not logged in');

    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPrayers')
        .doc(periodId)
        .collection('prayers')
        .orderBy('date')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DailyPrayer.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Update prayer status
  Future<void> updatePrayerStatus(
    String prayerId,
    String prayerName,
    bool value,
  ) async {
    if (currentUserId == null) throw Exception('User not logged in');

    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPrayers')
        .doc(prayerId)
        .update({prayerName.toLowerCase(): value});
  }

  // Get active periods
  Stream<List<BulkPeriod>> getActivePeriods() {
    if (currentUserId == null) throw Exception('User not logged in');

    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPrayers')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => BulkPeriod.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Get completed periods with aggregated data
  Stream<List<Map<String, dynamic>>> getCompletedPeriodsWithStats() {
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('completedBulkPeriods')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                ...data,
                'id': doc.id,
                'totalPrayers': (data['totalDays'] as int) * 5,
                'completedPrayers': (data['completedDays'] as int) * 5,
              };
            }).toList());
  }

  // Load completed prayers for a specific period
  Stream<List<CompletedPeriod>> getCompletedPrayers() {
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('completedBulkPeriods')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CompletedPeriod.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Handle period completion
  Future<void> _completePeriod(String periodId) async {
    final periodRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPeriods')
        .doc(periodId);

    final periodDoc = await periodRef.get();
    final periodData = periodDoc.data() as Map<String, dynamic>;

    // Create completed period entry
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('completedBulkPeriods')
        .add({
      'originalPeriodId': periodId,
      'startDate': periodData['startDate'],
      'endDate': periodData['endDate'],
      'totalDays': periodData['totalDays'],
      'completedDays': periodData['completedDays'],
      'totalPrayers': periodData['totalDays'] * 5,
      'completedAt': FieldValue.serverTimestamp(),
    });

    // Update original period status
    await periodRef.update({
      'isActive': false,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<DailyPrayers>> getPeriodPrayers(String periodId) async {
    final prayersQuery = await _firestore
        .collection('periods')
        .doc(periodId)
        .collection('prayers')
        .orderBy('date')
        .get();

    return prayersQuery.docs.map((doc) {
      return DailyPrayers.fromMap({...doc.data(), 'id': doc.id});
    }).toList();
  }

  Future<void> addCompletedPrayers(List<CompletedPeriod> periods) async {
    final batch = _firestore.batch();

    for (var period in periods) {
      final docRef = _firestore.collection('completedPrayers').doc();
      batch.set(docRef, period.toMap());
    }

    await batch.commit();
  }

  Future<void> createPrayerPeriod(DateTime startDate, DateTime endDate) async {
    final periodRef = _firestore
        .collection('bulkPrayers')
        .doc(currentUserId)
        .collection('periodTime')
        .doc();

    await periodRef.set({
      'startDate': startDate,
      'endDate': endDate,
      'totalPrayers': endDate.difference(startDate).inDays * 5,
      'completedPrayers': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _firestore.batch();
    DateTime current = startDate;

    while (current.isBefore(endDate.add(Duration(days: 1)))) {
      final prayerRef = _firestore
          .collection('bulkPrayers')
          .doc(currentUserId)
          .collection('prayers')
          .doc();

      batch.set(prayerRef, {
        'date': current,
        'periodId': periodRef.id,
        'fajr': {'completed': false, 'completedAt': null},
        'zuhr': {'completed': false, 'completedAt': null},
        'asr': {'completed': false, 'completedAt': null},
        'maghrib': {'completed': false, 'completedAt': null},
        'isha': {'completed': false, 'completedAt': null},
        'allCompleted': false
      });

      current = current.add(Duration(days: 1));
    }

    await batch.commit();
  }

  Future<void> completePrayer(
      String periodId, DateTime date, String prayerName) async {
    // Transaction to ensure atomic updates
    await _firestore.runTransaction((transaction) async {
      // Get prayer document
      final prayerQuery = await _firestore
          .collection('bulkPrayers')
          .doc(currentUserId)
          .collection('prayers')
          .where('date', isEqualTo: date)
          .where('periodId', isEqualTo: periodId)
          .get();

      if (prayerQuery.docs.isEmpty) return;

      final prayerDoc = prayerQuery.docs.first;
      final prayerData = prayerDoc.data();

      // Update prayer status
      transaction.update(prayerDoc.reference, {
        '$prayerName.completed': true,
        '$prayerName.completedAt': FieldValue.serverTimestamp(),
      });

      // Check if all prayers for the day are completed
      bool allCompleted = true;
      ['fajr', 'zuhr', 'asr', 'maghrib', 'isha'].forEach((prayer) {
        if (prayer == prayerName) return;
        allCompleted = allCompleted && prayerData[prayer]['completed'] == true;
      });

      if (allCompleted) {
        // Update prayer document
        transaction.update(prayerDoc.reference, {'allCompleted': true});

        // Add to completed prayers
        final completedRef = _firestore
            .collection('bulkPrayers')
            .doc(currentUserId)
            .collection('completedPrayers')
            .doc();

        transaction.set(completedRef, {
          'periodId': periodId,
          'date': date,
          'completedAt': FieldValue.serverTimestamp(),
        });

        // Update period progress
        final periodRef = _firestore
            .collection('bulkPrayers')
            .doc(currentUserId)
            .collection('periodTime')
            .doc(periodId);

        final periodDoc = await transaction.get(periodRef);
        final currentCompleted = periodDoc.data()?['completedPrayers'] ?? 0;

        transaction
            .update(periodRef, {'completedPrayers': currentCompleted + 5});
      }
    });
  }

  CollectionReference get _completedBulkPrayersCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('completedBulkPrayers');
  }

  Future<void> addPeriodPrayers(List<DailyPrayers> prayers) async {
    if (currentUserId == null) throw Exception('No user logged in');
    if (prayers.isEmpty) return;

    try {
      // Create a new bulk period document
      final periodDoc = await _bulkPrayersCollection.add({
        'startDate': Timestamp.fromDate(prayers.first.date),
        'endDate': Timestamp.fromDate(prayers.last.date),
        'totalDays': prayers.length,
        'completedDays': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add all prayers in a batch
      final batch = _firestore.batch();

      for (var prayer in prayers) {
        final prayerDoc = _bulkPrayersCollection
            .doc(periodDoc.id)
            .collection('prayers')
            .doc();

        batch.set(prayerDoc, {
          ...prayer.toMap(),
          'periodId': periodDoc.id,
        });
      }

      await batch.commit();
      print(
          'Successfully added ${prayers.length} prayers to period ${periodDoc.id}');
    } catch (e) {
      print('Error adding bulk prayers: $e');
      throw Exception('Failed to add prayers: $e');
    }
  }

  CollectionReference get _prayersCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('user_prayers'); // Add prefix
  }

  CollectionReference get _bulkPrayersCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPrayers');
  }

  CollectionReference get _bulkPeriodsCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('bulkPrayers') // Separate collection for bulk prayers
        .doc('periods')
        .collection('daily'); // Store daily prayers here
  }

  CollectionReference get _dailyPrayersCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('dailyBulkPrayers');
  }

  CollectionReference get _completedPeriodsCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('completedBulkPeriods');
  }

  Stream<List<DailyPrayer>> getDailyPrayers(String periodId) {
    return _dailyPrayersCollection
        .where('periodId', isEqualTo: periodId)
        .orderBy('date')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                DailyPrayer.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  // Get completed periods
  Stream<List<CompletedPeriod>> getCompletedPeriods() {
    return _completedPeriodsCollection
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CompletedPeriod.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  // Delete a period
  Future<void> deletePeriod(String periodId) async {
    try {
      // Delete all daily prayers for this period
      final dailyPrayers = await _dailyPrayersCollection
          .where('periodId', isEqualTo: periodId)
          .get();

      final batch = _firestore.batch();
      for (var doc in dailyPrayers.docs) {
        batch.delete(doc.reference);
      }

      // Delete the period document
      batch.delete(_bulkPeriodsCollection.doc(periodId));

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete period: $e');
    }
  }
}

class DailyPrayer {
  final DateTime date;
  final String? id;

  final String periodId;

  bool fajr, zuhr, asr, maghrib, isha;
  bool isCompleted;

  DailyPrayer({
    required this.id,
    required this.date,
    required this.periodId,
    this.fajr = false,
    this.zuhr = false,
    this.asr = false,
    this.maghrib = false,
    this.isha = false,
    this.isCompleted = false,
  });

  void togglePrayer(String prayer) {
    switch (prayer) {
      case 'Fajr':
        fajr = !fajr;
        break;
      case 'Zuhr':
        zuhr = !zuhr;
        break;
      case 'Asr':
        asr = !asr;
        break;
      case 'Maghrib':
        maghrib = !maghrib;
        break;
      case 'Isha':
        isha = !isha;
        break;
    }
  }

  factory DailyPrayer.fromMap(Map<String, dynamic> map, String id) {
    return DailyPrayer(
      id: id,
      periodId: map['periodId'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      fajr: map['fajr'] ?? false,
      zuhr: map['zuhr'] ?? false,
      asr: map['asr'] ?? false,
      maghrib: map['maghrib'] ?? false,
      isha: map['isha'] ?? false,
      isCompleted: map['isCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'periodId': periodId,
      'date': Timestamp.fromDate(date),
      'fajr': fajr,
      'zuhr': zuhr,
      'asr': asr,
      'maghrib': maghrib,
      'isha': isha,
      'isCompleted': isCompleted,
    };
  }
}

// // Data Models
// class DailyPrayer {
//   final String id;
//   final String periodId;
//   final DateTime date;
//   bool fajr;
//   bool zuhr;
//   bool asr;
//   bool maghrib;
//   bool isha;
//   bool isCompleted;

//   DailyPrayer({
//     required this.id,
//     required this.periodId,
//     required this.date,
//     this.fajr = false,
//     this.zuhr = false,
//     this.asr = false,
//     this.maghrib = false,
//     this.isha = false,
//     this.isCompleted = false,
//   });

// }
class PeriodProgress {
  final int totalPrayers;
  final int completedPrayers;

  PeriodProgress({
    required this.totalPrayers,
    required this.completedPrayers,
  });

  double get percentage =>
      totalPrayers > 0 ? (completedPrayers / totalPrayers) * 100 : 0;
}
