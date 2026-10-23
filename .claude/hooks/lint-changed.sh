#!/usr/bin/env bash
# PostToolUse hook: rubocop no arquivo .rb que acabou de ser editado.
#
# Só valida — não corrige. Editar arquivo dentro de um hook tornaria a mudança
# invisível para quem a pediu, e o Claude conserta melhor vendo o offense.
# Saída 2 devolve o offense ao agente; qualquer outra coisa é silêncio.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 0

payload=$(cat)

file_path=$(
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null
  else
    printf '%s' "$payload" | python3 -c \
      'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null
  fi
)

[ -n "$file_path" ] || exit 0
case "$file_path" in
  *.rb) ;;
  *) exit 0 ;;
esac

# Fora do repo (ex.: ~/.claude) ou em bin/ (ignorado pelo .rubocop.yml).
case "$file_path" in
  *"/bin/"*|*"/vendor/"*|*"/node_modules/"*) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

# Só arquivos deste projeto.
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
case "$(cd "$(dirname "$file_path")" 2>/dev/null && pwd)" in
  "$root"*) ;;
  *) exit 0 ;;
esac

output=$(timeout 60 bin/rubocop --force-exclusion --format simple "$file_path" 2>&1)
status=$?

if [ "$status" -eq 0 ]; then
  exit 0
fi

if [ "$status" -eq 124 ]; then
  printf 'rubocop excedeu 60s em %s (hook abortado)\n' "$file_path" >&2
  exit 0
fi

# Offense real: devolve ao agente. Truncado para não poluir o contexto.
printf '%s\n' "$output" | tail -25 >&2
exit 2
