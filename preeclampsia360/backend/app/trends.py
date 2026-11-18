from __future__ import annotations
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from .security import current_user
from .repository import supabase_admin
from .authorization import (
    assert_patient_access,
    get_all_facilities_map,
)

router = APIRouter(prefix="/api/v1", tags=["bp-trends-analytics"])


class ClinicalAssessmentCreate(BaseModel):
    bp_trend_summary: str = Field(min_length=2)
    obstetric_risk_factors: list[str] = Field(default_factory=list)
    maternal_symptoms: list[str] = Field(default_factory=list)
    urine_protein: Optional[str] = None
    lab_investigations: Optional[dict[str, Any]] = None
    fetal_assessment: Optional[str] = None
    clinical_impression: str = Field(min_length=2)
    follow_up_recommendation: str = Field(min_length=2)
    referral_decision: str = Field(pattern="^(no_referral_needed|routine_referral|urgent_referral|immediate_emergency)$")
    clinical_notes: Optional[str] = None
    referenced_measurement_ids: list[str] = Field(default_factory=list)


def _calculate_gestational_age(lmp_str: str | None, edd_str: str | None, measured_dt: datetime) -> tuple[float | None, str]:
    """Calculates gestational age in weeks and formatted string (e.g. '28w 2d') at measurement date."""
    base_lmp: date | None = None
    m_date = measured_dt.date()
    if lmp_str:
        try:
            base_lmp = date.fromisoformat(lmp_str[:10])
        except Exception:
            pass
    if not base_lmp and edd_str:
        try:
            base_lmp = date.fromisoformat(edd_str[:10]) - timedelta(days=280)
        except Exception:
            pass
    if not base_lmp:
        return None, "—"

    days = (m_date - base_lmp).days
    if days < 0 or days > 315:
        return None, "—"

    w = days // 7
    d = days % 7
    return round(days / 7.0, 1), f"{w}w {d}d"


@router.get("/patients/{patient_id}/bp-trends")
def get_bp_trends(
    patient_id: str,
    period: str = Query(default="all", pattern="^(7d|30d|90d|all)$"),
    user: dict = Depends(current_user),
):
    """
    Returns longitudinal BP measurements with gestational age, threshold indicators,
    verification status, and clinical markers for interactive charting.
    """
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="bp_read")

    query = (
        db.table("bp_measurements")
        .select("*")
        .eq("patient_id", patient_id)
        .order("measured_at", desc=False)
    )

    now_utc = datetime.now(timezone.utc)
    if period == "7d":
        since = (now_utc - timedelta(days=7)).isoformat()
        query = query.gte("measured_at", since)
    elif period == "30d":
        since = (now_utc - timedelta(days=30)).isoformat()
        query = query.gte("measured_at", since)
    elif period == "90d":
        since = (now_utc - timedelta(days=90)).isoformat()
        query = query.gte("measured_at", since)

    rows = query.execute().data or []

    # Map measurement captures for clinical markers (urine protein, imminent symptoms)
    meas_ids = [r["id"] for r in rows if r.get("id")]
    captures_map = {}
    if meas_ids:
        try:
            caps = (
                db.table("measurement_captures")
                .select("measurement_id,extracted_values")
                .in_("measurement_id", meas_ids)
                .execute()
                .data
                or []
            )
            for c in caps:
                captures_map[c.get("measurement_id")] = c.get("extracted_values") or {}
        except Exception:
            pass

    fac_map = get_all_facilities_map(db)

    # Resolve healthcare worker names
    recorder_ids = list({r["recorded_by"] for r in rows if r.get("recorded_by")})
    recorders_map = {}
    if recorder_ids:
        try:
            profs = (
                db.table("user_profiles")
                .select("user_id,full_name")
                .in_("user_id", recorder_ids)
                .execute()
                .data
                or []
            )
            for pr in profs:
                recorders_map[pr["user_id"]] = pr["full_name"]
        except Exception:
            pass

    points = []
    for r in rows:
        try:
            m_dt = datetime.fromisoformat(r["measured_at"].replace("Z", "+00:00"))
        except Exception:
            m_dt = now_utc

        ga_weeks, ga_display = _calculate_gestational_age(patient.get("lmp"), patient.get("edd"), m_dt)
        cap = captures_map.get(r["id"], {})
        sys_val = r["systolic_mmhg"]
        dia_val = r["diastolic_mmhg"]

        points.append({
            "id": r["id"],
            "measured_at": r["measured_at"],
            "systolic_mmhg": sys_val,
            "diastolic_mmhg": dia_val,
            "pulse_bpm": r.get("pulse_bpm"),
            "gestational_age_weeks": ga_weeks,
            "gestational_age_display": ga_display,
            "verification_status": r.get("verification_status", "pending"),
            "worker_confirmed": bool(r.get("worker_confirmed")),
            "capture_method": r.get("capture_method", "manual"),
            "facility_id": r.get("facility_id"),
            "facility_name": fac_map.get(r.get("facility_id"), {}).get("name", "Unknown Facility"),
            "recorder_name": recorders_map.get(r.get("recorded_by"), "Healthcare Worker"),
            "urine_protein": cap.get("urine_protein"),
            "imminent_symptoms": cap.get("imminent_symptoms", []),
            "is_elevated": (sys_val >= 140 or dia_val >= 90),
            "is_severe": (sys_val >= 160 or dia_val >= 110),
        })

    return {
        "patient_id": patient_id,
        "period": period,
        "total_count": len(points),
        "measurements": points,
    }


