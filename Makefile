# Recipes must run under both sh and cmd.exe: GNU Make on Windows ignores SHELL.
# The race detector needs a C compiler, so CI passes RACE=-race; pass it locally too
# when one is installed. CI also passes COVER=-coverprofile=coverage.out for its
# report; coverage is never a gate. Version: Go embeds the commit at build time;
# releases stamp the tag with -X main.version.
RACE ?=
COVER ?=
LDFLAGS ?= -s -w
# Lazarus projects live under tools/; the toolchain is needed only where one exists, and
# a developer whose Lazarus is not on PATH passes LAZBUILD=<path>.
LAZARUS_PROJECTS := $(wildcard tools/*/*.lpi tools/*/*/*.lpi)
LAZBUILD ?= lazbuild

.PHONY: check build vet lint test vuln pascal bootstrap

check: build vet lint test vuln pascal

build:
	go build -trimpath -ldflags "$(LDFLAGS)" ./...

vet:
	go vet ./...

lint:
	golangci-lint run ./...

test:
	go test $(RACE) $(COVER) -count=1 ./...

vuln:
	govulncheck ./...

pascal:
ifneq ($(strip $(LAZARUS_PROJECTS)),)
	$(LAZBUILD) --build-mode=Release $(LAZARUS_PROJECTS)
endif

bootstrap:
	go version
	golangci-lint version
	govulncheck -version
	docker compose up -d --wait
