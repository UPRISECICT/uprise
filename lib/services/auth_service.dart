// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import 'push_notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign in
  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Sign out
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await PushNotificationService.unregister(uid);
    await _auth.signOut();
  }

  // Admin can archive a student account (student_accounts.dart) — checked
  // right after sign-in so an archived student is bounced immediately
  // instead of getting signed into Firebase Auth with nowhere valid to go.
  Future<bool> isArchived(String userId) async {
    final doc = await _firestore.collection(FirebaseConstants.usersCollection).doc(userId).get();
    if (!doc.exists) return false;
    return doc.data()?['archived'] == true;
  }

  // Check if user needs to change password (first login)
  Future<bool> needsPasswordChange(String userId) async {
    final doc = await _firestore.collection(FirebaseConstants.usersCollection).doc(userId).get();
    if (!doc.exists) return false;
    final data = doc.data();
    return (data?['isFirstLogin'] == true) ||
        (data?['mustChangePassword'] == true) ||
        (data?['needsPasswordChange'] == true) ||
        (data?['firstLogin'] == true);
  }

  // Change password
  Future<void> changePassword(String userId, String newPassword, {bool isFirstLogin = false}) async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.updatePassword(newPassword);
      
      // Update Firestore to mark password-change flags as false
      if (isFirstLogin) {
        await _firestore.collection(FirebaseConstants.usersCollection).doc(userId).update({
          'isFirstLogin': false,
          'mustChangePassword': false,
          'needsPasswordChange': false,
          'firstLogin': false,
        });
      }
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Get current user data
  Future<UserModel?> getCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    
    final doc = await _firestore.collection(FirebaseConstants.usersCollection).doc(user.uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }
}