.PHONY: test test-bats test-legacy

## Run all tests (bats + legacy)
test: test-bats test-legacy

## Run bats-core tests
test-bats:
	@echo "=== Running bats tests ==="
	./tests/run-bats.sh

## Run legacy integration tests
test-legacy:
	@echo "=== Running legacy tests ==="
	./tests/test-setup.sh
