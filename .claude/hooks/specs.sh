#!/usr/bin/env bash
# Stop hook: roda a suíte antes de o agente encerrar o turno.
#
# A suíte inteira leva ~1.2s (191 exemplos, zero rede, zero banco), então o
# custo por turno é baixo e o retorno é alto: um spec vermelho não passa
# despercebido.
#
# Só roda quando há Ruby sujo na árvore: um turno que só mexeu em .md não paga
# o boot do Rails. Saída 2 bloqueia o encerramento e devolve as falhas ao
# agente; `stop_hook_active` evita o laço de bloquear para sempre.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 0

payload=$(cat)
if command -v jq >/dev/null 2>&1; then
  [ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
fi

[ -f Gemfile.lock ] || exit 0

# Nada de Ruby alterado (staged, unstaged ou untracked) → nada a validar.
if [ -z "$(git status --porcelain -- '*.rb' 2>/dev/null)" ]; then
  exit 0
fi

output=$(timeout 150 bundle exec rspec --no-color 2>&1)
status=$?

[ "$status" -eq 0 ] && exit 0

if [ "$status" -eq 124 ]; then
  printf 'rspec excedeu 150s — verifique spec travado ou dependência de rede.\n' >&2
  exit 2
fi

printf '%s\n' "$output" \
  | grep -E "^(Failures:|  [0-9]+\)|Failure/Error|rspec \./|[0-9]+ examples?,)" \
  | head -30 >&2
printf '\nRode `bundle exec rspec` para a saída completa.\n' >&2
exit 2
