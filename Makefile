.PHONY: all_checks hardcode_string_check missing_translation_check organize_translations missing_locale_key_check test test-ci test-file test-pattern test-only local check_untracked_files help

all_checks: hardcode_string_check missing_translation_check missing_locale_key_check

# Show available make targets
help:
	@echo "Available targets:"
	@echo "  test                - Run all tests without coverage"
	@echo "  test-cov           - Run all tests with coverage"
	@echo "  test-only           - Run tests tagged with 'only'"
	@echo "  test-file FILE=...  - Run tests for a specific file"
	@echo "                        Example: make test-file FILE=RPGLootFeed_spec/Features/Currency_spec.lua"
	@echo "  test-pattern PATTERN=... - Run tests matching a pattern"
	@echo "                        Example: make test-pattern PATTERN=\"quantity mismatch\""
	@echo "  test-ci             - Run tests for CI (TAP output)"
	@echo "  all_checks          - Run all code quality checks"
	@echo "  hardcode_string_check - Check for hardcoded strings"
	@echo "  missing_translation_check - Check for missing translations"
	@echo "  organize_translations - Organize translations"
	@echo "  missing_locale_key_check - Check for missing locale keys"
	@echo "  generate_hidden_currencies - Generate hidden currencies list"
	@echo "  lua_deps            - Install Lua dependencies"
	@echo "  check_untracked_files - Check for untracked git files"
	@echo "  watch               - Watch for changes and build"
	@echo "  dev                 - Build for development"
	@echo "  build               - Build for production"

# Variables
ROCKSBIN := $(HOME)/.luarocks/bin

# Target for running the hardcoded string checker
hardcode_string_check:
	@poetry run python .scripts/hardcode_string_check.py

# Target for running the missing translation checker
missing_translation_check:
	@poetry run python .scripts/missing_translation_check.py

organize_translations:
	@poetry run python .scripts/organize_translations.py

missing_locale_key_check:
	@poetry run python .scripts/check_for_missing_locale_keys.py

generate_hidden_currencies:
	@poetry run python .scripts/get_wowhead_hidden_currencies.py RPGLootFeed/Features/Currency/HiddenCurrencies.lua

test:
	@$(ROCKSBIN)/busted RPGLootFeed_spec

test-only:
	@$(ROCKSBIN)/busted --tags=only RPGLootFeed_spec

# Run tests with coverage
test-cov:
	@rm -rf luacov-html && rm -rf luacov.*out && mkdir -p luacov-html && $(ROCKSBIN)/busted --coverage RPGLootFeed_spec && $(ROCKSBIN)/luacov && echo "\nCoverage report generated at luacov-html/index.html"

# Run tests for a specific file
# Usage: make test-file FILE=RPGLootFeed_spec/Features/Currency_spec.lua
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make test-file FILE=path/to/test_file.lua"; \
		exit 1; \
	fi
	@$(ROCKSBIN)/busted --verbose "$(FILE)"

# Run tests matching a specific pattern
# Usage: make test-pattern PATTERN="quantity mismatch"
test-pattern:
	@if [ -z "$(PATTERN)" ]; then \
		echo "Usage: make test-pattern PATTERN=\"test description\""; \
		exit 1; \
	fi
	@$(ROCKSBIN)/busted --verbose --filter="$(PATTERN)" RPGLootFeed_spec

test-ci:
	@rm -rf luacov-html && rm -rf luacov.*out && mkdir -p luacov-html && $(ROCKSBIN)/busted --coverage -o=TAP RPGLootFeed_spec && $(ROCKSBIN)/luacov

lua_deps:
	@luarocks install busted --local
	@luarocks install luacov --local
	@luarocks install luacov-html --local

check_untracked_files:
	@if [ -n "$$(git ls-files --others --exclude-standard)" ]; then \
		echo "You have untracked files:"; \
		git ls-files --others --exclude-standard; \
		echo ""; \
		echo "This may cause errors in game. Please stage or remove them."; \
		exit 1; \
	else \
		echo "No untracked files."; \
	fi

watch: missing_locale_key_check check_untracked_files
	@wow-build-tools watch -t RPGLootFeed -r ./.release

dev: missing_locale_key_check check_untracked_files
	@wow-build-tools build -d -t RPGLootFeed -r ./.release --skipChangelog

build: missing_locale_key_check check_untracked_files
	@wow-build-tools build -d -t RPGLootFeed -r ./.release
