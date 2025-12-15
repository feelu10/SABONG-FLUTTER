import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class FightBetDetailsPage extends StatefulWidget {
  final int fightId;
  final String fightNumber;
  final String username;

  const FightBetDetailsPage({
    super.key,
    required this.fightId,
    required this.fightNumber,
    required this.username,
  });

  @override
  State<FightBetDetailsPage> createState() => _FightBetDetailsPageState();
}

class _FightBetDetailsPageState extends State<FightBetDetailsPage> {
  bool _loading = true;
  String? _error;
  String? _apiUrl;

  List<Map<String, dynamic>> _bets = [];
  Map<String, dynamic> _totals = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _getApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_url');
  }

  // optional if you want to pass token (your endpoint currently does NOT require it)
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Uri _endpoint(String apiUrl) {
    // ✅ THIS EXISTS IN YOUR BACKEND
    return Uri.parse('$apiUrl/api/teller-bet-history');
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final apiUrl = await _getApiUrl();
    if (apiUrl == null || apiUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "API URL is not set in settings.";
      });
      return;
    }

    _apiUrl = apiUrl;

    try {
      await _fetchBets(apiUrl);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _fetchBets(String apiUrl) async {
    final token = await _getToken();

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = _endpoint(apiUrl);

    // ✅ YOUR BACKEND EXPECTS "nickname" and optional "fight_id"
    final body = jsonEncode({
      "nickname": widget.username,
      "fight_id": widget.fightId,
    });

    debugPrint("[FightBetDetails] POST $uri");
    debugPrint("[FightBetDetails] body=$body");

    final res = await http.post(uri, headers: headers, body: body);

    if (res.statusCode != 200) {
      debugPrint("[FightBetDetails] status=${res.statusCode} body=${res.body}");
      throw Exception("History fetch failed (${res.statusCode}).");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception(decoded['error'].toString());
    }

    if (decoded is! Map) {
      throw Exception("Invalid response (expected Map).");
    }

    final betsRaw = decoded['bets'];
    final totalsRaw = decoded['totals'];

    _bets = (betsRaw is List)
        ? betsRaw.whereType<Map>().cast<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    _totals = (totalsRaw is Map) ? Map<String, dynamic>.from(totalsRaw) : {};
  }

  // ---------- UI helpers ----------
  Widget _glassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.25),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  String _money(dynamic v) {
    final n = double.tryParse((v ?? "0").toString()) ?? 0;
    return n.toStringAsFixed(2);
  }

  Color _sideColor(String side) {
    final s = side.toLowerCase();
    if (s.contains("meron")) return Colors.redAccent;
    if (s.contains("wala")) return Colors.blueAccent;
    return Colors.white70;
  }

  Color _outcomeColor(String outcome) {
    final s = outcome.toLowerCase();
    if (s == "win") return Colors.greenAccent;
    if (s == "lose") return Colors.redAccent;
    if (s == "draw" || s == "cancelled") return Colors.amberAccent;
    return Colors.orangeAccent; // pending
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070F),
        elevation: 0,
        title: Text(
          "Fight #${widget.fightNumber}",
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF05070F),
                Color(0xFF0B1220),
                Color(0xFF070A14),
              ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            children: [
              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Transactions",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "User: ${widget.username}",
                      style: TextStyle(color: Colors.white.withOpacity(0.70), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Fight ID: ${widget.fightId}",
                      style: TextStyle(color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (_loading)
                _glassCard(
                  child: Row(
                    children: const [
                      SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text("Loading transactions...", style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              else if (_error != null)
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Unable to load", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () => _load(),
                        icon: const Icon(Icons.refresh),
                        label: const Text("Try again"),
                      ),
                      if (_apiUrl != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Endpoint: ${_endpoint(_apiUrl!).toString()}",
                          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                )
              else if (_bets.isEmpty)
                // ✅ INDICATOR IF NO TRANSACTION ON THAT FIGHT
                _glassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.amberAccent.withOpacity(0.12),
                          border: Border.all(color: Colors.amberAccent.withOpacity(0.55)),
                        ),
                        child: const Center(
                          child: Icon(Icons.receipt_long_rounded, color: Colors.amberAccent),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "No transactions on this fight",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "No bets were recorded for Fight #${widget.fightNumber}.",
                              style: const TextStyle(color: Colors.white70, height: 1.25),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Summary",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      _summaryRow("Total Bets", "₱${_money(_totals['total_bets'])}"),
                      _summaryRow("Total Win (stake)", "₱${_money(_totals['total_win'])}"),
                      _summaryRow("Total Lose", "₱${_money(_totals['total_lose'])}"),
                      _summaryRow("Total Claimed", "₱${_money(_totals['total_claimed'])}"),
                      _summaryRow("Total Refund", "₱${_money(_totals['total_refund'])}"),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Transactions (${_bets.length})",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      ..._bets.map(_betRow).toList(),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w700)),
          ),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _betRow(Map<String, dynamic> b) {
    final betId = b['id'] ?? '--';
    final side = (b['side'] ?? '--').toString();
    final amount = _money(b['amount'] ?? 0);
    final outcome = (b['outcome'] ?? 'pending').toString();
    final winAmount = _money(b['win_amount'] ?? 0);
    final receipt = (b['receipt_id'] ?? '').toString();
    final createdAt = (b['created_at'] ?? '').toString();
    final isClaimed = (b['is_claimed'] == true);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _sideColor(side).withOpacity(0.12),
              border: Border.all(color: _sideColor(side).withOpacity(0.55)),
            ),
            child: Center(
              child: Text(
                side.toUpperCase(),
                style: TextStyle(color: _sideColor(side), fontWeight: FontWeight.w900, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Bet #$betId • ₱$amount",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  receipt.isNotEmpty ? "Receipt: $receipt" : "Receipt: --",
                  style: TextStyle(color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 4),
                if (outcome.toLowerCase() == "win")
                  Text(
                    "Win Amount: ₱$winAmount ${isClaimed ? "(CLAIMED)" : "(NOT CLAIMED)"}",
                    style: TextStyle(color: Colors.white.withOpacity(0.70), fontWeight: FontWeight.w700, fontSize: 12),
                  )
                else
                  Text(
                    "Outcome: ${outcome.toUpperCase()}",
                    style: TextStyle(color: Colors.white.withOpacity(0.70), fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    createdAt,
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _outcomeColor(outcome).withOpacity(0.55)),
            ),
            child: Text(
              outcome.toUpperCase(),
              style: TextStyle(color: _outcomeColor(outcome), fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
