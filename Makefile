# Convenience targets. Everything runs from the repository root.
.PHONY: help check test-help evidence

help:
	@echo "make check      syntax-check every shell script and verify the evidence checksums"
	@echo "make test-help  how to run the per-Mac test scripts"
	@echo "make evidence   rebuild evidence/EVIDENCE.pdf, the figure PNGs and the checksums"

check:
	@for f in $$(git ls-files '*.sh'); do bash -n "$$f" || exit 1; done; echo "shell syntax: ok"
	@cd evidence && shasum -a 256 -c --quiet MANIFEST.sha256 && echo "evidence checksums: ok"

test-help:
	@echo "Start this Mac's services:  ./demo.sh ready"
	@echo "Then run its tests:         ./tests/test-mac1.sh   (or mac2, mac3, mac4)"
	@echo "Results are saved under evidence/test-results/"

evidence:
	./evidence/build/build.sh
