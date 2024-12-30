import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'package:flutter/material.dart';

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

  // Future<void> deleteFromHistory(String prayerId) async {
  //   final prayerDoc = await _historyCollection.doc(prayerId).get();
  //   if (prayerDoc.exists) {
  //     // Move the prayer to the deletedHistory collection
  //     await _deletedHistoryCollection.add(prayerDoc.data()!);
  //     // Remove it from the active history collection
  //     await _historyCollection.doc(prayerId).delete();
  //   }
  // }

//   // Clear all history
//   Future<void> clearAllHistory() async {
//     var snapshot = await _historyCollection.get();
//     for (var doc in snapshot.docs) {
//       await doc.reference.delete();
//     }
//   }
// Future<void> deleteFromHistory(String prayerId) async {
//   try {
//     await _historyCollection.doc(prayerId).delete();
//   } catch (e) {
//     throw Exception('Failed to delete prayer: $e');
//   }
// }

  Future<void> clearDeletedHistory() async {
    final deletedDocs = await _deletedHistoryCollection.get();
    for (var doc in deletedDocs.docs) {
      await doc.reference.delete();
    }
  }

  // Future<void> restorePrayer(QazaNamaz prayer) async {
  //   // Add back to active history
  //   await _historyCollection.add(prayer.toMap());
  //   // (Optional) Remove from deletedHistory if desired
  //   // await _deletedHistoryCollection.doc(prayer.id).delete();
  // }

  CollectionReference get _deletedHistoryCollection {
    if (currentUserId == null) throw Exception('No user logged in');
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('deletedHistory');
  }

  // Stream<List<QazaNamaz>> getDeletedHistory() {
  //   return _deletedHistoryCollection.snapshots().map((snapshot) {
  //     return snapshot.docs.map((doc) {
  //       return QazaNamaz.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  //     }).toList();
  //   });
  // }
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
