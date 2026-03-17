import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'tmdb_service.dart';
import 'firebase_service.dart';
import 'storage_service.dart';

class AddPlanDialog extends StatefulWidget {
  final Map<String, dynamic>? existingPlan;
  const AddPlanDialog({super.key, this.existingPlan});

  @override
  State<AddPlanDialog> createState() => _AddPlanDialogState();
}

class _AddPlanDialogState extends State<AddPlanDialog> {
  final TMDBService _tmdbService = TMDBService();
  final FirebaseService _firebaseService = FirebaseService();
  final StorageService _storageService = StorageService();

  final TextEditingController _movieController = TextEditingController();
  final TextEditingController _theaterController = TextEditingController();

  Map<String, dynamic>? _selectedMovie;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(
    hour: 19,
    minute: 0,
  ); // Default 7:00 PM

  List<dynamic> _friendsList = [];
  List<String> _invitedFriends = [];
  List<String> _pastTheaters = [];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // 1. Load Friends from Firebase
    final userData = await _firebaseService.fetchUserData();
    if (userData != null && userData['friendsList'] != null) {
      _friendsList = List<dynamic>.from(userData['friendsList']);
    }

    // 2. Load Past Theaters from local tickets to use for Autocomplete
    final tickets = await _storageService.getTickets();
    for (var t in tickets) {
      final theater = t['theater']?.toString().trim();
      if (theater != null &&
          theater.isNotEmpty &&
          !_pastTheaters.contains(theater)) {
        _pastTheaters.add(theater);
      }
    }

