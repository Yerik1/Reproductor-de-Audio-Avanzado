# Guía de Contribución — Reproductor de Audio Avanzado (CE-1113)

Esta guía define el flujo de trabajo de Git para el **Proyecto II: Co-diseño Hardware/Software de SoC con hardware personalizado para reproductor de audio avanzado**. 
**Equipo:** Yerik, Emmanuel, Gabriel y Sergio.  
**Entrega:** 2 de diciembre de 2026.  

## 1. Estructura de branches

- **`main`**: rama estable. Solo recibe PRs desde `develop` al cerrar un hito verificado. Prohibidos commits directos.
- **`develop`**: rama de integración. Recibe PRs revisados de las ramas de trabajo.
- **Ramas por issue**: se crean desde `develop` actualizado y vuelven a `develop` mediante PR.

Flujo: `feature/<descripcion-corta>` (o `test/`, `fix/`, `docs/`, `chore/`) → PR a `develop` → pruebas e integración → PR de `develop` a `main`.

## 2. Convención de nombres de branches

| Tipo | Formato | Uso |
|---|---|---|
| Funcionalidad | `feature/<descripcion-corta>` | Nueva función o módulo |
| Pruebas | `test/<descripcion-corta>` | Testbench, pruebas automatizadas o de integración |
| Corrección | `fix/<descripcion-corta>` | Bug reproducible |
| Documentación | `docs/<descripcion-corta>` | Diseño, instrucciones o evidencias |
| Mantenimiento | `chore/<descripcion-corta>` | Configuración y dependencias |

La descripción se escribe en **minúsculas, con guiones**. **El número del issue no va en el nombre de la rama**; se referencia en el PR.

**Ejemplos para este proyecto:**

```text
feature/hps-sd-access
feature/wav-parser
feature/audio-core-output
feature/hps-fpga-mmio
feature/dsp-custom-filter
feature/button-interrupts
feature/adc-volume
feature/seven-segment-timer
feature/song-metadata-display
test/dsp-filter-testbench
test/audio-latency
fix/audio-buffer-underrun
docs/hardware-register-map
docs/readme-final
chore/repo-setup
```

Cada rama debe corresponder a un issue existente. Los códigos internos del backlog (`SD-02`, `DSP-02`, etc.) pueden aparecer en el **título o cuerpo del PR**, junto con el número real de GitHub, pero no son necesarios en la rama.

## 3. Mensajes de commit: Conventional Commits

Formato:

```text
<tipo>(<ámbito>): <descripción breve en imperativo>
```

| Tipo | Cuándo se usa |
|---|---|
| `feat` | Nueva función o componente |
| `fix` | Corrección de error |
| `test` | Caso de prueba, testbench o medición |
| `docs` | Documentación o evidencias |
| `refactor` | Reorganización sin modificar comportamiento |
| `chore` | Mantenimiento y configuración |

El **ámbito es opcional, pero recomendado**. Ámbitos sugeridos: `hps`, `fpga`, `dsp`, `audio`, `sd`, `wav`, `irq`, `adc`, `ui`, `sevenseg`, `soc`, `docs`, `repo`.

```text
feat(sd): implementar acceso a canciones desde HPS
feat(wav): validar cabecera PCM de 16 bits
feat(audio): enviar muestras al Audio Core de FPGA
feat(dsp): implementar filtro FIR personalizado en HDL
test(dsp): agregar testbench con vectores de referencia
feat(irq): manejar botones mediante interrupciones
feat(ui): mostrar titulo y duracion de pista
fix(audio): corregir underrun del buffer
docs(soc): documentar mapa de registros MMIO
docs(readme): agregar instrucciones de compilacion
chore(repo): configurar plantillas de issues y Git Flow
```

Realizar un commit por cambio lógico. Evitar mensajes como `avances`, `final`, `cambios` o commits enormes que mezclen tareas no relacionadas.

## 4. Ciclo de vida de un cambio

1. Elegir un issue del `BACKLOG.md` ya creado en GitHub; confirmar responsable y criterios de aceptación.
2. Actualizar `develop` y crear una rama nueva con el prefijo apropiado.
3. Implementar el alcance del issue; subir commits descriptivos y pruebas/evidencias cuando aplique.
4. Abrir PR **hacia `develop`**; incluir resumen, pasos de prueba, evidencias y referencia al issue (`Closes #12` para cerrarlo al fusionar, o `Refs #12` si no debe cerrarse aún).
5. Solicitar revisión a **al menos un integrante distinto del autor**. Atender observaciones antes del merge.
6. Verificar la Definition of Done global y los criterios específicos del issue; fusionar PR a `develop`.
7. Al completar un hito funcional probado, crear un PR de `develop` a `main` y revisarlo.

**Nunca** hacer commits directos a `main`; tampoco `git push --force` a `main` o `develop`. No fusionar ramas con pruebas conocidas como fallidas sin documentar y resolver el riesgo.

