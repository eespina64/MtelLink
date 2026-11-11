#!/usr/bin/env bash
# Hook PreToolUse de Claude Code: bloquea git commit / git push sin recibo aprobado.
# Claude Code envía el evento como JSON por stdin. Salir con código 2 bloquea la herramienta
# y el texto de stderr vuelve a Claude como explicación.
set -uo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"

case "$CMD" in
  *"git commit"*|*"git push"*) ;;
  *) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DIR="$ROOT/.claude/receipts"

RECIBO="$(ls -t "$DIR"/recibo-*.json 2>/dev/null | head -n 1)"
if [ -z "$RECIBO" ]; then
  echo "Commit bloqueado: no hay recibo en .claude/receipts/recibo-<tarea>.json. Verifica la tarea y escribe el recibo primero." >&2
  exit 2
fi

ESTADO="$(jq -r '.verificacion.veredicto // empty' "$RECIBO")"
FALLIDAS="$(jq -r '[.evidencia[]? | select(.codigo_salida != 0)] | length' "$RECIBO")"

if [ "$ESTADO" != "APROBADO" ]; then
  echo "Commit bloqueado: el recibo $(basename "$RECIBO") tiene veredicto '${ESTADO:-vacío}', no APROBADO." >&2
  exit 2
fi
if [ "${FALLIDAS:-1}" != "0" ]; then
  echo "Commit bloqueado: el recibo $(basename "$RECIBO") registra comandos de evidencia con código distinto de 0." >&2
  exit 2
fi

exit 0
