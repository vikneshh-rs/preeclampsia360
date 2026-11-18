import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../clinical/bp_entry_screen.dart';

class PatientRegistrationScreen extends StatefulWidget {
  const PatientRegistrationScreen({super.key});
  @override
  State<PatientRegistrationScreen> createState() => _PatientRegistrationScreenState();
}

class _PatientRegistrationScreenState extends State<PatientRegistrationScreen> {
  final form = GlobalKey<FormState>();
  int step = 0;
  bool saving = false;

  final name = TextEditingController();
  final age = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final blood = TextEditingController();
  final lmp = TextEditingController();
  final edd = TextEditingController();
  final gravida = TextEditingController();
  final parity = TextEditingController();
  final abortions = TextEditingController();
  final living = TextEditingController();
  final husband = TextEditingController();
  final occupation = TextEditingController();
  final income = TextEditingController();
  final healthCenter = TextEditingController();
  final transport = TextEditingController();
  final distance = TextEditingController();
  final menarche = TextEditingController();
  final married = TextEditingController();
  final medical = TextEditingController();
  final allergy = TextEditingController();
  final diet = TextEditingController();
  final pastOb = TextEditingController();
  final delivery = TextEditingController();
  final baby = TextEditingController();
  final family = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    age.dispose();
    phone.dispose();
    address.dispose();
    blood.dispose();
    lmp.dispose();
    edd.dispose();
    gravida.dispose();
    parity.dispose();
    abortions.dispose();
    living.dispose();
    husband.dispose();
    occupation.dispose();
    income.dispose();
    healthCenter.dispose();
    transport.dispose();
    distance.dispose();
    menarche.dispose();
    married.dispose();
    medical.dispose();
    allergy.dispose();
    diet.dispose();
    pastOb.dispose();
    delivery.dispose();
    baby.dispose();
    family.dispose();
    super.dispose();
  }

  int? _int(String v) => int.tryParse(v.trim());

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final q = <String, dynamic>{
        'personal_details': {
          'age': _int(age.text),
          'husband_name': husband.text.trim(),
          'occupation': occupation.text.trim(),
          'family_income': income.text.trim(),
          'nearest_health_center': healthCenter.text.trim(),
          'transportation_method': transport.text.trim(),
          'distance_from_residence': distance.text.trim(),
        },
        'obstetric_history': {
          'gravida': _int(gravida.text),
          'parity': _int(parity.text),
          'abortions': _int(abortions.text),
          'living_children': _int(living.text),
          'past_obstetric_history': pastOb.text.trim(),
          'delivery_details': delivery.text.trim(),
          'baby_details': baby.text.trim(),
        },
        'menstrual_history': {
          'age_at_menarche': menarche.text.trim(),
          'married_for': married.text.trim(),
        },
        'medical_history': {
          'past_medical_history': medical.text.trim(),
          'allergies': allergy.text.trim(),
        },
        'diet_history': {
          'diet': diet.text.trim(),
        },
        'family_history': {
          'history': family.text.trim(),
        },
      };

      final payload = {
        'full_name': name.text.trim(),
        'date_of_birth': null,
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim(),
        'blood_group': blood.text.trim().isEmpty ? null : blood.text.trim(),
        'lmp': lmp.text.trim().isEmpty ? null : lmp.text.trim(),
        'edd': edd.text.trim().isEmpty ? null : edd.text.trim(),
        'gravida': _int(gravida.text),
        'parity': _int(parity.text),
        'abortions': _int(abortions.text),
        'living_children': _int(living.text),
        'questionnaire': q,
      };

      final res = await ApiClient.instance.post('/api/v1/patients', payload);
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: const Text('Mother Registered Successfully'),
            content: Text(
              'Mother ${name.text.trim()} has been registered with ID ${res['patient_code'] ?? 'PE360'}.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.pop(context, true);
                },
                child: const Text('Return to Patient List'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BPEntryScreen(
                        initialPatientId: res['id']?.toString(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.monitor_heart, size: 18),
                label: const Text('Record Blood Pressure'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Personal details',
      'Obstetric history',
      'Medical & lifestyle',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Register pregnant woman')),
      body: Form(
        key: form,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step ${step + 1} of 3  •  ${titles[step]}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.crimson),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: (step + 1) / 3,
                    color: AppColors.crimson,
                    backgroundColor: AppColors.blush,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (step == 0) ...[
                    _section('Mother’s details'),
                    _field('Full name', name, required: true),
                    _field('Age', age, numeric: true),
                    _field('Phone (optional)', phone, numeric: true),
                    _field('Address', address, maxLines: 2),
                    _field('Blood group (e.g. O+, B+, A+)', blood),
                    _section('Family & access'),
                    _field('Husband / partner name', husband),
                    _field('Occupation', occupation),
                    _field('Family income', income),
                    _field('Nearest health centre', healthCenter),
                    _field('Transportation method', transport),
                    _field('Distance from residence', distance),
                  ],
                  if (step == 1) ...[
                    _section('Pregnancy details'),
                    _field('LMP (YYYY-MM-DD)', lmp),
                    _field('EDD (YYYY-MM-DD)', edd),
                    _field('Gravida (G)', gravida, numeric: true),
                    _field('Parity (P)', parity, numeric: true),
                    _field('Abortions (A)', abortions, numeric: true),
                    _field('Living children (L)', living, numeric: true),
                    _field('Past obstetric summary', pastOb, maxLines: 3),
                    _field('Delivery details', delivery, maxLines: 2),
                    _field('Baby details', baby, maxLines: 2),
                  ],
                  if (step == 2) ...[
                    _section('Menstrual & marital history'),
                    _field('Age at menarche', menarche),
                    _field('Married for', married),
                    _section('Medical history'),
                    _field('Past medical history (HTN, DM, thyroid, TB, etc.)', medical, maxLines: 3),
                    _field('Drug / other allergies', allergy, maxLines: 2),
                    _section('Diet & family history'),
                    _field('Diet history / 24-hour recall', diet, maxLines: 3),
                    _field('Family history (congenital anomalies, multiple pregnancy, chronic disorders)', family, maxLines: 3),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => step--),
                        child: const Text('Back'),
                      ),
                    ),
                  if (step > 0) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
                      onPressed: saving
                          ? null
                          : () => step < 2 ? setState(() => step++) : save(),
                      child: saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(step < 2 ? 'Continue' : 'Save patient'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(
          s,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.crimson),
        ),
      );

  Widget _field(
    String label,
    TextEditingController c, {
    bool required = false,
    bool numeric = false,
    int maxLines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: maxLines,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          validator: required ? (v) => v == null || v.trim().isEmpty ? 'Required field' : null : null,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
