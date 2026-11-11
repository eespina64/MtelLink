# MtelLink

Repositorio de simulación (Maratel). Por ahora solo contiene README y licencia.

## Reglas para Claude
- Responde en español
- Antes de crear la estructura del proyecto, confirma con el usuario qué se simula y con qué stack
- Stack por defecto de la casa, salvo indicación: Docker Compose, PostgreSQL, n8n, OpenRouter
- Nunca leas ni escribas `.env*`

## Harness
- Lee `.claude/rules/aprendizajes.md` antes de cada tarea
- Tareas largas: contrato aprobado en `.claude/contracts/<tarea>.json` antes de escribir código
- Trabaja dentro de `.agent_worktrees/<tarea>` (crear con `bash scripts/nueva-tarea.sh <tarea>`) y solo en `escritura_permitida`
- Nunca te autoapruebes: un revisor distinto intenta romper el cambio
- Sin `.claude/receipts/recibo-<tarea>.json` con evidencia en 0 y veredicto APROBADO, no hay commit (el hook lo bloquea)
- Todo error corregido se agrega como regla a `.claude/rules/aprendizajes.md`
- Guía completa: `.claude/HARNESS.md`

## Estado actual
- Repo vacío; falta definir el objetivo de la simulación
