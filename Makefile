# Recipes run under sh; $(shell ...) does not on Windows make, so nothing uses it.
SHELL := sh

.PHONY: check build vet lint test vuln bootstrap

check: build vet lint test vuln

# The version is the exact commit, which the AGPLv3 section 13 source offer must name.
build:
	go build -trimpath -ldflags "-s -w -X main.version=$$(git describe --tags --always --dirty 2>/dev/null || echo dev)" ./...

vet:
	go vet ./...

lint:
	golangci-lint run ./...

# The race detector needs cgo and therefore a C compiler; CI always has one.
test:
	@command -v gcc >/dev/null 2>&1 || echo "WARNING: no C compiler found, race detector skipped"
	go test $$(command -v gcc >/dev/null 2>&1 && echo -race) -count=1 ./...

vuln:
	govulncheck ./...

bootstrap:
	go version
	golangci-lint version
	govulncheck -version
	docker compose up -d --wait
