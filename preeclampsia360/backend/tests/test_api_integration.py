import unittest
from unittest.mock import MagicMock, patch
import uuid
import jwt
from datetime import datetime, timezone, timedelta
from fastapi.testclient import TestClient

from app.main import app
from app.config import settings

# Test tokens
TEST_SECRET = "test_jwt_secret_32_bytes_minimum_length_for_hs256!"
settings.supabase_jwt_secret = TEST_SECRET

def generate_test_jwt(sub: str, email: str = "worker@test.invalid") -> str:
    payload = {
        "sub": sub,
        "email": email,
        "aud": "authenticated",
        "iss": f"{settings.supabase_url}/auth/v1",
        "exp": datetime.now(timezone.utc) + timedelta(hours=2),
    }
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")

class MockResult:
    def __init__(self, data=None):
        self.data = data

class MockQueryBuilder:
    def __init__(self, table):
        self.table = table
        self._filtered = list(table.items)
        self.is_single = False
        self._update_payload = None
        self._is_delete = False
        self._last_result = None

    def select(self, *args, **kwargs):
        return self

    def eq(self, field, value):
        if self._is_delete:
            self.table.items = [item for item in self.table.items if str(item.get(field, "")) != str(value)]
            self._last_result = []
            return self
        if self._update_payload is not None:
            updated = []
            for item in self.table.items:
                if str(item.get(field, "")) == str(value):
                    item.update(self._update_payload)
                    updated.append(item)
            self._last_result = updated
            return self
        self._filtered = [x for x in self._filtered if str(x.get(field, "")) == str(value)]
        return self

    def in_(self, field, values):
        val_strs = {str(v) for v in values}
        self._filtered = [x for x in self._filtered if str(x.get(field, "")) in val_strs]
        return self

    def maybe_single(self):
        self.is_single = True
        return self

    def order(self, *args, **kwargs):
        return self

    def limit(self, *args, **kwargs):
        return self

    def delete(self):
        self._is_delete = True
        return self

    def insert(self, payload):
        if isinstance(payload, list):
            res = []
            for item in payload:
                d = dict(item)
                d.setdefault("id", str(uuid.uuid4()))
                self.table.items.append(d)
                self.table.inserted.append(d)
                res.append(d)
            self._last_result = res
        else:
            d = dict(payload)
            d.setdefault("id", str(uuid.uuid4()))
            self.table.items.append(d)
            self.table.inserted.append(d)
            self._last_result = [d]
        return self

    def update(self, payload):
        self._update_payload = dict(payload)
        return self

    def execute(self):
        if self._last_result is not None:
            if self.is_single:
                return MockResult(self._last_result[0] if self._last_result else None)
            return MockResult(self._last_result)
        if self.is_single:
            return MockResult(self._filtered[0] if self._filtered else None)
        return MockResult(self._filtered)

class MockTable:
    def __init__(self, name, items=None):
        self.name = name
        self.items = [dict(x) for x in (items or [])]
        self.inserted = []

    def new_query(self):
        return MockQueryBuilder(self)

class MockDatabase:
    def __init__(self, seed=None):
        self.tables = {}
        if seed:
            for name, items in seed.items():
                self.tables[name] = MockTable(name, items)

    def table(self, name):
        if name not in self.tables:
            self.tables[name] = MockTable(name)
        return self.tables[name].new_query()

