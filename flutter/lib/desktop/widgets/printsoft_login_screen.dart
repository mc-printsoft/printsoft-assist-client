// 0g.14b Etap 1 (10.05.2026): Printsoft Assist — login screen email.
//
// Pierwszy ekran po starcie aplikacji. Klient wpisuje email firmowy
// (np. anna@drewpol.pl). Backend matchuje Contact w CRM, auto-tworzy
// Device + zwraca device token. Token zapisany przez bind.mainSetOption
// (RustDesk built-in storage).
//
// Endpoint: POST https://ps.printsoft.app/api/assist/agent/register-with-email
// Body: { email, rustdeskId, hostname }
// Response: { device: { id, hostname, rustdeskId }, company, contact, agentToken }
//
// Skip jesli token juz istnieje (klient zalogowany w przeszlosci).

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const String _apiBaseUrl = 'https://ps.printsoft.app';

// Klucze w RustDesk options storage (bind.mainSetOption)
const String _kPrintsoftDeviceId = 'printsoft-device-id';
const String _kPrintsoftDeviceToken = 'printsoft-device-token';
const String _kPrintsoftRegisteredEmail = 'printsoft-registered-email';
const String _kPrintsoftCompanyName = 'printsoft-company-name';
const String _kPrintsoftContactName = 'printsoft-contact-name';

/// Sprawdza czy klient jest juz zalogowany (token + deviceId zapisane).
bool isPrintsoftLoggedIn() {
  final token = bind.mainGetOptionSync(key: _kPrintsoftDeviceToken);
  final deviceId = bind.mainGetOptionSync(key: _kPrintsoftDeviceId);
  return token.isNotEmpty && deviceId.isNotEmpty;
}

/// Pobiera credentials do API calls (np. desk-ticket).
({String? token, String? deviceId, String? email}) getPrintsoftCredentials() {
  final token = bind.mainGetOptionSync(key: _kPrintsoftDeviceToken);
  final deviceId = bind.mainGetOptionSync(key: _kPrintsoftDeviceId);
  final email = bind.mainGetOptionSync(key: _kPrintsoftRegisteredEmail);
  return (
    token: token.isNotEmpty ? token : null,
    deviceId: deviceId.isNotEmpty ? deviceId : null,
    email: email.isNotEmpty ? email : null,
  );
}

/// Wyloguj klienta - usun token + deviceId.
Future<void> printsoftLogout() async {
  await bind.mainSetOption(key: _kPrintsoftDeviceToken, value: '');
  await bind.mainSetOption(key: _kPrintsoftDeviceId, value: '');
  await bind.mainSetOption(key: _kPrintsoftRegisteredEmail, value: '');
  await bind.mainSetOption(key: _kPrintsoftCompanyName, value: '');
  await bind.mainSetOption(key: _kPrintsoftContactName, value: '');
}

class PrintsoftLoginScreen extends StatefulWidget {
  /// Callback po sukcesie - main.dart zamknie login screen i pokaze app.
  final VoidCallback? onSuccess;

  const PrintsoftLoginScreen({super.key, this.onSuccess});

  @override
  State<PrintsoftLoginScreen> createState() => _PrintsoftLoginScreenState();
}

class _PrintsoftLoginScreenState extends State<PrintsoftLoginScreen> {
  final _emailController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<String> _getRustdeskId() async {
    // RustDesk hbbs nadaje ID po pierwszym launch. Czytamy przez bind.
    try {
      final id = await bind.mainGetMyId();
      return id;
    } catch (_) {
      return '';
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Wprowadź poprawny adres email');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final rustdeskId = await _getRustdeskId();
      if (rustdeskId.isEmpty) {
        setState(() {
          _errorMessage = 'Nie udało się uzyskać ID urządzenia. Poczekaj 5 sekund i spróbuj ponownie.';
          _submitting = false;
        });
        return;
      }

      final hostname = Platform.localHostname;

      // POST /api/assist/agent/register-with-email
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('$_apiBaseUrl/api/assist/agent/register-with-email'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({
        'email': email,
        'rustdeskId': rustdeskId,
        'hostname': hostname,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 201) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final device = data['device'] as Map<String, dynamic>?;
        final company = data['company'] as Map<String, dynamic>?;
        final contact = data['contact'] as Map<String, dynamic>?;
        final token = data['agentToken'] as String?;

        if (device == null || token == null) {
          setState(() {
            _errorMessage = 'Backend zwrócił niekompletne dane (brak token lub device id)';
            _submitting = false;
          });
          return;
        }

        // Zapisz credentials w RustDesk storage
        await bind.mainSetOption(key: _kPrintsoftDeviceId, value: device['id'] as String);
        await bind.mainSetOption(key: _kPrintsoftDeviceToken, value: token);
        await bind.mainSetOption(key: _kPrintsoftRegisteredEmail, value: email);
        if (company != null) {
          await bind.mainSetOption(
            key: _kPrintsoftCompanyName,
            value: company['name'] as String? ?? '',
          );
        }
        if (contact != null) {
          final fn = contact['firstName'] as String? ?? '';
          final ln = contact['lastName'] as String? ?? '';
          await bind.mainSetOption(
            key: _kPrintsoftContactName,
            value: '$fn $ln'.trim(),
          );
        }

        // Sukces - przejdz do glownego ekranu
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        }
      } else if (response.statusCode == 404) {
        setState(() {
          _errorMessage = 'Email "$email" nie znaleziony w bazie. Skontaktuj się z PRINTSOFT (hello@printsoft.app).';
          _submitting = false;
        });
      } else {
        final err = jsonDecode(body) as Map<String, dynamic>?;
        setState(() {
          _errorMessage = err?['error'] as String? ?? 'Błąd serwera (${response.statusCode})';
          _submitting = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Brak połączenia z serwerem. Sprawdź internet i spróbuj ponownie.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo "P" Printsoft
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3b82f6), Color(0xFF2563eb)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Printsoft Assist',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Zaloguj się swoim emailem firmowym',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _emailController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Email firmowy',
                    hintText: 'np. jan.kowalski@twoja-firma.pl',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF3b82f6),
                    foregroundColor: Colors.white,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Zaloguj się', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Nie masz jeszcze konta?\nSkontaktuj się z PRINTSOFT (hello@printsoft.app).',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Skip login - korzystaj z RustDesk standardowo (manual ID + hasło)
                      if (widget.onSuccess != null) {
                        widget.onSuccess!();
                      }
                    },
                    child: Text(
                      'Pomiń (użyj ręcznie)',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