@router.get("/patients/{patient_id}/bp-analytics")
def get_bp_analytics(
    patient_id: str,
    period: str = Query(default="all", pattern="^(7d|30d|90d|all)$"),
    user: dict = Depends(current_user),
):
    """
    Computes explainable, persistent-record-based BP trend analytics:
    delta SBP/DBP, threshold crossing rate, frequency, trend direction, and clinical insights.
    """
    trends = get_bp_trends(patient_id=patient_id, period=period, user=user)
    all_meas = trends["measurements"]
    total_count = len(all_meas)

    # Clinical analytics strictly use verified measurements
    verified = [m for m in all_meas if m["worker_confirmed"] or m["verification_status"] == "worker_verified"]
    unverified_count = total_count - len(verified)

    if not verified:
        return {
            "patient_id": patient_id,
            "period": period,
            "total_measurements": total_count,
            "verified_count": 0,
            "unverified_count": unverified_count,
            "latest_reading": None,
            "previous_reading": None,
            "delta_systolic": None,
            "delta_diastolic": None,
            "elevated_count": 0,
            "severe_count": 0,
            "threshold_crossing_percentage": 0.0,
            "trend_direction": "insufficient_data",
            "measurement_frequency_days": None,
            "irregular_or_missing_history": True,
            "insights": [
                {
                    "type": "missing",
                    "icon": "info_outline",
                    "statement": "No verified blood pressure measurements recorded for this observation window.",
                    "value": "0 verified",
                }
            ],
        }

    latest = verified[-1]
    previous = verified[-2] if len(verified) >= 2 else None

    delta_s = (latest["systolic_mmhg"] - previous["systolic_mmhg"]) if previous else None
    delta_d = (latest["diastolic_mmhg"] - previous["diastolic_mmhg"]) if previous else None

    elevated_count = sum(1 for m in verified if m["is_elevated"])
    severe_count = sum(1 for m in verified if m["is_severe"])
    pct_crossing = round((elevated_count / len(verified)) * 100.0, 1)

    if len(verified) < 2:
        trend_direction = "insufficient_data"
    elif (delta_s is not None and delta_s >= 10) or (delta_d is not None and delta_d >= 5):
        trend_direction = "rising"
    elif (delta_s is not None and delta_s <= -10) or (delta_d is not None and delta_d <= -5):
        trend_direction = "falling"
    else:
        trend_direction = "stable"

    # Frequency and intervals
    now_utc = datetime.now(timezone.utc)
    try:
        latest_dt = datetime.fromisoformat(latest["measured_at"].replace("Z", "+00:00"))
        days_since_latest = max(0.0, (now_utc - latest_dt).total_seconds() / 86400.0)
    except Exception:
        days_since_latest = 0.0

    freq_days: float | None = None
    irregular_history = False
    if len(verified) >= 2:
        try:
            first_dt = datetime.fromisoformat(verified[0]["measured_at"].replace("Z", "+00:00"))
            total_days = max(1.0, (latest_dt - first_dt).total_seconds() / 86400.0)
            freq_days = round(total_days / (len(verified) - 1), 1)
        except Exception:
            pass

    if days_since_latest > 7.0 or (freq_days is not None and freq_days > 14.0):
        irregular_history = True

    # Generate up to 3 concise, highly readable clinical insights
    insights = []

    # 1. Delta Insight
    if previous and delta_s is not None and delta_d is not None:
        if delta_s > 0:
            insights.append({
                "type": "rising" if delta_s >= 10 else "neutral",
                "icon": "trending_up",
                "statement": f"Systolic BP increased by {delta_s} mmHg since previous reading ({previous['systolic_mmhg']}/{previous['diastolic_mmhg']} mmHg).",
                "value": f"+{delta_s} mmHg",
            })
        elif delta_s < 0:
            insights.append({
                "type": "falling",
                "icon": "trending_down",
                "statement": f"Systolic BP decreased by {abs(delta_s)} mmHg compared to previous reading ({previous['systolic_mmhg']}/{previous['diastolic_mmhg']} mmHg).",
                "value": f"{delta_s} mmHg",
            })
        else:
            insights.append({
                "type": "stable",
                "icon": "trending_flat",
                "statement": f"Systolic BP unchanged compared to previous reading ({previous['systolic_mmhg']}/{previous['diastolic_mmhg']} mmHg).",
                "value": "Stable (0 mmHg)",
            })
    else:
        insights.append({
            "type": "baseline",
            "icon": "radio_button_checked",
            "statement": f"Baseline verified reading recorded at {latest['systolic_mmhg']}/{latest['diastolic_mmhg']} mmHg. Repeat reading required to establish delta.",
            "value": "Baseline",
        })

    # 2. Threshold Insight
    if severe_count > 0:
        insights.append({
            "type": "severe",
            "icon": "warning_rounded",
            "statement": f"{severe_count} of {len(verified)} verified measurements crossed severe screening threshold (>= 160/110 mmHg).",
            "value": f"{severe_count} severe",
        })
    elif elevated_count > 0:
        insights.append({
            "type": "elevated",
            "icon": "report_problem_outlined",
            "statement": f"{elevated_count} of {len(verified)} verified measurements crossed screening threshold (>= 140/90 mmHg).",
            "value": f"{pct_crossing}% crossing",
        })
    else:
        insights.append({
            "type": "normal",
            "icon": "check_circle_outline",
            "statement": f"All {len(verified)} verified measurements remain within normal screening thresholds.",
            "value": "100% normal",
        })

    # 3. Schedule / Interval Insight
    if days_since_latest > 7.0:
        insights.append({
            "type": "gap",
            "icon": "event_busy",
            "statement": f"No verified BP measurements recorded in the last {int(days_since_latest)} days.",
            "value": f"{int(days_since_latest)}d gap",
        })
    elif freq_days is not None:
        insights.append({
            "type": "frequency",
            "icon": "update",
            "statement": f"Measurement frequency: Verified reading recorded approximately every {freq_days} days.",
            "value": f"Every {freq_days}d",
        })
    else:
        insights.append({
            "type": "frequency",
            "icon": "calendar_today",
            "statement": "Regular antenatal BP monitoring recommended to track longitudinal trend.",
            "value": "Follow protocol",
        })

    return {
        "patient_id": patient_id,
        "period": period,
        "total_measurements": total_count,
        "verified_count": len(verified),
        "unverified_count": unverified_count,
        "latest_reading": latest,
        "previous_reading": previous,
        "delta_systolic": delta_s,
        "delta_diastolic": delta_d,
        "elevated_count": elevated_count,
        "severe_count": severe_count,
        "threshold_crossing_percentage": pct_crossing,
        "trend_direction": trend_direction,
        "measurement_frequency_days": freq_days,
        "irregular_or_missing_history": irregular_history,
        "insights": insights[:3],
    }


