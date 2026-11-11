# Kit de harness CIDETIU para repos

Copiar el contenido de esta carpeta en la raíz de cada repo (respetando `.claude/`).

## Qué trae

- `.claude/settings.json`: registra el hook que bloquea `git commit` y `git push` sin recibo aprobado.
- `.claude/hooks/require-receipt.sh`: el hook. Requiere `jq`.
- `.claude/contracts/plantilla-contrato.json`: contrato de tarea.
- `.claude/receipts/plantilla-recibo.json`: recibo de entrega (la plantilla no cuenta como recibo).
- `.claude/rules/aprendizajes.md`: errores convertidos en reglas.
- `scripts/nueva-tarea.sh`: crea un worktree aislado y una rama `agent/<tarea>`.

## Flujo

1. `bash scripts/nueva-tarea.sh <id-tarea>` crea `.agent_worktrees/<id-tarea>`.
2. Copia la plantilla de contrato a `.claude/contracts/<id-tarea>.json`, complétala y apruébala.
3. Claude Code trabaja dentro del worktree, solo en `escritura_permitida`.
4. Un revisor distinto (subagente o sesión aparte) intenta romper el cambio.
5. Se escribe `.claude/receipts/recibo-<id-tarea>.json` con pruebas en 0 y veredicto `APROBADO`.
6. Recién entonces el hook deja hacer commit.
7. Cualquier error corregido se agrega a `.claude/rules/aprendizajes.md`.

## Agregar a `.gitignore`

```
.agent_worktrees/
```
