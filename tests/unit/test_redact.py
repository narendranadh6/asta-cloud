from asta_cloud.security.redact import redact_text


def test_redacts_openai_style_token() -> None:
    secret = "sk-astaCloudFixtureKeyDoNotUse0001"
    redacted = redact_text(f"token = '{secret}'")
    assert secret not in redacted
    assert "sk-[REDACTED]" in redacted


def test_redacts_pem_block() -> None:
    pem = "-----BEGIN PRIVATE KEY-----\nABCDEF\n-----END PRIVATE KEY-----"
    redacted = redact_text(pem)
    assert "ABCDEF" not in redacted
    assert "[REDACTED]" in redacted
