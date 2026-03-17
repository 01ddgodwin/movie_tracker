import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _watchlistKey = 'movieWatchlist';
  static const String _diaryKey = 'movieDiary';
  static const String _ticketsKey = 'movieTickets';

  // --- Watchlist Methods ---

  Future<List<dynamic>> getWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_watchlistKey);
    if (data != null) {
      return json.decode(data);
    }
    return [];
  }

  Future<void> addToWatchlist(Map<String, dynamic> movie) async {
    final prefs = await SharedPreferences.getInstance();
    final watchlist = await getWatchlist();

    // Prevent duplicates
    final exists = watchlist.any(
      (item) => item['id'].toString() == movie['id'].toString(),
    );

    if (!exists) {
      watchlist.add({
        'id': movie['id'].toString(),
        'title': movie['title'],
        'releaseDate': movie['release_date'],
        'posterPath': movie['poster_path'],
        'synced': false,
      });
      await prefs.setString(_watchlistKey, json.encode(watchlist));
    }
  }

  Future<void> removeFromWatchlist(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final watchlist = await getWatchlist();

    // Remove the item where the ID matches
    watchlist.removeWhere((item) => item['id'].toString() == id);

    // Save the updated list back to storage
    await prefs.setString(_watchlistKey, json.encode(watchlist));
  }

  // NEW: Replaces local watchlist with cloud data
  Future<void> saveWatchlist(List<dynamic> watchlist) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_watchlistKey, json.encode(watchlist));
  }

  // --- Diary Methods ---

  Future<List<dynamic>> getDiary() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_diaryKey);
    if (data != null) {
      return json.decode(data);
    }
    return [];
  }

  Future<void> addToDiary(Map<String, dynamic> entry) async {
    final prefs = await SharedPreferences.getInstance();
    final diary = await getDiary();
    
    // Add the new entry to the list
    diary.add(entry);
    
    // Save back to storage
    await prefs.setString(_diaryKey, json.encode(diary));
  }

  Future<void> removeFromDiary(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final diary = await getDiary();
    
    diary.removeWhere((item) => item['id'].toString() == id);
    
    await prefs.setString(_diaryKey, json.encode(diary));
  }

  // NEW: Replaces local diary with cloud data
  Future<void> saveDiary(List<dynamic> diary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_diaryKey, json.encode(diary));
  }

  // --- Plans & Tickets Methods ---

  Future<List<dynamic>> getTickets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_ticketsKey);
    if (data != null) {
      return json.decode(data);
    }
    return [];
  }

  Future<void> addTicket(Map<String, dynamic> ticket) async {
    final prefs = await SharedPreferences.getInstance();
    final tickets = await getTickets();
    tickets.add(ticket);
    await prefs.setString(_ticketsKey, json.encode(tickets));
  }

  Future<void> removeTicket(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final tickets = await getTickets();
    tickets.removeWhere((item) => item['id'].toString() == id);
    await prefs.setString(_ticketsKey, json.encode(tickets));
  }

  // NEW: Replaces local tickets with cloud data
  Future<void> saveTickets(List<dynamic> tickets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ticketsKey, json.encode(tickets));
  }
}