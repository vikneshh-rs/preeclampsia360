from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_env: str = "development"
    app_name: str = "Preeclampsia 360 API"
    cors_origins: str = "http://localhost:3000,http://localhost:5173"
    supabase_url: str
    supabase_jwks_url: str | None = None
    supabase_jwt_aud: str = "authenticated"
    supabase_service_role_key: str | None = None
    internal_auth_domain: str = "staff.preeclampsia360.invalid"
    bootstrap_secret: str | None = None
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def allowed_origins(self) -> list[str]:
        return [x.strip() for x in self.cors_origins.split(",") if x.strip()]

    @property
    def jwks_url(self) -> str:
        return self.supabase_jwks_url or f"{self.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"

settings = Settings()
