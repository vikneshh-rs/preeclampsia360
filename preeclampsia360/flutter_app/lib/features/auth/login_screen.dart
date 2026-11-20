import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final patientIdCtrl = TextEditingController();
  bool isPatientLogin = false;
  bool busy = false;
  bool hide = true;

  @override
  void dispose() {
    id.dispose();
    pin.dispose();
    patientIdCtrl.dispose();
    super.dispose();
  }

  Future<void> submitPatientLogin() async {
    final pId = patientIdCtrl.text.trim().toUpperCase();
    if (pId.isEmpty) {
      showMessage(context, 'Please enter your Patient ID (e.g. PE360-xxxxxx).', error: true);
      return;
    }

    setState(() => busy = true);
    try {
      final data = await ApiClient.instance.patientLogin(pId);
      await ApiClient.instance.setSession(Map<String, dynamic>.from(data));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } catch (e) {
      if (mounted) {
        final errText = e.toString();
        if (errText.contains('Cannot reach')) {
          showMessage(context, 'Cannot reach Preeclampsia 360 server. Check internet connection.', error: true);
        } else {
          showMessage(context, errText, error: true);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          showMessage(context, 'Cannot reach Preeclampsia 360 server. Check internet connection.', error: true);
        } else {
          showMessage(context, errText, error: true);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
              title: const Text('Security: Set New 6-Digit PIN'),
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
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Crest / Emblem (Medical maternity icon)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: AppColors.softBlush,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.pregnant_woman_rounded,
                        color: AppColors.deepBurgundy,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Preeclampsia 360',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.darkWine,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Maternal Monitoring & Care Coordination',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.slate,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Segmented Switch between Staff Login and Patient Login
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Staff Login'),
                        icon: Icon(Icons.badge_outlined, size: 16),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Patient Login'),
                        icon: Icon(Icons.pregnant_woman_rounded, size: 16),
                      ),
                    ],
                    selected: {isPatientLogin},
                    onSelectionChanged: (s) => setState(() => isPatientLogin = s.first),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  if (!isPatientLogin) ...[
                    // Healthcare Worker Login Card
                    P360Card(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Healthcare Worker Login',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkWine,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Access clinical care coordination for your facility.',
                            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.slate),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: id,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [HealthcareWorkerIdInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Healthcare Worker ID',
                        prefixIcon: Icon(Icons.badge_outlined, color: AppColors.slate),
                        hintText: 'e.g. PY-PHC-MUTH or PY-PHC-ANM-MUTH',
                        helperText: 'Hyphens (-) auto-fill as you type your PHC or ANM area code',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: pin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      obscureText: hide,
                      decoration: InputDecoration(
                        labelText: '6-digit PIN',
                        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.slate),
                        counterText: '',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => hide = !hide),
                          icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.slate),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sign In'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'No email or phone number required. Contact your facility administrator for account support.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(color: AppColors.mutedGrey, fontSize: 12),
                    ),
                  ] else ...[
                    // Patient Login Card
                    P360Card(
                      color: AppColors.softBlush,
                      border: const BorderSide(color: Color(0xFFFECDD3)),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient Self-Monitoring Login',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.deepBurgundy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enter the unique Patient ID assigned to you during registration by your PHC Medical Officer or ANM.',
                            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.darkWine, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: patientIdCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Patient ID *',
                        prefixIcon: Icon(Icons.badge_outlined, color: AppColors.deepBurgundy),
                        hintText: 'e.g. PE360-B635ACA278',
                        helperText: 'Case-insensitive. No password or PIN required.',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: busy ? null : submitPatientLogin,
                        icon: busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.login_rounded),
                        label: Text(
                          busy ? 'Signing in…' : 'Sign In as Patient',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'If you do not have your Patient ID, please ask your Village Health Nurse (ANM) or visit your PHC.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(color: AppColors.mutedGrey, fontSize: 12),
                    ),
                  ],
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
class HealthcareWorkerIdInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
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

        if (rem1.startsWith('PHC')) {
          buffer.write('PHC');
          if (rem1.length > 3) {
            buffer.write('-');
            final rem2 = rem1.substring(3);

            if (rem2.startsWith('ANM')) {
              buffer.write('ANM');
              if (rem2.length > 3) {
                buffer.write('-');
                final rem3 = rem2.substring(3);
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
