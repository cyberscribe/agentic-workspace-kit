# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015); single-quoted strings hold literal text for the stub (SC2016).
# shellcheck disable=SC2154,SC2015,SC2016
# Section 29: /workspace:diagnose's report (plugins/workspace/scripts/diagnose.sh). A fixture workspace
# under a planted home folder, with a planted project, a planted git name and email, and a stub claude
# whose answers carry a planted token, webhook URL, project name and home path: none of them is in the
# report, which still names the versions and the plugins. With --allow-names the project name may stay.
# Everything here is prefixed s29_, since the sections share one shell.

echo
echo "29 · Diagnose: the report names the kit's state and nothing private"

s29="$SCRATCH/s29"
s29_home="$s29/home-plantedhome"
s29_ws="$s29_home/work/plantedws"
s29_bin="$s29/bin"
mkdir -p "$s29_ws/projects/zephyr-launch" "$s29_ws/ongoing/quill-garden" "$s29_ws/.claude" "$s29_bin" "$s29_home/.claude/plugins"
ln -s "$KIT" "$s29_ws/kit"
: > "$s29_ws/.claude/kit-templates.lock"
git -C "$s29_ws" init -q
git -C "$s29_ws" config user.name "Casey Plantedname"
git -C "$s29_ws" config user.email "casey@planted.example"
printf '# Zephyr Launch\n\n## Current state\n\n- **State:** doing\n' > "$s29_ws/projects/zephyr-launch/README.md"
printf '# Projects\n\n## Active\n\n| Project | Folder | Owner | State |\n|---|---|---|---|\n| [Orchid Rollout](orchid/) | `projects/orchid/` | Casey | doing |\n' > "$s29_ws/projects/INDEX.md"
s29_secret="sk-ant-api03-PlantedSecret0123456789abcdefXYZ"
s29_hook="https://hooks.slack.com/services/T00PLANT/B00PLANT/PlantedWebhook99"
jq -n --arg p "$s29_ws" '{version: 2, plugins: {"projects@agentic-workspace": [{scope: "user"}, {scope: "project", projectPath: $p}, {scope: "project", projectPath: "/nowhere/zephyr-launch"}]}}' \
    > "$s29_home/.claude/plugins/installed_plugins.json"
cat > "$s29_bin/claude" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
    "--version "*) echo "9.9.9 (Claude Code) zephyr-launch build, Orchid Rollout, $s29_hook" ;;
    "plugin list") printf '%s\n' '[{"id":"projects@agentic-workspace","version":"3.9.0","scope":"user","enabled":true,"installPath":"$s29_home/.claude/plugins/cache/x/projects/3.9.0","readFromFolder":"$KIT/plugins/projects","folderVersion":"3.10.0"},{"id":"workspace@agentic-workspace","version":"2.4.0","scope":"project","enabled":true,"installPath":"$s29_home/secret/zephyr-launch/$s29_secret","projectPath":"$s29_ws"}]' ;;
esac
EOF
chmod +x "$s29_bin/claude"
s29_run() { (cd "$s29_ws" && env HOME="$s29_home" CLAUDE_CONFIG_DIR="$s29_home/.claude" PATH="$s29_bin:$PATH" \
    bash "$KIT/plugins/workspace/scripts/diagnose.sh" "$@" 2>&1); }
s29_out="$(s29_run)"; s29_rc=$?

s29_bad=""
[[ $s29_rc -eq 0 ]] || s29_bad+="exit $s29_rc"$'\n'
for s29_w in "$s29_secret" PlantedSecret PlantedWebhook hooks.slack.com plantedhome plantedws "$s29_home" "$HOME" \
             zephyr Zephyr quill-garden "Orchid Rollout" Plantedname casey@planted.example "$KIT"; do
    grep_all -iF -- "$s29_w" <<<"$s29_out" && s29_bad+="the report holds: $s29_w"$'\n'
done
empty "29 diagnose: no planted token, webhook URL, project or area name, git name, email or home path survives the scrub" "$s29_bad"

s29_bad=""
for s29_w in '# Fault report for the agentic workspace kit' '## Versions' '- Kit: v' '- Claude Code: 9.9.9 (Claude Code) <project> build, <project>, <secret>' \
             '## Kit plugins' 'projects@agentic-workspace user enabled, recorded 3.9.0, loads from this kit checkout (3.10.0)' \
             '## Install records' '- Records for folders that no longer exist: 1' '## Hooks' '## State check (quick)'; do
    grep_all -F -- "$s29_w" <<<"$s29_out" || s29_bad+="no: $s29_w"$'\n'
done
empty "29 diagnose: the report names the kit version, each plugin and where it loads from, the stale record, the hooks and the state check" "$s29_bad${s29_bad:+$s29_out}"

s29_out2="$(s29_run --allow-names)"
grep_all -F 'zephyr-launch build' <<<"$s29_out2" && ! grep_all -F "$s29_secret" <<<"$s29_out2" && ! grep_all -F 'plantedhome' <<<"$s29_out2" \
    && ok "29 diagnose --allow-names keeps project names and still scrubs secrets and paths" \
    || ko "29 diagnose --allow-names keeps project names and still scrubs secrets and paths" "$s29_out2"
s29_bad="$(grep -c . <<<"$(grep -rlF 'diagnose' "$s29_ws" 2>/dev/null)")"
[[ "$s29_bad" == 0 ]] && ok "29 diagnose writes nothing in the workspace without --out" || ko "29 diagnose writes nothing in the workspace without --out" "$(grep -rlF diagnose "$s29_ws")"
