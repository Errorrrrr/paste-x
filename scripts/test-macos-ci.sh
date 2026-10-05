#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log_file=$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pastex-swift-test.XXXXXX")
echo "Swift test log: $log_file"

# Capture both exit codes immediately: tee must not hide a failed test run.
set +e
swift test --disable-sandbox 2>&1 | tee "$log_file"
pipeline_status=("${PIPESTATUS[@]}")
set -e
test_status=${pipeline_status[0]}
log_status=${pipeline_status[1]}

if [[ "$test_status" != 0 ]]; then
    # Annotations remain readable through the checks API even when the full
    # Actions log requires signing in. Keep real diagnostics, with bounded context.
    python3 - "$log_file" "$test_status" <<'PY' || echo '::error::Unable to summarize the Swift test log; see the complete log above.'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
lines = text.splitlines()

def is_diagnostic(line):
    return "error:" in line.lower() or "✘" in line or "recorded an issue" in line

diagnostics = []
seen = set()
for index, line in enumerate(lines):
    if not is_diagnostic(line) or line in seen:
        continue
    seen.add(line)
    context = [line]
    for following in lines[index + 1:index + 4]:
        if is_diagnostic(following):
            break
        context.append(following)
    diagnostics.append("\n".join(context))

if not diagnostics:
    diagnostics = [f"swift test exited with status {sys.argv[2]}. Last output:\n" + "\n".join(lines[-20:])]

for diagnostic in diagnostics[:10]:
    message = diagnostic[:6000]
    # Escape workflow command data in this order so literal %0A cannot inject lines.
    message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error::{message}")

if len(diagnostics) > 10:
    print(f"::notice::{len(diagnostics) - 10} additional Swift diagnostics are in the complete test log.")
PY
elif [[ "$log_status" != 0 ]]; then
    echo '::error::Swift tests passed, but tee could not save the complete test log.'
    exit "$log_status"
fi

exit "$test_status"
