import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'individual_prayers.dart';
import 'bulk_prayers.dart';
import 'how_much_remind_screen.dart';
import 'deeds_tracker_screen.dart';
import 'setting_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure widgets are initialized
  await Firebase.initializeApp(); // Initialize Firebase
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Prayer Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final FirebaseAuth _auth = FirebaseAuth.instance;

    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return QazaNamazTracker();
        } else {
          return LoginScreen();
        }
      },
    );
  }
}

class QazaNamazTracker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
      title: 'Qaza Namaz Tracker',
      theme: ThemeData(primarySwatch: Colors.teal),
      routes: {
        '/individualPrayer': (context) => IndividualPrayersScreen(),
        '/bulkPrayer': (context) => QazaPeriodPage(),
        // Add these when implemented:
        '/deedsTracker': (context) => DeedsTrackerScreen(),
        '/myReminds': (context) => HowMuchRemindScreen(),
        '/settings': (context) => SettingsScreen(),
      },
      // Handle unknown routes gracefully
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => ErrorScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  final List<Map<String, dynamic>> features = [
    {
      'title': 'Individual Prayer',
      'icon': Icons.person,
      'route': '/individualPrayer'
    },
    {'title': 'Bulk Prayer', 'icon': Icons.group, 'route': '/bulkPrayer'},
    {
      'title': 'Deeds Tracker',
      'icon': Icons.track_changes,
      'route': '/deedsTracker' // Add implementation later
    },
    {
      'title': 'What I know and practice',
      'icon': Icons.query_stats,
      'route': '/myReminds' // Add implementation later
    },
    {'title': 'Settings', 'icon': Icons.settings, 'route': '/settings'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer Tracker Home'),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // Two items per row
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: features.length,
          itemBuilder: (context, index) {
            final feature = features[index];
            return GestureDetector(
              onTap: () {
                // Check if the route exists
                if (Navigator.canPop(context) ||
                    ModalRoute.of(context)?.settings.name != null) {
                  Navigator.pushNamed(context, feature['route']);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Feature "${feature['title']}" is not implemented yet.'),
                    ),
                  );
                }
              },
              child: Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                color: Colors.teal.shade100,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      feature['icon'],
                      size: 50,
                      color: Colors.teal.shade900,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      feature['title'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error'),
      ),
      body: const Center(
        child: Text('The page you are trying to access will come soon.'),
      ),
    );
  }
}
