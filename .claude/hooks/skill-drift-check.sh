#!/usr/bin/env bash
# Skill/documentation drift detector (PostToolUse on Bash, fires after `git commit`).
#
# After a commit lands, this inspects the committed files. If any "structural" source
# file changed (schemas, hardware layer, controllers, automation, supervision tree,
# migrations, web UI, deps), it reminds Claude to check whether the matching
# .claude/skills/*.md or CLAUDE.md still describes reality.
#
# Advisory only — it never blocks. Mapping is curated to high-signal files so it
# doesn't nag on routine logic tweaks.

input=$(cat)

cmd=$(printf '%s' "$input" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception:
    print("")' 2>/dev/null)

# Only act when the Bash command was a git commit.
case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Files in the most recent commit (the one just created). --root handles a root commit.
files=$(git diff-tree --no-commit-id --name-only -r --root HEAD 2>/dev/null)
[ -z "$files" ] && exit 0

# Map a single path to the doc(s) most likely to drift (empty = not structural).
map_target() {
  case "$1" in
    */.claude/skills/*|CLAUDE.md|*/CLAUDE.md|*/.claude/hooks/*) echo "" ;;
    */test/*|test/*)                  echo "" ;;
    */priv/repo/migrations/*|priv/repo/migrations/*) echo "CLAUDE.md (DB/logging) + pou-con-schema.md" ;;
    */equipment/schemas/*)            echo "pou-con-schema.md + pou-con-controller.md (valid types / fields)" ;;
    */hardware/ports/port.ex)         echo "pou-con-schema.md (Port schema/protocols)" ;;
    */hardware/devices/*)             echo "pou-con-hardware.md (read_fn/write_fn device modules)" ;;
    */hardware/*)                     echo "pou-con-hardware.md (DataPointManager/PortWorker/adapters)" ;;
    */logging/*)                      echo "CLAUDE.md logging section + pou-con-schema.md (log tables)" ;;
    */equipment/equipment_loader.ex)  echo "pou-con-controller.md + CLAUDE.md (type->module mapping)" ;;
    */equipment/controllers/*)        echo "pou-con-controller.md (controller taxonomy/state machine)" ;;
    */automation/*)                   echo "pou-con-automation.md" ;;
    */application.ex)                 echo "CLAUDE.md supervision tree + pou-con-automation.md (startup order)" ;;
    *lib/pou_con_web/*)               echo "pou-con-liveview.md" ;;
    mix.exs|*/mix.exs)                echo "pou-con-libraries.md (dependency/library reference)" ;;
    *) echo "" ;;
  esac
}

# Collect unique "file -> target" lines for structural files only.
report=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  t=$(map_target "$f")
  [ -z "$t" ] && continue
  report="${report}  - ${f} -> ${t}"$'\n'
done <<< "$files"

[ -z "$report" ] && exit 0

python3 -c 'import json,sys
report = sys.stdin.read().rstrip("\n")
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": (
        "[skill-drift-check] The commit you just made touched structural files. "
        "For any that changed schema, public API, valid types, table names, or documented "
        "behavior, update the mapped docs so they stay in sync with the code:\n" + report
    )
}}))' <<< "$report"

exit 0
