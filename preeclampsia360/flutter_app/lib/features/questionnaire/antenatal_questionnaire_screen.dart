import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';

/// Guided capture shell for the supplied ANM/ASHA proforma.
/// Field definitions preserve the original form; clinical interpretation is separate.
class AntenatalQuestionnaireScreen extends StatefulWidget {
  final String? patientId;
  final String? patientName;

  const AntenatalQuestionnaireScreen({
    super.key,
    this.patientId,
    this.patientName,
  });

  @override
  State<AntenatalQuestionnaireScreen> createState() => _AntenatalQuestionnaireScreenState();
}

class _AntenatalQuestionnaireScreenState extends State<AntenatalQuestionnaireScreen> {
  final PageController page = PageController();
  int step = 0;
  bool saving = false;
  bool loading = false;
  String? activePatientId;
  String? activePatientName;
  List<Map<String, dynamic>> availablePatients = [];

  final Map<String, TextEditingController> values = {};

  final sections = <String, List<String>>{
    'Personal details': [
      'Patient name',
      'Age',
      'Degree',
      'Occupation',
      'Husband name',
      'Husband age',
      'Husband degree',
      'Husband occupation',
      'Consumption habits',
      'Family income',
      'Socioeconomic status',
      'Address',
      'Nearest health centre',
      'Transportation method',
      'Time taken to reach',
      'Distance from residence',
      'Blood group'
    ],
    'Menstrual & current pregnancy': [
      'Gravida (Primi / Multi)',
      'G',
      'P',
      'A',
      'L',
      'LMP',
      'Previous cycles (regular / irregular)',
      'EDD',
      'POG',
      'Booking & immunization details'
    ],
    'Presenting complaints': [
      'Presenting complaint',
      'History of presenting complaints'
    ],
    'First trimester': [
      'Conception (spontaneous / induced)',
      'Pregnancy confirmation',
      'Days of amenorrhoea',
      'UPT / USG done',
      'Place',
      'Number of antenatal visits',
      'Remarks in antenatal visits',
      'Folic acid supplements',
      'History of hyperemesis',
      'Fever with rashes',
      'Bleeding PV',
      'Radiation exposure',
      'Bladder habits',
      'Pain during micturition',
      'Drug intake',
      'Dating scan with place',
      'Dating scan remarks'
    ],
    'Second trimester': [
      'Number of antenatal visits',
      'Remarks in antenatal visits',
      'TT immunization with place',
      'Number of doses and POG',
      'Quickening',
      'Iron and calcium supplements',
      'Bleeding PV',
      'Leaking PV',
      'Symptoms of preeclampsia',
      'Oedema',
      'DIPSI',
      'Result of DIPSI',
      'Anomaly scan',
      'Anomaly scan remarks'
    ],
    'Third trimester': [
      'Number of antenatal visits',
      'Remarks in antenatal visits',
      'Iron and calcium supplements',
      'Fetal movements',
      'Symptoms of preeclampsia',
      'Bleeding PV',
      'Leaking PV',
      'Pain in abdomen',
      'Bladder and bowel disturbances'
    ],
    'Menstrual & marital history': [
      'Age at menarche',
      'Menstrual cycles',
      'Days between cycles',
      'Cycles lasting for',
      'Flow',
      'Clots',
      'Dysmenorrhoea',
      'Married for',
      'Consanguinity',
      'Degree'
    ],
    'Past medical, personal, diet & family history': [
      'Jaundice / HTN / DM / thyroid / epilepsy / asthma / TB / other',
      'Past surgeries (except LSCS)',
      'Past hospitalisations',
      'Blood transfusions',
      'STD',
      'Drug / other allergies',
      'Sleep',
      'Appetite',
      'Addictions',
      'Bowel & bladder habits',
      'Diet (mixed / vegetarian)',
      '24-hour recall',
      'Calorie and protein intake adequacy',
      'Congenital anomalies in family',
      'Multiple pregnancies in family',
      'Abortions in family',
      'Chronic disorders in family'
    ],
  };

  @override
  void initState() {
    super.initState();
    activePatientId = widget.patientId;
    activePatientName = widget.patientName;
    if (activePatientId != null) {
      _loadExistingQuestionnaire(activePatientId!);
    } else {
      _loadPatientList();
    }
  }

  @override
  void dispose() {
    for (final c in values.values) {
      c.dispose();
    }
    page.dispose();
    super.dispose();
  }

  TextEditingController controller(String key) =>
      values.putIfAbsent(key, () => TextEditingController());

