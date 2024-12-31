import 'package:flutter/material.dart';
import 'models.dart';
import 'package:intl/intl.dart';
import 'history.dart';
import 'services.dart';

class IndividualPrayersScreen extends StatefulWidget {
  @override
  _IndividualPrayersScreenState createState() =>
      _IndividualPrayersScreenState();
}

class _IndividualPrayersScreenState extends State<IndividualPrayersScreen> {
  final PrayerService _prayerService =
      PrayerService(); // Updated to use PrayerService
  List<QazaNamaz> qazaNamazList = [];
  List<QazaNamaz> historyList = [];

  bool _isDuplicatePrayer(String prayerName, DateTime date) {
    // Check current list
    bool isInCurrentList = qazaNamazList.any((prayer) =>
        prayer.prayerName == prayerName &&
        prayer.date.year == date.year &&
        prayer.date.month == date.month &&
        prayer.date.day == date.day);

    return isInCurrentList;
  }

  void _addQazaNamaz(String prayerName, DateTime date) async {
    // First check current list
    if (_isDuplicatePrayer(prayerName, date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This prayer is already in your current list'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Then check history
    final historyPrayers = await _prayerService.getHistoryOnce();
    bool isInHistory = historyPrayers.any((prayer) =>
        prayer.prayerName == prayerName &&
        prayer.date.year == date.year &&
        prayer.date.month == date.month &&
        prayer.date.day == date.day);

    if (isInHistory) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Prayer Already Completed'),
            content: Text(
                'This prayer is already in your history as completed. Would you like to add it again?'),
            actions: <Widget>[
              TextButton(
                child: Text('No'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text('Yes'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  final prayer = QazaNamaz(prayerName: prayerName, date: date);
                  await _prayerService.addPrayer(prayer);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Prayer added to your list'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
            ],
          );
        },
      );
      return;
    }

    // If not in either list, add the prayer
    final prayer = QazaNamaz(prayerName: prayerName, date: date);
    await _prayerService.addPrayer(prayer);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Prayer added successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // Add this debug print
    print('Current user ID: ${_prayerService.currentUserId}');

    if (_prayerService.currentUserId == null) {
      print('No user logged in!');
      return;
    }

    _prayerService.getPrayers().listen(
      (prayers) {
        print('Received ${prayers.length} prayers'); // Debug print
        setState(() {
          qazaNamazList = prayers;
        });
      },
      onError: (error) {
        print('Error getting prayers: $error'); // Debug print
      },
    );
  }

  void _toggleCompletion(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Prayer Completion'),
          content: Text('Had you prayed ${qazaNamazList[index].prayerName}?'),
          actions: <Widget>[
            TextButton(
              child: Text('No'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Yes'),
              onPressed: () async {
                final prayer = qazaNamazList[index];
                prayer.isCompleted = true;
                await _prayerService.updatePrayer(prayer);
                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${prayer.prayerName} marked as completed!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _deleteFromHistory(QazaNamaz prayer) async {
    await _prayerService.deleteFromHistory(prayer.id!);
  }

  void _clearAllHistory() async {
    await _prayerService.clearAllHistory();
  }

  void _moveToHistory(int index) async {
    final prayer = qazaNamazList[index];
    await _prayerService.movePrayerToHistory(prayer);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved to history!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openAddPrayerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AddQazaNamazDialog(onAdd: _addQazaNamaz),
    );
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryPage(
          prayerService: _prayerService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Qaza Namaz Tracker'),
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            onPressed: _navigateToHistory,
          ),
        ],
      ),
      body: qazaNamazList.isEmpty
          ? Center(child: Text('No Qaza Namaz added yet.'))
          : ListView.builder(
              itemCount: qazaNamazList.length,
              itemBuilder: (context, index) {
                final namaz = qazaNamazList[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(
                          namaz.prayerName,
                          style: TextStyle(
                            color:
                                _isDuplicatePrayer(namaz.prayerName, namaz.date)
                                    ? Colors.green
                                    : null,
                          ),
                        ),
                        subtitle:
                            Text('Date: ${formatDateWithSuffix(namaz.date)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: namaz.isCompleted,
                              onChanged: (_) {
                                if (!namaz.isCompleted) {
                                  _toggleCompletion(index);
                                }
                              },
                            ),
                            if (namaz.isCompleted)
                              TextButton(
                                onPressed: () => _moveToHistory(index),
                                child: Text('Move to History'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPrayerDialog,
        child: Icon(Icons.add),
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

class AddQazaNamazDialog extends StatefulWidget {
  final Function(String, DateTime) onAdd;

  AddQazaNamazDialog({required this.onAdd});

  @override
  _AddQazaNamazDialogState createState() => _AddQazaNamazDialogState();
}

class _AddQazaNamazDialogState extends State<AddQazaNamazDialog> {
  final _formKey = GlobalKey<FormState>();
  String _selectedPrayer = 'Fajr';
  DateTime _selectedDate = DateTime.now();

  void _submit() {
    if (_formKey.currentState!.validate()) {
      widget.onAdd(_selectedPrayer, _selectedDate);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Qaza Namaz'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedPrayer,
              items: ['Fajr', 'Zuhr', 'Asar', 'Maghrib', 'Isha']
                  .map((prayer) => DropdownMenuItem(
                        value: prayer,
                        child: Text(prayer),
                      ))
                  .toList(),
              onChanged: (value) => setState(() {
                _selectedPrayer = value!;
              }),
              decoration: InputDecoration(labelText: 'Prayer Name'),
            ),
            SizedBox(height: 10),
            TextFormField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () async {
                final selectedDate = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (selectedDate != null) {
                  setState(() {
                    _selectedDate = selectedDate;
                  });
                }
              },
              validator: (value) =>
                  _selectedDate == null ? 'Please pick a date' : null,
              controller: TextEditingController(
                  text: _selectedDate.toLocal().toString().split(' ')[0]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: Text('Add')),
      ],
    );
  }
}
