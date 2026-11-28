# Mapa de memoria y contrato HW/SW

**Issue:** ARC-03 · **Estado:** registros de `audio_proc` verificados en simulación y en la placa desde el HPS y el Nios V; mapa generado por [`fpga/scripts/build_system.tcl`](../fpga/scripts/build_system.tcl).

## Mapa de memoria

Las direcciones son las mismas para el Nios V y para el HPS: el puente LW del HPS empieza en `0xFF200000`, así que el HPS ve `audio_proc_0` en el offset `0x00000` y `mailbox` en `0x10000` de su ventana. Se conservan las direcciones del DE1-SoC Computer de FPGAcademy para los periféricos de University Program.

| Componente | Dirección | Tamaño | Maestros | IRQ Nios V | Función |
|---|---|---|---|---|---|
| `ram` | `0x00000000` | 256 KB | Nios V | — | Programa y datos del Nios V |
| `cpu.dm_agent` | `0x0A000000` | — | Nios V | — | Módulo de depuración |
| `audio_proc_0` | `0xFF200000` | 64 B | Nios V, HPS | — | Muestras, filtros, volumen, tiempo y 7 segmentos |
| `key_pio` | `0xFF200050` | 16 B | Nios V | 2 | KEY3..KEY0, flanco de subida de `~KEY` (al presionar) |
| `jtag_uart` | `0xFF201000` | 8 B | Nios V | 8 | Consola de depuración |
| `cpu.timer_sw_agent` | `0xFF202100` | 16 B | Nios V | — | `mtime`, `mtimecmp`, `msip` |
| `av_config` | `0xFF203000` | 16 B | Nios V | — | Configuración I2C del WM8731 (48 kHz, 32 bits) |
| `audio` | `0xFF203040` | 16 B | Nios V, `audio_proc_0.m0` | — | Audio Core: `CONTROL`, `FIFOSPACE`, `LEFTDATA`, `RIGHTDATA` |
| `adc` | `0xFF204000` | 32 B | Nios V | — | ADC de 8 canales; potenciómetro en CH0 |
| `mailbox` | `0xFF210000` | 4 KB | Nios V, HPS | — | Buzón: comandos y estado del reproductor ([`sw/src/mailbox.h`](../sw/src/mailbox.h)) |
| Pantalla externa | por definir (etapa 3) | — | Nios V | — | UI-02 |

## Registros de `audio_proc`

Accesos de 32 bits. Encabezado C: [`sw/src/audio_proc_regs.h`](../sw/src/audio_proc_regs.h).

| Offset | Nombre | Acceso | Reset | Descripción |
|---|---|---|---|---|
| `0x00` | `ID` | RO | `0x41554450` | Identificador "AUDP"; primera prueba del puente |
| `0x04` | `CTRL` | RW | `0x100` | Control (ver campos) |
| `0x08` | `STATUS` | RO | — | Estado (ver campos) |
| `0x0C` | `FIFO_SPACE` | RO | `FIFO_DEPTH` | Muestras estéreo que se pueden escribir sin pérdida |
| `0x10` | `DATA` | WO | — | `[31:16]` izquierda, `[15:0]` derecha, PCM 16 bits con signo a 48 kHz |
| `0x14` | `VOLUME` | RW | `0x8000` | Ganancia Q1.15 sin signo; `0x8000` = 1,0 |
| `0x18` | `PLAYED` | RO | 0 | Muestras estéreo escritas en el Audio Core desde `TIME_CLR` |
| `0x1C` | `TIME` | RO | 0 | Tiempo en BCD: `[15:12]` decenas de minuto … `[3:0]` unidades de segundo |
| `0x20` | `TRACK` | RW | 0 | Pista mostrada en HEX5..HEX4 (0 apaga ambos) |
| `0x24` | `UNDERRUN` | RO | 0 | Veces que la FIFO quedó vacía con `RUN = 1` |
| `0x28` | `COEF_ADDR` | RW | 0 | `{banco[1:0], tap[6:0]}` |
| `0x2C` | `COEF_DATA` | WO | — | Escribe el coeficiente Q1.15 en `COEF_ADDR` y lo incrementa |
| `0x30` | `OVERFLOW` | RO | 0 | Escrituras a `DATA` descartadas por FIFO llena |
| `0x34` | `FIFO_DEPTH` | RO | 4096 | Capacidad de la FIFO |

