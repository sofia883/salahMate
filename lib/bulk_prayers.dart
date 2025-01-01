import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  DateTime? startDate;
  DateTime? endDate;
  List<DailyPrayers> periodPrayers = [];
  List<CompletedPeriod> completedPeriods = [];
  int totalDays = 0;
  int displayDays = 7;
  String? currentPeriodId;

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

  void _subscribeToPrayerStatuses() {
    if (currentPeriodId == null) return;

    // Listen to period document changes
    FirebaseFirestore.instance
        .collection('bulkPeriods')
        .doc(currentPeriodId)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          setState(() {
            completedDays = data['completedDays'] ?? 0;
            completedPrayersCount = data['completedPrayers'] ?? 0;
            totalPrayers = data['totalPrayers'] ?? 0;
            totalDays = data['totalDays'] ?? 0;
          });
        }
      },
      onError: (error) {
        print('Error listening to period changes: $error');
      },
    );

    // Listen to prayer status changes
    FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .collection('prayers')
        .where('periodId', isEqualTo: currentPeriodId)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.docs.isNotEmpty) {
          setState(() {
            _prayerCache = Map.fromEntries(
              snapshot.docs.map((doc) => MapEntry(
                    doc.id,
                    Map<String, bool>.from({
                      'fajr': doc.data()['fajr'] ?? false,
                      'zuhr': doc.data()['zuhr'] ?? false,
                      'asr': doc.data()['asr'] ?? false,
                      'maghrib': doc.data()['maghrib'] ?? false,
                      'isha': doc.data()['isha'] ?? false,
                    }),
                  )),
            );
          });
        }
      },
      onError: (error) {
        print('Error listening to prayer changes: $error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Qaza Prayer Tracker'),
        actions: [
          if (currentPeriodId != null)
            Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$completedDays/$totalDays days',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$completedPrayersCount/$totalPrayers prayers',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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

  Future<void> _loadActivePeriod() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final periodsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection(
              'bulkPeriods') // Changed from 'bulkPeriods' to user's collection
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

        // Immediately subscribe to prayer statuses after loading period
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

  Future<void> _updateProgressCounters() async {
    if (currentPeriodId == null) return;

    try {
      // First check if the period document exists
      final periodDoc = await FirebaseFirestore.instance
          .collection('bulkPeriods')
          .doc(currentPeriodId)
          .get();

      if (!periodDoc.exists) {
        print('Period document not found');
        return;
      }

      QuerySnapshot prayers = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .collection('prayers')
          .where('periodId', isEqualTo: currentPeriodId)
          .get();

      int prayersCount = 0;
      int daysCount = 0;

      for (var doc in prayers.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        int dayCompletedPrayers = 0;

        if (data['fajr'] == true) dayCompletedPrayers++;
        if (data['zuhr'] == true) dayCompletedPrayers++;
        if (data['asr'] == true) dayCompletedPrayers++;
        if (data['maghrib'] == true) dayCompletedPrayers++;
        if (data['isha'] == true) dayCompletedPrayers++;

        prayersCount += dayCompletedPrayers;
        if (dayCompletedPrayers == 5) daysCount++;
      }

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('bulkPeriods')
          .doc(currentPeriodId)
          .update({
        'completedPrayers': prayersCount,
        'completedDays': daysCount,
      });

      // Update local state
      setState(() {
        completedPrayersCount = prayersCount;
        completedDays = daysCount;
      });
    } catch (e) {
      print('Error updating progress counters: $e');
    }
  }

  Future<void> _updatePrayerStatus(
      String prayerId, String prayer, bool value) async {
    try {
      // Update local cache
      setState(() {
        if (_prayerCache[prayerId] == null) {
          _prayerCache[prayerId] = {};
        }
        _prayerCache[prayerId]![prayer] = value;
      });

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .collection('prayers')
          .doc(prayerId)
          .set({prayer: value}, SetOptions(merge: true));

      // Check completion and update progress
      await _updateProgressCounters();
    } catch (e) {
      print('Error updating prayer status: $e');
      // Revert local cache if update fails
      setState(() {
        _prayerCache[prayerId]![prayer] = !value;
      });
    }
  }

  Future<void> _deletePeriod() async {
    try {
      if (currentPeriodId != null) {
        await FirebaseFirestore.instance
            .collection('bulkPeriods')
            .doc(currentPeriodId)
            .delete();

        // Delete all prayers for this period
        final prayers = await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .collection('prayers')
            .where('periodId', isEqualTo: currentPeriodId)
            .get();

        for (var doc in prayers.docs) {
          await doc.reference.delete();
        }

        setState(() {
          currentPeriodId = null;
          completedDays = 0;
          totalDays = 0;
          completedPrayersCount = 0;
          totalPrayers = 0;
          showDatePickers = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Period deleted successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete period: $e')),
      );
    }
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

  bool _canMarkPrayer(int index, String prayer) {
    if (index == 0) return true;

    DailyPrayers previousDay = periodPrayers[index - 1];
    return previousDay.isCompleted();
  }

  void _togglePrayer(int index, String prayer) {
    if (!_canMarkPrayer(index, prayer)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please complete previous day prayers first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      periodPrayers[index].togglePrayer(prayer);
      _checkAndMoveCompleted();
      _loadNextDayIfNeeded();
    });
  }

  void _checkAndMoveCompleted() {
    List<DailyPrayers> completedDays = [];
    List<DailyPrayers> remainingDays = [];

    for (var prayers in periodPrayers) {
      if (prayers.isCompleted()) {
        // Call the method here
        completedDays.add(prayers);
      } else {
        remainingDays.add(prayers);
      }
    }

    if (completedDays.isNotEmpty) {
      // Convert DailyPrayers to CompletedPeriod
      List<CompletedPeriod> completedPeriods = completedDays.map((prayer) {
        return CompletedPeriod(
          startDate: prayer.date,
          endDate: prayer.date, // Assuming single-day completion
          days: 1, // Assuming one day per `DailyPrayers` entry
        );
      }).toList();

      // Add to Firestore
      _bulkPrayerService.addCompletedPrayers(completedPeriods);

      setState(() {
        periodPrayers = remainingDays;
      });
    }
  }

  void _loadNextDayIfNeeded() {
    if (periodPrayers.isEmpty && endDate != null) {
      DateTime lastDate =
          periodPrayers.isEmpty ? startDate! : periodPrayers.last.date;
      DateTime nextDate = lastDate.add(Duration(days: 1));

      if (!nextDate.isAfter(endDate!)) {
        DateTime endLoadDate = nextDate.add(Duration(days: displayDays - 1));
        for (DateTime date = nextDate;
            date.isBefore(endLoadDate.add(Duration(days: 1))) &&
                date.isBefore(endDate!.add(Duration(days: 1)));
            date = date.add(Duration(days: 1))) {
          periodPrayers.add(DailyPrayers(date: date));
        }
        setState(() {});
      }
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

  Widget _buildPrayerCard(DailyPrayer prayer) {
    bool isCompleted = prayer.fajr &&
        prayer.zuhr &&
        prayer.asr &&
        prayer.maghrib &&
        prayer.isha;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('d MMMM yyyy').format(prayer.date),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isCompleted)
                  Text('All Prayers Completed!',
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold))
              ],
            ),
          ),
          if (!isCompleted)
            Wrap(
              children: [
                _buildPrayerCheckbox(
                    prayer, 'Fajr', _getPrayerStatus(prayer.id!, 'fajr')),
                _buildPrayerCheckbox(
                    prayer, 'Zuhr', _getPrayerStatus(prayer.id!, 'zuhr')),
                _buildPrayerCheckbox(
                    prayer, 'Asr', _getPrayerStatus(prayer.id!, 'asr')),
                _buildPrayerCheckbox(
                    prayer, 'Maghrib', _getPrayerStatus(prayer.id!, 'maghrib')),
                _buildPrayerCheckbox(
                    prayer, 'Isha', _getPrayerStatus(prayer.id!, 'isha')),
              ],
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
                                    Text('$name prayer marked as completed'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
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
