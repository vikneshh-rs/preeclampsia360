from datetime import date, datetime
from enum import Enum
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional

class Sex(str, Enum):
    female = "female"

class PatientCreate(BaseModel):
    full_name: str = Field(min_length=2, max_length=160)
    date_of_birth: Optional[date] = None
    phone: Optional[str] = Field(default=None, max_length=30)
    address: Optional[str] = None
    blood_group: Optional[str] = None
    lmp: Optional[date] = None
    edd: Optional[date] = None
    gravida: Optional[int] = Field(default=None, ge=1, le=30)
    parity: Optional[int] = Field(default=None, ge=0, le=30)
    abortions: Optional[int] = Field(default=None, ge=0, le=30)
    living_children: Optional[int] = Field(default=None, ge=0, le=30)
    questionnaire: dict = Field(default_factory=dict)

class PatientOut(BaseModel):
    id: str
    full_name: str
    patient_code: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

class PatientUpdate(BaseModel):
    full_name: Optional[str] = Field(default=None, min_length=2, max_length=160)
    date_of_birth: Optional[date] = None
    phone: Optional[str] = Field(default=None, max_length=30)
    address: Optional[str] = None
    blood_group: Optional[str] = None
    lmp: Optional[date] = None
    edd: Optional[date] = None
    gravida: Optional[int] = Field(default=None, ge=1, le=30)
    parity: Optional[int] = Field(default=None, ge=0, le=30)
    abortions: Optional[int] = Field(default=None, ge=0, le=30)
    living_children: Optional[int] = Field(default=None, ge=0, le=30)
    questionnaire_data: Optional[dict] = None

class ObstetricHistoryCreate(BaseModel):
    pregnancy_number: int = Field(ge=1, le=30)
    conception_type: Optional[str] = "spontaneous"
    antenatal_complications: Optional[str] = None
    delivery_details: dict = Field(default_factory=dict)
    baby_details: dict = Field(default_factory=dict)
    abortion_details: dict = Field(default_factory=dict)
    supplements_taken: Optional[str] = None

class ObstetricHistoryOut(BaseModel):
    id: str
    patient_id: str
    pregnancy_number: int
    conception_type: Optional[str] = None
    antenatal_complications: Optional[str] = None
    delivery_details: dict = {}
    baby_details: dict = {}
    abortion_details: dict = {}
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

class BPMeasurementCreate(BaseModel):
    patient_id: str
    systolic_mmhg: int = Field(ge=40, le=300)
    diastolic_mmhg: int = Field(ge=20, le=200)
    pulse_bpm: Optional[int] = Field(default=None, ge=20, le=250)
    device_id: Optional[str] = None
    capture_method: str = "camera_ocr"
    ocr_confidence: Optional[float] = Field(default=None, ge=0, le=1)
    worker_confirmed: bool = False
    measured_at: datetime
    urine_protein: Optional[str] = None
    imminent_symptoms: list[str] = Field(default_factory=list)

class BPMeasurementOut(BaseModel):
    id: str
    patient_id: str
    systolic_mmhg: int
    diastolic_mmhg: int
    pulse_bpm: int | None
    verification_status: str
    created_at: datetime
