import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'ticket_reprint.dart';

class BetHistoryPage extends StatefulWidget {
  const BetHistoryPage({super.key});

  @override
  State<BetHistoryPage> createState() => _BetHistoryPageState();
}

class _BetHistoryPageState extends State<BetHistoryPage> {
  List<Map<String, dynamic>> _bets = [];
  Map<String, dynamic> _totals = {};
  bool _loading = true;
  String? _error;
  Timer? _pollingTimer;

  // --- FIGHT DROPDOWN ---
  List<Map<String, dynamic>> _fightList = [];
  int? _selectedFightId;
  int _currentPage = 1;
  int _totalPages = 1;
  int _perPage = 10;

  // --- FILTER ---
  String _activeFilter = 'all';
  final Map<String, String> _filterLabels = {
    'all': 'All',
    'win': 'Win',
    'lose': 'Lose',
    'claimed': 'Claimed',
    'refund': 'Refund',
    'pending': 'Pending',
  };

  @override
  void initState() {
    super.initState();
    fetchFightList();
    _startActiveUpdater();
  }

  void _startActiveUpdater() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 7), (_) => _fetchAndUpdate());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchFightList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      final username = prefs.getString('username');
      if (apiUrl == null || username == null) return;

      final lastFetched = prefs.getInt('fight_cache_timestamp') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Use cache if last fetch is within 7 seconds
      if ((now - lastFetched) < 7000) {
        final cachedJson = prefs.getString('fight_cache_data');
        if (cachedJson != null) {
          final cachedFights = (jsonDecode(cachedJson) as List)
              .map((f) => Map<String, dynamic>.from(f))
              .toList();

          int? latestFightId = cachedFights.isNotEmpty ? cachedFights.first['fight_id'] as int? : null;

          setState(() {
            _fightList = cachedFights;
            if (_selectedFightId == null && latestFightId != null) {
              _selectedFightId = latestFightId;
              fetchBetHistory(fightId: latestFightId, page: 1);
            } else if (_selectedFightId == null) {
              fetchBetHistory(page: 1);
            }
          });
          return;
        }
      }

      // If no recent cache, fetch from API
      final url = Uri.parse('$apiUrl/api/teller-bet-history');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nickname': username}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fights = (data['fights'] as List)
            .map((f) => Map<String, dynamic>.from(f))
            .toList();

        await prefs.setString('fight_cache_data', jsonEncode(fights));
        await prefs.setInt('fight_cache_timestamp', now);

        int? latestFightId = fights.isNotEmpty ? fights.first['fight_id'] as int? : null;

        setState(() {
          _fightList = fights;
          if (_selectedFightId == null && latestFightId != null) {
            _selectedFightId = latestFightId;
            fetchBetHistory(fightId: latestFightId, page: 1);
          } else if (_selectedFightId == null) {
            fetchBetHistory(page: 1);
          }
        });
      }
    } catch (e) {
      print('fetchFightList error: $e');
    }
  }

  Future<void> _fetchAndUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      final username = prefs.getString('username');
      if (apiUrl == null || username == null) return;

      final url = Uri.parse('$apiUrl/api/teller-bet-history');
      final body = {
        'nickname': username,
        if (_selectedFightId != null) 'fight_id': _selectedFightId,
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updatedBets = (data['bets'] as List).map((b) => Map<String, dynamic>.from(b)).toList();

        for (int i = 0; i < updatedBets.length; i++) {
          final updated = updatedBets[i];
          final index = _bets.indexWhere((b) => b['id'] == updated['id']);
          if (index != -1) {
            final old = _bets[index];
            if (old['outcome'] != updated['outcome'] || old['is_claimed'] != updated['is_claimed']) {
              setState(() {
                _bets[index] = updated;
              });
            }
          }
        }
        setState(() {
          _totals = Map<String, dynamic>.from(data['totals'] ?? {});
        });
      }
    } catch (e) {
      // silently fail
    }
  }

  Future<void> _confirmVoid(int betId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void Bet'),
        content: const Text('Are you sure you want to void this bet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Void')),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      final username = prefs.getString('username');

      final url = Uri.parse('$apiUrl/api/bet/$betId/void');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bet voided successfully.')));
        fetchBetHistory(fightId: _selectedFightId, page: _currentPage);
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Unable to void';
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Failed'),
            content: Text(error),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  void _reprintTicket(Map<String, dynamic> bet) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => TicketReprintPage(bet: bet),
      ),
    );
  }

  Future<void> fetchBetHistory({int? fightId, int? page}) async {
    setState(() {
      _loading = true;
      _error = null;
      _bets = [];
      _totals = {};
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      final username = prefs.getString('username');
      if (apiUrl == null || username == null) {
        setState(() {
          _error = "Missing username or API URL";
          _loading = false;
        });
        return;
      }

      final url = Uri.parse('$apiUrl/api/teller-bet-history');
      final body = {
        'nickname': username,
        if (fightId != null) 'fight_id': fightId,
        'page': page ?? _currentPage,
        'per_page': _perPage,
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _bets = (data['bets'] as List)
              .map((b) => Map<String, dynamic>.from(b))
              .toList();
          _totals = Map<String, dynamic>.from(data['totals'] ?? {});
          _loading = false;
          final pagination = data['pagination'];
          if (pagination != null) {
            _currentPage = pagination['page'] ?? 1;
            _totalPages = pagination['pages'] ?? 1;
          } else {
            _currentPage = 1;
            _totalPages = 1;
          }
        });
      } else {
        setState(() {
          _error = jsonDecode(response.body)['error']?.toString() ?? 'Unknown error';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // --- FIGHT DROPDOWN ---
  Widget _buildFightDropdown() {
    if (_fightList.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: DropdownButtonFormField<int>(
        value: _selectedFightId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Filter by Fight',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color.fromARGB(255, 0, 0, 0),
        ),
        items: [
          const DropdownMenuItem<int>(
            value: null,
            child: Text("All Fights"),
          ),
          ..._fightList.map((f) => DropdownMenuItem<int>(
                value: f['fight_id'],
                child: Text("Fight #${f['fight_number'] ?? f['fight_id']}"),
              )),
        ],
        onChanged: (val) {
          setState(() {
            _selectedFightId = val;
            _currentPage = 1; // reset to first page
          });
          fetchBetHistory(fightId: val, page: 1);
        },
      ),
    );
  }

  // --- FILTERED BETS ---
  List<Map<String, dynamic>> get _filteredBets {
    switch (_activeFilter) {
      case 'win':
        return _bets.where((b) => b['outcome'] == 'win' && b['is_claimed'] != true).toList();
      case 'lose':
        return _bets.where((b) => b['outcome'] == 'lose').toList();
      case 'claimed':
        return _bets.where((b) => b['outcome'] == 'win' && b['is_claimed'] == true).toList();
      case 'refund':
        return _bets.where((b) => b['outcome'] == 'draw' || b['outcome'] == 'cancelled').toList();
      case 'pending':
        return _bets.where((b) => b['outcome'] == 'pending').toList();
      case 'all':
      default:
        return _bets;
    }
  }

  Color outcomeColor(String outcome, bool isClaimed) {
    switch (outcome) {
      case 'win':
        return isClaimed ? Colors.green : Colors.amber.shade700;
      case 'lose':
        return Colors.red.shade400;
      case 'draw':
      case 'cancelled':
        return Colors.blueGrey.shade600;
      case 'pending':
      default:
        return Colors.grey.shade500;
    }
  }

  String outcomeText(String outcome, bool isClaimed) {
    switch (outcome) {
      case 'win':
        return isClaimed ? "WON & CLAIMED" : "WON (Unclaimed)";
      case 'lose':
        return "LOST";
      case 'draw':
        return "REFUND (Draw)";
      case 'cancelled':
        return "REFUND (Cancelled)";
      case 'pending':
      default:
        return "Pending";
    }
  }

  // --- DASHBOARD CARDS ---
  Widget totalsCard() {
    if (_totals.isEmpty) return const SizedBox.shrink();
    final cards = [
      _bigSummaryCard("Total Bets", _totals['total_bets'], Icons.account_balance_wallet, Colors.blue.shade600),
      _bigSummaryCard("Total Won", _totals['total_win'], Icons.emoji_events, Colors.green.shade700),
      _bigSummaryCard("Total Lost", _totals['total_lose'], Icons.close, Colors.red.shade600),
      _bigSummaryCard("Total Claimed", _totals['total_claimed'], Icons.verified, Colors.amber.shade800),
      _bigSummaryCard("Total Refund", _totals['total_refund'], Icons.undo, Colors.blueGrey.shade700),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 10),
      padding: const EdgeInsets.only(left: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: cards
              .map((card) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: card,
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _bigSummaryCard(String label, dynamic value, IconData icon, Color color) {
    String strValue = value == null ? "₱0" : "₱${(value as num).toStringAsFixed(0)}";
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.14),
            offset: const Offset(0, 3),
            blurRadius: 10,
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: Colors.white),
            const SizedBox(height: 7),
            Text(
              strValue,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterLabels.keys.map((key) {
            final selected = _activeFilter == key;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  _filterLabels[key]!,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : Colors.grey[400],
                  ),
                ),
                selected: selected,
                selectedColor: Colors.red[700],
                backgroundColor: Colors.grey[900],
                elevation: selected ? 3 : 0,
                onSelected: (_) => setState(() => _activeFilter = key),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                side: BorderSide(color: selected ? Colors.red : Colors.grey[800]!),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _paginationControls() {
    if (_totalPages <= 1 || _selectedFightId != null) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    fetchBetHistory(page: _currentPage);
                  }
                : null,
            child: const Text('Prev'),
          ),
          const SizedBox(width: 18),
          Text('Page $_currentPage / $_totalPages'),
          const SizedBox(width: 18),
          ElevatedButton(
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage++);
                    fetchBetHistory(page: _currentPage);
                  }
                : null,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  Widget _buildBetCard(Map<String, dynamic> bet) {
    final outcome = bet['outcome'] ?? "pending";
    final isClaimed = bet['is_claimed'] == true;
    final payout = bet['win_amount'] != null && bet['win_amount'] > 0
        ? "Payout: ₱${(bet['win_amount'] as num).toStringAsFixed(0)}"
        : "";
    final time = bet['created_at']?.toString().replaceFirst('T', ' ').substring(0, 16) ?? '';
    final fightNo = bet['fight_number']?.toString() ?? bet['fight_id']?.toString() ?? '?';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      elevation: 2.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outcomeColor(outcome, isClaimed).withOpacity(0.12), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Icon, fight info, reprint button
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: bet['side'] == 'meron' ? Colors.red[600] : Colors.blue[700],
                  radius: 18,
                  child: Icon(
                    bet['side'] == 'meron' ? Icons.sports_mma : Icons.sports_mma_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Fight #$fightNo",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: Color.fromARGB(221, 255, 255, 255),
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.print, size: 17),
                  label: const Text("Reprint", style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color.fromARGB(255, 5, 113, 167),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _reprintTicket(bet),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Bet amount, receipt
            Row(
              children: [
                Text(
                  "₱${(bet['amount'] as num).toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    "Receipt: ${bet['receipt_id'] ?? '--'}",
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color.fromARGB(137, 255, 255, 255),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Side and time
            Row(
              children: [
                Chip(
                  label: Text(
                    bet['side'].toString().toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: bet['side'] == 'meron'
                      ? Colors.red.withOpacity(0.12)
                      : Colors.blue.withOpacity(0.13),
                  labelStyle: TextStyle(
                    color: bet['side'] == 'meron' ? Colors.red[700] : Colors.blue[800],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    time,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Status row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: outcomeColor(outcome, isClaimed).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    outcomeText(outcome, isClaimed),
                    style: TextStyle(
                      color: outcomeColor(outcome, isClaimed),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (payout.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      payout,
                      style: const TextStyle(
                        color: Color.fromARGB(255, 139, 248, 143),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const Spacer(),
                if (bet['can_void'] == true)
                  ElevatedButton(
                    onPressed: () => _confirmVoid(bet['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Void'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.red[700],
        title: const Text("Bet History", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: fetchBetHistory,
                        child: const Text("Retry"),
                      ),
                    ],
                  ),
                )
              : _bets.isEmpty
                  ? const Center(
                      child: Text(
                        "No bet history found.",
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    )
                  : Column(
                      children: [
                        // List and controls are scrollable, pagination stays pinned at the bottom
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () async {
                              await fetchBetHistory(
                                fightId: _selectedFightId,
                                page: _currentPage,
                              );
                            },
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _filteredBets.length + 3, // totals, fight dropdown, filter chips
                              itemBuilder: (ctx, idx) {
                                if (idx == 0) return totalsCard();
                                if (idx == 1) return _buildFightDropdown();
                                if (idx == 2) return _buildFilterChips();
                                final bet = _filteredBets[idx - 3];
                                return _buildBetCard(bet);
                              },
                            ),
                          ),
                        ),
                        _paginationControls(),
                      ],
                    ),
    );
  }
}
