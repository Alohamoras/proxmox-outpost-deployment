# Proxmox VE on EC2 Test Makefile

.PHONY: test test-fast test-cleanup test-small help clean

# Default target
help:
	@echo "Proxmox VE on EC2 Test Suite"
	@echo ""
	@echo "Available targets:"
	@echo "  test        - Run full test with c5.2xlarge (default)"
	@echo "  test-fast   - Run test with c5.4xlarge for faster deployment"
	@echo "  test-small  - Run test with t3.small (slower, cheaper)"
	@echo "  test-cleanup - Run test and cleanup resources after success"
	@echo "  clean       - Clean up any leftover test files"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  INSTANCE_TYPE     - EC2 instance type (default: c5.2xlarge)"
	@echo "  CLEANUP_ON_FAILURE - Cleanup resources on failure (default: true)"
	@echo "  CLEANUP_AFTER_SUCCESS - Cleanup resources after success (default: false)"

# Standard test
test:
	./run-test.sh

# Fast test with larger instance
test-fast:
	INSTANCE_TYPE=c5.4xlarge ./run-test.sh

# Small/cheap test
test-small:
	INSTANCE_TYPE=t3.small ./run-test.sh

# Test with cleanup after success
test-cleanup:
	CLEANUP_AFTER_SUCCESS=true ./run-test.sh

# Clean up test artifacts
clean:
	rm -f test-*.log
	rm -f test-report-*.md
	rm -f proxmox-test-*.pem
	@echo "Cleaned up test artifacts"