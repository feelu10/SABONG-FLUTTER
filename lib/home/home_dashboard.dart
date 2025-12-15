import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:D_OCBS/home/fight_bet_details.dart';

class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({super.key});

  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  Timer? _timer;

  bool _loading = true;
  String? _error;

  // current fight
  String _fightNumber = "--";
  String _fightStatus = "--";
  String? _fightResult;
  bool _meronClosed = false;
  bool _walaClosed = false;

  // recent results
  List<Map<String, dynamic>> _recentResults = [];

  @override
  void initState() {
    super.initState();
    _refreshAll();

    // auto refresh (lightweight)
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshAll(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String?> _getApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_url');
  }

  Future<void> _refreshAll({bool silent = false}) async {
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

    try {
      await Future.wait([
        _fetchActiveFight(apiUrl),
        _fetchResultsHistory(apiUrl),
      ]);

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

  Future<void> _fetchActiveFight(String apiUrl) async {
    final uri = Uri.parse('$apiUrl/api/fights/active');
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception("Active fight fetch failed (${res.statusCode}).");
    }

    final Map<String, dynamic> data = jsonDecode(res.body);

    if (data.containsKey('error')) {
      throw Exception("Active fight error: ${data['error']}");
    }

    final statusRaw = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = _normalizeStatus(statusRaw);

    if (!mounted) return;
    setState(() {
      _fightNumber = (data['fight_number'] ?? '--').toString();
      _fightStatus = normalizedStatus;
      _fightResult = data['result']?.toString();
      _meronClosed = (data['is_meron_close'] == true);
      _walaClosed = (data['is_wala_close'] == true);
    });
  }

  Future<void> _fetchResultsHistory(String apiUrl) async {
    final uri = Uri.parse('$apiUrl/api/fights');
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception("Results history fetch failed (${res.statusCode}).");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception("Results history error: ${decoded['error']}");
    }

    if (decoded is! List) {
      throw Exception("Invalid results history response.");
    }

    // take fights with result only
    final fights = decoded
        .where((e) => e is Map && e['result'] != null && e['result'].toString().trim().isNotEmpty)
        .cast<Map<String, dynamic>>()
        .toList();

    final recent = fights.take(20).map((f) {
      final statusRaw = (f['status'] ?? '').toString().toLowerCase();

      // IMPORTANT: make ID resilient (some APIs return fight_id/fightId)
      final idValue = f['id'] ?? f['fight_id'] ?? f['fightId'];

      return {
        "id": idValue,
        "fight_number": f["fight_number"]?.toString() ?? "--",
        "status": _normalizeStatus(statusRaw),
        "result": f["result"]?.toString(),
      };
    }).toList();

    final oldJson = jsonEncode(_recentResults);
    final newJson = jsonEncode(recent);

    if (oldJson != newJson && mounted) {
      setState(() => _recentResults = recent);
    }
  }

  String _normalizeStatus(String s) {
    if (s == 'last_call' || s == 'last call' || s == 'last-call' || s == 'lastcall') return 'lastcall';
    if (s == 'open') return 'open';
    if (s == 'closed') return 'closed';
    return s.isEmpty ? '--' : s;
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':
        return 'OPEN';
      case 'lastcall':
        return 'LAST CALL';
      case 'closed':
        return 'CLOSED';
      default:
        return s.toUpperCase();
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'open':
        return Colors.greenAccent;
      case 'lastcall':
        return Colors.orangeAccent;
      case 'closed':
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  Color _resultColor(String? r) {
    final v = (r ?? '').toLowerCase();
    if (v == 'meron') return Colors.redAccent;
    if (v == 'wala') return Colors.blueAccent;
    if (v == 'draw') return Colors.greenAccent;
    if (v == 'cancelled') return Colors.amberAccent;
    return Colors.white54;
  }

  String _resultLabel(String? r) {
    final v = (r ?? '').toLowerCase();
    if (v.isEmpty) return '--';
    return v.toUpperCase();
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.25),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _refreshAll(),
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
            Row(
              children: [
                const Icon(Icons.dashboard_rounded, color: Colors.white70),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Dashboard",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                IconButton(
                  onPressed: () => _refreshAll(),
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  tooltip: "Refresh",
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (_loading)
              _glassCard(
                child: Row(
                  children: const [
                    SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text("Loading live data...", style: TextStyle(color: Colors.white70)),
                  ],
                ),
              )
            else if (_error != null)
              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Unable to load", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => _refreshAll(),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Try again"),
                    ),
                  ],
                ),
              )
            else ...[
              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Current Fight",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Fight #$_fightNumber",
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _statusColor(_fightStatus).withOpacity(0.6)),
                          ),
                          child: Text(
                            _statusLabel(_fightStatus),
                            style: TextStyle(color: _statusColor(_fightStatus), fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _miniPill(
                          label: "MERON",
                          value: _meronClosed ? "CLOSED" : "OPEN",
                          color: _meronClosed ? Colors.redAccent : Colors.greenAccent,
                        ),
                        const SizedBox(width: 10),
                        _miniPill(
                          label: "WALA",
                          value: _walaClosed ? "CLOSED" : "OPEN",
                          color: _walaClosed ? Colors.redAccent : Colors.greenAccent,
                        ),
                        const SizedBox(width: 10),
                        _miniPill(
                          label: "RESULT",
                          value: _resultLabel(_fightResult),
                          color: _resultColor(_fightResult),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.history_rounded, color: Colors.white70, size: 20),
                        SizedBox(width: 10),
                        Text(
                          "Recent Results",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_recentResults.isEmpty)
                      const Text("No completed fights yet.", style: TextStyle(color: Colors.white54))
                    else
                      ..._recentResults.map((f) => _resultRow(f)).toList(),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
            const Center(
              child: Text("Pull down to refresh", style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniPill({required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(Map<String, dynamic> f) {
    final status = (f["status"] ?? "--").toString();
    final result = f["result"]?.toString();
    final fightNo = (f["fight_number"] ?? "--").toString();

    final rawId = f["id"];
    final fightId = int.tryParse((rawId ?? "").toString());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          debugPrint("Tapped fight: rawId=$rawId parsedId=$fightId fightNo=$fightNo");

          if (fightId == null || fightId <= 0) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cannot open: missing fight ID from API.")),
            );
            return;
          }

          final prefs = await SharedPreferences.getInstance();
          final uname = prefs.getString('username') ?? "User";

          if (!mounted) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FightBetDetailsPage(
                fightId: fightId,
                fightNumber: fightNo,
                username: uname,
              ),
            ),
          );
        },
        child: Container(
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
                  color: _resultColor(result).withOpacity(0.12),
                  border: Border.all(color: _resultColor(result).withOpacity(0.55)),
                ),
                child: Center(
                  child: Text(
                    _resultLabel(result),
                    style: TextStyle(color: _resultColor(result), fontWeight: FontWeight.w900, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Fight #$fightNo", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      "Status: ${_statusLabel(status)}",
                      style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
