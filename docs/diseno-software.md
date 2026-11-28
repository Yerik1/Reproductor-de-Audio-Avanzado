# Diseño de software

**Issue:** DOC-01 (base) · Contrato de hardware: [mapa-registros.md](mapa-registros.md) · Arquitectura: [arquitectura.md](arquitectura.md)

## Programas

| Programa | Procesador | Fuente | Función |
|---|---|---|---|
| `reproductor` | HPS, Linux, binario estático | `sw/src/main_hps.c` | Catálogo de la SD, máquina de estados, lectura de WAV, conversión a 48 kHz y envío de muestras a `audio_proc` |
| `control` | Nios V/m, bare metal | `sw/niosv/control/main.c` | ISR de botones, comandos al HPS, volumen desde el ADC, interfaz y medición de latencia |
| `bringup` | Nios V/m, bare metal | `sw/niosv/bringup/main.c` | Prueba de la etapa 1 sin HPS |

## Módulos del HPS

| Módulo | Responsabilidad | Pruebas |
|---|---|---|
| `wav` | Valida RIFF/WAVE PCM de 16 bits (1–2 canales, 8–48 kHz) y extrae `INAM`, `IART`, `IPRD` | 19 verificaciones: formatos válidos, inválidos, truncados, metadatos antes y después de `data` |
| `catalog` | Lista ordenada por nombre de archivo, omite ocultos y rechaza WAV inválidos sin detenerse; valores por defecto sin metadatos | 11 verificaciones |
| `resampler` | Interpolación lineal con posición Q32.32 hacia 48 kHz, por bloques | 9 verificaciones: identidad, monotonía, 44,1 kHz, equivalencia por bloques, mono |
| `mailbox` | Cola de comandos y estado con contador de secuencia | 5 verificaciones: cola llena, orden, lectura consistente |
| `player` | Máquina de estados y alimentación de la FIFO a través de `audio_out_t` | 21 verificaciones con `audio_proc` simulado: lista completa bit-exacta, pausa, siguiente, stop, navegación circular |

`player` no accede al hardware directamente: recibe una interfaz `audio_out_t` (espacio en la FIFO, FIFO vacía, escribir, `CTRL`, `TRACK`). En la placa la implementa `main_hps.c` con punteros a la ventana del puente LW obtenida con `mmap` de `/dev/mem`; en las pruebas, un modelo que consume 48 muestras por milisegundo.

## Máquina de estados (PLAY-01)

```mermaid
stateDiagram-v2
    [*] --> Detenido
    Detenido --> Reproduciendo: reproducir/pausa
    Reproduciendo --> Pausado: reproducir/pausa
    Pausado --> Reproduciendo: reproducir/pausa
    Reproduciendo --> Detenido: stop
    Pausado --> Detenido: stop
    Reproduciendo --> Reproduciendo: siguiente / anterior / fin de pista
    Reproduciendo --> Detenido: fin de la última pista
```

| Evento | Efecto | Motivo |
|---|---|---|
| Pausa | `RUN = 0`; la FIFO conserva las muestras | Reanuda sin perder audio y el tiempo en HEX se congela solo |
| Stop | `FLUSH`, `TIME_CLR`; queda en la misma pista | Tiempo en 00:00 y siguiente play desde el inicio |
| Siguiente / anterior | Circulares; si reproducía, la nueva pista suena; si no, queda detenido en ella | Navegación sin bordes muertos |
| Fin de pista | Espera la FIFO vacía, luego `FLUSH`, `TIME_CLR`, `TRACK` y precarga de la siguiente | El tiempo y la pista cambian cuando realmente cambia el audio; en la simulación el silencio entre pistas es de 0,2 ms |
| Fin de la lista | Detenido en la primera pista | Comportamiento definido (AUD-04) |

## Buzón HPS ↔ Nios V

Memoria de 4 KB en la FPGA (`0xFF210000`), accedida por ambos procesadores con punteros `volatile`.

| Campo | Escribe | Uso |
|---|---|---|
| `magic` | HPS | `MBX1` cuando el reproductor está listo |
| `heartbeat` | HPS | Se incrementa cada 2 ms; el Nios V detecta un HPS detenido |
| `flags` | HPS | `MBX_FLAG_FIXED_VOL` (opción `-f`): volumen fijo mientras no hay potenciómetro |
| `cmd_head`, `cmd[16]` | Nios V | Cola de comandos: un solo productor |
| `cmd_tail` | HPS | Comandos consumidos: un solo consumidor |
| `seq`, estado | HPS | Impar mientras se escribe; el Nios V descarta lecturas con `seq` impar o cambiado |

Cada lado escribe solo sus campos, así que no se necesitan bloqueos entre procesadores.

## Botones

| Botón | Comando |
|---|---|
| KEY3 | Anterior |
| KEY2 | Stop |
| KEY1 | Reproducir / pausa |
| KEY0 | Siguiente |

La ISR del Nios V lee y limpia el registro de edge capture del PIO, cuenta el evento y guarda `mtime`. El lazo principal envía el comando y, cuando el HPS lo consume, imprime la latencia (CTL-02). Los botones de la DE1-SoC tienen antirrebote por Schmitt trigger en la placa.

## Volumen (VOL-01, VOL-02)

| Elemento | Valor |
|---|---|
| Conexión | Potenciómetro entre VCC5 (pin 1 del header 2x5) y GND (pin 10); cursor en ADC_IN0 (pin 2) |
| Lectura | Canal CH0 del ADC Controller (`0xFF204000`) en auto-actualización, 12 bits, 0–5 V |
| Calibración medida en la placa | 0 en un extremo y 4095 en el otro: se usa el rango completo sin corrección |
| Ganancia | `VOLUME = v² / 512` en Q1.15: 0 → silencio, 4095 → `0x7FF0` (0,9995) |
| Volumen fijo | Con `reproductor -f` el HPS activa `MBX_FLAG_FIXED_VOL` y el Nios V escribe `0x8000` |

La curva cuadrática da más resolución en volúmenes bajos, donde el oído distingue cambios pequeños. La ganancia nunca supera 1 y `audio_proc` satura el producto, así que el volumen no introduce recorte.

## Memoria utilizada (AUD-02)

| Recurso | Tamaño | Uso |
|---|---|---|
| FIFO de `audio_proc` | 4096 × 32 bits (16 KB, M10K) | 85 ms de audio a 48 kHz entre escrituras del HPS |
| Buzón | 4 KB en la FPGA, 304 B usados (`mailbox_t`) | Comandos y estado HPS ↔ Nios V |
| RAM del Nios V | 256 KB en la FPGA | Programa `control` y su pila |
| Memoria de bloques total (reporte de Quartus) | 2 292 736 bits (56 %), 286 de 397 bloques M10K (72 %) | Incluye las tres anteriores y los coeficientes FIR |
| `reproductor` (`arm-linux-gnueabihf-size`) | 342 KB de código, 13 KB de datos, 69 KB de `bss` | Binario estático, sin dependencias de la imagen |
| `catalog_t` | 30 472 B | Hasta 64 pistas con ruta y metadatos |
| `player_t` | 28 808 B | Bloque de lectura de 1024 tramas y salida remuestreada |

## Restricciones del profesor

- HAL solo para interrupciones: `alt_ic_isr_register` en el Nios V; ningún otro `alt_*`.
- Acceso a periféricos con punteros a las bases de `system.h`, sin `IOWR`/`IORD`.
