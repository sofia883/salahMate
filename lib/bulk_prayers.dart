import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class QazaPeriodPage extends StatefulWidget {
  @override
  _QazaPeriodPageState createState() => _QazaPeriodPageState();
}

class _QazaPeriodPageState extends State<QazaPeriodPage> {
  DateTime? startDate;
  DateTime? endDate;
  List<DailyPrayers> periodPrayers = [];
  List<CompletedPeriod> completedPrayers = [];
  int totalDays = 0;
  int displayDays = 7;

  void _calculatePeriodPrayers() {
    if (startDate == null || endDate == null) return;

    periodPrayers.clear();
    totalDays = endDate!.difference(startDate!).inDays + 1;

    // Load first 7 days only
    DateTime endLoadDate = startDate!.add(Duration(days: displayDays - 1));
    for (DateTime date = startDate!;
        date.isBefore(endLoadDate.add(Duration(days: 1))) &&
            date.isBefore(endDate!.add(Duration(days: 1)));
        date = date.add(Duration(days: 1))) {
      periodPrayers.add(DailyPrayers(date: date));
    }
    setState(() {});
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
        completedDays.add(prayers);
      } else {
        remainingDays.add(prayers);
      }
    }

    if (completedDays.isNotEmpty) {
      _addToCompletedPeriods(completedDays);
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
  Widget build(BuildContext context) {
    int completedDays =
        completedPrayers.fold(0, (sum, period) => sum + period.days);

    return Scaffold(
      appBar: AppBar(
        title: Text('Qaza Period Tracker'),
        actions: [
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '$completedDays/$totalDays',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CompletedPrayersPage(
                    completedPeriods: completedPrayers,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
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
                      text: startDate?.toLocal().toString().split(' ')[0] ?? '',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          startDate = date;
                          if (endDate != null) _calculatePeriodPrayers();
                        });
                      }
                    },
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
                      text: endDate?.toLocal().toString().split(' ')[0] ?? '',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          endDate = date;
                          if (startDate != null) _calculatePeriodPrayers();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: periodPrayers.isEmpty
                ? Center(child: Text('Select dates to see prayers'))
                : ListView.builder(
                    itemCount: periodPrayers.length,
                    itemBuilder: (context, index) {
                      final dailyPrayer = periodPrayers[index];
                      return Card(
                        margin:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                formatDateWithSuffix(dailyPrayer.date),
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Wrap(
                              children: [
                                _buildPrayerCheckbox(
                                    index, 'Fajr', dailyPrayer.fajr),
                                _buildPrayerCheckbox(
                                    index, 'Zuhr', dailyPrayer.zuhr),
                                _buildPrayerCheckbox(
                                    index, 'Asr', dailyPrayer.asr),
                                _buildPrayerCheckbox(
                                    index, 'Maghrib', dailyPrayer.maghrib),
                                _buildPrayerCheckbox(
                                    index, 'Isha', dailyPrayer.isha),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerCheckbox(int index, String prayer, bool value) {
    return Container(
      width: MediaQuery.of(context).size.width / 2 - 16,
      child: CheckboxListTile(
        title: Text(prayer),
        value: value,
        onChanged: (_) => _togglePrayer(index, prayer),
        dense: true,
      ),
    );
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

class DailyPrayers {
  final DateTime date;
  bool fajr;
  bool zuhr;
  bool asr;
  bool maghrib;
  bool isha;

  DailyPrayers({
    required this.date,
    this.fajr = false,
    this.zuhr = false,
    this.asr = false,
    this.maghrib = false,
    this.isha = false,
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
}

class CompletedPrayersPage extends StatelessWidget {
  final List<CompletedPeriod> completedPeriods;

  CompletedPrayersPage({required this.completedPeriods});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Completed Prayers'),
      ),
      body: ListView.builder(
        itemCount: completedPeriods.length,
        itemBuilder: (context, index) {
          final period = completedPeriods[index];
          final isSameMonth = period.startDate.month == period.endDate.month &&
              period.startDate.year == period.endDate.year;

          String periodText = isSameMonth
              ? '${DateFormat('MMMM yyyy').format(period.startDate)}'
              : '${formatDateWithSuffix(period.startDate)} to ${formatDateWithSuffix(period.endDate)}';

          return ListTile(
            title: Text(periodText),
            subtitle: Text('${period.days} days completed'),
          );
        },
      ),
    );
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
    return '${DateFormat('d').format(date)}$suffix ${DateFormat('MMMM yyyy').format(date)}';
  }
}
