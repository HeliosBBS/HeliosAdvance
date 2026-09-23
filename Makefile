SHELL := sh
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -trimpath -ldflags "-s -w -X main.version=$(VERSION)"
# The race detector needs cgo and therefore a C compiler; CI always has one.
HAVE_CC := $(shell command -v gcc >/dev/null 2>&1 && echo yes)
RACE := $(if $(HAVE_CC),-race,)

.PHONY: check build vet lint test vuln bootstrap

check: build vet lint test vuln

build:
	go build $(LDFLAGS) ./...

vet:
	go vet ./...

lint:
	golangci-lint run ./...

test:
	$(if $(HAVE_CC),,@echo "WARNING: no C compiler found, race detector skipped")
	go test $(RACE) -count=1 ./...

vuln:
	govulncheck ./...

bootstrap:
	go version
	golangci-lint version
	govulncheck -version
	docker compose up -d --wait
