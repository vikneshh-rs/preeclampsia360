from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, status
from PIL import Image, ImageOps, ImageEnhance
import io, re
from .security import current_user

router = APIRouter(prefix="/api/v1/bp", tags=["bp-ocr"])

@router.post("/ocr-preview")
async def ocr_preview(image: UploadFile = File(...), user: dict = Depends(current_user)):
    if image.content_type not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Upload a valid JPEG, PNG or WebP image",
        )
    raw = await image.read()
    if len(raw) > 8 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Image must be 8 MB or smaller",
        )

    try:
        im = Image.open(io.BytesIO(raw)).convert("L")
        im = ImageOps.autocontrast(im)
        im = ImageEnhance.Sharpness(im).enhance(1.5)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Image could not be decoded: {str(exc)[:100]}",
        )

    text = ""
    engine = "unavailable"
    engine_error = None

    try:
        import pytesseract
        text = pytesseract.image_to_string(im, config="--psm 6")
        engine = "tesseract"
    except ImportError:
        engine_error = "PyTesseract package is not installed."
    except Exception as exc:
        err_msg = str(exc)
        if "tesseract is not installed" in err_msg.lower() or "not found" in err_msg.lower():
            engine_error = "Native Tesseract binary is not installed in the operating environment."
        else:
            engine_error = f"OCR engine execution error: {err_msg[:120]}"

    if engine_error:
        return {
            "engine": engine,
            "status": "engine_unavailable",
            "error_detail": engine_error,
            "raw_text": "",
            "candidate": {"systolic_mmhg": None, "diastolic_mmhg": None, "pulse_bpm": None},
            "requires_worker_verification": True,
            "message": f"Server OCR is unavailable ({engine_error}). Please use mobile camera OCR or manual entry.",
        }

    nums = [int(x) for x in re.findall(r"(?<![A-Za-z])\d{2,3}(?![A-Za-z])", text)]
    candidate = {"systolic_mmhg": None, "diastolic_mmhg": None, "pulse_bpm": None}
    validation_warning = None

    if len(nums) >= 2:
        # Heuristic: SYS is usually higher than DIA
        if nums[0] > nums[1]:
            candidate["systolic_mmhg"] = nums[0]
            candidate["diastolic_mmhg"] = nums[1]
            if len(nums) >= 3:
                candidate["pulse_bpm"] = nums[2]
        else:
            candidate["systolic_mmhg"] = nums[0]
            candidate["diastolic_mmhg"] = nums[1]
            validation_warning = "Extracted SYS <= DIA. Monitor readings may be inverted or misplaced."
    else:
        validation_warning = "No 2-digit or 3-digit blood pressure numbers detected in image."

    return {
        "engine": engine,
        "status": "success" if candidate["systolic_mmhg"] else "unrecognized",
        "raw_text": text[:1000],
        "candidate": candidate,
        "validation_warning": validation_warning,
        "requires_worker_verification": True,
        "message": "OCR suggestions are not medical records until visually confirmed against the physical display by a healthcare worker.",
    }
