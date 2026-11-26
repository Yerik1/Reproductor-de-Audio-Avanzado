#ifndef AUDIO_PROC_REGS_H
#define AUDIO_PROC_REGS_H

/* Contrato HW/SW del modulo audio_proc (docs/mapa-registros.md). Offsets en bytes
 * respecto a la base del componente; accesos de 32 bits. */

#define AP_ID_VALUE        0x41554450u   /* "AUDP" */
#define AP_FS_HZ           48000u

#define AP_REG_ID          0x00u
#define AP_REG_CTRL        0x04u
#define AP_REG_STATUS      0x08u
#define AP_REG_FIFO_SPACE  0x0Cu
#define AP_REG_DATA        0x10u
#define AP_REG_VOLUME      0x14u
#define AP_REG_PLAYED      0x18u
#define AP_REG_TIME        0x1Cu
#define AP_REG_TRACK       0x20u
#define AP_REG_UNDERRUN    0x24u
#define AP_REG_COEF_ADDR   0x28u
#define AP_REG_COEF_DATA   0x2Cu
#define AP_REG_OVERFLOW    0x30u
#define AP_REG_FIFO_DEPTH  0x34u

#define AP_CTRL_RUN        (1u << 0)
#define AP_CTRL_FLUSH      (1u << 1)
#define AP_CTRL_TIME_CLR   (1u << 2)
#define AP_CTRL_SEL_SRC    (1u << 3)
#define AP_CTRL_FILTER(n)  (((unsigned)(n) & 3u) << 4)
#define AP_CTRL_HEX_EN     (1u << 8)

#define AP_STATUS_FILTER(s)  ((s) & 3u)
#define AP_STATUS_EMPTY      (1u << 2)
#define AP_STATUS_FULL       (1u << 3)
#define AP_STATUS_RUN        (1u << 4)
#define AP_STATUS_BUSY       (1u << 5)
#define AP_STATUS_SW(s)      (((s) >> 8) & 3u)

#define AP_FILTER_BYPASS   0u
#define AP_FILTER_LPF      1u
#define AP_FILTER_HPF      2u
#define AP_FILTER_BPF      3u

#define AP_VOL_UNITY       0x8000u
#define AP_COEF_ADDR(bank, tap)  ((((unsigned)(bank) & 3u) << 7) | ((unsigned)(tap) & 0x7Fu))

#endif
