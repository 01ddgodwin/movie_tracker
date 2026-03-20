const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
admin.initializeApp();

exports.notifyFollowersOnNewMovie = functions.firestore
  .document("social_feed/{postId}")
  .onCreate(async (snap, context) => {
    const post = snap.data();
    const posterId = post.userId;
    const posterName = post.userName;
    const movieTitle = post.movieTitle;

    console.log(`New post detected from ${posterName} for ${movieTitle}`);

    try {
      // 1. Find everyone who has this user in their friends list
      const followersSnapshot = await admin.firestore()
        .collectionGroup("friends")
        .where("uid", "==", posterId)
        .get();

      if (followersSnapshot.empty) {
        return console.log("No followers found. Nobody to notify.");
      }

      // 2. Grab the push tokens from those followers' main user profiles
      const tokens = [];
      for (const doc of followersSnapshot.docs) {
        // doc.ref is the friend document. parent.parent gets the actual user's profile!
        const followerRef = doc.ref.parent.parent; 
        const followerDoc = await followerRef.get();
        const followerData = followerDoc.data();

        if (followerData && followerData.pushToken) {
          tokens.push(followerData.pushToken);
        }
      }

      if (tokens.length === 0) {
        return console.log("Followers found, but no push tokens available.");
      }

      // 3. Draft and send the actual Push Notification
      const message = {
        notification: {
          title: `🍿 ${posterName} just logged a movie!`,
          body: `They watched ${movieTitle}. Tap to see their rating and react.`,
        },
        tokens: tokens,
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      return console.log(`Successfully sent ${response.successCount} notifications.`);
      
    } catch (error) {
      return console.error("Error sending notifications:", error);
    }
  });