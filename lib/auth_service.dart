import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/app_sign_out.dart';

class AuthService {
  static final Map<String, String> _roleCache = {};

  static void cacheRole(String uid, String role) {
    if (uid.isNotEmpty) {
      _roleCache[uid] = role.toLowerCase();
    }
  }

  static String? getCachedRole(String uid) {
    return uid.isNotEmpty ? _roleCache[uid] : null;
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<User?> registerWithEmail(
    String email,
    String password,
    String fullName, {
    String role = 'student',
    String? orgId, // required when role == 'org'
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email, password: password,
      );
      final Map<String, dynamic> data = {
        'uid': result.user!.uid,
        'email': email,
        'fullName': fullName,
        'role': role,
        'createdAt': Timestamp.now(),
      };
      if (orgId != null && orgId.isNotEmpty) data['orgId'] = orgId;
      await _firestore.collection('users').doc(result.user!.uid).set(data);
      return result.user;
    } catch (_) {
      return null;
    }
  }

  Future<User?> loginWithEmail(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email, password: password,
      );
      return result.user;
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        final role = (data?['role'] as String?)?.toLowerCase() ?? 'student';
        cacheRole(uid, role);
        return role;
      }
      return 'student';
    } catch (e) {
      return 'student';
    }
  }

  /// The role exactly as recorded on `users/{uid}` — `null` when there is no
  /// such doc, no `role` field, or the read failed.
  ///
  /// [getUserRole] answers "what should I show this person" and guesses
  /// 'student' when it can't tell, which is the right default for routing. A
  /// login gate needs the opposite: it has to distinguish "this is a student"
  /// from "I could not find out", because treating the second as the first is
  /// how a guest ends up signed in on the student screen.
  Future<String?> getRecordedRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      final role = (doc.data()?['role'] as String?)?.toLowerCase();
      if (role == null || role.isEmpty) return null;
      cacheRole(uid, role);
      return role;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.exists ? doc.data() as Map<String, dynamic>? : null;
    } catch (e) {
      return null;
    }
  }

  // Delegates so this and every inline logout button share one implementation
  // (and one push-token cleanup).
  Future<void> logout() => AppSignOut.signOut(_auth);

  Future<bool> needsPasswordChange(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;
      final data = doc.data() as Map<String, dynamic>? ?? {};
      return data['isFirstLogin'] == true ||
          data['mustChangePassword'] == true ||
          data['needsPasswordChange'] == true ||
          data['firstLogin'] == true;
    } catch (_) {
      return false;
    }
  }

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signInAsGuest() async {
  try {
    final result = await _auth.signInAnonymously();
    return result.user;
  } on FirebaseAuthException catch (e) {
    print('❌ Guest login error: ${e.message}');
    return null;
  } catch (e) {
    print('❌ Guest login error: $e');
    return null;
  }
}
}