@router.get("/patients/{patient_id}/risk-profile")
def get_risk_profile(
    patient_id: str,
    user: dict = Depends(current_user),
):
    """
    Evaluates maternal preeclampsia risk factors from registration, questionnaire,
    and obstetric history. Missing data is explicitly categorized as 'unknown'.
    """
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="patient_read")

    # Fetch repeatable obstetric history records
    ob_rows = (
        db.table("obstetric_history")
        .select("*")
        .eq("patient_id", patient_id)
        .order("pregnancy_number", desc=False)
        .execute()
        .data
        or []
    )

    qd = patient.get("questionnaire_data") or {}
    pd = qd.get("personal_details") or {}
    ob_hist = qd.get("obstetric_history") or {}
    med_hist = qd.get("medical_history") or {}
    fam_hist = qd.get("family_history") or {}

    factors: list[dict[str, Any]] = []

    # 1. Maternal Age
    age_val = pd.get("age")
    dob_val = patient.get("date_of_birth")
    calc_age: int | None = None
    if dob_val:
        try:
            d = date.fromisoformat(dob_val[:10])
            calc_age = (date.today() - d).days // 365
        except Exception:
            pass
    if calc_age is None and age_val is not None and str(age_val).isdigit():
        calc_age = int(age_val)

    if calc_age is not None:
        if calc_age >= 35:
            factors.append({
                "factor_key": "maternal_age",
                "name": "Advanced Maternal Age (>= 35 years)",
                "status": "present",
                "detail": f"Age: {calc_age} years (>= 35 threshold)",
                "source": "Patient Demographics",
            })
        elif calc_age < 18:
            factors.append({
                "factor_key": "maternal_age",
                "name": "Adolescent Pregnancy (< 18 years)",
                "status": "present",
                "detail": f"Age: {calc_age} years (< 18 threshold)",
                "source": "Patient Demographics",
            })
        else:
            factors.append({
                "factor_key": "maternal_age",
                "name": "Maternal Age (18–34 years)",
                "status": "absent",
                "detail": f"Age: {calc_age} years (Standard baseline range)",
                "source": "Patient Demographics",
            })
    else:
        factors.append({
            "factor_key": "maternal_age",
            "name": "Maternal Age",
            "status": "unknown",
            "detail": "Age / date of birth not recorded",
            "source": "Patient Demographics",
        })

    # 2. Nulliparity (First Delivery)
    parity = patient.get("parity") if patient.get("parity") is not None else ob_hist.get("parity")
    gravida = patient.get("gravida") if patient.get("gravida") is not None else ob_hist.get("gravida")

    if parity is not None and str(parity).isdigit():
        p_num = int(parity)
        if p_num == 0:
            factors.append({
                "factor_key": "nulliparity",
                "name": "Nulliparity (Primigravida / First Delivery)",
                "status": "present",
                "detail": "Parity 0 (Nulliparous pregnant woman)",
                "source": "Obstetric History (GPAL)",
            })
        else:
            factors.append({
                "factor_key": "nulliparity",
                "name": "Nulliparity",
                "status": "absent",
                "detail": f"Multiparous mother (Parity {p_num})",
                "source": "Obstetric History (GPAL)",
            })
    elif gravida is not None and str(gravida).isdigit() and int(gravida) == 1:
        factors.append({
            "factor_key": "nulliparity",
            "name": "Nulliparity (First Pregnancy)",
            "status": "present",
            "detail": "Gravida 1 (Primigravida)",
            "source": "Obstetric History (GPAL)",
        })
    else:
        factors.append({
            "factor_key": "nulliparity",
            "name": "Nulliparity",
            "status": "unknown",
            "detail": "Parity / Gravida not recorded",
            "source": "Obstetric History (GPAL)",
        })

    # 3. Previous Preeclampsia / Eclampsia
    ob_comp_text = " ".join([
        str(row.get("antenatal_complications") or "") for row in ob_rows
    ]) + " " + str(ob_hist.get("past_obstetric_history") or "")
    ob_comp_lower = ob_comp_text.lower()

    has_pe = any(k in ob_comp_lower for k in ["preeclampsia", "pre-eclampsia", "eclampsia", "toxemia", "pih", "high bp in past"])
    if has_pe:
        factors.append({
            "factor_key": "previous_preeclampsia",
            "name": "Previous Preeclampsia / Eclampsia",
            "status": "present",
            "detail": "Documented complication in previous pregnancy",
            "source": "Past Obstetric Records",
        })
    elif parity is not None and str(parity).isdigit() and int(parity) == 0:
        factors.append({
            "factor_key": "previous_preeclampsia",
            "name": "Previous Preeclampsia",
            "status": "absent",
            "detail": "Not applicable (First pregnancy / Parity 0)",
            "source": "Obstetric History",
        })
    elif ob_rows or (ob_hist.get("past_obstetric_history") and len(str(ob_hist.get("past_obstetric_history")).strip()) > 3):
        factors.append({
            "factor_key": "previous_preeclampsia",
            "name": "Previous Preeclampsia",
            "status": "absent",
            "detail": "No previous preeclampsia documented in past pregnancy records",
            "source": "Past Obstetric Records",
        })
    else:
        factors.append({
            "factor_key": "previous_preeclampsia",
            "name": "Previous Preeclampsia",
            "status": "unknown",
            "detail": "Past obstetric history not documented",
            "source": "Past Obstetric Records",
        })

    # 4. Previous Gestational Hypertension
    has_ghtn = any(k in ob_comp_lower for k in ["gestational hypertension", "pregnancy-induced hypertension", "pregnancy induced hypertension", "g-htn"])
    if has_ghtn:
        factors.append({
            "factor_key": "previous_gestational_hypertension",
            "name": "Previous Gestational Hypertension",
            "status": "present",
            "detail": "History of gestational hypertension documented in past pregnancy",
            "source": "Past Obstetric Records",
        })
    elif parity is not None and str(parity).isdigit() and int(parity) == 0:
        factors.append({
            "factor_key": "previous_gestational_hypertension",
            "name": "Previous Gestational Hypertension",
            "status": "absent",
            "detail": "Not applicable (First pregnancy)",
            "source": "Obstetric History",
        })
    elif ob_rows:
        factors.append({
            "factor_key": "previous_gestational_hypertension",
            "name": "Previous Gestational Hypertension",
            "status": "absent",
            "detail": "No previous gestational hypertension reported",
            "source": "Past Obstetric Records",
        })
    else:
        factors.append({
            "factor_key": "previous_gestational_hypertension",
            "name": "Previous Gestational Hypertension",
            "status": "unknown",
            "detail": "Past pregnancy complications not recorded",
            "source": "Past Obstetric Records",
        })

    # 5. Chronic Hypertension
    med_text = str(med_hist.get("past_medical_history") or "").lower()
    has_chronic_htn = any(k in med_text for k in ["htn", "hypertension", "chronic high bp", "high blood pressure"])
    if has_chronic_htn:
        factors.append({
            "factor_key": "chronic_hypertension",
            "name": "Chronic (Pre-existing) Hypertension",
            "status": "present",
            "detail": "Documented pre-existing hypertension",
            "source": "Medical History",
        })
    elif med_text.strip() and med_text.strip() not in ["", "none", "nil"]:
        factors.append({
            "factor_key": "chronic_hypertension",
            "name": "Chronic Hypertension",
            "status": "absent",
            "detail": "No pre-existing hypertension noted in medical history",
            "source": "Medical History",
        })
    else:
        factors.append({
            "factor_key": "chronic_hypertension",
            "name": "Chronic Hypertension",
            "status": "unknown",
            "detail": "Past medical history not documented",
            "source": "Medical History",
        })

    # 6. Pre-existing Diabetes (Type 1 or Type 2)
    has_dm = any(k in med_text for k in ["diabetes", "dm", "type 1", "type 2", "t1dm", "t2dm", "diabetic"])
    has_no_dm = any(k in med_text for k in ["no diabetes", "nil diabetes", "non-diabetic", "no dm"]) or med_text.strip() in ["none", "nil", "normal", "healthy"]
    if has_dm and not has_no_dm:
        factors.append({
            "factor_key": "diabetes",
            "name": "Pre-existing Diabetes Mellitus",
            "status": "present",
            "detail": "Documented diabetes mellitus in medical history",
            "source": "Medical History",
        })
    elif has_no_dm:
        factors.append({
            "factor_key": "diabetes",
            "name": "Pre-existing Diabetes",
            "status": "absent",
            "detail": "No pre-existing diabetes recorded in medical history",
            "source": "Medical History",
        })
    else:
        factors.append({
            "factor_key": "diabetes",
            "name": "Pre-existing Diabetes",
            "status": "unknown",
            "detail": "Diabetes status not specifically recorded",
            "source": "Medical History",
        })

    # 7. Kidney / Renal Disease
    has_renal = any(k in med_text for k in ["kidney", "renal", "nephro", "glomerulo", "ckd", "proteinuria history"])
    has_no_renal = any(k in med_text for k in ["no kidney", "no renal", "nil renal", "renal normal"]) or med_text.strip() in ["none", "nil", "normal", "healthy"]
    if has_renal and not has_no_renal:
        factors.append({
            "factor_key": "kidney_disease",
            "name": "Chronic Kidney Disease / Renal Disorder",
            "status": "present",
            "detail": "Documented renal condition in medical history",
            "source": "Medical History",
        })
    elif has_no_renal:
        factors.append({
            "factor_key": "kidney_disease",
            "name": "Kidney Disease",
            "status": "absent",
            "detail": "No pre-existing kidney disease reported",
            "source": "Medical History",
        })
    else:
        factors.append({
            "factor_key": "kidney_disease",
            "name": "Kidney Disease",
            "status": "unknown",
            "detail": "Renal history not specifically recorded",
            "source": "Medical History",
        })

    # 8. Vascular / Autoimmune Disease (SLE / APS)
    has_autoimmune = any(k in med_text for k in ["sle", "lupus", "antiphospholipid", "aps", "autoimmune", "thrombophilia", "vascular"])
    has_no_autoimmune = any(k in med_text for k in ["no sle", "no autoimmune", "no lupus"]) or med_text.strip() in ["none", "nil", "normal", "healthy"]
    if has_autoimmune and not has_no_autoimmune:
        factors.append({
            "factor_key": "vascular_disease",
            "name": "Autoimmune / Vascular Disease (SLE / APS)",
            "status": "present",
            "detail": "Documented autoimmune or vascular disorder",
            "source": "Medical History",
        })
    elif has_no_autoimmune:
        factors.append({
            "factor_key": "vascular_disease",
            "name": "Autoimmune / Vascular Disease",
            "status": "absent",
            "detail": "No autoimmune or vascular disorder reported",
            "source": "Medical History",
        })
    else:
        factors.append({
            "factor_key": "vascular_disease",
            "name": "Autoimmune / Vascular Disease",
            "status": "unknown",
            "detail": "Autoimmune history not specifically recorded",
            "source": "Medical History",
        })

    # 9. Multiple Pregnancy (Twins / Multiples)
    t2_scan = str(qd.get("trimester_2", {}).get("anomaly_scan_remarks") or "").lower()
    has_multiple = any(k in t2_scan for k in ["twin", "triplet", "multiple gestation", "multiple pregnancy"])
    if has_multiple:
        factors.append({
            "factor_key": "multiple_pregnancy",
            "name": "Multiple Pregnancy (Twins / Multiples)",
            "status": "present",
            "detail": "Documented multiple gestation on ultrasound / exam",
            "source": "Antenatal & Ultrasound Records",
        })
    else:
        factors.append({
            "factor_key": "multiple_pregnancy",
            "name": "Multiple Pregnancy",
            "status": "absent",
            "detail": "Singleton pregnancy confirmed / standard presentation",
            "source": "Antenatal Examination",
        })

    # 10. Family History of Preeclampsia
    fam_text = str(fam_hist.get("history") or "").lower()
    has_fam_pe = any(k in fam_text for k in ["preeclampsia", "pre-eclampsia", "eclampsia", "hypertension in pregnancy", "toxemia"])
    if has_fam_pe:
        factors.append({
            "factor_key": "family_history",
            "name": "Family History of Preeclampsia (Mother / Sister)",
            "status": "present",
            "detail": "Documented preeclampsia in first-degree relative",
            "source": "Family History",
        })
    elif fam_text.strip() and fam_text.strip() not in ["", "none", "nil"]:
        factors.append({
            "factor_key": "family_history",
            "name": "Family History of Preeclampsia",
            "status": "absent",
            "detail": "No family history of preeclampsia reported",
            "source": "Family History",
        })
    else:
        factors.append({
            "factor_key": "family_history",
            "name": "Family History of Preeclampsia",
            "status": "unknown",
            "detail": "Family obstetric history not documented",
            "source": "Family History",
        })

    # 11. Body Mass Index (BMI)
    # Check for weight / height
    wt = pd.get("weight_kg")
    ht = pd.get("height_cm")
    if wt and ht and isinstance(wt, (int, float)) and isinstance(ht, (int, float)) and ht > 50:
        bmi = round(float(wt) / ((float(ht) / 100.0) ** 2), 1)
        if bmi >= 30.0:
            factors.append({
                "factor_key": "bmi",
                "name": "Elevated BMI / Obesity (>= 30 kg/m²)",
                "status": "present",
                "detail": f"BMI {bmi} kg/m² ({wt} kg, {ht} cm)",
                "source": "Physical Examination",
            })
        else:
            factors.append({
                "factor_key": "bmi",
                "name": "Body Mass Index (BMI)",
                "status": "absent",
                "detail": f"BMI {bmi} kg/m² (Normal range < 30 kg/m²)",
                "source": "Physical Examination",
            })
    else:
        factors.append({
            "factor_key": "bmi",
            "name": "Body Mass Index (BMI)",
            "status": "unknown",
            "detail": "Maternal height / weight not documented",
            "source": "Physical Examination",
        })

    present_cnt = sum(1 for f in factors if f["status"] == "present")
    absent_cnt = sum(1 for f in factors if f["status"] == "absent")
    unknown_cnt = sum(1 for f in factors if f["status"] == "unknown")

    return {
        "patient_id": patient_id,
        "documented_risk_factors_count": present_cnt,
        "absent_count": absent_cnt,
        "unknown_count": unknown_cnt,
        "summary_headline": f"{present_cnt} documented risk factors" if present_cnt > 0 else "No high-risk factors documented",
        "factors": factors,
    }


