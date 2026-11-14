from __future__ import annotations
from datetime import datetime, timezone
from uuid import UUID
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from .security import current_user
from .repository import supabase_admin

router = APIRouter(prefix='/api/v1', tags=['clinical-workflows'])

ROLE_HOME = {
 'ASHA':['My Mothers','Visit Log','Symptom Reports','Follow-up Tasks','Referral Companion'],
 'ANM':['Patient Registration','Patient List','BP Scanner','Risk Radar','Follow-ups','Referrals','Postpartum'],
 'VHN':['Patient Registration','Patient List','BP Scanner','Risk Radar','Follow-ups','Referrals','Postpartum'],
 'PHC_MO':['PHC Dashboard','Clinical Review','Risk Radar','Referral Board','Team & Follow-ups','Reports'],
 'CHC_MO':['CHC Dashboard','PHC Overview','Clinical Alerts','Referral Coordination','Workload Analytics'],
 'CHC_ADMIN':['CHC Dashboard','PHC Overview','User Management','Referral Coordination','Reports'],
 'THC_MO':['THC Dashboard','CHC Comparison','Clinical Alerts','Referral Performance','Reports'],
 'THC_ADMIN':['THC Dashboard','Facility Hierarchy','User Management','Analytics','Audit'],
 'RECEIVING_STAFF':['Incoming Referrals','Referral Details','Arrival Check-in','Assessment & Outcome'],
 'SUPERVISOR':['Jurisdiction Dashboard','Escalations','Facility Performance','Reports'],
 'SYSTEM_ADMIN':['System Overview','Users & Roles','Facilities','Clinical Rules','Audit Logs','Device Health'],
}

@router.get('/workspace')
def workspace(user: dict = Depends(current_user)):
    db=supabase_admin(); uid=user['sub']
    profile=db.table('user_profiles').select('user_id,full_name,login_id,preferred_language,is_active,account_status').eq('user_id',uid).maybe_single().execute().data
    if not profile or not profile.get('is_active') or profile.get('account_status') not in (None,'active'):
        raise HTTPException(403,'Account inactive')
    assignments=db.table('user_facility_assignments').select('facility_id,role,is_active,facilities(id,name,facility_type,parent_facility_id,facility_code)').eq('user_id',uid).eq('is_active',True).execute().data or []
    if not assignments: raise HTTPException(403,'No active facility assignment')
    roles=list(dict.fromkeys(a['role'] for a in assignments))
    return {'profile':profile,'assignments':assignments,'workspaces':[{'role':r,'navigation':ROLE_HOME.get(r,[])} for r in roles]}

class QuestionnaireSection(BaseModel):
 patient_id: UUID
 pregnancy_id: UUID|None=None
 section_key: str = Field(min_length=2,max_length=80)
 answers: dict[str,Any]
 schema_version: str='1.0'
 completed: bool=False

@router.post('/questionnaires/sections',status_code=201)
def save_questionnaire_section(payload: QuestionnaireSection,user:dict=Depends(current_user)):
 db=supabase_admin(); patient=db.table('patients').select('id,facility_id').eq('id',str(payload.patient_id)).maybe_single().execute().data
 if not patient: raise HTTPException(404,'Patient not found')
 assert_patient_scope(db,user['sub'],patient['facility_id'])
 row={'patient_id':str(payload.patient_id),'pregnancy_id':str(payload.pregnancy_id) if payload.pregnancy_id else None,'section_key':payload.section_key,'answers':payload.answers,'schema_version':payload.schema_version,'completed_by':user['sub'],'completed_at':datetime.now(timezone.utc).isoformat() if payload.completed else None}
 out=db.table('questionnaire_revisions').insert(row).execute().data
 # Keep latest complete snapshot in original patient record for compatibility.
 current=patient_payload=db.table('patients').select('questionnaire_data').eq('id',str(payload.patient_id)).single().execute().data or {}
 q=current.get('questionnaire_data') or {}; q[payload.section_key]=payload.answers
 db.table('patients').update({'questionnaire_data':q}).eq('id',str(payload.patient_id)).execute()
 return out[0] if out else {'saved':True}

def assert_patient_scope(db,uid,facility_id):
 rows=db.table('user_facility_assignments').select('facility_id,role').eq('user_id',uid).eq('is_active',True).execute().data or []
 own={x['facility_id'] for x in rows}
 if facility_id in own:return
 # Resolve ancestry in application code; CHC can see PHCs beneath it, THC can see CHCs and PHCs beneath it.
 facilities=db.table('facilities').select('id,facility_type,parent_facility_id').execute().data or []
 byid={x['id']:x for x in facilities}
 for r in rows:
  cur=byid.get(facility_id); seen=set()
  while cur and cur.get('parent_facility_id') and cur['id'] not in seen:
   seen.add(cur['id']); parent=cur['parent_facility_id']
   if parent==r['facility_id'] and r['role'] in ('CHC_MO','CHC_ADMIN','THC_MO','THC_ADMIN','SUPERVISOR','SYSTEM_ADMIN'): return
   cur=byid.get(parent)
 if any(x['role']=='SYSTEM_ADMIN' for x in rows):return
 raise HTTPException(403,'Patient is outside your authorised facility hierarchy')

