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

class BPMeasurementOut(BaseModel):
    id: str
    patient_id: str
    systolic_mmhg: int
    diastolic_mmhg: int
    pulse_bpm: int | None
    verification_status: str
    created_at: datetime
