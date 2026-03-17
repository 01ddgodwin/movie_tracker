import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class AmcStubsCard extends StatefulWidget {
  final List<dynamic> diary;
  final List<dynamic> watchlist;

  const AmcStubsCard({
    super.key,
    required this.diary,
    required this.watchlist,
  });

  @override
  State<AmcStubsCard> createState() => _AmcStubsCardState();
}

class _AmcStubsCardState extends State<AmcStubsCard> {
  String _currentCity = "Mesa, AZ";
  double _ticketPrice = 15.00;
  double _monthlyStubs = 23.99;
  bool _isLocating = true;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    try {
      // 1. Check if GPS is even turned on
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _currentCity = "GPS Disabled (Mesa Default)";
          _isLocating = false;
        });
        return;
      }

      // 2. Check and ACTIVELY REQUEST permissions
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _currentCity = "Permission Denied (Mesa Default)";
            _isLocating = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _currentCity = "Location Blocked (Mesa Default)";
          _isLocating = false;
        });
        return;
      }

      // 3. Get Coordinates
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low // Low accuracy is fine for city-level and saves battery
      );

      // 4. Convert Coordinates to City/State
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String state = place.administrativeArea ?? "AZ";
        String city = place.locality ?? "Mesa";

        setState(() {
          _currentCity = "$city, $state";
          _updatePricing(state);
          _isLocating = false;
        });
      }
    } catch (e) {
      debugPrint("Location error: $e");
      setState(() => _isLocating = false); // Fallback to Mesa defaults on any crash
    }
  }

  // Real-world AMC A-List Tiers (2026 approximation)
  void _updatePricing(String state) {
    // Tier 1: CA, NY, NJ, CT, MA, DC, IL (The expensive ones)
    const tier1 = ["CA", "NY", "NJ", "CT", "MA", "DC", "IL"];
    // Tier 2: AZ, CO, FL, GA, MD, MN, NV, OH, OR, PA, TX, VA, WA
    const tier2 = ["AZ", "CO", "FL", "GA", "MD", "MN", "NV", "OH", "OR", "PA", "TX", "VA", "WA"];

    if (tier1.contains(state.toUpperCase())) {
      _ticketPrice = 18.50;
      _monthlyStubs = 25.99;
    } else if (tier2.contains(state.toUpperCase())) {
      _ticketPrice = 15.00;
      _monthlyStubs = 23.99;
    } else {
      _ticketPrice = 12.50; // Lower cost states
      _monthlyStubs = 21.99;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double annualStubs = _monthlyStubs * 12;
    final int currentYear = DateTime.now().year;

    int moviesSeenThisYear = 0;
    for (var m in widget.diary) {
      try {
        if (m['watchedDate'] != null) {
          DateTime d = DateTime.parse(m['watchedDate'].toString());
          if (d.year == currentYear) moviesSeenThisYear++;
        }
      } catch (_) {}
    }

    int plannedMoviesThisYear = 0;
    for (var m in widget.watchlist) {
      try {
        final String? rDateStr = (m['releaseDate'] ?? m['release_date'])?.toString();
        if (rDateStr != null && rDateStr.isNotEmpty) {
          DateTime rDate = DateTime.parse(rDateStr);
          if (rDate.year == currentYear) plannedMoviesThisYear++;
        }
      } catch (_) {}
    }

    int totalMovies = moviesSeenThisYear + plannedMoviesThisYear;
    double spentSoFar = moviesSeenThisYear * _ticketPrice;
    double projectedSpend = plannedMoviesThisYear * _ticketPrice;
    double totalSpend = spentSoFar + projectedSpend;
    double savings = totalSpend - annualStubs;
    bool isWorthIt = savings > 0;
    int breakEvenMovies = (annualStubs / _ticketPrice).ceil();
    int moviesNeeded = breakEvenMovies - totalMovies;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE50914), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE50914).withOpacity(0.15), 
            blurRadius: 20, 
            offset: const Offset(0, 8)
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFE50914), 
              borderRadius: BorderRadius.vertical(top: Radius.circular(14))
            ),
            child: Row(
              children: [
                const Icon(Icons.theaters, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('AMC STUBS A-LIST CALCULATOR', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const Spacer(),
                if (_isLocating)
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  const Icon(Icons.location_on, color: Colors.white, size: 14),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('BASED ON ${_currentCity.toUpperCase()} PRICING', style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn('SEEN', moviesSeenThisYear.toString(), '\$${spentSoFar.toStringAsFixed(2)}'),
                    Container(height: 40, width: 1, color: const Color(0xFF333333)),
                    _buildStatColumn('REMAINING', plannedMoviesThisYear.toString(), '\$${projectedSpend.toStringAsFixed(2)}'),
                    Container(height: 40, width: 1, color: const Color(0xFF333333)),
                    _buildStatColumn('TOTAL', totalMovies.toString(), '\$${totalSpend.toStringAsFixed(2)}', isHighlight: true),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(color: Color(0xFF333333), height: 1)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Using String concatenation to avoid the $ variable trigger
                    Text('A-List Annual Cost (\$' + _monthlyStubs.toStringAsFixed(2) + '/mo):', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text('\$${annualStubs.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isWorthIt ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isWorthIt ? Colors.green : Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(isWorthIt ? Icons.check_circle : Icons.info_outline, color: isWorthIt ? Colors.green : Colors.orange, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isWorthIt ? 'WORTH IT!' : 'NOT QUITE YET', style: TextStyle(color: isWorthIt ? Colors.green : Colors.orange, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 2),
                            Text(isWorthIt 
                                ? 'You will save \$${savings.toStringAsFixed(2)} this year based on your current location.'
                                : 'You need to see $moviesNeeded more movies this year to break even.', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String count, String cost, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(count, style: TextStyle(color: isHighlight ? const Color(0xFFE50914) : Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(cost, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}