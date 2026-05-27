# Project Best Practices

This document provides a brief overview of best practices when working with the PhotoPrism codebase. Following these guidelines helps maintain a consistent architecture and keeps build and runtime performance high.

## Development Environment

- Install all required dependencies before running tests or building the project. For the frontend this means running `npm install` within the `frontend` directory.
- Node.js tests depend on a Chromium based browser. Ensure that `CHROME_BIN` is set to the path of an available Chrome or Chromium installation when running `npm test`.
- Go developers should install the toolchain specified in `go.mod` and keep dependencies updated via `go get -u` where appropriate.

## Coding Guidelines

- Write clear, self-documenting code and keep functions small and focused.
- Add unit tests for new functionality. Frontend tests are located under `frontend/tests`; backend tests are colocated with package source files.
- For performance critical code paths, prefer streaming and incremental processing over loading entire datasets into memory.
- Review pull requests with attention to database migrations, API compatibility and security implications.

## Continuous Integration

- Lint and format your changes before opening a pull request. The frontend uses `npm run lint` and `npm run fmt` while Go code should be formatted with `go fmt`.
- Run the full test suite (`npm test` and `go test ./...`) locally to catch issues early.

Adhering to these recommendations will keep the project easy to maintain and ensure that it performs well in production deployments.

## BRAINS Backups

The `BRAINS` models can consume significant disk space, especially when backups accumulate.
Use `scripts/cleanup_brains_backups.py` to remove backups older than a specified
number of days:

```bash
python scripts/cleanup_brains_backups.py --days 30 --dry-run
```

Run this regularly to prevent the backup directory from growing without bounds.

## Forensic Case Builder

Use `scripts/forensic_case_builder.py` to move evidence files into
case-specific directories while preserving a record of SHA-256 digests.
Run in dry-run mode first to verify the planned actions:

```bash
python scripts/forensic_case_builder.py /path/to/source CASE123 --dry-run
```

This organizes files under `cases/CASE123/` using timestamped names so
chain-of-custody requirements are met.
