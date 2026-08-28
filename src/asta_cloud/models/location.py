from pydantic import BaseModel, ConfigDict, Field


class Location(BaseModel):
    model_config = ConfigDict(extra="forbid")

    path: str = Field(description="POSIX path relative to the scan root.")
    line: int | None = Field(default=None, description="1-based line number.")
    end_line: int | None = None
