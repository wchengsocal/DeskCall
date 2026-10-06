import os
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    mock_mode: bool = True

    twilio_account_sid: str = ""
    twilio_auth_token: str = ""

    b2b_api_key: str = ""
    b2b_base_url: str = "https://api.blitz-api.ai/v2/enrichment/phone-to-person"

    cache_ttl_seconds: int = 86_400
    rate_limit_per_minute: int = 20
    client_keys: str = ""

    upstream_timeout_seconds: float = 4.0

    class Config:
        env_file = os.getenv("ENV_FILE", ".env")
        case_sensitive = False

    @property
    def allowed_client_keys(self) -> set[str]:
        return {k.strip() for k in self.client_keys.split(",") if k.strip()}

    @property
    def telecom_configured(self) -> bool:
        return bool(self.twilio_account_sid and self.twilio_auth_token)

    @property
    def b2b_configured(self) -> bool:
        return bool(self.b2b_api_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()
