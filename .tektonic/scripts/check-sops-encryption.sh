#!/bin/sh
# Fail if anything that is supposed to be SOPS-encrypted was committed in plaintext.
#
# .sops.yaml decides what *gets* encrypted when someone runs `sops -e`; nothing
# enforces that they did. A secret committed before encryption is in git history
# for good, so this runs on every pull request rather than at review time.
set -eu

rc=0
found=0

# `*.secret.template.yaml` and `secrets.template.yaml` are plaintext placeholders
# by design and do not match these patterns.
files=$(find . -path ./.git -prune -o -type f \
    \( -name '*.secret.yaml' -o -name '*.enc.yaml' -o -name 'secrets.yaml' \) -print | sort)

for f in $files; do
    case "$f" in
        *template*) continue ;;
    esac
    found=$((found + 1))
    # SOPS appends a `sops:` block (YAML) or a "sops" key (JSON) to everything it
    # encrypts; its absence means the file is cleartext.
    if grep -q '^sops:' "$f" || grep -q '^[[:space:]]*"sops"[[:space:]]*:' "$f"; then
        printf 'ok    %s\n' "$f"
    else
        printf 'FAIL  %s is NOT encrypted\n' "$f"
        rc=1
    fi
done

if [ "$found" -eq 0 ]; then
    printf '✗ no secret files matched — the patterns in this script have drifted\n' >&2
    exit 1
fi

printf '\n'
if [ "$rc" -eq 0 ]; then
    printf '✓ all %s secret files are SOPS-encrypted\n' "$found"
else
    printf '✗ plaintext secrets found — do NOT merge; rotate anything already pushed\n'
fi
exit "$rc"
