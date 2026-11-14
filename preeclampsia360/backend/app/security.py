from functools import lru_cache
from typing import Any
import jwt
from jwt import PyJWKClient
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from .config import settings

bearer = HTTPBearer(auto_error=False)

@lru_cache
def _jwks_client() -> PyJWKClient:
    return PyJWKClient(settings.jwks_url)

def decode_token(token: str) -> dict[str, Any]:
    header = jwt.get_unverified_header(token)
    alg = header.get("alg")

    decode_options = {
        "require": ["exp", "sub", "aud"],
        "verify_signature": True,
        "verify_exp": True,
        "verify_aud": True,
    }

    if alg == "HS256":
        secret = settings.supabase_jwt_secret or settings.supabase_service_role_key
        if not secret:
            raise HTTPException(
                status_code=500,
                detail="Server JWT secret is not configured for HS256 verification",
            )
        return jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            audience=settings.supabase_jwt_aud,
            options=decode_options,
        )
    elif alg in {"RS256", "ES256"}:
        signing_key = _jwks_client().get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            signing_key.key,
            algorithms=[alg],
            audience=settings.supabase_jwt_aud,
            options=decode_options,
        )
    else:
        raise ValueError(f"Unsupported JWT signing algorithm: {alg}")

async def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict[str, Any]:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        payload = decode_token(credentials.credentials)
        # Verify issuer if present in token claims
        iss = payload.get("iss")
        if iss:
            expected_iss_prefix = settings.supabase_url.rstrip("/")
            if not iss.startswith(expected_iss_prefix):
                raise ValueError(f"Invalid token issuer: {iss}")
        return payload
    except HTTPException:
        raise
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired. Please sign in again.")
    except jwt.InvalidAudienceError:
        raise HTTPException(status_code=401, detail="Invalid token audience")
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"Invalid access token: {str(exc)[:100]}") from exc
