#!/bin/bash
# ZLAR public installer transition stub.
#
# Current core source access is private. This public website does not publish an
# authorized installer bundle, clone path, live hook path, or machine-governance
# activation path.

set -eu

cat <<'MSG'
ZLAR public installer is not available from zlar.ai right now.

Current boundary:
- Public verification uses static zlar.ai artifacts:
  https://zlar.ai/release.json
  https://zlar.ai/demo/proof-pack/proof-pack-manifest.json
- Current core source access is private.
- Prior Apache-2.0 public distribution remains licensed.
- This stub does not install, activate, configure hooks, emit live receipts, or
  claim current-machine governance.

To discuss one routed action surface or request source review:
hello@zlar.ai
MSG

exit 1
