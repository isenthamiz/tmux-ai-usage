SHELL_FILES := ai_usage.tmux $(shell find scripts test/shims -type f \( -name '*.sh' -o -name 'jq' -o -path 'test/shims/*' \) ! -name '.keep') test/test_helper.bash $(wildcard test/*.bats)

.PHONY: test lint unit

test: lint unit

lint:
	shellcheck -x -s bash $(SHELL_FILES)

unit:
	bats test/