class TestPreeclampsia360BackendIntegration(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.sys_admin_id = str(uuid.uuid4())
        self.thc_mo_id = str(uuid.uuid4())
        self.chc_mo_id = str(uuid.uuid4())
        self.phc_anm_id = str(uuid.uuid4())
        self.other_phc_anm_id = str(uuid.uuid4())
        self.hospital_staff_id = str(uuid.uuid4())

        self.thc_id = str(uuid.uuid4())
        self.chc_id = str(uuid.uuid4())
        self.phc_a_id = str(uuid.uuid4())
        self.phc_b_id = str(uuid.uuid4())
        self.hospital_id = str(uuid.uuid4())

        self.facilities = [
            {"id": self.thc_id, "name": "District THC", "facility_type": "THC", "parent_facility_id": None, "is_active": True},
            {"id": self.chc_id, "name": "Taluk CHC", "facility_type": "CHC", "parent_facility_id": self.thc_id, "is_active": True},
            {"id": self.phc_a_id, "name": "Primary PHC A", "facility_type": "PHC", "parent_facility_id": self.chc_id, "is_active": True},
            {"id": self.phc_b_id, "name": "Primary PHC B", "facility_type": "PHC", "parent_facility_id": self.chc_id, "is_active": True},
            {"id": self.hospital_id, "name": "District Hospital", "facility_type": "HOSPITAL", "parent_facility_id": self.thc_id, "is_active": True},
        ]

    def test_health_endpoint(self):
        res = self.client.get("/health")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

    @patch("app.auth.supabase_admin")
    @patch("app.auth._client")
    def test_login_success(self, mock_client, mock_db_getter):
        user_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "user_profiles": [{
                "user_id": user_id,
                "login_id": "PY-PHC-ANM-01",
                "full_name": "Sister Mary",
                "is_active": True,
                "account_status": "active",
                "must_change_pin": False,
                "internal_auth_email": f"{user_id}@test.invalid",
            }],
            "user_facility_assignments": [{
                "user_id": user_id,
                "facility_id": self.phc_a_id,
                "role": "ANM",
                "is_active": True,
                "facilities": {"name": "PHC A"},
            }],
        })
        mock_db_getter.return_value = mock_db

        auth_session = MagicMock()
        auth_session.session.access_token = "mock_access_token"
        auth_session.session.refresh_token = "mock_refresh_token"
        auth_session.session.expires_in = 3600
        mock_client.return_value.auth.sign_in_with_password.return_value = auth_session

        res = self.client.post("/api/v1/auth/login", json={"login_id": "PY-PHC-ANM-01", "pin": "123456"})
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["access_token"], "mock_access_token")
        self.assertEqual(data["user"]["login_id"], "PY-PHC-ANM-01")

    @patch("app.auth.supabase_admin")
    def test_login_invalid_pin_failure(self, mock_db_getter):
        mock_db = MockDatabase({"user_profiles": []})
        mock_db_getter.return_value = mock_db

        res = self.client.post("/api/v1/auth/login", json={"login_id": "PY-PHC-ANM-01", "pin": "999999"})
        self.assertEqual(res.status_code, 401)
        self.assertIn("Invalid ID or PIN", res.json()["detail"])

    @patch("app.auth.supabase_admin")
    @patch("app.auth._client")
    def test_account_provisioning_and_audit_action(self, mock_client, mock_db_getter):
        token = generate_test_jwt(self.sys_admin_id)
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "user_facility_assignments": [{
                "user_id": self.sys_admin_id,
                "facility_id": self.thc_id,
                "role": "SYSTEM_ADMIN",
                "is_active": True,
            }],
            "user_profiles": [],
        })
        mock_db_getter.return_value = mock_db

        # Auth create
        new_auth_user = MagicMock()
        new_auth_user.id = str(uuid.uuid4())
        mock_client.return_value.auth.admin.create_user.return_value.user = new_auth_user

        payload = {
            "login_id": "PY-PHC-ANM-NEW",
            "full_name": "Priya Sharma",
            "facility_id": self.phc_a_id,
            "role": "ANM",
            "pin": "234567",
        }

        res = self.client.post(
            "/api/v1/auth/provision",
            json=payload,
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res.status_code, 201)
        self.assertEqual(res.json()["login_id"], "PY-PHC-ANM-NEW")

        # Verify audit call was made with corrected action 'created'
        audit_table = mock_db.tables.get("account_provisioning_audit")
        self.assertIsNotNone(audit_table)
        created_audits = [item for item in audit_table.inserted if item.get("action") == "created"]
        self.assertTrue(len(created_audits) > 0, "Expected audit insert with action='created'")
        self.assertEqual(created_audits[0]["action"], "created")

    @patch("app.main.supabase_admin")
    def test_facility_hierarchy_patient_access(self, mock_db_getter):
        patient_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "patient_code": "PE360-TEST01",
                "full_name": "Geeta Devi",
                "facility_id": self.phc_a_id,
            }],
            "user_facility_assignments": [{
                "user_id": self.chc_mo_id,
                "facility_id": self.chc_id,
                "role": "CHC_MO",
                "is_active": True,
            }],
        })
        mock_db_getter.return_value = mock_db

        # CHC MO should access PHC A patient via hierarchy (CHC is parent of PHC A)
        chc_token = generate_test_jwt(self.chc_mo_id)
        res = self.client.get(
            f"/api/v1/patients/{patient_id}",
            headers={"Authorization": f"Bearer {chc_token}"},
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["full_name"], "Geeta Devi")

    @patch("app.main.supabase_admin")
    def test_cross_facility_access_denied(self, mock_db_getter):
        patient_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "patient_code": "PE360-TEST02",
                "full_name": "Meena Kumari",
                "facility_id": self.phc_b_id,
            }],
            "user_facility_assignments": [{
                "user_id": self.phc_anm_id,
                "facility_id": self.phc_a_id,
                "role": "ANM",
                "is_active": True,
            }],
        })
        mock_db_getter.return_value = mock_db

        # Worker is ANM at PHC A (sibling of PHC B, not ancestor) -> Should be denied 403
        phc_a_token = generate_test_jwt(self.phc_anm_id)
        res = self.client.get(
            f"/api/v1/patients/{patient_id}",
            headers={"Authorization": f"Bearer {phc_a_token}"},
        )
        self.assertEqual(res.status_code, 403)
        self.assertIn("outside your assigned facility hierarchy", res.json()["detail"])

    @patch("app.workflows.supabase_admin")
    def test_referral_creation_and_state_transitions(self, mock_db_getter):
        patient_id = str(uuid.uuid4())
        referral_id = str(uuid.uuid4())

        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "facility_id": self.phc_a_id,
                "full_name": "Lakshmi Bai",
            }],
            "user_facility_assignments": [
                {
                    "user_id": self.phc_anm_id,
                    "facility_id": self.phc_a_id,
                    "role": "ANM",
                    "is_active": True,
                },
                {
                    "user_id": self.hospital_staff_id,
                    "facility_id": self.hospital_id,
                    "role": "RECEIVING_STAFF",
                    "is_active": True,
                },
            ],
            "referrals": [],
            "referral_events": [],
        })
        mock_db_getter.return_value = mock_db

        # 1. Create referral with valid receiving_facility_id
        anm_token = generate_test_jwt(self.phc_anm_id)
        ref_payload = {
            "patient_id": patient_id,
            "receiving_facility_id": self.hospital_id,
            "reason": "Severe preeclampsia, BP 165/110",
            "clinical_summary": {"systolic": 165, "diastolic": 110},
        }

        res = self.client.post(
            "/api/v1/referrals",
            json=ref_payload,
            headers={"Authorization": f"Bearer {anm_token}"},
        )
        self.assertEqual(res.status_code, 201)
        created_ref = res.json()
        self.assertEqual(created_ref["status"], "generated")
        ref_id = created_ref["id"]

        # 2. Origin facility clinician transitions from 'generated' to 'sent'
        res_sent = self.client.post(
            f"/api/v1/referrals/{ref_id}/transition",
            json={"status": "sent", "note": "Ambulance dispatched"},
            headers={"Authorization": f"Bearer {anm_token}"},
        )
        self.assertEqual(res_sent.status_code, 200)
        self.assertEqual(res_sent.json()["status"], "sent")

        # 3. Receiving facility acknowledges
        hospital_token = generate_test_jwt(self.hospital_staff_id)
        res_ack = self.client.post(
            f"/api/v1/referrals/{ref_id}/transition",
            json={"status": "acknowledged", "note": "Bed reserved in emergency obstetrics"},
            headers={"Authorization": f"Bearer {hospital_token}"},
        )
        self.assertEqual(res_ack.status_code, 200)
        self.assertEqual(res_ack.json()["status"], "acknowledged")

        # 4. Invalid referral transition: from 'acknowledged' directly to 'completed' (must go departed -> arrived -> assessed -> completed)
        res_invalid = self.client.post(
            f"/api/v1/referrals/{ref_id}/transition",
            json={"status": "completed", "note": "Illegal status jump"},
            headers={"Authorization": f"Bearer {hospital_token}"},
        )
        self.assertEqual(res_invalid.status_code, 409)
        self.assertIn("Invalid referral transition", res_invalid.json()["detail"])

    @patch("app.main.supabase_admin")
    def test_patient_update_profile(self, mock_db_getter):
        patient_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "patient_code": "PE360-P1",
                "full_name": "Radha Rani",
                "phone": "9876543210",
                "facility_id": self.phc_a_id,
                "blood_group": "B+",
            }],
            "user_facility_assignments": [{
                "user_id": self.phc_anm_id,
                "facility_id": self.phc_a_id,
                "role": "ANM",
                "is_active": True,
            }],
            "audit_logs": [],
        })
        mock_db_getter.return_value = mock_db

        token = generate_test_jwt(self.phc_anm_id)
        update_payload = {
            "phone": "9988776655",
            "blood_group": "O+",
            "gravida": 2,
            "parity": 1,
        }
        res = self.client.put(
            f"/api/v1/patients/{patient_id}",
            json=update_payload,
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["phone"], "9988776655")
        self.assertEqual(res.json()["blood_group"], "O+")

    @patch("app.main.supabase_admin")
    def test_patient_obstetric_history_repeatable(self, mock_db_getter):
        patient_id = str(uuid.uuid4())
        history_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "patient_code": "PE360-P2",
                "full_name": "Sunita Verma",
                "facility_id": self.phc_a_id,
            }],
            "user_facility_assignments": [{
                "user_id": self.phc_anm_id,
                "facility_id": self.phc_a_id,
                "role": "ANM",
                "is_active": True,
            }],
            "obstetric_history": [],
            "audit_logs": [],
        })
        mock_db_getter.return_value = mock_db

        token = generate_test_jwt(self.phc_anm_id)

        # 1. Add obstetric history record for Pregnancy #1
        ob_payload = {
            "pregnancy_number": 1,
            "conception_type": "spontaneous",
            "antenatal_complications": "Preeclampsia at 34 weeks, delivered via LSCS",
            "delivery_details": {"outcome": "LSCS", "year": "2024"},
            "baby_details": {"birth_weight_kg": 2.4, "gender": "Female"},
        }
        res = self.client.post(
            f"/api/v1/patients/{patient_id}/obstetric-history",
            json=ob_payload,
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res.status_code, 201)
        created_id = res.json()["id"]

        # 2. Retrieve obstetric history list
        res_list = self.client.get(
            f"/api/v1/patients/{patient_id}/obstetric-history",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res_list.status_code, 200)
        self.assertEqual(len(res_list.json()["items"]), 1)
        self.assertEqual(res_list.json()["items"][0]["pregnancy_number"], 1)

    @patch("app.workflows.supabase_admin")
    @patch("app.main.supabase_admin")
    def test_patient_questionnaire_sections_and_draft(self, mock_main_db, mock_wf_db):
        patient_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "patient_code": "PE360-P3",
                "full_name": "Ananya Sen",
                "facility_id": self.phc_a_id,
                "questionnaire_data": {},
            }],
            "user_facility_assignments": [{
                "user_id": self.phc_anm_id,
                "facility_id": self.phc_a_id,
                "role": "ANM",
                "is_active": True,
            }],
            "questionnaire_revisions": [],
            "audit_logs": [],
        })
        mock_main_db.return_value = mock_db
        mock_wf_db.return_value = mock_db

        token = generate_test_jwt(self.phc_anm_id)

        # Save draft section
        res_draft = self.client.post(
            "/api/v1/questionnaires/sections",
            json={
                "patient_id": patient_id,
                "section_key": "Personal details",
                "answers": {"Patient name": "Ananya Sen", "Age": "26", "Blood group": "A+"},
                "completed": False,
            },
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res_draft.status_code, 201)

        # Retrieve full questionnaires endpoint
        res_q = self.client.get(
            f"/api/v1/patients/{patient_id}/questionnaires",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res_q.status_code, 200)
        self.assertIn("Personal details", res_q.json()["questionnaire_data"])

    @patch("app.main.supabase_admin")
    def test_bp_measurement_normal_and_elevated_alert(self, mock_db_getter):
        patient_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "patient_code": "PE360-P4",
                "full_name": "Meera Joshi",
                "facility_id": self.phc_a_id,
            }],
            "user_facility_assignments": [{
                "user_id": self.phc_anm_id,
                "facility_id": self.phc_a_id,
                "role": "ANM",
                "is_active": True,
            }],
            "bp_measurements": [],
            "clinical_alerts": [],
            "audit_logs": [],
        })
        mock_db_getter.return_value = mock_db

        token = generate_test_jwt(self.phc_anm_id)

        # 1. Normal BP (118/76) -> No alert triggered
        payload_normal = {
            "patient_id": patient_id,
            "systolic_mmhg": 118,
            "diastolic_mmhg": 76,
            "pulse_bpm": 72,
            "worker_confirmed": True,
            "measured_at": datetime.now(timezone.utc).isoformat(),
        }
        res_norm = self.client.post(
            "/api/v1/bp/measurements",
            json=payload_normal,
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res_norm.status_code, 201)
        self.assertFalse(res_norm.json()["alert_triggered"])
        self.assertIsNone(res_norm.json()["alert"])

        # 2. Elevated BP (148/96) -> SBP >= 140 / DBP >= 90 -> Triggers Amber Alert
        payload_elevated = {
            "patient_id": patient_id,
            "systolic_mmhg": 148,
            "diastolic_mmhg": 96,
            "pulse_bpm": 84,
            "worker_confirmed": True,
            "measured_at": datetime.now(timezone.utc).isoformat(),
        }
        res_elevated = self.client.post(
            "/api/v1/bp/measurements",
            json=payload_elevated,
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res_elevated.status_code, 201)
        self.assertTrue(res_elevated.json()["alert_triggered"])
        alert = res_elevated.json()["alert"]
        self.assertEqual(alert["severity"], "amber")
        self.assertEqual(alert["status"], "active")
        self.assertIn("148/96", alert["trigger_reason"])

        # 3. Severe BP (165/112) -> SBP >= 160 / DBP >= 110 -> Triggers Red Alert
        payload_severe = {
            "patient_id": patient_id,
            "systolic_mmhg": 165,
            "diastolic_mmhg": 112,
            "pulse_bpm": 92,
            "worker_confirmed": True,
            "measured_at": datetime.now(timezone.utc).isoformat(),
        }
        res_severe = self.client.post(
            "/api/v1/bp/measurements",
            json=payload_severe,
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(res_severe.status_code, 201)
        self.assertTrue(res_severe.json()["alert_triggered"])
        alert_red = res_severe.json()["alert"]
        self.assertEqual(alert_red["severity"], "red")

    @patch("app.main.supabase_admin")
    def test_alert_list_and_mo_review(self, mock_db_getter):
        alert_id = str(uuid.uuid4())
        patient_id = str(uuid.uuid4())
        mock_db = MockDatabase({
            "facilities": self.facilities,
            "patients": [{
                "id": patient_id,
                "patient_code": "PE360-ALERT-PAT",
                "full_name": "Lata Mangesh",
                "facility_id": self.phc_a_id,
            }],
            "user_facility_assignments": [{
                "user_id": self.chc_mo_id,
                "facility_id": self.chc_id,
                "role": "CHC_MO",
                "is_active": True,
            }],
            "clinical_alerts": [{
                "id": alert_id,
                "patient_id": patient_id,
                "facility_id": self.phc_a_id,
                "measurement_id": str(uuid.uuid4()),
                "worker_user_id": self.phc_anm_id,
                "alert_type": "ELEVATED_BP",
                "severity": "red",
                "trigger_reason": "Elevated blood pressure: 165/110 mmHg",
                "systolic_mmhg": 165,
                "diastolic_mmhg": 110,
                "status": "active",
                "created_at": datetime.now(timezone.utc).isoformat(),
            }],
            "referrals": [],
            "audit_logs": [],
        })
        mock_db_getter.return_value = mock_db

        mo_token = generate_test_jwt(self.chc_mo_id)

        # 1. MO lists active alerts within CHC hierarchy (includes child PHC A)
        res_list = self.client.get(
            "/api/v1/alerts?status=active",
            headers={"Authorization": f"Bearer {mo_token}"},
        )
        self.assertEqual(res_list.status_code, 200)
        items = res_list.json()["items"]
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["severity"], "red")
        self.assertEqual(items[0]["patient"]["full_name"], "Lata Mangesh")

        # 2. MO reviews alert and marks for referral
        res_review = self.client.post(
            f"/api/v1/alerts/{alert_id}/review",
            json={"status": "referred", "review_notes": "Urgent obstetric consult required for severe HTN"},
            headers={"Authorization": f"Bearer {mo_token}"},
        )
        self.assertEqual(res_review.status_code, 200)
        self.assertEqual(res_review.json()["status"], "referred")
        self.assertEqual(res_review.json()["review_notes"], "Urgent obstetric consult required for severe HTN")

        # 3. Check dashboard metrics endpoint
        res_metrics = self.client.get(
            "/api/v1/dashboard/metrics",
            headers={"Authorization": f"Bearer {mo_token}"},
        )
        self.assertEqual(res_metrics.status_code, 200)
        metrics = res_metrics.json()
        self.assertIn("registered_patients", metrics)
        self.assertIn("active_alerts", metrics)



if __name__ == "__main__":
    unittest.main()
