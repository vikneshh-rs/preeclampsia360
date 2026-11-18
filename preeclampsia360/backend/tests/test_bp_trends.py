import unittest
from datetime import datetime, timezone, timedelta
from app.trends import _calculate_gestational_age

class TestBPTrendCalculations(unittest.TestCase):
    def test_gestational_age_calculation_from_lmp(self):
        m_dt = datetime(2026, 11, 15, 10, 0, tzinfo=timezone.utc)
        lmp = "2026-05-01"
        weeks, display = _calculate_gestational_age(lmp, None, m_dt)
        self.assertIsNotNone(weeks)
        self.assertEqual(display, "28w 2d")
        self.assertAlmostEqual(weeks, 28.3, places=1)

    def test_gestational_age_calculation_from_edd(self):
        m_dt = datetime(2026, 11, 15, 10, 0, tzinfo=timezone.utc)
        edd = "2027-02-05"  # LMP ~ 2026-05-01
        weeks, display = _calculate_gestational_age(None, edd, m_dt)
        self.assertIsNotNone(weeks)
        self.assertTrue("w" in display)

    def test_gestational_age_missing_dates(self):
        m_dt = datetime(2026, 11, 15, 10, 0, tzinfo=timezone.utc)
        weeks, display = _calculate_gestational_age(None, None, m_dt)
        self.assertIsNone(weeks)
        self.assertEqual(display, "—")

    def test_risk_factors_nulliparity_and_age(self):
        from app.trends import get_risk_profile
        # Test evaluating risk factors
        from unittest.mock import MagicMock, patch
        mock_db = MagicMock()
        mock_db.table().select().eq().order().execute.return_value.data = []

        patient = {
            "id": "pat-1",
            "facility_id": "fac-1",
            "date_of_birth": "1988-01-01",  # 38 years old -> Advanced Maternal Age
            "parity": 0,  # Nulliparity
            "gravida": 1,
            "questionnaire_data": {
                "personal_details": {"age": 38},
                "medical_history": {"past_medical_history": "chronic HTN on labetalol"},
            }
        }

        with patch("app.trends.supabase_admin", return_value=mock_db), \
             patch("app.trends.assert_patient_access", return_value=patient):
            res = get_risk_profile("pat-1", user={"sub": "u-1"})
            factors = {f["factor_key"]: f for f in res["factors"]}
            
            # Maternal age should be present (Advanced)
            self.assertEqual(factors["maternal_age"]["status"], "present")
            # Nulliparity should be present
            self.assertEqual(factors["nulliparity"]["status"], "present")
            # Chronic HTN should be present
            self.assertEqual(factors["chronic_hypertension"]["status"], "present")
            # Unrecorded factors should be unknown, NOT absent
            self.assertEqual(factors["kidney_disease"]["status"], "unknown")
            self.assertEqual(factors["bmi"]["status"], "unknown")

    def test_screening_triggers_and_repeat_confirmation(self):
        from app.trends import get_clinical_screening
        from unittest.mock import MagicMock, patch

        mock_db = MagicMock()
        patient = {"id": "pat-2", "facility_id": "fac-1"}

        # 1. Normal reading
        mock_db.table().select().eq().order().limit().execute.return_value.data = [
            {"systolic_mmhg": 118, "diastolic_mmhg": 76, "measured_at": "2026-11-15T10:00:00Z", "verification_status": "worker_verified"}
        ]
        mock_db.table().select().eq().eq().order().execute.return_value.data = []

        with patch("app.trends.supabase_admin", return_value=mock_db), \
             patch("app.trends.assert_patient_access", return_value=patient):
            res = get_clinical_screening("pat-2", user={"sub": "u-1"})
            self.assertEqual(res["screening_status"], "no_elevated")
            self.assertFalse(res["repeat_confirmation_needed"])

        # 2. Severe reading requiring repeat confirmation
        mock_db.table().select().eq().order().limit().execute.return_value.data = [
            {"systolic_mmhg": 164, "diastolic_mmhg": 112, "measured_at": "2026-11-15T10:00:00Z", "verification_status": "worker_verified"}
        ]
        with patch("app.trends.supabase_admin", return_value=mock_db), \
             patch("app.trends.assert_patient_access", return_value=patient):
            res = get_clinical_screening("pat-2", user={"sub": "u-1"})
            self.assertEqual(res["screening_status"], "severe_screening")
            self.assertTrue(res["repeat_confirmation_needed"])
            self.assertFalse(res["repeat_confirmation_recorded"])

if __name__ == "__main__":
    unittest.main()
