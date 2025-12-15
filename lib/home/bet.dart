import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ticket_print.dart';

class BettingPage extends StatefulWidget {
  const BettingPage({super.key});
  @override
  State<BettingPage> createState() => _BettingPageState();
}

class _BettingPageState extends State<BettingPage> {
  final TextEditingController _amountController = TextEditingController();
  int? selectedAmount;

  final List<Map<String, dynamic>> _tickets = [];

  Timer? _timer;
  String? apiUrl;

  int? currentFightId;
  String? currentFightNumber;

  String fightStatus = "loading…";
  bool isMeronClosed = false;
  bool isWalaClosed = false;

  static const String _appFont = 'Roboto';

  // RULES
  bool _isBelowMinBet(int amt) => amt < 100;

  bool _isOppositeSideTaken(String side) {
    final opposite = side == 'meron' ? 'wala' : 'meron';
    return _tickets.any((t) =>
        t['side'] == opposite &&
        t['fight_id'] == currentFightId &&
        t['fight_number'] == currentFightNumber);
  }

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
    _checkUserStatus();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString('api_url');

    if (apiUrl != null) {
      await _fetchFightStatus(apiUrl!);
      _timer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _fetchFightStatus(apiUrl!),
      );
    }
  }

  Future<void> _checkUserStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final api = prefs.getString('api_url');

    if (username == null || api == null) return;

    final res = await http.post(
      Uri.parse('$api/api/check-user-status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username}),
    );

    if (res.statusCode == 403 || res.statusCode == 404) {
      final preservedApi = api;
      await prefs.clear();
      await prefs.setString('api_url', preservedApi);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Access Denied"),
          content: const Text("Your account has been deactivated."),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/login'),
              child: const Text("OK"),
            )
          ],
        ),
      );
    }
  }

  Future<void> _fetchFightStatus(String url) async {
    try {
      final res = await http.get(Uri.parse('$url/api/fights/last-completed'));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        setState(() {
          currentFightId = data['id'];
          currentFightNumber = data['fight_number']?.toString();
          fightStatus = data['status']?.toLowerCase() ?? "unknown";

          isMeronClosed =
              data['is_meron_close'] == true || data['is_meron_close'] == 1;
          isWalaClosed =
              data['is_wala_close'] == true || data['is_wala_close'] == 1;
        });
      } else {
        setState(() => fightStatus = "closed");
      }
    } catch (e) {
      setState(() => fightStatus = "error");
    }
  }

  Color getStatusColor() {
    switch (fightStatus) {
      case "open":
        return Colors.green[600]!;
      case "last_call":
        return Colors.orange[800]!;
      case "closed":
        return Colors.red[700]!;
      case "error":
        return Colors.red[400]!;
      default:
        return Colors.grey[600]!;
    }
  }

  bool get isAllClosed =>
      fightStatus == "closed" ||
      fightStatus == "error" ||
      fightStatus == "unknown" ||
      fightStatus == "loading…";

  // UI LOGIC
  void _fillAmount(int amt) {
    _amountController.text = '$amt';
    setState(() => selectedAmount = amt);
  }

  void _onAmountChanged(String value) {
    setState(() => selectedAmount = int.tryParse(value));
  }

  void _placeBet(String side) {
    final amt = int.tryParse(_amountController.text) ?? 0;

    if (_isBelowMinBet(amt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Minimum bet is ₱100"),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    if (_isOppositeSideTaken(side)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Cannot bet both sides."),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      final idx = _tickets.indexWhere((t) =>
          t['side'] == side &&
          t['fight_id'] == currentFightId &&
          t['fight_number'] == currentFightNumber);

      if (idx != -1) {
        _tickets[idx]['amount'] += amt;
      } else {
        _tickets.add({
          'side': side,
          'amount': amt,
          'fight_id': currentFightId,
          'fight_number': currentFightNumber,
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ticketed ₱$amt on ${side.toUpperCase()}'),
        backgroundColor: side == 'meron' ? Colors.red[700] : Colors.blue[700],
      ),
    );

    _amountController.clear();
    selectedAmount = null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  int get _totalBet =>
      _tickets.fold(0, (sum, t) => sum + (t['amount'] as int));

  // NEW TICKET LIST — TRASH ICON VISIBLE
  Widget _buildTicketList() {
    if (_tickets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            "No tickets yet.",
            style: TextStyle(
              fontFamily: _appFont,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Column(
      children: _tickets.asMap().entries.map((entry) {
        final idx = entry.key;
        final t = entry.value;
        final color =
            t['side'] == 'meron' ? Colors.red[700]! : Colors.blue[700]!;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: Icon(Icons.sports_mma, color: color),
            title: Text(
              t['side'].toUpperCase(),
              style: TextStyle(
                fontFamily: _appFont,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "₱${t['amount']}",
                  style: const TextStyle(
                    fontFamily: _appFont,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () =>
                      setState(() => _tickets.removeAt(idx)),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // UI — FULL PAGE
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // FIGHT HEADER
            Container(
              margin: const EdgeInsets.only(bottom: 22),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: getStatusColor().withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.sports_mma, color: Colors.amber[700]),
                  const SizedBox(width: 14),
                  Text(
                    currentFightNumber != null
                        ? "Fight #$currentFightNumber"
                        : "Loading...",
                    style: const TextStyle(
                      fontFamily: _appFont,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: getStatusColor().withOpacity(0.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      fightStatus.toUpperCase(),
                      style: TextStyle(
                        fontFamily: _appFont,
                        color: getStatusColor(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // AMOUNT SELECTOR
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [100, 200, 500, 1000].map((amt) {
                final isSelected = selectedAmount == amt;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(
                      '₱$amt',
                      style: TextStyle(
                        fontFamily: _appFont,
                        color: isSelected ? Colors.white : Colors.red[700],
                      ),
                    ),
                    selected: isSelected,
                    backgroundColor: Colors.red[700]!.withOpacity(0.09),
                    selectedColor: Colors.red[700],
                    onSelected: isAllClosed ? null : (_) => _fillAmount(amt),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // CUSTOM AMOUNT FIELD
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red[700]!.withOpacity(0.5)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.red),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      enabled: !isAllClosed,
                      style: const TextStyle(
                        fontFamily: _appFont,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Custom amount',
                        border: InputBorder.none,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      onChanged: _onAmountChanged,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // BET BUTTONS
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (!isAllClosed &&
                            !(isMeronClosed) &&
                            (int.tryParse(_amountController.text) ?? 0) >= 100)
                        ? () => _placeBet("meron")
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isMeronClosed ? Colors.grey : Colors.red[700],
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text("MERON"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (!isAllClosed &&
                            !(isWalaClosed) &&
                            (int.tryParse(_amountController.text) ?? 0) >= 100)
                        ? () => _placeBet("wala")
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isWalaClosed ? Colors.grey : Colors.blue[700],
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text("WALA"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 34),

            // TICKET LIST CARD
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long, color: Colors.amber),
                        const SizedBox(width: 10),
                        Text(
                          "Tickets",
                          style: TextStyle(
                            fontFamily: _appFont,
                            color: Colors.amber[400],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "Total: ₱$_totalBet",
                          style: const TextStyle(
                            fontFamily: _appFont,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 7),

                    _buildTicketList(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // PROCEED BUTTON
            ElevatedButton.icon(
              onPressed: !isAllClosed && _tickets.isNotEmpty
                  ? () async {
                      final prefs = await SharedPreferences.getInstance();
                      final printer = prefs.getString("printer_address");

                      if (printer == null || printer.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                                "No printer selected. Go to Settings → Printer."),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TicketPrintPage(
                            tickets: List<Map<String, dynamic>>.from(_tickets),
                          ),
                        ),
                      );

                      setState(() {
                        _tickets.clear();
                        _amountController.clear();
                        selectedAmount = null;
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[800],
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('PROCEED'),
            ),
          ],
        ),
      ),
    );
  }
}
