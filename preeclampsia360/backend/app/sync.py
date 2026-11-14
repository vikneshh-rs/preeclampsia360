from uuid import UUID
from typing import Any
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from .security import current_user
from .repository import supabase_admin
from .workflows import assert_patient_scope
router=APIRouter(prefix='/api/v1/sync',tags=['offline-sync'])
class SyncItem(BaseModel):
 id: UUID
 event_type: str
 entity_id: UUID|None=None
 facility_id: UUID
 client_created_at: str|None=None
 payload: dict[str,Any]
class SyncBatch(BaseModel): items: list[SyncItem]=Field(min_length=1,max_length=100)
@router.post('/push')
def push(batch:SyncBatch,user:dict=Depends(current_user)):
 db=supabase_admin(); results=[]
 assignments=db.table('user_facility_assignments').select('facility_id').eq('user_id',user['sub']).eq('is_active',True).execute().data or []
 allowed={x['facility_id'] for x in assignments}
 for item in batch.items:
  if str(item.facility_id) not in allowed:
   # Do not silently accept data from a facility the worker is not assigned to.
   results.append({'id':str(item.id),'status':'rejected','reason':'facility_not_assigned'}); continue
  existing=db.table('sync_events').select('id,processing_status').eq('id',str(item.id)).maybe_single().execute().data
  if existing:
   results.append({'id':str(item.id),'status':'duplicate','server_status':existing['processing_status']}); continue
  row={'id':str(item.id),'user_id':user['sub'],'facility_id':str(item.facility_id),'event_type':item.event_type,'entity_id':str(item.entity_id) if item.entity_id else None,'payload':item.payload,'client_created_at':item.client_created_at,'processing_status':'accepted'}
  try:
   db.table('sync_events').insert(row).execute(); results.append({'id':str(item.id),'status':'accepted'})
  except Exception as e: results.append({'id':str(item.id),'status':'rejected','reason':'persistence_error'})
 return {'results':results}
@router.get('/status')
def status(user:dict=Depends(current_user)):
 db=supabase_admin(); r=db.table('sync_events').select('processing_status').eq('user_id',user['sub']).execute().data or []
 return {'accepted':sum(x['processing_status']=='accepted' for x in r),'processed':sum(x['processing_status']=='processed' for x in r),'rejected':sum(x['processing_status']=='rejected' for x in r)}
