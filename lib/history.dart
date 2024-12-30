import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'services.dart';

class HistoryPage extends StatefulWidget {
  final PrayerService prayerService;

  HistoryPage({
    required this.prayerService,
  });

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final PrayerService _prayerService =
      PrayerService(); // Updated to use PrayerService
  List<QazaNamaz> historyList = [];

  @override
  void initState() {
    super.initState();
    widget.prayerService.getHistory().listen((prayers) {
      setState(() {
        // Remove duplicates locally if needed
        final seen = <String>{};
        historyList = prayers.where((prayer) {
          final key =
              '${prayer.prayerName}-${DateFormat('yyyy-MM-dd').format(prayer.date)}';
          return seen.add(key); // Only add if not already seen
        }).toList();
      });
    });
  }

  void _handleDelete(QazaNamaz namaz) async {
    await widget.prayerService.deleteFromHistory(namaz.id!);
   if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Prayer moved to history!'),
      backgroundColor: Colors.green,
    ),
  );
}

  }

  void _clearAllHistory() async {
    await widget.prayerService.clearAllHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('All history cleared successfully'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('History of Qaza Namaz'),
          actions: [
            IconButton(
              icon: Icon(Icons.restore_from_trash),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => DeletedHistoryBottomSheet(
                      prayerService: widget.prayerService),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_forever),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Clear All History'),
                      content:
                          Text('Are you sure you want to clear all history?'),
                      actions: [
                        TextButton(
                          child: Text('Cancel'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        TextButton(
                          child: Text('Clear All'),
                          onPressed: () {
                            widget.prayerService.clearAllHistory();
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
        body: historyList.isEmpty
            ? Center(child: Text('No history available'))
            : ListView.builder(
                itemCount: historyList.length,
                itemBuilder: (context, index) {
                  final namaz = historyList[index];
                  return Dismissible(
                    key: Key(namaz.id ?? ''),
                    background: Container(
                      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_sweep, color: Colors.white),
                              SizedBox(height: 4),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      return await showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            title: Text('Delete Prayer'),
                            content: Text(
                                'Are you sure you want to delete this prayer?'),
                            actions: [
                              TextButton(
                                child: Text('Cancel'),
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: Text('Delete'),
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    onDismissed: (_) => _handleDelete(namaz),
                    child: Card(
                      elevation: 2,
                      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.mosque,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        title: Text(
                          namaz.prayerName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 4),
                            Text(
                              'Date: ${formatDateWithSuffix(namaz.date)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline),
                          color: Colors.red[400],
                          onPressed: () async {
                            final delete = await showDialog<bool>(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  title: Text('Delete Prayer'),
                                  content: Text(
                                      'Are you sure you want to delete this prayer?'),
                                  actions: [
                                    TextButton(
                                      child: Text('Cancel'),
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: Text('Delete'),
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                    ),
                                  ],
                                );
                              },
                            );

                            if (delete == true) {
                              _handleDelete(namaz);
                            }
                          },
                        ),
                      ),
                    ),
                  );
                },
              ));
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
