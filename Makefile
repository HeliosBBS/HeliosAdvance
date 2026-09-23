# Recipes must run under both sh and cmd.exe: GNU Make on Windows ignores SHELL.
# The race detector needs a C compiler, so CI passes RACE=-race; pass it locally too
# when one is installed. Version: Go embeds the commit at build time; releases
# stamp the tag with -X main.version.
RACE ?=
LDFLAGS ?= -s -w

.PHONY: check build vet lint test vuln bootstrap

check: build vet lint test vuln

build:
	go build -trimpath -ldflags "$(LDFLAGS)" ./...

vet:
	go vet ./...

lint:
	golangci-lint run ./...

test:
	go test $(RACE) -count=1 ./...

vuln:
	govulncheck ./...

bootstrap:
	go version
	golangci-lint version
	govulncheck -version
	docker compose up -d --wait
