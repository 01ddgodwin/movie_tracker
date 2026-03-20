import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class SocialFeedScreen extends StatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseService _firebaseService = FirebaseService();

  // Helper to format timestamps (e.g., "2h ago")
  String _timeAgo(DateTime d) {
    Duration diff = DateTime.now().difference(d);
    if (diff.inDays > 365) return "${(diff.inDays / 365).floor()}y ago";
    if (diff.inDays > 30) return "${(diff.inDays / 30).floor()}mo ago";
    if (diff.inDays > 0) return "${diff.inDays}d ago";
    if (diff.inHours > 0) return "${diff.inHours}h ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes}m ago";
    return "Just now";
  }

  // Updates the post with an emoji reaction
  Future<void> _reactToPost(String docId, String emoji) async {
    final user = _firebaseService.currentUser;
    if (user == null) return;

    final docRef = _db.collection('social_feed').doc(docId);

    // SetOptions(merge: true) ensures we don't delete other friends' reactions
    await docRef.set({
      'reactions': {user.displayName ?? 'Friend': emoji},
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🌐 Friend Feed',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Listen to the feed collection, newest posts at the top
        stream: _db
            .collection('social_feed')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Error loading feed.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFE50914)),
            );
          }

          final posts = snapshot.data!.docs;

          if (posts.isEmpty) {
            return const Center(
              child: Text(
                "It's quiet here. Go watch a movie!",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index].data() as Map<String, dynamic>;
              final docId = posts[index].id;

              final timestamp = post['timestamp'] as Timestamp?;
              final date = timestamp != null
                  ? timestamp.toDate()
                  : DateTime.now();

              final double rating =
                  double.tryParse(post['rating'].toString()) ?? 0.0;
              final Map<String, dynamic> reactions = post['reactions'] ?? {};

              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Avatar, Name, and Time
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF333333),
                            backgroundImage:
                                post['userAvatar'] != null &&
                                    post['userAvatar'].toString().isNotEmpty
                                ? NetworkImage(post['userAvatar'])
                                : null,
                            child:
                                post['userAvatar'] == null ||
                                    post['userAvatar'].toString().isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.grey,
                                    size: 20,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post['userName'] ?? 'Movie Fan',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _timeAgo(date),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // The Activity Text
                      Text.rich(
                        TextSpan(
                          text: 'Logged ',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                          children: [
                            TextSpan(
                              text: post['movieTitle'] ?? 'a movie',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Star Rating
                      if (rating > 0)
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: Color(0xFFF5C518),
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Color(0xFFF5C518),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: Color(0xFF333333), height: 1),
                      ),

                      // Reactions Bar
                      Row(
                        children: [
                          _buildReactionButton(docId, '🔥'),
                          _buildReactionButton(docId, '👀'),
                          _buildReactionButton(docId, '🍿'),
                          _buildReactionButton(docId, '💯'),
                          const Spacer(),
                          if (reactions.isNotEmpty)
                            Row(
                              children: [
                                // 1. Print out all the actual emojis that were given
                                Text(
                                  reactions.values.join(' '),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 6),
                                // 2. Show the total count next to them
                                Text(
                                  '(${reactions.length})',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildReactionButton(String docId, String emoji) {
    return GestureDetector(
      onTap: () => _reactToPost(docId, emoji),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF444444)),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
