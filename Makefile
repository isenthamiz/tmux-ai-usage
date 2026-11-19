SHELL_FILES := ai_usage.tmux $(shell find scripts test/shims -type f \( -name '*.sh' -o -path 'test/shims/*' \)) test/test_helper.bash

.PHONY: test lint unit

test: lint unit

lint:
	shellcheck -x -s bash $(SHELL_FILES)

unit:
	bats test/
