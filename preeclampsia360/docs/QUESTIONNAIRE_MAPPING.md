# ANM / ASHA maternal assessment questionnaire mapping

This mapping preserves the supplied proforma wording and separates repeated pregnancy records from current-pregnancy sections. It is a data-capture model, not a clinical guideline. Optionality and role ownership must be approved by the pilot clinical lead before production.

## Personal details
- Patient: name, age, degree, occupation.
- Husband: name, age, degree, occupation, consumption habits.
- Family income, socioeconomic status, address, nearest health centre, transport method, travel time, distance from residence.
- Blood group; gravida (Primi/Multi); G/P/A/L; LMP; previous cycles (regular/irregular); EDD; POG; booking and immunisation details (place and POG at immunisation).

## Presenting complaint
- Presenting complaint (free text).
- History of presenting complaints (free text).

## History of present pregnancy — current pregnancy, by trimester
### First trimester
Conception (spontaneous/induced); pregnancy confirmation; days of amenorrhoea; UPT/USG done and place; number of antenatal visits; remarks; folic acid supplements; history of hyperemesis; fever with rashes; bleeding per vaginum; radiation exposure; bladder habits; pain during micturition; drug intake; dating scan with place; remarks in dating scan.
### Second trimester
Number of antenatal visits; remarks; TT immunisation with place; number of doses including POG; quickening; iron and calcium supplements; bleeding PV; leaking PV; symptoms of preeclampsia; oedema; DIPSI and result; anomaly scan and remarks.
### Third trimester
Number of antenatal visits; remarks; iron and calcium supplements; fetal movements; symptoms of preeclampsia; bleeding PV; leaking PV; abdominal pain; bladder and bowel disturbances.

## Menstrual and marital history
- Age at menarche; cycle regularity; days between cycles; cycle duration; flow; clots; dysmenorrhoea; LMP.
- Married for; consanguinity; degree.

## Past obstetric history — repeat one record per prior pregnancy
- Conception spontaneous/induced; pregnancy confirmation; days of amenorrhoea; UPT/USG and POG; booked and immunised; antenatal complications; supplements taken.
- Delivery: place; vaginal/caesarean; spontaneous/induced/instrumental; incision type; time of labour; cause; episiotomy; complications; catheter removal days after labour; stitches removal days after labour; blood transfusion; postpartum fever/haemorrhage; hospital days; days until resuming normal work/routine.
- Baby: live birth/stillbirth; sex; weight; cried immediately; NICU; anomalies; breastfeeding duration; present age; normal milestones.
- Abortion: spontaneous/induced; reason; POG; medical/surgical; fever or foul-smelling discharge; resumption of menses; contraception after abortion.

## Medical, personal, diet and family history
- Past medical: jaundice, HTN, DM, thyroid disorders, epilepsy, bronchial asthma, TB, other; surgeries (except LSCS); hospitalisations; blood transfusions; STD; drug/other allergies.
- Personal: sleep; appetite; addictions; allergy; bowel and bladder habits.
- Diet: mixed/vegetarian; 24-hour recall; adequacy of calorie and protein intake.
- Family: congenital anomalies; multiple pregnancies; abortions; chronic disorders (DM/HTN/thyroid/TB).

## Implementation rules
- Keep source responses as captured; do not infer absent answers.
- Support `yes/no/unknown/not-asked/not-applicable` where the form requires a binary history and preserve a free-text detail field.
- Use separate structured sections and revision history. Prior pregnancies are repeatable child records.
- Store dates in ISO-8601/date types; store units with measurements.
- Do not compute a clinical risk category from this questionnaire without a versioned, approved rule set.
- ANM/ASHA role-level field ownership remains configurable pending clinical governance approval.
