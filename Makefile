
# HTML for the Editor's Copy: `make html`
# Publish that HTML to the gh-pages branch: `make gh-pages`
LIBDIR := deps/i-d-template
include deps/i-d-template/main.mk

$(LIBDIR)/main.mk:
	@echo "Updating submodules"
	git submodule update --init --recursive

