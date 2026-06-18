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


# Minimal hand-crafted PDF with known extractable text.  No external PDF
# library needed — just a few bytes of valid PDF syntax.  Used by tests that
# only care about the I/O path (stdout, file output, JSON, error handling),
# not conversion quality.
_MINIMAL_PDF_BYTES = (
    b"%PDF-1.4\n"
    b"1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
    b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
    b"3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R"
    b"/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj\n"
    b"4 0 obj<</Length 44>>stream\n"
    b"BT /F1 12 Tf 72 720 Td (Hello World) Tj ET\n"
    b"endstream\nendobj\n"
    b"5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n"
    b"xref\n0 6\n0000000000 65535 f \n0000000009 00000 n \n"
    b"0000000058 00000 n \n0000000115 00000 n \n"
    b"0000000266 00000 n \n0000000360 00000 n \n"
    b"trailer<</Size 6/Root 1 0 R>>\nstartxref\n437\n%%EOF"
)


@pytest.fixture(scope="session")
def minimal_pdf(tmp_path_factory) -> Path:
    """A tiny valid PDF with known text ('Hello World').  Created once per session."""
    p = tmp_path_factory.mktemp("pdf") / "minimal.pdf"
    p.write_bytes(_MINIMAL_PDF_BYTES)
    return p


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


class TestCLIStdout:
    """Test that main() writes markdown to stdout — this is the code path
    PdfExtractionService.run() exercises when it pipes pdf2md's stdout.
    Uses a tiny hand-crafted PDF so the tests are fast and never hang."""

    def test_stdout_contains_markdown(self, minimal_pdf, capsys):
        _pdf2md.main(argv=[str(minimal_pdf)])
        captured = capsys.readouterr()
        assert len(captured.out.strip()) > 0, "stdout should contain markdown text"
        # A harmless deprecation warning from transformers may land on stderr;
        # real errors are signalled by exit code, not by stderr emptiness.
        assert "Error:" not in captured.err, (
            f"stderr should not contain errors, got: {captured.err!r}"
        )

    def test_stdout_matches_file_output(self, minimal_pdf, tmp_path, capsys):
        """The markdown written to stdout must be byte-identical to --output."""
        out = tmp_path / "out.md"
        _pdf2md.main(argv=["-o", str(out), str(minimal_pdf)])
        file_content = out.read_text()

        _pdf2md.main(argv=[str(minimal_pdf)])
        stdout_content = capsys.readouterr().out

        assert stdout_content == file_content, (
            "stdout and --output must produce identical markdown"
        )

    def test_json_to_stdout(self, minimal_pdf, capsys):
        """--json writes metadata to stdout (no markdown)."""
        _pdf2md.main(argv=["--json", str(minimal_pdf)])
        captured = capsys.readouterr()
        data = json.loads(captured.out.strip())
        assert "char_count" in data
        assert "line_count" in data
        assert data["char_count"] > 0
        assert data["line_count"] > 0
        assert data["pipeline"] == "vlm"

    def test_json_ignores_output_flag(self, minimal_pdf, tmp_path, capsys):
        """--json always writes to stdout; the -o flag is ignored for JSON.
        This is existing behaviour — documented, not prescribed."""
        out = tmp_path / "out.json"
        _pdf2md.main(argv=["--json", "-o", str(out), str(minimal_pdf)])
        captured = capsys.readouterr()
        # JSON went to stdout, not the file.
        data = json.loads(captured.out.strip())
        assert data["char_count"] > 0
        # File was never created (--json ignores -o).
        assert not out.exists()


class TestErrorOutput:
    """Error messages go to the right file descriptor."""

    def test_nonexistent_file_error_to_stderr(self, capsys):
        with pytest.raises(SystemExit) as exc:
            _pdf2md.main(argv=["/nonexistent/path.pdf"])
        assert exc.value.code == 1
        captured = capsys.readouterr()
        assert captured.out == "", "stdout should be empty on error"
        assert "Error:" in captured.err
        assert "nonexistent" in captured.err

    def test_nonexistent_file_also_stderr_in_json_mode(self, capsys):
        """The file-exists check runs before --json is consulted, so
        'file not found' always goes to stderr regardless of --json."""
        with pytest.raises(SystemExit) as exc:
            _pdf2md.main(argv=["--json", "/nonexistent/path.pdf"])
        assert exc.value.code == 1
        captured = capsys.readouterr()
        assert captured.out == ""
        assert "Error:" in captured.err
        assert "nonexistent" in captured.err


class TestCLIWithMinimalPdf:
    """Output-file and JSON tests that are safe to run on the tiny PDF."""

    def test_output_file_written(self, minimal_pdf, tmp_path):
        out = tmp_path / "out.md"
        _pdf2md.main(argv=["-o", str(out), str(minimal_pdf)])
        assert out.exists()
        content = out.read_text()
        assert len(content.strip()) > 0

    def test_output_file_overwrites(self, minimal_pdf, tmp_path):
        out = tmp_path / "out.md"
        out.write_text("preexisting content")
        _pdf2md.main(argv=["-o", str(out), str(minimal_pdf)])
        assert out.read_text() != "preexisting content"

    def test_json_stdout_metadata(self, minimal_pdf, capsys):
        """--json writes metadata to stdout (no -o flag needed)."""
        _pdf2md.main(argv=["--json", str(minimal_pdf)])
        captured = capsys.readouterr()
        data = json.loads(captured.out.strip())
        assert data["char_count"] == 11  # "Hello World" is 11 characters
        assert data["line_count"] == 1
        assert data["pipeline"] == "vlm"
