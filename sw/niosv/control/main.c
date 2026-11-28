/* Plano de control en el Nios V/m (bare metal).
 *   Botones por IRQ -> comandos al HPS por el buzon:
 *     KEY3 anterior   KEY2 stop   KEY1 reproducir/pausa   KEY0 siguiente
 *   Volumen: ADC CH0 -> VOLUME de audio_proc (fijo si el HPS lo indica en el buzon).
 *   Interfaz: estado, pista N/total, metadatos, filtro activo y tiempo por la JTAG UART.
 *   Latencia de cada boton: desde la ISR hasta que el HPS consume el comando. */
#include <stdint.h>
#include <stdio.h>

#include "audio_proc_regs.h"
#include "mailbox.h"
#include "sys/alt_irq.h"
#include "system.h"

#define REG(base, off)    (*(volatile uint32_t *)((uintptr_t)(base) + (off)))
#define AP(off)           REG(AUDIO_PROC_0_BASE, off)
#define KEY_INTMASK       REG(KEY_PIO_BASE, 0x8)
#define KEY_EDGECAP       REG(KEY_PIO_BASE, 0xC)
#define ADC_CH0           REG(ADC_BASE, 0x0)
#define ADC_AUTO_UPDATE   REG(ADC_BASE, 0x4)

#ifndef CPU_TIMER_SW_AGENT_BASE
#define CPU_TIMER_SW_AGENT_BASE 0xFF202100u
#endif
#define MTIME_LO          REG(CPU_TIMER_SW_AGENT_BASE, 0x0)
#define CLK_HZ            50000000u

static const uint32_t key_cmd[4] = {MBX_CMD_NEXT, MBX_CMD_PLAY_PAUSE, MBX_CMD_STOP, MBX_CMD_PREV};
static const char *const key_name[4] = {"siguiente", "reproducir/pausa", "stop", "anterior"};
static const char *const filter_name[4] = {
    "Bypass", "Pasa-bajos 1 kHz", "Pasa-altos 2 kHz", "Pasa-banda 300-3400 Hz"
};

static volatile uint32_t key_count[4];
static volatile uint32_t key_tick[4];

static void key_isr(void *context)
{
    uint32_t edges = KEY_EDGECAP;
    uint32_t now = MTIME_LO;
    int i;

    (void)context;
    KEY_EDGECAP = edges;
    for (i = 0; i < 4; i++) {
        if (edges & (1u << i)) {
            key_count[i]++;
            key_tick[i] = now;
        }
    }
}

static uint32_t volume_from_adc(uint32_t raw)
{
    uint32_t v = raw & 0xFFFu;
    uint32_t g = (v * v) >> 9;

    return g > AP_VOL_UNITY ? AP_VOL_UNITY : g;
}

static void show_status(const mbx_status_t *s, uint32_t filter)
{
    uint32_t d = s->duration_ms / 1000u;

    printf("\n[%s] Pista %u/%u\n", mbx_state_name(s->state), (unsigned)s->track + 1, (unsigned)s->total);
    printf("  Titulo : %s\n  Artista: %s\n  Album  : %s\n", s->title, s->artist, s->album);
    printf("  Duracion %u:%02u | %u Hz, %u canal(es) | Filtro: %s\n",
           (unsigned)(d / 60u), (unsigned)(d % 60u), (unsigned)s->sample_rate,
           (unsigned)s->channels, filter_name[filter & 3u]);
}

int main(void)
{
    volatile mailbox_t *mb = (volatile mailbox_t *)MAILBOX_BASE;
    uint32_t seen[4] = {0, 0, 0, 0};
    uint32_t pend_idx = 0, pend_tick = 0, last_seq = 0xFFFFFFFFu, last_filter = 0xFFu;
    uint32_t last_time = 0xFFFFFFFFu, last_beat = 0, beat_tick = 0;
    int pend = -1, ready = 0, hps_alive = 1, k;
    mbx_status_t st;

    ADC_AUTO_UPDATE = 1;
    KEY_EDGECAP = 0xF;
    KEY_INTMASK = 0xF;
    if (alt_ic_isr_register(KEY_PIO_IRQ_INTERRUPT_CONTROLLER_ID, KEY_PIO_IRQ, key_isr, NULL, NULL) != 0)
        printf("ERROR: no se pudo registrar la ISR de KEY\n");

    printf("\n=== Reproductor: control Nios V ===\n");
    printf("KEY3 anterior | KEY2 stop | KEY1 reproducir/pausa | KEY0 siguiente\n");
    printf("Esperando al HPS...\n");

    for (;;) {
        uint32_t now = MTIME_LO;
        uint32_t seq, filter, t;

        if (!ready && mbx_ready(mb)) {
            ready = 1;
            last_beat = mb->heartbeat;
            beat_tick = now;
            printf("HPS listo%s\n", (mb->flags & MBX_FLAG_FIXED_VOL) ? " (volumen fijo)" : "");
        }

        for (k = 0; k < 4; k++) {
            if (key_count[k] == seen[k])
                continue;
            seen[k] = key_count[k];
            if (!ready) {
                printf("KEY%d ignorado: el HPS no esta listo\n", k);
                continue;
            }
            if (mbx_push_cmd(mb, key_cmd[k])) {
                pend      = k;
                pend_idx  = mb->cmd_head;
                pend_tick = key_tick[k];
            }
        }
        if (pend >= 0 && (int32_t)(mb->cmd_tail - pend_idx) >= 0) {
            uint32_t us = (MTIME_LO - pend_tick) / (CLK_HZ / 1000000u);

            printf("KEY%d %s: aplicado por el HPS en %u.%03u ms\n", pend, key_name[pend],
                   (unsigned)(us / 1000u), (unsigned)(us % 1000u));
            pend = -1;
        }

        AP(AP_REG_VOLUME) = (ready && !(mb->flags & MBX_FLAG_FIXED_VOL)) ? volume_from_adc(ADC_CH0)
                                                                          : AP_VOL_UNITY;
        if (!ready)
            continue;

        if (mb->heartbeat != last_beat) {
            last_beat = mb->heartbeat;
            beat_tick = now;
            if (!hps_alive)
                printf("HPS responde de nuevo\n");
            hps_alive = 1;
        } else if (hps_alive && now - beat_tick > CLK_HZ) {
            hps_alive = 0;
            printf("HPS sin respuesta\n");
        }

        filter = AP_STATUS_FILTER(AP(AP_REG_STATUS));
        if (mbx_read_status(mb, &st, &seq) && (seq != last_seq || filter != last_filter)) {
            last_seq    = seq;
            last_filter = filter;
            show_status(&st, filter);
        }
        t = AP(AP_REG_TIME);
        if (t != last_time) {
            last_time = t;
            printf("\r  Tiempo %X%X:%X%X ", (unsigned)(t >> 12) & 0xFu, (unsigned)(t >> 8) & 0xFu,
                   (unsigned)(t >> 4) & 0xFu, (unsigned)t & 0xFu);
        }
    }
    return 0;
}
