from functools import lru_cache
from typing import Any
import jwt
from jwt import PyJWKClient
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from .config import settings

bearer = HTTPBearer(auto_error=False)

@lru_cache
def _jwks_client():
    return PyJWKClient(settings.jwks_url)

async def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict[str, Any]:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        token = credentials.credentials
        header = jwt.get_unverified_header(token)
        # Supabase projects may use asymmetric ES256/RS256 signing keys.
        if header.get("alg") not in {"ES256", "RS256"}:
            raise ValueError("Unsupported JWT algorithm")
        key = _jwks_client().get_signing_key_from_jwt(token).key
        return jwt.decode(token, key, algorithms=[header["alg"]], audience=settings.supabase_jwt_aud, options={"require": ["exp", "sub", "aud"]})
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired access token") from exc
