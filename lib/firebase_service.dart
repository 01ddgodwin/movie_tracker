import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart'; // <-- NEW IMPORT

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Creates a movie night plan and shares it with invited friends
  Future<void> createOrUpdatePlan(Map<String, dynamic> planData) async {
    if (currentUser == null) return;

    try {
      final userRef = _firestore.collection('users').doc(currentUser!.uid);
      final docSnapshot = await userRef.get();

      // 1. Save it to your own "plans" list
      List<dynamic> currentPlans = [];
      if (docSnapshot.exists && docSnapshot.data()!.containsKey('plans')) {
        currentPlans = List<dynamic>.from(docSnapshot.data()!['plans']);
      }

      // Remove the old version if you are updating an existing plan
      currentPlans.removeWhere((p) => p['id'] == planData['id']);
      currentPlans.add(planData);

      await userRef.update({'plans': currentPlans});

      // 2. Push the invite to your friends' "sharedPlans" list
      final List<dynamic> invitedUids = planData['invitedUids'] ?? [];
      for (String uid in invitedUids) {
        final friendRef = _firestore.collection('users').doc(uid);
        final friendSnapshot = await friendRef.get();

        if (friendSnapshot.exists) {
          List<dynamic> sharedPlans = [];
          if (friendSnapshot.data()!.containsKey('sharedPlans')) {
            sharedPlans = List<dynamic>.from(
              friendSnapshot.data()!['sharedPlans'],
            );
          }

          // Remove the old version and add the new one
          sharedPlans.removeWhere((p) => p['id'] == planData['id']);
          sharedPlans.add(planData);

          await friendRef.update({'sharedPlans': sharedPlans});
        }
      }
    } catch (e) {
      debugPrint('Error creating/updating plan: $e');
      throw Exception('Failed to save plan to the cloud.');
    }
  }

  // --- FRIEND CODE GENERATOR ---
  String _generateFriendCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return 'FILM-' +
        List.generate(6, (index) => chars[rnd.nextInt(chars.length)]).join();
  }

  // --- PLAN MANAGEMENT ---
  Future<void> savePlan(Map<String, dynamic> planData) async {
    if (currentUser == null) return;
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .get();
      if (userDoc.exists) {
        List plans = List.from(userDoc.data()?['plans'] ?? []);
        // Remove it if it exists (for editing)
        plans.removeWhere((p) => p['id'] == planData['id']);
        // Add the new/updated plan
        plans.add(planData);
        await _firestore.collection('users').doc(currentUser!.uid).update({
          'plans': plans,
        });
      }
    } catch (e) {
      debugPrint('Error saving plan: $e');
    }
  }

  Future<void> deletePlan(String planId) async {
    if (currentUser == null) return;
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .get();
      if (userDoc.exists) {
        List plans = List.from(userDoc.data()?['plans'] ?? []);
        plans.removeWhere((p) => p['id'] == planId);
        await _firestore.collection('users').doc(currentUser!.uid).update({
          'plans': plans,
        });
      }
    } catch (e) {
      debugPrint('Error deleting plan: $e');
    }
  }

  Future<void> leavePlan(String planId) async {
    if (currentUser == null) return;
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .get();
      if (userDoc.exists) {
        List sharedPlans = List.from(userDoc.data()?['sharedPlans'] ?? []);
        sharedPlans.removeWhere((p) => p['id'] == planId);
        await _firestore.collection('users').doc(currentUser!.uid).update({
          'sharedPlans': sharedPlans,
        });
      }
    } catch (e) {
      debugPrint('Error leaving plan: $e');
    }
  }

  // --- EMAIL & PASSWORD AUTH ---

  Future<User?> signUp(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Sign up failed');
    }
  }

  Future<User?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Sign in failed');
    }
  }

  Future<User?> signInWithGoogleWeb() async {
    try {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      if (kIsWeb) {
        UserCredential userCredential = await _auth.signInWithPopup(
          googleProvider,
        );
        return userCredential.user;
      } else {
        UserCredential userCredential = await _auth.signInWithProvider(
          googleProvider,
        );
        return userCredential.user;
      }
    } catch (e) {
      debugPrint('Error during Google Sign-In: $e');
      throw Exception('Google Sign-In failed: $e');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // --- PUSH NOTIFICATIONS ---
  Future<void> setupPushNotifications() async {
    if (currentUser == null) return;

    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permission from the OS
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Get the unique device token
      String? token = await messaging.getToken();

      if (token != null) {
        // Save the token to your user document so the cloud knows where to send alerts
        await _db.collection('users').doc(currentUser!.uid).set({
          'pushToken': token,
        }, SetOptions(merge: true));

        debugPrint("MOVIE_DEBUG: Push token saved successfully! ($token)");
      }

      // If the OS rotates the token, update it automatically
      messaging.onTokenRefresh.listen((newToken) {
        _db.collection('users').doc(currentUser!.uid).set({
          'pushToken': newToken,
        }, SetOptions(merge: true));
      });
    }
  }

  // --- CLOUD SYNC LOGIC ---

  Future<void> syncToCloud({
    required List<dynamic> watchlist,
    required List<dynamic> diary,
    required List<dynamic> tickets,
  }) async {
    if (currentUser == null) return;
    try {
      final userRef = _db.collection('users').doc(currentUser!.uid);

      await userRef.set({
        'lastSynced': FieldValue.serverTimestamp(),
        'watchlist': watchlist,
        'tickets': tickets,
      }, SetOptions(merge: true));

      final batch = _db.batch();
      for (var entry in diary) {
        if (entry is Map) {
          final Map<String, dynamic> mapEntry = Map<String, dynamic>.from(
            entry,
          );
          final String docId = mapEntry['id'].toString();
          final diaryRef = userRef.collection('diary').doc(docId);
          batch.set(diaryRef, mapEntry);
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error syncing to Firestore: $e');
    }
  }

  Future<void> deleteDiaryEntry(String id) async {
    if (currentUser == null) return;
    try {
      await _db
          .collection('users')
          .doc(currentUser!.uid)
          .collection('diary')
          .doc(id)
          .delete();
    } catch (e) {
      debugPrint('Error deleting diary entry: $e');
    }
  }

  // --- FRIENDS SYSTEM ---

  Future<String?> addFriendByCode(String code) async {
    if (currentUser == null) return "Sign in to add friends!";
    try {
      final codeDoc = await _db
          .collection('friendCodes')
          .doc(code.toUpperCase())
          .get();
      if (!codeDoc.exists) return "Code not found. Double-check and try again.";

      final fData = codeDoc.data() as Map<String, dynamic>;
      final friendUid = fData['uid'];

      if (friendUid == currentUser!.uid) return "That's your own code! 😄";

      await _db
          .collection('users')
          .doc(currentUser!.uid)
          .collection('friends')
          .doc(friendUid)
          .set({
            'uid': friendUid,
            'displayName': fData['displayName'] ?? 'Friend',
            'photoURL': fData['photoURL'] ?? '',
            'addedAt': FieldValue.serverTimestamp(),
          });
      return null; // Success
    } catch (e) {
      return "Error adding friend. Check your connection.";
    }
  }

  Future<void> removeFriend(String friendUid) async {
    if (currentUser == null) return;
    try {
      await _db
          .collection('users')
          .doc(currentUser!.uid)
          .collection('friends')
          .doc(friendUid)
          .delete();
    } catch (e) {
      debugPrint("Error removing friend: $e");
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriendDiary(String friendUid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(friendUid)
          .collection('diary')
          .get();
      return snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  // --- PULL CLOUD DATA TO LOCAL ---
  Future<Map<String, dynamic>?> fetchUserData() async {
    if (currentUser == null) return null;

    final String myUid = currentUser!.uid.trim();

    try {
      final userRef = _db.collection('users').doc(myUid);

      // 1. Fetch your main document
      DocumentSnapshot doc = await userRef.get();
      Map<String, dynamic> userData = {};

      if (doc.exists && doc.data() != null) {
        userData = Map<String, dynamic>.from(
          doc.data() as Map<String, dynamic>,
        );

        // Auto-generate Friend Code if missing
        if (userData['friendCode'] == null ||
            userData['friendCode'].toString().isEmpty) {
          final newCode = _generateFriendCode();
          await userRef.set({'friendCode': newCode}, SetOptions(merge: true));
          await _db.collection('friendCodes').doc(newCode).set({
            'uid': myUid,
            'displayName': currentUser!.displayName ?? 'Movie Fan',
            'photoURL': currentUser!.photoURL ?? '',
          });
          userData['friendCode'] = newCode;
        }
      }

      // 2. Fetch your Diary
      final diaryQuery = await userRef.collection('diary').get();
      userData['diary'] = diaryQuery.docs.map((d) => d.data()).toList();

      // 3. FETCH FRIENDS & SHARED PLANS
      List<dynamic> sharedPlans = [];
      List<dynamic> friendTickets = [];
      List<dynamic> friendsList = []; // Add friends to returned data

      try {
        final friendsSnap = await userRef.collection('friends').get();

        for (var fDoc in friendsSnap.docs) {
          final friendUid = fDoc.id.trim();
          final fData = fDoc.data() as Map<String, dynamic>? ?? {};
          fData['uid'] = friendUid;
          friendsList.add(fData); // Add friend to local list

          final friendName = fData['displayName'] ?? 'Friend';
          final friendAvatar = fData['photoURL'] ?? '';

          final friendDoc = await _db.collection('users').doc(friendUid).get();

          if (friendDoc.exists && friendDoc.data() != null) {
            final friendData = friendDoc.data() as Map<String, dynamic>;

            if (friendData['plans'] is List) {
              for (var plan in friendData['plans']) {
                if (plan is Map && plan['invitees'] is List) {
                  final inviteList = (plan['invitees'] as List)
                      .map((e) => e.toString().trim())
                      .toList();
                  if (inviteList.contains(myUid))
                    sharedPlans.add(Map<String, dynamic>.from(plan));
                }
              }
            }

            if (friendData['tickets'] is List) {
              for (var ticket in friendData['tickets']) {
                if (ticket is Map) {
                  final tCopy = Map<String, dynamic>.from(ticket);
                  tCopy['addedBy'] = friendName;
                  tCopy['addedByAvatar'] = friendAvatar;
                  friendTickets.add(tCopy);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning friends data: $e');
      }

      userData['friendsList'] = friendsList;
      userData['sharedPlans'] = sharedPlans;
      userData['friendTickets'] = friendTickets;
      return userData;
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
    return null;
  }
}
