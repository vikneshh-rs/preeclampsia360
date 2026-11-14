# Flutter screens and FastAPI wiring

## Implemented screens

- ID + 6-digit PIN login (`POST /api/v1/auth/login`)
- Authenticated workspace and role/facility context (`GET /api/v1/workspace`)
- Clinical overview dashboard (`GET /api/v1/patients`, `GET /api/v1/referrals`)
- Patient search/list (`GET /api/v1/patients`)
- Patient 360 detail and timeline (`GET /api/v1/patients/{id}`, `GET /api/v1/patients/{id}/timeline`)
- Multi-step registration and structured questionnaire payload (`POST /api/v1/patients`)
- BP measurement with explicit worker confirmation (`POST /api/v1/bp/measurements`)
- Android camera image capture and on-device ML Kit text recognition as a suggestion only
- Referral creation and lifecycle actions (`POST /api/v1/referrals`, `POST /api/v1/referrals/{id}/transition`)

## Run locally

1. Start the FastAPI service from `backend/` after configuring `.env`:

   ```powershell
   python -m venv .venv
   .venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

2. Start Flutter from `flutter_app/`:

   ```powershell
   flutter pub get
   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
   ```

   For Android emulator use `--dart-define=API_BASE_URL=http://10.0.2.2:8000`.
   For a physical device, use the development computer's reachable LAN address or deployed HTTPS API URL.

3. Android camera OCR uses `image_picker` and `google_mlkit_text_recognition`. Add/confirm camera permission in `android/app/src/main/AndroidManifest.xml` when generating the native Android project:

   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   ```

## Important implementation boundaries

- Flutter sends all clinical data to FastAPI; it does not query Supabase clinical tables directly.
- The Supabase publishable key is not used to bypass the API. The API bearer token is stored with `flutter_secure_storage`.
- The camera OCR reads visible text and only pre-fills candidate values. It is not a validated BP-device integration. A worker must compare every value to the physical display and explicitly confirm before submission.
- OCR extraction is Android-only in this increment. Web uses manual entry.
- Offline local persistence, encrypted database, outbox replay, conflict resolution, refresh-token rotation, PIN change, facility management screens and full role-specific dashboards remain follow-up work.
- The current dashboard uses a common clinical workspace shell with role/facility context. It is not yet a fully differentiated dashboard for every role.
- The backend currently has known authorization limitations documented in the implementation status; do not use this build with real patient data until hierarchy access, referral receiving-facility access, RLS/service-role boundaries and security tests have been reviewed.

## Validation performed

- Python source syntax compilation passed with `python -m compileall`.
- Flutter SDK/Dart analyzer were not available in the build environment, so Flutter compilation and device tests remain to be run locally.