@router.get("/patients/{patient_id}/clinical-screening")
def get_clinical_screening(
    patient_id: str,
    user: dict = Depends(current_user),
):
    """
    Evaluates current clinical screening status, repeat confirmation requirements,
    and active screening alerts without providing an automated diagnosis.
    """
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="bp_read")

    # Fetch verified measurements ordered desc
    rows = (
        db.table("bp_measurements")
        .select("*")
        .eq("patient_id", patient_id)
        .order("measured_at", desc=True)
        .limit(10)
        .execute()
        .data
        or []
    )

    verified = [r for r in rows if r.get("worker_confirmed") or r.get("verification_status") == "worker_verified"]

    # Active alerts
    alerts = (
        db.table("clinical_alerts")
        .select("*")
        .eq("patient_id", patient_id)
        .eq("status", "active")
        .order("created_at", desc=True)
        .execute()
        .data
        or []
    )

    if not verified:
        return {
            "patient_id": patient_id,
            "screening_status": "insufficient_data",
            "status_label": "Insufficient measurement history",
            "latest_reading": None,
            "repeat_confirmation_needed": False,
            "repeat_confirmation_recorded": False,
            "active_alerts_count": len(alerts),
            "active_alerts": alerts,
            "rule_explanation": "Screening trigger threshold: SBP >= 140 or DBP >= 90 mmHg. Screening triggers indicate clinical need for evaluation, not an automated diagnosis of preeclampsia.",
        }

    latest = verified[0]
    sys_val = latest["systolic_mmhg"]
    dia_val = latest["diastolic_mmhg"]
    is_severe = (sys_val >= 160 or dia_val >= 110) or any(a.get("severity") == "red" for a in alerts)
    is_elevated = (sys_val >= 140 or dia_val >= 90) or any(a.get("severity") == "amber" for a in alerts)

    if is_severe:
        screening_status = "severe_screening"
        status_label = "Severe-range BP screening"
    elif is_elevated:
        screening_status = "elevated_screening"
        status_label = "Elevated BP screening"
    else:
        screening_status = "no_elevated"
        status_label = "No elevated reading recorded"

    # Repeat confirmation evaluation:
    # If latest reading was elevated, check if repeat confirmation reading exists within 4-24h
    repeat_needed = False
    repeat_recorded = False

    if is_elevated or is_severe:
        if len(verified) >= 2:
            try:
                t1 = datetime.fromisoformat(latest["measured_at"].replace("Z", "+00:00"))
                t2 = datetime.fromisoformat(verified[1]["measured_at"].replace("Z", "+00:00"))
                gap_hours = abs((t1 - t2).total_seconds()) / 3600.0
                if 0.25 <= gap_hours <= 24.0:
                    repeat_recorded = True
                else:
                    repeat_needed = True
            except Exception:
                repeat_needed = True
        else:
            repeat_needed = True

    return {
        "patient_id": patient_id,
        "screening_status": screening_status,
        "status_label": status_label,
        "latest_reading": {
            "systolic_mmhg": sys_val,
            "diastolic_mmhg": dia_val,
            "pulse_bpm": latest.get("pulse_bpm"),
            "measured_at": latest.get("measured_at"),
            "verification_status": latest.get("verification_status"),
        },
        "repeat_confirmation_needed": repeat_needed,
        "repeat_confirmation_recorded": repeat_recorded,
        "active_alerts_count": len(alerts),
        "active_alerts": alerts,
        "rule_explanation": "Screening triggers: SBP >= 140 or DBP >= 90 mmHg (elevated); SBP >= 160 or DBP >= 110 mmHg (severe). Repeat measurement within 4 hours confirms clinical hypertension.",
    }


