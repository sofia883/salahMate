// firebase_service.dart
import 'dart:developer';
import 'bulk_prayers.dart';
import 'services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'individual_prayers.dart';
import 'bulk_prayers.dart';
import 'models.dart';
import 'services.dart';
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Future<UserCredential> signUpWithEmail(String email, String password) async {
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );


      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'localCreatedAt': DateTime.now().toUtc(),
      });

      

      return userCredential;
    } catch (e) {
   throw e;
    }
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Prayer Data Methods
  Future<void> saveIndividualPrayer(QazaNamaz prayer) async {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('individual_prayers')
        .add({
      'prayerName': prayer.prayerName,
      'date': prayer.date.toIso8601String(),
      'isCompleted': prayer.isCompleted,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> savePeriodPrayers(DailyPrayers prayers) async {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('period_prayers')
        .add({
      'date': prayers.date.toIso8601String(),
      'fajr': prayers.fajr,
      'zuhr': prayers.zuhr,
      'asr': prayers.asr,
      'maghrib': prayers.maghrib,
      'isha': prayers.isha,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<QazaNamaz>> getIndividualPrayers() {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('individual_prayers')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return QazaNamaz(
          prayerName: data['prayerName'],
          date: DateTime.parse(data['date']),
          isCompleted: data['isCompleted'],
        );
      }).toList();
    });
  }

  Stream<List<DailyPrayers>> getPeriodPrayers() {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('period_prayers')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return DailyPrayers(
          date: DateTime.parse(data['date']),
          fajr: data['fajr'],
          zuhr: data['zuhr'],
          asr: data['asr'],
          maghrib: data['maghrib'],
          isha: data['isha'],
        );
      }).toList();
    });
  }
}

// Add this LoginScreen widget
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firebaseService = AuthService();
  bool _isLogin = true;

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      try {
        if (_isLogin) {
          await _firebaseService.signInWithEmail(
            _emailController.text,
            _passwordController.text,
          );
        } else {
          await _firebaseService.signUpWithEmail(
            _emailController.text,
            _passwordController.text,
          );
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => IndividualPrayersScreen()),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Login' : 'Sign Up'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter email' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter password' : null,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submitForm,
                child: Text(_isLogin ? 'Login' : 'Sign Up'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                  });
                },
                child: Text(_isLogin
                    ? 'Need an account? Sign Up'
                    : 'Have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