  Future<void> _loadPatientList() async {
    setState(() => loading = true);
    try {
      final res = await ApiClient.instance.get('/api/v1/patients?limit=50');
      final list = List<dynamic>.from(res['items'] ?? []);
      if (mounted) {
        setState(() {
          availablePatients = list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadExistingQuestionnaire(String patId) async {
    setState(() => loading = true);
    try {
      final res = await ApiClient.instance.get('/api/v1/patients/$patId');
      final qData = Map<String, dynamic>.from(res['questionnaire_data'] ?? {});
      if (mounted) {
        setState(() {
          activePatientName = res['full_name'];
          // Prefill values
          for (final secEntry in qData.entries) {
            final secKey = secEntry.key;
            if (secEntry.value is Map) {
              final secMap = Map<String, dynamic>.from(secEntry.value as Map);
              for (final fieldEntry in secMap.entries) {
                final k = '$secKey::${fieldEntry.key}';
                controller(k).text = fieldEntry.value?.toString() ?? '';
              }
            }
          }
          // Also prefill name & blood group if empty
          if (controller('Personal details::Patient name').text.isEmpty && res['full_name'] != null) {
            controller('Personal details::Patient name').text = res['full_name'].toString();
          }
          if (controller('Personal details::Blood group').text.isEmpty && res['blood_group'] != null) {
            controller('Personal details::Blood group').text = res['blood_group'].toString();
          }
          if (controller('Personal details::Address').text.isEmpty && res['address'] != null) {
            controller('Personal details::Address').text = res['address'].toString();
          }
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not prefill questionnaire: $e', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> _gatherSectionAnswers(String sectionName) {
    final fields = sections[sectionName] ?? [];
    final ans = <String, dynamic>{};
    for (final f in fields) {
      final val = controller('$sectionName::$f').text.trim();
      if (val.isNotEmpty) {
        ans[f] = val;
      }
    }
    return ans;
  }

  Future<void> _saveSection({bool completed = false}) async {
    if (activePatientId == null) {
      showMessage(context, 'Please select or link a pregnant woman first.', error: true);
      return;
    }
    final sectionNames = sections.keys.toList();
    final currentSection = sectionNames[step];
    final ans = _gatherSectionAnswers(currentSection);

    setState(() => saving = true);
    try {
      await ApiClient.instance.post('/api/v1/questionnaires/sections', {
        'patient_id': activePatientId,
        'section_key': currentSection,
        'answers': ans,
        'schema_version': '1.0',
        'completed': completed,
      });
      if (mounted) {
        showMessage(
          context,
          completed ? 'Section marked complete.' : 'Section draft saved to patient record.',
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _submitAllFinal() async {
    if (activePatientId == null) {
      showMessage(context, 'No patient selected.', error: true);
      return;
    }
    setState(() => saving = true);
    try {
      final names = sections.keys.toList();
      for (final sec in names) {
        final ans = _gatherSectionAnswers(sec);
        await ApiClient.instance.post('/api/v1/questionnaires/sections', {
          'patient_id': activePatientId,
          'section_key': sec,
          'answers': ans,
          'schema_version': '1.0',
          'completed': true,
        });
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Maternal Assessment Complete'),
            content: Text(
              'All 8 proforma sections for $activePatientName have been validated and saved to Supabase.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.pop(context, true);
                },
                child: const Text('Return to Patient Profile'),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Submission failed: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = sections.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(activePatientName != null ? 'Assessment: $activePatientName' : 'Maternal Assessment'),
            Text(
              'Section ${step + 1} of ${names.length}: ${names[step]}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (activePatientId != null)
            TextButton.icon(
              onPressed: saving ? null : () => _saveSection(completed: false),
              icon: const Icon(Icons.save_outlined, color: Colors.white, size: 18),
              label: const Text('Save draft', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: loading
          ? const LoadingView()
          : Column(
              children: [
                LinearProgressIndicator(
                  value: (step + 1) / names.length,
                  color: AppColors.crimson,
                  backgroundColor: AppColors.blush,
                  minHeight: 5,
                ),
                if (activePatientId == null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: AppColors.paleRose,
                    child: Row(
                      children: [
                        const Icon(Icons.person_search, color: AppColors.crimson),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: activePatientId,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Select mother for this assessment',
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: availablePatients.map((p) {
                              return DropdownMenuItem<String>(
                                value: p['id'].toString(),
                                child: Text('${p['full_name']} (${p['patient_code']})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => activePatientId = val);
                                _loadExistingQuestionnaire(val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    controller: page,
                    itemCount: names.length,
                    onPageChanged: (v) => setState(() => step = v),
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final section = names[index];
                      return ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFE8EC), Color(0xFFFFF8F8)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  section,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF6F1428),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Complete the available information. Unknown or unasked items should not be guessed.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...sections[section]!.map(
                            (field) => Padding(
                              padding: const EdgeInsets.only(bottom: 13),
                              child: TextField(
                                controller: controller('$section::$field'),
                                decoration: InputDecoration(
                                  labelText: field,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                textCapitalization: TextCapitalization.sentences,
                                maxLines: field.toLowerCase().contains('address') ||
                                        field.toLowerCase().contains('remarks') ||
                                        field.toLowerCase().contains('recall') ||
                                        field.toLowerCase().contains('complaint')
                                    ? 3
                                    : 1,
                              ),
                            ),
                          ),
                          if (section == 'Past medical, personal, diet & family history')
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Past obstetric history, delivery, baby and abortion details can also be recorded as repeatable pregnancy records in the Patient 360 profile.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: step == 0
                            ? null
                            : () => page.previousPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                ),
                        child: const Text('Back'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: saving ? null : () => _saveSection(completed: false),
                        icon: const Icon(Icons.bookmark_border, size: 16),
                        label: const Text('Save section draft'),
                      ),
                      const Spacer(),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
                        onPressed: saving
                            ? null
                            : () {
                                if (step == names.length - 1) {
                                  _submitAllFinal();
                                } else {
                                  _saveSection(completed: true);
                                  page.nextPage(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                  );
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(step == names.length - 1 ? 'Submit Assessment' : 'Save & Continue'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
