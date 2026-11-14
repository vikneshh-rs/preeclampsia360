from fastapi import FastAPI, Depends, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .security import current_user
from .schemas import PatientCreate, BPMeasurementCreate
from .repository import supabase_admin
from .auth import router as auth_router
from .workflows import router as workflows_router
from .sync import router as sync_router
from .ocr import router as ocr_router

app = FastAPI(title=settings.app_name, version="0.1.0", description="Maternal monitoring and referral coordination API")
app.add_middleware(CORSMiddleware, allow_origins=settings.allowed_origins, allow_credentials=True, allow_methods=["GET", "POST", "PATCH", "DELETE"], allow_headers=["Authorization", "Content-Type"])
app.include_router(auth_router)
app.include_router(workflows_router)
app.include_router(sync_router)
app.include_router(ocr_router)

@app.get("/health")
def health():
    return {"status": "ok", "service": "preeclampsia360-api", "environment": settings.app_env}

@app.get("/api/v1/me")
def me(user: dict = Depends(current_user)):
    return {"id": user["sub"], "email": user.get("email"), "role": user.get("user_metadata", {}).get("role")}

@app.get("/api/v1/facilities/my-scope")
def facility_scope(user: dict = Depends(current_user)):
    db = supabase_admin()
    result = db.table("user_facility_assignments").select("facility_id,role,facilities(id,name,facility_type,parent_facility_id)").eq("user_id", user["sub"]).eq("is_active", True).execute()
    if not result.data:
        raise HTTPException(status_code=403, detail="No active facility assignment")
    return {"assignments": result.data}

@app.post("/api/v1/patients", status_code=201)
def create_patient(payload: PatientCreate, user: dict = Depends(current_user)):
    db = supabase_admin()
    assignment = db.table("user_facility_assignments").select("facility_id").eq("user_id", user["sub"]).eq("is_active", True).limit(1).execute()
    if not assignment.data:
        raise HTTPException(status_code=403, detail="No active facility assignment")
    facility_id = assignment.data[0]["facility_id"]
    data = payload.model_dump(mode="json")
    questionnaire = data.pop("questionnaire")
    row = {**data, "facility_id": facility_id, "created_by": user["sub"], "questionnaire_data": questionnaire}
    result = db.table("patients").insert(row).execute()
    if not result.data:
        raise HTTPException(status_code=400, detail="Patient could not be created")
    return result.data[0]

@app.get("/api/v1/patients")
def list_patients(q: str | None = Query(default=None, max_length=100), limit: int = Query(default=30, ge=1, le=100), user: dict = Depends(current_user)):
    db = supabase_admin()
    assignment = db.table("user_facility_assignments").select("facility_id").eq("user_id", user["sub"]).eq("is_active", True).limit(1).execute()
    if not assignment.data:
        raise HTTPException(status_code=403, detail="No active facility assignment")
    query = db.table("patients").select("id,patient_code,full_name,date_of_birth,phone,created_at").eq("facility_id", assignment.data[0]["facility_id"]).order("created_at", desc=True).limit(limit)
    if q:
        query = query.ilike("full_name", f"%{q}%")
    return {"items": query.execute().data or []}

@app.get("/api/v1/patients/{patient_id}")
def get_patient(patient_id: str, user: dict = Depends(current_user)):
    db = supabase_admin()
    result = db.table("patients").select("*").eq("id", patient_id).maybe_single().execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Patient not found")
    # TODO: replace direct facility check with hierarchy-aware policy service before enabling CHC/THC access.
    assignment = db.table("user_facility_assignments").select("facility_id").eq("user_id", user["sub"]).eq("is_active", True).execute()
    allowed = {x["facility_id"] for x in (assignment.data or [])}
    if result.data["facility_id"] not in allowed:
        raise HTTPException(status_code=403, detail="Patient is outside your assigned facility scope")
    return result.data

@app.post("/api/v1/bp/measurements", status_code=201)
def create_bp_measurement(payload: BPMeasurementCreate, user: dict = Depends(current_user)):
    if not payload.worker_confirmed:
        raise HTTPException(status_code=422, detail="Worker must verify the displayed reading before saving")
    if payload.systolic_mmhg <= payload.diastolic_mmhg:
        raise HTTPException(status_code=422, detail="Systolic value must exceed diastolic value")
    db = supabase_admin()
    patient = db.table("patients").select("id,facility_id").eq("id", payload.patient_id).maybe_single().execute()
    if not patient.data:
        raise HTTPException(status_code=404, detail="Patient not found")
    assignments = db.table("user_facility_assignments").select("facility_id").eq("user_id", user["sub"]).eq("is_active", True).execute()
    if patient.data["facility_id"] not in {x["facility_id"] for x in (assignments.data or [])}:
        raise HTTPException(status_code=403, detail="Patient is outside your assigned facility scope")
    row = {**payload.model_dump(mode="json"), "facility_id": patient.data["facility_id"], "recorded_by": user["sub"], "verification_status": "worker_verified"}
    result = db.table("bp_measurements").insert(row).execute()
    if not result.data:
        raise HTTPException(status_code=400, detail="Measurement could not be saved")
    return result.data[0]
