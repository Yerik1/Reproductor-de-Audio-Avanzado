/* Prueba de arranque en la placa: audio_proc, Audio Core, botones por IRQ y ADC.
 *
 * Genera un diente de sierra de 220 Hz (rico en armonicos, para que los filtros se
 * distingan) y lo envia por audio_proc o directamente al Audio Core.
 *   KEY0 reproducir/pausa   KEY1 siguiente pista   KEY2 stop
 *   KEY3 modo: audio_proc con volumen fijo -> audio_proc con volumen del ADC CH0 -> directo
 *   SW1..SW0 filtro (en hardware)
 */
#include <stdint.h>
#include <stdio.h>

#include "audio_proc_regs.h"
#include "sys/alt_irq.h"
#include "system.h"

#define REG(base, off)    (*(volatile uint32_t *)((uintptr_t)(base) + (off)))

#define KEY_INTMASK       REG(KEY_PIO_BASE, 0x8)
#define KEY_EDGECAP       REG(KEY_PIO_BASE, 0xC)

#define AC_FIFOSPACE      REG(AUDIO_BASE, 0x4)
#define AC_LEFT           REG(AUDIO_BASE, 0x8)
#define AC_RIGHT          REG(AUDIO_BASE, 0xC)

#define ADC_CH0           REG(ADC_BASE, 0x0)
#define ADC_AUTO_UPDATE   REG(ADC_BASE, 0x4)

#define AP(off)           REG(AUDIO_PROC_0_BASE, off)

#define SAW_INC           19685266u   /* 220 Hz con acumulador de fase de 32 bits a 48 kHz */

enum { MODE_FIXED_VOL, MODE_ADC_VOL, MODE_DIRECT, MODE_COUNT };

static const char *const mode_name[MODE_COUNT] = {
    "audio_proc, volumen fijo",
    "audio_proc, volumen del ADC CH0",
    "directa al Audio Core",
};

static volatile uint32_t key_count[4];

static void key_isr(void *context)
{
    uint32_t edges = KEY_EDGECAP;
    int i;

    (void)context;
    KEY_EDGECAP = edges;
    for (i = 0; i < 4; i++)
        if (edges & (1u << i))
            key_count[i]++;
}

static int16_t next_sample(uint32_t *phase)
{
    int16_t s = (int16_t)(((int32_t)(*phase >> 16) - 32768) / 4);

    *phase += SAW_INC;
    return s;
}

static uint32_t volume_from_adc(uint32_t raw)
{
    uint32_t v = raw & 0xFFFu;
    uint32_t g = (v * v) >> 9;

    return g > AP_VOL_UNITY ? AP_VOL_UNITY : g;
}

int main(void)
{
    uint32_t seen[4] = {0, 0, 0, 0};
    uint32_t phase = 0, ctrl, last_time = 0xFFFFFFFFu, last_status = 0xFFFFFFFFu;
    int playing = 1, mode = MODE_FIXED_VOL, direct = 0, track = 1, k;

    printf("\n=== Prueba de arranque: audio_proc + Audio Core + KEY + ADC ===\n");
    printf("audio_proc ID=0x%08X (esperado 0x%08X), FIFO_DEPTH=%u\n",
           (unsigned)AP(AP_REG_ID), AP_ID_VALUE, (unsigned)AP(AP_REG_FIFO_DEPTH));

    AP(AP_REG_CTRL)  = AP_CTRL_HEX_EN | AP_CTRL_FLUSH | AP_CTRL_TIME_CLR;
    AP(AP_REG_TRACK) = (uint32_t)track;
    ADC_AUTO_UPDATE  = 1;

    KEY_EDGECAP = 0xF;
    KEY_INTMASK = 0xF;
    if (alt_ic_isr_register(KEY_PIO_IRQ_INTERRUPT_CONTROLLER_ID, KEY_PIO_IRQ, key_isr, NULL, NULL) != 0)
        printf("ERROR: no se pudo registrar la ISR de KEY\n");

    ctrl = AP_CTRL_HEX_EN | AP_CTRL_RUN;
    AP(AP_REG_CTRL) = ctrl;
    printf("KEY0 play/pausa | KEY1 siguiente | KEY2 stop | KEY3 modo | SW1..0 filtro\n");
    printf("modo: %s\n", mode_name[mode]);

    for (;;) {
        for (k = 0; k < 4; k++) {
            if (key_count[k] == seen[k])
                continue;
            seen[k] = key_count[k];
            switch (k) {
            case 0:
                playing = !playing;
                break;
            case 1:
                track = track % 99 + 1;
                AP(AP_REG_TRACK) = (uint32_t)track;
                AP(AP_REG_CTRL) = (ctrl & ~AP_CTRL_RUN) | AP_CTRL_FLUSH | AP_CTRL_TIME_CLR;
                playing = 1;
                break;
            case 2:
                playing = 0;
                AP(AP_REG_CTRL) = AP_CTRL_HEX_EN | AP_CTRL_FLUSH | AP_CTRL_TIME_CLR;
                break;
            default:
                mode   = (mode + 1) % MODE_COUNT;
                direct = (mode == MODE_DIRECT);
                AP(AP_REG_CTRL) = AP_CTRL_HEX_EN | AP_CTRL_FLUSH;
                break;
            }
            ctrl = AP_CTRL_HEX_EN | ((playing && !direct) ? AP_CTRL_RUN : 0u);
            AP(AP_REG_CTRL) = ctrl;
            printf("KEY%d (%u) -> %s, pista %d, modo: %s\n", k, (unsigned)seen[k],
                   playing ? "reproduciendo" : (k == 2 ? "detenido" : "pausado"), track,
                   mode_name[mode]);
        }

        AP(AP_REG_VOLUME) = (mode == MODE_ADC_VOL) ? volume_from_adc(ADC_CH0) : AP_VOL_UNITY;

        if (playing && !direct) {
            uint32_t space = AP(AP_REG_FIFO_SPACE);

            while (space--) {
                int16_t s = next_sample(&phase);

                AP(AP_REG_DATA) = ((uint32_t)(uint16_t)s << 16) | (uint16_t)s;
            }
        } else if (playing && direct) {
            uint32_t fs = AC_FIFOSPACE;
            uint32_t wl = fs >> 24, wr = (fs >> 16) & 0xFFu;
            uint32_t n = wl < wr ? wl : wr;

            while (n--) {
                uint32_t s = (uint32_t)(uint16_t)next_sample(&phase) << 16;

                AC_LEFT  = s;
                AC_RIGHT = s;
            }
        }

        if (AP(AP_REG_TIME) != last_time || (AP(AP_REG_STATUS) & 0x303u) != last_status) {
            uint32_t t = AP(AP_REG_TIME);

            last_time   = t;
            last_status = AP(AP_REG_STATUS) & 0x303u;
            printf("tiempo %X%X:%X%X | filtro %u (SW=%u) | volumen 0x%04X (ADC %u) | underrun %u\n",
                   (unsigned)(t >> 12) & 0xF, (unsigned)(t >> 8) & 0xF,
                   (unsigned)(t >> 4) & 0xF, (unsigned)t & 0xF,
                   (unsigned)AP_STATUS_FILTER(last_status), (unsigned)AP_STATUS_SW(last_status),
                   (unsigned)AP(AP_REG_VOLUME), (unsigned)(ADC_CH0 & 0xFFFu),
                   (unsigned)AP(AP_REG_UNDERRUN));
        }
    }
    return 0;
}
