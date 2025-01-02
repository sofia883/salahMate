import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:async/async.dart';

class QazaPeriodPage extends StatefulWidget {
  @override
  _QazaPeriodPageState createState() => _QazaPeriodPageState();
}

class _QazaPeriodPageState extends State<QazaPeriodPage> {
  BulkPrayerService _bulkPrayerService = BulkPrayerService();
  final Map<String, bool> _prayerStatuses = {};
  Map<String, Map<String, bool>> _prayerCache = {};
  bool isLoading = true; // Add loading state
  int completedDays = 0;
  int totalPrayers = 0;
  int completedPrayersCount = 0;
  bool showDatePickers = true;
  bool _isUpdatingPrayer = false;
  DateTime? startDate;
  DateTime? endDate;
  List<DailyPrayer> periodPrayers = [];
  List<CompletedPeriod> completedPeriods = [];
  int totalDays = 0;
  int displayDays = 7;
  String? currentPeriodId;
  // The main issue is in the _handlePrayerCompletion function where the counts are not being properly preserved
// Here's the fixed version:
// Add this to your state variables at the top of _QazaPeriodPageState
  bool _isProcessing = false;
  Widget _buildPrayerCard(DailyPrayer prayer) {
    bool isCompleted = prayer.fajr &&
        prayer.zuhr &&
        prayer.asr &&
        prayer.maghrib &&
        prayer.isha;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: isCompleted
          ? ListTile(
              contentPadding: EdgeInsets.all(8),
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text(
                DateFormat('d').format(prayer.date) +
                    _getDaySuffix(prayer.date.day) +
                    ' ' +
                    DateFormat('MMMM yyyy').format(prayer.date),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              subtitle: Text(
                'All prayers completed',
                style: TextStyle(color: Colors.green, fontSize: 12),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date header with checkbox for all prayers
                Container(
                  color: isCompleted
                      ? Colors.green.withOpacity(0.1)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      Checkbox(
                        value: isCompleted,
                        activeColor: Colors.green,
                        onChanged: (bool? newValue) async {
                          if (newValue != null) {
                            await _handleBatchPrayerCompletion(
                                prayer, newValue);
                          }
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            DateFormat('d').format(prayer.date) +
                                _getDaySuffix(prayer.date.day) +
                                ' ' +
                                DateFormat('MMMM yyyy').format(prayer.date),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Prayer tiles for incomplete prayers
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    children: [
                      _buildPrayerTile(prayer, 'Fajr', prayer.fajr),
                      _buildPrayerTile(prayer, 'Zuhr', prayer.zuhr),
                      _buildPrayerTile(prayer, 'Asr', prayer.asr),
                      _buildPrayerTile(prayer, 'Maghrib', prayer.maghrib),
                      _buildPrayerTile(prayer, 'Isha', prayer.isha),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPrayerTile(DailyPrayer prayer, String name, bool value) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: ListTile(
        dense: true,
        leading: Icon(
          value ? Icons.check_circle : Icons.circle_outlined,
          color: value ? Colors.green : Colors.grey,
        ),
        title: Text(
          name,
          style: TextStyle(
            color: value ? Colors.green : Colors.black,
            fontWeight: value ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () => _handlePrayerCompletion(prayer, name, !value),
      ),
    );
  }

// Add this new function to handle marking all prayers for a day
  Future<void> _handleBatchPrayerCompletion(
      DailyPrayer prayer, bool newValue) async {
    if (_isProcessing) return;

    try {
      setState(() {
        _isProcessing = true;
        isLoading = true;
      });

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not logged in');

      final batch = FirebaseFirestore.instance.batch();

      // Update prayer document
      final prayerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prayers')
          .doc(prayer.id);

      // Update all prayers at once
      batch.update(prayerRef, {
        'fajr': newValue,
        'zuhr': newValue,
        'asr': newValue,
        'maghrib': newValue,
        'isha': newValue,
        'lastUpdated': FieldValue.serverTimestamp()
      });

      // Get current period data
      final periodRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bulkPeriods')
          .doc(currentPeriodId);

      final periodDoc = await periodRef.get();
      final currentData = periodDoc.data() ?? {};

      // Calculate prayer count change (5 prayers per day)
      final currentPrayerCount = currentData['completedPrayers'] ?? 0;
      final currentDayCount = currentData['completedDays'] ?? 0;

      final prayerDoc = await prayerRef.get();
      final oldData = prayerDoc.data() as Map<String, dynamic>;
      final wasCompleted = oldData['fajr'] == true &&
          oldData['zuhr'] == true &&
          oldData['asr'] == true &&
          oldData['maghrib'] == true &&
          oldData['isha'] == true;

      // Calculate changes
      final int completedPrayersChange = newValue
          ? (5 - _countCompletedPrayers(oldData))
          : -_countCompletedPrayers(oldData);

      final int dayCountChange = newValue && !wasCompleted
          ? 1
          : !newValue && wasCompleted
              ? -1
              : 0;

      // Update period document
      batch.update(periodRef, {
        'completedPrayers': currentPrayerCount + completedPrayersChange,
        'completedDays': currentDayCount + dayCountChange,
        'lastUpdated': FieldValue.serverTimestamp()
      });

      await batch.commit();

      // Update local state
      if (mounted) {
        setState(() {
          _prayerCache[prayer.id] = {
            'fajr': newValue,
            'zuhr': newValue,
            'asr': newValue,
            'maghrib': newValue,
            'isha': newValue,
            'isCompleted': newValue,
          };
          completedPrayersCount = currentPrayerCount + completedPrayersChange;
          completedDays = currentDayCount + dayCountChange;
        });
      }
    } catch (e) {
      print('Error in batch prayer completion: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update prayers'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          isLoading = false;
        });
      }
    }
  }

// Helper function to count completed prayers
  int _countCompletedPrayers(Map<String, dynamic> data) {
    return [
      data['fajr'] ?? false,
      data['zuhr'] ?? false,
      data['asr'] ?? false,
      data['maghrib'] ?? false,
      data['isha'] ?? false,
    ].where((completed) => completed).length;
  }

  Future<void> _handlePrayerCompletion(
      DailyPrayer prayer, String prayerName, bool newValue) async {
    // Prevent multiple simultaneous updates
    if (_isProcessing) return;

    try {
      setState(() {
        _isProcessing = true;
        isLoading = true; // Show loading only once
      });

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Perform all updates in a single batch
      final batch = FirebaseFirestore.instance.batch();

      // Update prayer document
      final prayerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prayers')
          .doc(prayer.id);

      batch.update(prayerRef, {
        prayerName.toLowerCase(): newValue,
        'lastUpdated': FieldValue.serverTimestamp()
      });

      // Update period document
      final periodRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bulkPeriods')
          .doc(currentPeriodId);

      // Get current counts once
      final periodDoc = await periodRef.get();
      final currentData = periodDoc.data() ?? {};
      final currentPrayerCount = currentData['completedPrayers'] ?? 0;
      final currentDayCount = currentData['completedDays'] ?? 0;

      // Calculate new counts
      final allPrayers = await prayerRef.get();
      final prayerData = allPrayers.data() as Map<String, dynamic>;

      final updatedPrayers = {
        'fajr': prayerData['fajr'] ?? false,
        'zuhr': prayerData['zuhr'] ?? false,
        'asr': prayerData['asr'] ?? false,
        'maghrib': prayerData['maghrib'] ?? false,
        'isha': prayerData['isha'] ?? false,
        prayerName.toLowerCase(): newValue,
      };

      final bool willBeCompleted =
          updatedPrayers.values.every((v) => v == true);
      final bool wasCompleted = prayerData.values.every((v) => v == true);

      final prayerCountChange = newValue ? 1 : -1;
      final dayCountChange = willBeCompleted && !wasCompleted
          ? 1
          : !willBeCompleted && wasCompleted
              ? -1
              : 0;

      batch.update(periodRef, {
        'completedPrayers': currentPrayerCount + prayerCountChange,
        'completedDays': currentDayCount + dayCountChange,
        'lastUpdated': FieldValue.serverTimestamp()
      });

      // Commit all changes at once
      await batch.commit();

      // Update local state once
      if (mounted) {
        setState(() {
          completedPrayersCount = currentPrayerCount + prayerCountChange;
          completedDays = currentDayCount + dayCountChange;
          _prayerCache[prayer.id] ??= {};
          _prayerCache[prayer.id]![prayerName.toLowerCase()] = newValue;
          _prayerCache[prayer.id]!['isCompleted'] = willBeCompleted;
        });
      }
    } catch (e) {
      print('Error updating prayer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update prayer'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          isLoading = false;
        });
      }
    }
  }

// Modify your _subscribeToPrayerStatuses to reduce unnecessary updates
  void _subscribeToPrayerStatuses() {
    if (currentPeriodId == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid;

    // Use a single merged stream for both period and prayers
    final periodStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bulkPeriods')
        .doc(currentPeriodId)
        .snapshots();

    final prayersStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('prayers')
        .where('periodId', isEqualTo: currentPeriodId)
        .snapshots();

    // Combine streams to update UI only once when either changes
    StreamGroup.merge([periodStream, prayersStream]).listen((snapshot) {
      if (!mounted) return;

      if (snapshot is DocumentSnapshot) {
        // Period document update
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          setState(() {
            completedDays = data['completedDays'] ?? 0;
            completedPrayersCount = data['completedPrayers'] ?? 0;
            totalPrayers = data['totalPrayers'] ?? 0;
          });
        }
      } else if (snapshot is QuerySnapshot) {
        // Prayers update
        final updatedCache = Map<String, Map<String, bool>>.from(_prayerCache);

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final isCompleted = data['fajr'] == true &&
              data['zuhr'] == true &&
              data['asr'] == true &&
              data['maghrib'] == true &&
              data['isha'] == true;

          updatedCache[doc.id] = {
            'fajr': data['fajr'] ?? false,
            'zuhr': data['zuhr'] ?? false,
            'asr': data['asr'] ?? false,
            'maghrib': data['maghrib'] ?? false,
            'isha': data['isha'] ?? false,
            'isCompleted': isCompleted,
          };
        }

        setState(() {
          _prayerCache = updatedCache;
        });
      }
    });
  }

// New helper widget for showing completed prayer tiles
  Widget _buildCompletedPrayerTile(
      DailyPrayer prayer, String name, bool value) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 16,
      child: ListTile(
        dense: true,
        leading: value
            ? Icon(Icons.check_circle, color: Colors.green)
            : Icon(Icons.circle_outlined),
        title: Text(
          name,
          style: TextStyle(
            color: value ? Colors.green : Colors.black,
            fontWeight: value ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () => _handlePrayerCompletion(prayer, name, !value),
      ),
    );
  }

  // Future<void> _handlePrayerCompletion(
  //     DailyPrayer prayer, String prayerName, bool newValue) async {
  //   if (_isUpdatingPrayer) return;

  //   try {
  //     setState(() {
  //       _isUpdatingPrayer = true;
  //     });

  //     final userId = FirebaseAuth.instance.currentUser?.uid;
  //     if (userId == null) {
  //       throw Exception('User not logged in');
  //     }

  //     // Start a batch operation
  //     final batch = FirebaseFirestore.instance.batch();

  //     // 1. First get the current period document to get existing counts
  //     final periodDoc = await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(userId)
  //         .collection('bulkPeriods')
  //         .doc(currentPeriodId)
  //         .get();

  //     // Get existing counts from the period document
  //     final existingCompletedPrayers =
  //         periodDoc.data()?['completedPrayers'] ?? 0;
  //     final existingCompletedDays = periodDoc.data()?['completedDays'] ?? 0;

  //     // 2. Get the prayer document
  //     final prayerRef = FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(userId)
  //         .collection('prayers')
  //         .doc(prayer.id);

  //     final prayerDoc = await prayerRef.get();
  //     final prayerData = prayerDoc.data() as Map<String, dynamic>;

  //     // Check if this specific prayer was previously completed
  //     final bool wasPreviouslyCompleted =
  //         prayerData[prayerName.toLowerCase()] ?? false;

  //     // Calculate the change in prayer count
  //     final int prayerCountChange = newValue && !wasPreviouslyCompleted
  //         ? 1
  //         : !newValue && wasPreviouslyCompleted
  //             ? -1
  //             : 0;

  //     // Update the prayer status
  //     batch.update(prayerRef, {
  //       prayerName.toLowerCase(): newValue,
  //       'lastUpdated': FieldValue.serverTimestamp()
  //     });

  //     // Get updated prayer state
  //     Map<String, bool> updatedPrayerState = {
  //       'fajr': prayerData['fajr'] ?? false,
  //       'zuhr': prayerData['zuhr'] ?? false,
  //       'asr': prayerData['asr'] ?? false,
  //       'maghrib': prayerData['maghrib'] ?? false,
  //       'isha': prayerData['isha'] ?? false,
  //     };
  //     updatedPrayerState[prayerName.toLowerCase()] = newValue;

  //     // Check completion status
  //     final bool willBeFullyCompleted =
  //         updatedPrayerState.values.every((v) => v);
  //     final bool wasFullyCompleted = prayerData.values.every((v) => v == true);

  //     // Calculate day completion change
  //     final int dayCountChange = willBeFullyCompleted && !wasFullyCompleted
  //         ? 1
  //         : !willBeFullyCompleted && wasFullyCompleted
  //             ? -1
  //             : 0;

  //     // Calculate new totals by ADDING to existing counts
  //     final int newCompletedPrayers =
  //         existingCompletedPrayers + prayerCountChange;
  //     final int newCompletedDays = existingCompletedDays + dayCountChange;

  //     // Update the period document with accumulated totals
  //     batch.update(
  //         FirebaseFirestore.instance
  //             .collection('users')
  //             .doc(userId)
  //             .collection('bulkPeriods')
  //             .doc(currentPeriodId),
  //         {
  //           'completedPrayers': newCompletedPrayers,
  //           'completedDays': newCompletedDays,
  //           'lastUpdated': FieldValue.serverTimestamp(),
  //           'lastPrayerUpdate': {
  //             'prayerId': prayer.id,
  //             'prayerName': prayerName,
  //             'timestamp': FieldValue.serverTimestamp()
  //           }
  //         });

  //     // Commit all updates
  //     await batch.commit();

  //     // Update local state
  //     if (mounted) {
  //       setState(() {
  //         _prayerCache[prayer.id] ??= {};
  //         _prayerCache[prayer.id]![prayerName.toLowerCase()] = newValue;
  //         _prayerCache[prayer.id]!['isCompleted'] = willBeFullyCompleted;
  //         completedPrayersCount = newCompletedPrayers;
  //         completedDays = newCompletedDays;
  //       });
  //     }
  //   } catch (e) {
  //     print('Error updating prayer status: $e');
  //     // Revert local cache if update fails
  //     if (mounted) {
  //       setState(() {
  //         _prayerCache[prayer.id]![prayerName.toLowerCase()] = !newValue;
  //       });
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Failed to update prayer status'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   } finally {
  //     if (mounted) {
  //       setState(() {
  //         _isUpdatingPrayer = false;
  //       });
  //     }
  //   }
  // }

  // void _subscribeToPrayerStatuses() {
  //   if (currentPeriodId == null) return;
  //   final userId = FirebaseAuth.instance.currentUser?.uid;

  //   // Listen to period document changes
  //   FirebaseFirestore.instance
  //       .collection('users')
  //       .doc(userId)
  //       .collection('bulkPeriods')
  //       .doc(currentPeriodId)
  //       .snapshots()
  //       .listen((snapshot) {
  //     if (snapshot.exists && mounted) {
  //       final data = snapshot.data()!;
  //       setState(() {
  //         completedDays = data['completedDays'] ?? 0;
  //         completedPrayersCount = data['completedPrayers'] ?? 0;
  //         totalPrayers = data['totalPrayers'] ?? 0;
  //       });
  //     }
  //   });

  //   // Listen to all prayers for this period
  //   FirebaseFirestore.instance
  //       .collection('users')
  //       .doc(userId)
  //       .collection('prayers')
  //       .where('periodId', isEqualTo: currentPeriodId)
  //       .snapshots()
  //       .listen((snapshot) {
  //     if (snapshot.docs.isNotEmpty && mounted) {
  //       final updatedCache = Map<String, Map<String, bool>>.from(_prayerCache);

  //       for (var doc in snapshot.docs) {
  //         final data = doc.data();
  //         final isCompleted = data['fajr'] == true &&
  //             data['zuhr'] == true &&
  //             data['asr'] == true &&
  //             data['maghrib'] == true &&
  //             data['isha'] == true;

  //         updatedCache[doc.id] = {
  //           'fajr': data['fajr'] ?? false,
  //           'zuhr': data['zuhr'] ?? false,
  //           'asr': data['asr'] ?? false,
  //           'maghrib': data['maghrib'] ?? false,
  //           'isha': data['isha'] ?? false,
  //           'isCompleted': isCompleted,
  //         };
  //       }

  //       setState(() {
  //         _prayerCache = updatedCache;
  //       });
  //     }
  //   });
  // }

  Future<void> _updatePrayerStatus(
      String prayerId, String prayer, bool value) async {
    if (_isUpdatingPrayer) return;

    try {
      setState(() {
        _isUpdatingPrayer = true;
        // Update local cache immediately
        if (_prayerCache[prayerId] == null) {
          _prayerCache[prayerId] = {};
        }
        _prayerCache[prayerId]![prayer] = value;
      });

      // Update Firestore
      final userId = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prayers')
          .doc(prayerId)
          .update({prayer: value});

      // Check if all prayers for this day are completed after the update
      final prayerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prayers')
          .doc(prayerId)
          .get();

      final data = prayerDoc.data()!;
      final bool isCompleted = data['fajr'] == true &&
          data['zuhr'] == true &&
          data['asr'] == true &&
          data['maghrib'] == true &&
          data['isha'] == true;

      // Update the cache with completion status
      setState(() {
        _prayerCache[prayerId]!['isCompleted'] = isCompleted;
      });

      // Update progress counters only after confirmation
      await _updateProgressCounters();
    } catch (e) {
      print('Error updating prayer status: $e');
      // Revert local cache if update fails
      setState(() {
        _prayerCache[prayerId]![prayer] = !value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update prayer status')),
      );
    } finally {
      setState(() {
        _isUpdatingPrayer = false;
      });
    }
  }

// Improve the _updateProgressCounters function
  Future<void> _updateProgressCounters() async {
    if (currentPeriodId == null) return;

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;

      // Get all prayers for this period
      final prayers = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prayers')
          .where('periodId', isEqualTo: currentPeriodId)
          .get();

      // Calculate totals
      int totalCompletedPrayers = 0;
      Set<String> completedDaysSet = {};

      for (var doc in prayers.docs) {
        var data = doc.data();
        String date =
            (data['date'] as Timestamp).toDate().toString().split(' ')[0];
        int dayCompletedPrayers = 0;

        if (data['fajr'] == true) dayCompletedPrayers++;
        if (data['zuhr'] == true) dayCompletedPrayers++;
        if (data['asr'] == true) dayCompletedPrayers++;
        if (data['maghrib'] == true) dayCompletedPrayers++;
        if (data['isha'] == true) dayCompletedPrayers++;

        totalCompletedPrayers += dayCompletedPrayers;

        if (dayCompletedPrayers == 5) {
          completedDaysSet.add(date);
        }
      }

      // Update period document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bulkPeriods')
          .doc(currentPeriodId)
          .update({
        'completedPrayers': totalCompletedPrayers,
        'completedDays': completedDaysSet.length,
        'completedDaysSet': completedDaysSet.toList(),
      });

      // Update local state only after successful Firestore update
      if (mounted) {
        setState(() {
          completedPrayersCount = totalCompletedPrayers;
          completedDays = completedDaysSet.length;
        });
      }
    } catch (e) {
      print('Error updating progress counters: $e');
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Congratulations! 🎉'),
        content: Text(
            'You have completed all prayers in this period! Would you like to start a new period?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                currentPeriodId = null;
                showDatePickers = true;
                startDate = null;
                endDate = null;
              });
            },
            child: Text('Start New Period'),
          ),
        ],
      ),
    );
  }

