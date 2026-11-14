# Architecture and security decisions

## Facility scope

The database stores a parent-child facility hierarchy: PHC belongs to CHC; CHC belongs to THC. Access must be computed server-side from the authenticated user's active assignments and descendant facilities. Receiving-facility access is a separate, time-bounded referral grant and must not grant general access to unrelated patients. The current starter API deliberately implements only direct facility matching; hierarchy traversal and referral grants are a required next increment before CHC/THC or cross-facility workflows are enabled.

## Patient questionnaire

The original ANM/ASHA proforma is represented in `docs/QUESTIONNAIRE_MAPPING.md`. Store versioned structured responses in `patients.questionnaire_data` initially; promote stable repeatable/analytical fields into normalized tables as the form implementation is completed. Do not silently modify the source questions.

## BP capture

Capture image locally, run on-device text recognition where supported, optionally submit an encrypted image to a backend OCR adapter, show extracted SYS/DIA/pulse and confidence, then require worker visual confirmation. OCR confidence is not clinical verification. Preserve provenance, device, worker, timestamps and verification state. Define image retention/deletion with clinical and privacy governance before enabling uploads.

## Offline

Flutter dependencies include Drift and connectivity detection, but the outbox, idempotency keys, conflict resolution and sync reconciliation are not implemented in this foundation. Implement append-only clinical events and server-authoritative rule evaluation before field deployment.
