SHELL_FILES := ai_usage.tmux $(shell find scripts test/shims -type f \( -name '*.sh' -o -name 'jq' -o -path 'test/shims/*' \) ! -name '.keep') test/test_helper.bash $(wildcard test/*.bats) $(wildcard docs/demo/*.sh)

# The README images, one VHS tape each in docs/demo/tapes/.
IMAGES := hero steps rotation focus popup problems

.PHONY: test lint unit images

test: lint unit

lint:
	shellcheck -x -s bash $(SHELL_FILES)

unit:
	bats test/

# Regenerate the README images in docs/images/; ONLY=<name> for one. Needs vhs.
images:
	@command -v vhs >/dev/null || { echo 'make images needs vhs: brew install vhs' >&2; exit 1; }
	@mkdir -p docs/images
	@for image in $(or $(ONLY),$(IMAGES)); do \
	  echo "images: $$image"; \
	  vhs -q docs/demo/tapes/$$image.tape; status=$$?; \
	  bash docs/demo/start.sh --stop; \
	  rm -f /tmp/tmux-ai-usage-$$image.gif; \
	  [ $$status -eq 0 ] || exit $$status; \
	done