class ReferralCreate(BaseModel):
 patient_id: UUID
 receiving_facility_id: UUID|None=None
 reason: str=Field(min_length=3,max_length=2000)
 clinical_summary: dict[str,Any]={}

TRANSITIONS={'generated':{'sent'},'sent':{'acknowledged','rejected'},'acknowledged':{'departed','rejected'},'departed':{'arrived'},'arrived':{'assessed'},'assessed':{'completed','redirected'},'rejected':{'redirected'},'redirected':{'sent'},'completed':set()}

@router.post('/referrals',status_code=201)
def create_referral(p:ReferralCreate,user:dict=Depends(current_user)):
 db=supabase_admin(); pat=db.table('patients').select('id,facility_id').eq('id',str(p.patient_id)).maybe_single().execute().data
 if not pat: raise HTTPException(404,'Patient not found')
 assert_patient_scope(db,user['sub'],pat['facility_id'])
 row={'patient_id':str(p.patient_id),'origin_facility_id':pat['facility_id'],'receiving_facility_id':str(p.receiving_facility_id) if p.receiving_facility_id else None,'reason':p.reason,'clinical_summary':p.clinical_summary,'created_by':user['sub'],'status':'generated'}
 result=db.table('referrals').insert(row).execute().data
 if not result: raise HTTPException(400,'Referral creation failed')
 ref=result[0]; db.table('referral_events').insert({'referral_id':ref['id'],'to_status':'generated','actor_user_id':user['sub'],'note':'Referral created'}).execute()
 return ref

class ReferralTransition(BaseModel):
 status: str
 note: str|None=None

@router.post('/referrals/{referral_id}/transition')
def transition_referral(referral_id:UUID,p:ReferralTransition,user:dict=Depends(current_user)):
 db=supabase_admin(); ref=db.table('referrals').select('*').eq('id',str(referral_id)).maybe_single().execute().data
 if not ref: raise HTTPException(404,'Referral not found')
 assignments=db.table('user_facility_assignments').select('facility_id,role').eq('user_id',user['sub']).eq('is_active',True).execute().data or []
 facilities={a['facility_id']:a['role'] for a in assignments}
 is_origin=ref['origin_facility_id'] in facilities; is_receiver=ref.get('receiving_facility_id') in facilities
 if not (is_origin or is_receiver or 'SYSTEM_ADMIN' in facilities.values()): raise HTTPException(403,'No access to this referral')
 nxt=p.status.lower(); allowed=TRANSITIONS.get(ref['status'],set())
 if nxt not in allowed: raise HTTPException(409,f"Invalid referral transition: {ref['status']} → {nxt}")
 receiver_only={'acknowledged','arrived','assessed','completed','rejected'}
 if nxt in receiver_only and not (is_receiver or 'SYSTEM_ADMIN' in facilities.values()): raise HTTPException(403,'Receiving facility action required')
 db.table('referrals').update({'status':nxt,'updated_at':datetime.now(timezone.utc).isoformat()}).eq('id',str(referral_id)).execute()
 db.table('referral_events').insert({'referral_id':str(referral_id),'from_status':ref['status'],'to_status':nxt,'actor_user_id':user['sub'],'note':p.note}).execute()
 return {'referral_id':str(referral_id),'previous_status':ref['status'],'status':nxt}

@router.get('/referrals')
def list_referrals(status:str|None=Query(None),user:dict=Depends(current_user)):
 db=supabase_admin(); rows=db.table('user_facility_assignments').select('facility_id,role').eq('user_id',user['sub']).eq('is_active',True).execute().data or []
 ids=[r['facility_id'] for r in rows]
 if not ids: raise HTTPException(403,'No facility assignment')
 # Separate origin and receiving queries then de-duplicate; never expose unrelated referrals.
 found=[]
 for fid in ids:
  for col in ('origin_facility_id','receiving_facility_id'):
   q=db.table('referrals').select('*').eq(col,fid)
   if status:q=q.eq('status',status)
   found += q.order('created_at',desc=True).limit(100).execute().data or []
 uniq={x['id']:x for x in found}
 return {'items':list(uniq.values())}

@router.get('/patients/{patient_id}/timeline')
def patient_timeline(patient_id:UUID,user:dict=Depends(current_user)):
 db=supabase_admin(); p=db.table('patients').select('id,facility_id').eq('id',str(patient_id)).maybe_single().execute().data
 if not p: raise HTTPException(404,'Patient not found')
 assert_patient_scope(db,user['sub'],p['facility_id'])
 return {'bp_measurements':db.table('bp_measurements').select('*').eq('patient_id',str(patient_id)).order('measured_at',desc=True).limit(100).execute().data or [],'screenings':db.table('clinical_screenings').select('*').eq('patient_id',str(patient_id)).order('assessed_at',desc=True).limit(50).execute().data or [],'follow_ups':db.table('follow_ups').select('*').eq('patient_id',str(patient_id)).order('due_at').limit(50).execute().data or [],'referrals':db.table('referrals').select('*').eq('patient_id',str(patient_id)).order('created_at',desc=True).limit(50).execute().data or []}
