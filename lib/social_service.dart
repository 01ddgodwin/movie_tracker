import 'package:cloud_firestore/cloud_firestore.dart';

class SocialService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // This gets called the moment you hit "Save" on your movie log
  Future<void> logMovieToFeed({
    required String currentUserId,
    required String currentUserName,
    required String movieTitle,
    required String movieId,
    required String rating, // Optional: Let friends see what you rated it!
  }) async {
    try {
      await _db.collection('social_feed').add({
        'userId': currentUserId,
        'userName': currentUserName, 
        'movieTitle': movieTitle,
        'movieId': movieId,
        'rating': rating,
        // serverTimestamp perfectly syncs the timeline across all phones
        'timestamp': FieldValue.serverTimestamp(),
        'reactions': {}, // Starts empty, ready for emojis
      });

      print("MOVIE_DEBUG: Successfully broadcasted to the social feed!");
    } catch (e) {
      print("MOVIE_DEBUG: Error posting to feed: $e");
    }
  }
}