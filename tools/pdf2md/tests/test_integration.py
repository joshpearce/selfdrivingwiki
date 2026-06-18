"""Integration tests for pdf2md — real PDF conversion with docling.

Run from the tools/pdf2md directory:
    uv run pytest tests/test_integration.py -v

These tests require docling + spacy (declared in pyproject.toml).
"""

from __future__ import annotations

import json
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

# ── Import the pdf2md module ──────────────────────────────────────────────

_SCRIPT_PATH = Path(__file__).resolve().parent.parent / "pdf2md"
assert _SCRIPT_PATH.exists(), f"pdf2md script not found at {_SCRIPT_PATH}"
_pdf2md = SourceFileLoader("pdf2md", str(_SCRIPT_PATH)).load_module()


# ── Fixtures ─────────────────────────────────────────────────────────────


@pytest.fixture(scope="session")
def test_pdf() -> Path | None:
    """Return path to a valid test PDF."""
    # Prefer known-good PDFs, in order of quality.
    candidates = [
        Path.home() / "work/R2R/py/core/examples/supported_file_types/pdf.pdf",
        Path.home() / "work/hermes-agent/docs/hermes-kanban-v1-spec.pdf",
    ]
    for p in candidates:
        if p.exists() and p.stat().st_size > 100:
            return p
    return None


@pytest.fixture(scope="session")
def real_pdf_or_skip(test_pdf: Path | None) -> Path:  # pyright: ignore[reportReturnType]
    """Verify the PDF exists and is non-empty."""
    if test_pdf is None:
        pytest.skip("No test PDF available — set TEST_PDF env var to a PDF path")
    if test_pdf.stat().st_size == 0:  # pyright: ignore[reportOptionalMemberAccess]
        pytest.skip("Test PDF is empty")
    return test_pdf


# ── Full pipeline tests ──────────────────────────────────────────────────


@pytest.mark.slow
class TestFullConversion:
    """End-to-end PDF→Markdown conversion."""

    def test_converts_pdf_to_non_empty_markdown(self, real_pdf_or_skip):
        text = _pdf2md.convert_pdf(real_pdf_or_skip, pipeline="standard")
        assert isinstance(text, str)
        assert len(text.strip()) > 0

    def test_converts_pdf_with_vlm_pipeline(self, real_pdf_or_skip):
        text = _pdf2md.convert_pdf(real_pdf_or_skip, pipeline="vlm")
        assert isinstance(text, str)
        assert len(text.strip()) > 0

    def test_output_is_valid_utf8(self, real_pdf_or_skip):
        text = _pdf2md.convert_pdf(real_pdf_or_skip, pipeline="standard")
        text.encode("utf-8")  # does not raise

    def test_output_has_no_soft_hyphens(self, real_pdf_or_skip):
        text = _pdf2md.convert_pdf(real_pdf_or_skip, pipeline="standard")
        assert "­" not in text

    def test_nonexistent_file_raises(self, tmp_path):
        with pytest.raises(FileNotFoundError):
            _pdf2md.convert_pdf(tmp_path / "nonexistent.pdf", pipeline="standard")


class TestCLIJSONMode:
    """Test --json output from main()."""

    def test_json_output_is_valid(self, real_pdf_or_skip, tmp_path):
        out = tmp_path / "out.json"
        _pdf2md.main(argv=["--json", "-o", str(out), str(real_pdf_or_skip)])

        data = json.loads(out.read_text())
        assert "input" in data
        assert "pipeline" in data
        assert "char_count" in data
        assert "line_count" in data
        assert data["char_count"] > 0
        assert data["line_count"] > 0

    def test_json_output_default_pipeline(self, real_pdf_or_skip, tmp_path):
        out = tmp_path / "out.json"
        _pdf2md.main(argv=["--json", "-o", str(out), str(real_pdf_or_skip)])
        data = json.loads(out.read_text())
        assert data["pipeline"] == "vlm"

    def test_json_output_standard_pipeline_flag(self, real_pdf_or_skip, tmp_path):
        out = tmp_path / "out.json"
        _pdf2md.main(
            argv=[
                "--json", "--pipeline", "standard",
                "-o", str(out), str(real_pdf_or_skip),
            ]
        )
        data = json.loads(out.read_text())
        assert data["pipeline"] == "standard"


class TestCLIOutputFile:
    """Test --output writes markdown to a file."""

    def test_output_file_written(self, real_pdf_or_skip, tmp_path):
        out = tmp_path / "out.md"
        _pdf2md.main(argv=["-o", str(out), str(real_pdf_or_skip)])
        assert out.exists()
        content = out.read_text()
        assert len(content.strip()) > 0

    def test_output_file_overwrites(self, real_pdf_or_skip, tmp_path):
        out = tmp_path / "out.md"
        out.write_text("preexisting content")
        _pdf2md.main(argv=["-o", str(out), str(real_pdf_or_skip)])
        assert out.read_text() != "preexisting content"
