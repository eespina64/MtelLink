#!/usr/bin/env bash
# Crea un worktree aislado para una tarea de Claude Code.
# Uso: bash scripts/nueva-tarea.sh <id-tarea> [rama-base]
set -euo pipefail

TAREA="${1:?Indica un id de tarea, por ejemplo: bash scripts/nueva-tarea.sh corregir-login}"
BASE="${2:-main}"
RUTA=".agent_worktrees/${TAREA}"

mkdir -p .agent_worktrees
git worktree add -b "agent/${TAREA}" "${RUTA}" "${BASE}"

if [ -f .env.example ]; then
  cp .env.example "${RUTA}/.env"
fi

cp .claude/contracts/plantilla-contrato.json ".claude/contracts/${TAREA}.json" 2>/dev/null || true

echo "Worktree listo en ${RUTA}"
echo "Completa .claude/contracts/${TAREA}.json, apruébalo y abre Claude Code dentro de ${RUTA}"
