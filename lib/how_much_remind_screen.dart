
// How Much I Remind Screen
import 'package:flutter/material.dart';

class HowMuchRemindScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('How Much I Remind'),
        backgroundColor: Colors.teal,
      ),
      body: Center(
        child: Text(
          'How Much I Remind Content Goes Here',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