// Add this helper function for day suffix
  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) {
      return 'th';
    }
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  Future<void> _loadActivePeriod() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final periodsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bulkPeriods')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (periodsSnapshot.docs.isNotEmpty) {
        final periodDoc = periodsSnapshot.docs.first;
        final data = periodDoc.data();

        setState(() {
          currentPeriodId = periodDoc.id;
          totalDays = data['totalDays'] ?? 0;
          completedDays = data['completedDays'] ?? 0;
          totalPrayers = data['totalPrayers'] ?? 0;
          completedPrayersCount = data['completedPrayers'] ?? 0;
          showDatePickers = false;

          if (data['startDate'] != null) {
            startDate = (data['startDate'] as Timestamp).toDate();
          }
          if (data['endDate'] != null) {
            endDate = (data['endDate'] as Timestamp).toDate();
          }
        });

        _subscribeToPrayerStatuses();
      } else {
        setState(() {
          showDatePickers = true;
        });
      }
    } catch (e) {
      print('Error loading active period: $e');
    }
  }

// First, let's improve the _up
// Add initState to ensure we load data when screen opens
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialLoad();
    });
  }

  Future<void> _initialLoad() async {
    setState(() {
      isLoading = true;
    });
    await _loadActivePeriod();
    _subscribeToPrayerStatuses(); // Subscribe after loading period
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _createNewPeriod() async {
    setState(() {
      isLoading = true;
    });

    try {
      if (startDate == null || endDate == null) {
        throw Exception('Start and end dates must be selected');
      }

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Calculate total days and prayers
      final days = endDate!.difference(startDate!).inDays + 1;
      final totalPrayersCount = days * 5;

      // Create period document under user's collection
      final periodRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bulkPeriods') // Store under user's collection
          .add({
        'startDate': Timestamp.fromDate(startDate!),
        'endDate': Timestamp.fromDate(endDate!),
        'totalDays': days,
        'completedDays': 0,
        'totalPrayers': totalPrayersCount,
        'completedPrayers': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final periodId = periodRef.id;

      // Create prayers using batched write
      final batch = FirebaseFirestore.instance.batch();
      DateTime currentDate = startDate!;

      while (!currentDate.isAfter(endDate!)) {
        final prayerRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('prayers')
            .doc();

        batch.set(prayerRef, {
          'date': Timestamp.fromDate(currentDate),
          'periodId': periodId,
          'fajr': false,
          'zuhr': false,
          'asr': false,
          'maghrib': false,
          'isha': false,
        });

        currentDate = currentDate.add(Duration(days: 1));
      }

      await batch.commit();

      // Update state
      setState(() {
        currentPeriodId = periodId;
        totalDays = days;
        completedDays = 0;
        totalPrayers = totalPrayersCount;
        completedPrayersCount = 0;
        showDatePickers = false;
      });

      // Remove the await here since it's a void function
      _subscribeToPrayerStatuses(); // Just call the function directly

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prayer period created successfully')),
      );
    } catch (e) {
      print('Error creating period: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create period: ${e.toString()}')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Qaza Prayer Tracker'), actions: [
        // Add New Period button
        IconButton(
          icon: Icon(Icons.add),
          tooltip: 'Create New Period',
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Create New Period?'),
                content: Text(currentPeriodId != null
                    ? 'This will end your current period. Continue?'
                    : 'Start tracking a new prayer period?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        currentPeriodId = null;
                        showDatePickers = true;
                        startDate = null;
                        endDate = null;
                      });
                    },
                    child: Text('Create New'),
                  ),
                ],
              ),
            );
          },
        ),
        if (currentPeriodId != null)
          Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$completedDays/$totalDays days',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$completedPrayersCount/$totalPrayers prayers',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ]),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (showDatePickers) _buildDatePickers(),
                Expanded(
                    child: currentPeriodId == null
                        ? Center(
                            child: Text(
                              showDatePickers
                                  ? 'Select dates to start tracking prayers'
                                  : 'No active period found',
                            ),
                          )
                        : StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(FirebaseAuth.instance.currentUser?.uid)
                                .collection('prayers')
                                .where('periodId', isEqualTo: currentPeriodId)
                                .orderBy('date',
                                    descending: false) // Only order by date
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                print(
                                    'Stream error: ${snapshot.error}'); // Add error logging
                                return Center(
                                    child: Text(
                                        'Error loading prayers: ${snapshot.error}'));
                              }

                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return Center(
                                    child: CircularProgressIndicator());
                              }

                              if (!snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return Center(
                                    child: Text(
                                        'No prayers found for this period'));
                              }

                              final prayers = snapshot.data!.docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return DailyPrayer(
                                  id: doc.id,
                                  periodId: data['periodId'] as String,
                                  date: (data['date'] as Timestamp).toDate(),
                                  fajr: data['fajr'] ?? false,
                                  zuhr: data['zuhr'] ?? false,
                                  asr: data['asr'] ?? false,
                                  maghrib: data['maghrib'] ?? false,
                                  isha: data['isha'] ?? false,
                                );
                              }).toList();

                              return ListView.builder(
                                itemCount: prayers.length,
                                itemBuilder: (context, index) {
                                  return _buildPrayerCard(prayers[index]);
                                },
                              );
                            },
                          )),
              ],
            ),
    );
  }

  Future<void> _moveToCompleted(DailyPrayer prayer) async {
    try {
      // Add to completed prayers
      await _bulkPrayerService.addCompletedPrayer(
        CompletedPeriod(
          startDate: prayer.date,
          endDate: prayer.date,
          days: 1,
        ),
      );

      // Remove from active prayers
      await _bulkPrayerService.removePrayer(prayer.id!);

      // Update progress
      setState(() {
        completedDays++;
      });
      await _updateProgressCounters();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${DateFormat('MMM d').format(prayer.date)} completed!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error moving completed prayers: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildDatePickers() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Start Date',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              controller: TextEditingController(
                text: startDate?.toString().split(' ')[0] ?? '',
              ),
              onTap: () => _selectDate(true),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'End Date',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              controller: TextEditingController(
                text: endDate?.toString().split(' ')[0] ?? '',
              ),
              onTap: () => _selectDate(false),
            ),
          ),
        ],
      ),
    );
  }

  bool _getPrayerStatus(String prayerId, String prayer) {
    return _prayerCache[prayerId]?[prayer] ?? false;
  }

  Widget _buildPrayerCheckbox(DailyPrayer prayer, String name, bool value) {
    String prayerId = '${prayer.id}_$name';
    bool isCompleted = _prayerCache[prayerId]?['completed'] ?? false;

    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 16,
      child: CheckboxListTile(
        title: Text(name),
        value: _prayerStatuses[prayerId] ?? value,
        enabled: !isCompleted, // Disable checkbox if prayer is completed
        secondary: _prayerStatuses[prayerId] == true
            ? Icon(Icons.check_circle, color: Colors.green)
            : null,
        onChanged: isCompleted
            ? null
            : (bool? newValue) {
                if (newValue != null && newValue != value) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Confirm Prayer'),
                      content: Text('Have you completed $name prayer?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('No'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            setState(() {
                              _prayerStatuses[prayerId] = newValue;
                            });

                            await _updatePrayerStatus(
                              prayer.id!,
                              name.toLowerCase(),
                              newValue,
                            );
// In _buildPrayerCheckbox after updatePrayerStatus
                            await _bulkPrayerService
                                .updatePeriodProgress(currentPeriodId!);
                            // Check if all prayers for this day are completed
                            bool allCompleted = _checkDayCompletion(prayer);
                            if (allCompleted) {
                              await _moveToCompleted(prayer);
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:

// Replace the dialog's Yes button onPressed with this optimized version
                                    TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _handlePrayerCompletion(
                                        prayer, name, newValue);
                                  },
                                  child: Text('Yes'),
                                ),
                              ),
                            );
                          },
                          child: Text('Yes'),
                        ),
                      ],
                    ),
                  );
                }
              },
      ),
    );
  }

  bool _checkDayCompletion(DailyPrayer prayer) {
    return prayer.fajr &&
        prayer.zuhr &&
        prayer.asr &&
        prayer.maghrib &&
        prayer.isha;
  }

  Future<void> _selectDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (date != null) {
      setState(() {
        if (isStart) {
          startDate = date;
        } else {
          endDate = date;
        }
      });

      if (startDate != null && endDate != null) {
        await _createNewPeriod();
      }
    }
  }

  String formatDateWithSuffix(DateTime date) {
    final day = date.day;
    final suffix = (day % 10 == 1 && day != 11)
        ? 'st'
        : (day % 10 == 2 && day != 12)
            ? 'nd'
            : (day % 10 == 3 && day != 13)
                ? 'rd'
                : 'th';
    return '${DateFormat('EEEE, d').format(date)}$suffix ${DateFormat('MMMM yyyy').format(date)}';
  }
}

