#!/usr/bin/env bash
# How the reader invoked us, so a printed remediation matches what they typed.
#
# Source, don't execute.
#
# The README documents `make uninstall YES=1`; the tool printed "Re-run with
# --yes". Both are right at their own layer — a make variable and a script flag
# — and neither is any use to a reader who followed the README and is now being
# told to run something it never mentioned. A remediation that doesn't match
# the invocation is a remediation the reader has to translate, and translating
# it requires knowing the thing they are here to look up.
#
# MAKELEVEL is exported by make into every recipe, so its presence is a
# reliable "we were run from a Makefile" without the Makefile having to pass
# anything down. Direct invocation, an editor task, or CI running the script
# gets the script form; `make ...` gets the make form.

invoked_via_make() { [ -n "${MAKELEVEL:-}" ]; }

# say_remediation <make-form> <script-form>
say_remediation() {
  if invoked_via_make; then printf '%s' "$1"; else printf '%s' "$2"; fi
}
