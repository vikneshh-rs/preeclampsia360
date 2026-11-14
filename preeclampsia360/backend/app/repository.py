from supabase import create_client, Client
from .config import settings


def supabase_admin() -> Client:
    if not settings.supabase_service_role_key:
        raise RuntimeError("Backend Supabase service key is not configured")
    return create_client(settings.supabase_url, settings.supabase_service_role_key)
