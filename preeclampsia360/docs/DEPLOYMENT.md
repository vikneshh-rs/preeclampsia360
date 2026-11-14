# Deployment guide

## Render (initial free-tier option)
1. Push this repository to a private GitHub repository.
2. Create a Render Web Service from `backend/` (or set root directory to `backend`).
3. Build command: `pip install -r requirements.txt`.
4. Start command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`.
5. Add environment variables from `.env.example` using Render's secret environment configuration.
6. Configure CORS with the exact Flutter Web origin.

Free-tier availability, sleep behaviour, resource limits and persistence can change. Do not rely on a free service for time-critical clinical alerts without a reliability review.

## Google Cloud Run migration
Build from `backend/` using the included Dockerfile. Configure the same environment variables using Secret Manager. Set min instances and scaling/health checks according to the pilot's clinical availability requirements.

## Supabase
Run SQL migration in order. Keep database backups enabled. Store service-role key only in backend secrets. Use separate development/staging/production projects when moving beyond prototype.

## Production gates
- Clinical approval of rules, alert thresholds, escalation timelines and questionnaire workflow.
- Security review, access-control tests, audit verification and penetration testing.
- Backup/restore drill and data retention policy.
- Consent, privacy notice, incident response and breach process.
- Offline sync, duplicate event and conflict tests.
- OCR accuracy evaluation on actual BP monitor models and lighting conditions.
