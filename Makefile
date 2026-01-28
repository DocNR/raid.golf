.PHONY: analyze analyze-latest

analyze:
	@if [ -z "$(file)" ]; then \
		echo "Usage: make analyze file=path/to/session.csv"; \
		exit 1; \
	fi
	python tools/scripts/analyze_session.py "$(file)"

analyze-latest:
	@latest=$$(ls -t data/session_logs/*.csv 2>/dev/null | head -n 1); \
	if [ -z "$$latest" ]; then \
		echo "No session logs found in data/session_logs"; \
		exit 1; \
	fi; \
	python tools/scripts/analyze_session.py "$$latest"
