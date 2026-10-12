# shellcheck shell=bash
# KIT, SCRATCH and the check helpers come from tests/run.sh (SC2154); checks are "cond && ok || ko"
# (SC2015).
# shellcheck disable=SC2154,SC2015
# Section 24: kit/setup.sh cowork. Every kit plugin packaged as <plugin>-<version>.plugin, each a zip
# with its manifest and no bin/; a plugin Cowork would refuse is reported and not packaged; --check
# writes nothing; and setup.sh dispatches the mode. Everything here is prefixed s24_.

echo
echo "24 · kit/setup.sh cowork: the kit's plugins as Cowork .plugin files"

s24_ws="$SCRATCH/s24/ws"
s24_out="$SCRATCH/s24/out"
mkdir -p "$s24_ws"

s24_res="$(bash "$KIT/lib/setup/cowork.sh" --target "$s24_ws" --out "$s24_out" 2>&1)"; s24_rc=$?
s24_bad=""
for s24_m in "$KIT"/plugins/*/.claude-plugin/plugin.json; do
    s24_n="$(jq -r .name "$s24_m")" s24_v="$(jq -r .version "$s24_m")"
    s24_f="$s24_out/$s24_n-$s24_v.plugin"
    if [[ ! -s "$s24_f" ]]; then s24_bad+="no $s24_n-$s24_v.plugin"$'\n'; continue; fi
    s24_l="$(python3 -c 'import sys, zipfile; print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))' "$s24_f")"
    grep -qx '.claude-plugin/plugin.json' <<<"$s24_l" || s24_bad+="$s24_n: no .claude-plugin/plugin.json at the zip's root"$'\n'
    grep -q '^bin/' <<<"$s24_l" && s24_bad+="$s24_n: carries bin/"$'\n'
done
[[ $s24_rc -eq 0 && -z "$s24_bad" ]] && ok "24 every kit plugin packaged as <plugin>-<version>.plugin, manifest at the root, no bin/" \
    || ko "24 every kit plugin packaged as <plugin>-<version>.plugin, manifest at the root, no bin/" "rc=$s24_rc $s24_res $s24_bad"

# A plugins folder with one good plugin and two Cowork refuses.
s24_from="$SCRATCH/s24/plugins"
mkdir -p "$s24_from/good/.claude-plugin" "$s24_from/long/.claude-plugin" "$s24_from/withbin/.claude-plugin" "$s24_from/withbin/bin"
printf '{"name":"good","version":"1.2.3","description":"Fine."}\n' > "$s24_from/good/.claude-plugin/plugin.json"
jq -n --arg d "$(printf 'x%.0s' $(seq 1 501))" '{name:"long",version:"1.0.0",description:$d}' > "$s24_from/long/.claude-plugin/plugin.json"
printf '{"name":"withbin","version":"1.0.0","description":"Has bin."}\n' > "$s24_from/withbin/.claude-plugin/plugin.json"
: > "$s24_from/withbin/bin/tool"
s24_out2="$SCRATCH/s24/out2"
s24_res="$(bash "$KIT/lib/setup/cowork.sh" --target "$s24_ws" --from "$s24_from" --out "$s24_out2" 2>&1)"; s24_rc=$?
[[ $s24_rc -eq 1 && -s "$s24_out2/good-1.2.3.plugin" && ! -e "$s24_out2/long-1.0.0.plugin" && ! -e "$s24_out2/withbin-1.0.0.plugin" \
    && "$s24_res" == *"refused long: description is 501 characters"* && "$s24_res" == *"refused withbin: has a top-level bin/"* ]] \
    && ok "24 a description over 500 characters or a bin/ folder is refused and not packaged; the rest are built; exit 1" \
    || ko "24 a description over 500 characters or a bin/ folder is refused and not packaged; the rest are built; exit 1" "rc=$s24_rc $s24_res"

s24_out3="$SCRATCH/s24/out3"
s24_res="$(bash "$KIT/lib/setup/cowork.sh" --target "$s24_ws" --from "$s24_from" --out "$s24_out3" --check good 2>&1)"; s24_rc=$?
[[ $s24_rc -eq 0 && "$s24_res" == "checked good 1.2.3" && ! -e "$s24_out3" ]] && ok "24 --check names what it checked and writes nothing" \
    || ko "24 --check names what it checked and writes nothing" "rc=$s24_rc $s24_res"

s24_res="$(bash "$KIT/setup.sh" cowork --target "$s24_ws" --check 2>&1)"; s24_rc=$?
[[ $s24_rc -eq 0 && "$(grep -c '^checked ' <<<"$s24_res")" -eq "$(ls -d "$KIT"/plugins/*/.claude-plugin | wc -l | tr -d ' ')" ]] \
    && ok "24 kit/setup.sh cowork dispatches to lib/setup/cowork.sh" || ko "24 kit/setup.sh cowork dispatches to lib/setup/cowork.sh" "rc=$s24_rc $s24_res"
