from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from PIL import Image, ImageOps, ImageEnhance
import io, re
from .security import current_user
router=APIRouter(prefix='/api/v1/bp',tags=['bp-ocr'])

@router.post('/ocr-preview')
async def ocr_preview(image:UploadFile=File(...), user:dict=Depends(current_user)):
    if image.content_type not in ('image/jpeg','image/png','image/webp'):
        raise HTTPException(415,'Upload a JPEG, PNG or WebP image')
    raw=await image.read()
    if len(raw)>8*1024*1024: raise HTTPException(413,'Image must be 8 MB or smaller')
    try:
        im=Image.open(io.BytesIO(raw)).convert('L'); im=ImageOps.autocontrast(im); im=ImageEnhance.Sharpness(im).enhance(1.5)
    except Exception: raise HTTPException(400,'Image could not be decoded')
    text=''; engine='unavailable'
    try:
        import pytesseract
        text=pytesseract.image_to_string(im,config='--psm 6')
        engine='tesseract'
    except Exception:
        # The mobile client can run ML Kit OCR and submit its extracted text for review.
        text=''
    nums=[int(x) for x in re.findall(r'(?<![A-Za-z])\d{2,3}(?![A-Za-z])',text)]
    candidate={'systolic_mmhg':None,'diastolic_mmhg':None,'pulse_bpm':None}
    if len(nums)>=3: candidate={'systolic_mmhg':nums[0],'diastolic_mmhg':nums[1],'pulse_bpm':nums[2]}
    return {'engine':engine,'raw_text':text[:1000],'candidate':candidate,'requires_worker_verification':True,'confidence':None,'message':'OCR suggestions are not measurements until a healthcare worker visually confirms the monitor display.'}