class CompletedPeriod {
  final DateTime startDate;
  final DateTime endDate;
  final int days;

  CompletedPeriod({
    required this.startDate,
    required this.endDate,
    required this.days,
  });

  factory CompletedPeriod.fromMap(Map<String, dynamic> map, String id) {
    return CompletedPeriod(
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
      days: map['days'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'days': days,
    };
  }
}

class CompletedPrayersScreen extends StatelessWidget {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Completed Prayers')),
        body: Center(child: Text('Please login first')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Completed Prayers History'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Use the correct collection path
        stream: _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('completedBulkPeriods')
            .orderBy('completedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No completed prayers yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final startDate = (data['startDate'] as Timestamp).toDate();
              final endDate = (data['endDate'] as Timestamp).toDate();
              final totalDays = data['totalDays'] ?? 0;
              final completedDays = data['completedDays'] ?? 0;

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.check, color: Colors.white),
                  ),
                  title: Text(
                    _formatDateRange(startDate, endDate),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 8),
                      Text('Completed $completedDays out of $totalDays days'),
                      Text(
                        '${completedDays * 5} prayers completed',
                        style: TextStyle(
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDateRange(DateTime startDate, DateTime endDate) {
    final start = DateFormat('MMM d, yyyy').format(startDate);
    final end = DateFormat('MMM d, yyyy').format(endDate);
    return '$start - $end';
  }
}
