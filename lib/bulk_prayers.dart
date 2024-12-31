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
  DateTime? startDate;
  DateTime? endDate;
  List<DailyPrayers> periodPrayers = [];
  List<CompletedPeriod> completedPrayers = [];
  int totalDays = 0;
  int displayDays = 7;
  String? currentPeriodId;

  // @override
  // void initState() {
  //   super.initState();
  //   _loadInitialData();
  // }

  // Future<void> _loadInitialData() async {
  //   // Load active period if exists
  //   final activePeriodList = await _bulkPrayerService
  //       .getActivePeriods()
  //       .first; // Get the first item from the stream
  //   if (activePeriodList.isNotEmpty) {
  //     final activePeriod =
  //         activePeriodList[0]; // Now activePeriod is a BulkPeriod object
  //     setState(() {
  //       currentPeriodId = activePeriod.id; // Access the id of the active period
  //     });
  //   }

  //   // Subscribe to completed prayers stream
  //   _bulkPrayerService.getCompletedPrayers().listen((completed) {
  //     setState(() {
  //       completedPrayers = completed;
  //     });
  //   });
  // }

  // void _calculatePeriodPrayers() async {
  //   if (startDate == null || endDate == null) return;

  //   try {
  //     // Create period in Firebase
  //     final periodId = await _bulkPrayerService.createBulkPeriod(
  //       startDate: startDate!,
  //       endDate: endDate!,
  //     );

  //     // Set current period ID
  //     setState(() {
  //       currentPeriodId = periodId;
  //     });

  //     // Generate daily prayers
  //     final days = endDate!.difference(startDate!).inDays + 1;
  //     final prayers = List.generate(days, (index) {
  //       return DailyPrayers(
  //         date: startDate!.add(Duration(days: index)),
  //         periodId: periodId,
  //       );
  //     });

  //     await _bulkPrayerService.addPeriodPrayers(prayers);

  //     setState(() {
  //       periodPrayers = prayers;
  //     });

  //     ScaffoldMessenger.of(context)
  //         .showSnackBar(SnackBar(content: Text('Successfully added prayers')));
  //   } catch (e) {
  //     ScaffoldMessenger.of(context)
  //         .showSnackBar(SnackBar(content: Text('Failed to add prayers: $e')));
  //   }
  // }

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

  @override
  void initState() {
    super.initState();
    _loadActivePeriod();
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
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              DateFormat('EEEE, MMMM d, yyyy').format(prayer.date),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Wrap(
            children: [
              _buildPrayerCheckbox(prayer, 'Fajr', prayer.fajr),
              _buildPrayerCheckbox(prayer, 'Zuhr', prayer.zuhr),
              _buildPrayerCheckbox(prayer, 'Asr', prayer.asr),
              _buildPrayerCheckbox(prayer, 'Maghrib', prayer.maghrib),
              _buildPrayerCheckbox(prayer, 'Isha', prayer.isha),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerCheckbox(DailyPrayer prayer, String name, bool value) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 16,
      child: CheckboxListTile(
        title: Text(name),
        value: value,
        onChanged: (bool? newValue) {
          if (newValue != null) {
            _bulkPrayerService.updatePrayerStatus(
              prayer.id!,
              name,
              newValue,
            );
          }
        },
      ),
    );
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

  Future<void> _createNewPeriod() async {
    try {
      final periodId = await _bulkPrayerService.createBulkPeriod(
        startDate: startDate!,
        endDate: endDate!,
      );
      setState(() => currentPeriodId = periodId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New prayer period created')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create period: $e')),
      );
    }
  }
  // Widget _buildPrayerCheckbox(int index, String prayer, bool value) {
  //   return Container(
  //     width: MediaQuery.of(context).size.width / 2 - 16,
  //     child: CheckboxListTile(
  //       title: Text(prayer),
  //       value: value,
  //       onChanged: (_) => _togglePrayer(index, prayer),
  //       dense: true,
  //     ),
  //   );
  // }

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

// class DailyPrayers {
//   final DateTime date;
//   bool fajr;
//   bool zuhr;
//   bool asr;
//   bool maghrib;
//   bool isha;
//   bool isCompleted;

//   DailyPrayers(
//       {required this.date,
//       this.fajr = false,
//       this.zuhr = false,
//       this.asr = false,
//       this.maghrib = false,
//       this.isha = false,
//       this.isCompleted = false});

//   void togglePrayer() {
//     isCompleted = !isCompleted;
//   }

//   factory DailyPrayers.fromMap(Map<String, dynamic> map) {
//     return DailyPrayers(
//       date: (map['date'] as Timestamp).toDate(),
//       fajr: map['fajr'] ?? false,
//       zuhr: map['zuhr'] ?? false,
//       asr: map['asr'] ?? false,
//       maghrib: map['maghrib'] ?? false,
//       isha: map['isha'] ?? false,
//       isCompleted: map['isCompleted'] ?? false, // Add this
//     );
//   }

//   Map<String, dynamic> toMap() {
//     return {
//       'date': Timestamp.fromDate(date),
//       'fajr': fajr,
//       'zuhr': zuhr,
//       'asr': asr,
//       'maghrib': maghrib,
//       'isha': isha,
//     };
//   }
// }

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
