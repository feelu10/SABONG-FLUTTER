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
    String fightStatus = "Loading…";
    bool isMeronClosed = false;
    bool isWalaClosed = false;
    static const String _appFont = 'Roboto';

    @override
    void initState() {
      super.initState();
      _loadApiUrl();
      _checkUserStatus();
    }

    Future<void> _loadApiUrl() async {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('api_url');
      setState(() => apiUrl = url);
      if (url != null) {
        await _fetchFightStatus(url);
        _timer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchFightStatus(url));
      }
    }

    Future<void> _checkUserStatus() async {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      final apiUrl = prefs.getString('api_url');

      if (username == null || apiUrl == null) return;

      final response = await http.post(
        Uri.parse('$apiUrl/api/check-user-status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );

      if (response.statusCode == 403 || response.statusCode == 404) {
        // Save api_url before clearing
        final preservedApi = apiUrl;

        // Clear all and restore api_url only
        await prefs.clear();
        await prefs.setString('api_url', preservedApi);

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Access Denied"),
            content: const Text("Your account has been deactivated. You will now be logged out."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
    }

    Future<void> _fetchFightStatus(String url) async {
      try {
        final response = await http.get(Uri.parse('$url/api/fights/last-completed'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            currentFightId = data['id'];
            currentFightNumber = data['fight_number']?.toString();
            fightStatus = data['status']?.toString().toLowerCase() ?? "unknown";
            isMeronClosed = data['is_meron_close'] == true || data['is_meron_close'] == 1;
            isWalaClosed = data['is_wala_close'] == true || data['is_wala_close'] == 1;
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
        case "loading…":
          return Colors.amber[700]!;
        default:
          return Colors.grey[600]!;
      }
    }

    bool get isAllClosed => fightStatus == "closed" || fightStatus == "error" || fightStatus == "unknown" || fightStatus == "loading…";

    void _fillAmount(int amt) {
      _amountController.text = '$amt';
      setState(() {
        selectedAmount = amt;
      });
    }

    void _onAmountChanged(String value) {
      final amt = int.tryParse(value);
      setState(() {
        selectedAmount = amt;
      });
    }

    // Future<String> _getUserBalance() async {
    //   final prefs = await SharedPreferences.getInstance();
    //   final username = prefs.getString('username');
    //   final api = prefs.getString('api_url');

    //   if (username == null || api == null) return '0.00';

    //   try {
    //     final res = await http.get(Uri.parse('$api/api/user/balance/logs/$username'));
    //     if (res.statusCode == 200) {
    //       final data = jsonDecode(res.body);
    //       final calculatedBalance = double.tryParse(data['calculated_balance'].toString()) ?? 0.0;

    //       return calculatedBalance.toStringAsFixed(2);
    //     }
    //   } catch (e) {
    //     print('Error getting balance: $e');
    //   }

    //   return '0.00';
    // }


    void _placeBet(String side) {
      final amt = int.tryParse(_amountController.text) ?? 0;
      if (amt <= 0) return;
      HapticFeedback.lightImpact();

      setState(() {
        // Check if a ticket for this side already exists
        final idx = _tickets.indexWhere((t) =>
            t['side'] == side &&
            t['fight_id'] == currentFightId &&
            t['fight_number'] == currentFightNumber);
        if (idx != -1) {
          // Increment the amount
          _tickets[idx]['amount'] += amt;
        } else {
          // Add new ticket
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
          content: Text('Ticketed ₱$amt on ${side.toUpperCase()}',
              style: const TextStyle(
                  fontFamily: _appFont, fontWeight: FontWeight.w400)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 1),
          backgroundColor:
              side == 'meron' ? Colors.red[700] : Colors.blue[700],
        ),
      );
      _amountController.clear();
      setState(() => selectedAmount = null);
    }

    int get _totalBet =>
        _tickets.fold(0, (sum, ticket) => sum + (ticket['amount'] as int));

    Widget _buildAmountSelector() {
      final chips = [100, 200, 500, 1000];
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: chips.map((amt) {
          final isSelected = selectedAmount == amt;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text('₱$amt',
                  style: TextStyle(
                    fontFamily: _appFont,
                    color: isSelected ? Colors.white : Colors.red[700],
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  )),
              selected: isSelected,
              backgroundColor: Colors.red[700]!.withOpacity(0.09),
              selectedColor: Colors.red[700],
              onSelected: isAllClosed ? null : (_) => _fillAmount(amt),
              showCheckmark: false,
              side: BorderSide(color: Colors.red[700]!.withOpacity(0.4)),
              elevation: 0,
            ),
          );
        }).toList(),
      );
    }

    @override
    void dispose() {
      _amountController.dispose();
      _timer?.cancel();
      super.dispose();
    }

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
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
      }
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _tickets.length,
        separatorBuilder: (_, __) => Divider(color: Colors.grey[800]),
        itemBuilder: (ctx, idx) {
          final ticket = _tickets[idx];
          final color = ticket['side'] == 'meron' ? Colors.red[700]! : Colors.blue[700]!;
          final icon = ticket['side'] == 'meron' ? Icons.sports_mma : Icons.sports_mma_outlined;
          return Dismissible(
            key: ValueKey('${ticket['side']}_${ticket['fight_id']}_${ticket['fight_number']}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red[800],
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: const Icon(Icons.delete, color: Colors.white, size: 28),
            ),
            onDismissed: (direction) {
              setState(() {
                _tickets.removeAt(idx);
              });
            },
            child: ListTile(
              leading: Icon(icon, color: color),
              title: Text(
                ticket['side'].toString().toUpperCase(),
                style: TextStyle(
                  fontFamily: _appFont,
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1.1,
                ),
              ),
              trailing: Text(
                "₱${ticket['amount']}",
                style: TextStyle(
                  fontFamily: _appFont,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      );
    }

    Widget _buildBetButton(String side, Color color, IconData icon, bool isClosed) {
      final isAmountValid = (int.tryParse(_amountController.text) ?? 0) > 0;
      final disabled = isAllClosed || isClosed;
      return Expanded(
        child: ElevatedButton.icon(
          onPressed: isAmountValid && !disabled
              ? () => _placeBet(side.toLowerCase())
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: disabled ? Colors.grey[700] : color,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: TextStyle(
              fontFamily: _appFont,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 1.1,
            ),
          ),
          icon: Icon(icon, size: 22),
          label: Text(disabled ? '$side CLOSED' : side.toUpperCase()),
        ),
      );
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFF101014),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // -- FIGHT INFO BAR (without balance) --
              Container(
                margin: const EdgeInsets.only(bottom: 22),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: getStatusColor().withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sports_mma, color: Colors.amber[700]),
                    const SizedBox(width: 14),
                    Text(
                      currentFightNumber != null
                          ? "Fight #$currentFightNumber"
                          : "Loading...",
                      style: TextStyle(
                        fontFamily: _appFont,
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 18),
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
                          fontSize: 13.5,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isAllClosed)
                      Icon(Icons.lock, color: Colors.red[700], size: 22),
                  ],
                ),
              ),

              const Text(
                'SELECT BET AMOUNT',
                style: TextStyle(
                  fontFamily: _appFont,
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              _buildAmountSelector(),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red[700]!.withOpacity(0.5)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.edit, color: Colors.red, size: 22),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        enabled: !isAllClosed,
                        style: const TextStyle(
                          fontFamily: _appFont,
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.normal,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Custom amount',
                          hintStyle: TextStyle(
                            fontFamily: _appFont,
                            color: Colors.grey,
                            fontWeight: FontWeight.w300,
                          ),
                          border: InputBorder.none,
                        ),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: _onAmountChanged,
                        onSubmitted: _onAmountChanged,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBetButton('Meron', Colors.red[700]!, Icons.sports_mma, isMeronClosed),
                  const SizedBox(width: 12),
                  _buildBetButton('Wala', Colors.blue[700]!, Icons.sports_mma_outlined, isWalaClosed),
                ],
              ),
              const SizedBox(height: 34),
              Card(
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_long, color: Colors.amber, size: 23),
                          const SizedBox(width: 10),
                          Text(
                            "Tickets",
                            style: TextStyle(
                              fontFamily: _appFont,
                              color: Colors.amber[400],
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            "Total: ₱$_totalBet",
                            style: TextStyle(
                              fontFamily: _appFont,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
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
              ElevatedButton.icon(
                onPressed: !isAllClosed && _tickets.isNotEmpty
                    ? () async {
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
                  textStyle: TextStyle(
                    fontFamily: _appFont,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 1,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('PROCEED'),
              ),
              const SizedBox(height: 22),
              Text(
                'Choose your bet amount, select side, and ticket as many as you want. Tap PROCEED when done.',
                style: TextStyle(
                  fontFamily: _appFont,
                  color: Colors.grey[400],
                  fontStyle: FontStyle.italic,
                  fontSize: 13.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

  }
