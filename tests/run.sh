#!/bin/bash
# Run the model unit tests (no Qt required).
cd "$(dirname "$0")/.." || exit 1
exec node --test tests/model.test.mjs
