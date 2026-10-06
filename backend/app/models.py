import phonenumbers
from pydantic import BaseModel, Field, field_validator


def to_e164(raw: str) -> str:
    """Normalize user input to E.164, assuming US when no country code is given."""
    region = None if raw.strip().startswith("+") else "US"
    try:
        parsed = phonenumbers.parse(raw, region)
    except phonenumbers.NumberParseException as exc:
        raise ValueError("unparseable phone number") from exc
    if not phonenumbers.is_possible_number(parsed):
        raise ValueError("not a possible phone number")
    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)


class LookupRequest(BaseModel):
    phone_number: str = Field(..., min_length=5, max_length=24)

    @field_validator("phone_number")
    @classmethod
    def _normalize(cls, raw: str) -> str:
        return to_e164(raw)


class ReportRequest(BaseModel):
    phone_number: str = Field(..., min_length=5, max_length=24)
    category: str = "spam"

    @field_validator("phone_number")
    @classmethod
    def _normalize(cls, raw: str) -> str:
        return to_e164(raw)


class CallerProfile(BaseModel):
    phone_number: str
    name: str = "Unknown Caller"
    title: str = "Private Individual"
    company: str = "N/A"
    linkedin_url: str = ""
    line_type: str = "unknown"
    carrier: str = ""
    spam_score: int = 0
    source: str = "none"
    cached: bool = False


class DirectoryEntry(BaseModel):
    number: int
    label: str = ""


class DirectoryResponse(BaseModel):
    version: str
    blocked: list[int] = []
    identified: list[DirectoryEntry] = []
