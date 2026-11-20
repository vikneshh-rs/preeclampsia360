from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_env: str = "development"
    app_name: str = "Preeclampsia 360 API"
    cors_origins: str = "http://localhost:3000,http://localhost:5173,http://localhost:8000,http://localhost:8080,http://127.0.0.1:8000,http://127.0.0.1:3000,https://*.vercel.app"
    supabase_url: str = "https://ymkqatqxuohrwlfajpdc.supabase.co"
    supabase_jwks_url: str | None = None
    supabase_jwt_secret: str | None = "iZ+x22qPvMuhe3CWpOEpxrNw6dQHYrYLv/dMtChvGdjgtvY4i+3qKTAzYEOIo6gj3rza+/MU6CiGWklI6MthDg=="
    supabase_jwt_aud: str = "authenticated"
    supabase_jwt_issuer: str | None = None
    supabase_service_role_key: str | None = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlta3FhdHF4dW9ocndsZmFqcGRjIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5NDU5MDM3MywiZXhwIjoyMTEwMTY2MzczfQ.6JjLHexnkl7B3jzE5qi9C3i0hzAqMPxePRkKSwrFRWc"
    internal_auth_domain: str = "staff.preeclampsia360.invalid"
    bootstrap_secret: str | None = None
    max_login_attempts: int = 5
    lockout_duration_seconds: int = 300

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def allowed_origins(self) -> list[str]:
        return [x.strip() for x in self.cors_origins.split(",") if x.strip()]

    @property
    def jwks_url(self) -> str:
        return self.supabase_jwks_url or f"{self.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"

    @property
    def jwt_issuer(self) -> str:
        return self.supabase_jwt_issuer or f"{self.supabase_url.rstrip('/')}/auth/v1"

settings = Settings()
