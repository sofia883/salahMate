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

  int completedDays = 0;

  DateTime? startDate;
  DateTime? endDate;
  List<DailyPrayers> periodPrayers = [];
  List<CompletedPeriod> completedPrayers = [];
  int totalDays = 0;
  int displayDays = 7;
  String? currentPeriodId;

  @override
  void initState() {
    super.initState();
    _loadActivePeriod();
    _subscribeToPrayerStatuses();
    _loadPeriodProgress();
  }

  Future<void> _updatePrayerStatus(
      String prayerId, String prayer, bool value) async {
    try {
      // Update local cache first
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
          .set(_prayerCache[prayerId]!, SetOptions(merge: true));

      // After successful Firestore update, check if all prayers are completed
      bool allCompleted = _checkAllPrayersCompleted(prayerId);
      if (allCompleted) {
        // Update the completed status in a separate collection
        await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .collection('completedPrayers')
            .doc(prayerId)
            .set({
          'completed': true,
          'completedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error updating prayer status: $e');
      // Revert local cache if Firebase update fails
      setState(() {
        _prayerCache[prayerId]![prayer] = !value;
      });
      throw e;
    }
  }

// Add this method to check if all prayers for a day are completed
  bool _checkAllPrayersCompleted(String prayerId) {
    final prayers = _prayerCache[prayerId];
    if (prayers == null) return false;

    return prayers['fajr'] == true &&
        prayers['zuhr'] == true &&
        prayers['asr'] == true &&
        prayers['maghrib'] == true &&
        prayers['isha'] == true;
  }

// Modify _subscribeToPrayerStatuses to handle both active and completed prayers
  void _subscribeToPrayerStatuses() {
    // Listen to active prayers
    FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .collection('prayers')
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _prayerCache = Map.fromEntries(
          snapshot.docs.map((doc) => MapEntry(
                doc.id,
                Map<String, bool>.from(doc.data()),
              )),
        );
      });
    });

    // Listen to completed prayers
    FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .collection('completedPrayers')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final prayerId = doc.id;
        if (_prayerCache[prayerId] != null) {
          setState(() {
            _prayerCache[prayerId]!['fajr'] = true;
            _prayerCache[prayerId]!['zuhr'] = true;
            _prayerCache[prayerId]!['asr'] = true;
            _prayerCache[prayerId]!['maghrib'] = true;
            _prayerCache[prayerId]!['isha'] = true;
          });
        }
      }
    });
  }

  Future<void> _loadPeriodProgress() async {
    if (currentPeriodId == null) return;

    final periodDoc = await FirebaseFirestore.instance
        .collection('bulkPeriods')
        .doc(currentPeriodId)
        .get();

    if (periodDoc.exists) {
      setState(() {
        totalDays = periodDoc.data()?['totalDays'] ?? 0;
        completedDays = periodDoc.data()?['completedDays'] ?? 0;
      });
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
      await _bulkPrayerService.updatePeriodProgress(
        currentPeriodId!,
      );

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

  Future<void> _createNewPeriod() async {
    try {
      final periodId = await _bulkPrayerService.createBulkPeriod(
        startDate: startDate!,
        endDate: endDate!,
      );
      final days = endDate!.difference(startDate!).inDays + 1;
      setState(() {
        currentPeriodId = periodId;
        totalDays = days;
        completedDays = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New prayer period created')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create period: $e')),
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

  void _addToCompletedPeriods(List<DailyPrayers> completed) {
    if (completed.isEmpty) return;

    DateTime periodStart = completed.first.date;
    DateTime periodEnd = completed.last.date;

    completedPrayers.add(CompletedPeriod(
        startDate: periodStart, endDate: periodEnd, days: completed.length));
  }

  Future<void> _loadActivePeriod() async {
    final periods = await _bulkPrayerService.getActivePeriods().first;
    if (periods.isNotEmpty) {
      setState(() => currentPeriodId = periods[0].id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Qaza Prayer Tracker'),
        actions: [
          Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text(
                '$completedDays/$totalDays days',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CompletedPrayersScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDatePickers(),
          Expanded(
            child: currentPeriodId == null
                ? Center(child: Text('Select dates to start tracking prayers'))
                : StreamBuilder<List<DailyPrayer>>(
                    stream: _bulkPrayerService
                        .getActivePeriodPrayers(currentPeriodId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(child: Text('No prayers found'));
                      }

                      return ListView.builder(
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) {
                          final prayer = snapshot.data![index];
                          return _buildPrayerCard(prayer);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
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