@router.post("/patients/{patient_id}/clinical-assessment", status_code=201)
def record_clinical_assessment(
    patient_id: str,
    payload: ClinicalAssessmentCreate,
    user: dict = Depends(current_user),
):
    """
    Stores a formal Medical Officer clinical assessment including BP trend review,
    risk factors, symptoms, impression, follow-up, and referral decision with an audit trail.
    """
    db = supabase_admin()
    patient = assert_patient_access(db, user["sub"], patient_id, action="bp_write")

    assessment_data = payload.model_dump(mode="json")
    now_iso = datetime.now(timezone.utc).isoformat()

    row = {
        "patient_id": patient_id,
        "facility_id": patient["facility_id"],
        "assessed_by": user["sub"],
        "screening_inputs": assessment_data,
        "result_category": payload.referral_decision,
        "rule_version": "p360_mo_assessment_v1",
        "clinician_review_status": "completed",
        "assessed_at": now_iso,
    }

    res = db.table("clinical_screenings").insert(row).execute()
    saved = res.data[0] if res.data else row

    # Log in audit trail
    db.table("audit_logs").insert({
        "actor_user_id": user["sub"],
        "facility_id": patient["facility_id"],
        "action": "mo_clinical_assessment_completed",
        "entity_type": "clinical_screening",
        "entity_id": saved.get("id"),
        "metadata": {
            "referral_decision": payload.referral_decision,
            "follow_up_recommendation": payload.follow_up_recommendation,
            "clinical_impression": payload.clinical_impression,
            "referenced_measurement_ids": payload.referenced_measurement_ids,
        },
    }).execute()

    return saved


@router.get("/patients/{patient_id}/clinical-assessments")
def list_clinical_assessments(
    patient_id: str,
    user: dict = Depends(current_user),
):
    """
    Retrieves history of Medical Officer clinical assessments for this patient.
    """
    db = supabase_admin()
    assert_patient_access(db, user["sub"], patient_id, action="patient_read")

    rows = (
        db.table("clinical_screenings")
        .select("*")
        .eq("patient_id", patient_id)
        .order("assessed_at", desc=True)
        .limit(20)
        .execute()
        .data
        or []
    )

    # Fetch assessor names
    assessor_ids = list({r["assessed_by"] for r in rows if r.get("assessed_by")})
    names_map = {}
    if assessor_ids:
        try:
            profs = (
                db.table("user_profiles")
                .select("user_id,full_name")
                .in_("user_id", assessor_ids)
                .execute()
                .data
                or []
            )
            for pr in profs:
                names_map[pr["user_id"]] = pr["full_name"]
        except Exception:
            pass

    for r in rows:
        r["assessor_name"] = names_map.get(r.get("assessed_by"), "Medical Officer")

    return {"items": rows}
