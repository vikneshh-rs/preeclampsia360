# Preeclampsia 360 — V1 Foundation

Premium maternal monitoring and referral coordination platform. This repository is the initial integrated foundation for Flutter Android/Web, FastAPI, and Supabase.

> **Clinical safety:** This software supports healthcare workers; it does not diagnose or prescribe. Clinical rules, thresholds, escalation timing, and workflows must be configured and approved by qualified clinical governance before pilot use. Sample data is fictional.

## Architecture

- `flutter_app/`: Flutter application shell for Android and Web.
- `backend/`: FastAPI service; verifies Supabase access tokens and enforces role/facility scope in application services.
- `supabase/migrations/`: PostgreSQL schema, constraints, indexes, RLS foundation and audit structures.
- `docs/`: architecture, questionnaire mapping and deployment notes.

Flutter communicates with FastAPI for clinical/business operations. Do not place the Supabase `service_role` key in Flutter or expose it to users. Supabase Auth issues user tokens; FastAPI validates them using the Supabase JWT signing configuration/JWKS.

## Local development

### Backend

```bash
cd backend
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload
```

API docs: `http://127.0.0.1:8000/docs` (development only).

### Flutter

Install Flutter stable, then:

```bash
cd flutter_app
flutter create . --platforms=android,web
flutter pub get
flutter run -d chrome
```

The Flutter app initialises `supabase_flutter` using the configured project URL and client publishable key in `lib/core/supabase_config.dart`. You can override the key at build time with `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`. The publishable key is intended for client use, but all exposed tables must have correctly configured Row Level Security (RLS). Never add the service-role key to Flutter. The current app shell initialises the SDK; full sign-in screens and end-to-end auth flows remain to be implemented and tested.

### Supabase

1. Use project URL: `https://ymkqatqxuohrwlfajpdc.supabase.co`.
2. Open SQL Editor and run the migration in `supabase/migrations/`.
3. Configure Auth providers and redirect URLs for your app domains.
4. Set backend environment variables from `backend/.env.example`.
5. Create the first system administrator through a controlled provisioning process; never make public self-registration an administrator path.

## Initial implementation status

This is a deployable engineering foundation, not a clinically validated production release. The initial API includes health, authenticated identity, facility scope, patient registration/list/detail, and BP measurement capture/verification primitives. Full OCR engine integration, push/SMS providers, offline conflict resolution, clinical rule approval workflow, referral state machine, and role-specific screen coverage are planned implementation increments and must be completed and tested before operational deployment.

## Hosting

- Initial option: Render free web service (subject to current free-tier sleep, resource, and availability limitations).
- Production path: Google Cloud Run.
- Supabase database/auth remains separately managed.

See `docs/DEPLOYMENT.md`.


## Current implementation status

This repository is a development foundation, not a clinically validated production release. It includes initial database migrations, a Flutter theme/dashboard scaffold, FastAPI API scaffold, and ID/PIN authentication endpoints. Complete role workflows, hierarchy enforcement, bootstrap tooling, offline sync, OCR integration, referral state machine, and end-to-end tests remain to be completed and validated. See `docs/AUTHENTICATION.md` and `docs/QUESTIONNAIRE_MAPPING.md`.


## Incremental workflow modules
See `docs/IMPLEMENTATION_STATUS.md` and `docs/BOOTSTRAP_AND_RUNBOOK.md`. Migration 0004 adds questionnaire revisions and offline event inbox. New FastAPI routers provide role workspace metadata, questionnaire section writes, patient timeline, referrals, sync queue acceptance, and OCR preview. These are development increments and require migration execution, full tests, security review, and clinical sign-off before pilot use.

## First System Administrator bootstrap

See `docs/BOOTSTRAP_AND_RUNBOOK.md`. Apply `supabase/migrations/0005_system_admin_bootstrap.sql`, create or confirm an active THC with a facility code, then run the trusted CLI from `backend/` with server-side Supabase environment variables. Never expose the service-role secret to clients or share it in chat.