### Campos de `CTRL`

| Bit | Campo | Descripción |
|---|---|---|
| 0 | `RUN` | 1 = consume la FIFO (reproduciendo); 0 = retiene las muestras (pausa) |
| 1 | `FLUSH` | Escribir 1 vacía la FIFO y borra el historial del filtro |
| 2 | `TIME_CLR` | Escribir 1 pone en cero `PLAYED`, `TIME`, `UNDERRUN` y `OVERFLOW` |
| 3 | `SEL_SRC` | 0 = filtro según SW1..SW0; 1 = filtro según `FILTER` |
| 5:4 | `FILTER` | Filtro cuando `SEL_SRC = 1` |
| 8 | `HEX_EN` | 1 = displays encendidos |

### Campos de `STATUS`

| Bit | Campo |
|---|---|
| 1:0 | Filtro activo |
| 2 | FIFO vacía |
| 3 | FIFO llena |
| 4 | `RUN` |
| 5 | Motor DSP ocupado |
| 9:8 | SW1..SW0 sincronizados |

### Filtros

| SW1 SW0 | Código | Filtro |
|---|---|---|
| 0 0 | 0 | Bypass (sin procesamiento) |
| 0 1 | 1 | Pasa-bajos FIR 1 kHz |
| 1 0 | 2 | Pasa-altos FIR 2 kHz |
| 1 1 | 3 | Pasa-banda FIR 300–3400 Hz |

127 taps, ventana Hamming, coeficientes Q1.15 generados por [`tools/filters.py`](../tools/filters.py). Respuesta: [`img/filtros_respuesta.png`](img/filtros_respuesta.png).

## Secuencias de software

| Acción | Escrituras |
|---|---|
| Inicio | Leer `ID`; `CTRL = HEX_EN \| FLUSH \| TIME_CLR`; `VOLUME` según ADC |
| Play de una pista | `TRACK = n`; precargar `DATA` hasta llenar; `CTRL = HEX_EN \| RUN` |
| Reproducción | Mientras haya pista: escribir `FIFO_SPACE` muestras en `DATA` |
| Pausa / continuar | `CTRL` con `RUN = 0` / `RUN = 1` (la FIFO conserva las muestras) |
| Stop | `CTRL = HEX_EN \| FLUSH \| TIME_CLR` |
| Cambio de pista | `CTRL = HEX_EN \| FLUSH \| TIME_CLR`, luego secuencia de play |
| Fin de pista | Al terminar el archivo, esperar `STATUS.FIFO vacía` y pasar a la siguiente |

## Interfaz con el Audio Core

`audio_proc` tiene un maestro Avalon-MM (`m0`, 32 bits, con `waitrequest`) conectado solo al esclavo del Audio Core, configurado en modo memory-mapped con muestras de 32 bits a 48 kHz:

1. Lee `FIFOSPACE` (`0x4`) y toma como crédito el mínimo entre `WSLC` (`[31:24]`) y `WSRC` (`[23:16]`). Si es 0, espera 256 ciclos antes de volver a leer.
2. Por cada muestra escribe `LEFTDATA` (`0x8`) y luego `RIGHTDATA` (`0xC`) con la muestra de 16 bits en `[31:16]`.
3. Un par iniciado siempre se completa, aunque llegue `FLUSH`, para no desalinear los canales.

El Nios V también puede escribir directamente en el Audio Core; el programa de prueba lo usa para aislar fallas del codec de las de `audio_proc`.