    // 3. Populate existing plan data if editing
    if (widget.existingPlan != null) {
      final plan = widget.existingPlan!;
      _movieController.text = plan['title'] ?? '';
      _theaterController.text = plan['location'] ?? '';
      _selectedMovie = {
        'title': plan['title'],
        'poster_path': plan['posterPath'],
      };

      try {
        if (plan['date'] != null) {
          _selectedDate = DateFormat('MMMM d, yyyy').parse(plan['date']);
        }
        if (plan['time'] != null) {
          final parsedTime = DateFormat.jm().parse(plan['time']);
          _selectedTime = TimeOfDay(
            hour: parsedTime.hour,
            minute: parsedTime.minute,
          );
        }
      } catch (_) {}

      if (plan['invitedUids'] != null) {
        _invitedFriends = List<String>.from(plan['invitedUids']);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2099),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE50914),
            surface: Color(0xFF1A1A1A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE50914),
            surface: Color(0xFF1A1A1A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _savePlan() async {
    if (_movieController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or select a movie.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final planData = {
        'id':
            widget.existingPlan?['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'title': _movieController.text.trim(),
        'posterPath': _selectedMovie?['poster_path'],
        'location': _theaterController.text.trim().isEmpty
            ? 'TBD'
            : _theaterController.text.trim(),
        'date': DateFormat('MMMM d, yyyy').format(_selectedDate),
        'time': _selectedTime.format(context),
        'hostUid': _firebaseService.currentUser?.uid,
        'hostName': _firebaseService.currentUser?.displayName ?? 'A Friend',
        'invitedUids': _invitedFriends,
      };

      // Calls your Firebase service to save/update the plan
      await _firebaseService.createOrUpdatePlan(planData);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error saving plan.'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- CUSTOM UI FOR THE MOVIE AUTOCOMPLETE DROPDOWN ---
  Widget _buildMovieAutocomplete() {
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(text: _movieController.text),
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text.isEmpty)
          return const Iterable<Map<String, dynamic>>.empty();

        // Fetch the results and cleanly convert them into the required Map format
        final results = await _tmdbService.searchMovies(textEditingValue.text);
        return List<Map<String, dynamic>>.from(results);
      },
      displayStringForOption: (option) => option['title'] ?? '',
      onSelected: (option) {
        setState(() {
          _selectedMovie = option;
          _movieController.text = option['title'] ?? '';
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        // Sync the internal controller with our external one
        controller.addListener(() {
          if (_movieController.text != controller.text) {
            _movieController.text = controller.text;
          }
        });
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            labelText: 'Search Movie Title',
            labelStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.search, color: Color(0xFFE50914)),
            filled: true,
            fillColor: const Color(0xFF2B2B2B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width:
                  MediaQuery.of(context).size.width -
                  90, // Match dialog width roughly
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF444444)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length > 5
                    ? 5
                    : options.length, // Limit to 5 results
                separatorBuilder: (context, index) =>
                    const Divider(color: Color(0xFF444444), height: 1),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  final poster = option['poster_path'];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: poster != null
                          ? Image.network(
                              'https://image.tmdb.org/t/p/w92$poster',
                              width: 30,
                              height: 45,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 30,
                              height: 45,
                              color: Colors.grey[800],
                              child: const Icon(Icons.movie, size: 16),
                            ),
                    ),
                    title: Text(
                      option['title'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      option['release_date']?.toString().split('-').first ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // --- CUSTOM UI FOR THE THEATER AUTOCOMPLETE ---
  Widget _buildTheaterAutocomplete() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _theaterController.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty)
          return const Iterable<String>.empty();
        return _pastTheaters.where(
          (theater) => theater.toLowerCase().contains(
            textEditingValue.text.toLowerCase(),
          ),
        );
      },
      onSelected: (String selection) {
        _theaterController.text = selection;
      },
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        controller.addListener(() {
          if (_theaterController.text != controller.text)
            _theaterController.text = controller.text;
        });
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Theater / Location',
            labelStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.location_on, color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF2B2B2B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width - 90,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF444444)),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    leading: const Icon(
                      Icons.history,
                      color: Colors.grey,
                      size: 20,
                    ),
                    title: Text(
                      option,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Dialog(
        backgroundColor: Color(0xFF1A1A1A),
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [CircularProgressIndicator(color: Color(0xFFE50914))],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existingPlan != null
                      ? 'Edit Movie Night'
                      : 'Plan Movie Night',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- MOVIE SEARCH ---
            _buildMovieAutocomplete(),
            const SizedBox(height: 16),

            // --- DATE & TIME ROW ---
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B2B2B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            color: Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat('MMM d, yyyy').format(_selectedDate),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B2B2B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            color: Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedTime.format(context),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- THEATER SEARCH ---
            _buildTheaterAutocomplete(),
            const SizedBox(height: 24),

            // --- INVITE FRIENDS ---
            const Text(
              'INVITE FRIENDS',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),

            _friendsList.isEmpty
                ? const Text(
                    'Add friends in the Friends Tab to invite them!',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _friendsList.map((friend) {
                      final uid = friend['uid'];
                      final isSelected = _invitedFriends.contains(uid);
                      final avatar = friend['photoURL'] ?? '';

                      return FilterChip(
                        backgroundColor: const Color(0xFF2B2B2B),
                        selectedColor: const Color(
                          0xFFE50914,
                        ).withValues(alpha: 0.2),
                        checkmarkColor: const Color(0xFFE50914),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFFE50914)
                              : Colors.transparent,
                        ),
                        avatar: CircleAvatar(
                          radius: 12,
                          backgroundImage: avatar.isNotEmpty
                              ? NetworkImage(avatar)
                              : null,
                          backgroundColor: Colors.grey[800],
                          child: avatar.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 12,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        label: Text(
                          friend['displayName'] ?? 'Friend',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected)
                              _invitedFriends.add(uid);
                            else
                              _invitedFriends.remove(uid);
                          });
                        },
                      );
                    }).toList(),
                  ),

            const SizedBox(height: 32),

            // --- SAVE BUTTON ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isSaving ? null : _savePlan,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        widget.existingPlan != null
                            ? 'Update Plan'
                            : 'Create Plan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
