// Faza 0g.14b (10.05.2026): Printsoft Assist — "Zglos problem" dialog.
//
// Dialog wysyla zgloszenie do psDesk przez backend endpoint:
//   POST /api/assist/agent/:deviceId/desk-ticket
//
// Auth: device token z preferences (ustawiony przy register-with-email).
// Auto-link Contact + Company po deviceId po stronie backend.
//
// Fallback gdy API niedostepne: link mailto:pomoc@printsoft.pl

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const String _apiBaseUrl = 'https://ps.printsoft.app';
const String _supportEmail = 'pomoc@printsoft.pl';
const String _appVersion = '1.4.6';

class PrintsoftReportProblemDialog extends StatefulWidget {
  const PrintsoftReportProblemDialog({super.key});

  @override
  State<PrintsoftReportProblemDialog> createState() =>
      _PrintsoftReportProblemDialogState();
}

class _PrintsoftReportProblemDialogState
    extends State<PrintsoftReportProblemDialog> {
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _includeLog = true;
  bool _submitting = false;
  String? _resultMessage;
  bool _resultIsError = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<String> _readLogTail() async {
    try {
      // Mac: ~/Library/Logs/Printsoft Assist/
      // Win: %APPDATA%\Printsoft Assist\
      // Linux: ~/.local/share/printsoft-assist/
      String? logPath;
      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null) logPath = '$home/Library/Logs/RustDesk/rustdesk.log';
      } else if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'];
        if (appData != null) logPath = '$appData\\RustDesk\\log\\client\\rustdesk.log';
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) logPath = '$home/.local/share/RustDesk/log/client/rustdesk.log';
      }
      if (logPath == null) return '';
      final file = File(logPath);
      if (!await file.exists()) return '';
      final content = await file.readAsString();
      final lines = content.split('\n');
      // Ostatnie 100 linii
      final tail = lines.length > 100 ? lines.sublist(lines.length - 100) : lines;
      return tail.join('\n');
    } catch (e) {
      return 'Nie udalo sie odczytac loga: $e';
    }
  }

  String _getOsVersion() {
    try {
      if (Platform.isMacOS) {
        return 'macOS ${Platform.operatingSystemVersion}';
      } else if (Platform.isWindows) {
        return 'Windows ${Platform.operatingSystemVersion}';
      } else if (Platform.isLinux) {
        return 'Linux ${Platform.operatingSystemVersion}';
      }
      return Platform.operatingSystem;
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  Future<({String? token, String? deviceId})> _getDeviceCredentials() async {
    // TODO: real implementacja — pobierz z RustDesk preferences gdzie zapisane
    // sa token + deviceId po register-with-email.
    // Na razie return null,null -> dialog uzywa mailto fallback.
    return (token: null, deviceId: null);
  }

  Future<void> _submit() async {
    if (_subjectController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      setState(() {
        _resultMessage = 'Wypelnij tytul i opis problemu';
        _resultIsError = true;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _resultMessage = null;
    });

    try {
      final creds = await _getDeviceCredentials();

      if (creds.token == null || creds.deviceId == null) {
        // Fallback: mailto link
        await _openMailtoFallback();
        return;
      }

      final logTail = _includeLog ? await _readLogTail() : '';

      final response = await HttpClient()
          .postUrl(Uri.parse('$_apiBaseUrl/api/assist/agent/${creds.deviceId}/desk-ticket'))
          .then((req) {
        req.headers.set('Authorization', 'Bearer ${creds.token}');
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({
          'subject': _subjectController.text.trim(),
          'description': _descriptionController.text.trim(),
          'logTail': logTail,
          'appVersion': _appVersion,
          'hostname': Platform.localHostname,
          'osVersion': _getOsVersion(),
        }));
        return req.close();
      });

      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 201) {
        final data = jsonDecode(body);
        setState(() {
          _resultMessage = data['message'] ??
              'Zgloszenie ${data['formattedNumber']} zostalo zarejestrowane.';
          _resultIsError = false;
        });
      } else {
        // API blad — zaproponuj mailto
        setState(() {
          _resultMessage =
              'Wyslanie nie udalo sie (kod ${response.statusCode}). Sproboj wyslac email.';
          _resultIsError = true;
        });
      }
    } catch (e) {
      setState(() {
        _resultMessage = 'Blad: $e. Mozesz wyslac email zamiast.';
        _resultIsError = true;
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _openMailtoFallback() async {
    final subject = _subjectController.text.trim().isEmpty
        ? 'Zgloszenie z Printsoft Assist'
        : _subjectController.text.trim();
    final body = '''${_descriptionController.text.trim()}

---
Wyslane z aplikacji Printsoft Assist
Wersja: $_appVersion
System: ${_getOsVersion()}
Hostname: ${Platform.localHostname}''';

    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      setState(() {
        _resultMessage = 'Otwarto klienta poczty. Wyslij maila do $_supportEmail.';
        _resultIsError = false;
      });
    } else {
      // Last resort — clipboard
      await Clipboard.setData(ClipboardData(text: '$_supportEmail\n\n$subject\n\n$body'));
      setState(() {
        _resultMessage = 'Skopiowano dane do schowka. Wklej w email do $_supportEmail.';
        _resultIsError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.report_problem_outlined,
                      color: Theme.of(context).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text('Zglos problem',
                      style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Opisz problem ktory napotkales. Twoje zgloszenie trafi bezposrednio do zespolu Print-Soft.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Tytul *',
                  hintText: 'Np. Drukarka nie chce drukowac',
                  border: OutlineInputBorder(),
                ),
                maxLength: 200,
                enabled: !_submitting,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Opis problemu *',
                  hintText: 'Co sie stalo? Z jaka aplikacja? Co probowales zrobic?',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 6,
                maxLength: 5000,
                enabled: !_submitting,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('Dolacz log Printsoft Assist',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Pomocne gdy problem dotyczy zdalnego polaczenia',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                value: _includeLog,
                onChanged: _submitting ? null : (v) => setState(() => _includeLog = v ?? true),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_resultMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _resultIsError
                        ? Colors.red.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _resultIsError ? Colors.red : Colors.green,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _resultMessage!,
                    style: TextStyle(
                      color: _resultIsError ? Colors.red : Colors.green[800],
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _submitting ? null : _openMailtoFallback,
                    icon: const Icon(Icons.email_outlined, size: 16),
                    label: const Text('Wyslij email zamiast'),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                        child: const Text('Anuluj'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send, size: 16),
                        label: Text(_submitting ? 'Wysylanie...' : 'Wyslij'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper do otwierania dialogu z dowolnego miejsca w app.
Future<void> showPrintsoftReportProblemDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const PrintsoftReportProblemDialog(),
  );
}
