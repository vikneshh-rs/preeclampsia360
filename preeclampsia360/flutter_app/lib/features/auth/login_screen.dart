import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../dashboard/app_shell.dart';
import '../../shared/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final id = TextEditingController();
  final pin = TextEditingController();
  bool busy = false;
  bool hide = true;

  @override
  void dispose() {
    id.dispose();
    pin.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final loginId = id.text.trim().toUpperCase();
    final pinCode = pin.text.trim();
    if (loginId.isEmpty || pinCode.length != 6) {
      showMessage(context, 'Enter your assigned ID and 6-digit PIN.', error: true);
      return;
    }

    setState(() => busy = true);
    try {
      final data = await ApiClient.instance.post(
        '/api/v1/auth/login',
        {'login_id': loginId, 'pin': pinCode},
      );
      await ApiClient.instance.setSession(Map<String, dynamic>.from(data));

      if (!mounted) return;

      final user = ApiClient.instance.currentUser;
      if (user != null && user['must_change_pin'] == true) {
        await _showChangePinDialog(loginId, pinCode);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } catch (e) {
      if (mounted) {
        final errText = e.toString();
        if (errText.contains('Cannot reach')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.critical,
              duration: const Duration(seconds: 8),
              content: const Text('Cannot reach server. Verify PC server is running and check Server URL.'),
              action: SnackBarAction(
                label: 'Configure URL',
                textColor: Colors.white,
                onPressed: _showServerUrlDialog,
              ),
            ),
          );
        } else {
          showMessage(context, errText, error: true);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showServerUrlDialog() async {
    final urlCtrl = TextEditingController(text: ApiClient.instance.baseUrl);
    bool testing = false;
    String? testResult;
    bool? testSuccess;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.dns_rounded, color: AppColors.crimson, size: 22),
                  SizedBox(width: 8),
                  Text('Server API URL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter the IP address of your host PC running the backend server. Make sure your phone and PC are connected to the same Wi-Fi network.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'https://preeclampsia360-api.onrender.com',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Quick Presets:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.cloud_done, size: 14, color: AppColors.crimson),
                          label: const Text('Render Cloud (Live)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => setDialogState(() => urlCtrl.text = 'https://preeclampsia360-api.onrender.com'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.wifi, size: 14),
                          label: const Text('Wi-Fi LAN (192.168.1.8)', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => urlCtrl.text = 'http://192.168.1.8:8000'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.phone_android, size: 14),
                          label: const Text('Emulator (10.0.2.2)', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => urlCtrl.text = 'http://10.0.2.2:8000'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.laptop, size: 14),
                          label: const Text('Localhost (127.0.0.1)', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => urlCtrl.text = 'http://127.0.0.1:8000'),
                        ),
                      ],
                    ),
                    if (testResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: testSuccess == true ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: testSuccess == true ? const Color(0xFF86EFAC) : const Color(0xFFFECDD3)),
                        ),
                        child: Row(
                          children: [
                            Icon(testSuccess == true ? Icons.check_circle : Icons.error, color: testSuccess == true ? const Color(0xFF16A34A) : AppColors.critical, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(testResult!, style: TextStyle(fontSize: 11, color: testSuccess == true ? const Color(0xFF166534) : AppColors.critical, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: testing
                      ? null
                      : () async {
                          setDialogState(() {
                            testing = true;
                            testResult = 'Testing connection...';
                            testSuccess = null;
                          });
                          final ok = await ApiClient.instance.testConnection(urlCtrl.text.trim());
                          setDialogState(() {
                            testing = false;
                            testSuccess = ok;
                            testResult = ok ? 'Connected successfully! (HTTP 200 OK)' : 'Failed to reach server at this URL.';
                          });
                        },
                  child: testing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Test Connection'),
                ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
                    onPressed: () async {
                      await ApiClient.instance.setBaseUrl(urlCtrl.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (!mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Server URL updated to ${ApiClient.instance.baseUrl}')),
                      );
                    },
                    child: const Text('Save & Apply'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showChangePinDialog(String loginId, String currentPin) async {
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    bool dialogBusy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Update Temporary PIN'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your account has a temporary PIN. Please set a new 6-digit PIN to secure your account before continuing.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New 6-digit PIN',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New PIN',
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: dialogBusy
                      ? null
                      : () async {
                          final n = newPinCtrl.text.trim();
                          final c = confirmPinCtrl.text.trim();
                          if (n.length != 6 || int.tryParse(n) == null) {
                            showMessage(context, 'New PIN must be 6 digits.', error: true);
                            return;
                          }
                          if (n != c) {
                            showMessage(context, 'New PIN confirmation does not match.', error: true);
                            return;
                          }
                          if (n == currentPin) {
                            showMessage(context, 'New PIN cannot be the same as temporary PIN.', error: true);
                            return;
                          }

                          setDialogState(() => dialogBusy = true);
                          try {
                            await ApiClient.instance.post(
                              '/api/v1/auth/change-pin',
                              {'current_pin': currentPin, 'new_pin': n},
                            );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              showMessage(ctx, 'PIN changed successfully.');
                            }
                          } catch (err) {
                            if (ctx.mounted) {
                              showMessage(ctx, err.toString(), error: true);
                            }
                          } finally {
                            setDialogState(() => dialogBusy = false);
                          }
                        },
                  child: dialogBusy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save New PIN'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        height: 72,
                        width: 72,
                        decoration: BoxDecoration(
                          color: AppColors.paleRose,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(
                          Icons.pregnant_woman_rounded,
                          color: AppColors.crimson,
                          size: 40,
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _showServerUrlDialog,
                        icon: const Icon(Icons.dns_rounded, size: 14, color: AppColors.crimson),
                        label: Text(
                          ApiClient.instance.baseUrl.replaceAll('http://', '').replaceAll(':8000', ''),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Preeclampsia 360',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.crimson,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Maternal Monitoring & Care Coordination',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 36),
                  const P360Card(
                    child: Text(
                      'Healthcare Worker Login',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: id,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [HealthcareWorkerIdInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Healthcare Worker ID',
                      prefixIcon: Icon(Icons.badge_outlined),
                      hintText: 'e.g. PY-PHC-ANM-MUTH or PY-PHC-MUTH',
                      helperText: 'Hyphens (-) auto-fill as you type your PHC or ANM area code',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: hide,
                    decoration: InputDecoration(
                      labelText: '6-digit PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      counterText: '',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => hide = !hide),
                        icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Sign In'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No email or phone number required. Contact your facility administrator for account support.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Automatically auto-fills hyphens ("-") as healthcare workers type their ID.
/// Example formats handled:
///   - PY-PHC-MUTH       (PHC Medical Officer)
///   - PY-PHC-ANM-MUTH   (Auxiliary Nurse Midwife)
///   - PY-THC-MO-001     (Tertiary Hospital MO)
///   - PY-SYS-ADMIN-001  (System Administrator)
class HealthcareWorkerIdInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If the user is deleting, allow free deletion without force-inserting hyphens
    if (newValue.text.length < oldValue.text.length) {
      return newValue.copyWith(text: newValue.text.toUpperCase());
    }

    final raw = newValue.text.toUpperCase();
    final clean = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final buffer = StringBuffer();

    if (clean.startsWith('PY')) {
      buffer.write('PY');
      if (clean.length > 2) {
        buffer.write('-');
        final rem1 = clean.substring(2);

        // Facility level check: PHC, THC, CHC, SYS, HOSP
        if (rem1.startsWith('PHC')) {
          buffer.write('PHC');
          if (rem1.length > 3) {
            buffer.write('-');
            final rem2 = rem1.substring(3);

            // Role check: ANM, ASHA, MO, or direct area code (e.g. MUTH)
            if (rem2.startsWith('ANM')) {
              buffer.write('ANM');
              if (rem2.length > 3) {
                buffer.write('-');
                final rem3 = rem2.substring(3);
                // Area code up to 4 characters
                buffer.write(rem3.length > 4 ? rem3.substring(0, 4) : rem3);
              }
            } else if (rem2.startsWith('ASHA')) {
              buffer.write('ASHA');
              if (rem2.length > 4) {
                buffer.write('-');
                final rem3 = rem2.substring(4);
                buffer.write(rem3.length > 4 ? rem3.substring(0, 4) : rem3);
              }
            } else if (rem2.startsWith('MO')) {
              buffer.write('MO');
              if (rem2.length > 2) {
                buffer.write('-');
                final rem3 = rem2.substring(2);
                buffer.write(rem3.length > 4 ? rem3.substring(0, 4) : rem3);
              }
            } else {
              // Direct area code after PHC (e.g. PY-PHC-MUTH)
              buffer.write(rem2.length > 4 ? rem2.substring(0, 4) : rem2);
            }
          }
        } else if (rem1.startsWith('THC') || rem1.startsWith('CHC') || rem1.startsWith('SYS') || rem1.startsWith('HOSP')) {
          final prefixLen = rem1.startsWith('HOSP') ? 4 : 3;
          buffer.write(rem1.substring(0, prefixLen));
          if (rem1.length > prefixLen) {
            buffer.write('-');
            buffer.write(rem1.substring(prefixLen));
          }
        } else {
          buffer.write(rem1);
        }
      } else {
        // Just 'PY' typed, auto-fill trailing hyphen
        buffer.write('-');
      }
    } else {
      buffer.write(clean);
    }

    final result = buffer.toString();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