Comandos de ejemplo:

```bash
git switch develop
git pull --ff-only origin develop
git switch -c feature/wav-parser

# Editar y ejecutar pruebas...
git add .
git commit -m "feat(wav): validar cabecera PCM de 16 bits"
git push -u origin feature/wav-parser
```

## 5. Gestión de issues y tablero Kanban

Cada feature o tarea técnica del backlog se registra como **issue**. Su contenido mínimo incluye descripción breve, criterios de aceptación, Definition of Done específica, dependencias cuando existan y pruebas/evidencia.

**Estados del GitHub Project:**

| Estado | Significado |
|---|---|
| `Pendiente` | Comprometido, pero no iniciado |
| `En progreso` | Implementación o pruebas en curso |
| `En revisión` | PR y evidencia listos para revisión |
| `Hecho` | PR fusionado y DoD validada |
| `Icebox` | Extra opcional o idea no comprometida, **no** finalizada |

- Los créditos extra (`EXTRA-01`, `EXTRA-02`) permanecen **abiertos en Icebox** hasta que el equipo decida realizarlos y acuerde su valoración con el profesor.
- Los requisitos **obligatorios no se mueven a Icebox** para ocultar trabajo pendiente: cualquier recorte se registra como riesgo explícito.
- Los bugs se documentan como issues nuevos (`bug`) con pasos para reproducirlos, comportamiento observado/esperado y evidencia.
- Evitar más de 1–2 issues simultáneos en `En progreso` por persona; se permite trabajo paralelo entre integrantes.
- Para cada issue, definir un responsable principal y, cuando haga falta, un compañero de apoyo; toda revisión de PR debe ser cruzada.
- No cerrar manualmente un issue antes de comprobar las pruebas. Verificar que la automatización del tablero no lo marque `Hecho` prematuramente.

## 6. Definition of Done global

Un issue solo se considera finalizado cuando:

- [ ] Satisface sus criterios de aceptación.
- [ ] Se compiló/simuló/ejecutó y verificó en el entorno pertinente; se enlaza evidencia según corresponda.
- [ ] La documentación modificada (interfaces, memoria, APIs, esquemas, README) está actualizada.
- [ ] No incorpora usos de `alt_*` fuera del **manejo de interrupciones**, según la aclaración del profesor.
- [ ] Si se utiliza Nios V, accede a periféricos con punteros MMIO directos según `system.h` y **no utiliza `IOWR`/`IORD`**.
- [ ] El PR referencia el issue, contiene descripción y pruebas, y fue revisado por otra persona.
- [ ] El PR está fusionado en `develop` y el tablero refleja el estado correcto.

**Reglas técnicas críticas del proyecto:** SD administrada por HPS; Audio Core implementado en FPGA; botones por interrupciones; 
7 segmentos controlados en hardware; al menos un filtro DSP propio descrito en HDL y **verificado aisladamente antes de integrarlo**. 
Los otros requisitos y métricas están en.

## 7. Responsabilidades y revisiones

| Frente | Responsable inicial | Revisión/apoyo sugerido |
|---|---|---|
| HPS, SD, WAV y reproducción | Jerick | Emanuel |
| Arquitectura SoC, puentes HPS–FPGA, Audio Core | Emanuel | Jerick o Gabriel |
| Filtro DSP personalizado y verificación HDL | Gabriel | Emanuel |
| Pantalla, indicadores, QA y evidencias | Sergio | Jerick |

Las áreas son una **distribución inicial**, no exclusivas. Se deben acordar pronto las interfaces 
entre módulos para que el equipo avance en paralelo (registros, PCM, buffers, flags, IRQ y datos 
para pantalla).

## 8. Checklist recomendado para Pull Requests

```md
## Resumen
- ¿Qué cambia este PR?

## Issue relacionado
- Closes #<numero>   <!-- o Refs #<numero> si aun no se cierra -->

## Pruebas y evidencia
- [ ] Compilación / simulación / ejecución relevante
- [ ] Criterios de aceptación verificados
- [ ] Evidencia adjunta o enlazada

## Revisión técnica
- [ ] Sin uso de alt_* fuera de interrupciones
- [ ] Sin IOWR/IORD en Nios V, si corresponde
- [ ] Documentación e interfaces actualizadas
- [ ] Revisado por otra persona
```

## 9. Cierre de hitos y repositorio

- Hacer PR `develop -> main` únicamente cuando una fase sea estable y demostrable.
- Mantener el `README.md` actualizado con instalación, compilación, uso, arquitectura, memoria, pruebas y evidencias, según la especificación.
- Guardar informes de Quartus (recursos y consumo PowerPlay), simulaciones de filtros y resultados de pruebas para la entrega.
- El tablero y el historial deben contar la historia completa del desarrollo, incluyendo bugs, revisiones, descartes opcionales y decisiones justificadas.
