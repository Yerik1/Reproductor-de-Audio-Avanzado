/* Reproductor del HPS (plano de datos): carga el catalogo de la SD, atiende los comandos
 * del buzon y alimenta audio_proc a traves del puente LW. */
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "audio_proc_regs.h"
#include "catalog.h"
#include "hps_map.h"
#include "mailbox.h"
#include "player.h"

#define POLL_NS 2000000L

static volatile sig_atomic_t g_stop;

static void on_signal(int sig)
{
    (void)sig;
    g_stop = 1;
}

static volatile uint32_t *g_ap;

#define AP(off) g_ap[(off) / 4u]

static uint32_t hw_space(void *c) { (void)c; return AP(AP_REG_FIFO_SPACE); }
static void hw_ctrl(void *c, uint32_t v) { (void)c; AP(AP_REG_CTRL) = v; }
static void hw_track(void *c, uint32_t n) { (void)c; AP(AP_REG_TRACK) = n; }

static int hw_idle(void *c)
{
    uint32_t s = AP(AP_REG_STATUS);

    (void)c;
    return (s & AP_STATUS_EMPTY) && !(s & AP_STATUS_BUSY);
}

static void hw_write(void *c, const uint32_t *w, uint32_t n)
{
    (void)c;
    while (n--)
        AP(AP_REG_DATA) = *w++;
}

static void usage(const char *prog)
{
    fprintf(stderr, "uso: %s [-d directorio_canciones] [-f]\n"
                    "  -f  volumen fijo (sin potenciometro)\n", prog);
}

int main(int argc, char **argv)
{
    static catalog_t cat;
    static player_t pl;
    const char *dir = "/root/musica";
    uint32_t flags = 0, last_changes = 0xFFFFFFFFu, cmd;
    struct timespec ts = {0, POLL_NS};
    volatile mailbox_t *mb;
    mbx_status_t st;
    audio_out_t out = {NULL, hw_space, hw_idle, hw_write, hw_ctrl, hw_track};
    void *lw;
    int fd, opt;

    while ((opt = getopt(argc, argv, "d:f")) != -1) {
        if (opt == 'd') {
            dir = optarg;
        } else if (opt == 'f') {
            flags |= MBX_FLAG_FIXED_VOL;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return 1;
    }
    lw = mmap(NULL, LW_BRIDGE_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, LW_BRIDGE_BASE);
    if (lw == MAP_FAILED) {
        perror("mmap puente LW");
        close(fd);
        return 1;
    }
    g_ap = (volatile uint32_t *)((uint8_t *)lw + AUDIO_PROC_OFFSET);
    mb   = (volatile mailbox_t *)((uint8_t *)lw + MAILBOX_OFFSET);

    if (AP(AP_REG_ID) != AP_ID_VALUE) {
        fprintf(stderr, "audio_proc no responde: ID=0x%08X (esperado 0x%08X)\n",
                (unsigned)AP(AP_REG_ID), AP_ID_VALUE);
        munmap(lw, LW_BRIDGE_SPAN);
        close(fd);
        return 1;
    }

    if (catalog_load(&cat, dir) < 0)
        fprintf(stderr, "no se pudo abrir %s\n", dir);
    printf("catalogo %s: %d pistas validas, %d descartadas\n", dir, cat.count, cat.rejected);

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    player_init(&pl, &cat, &out);
    mbx_hps_init(mb, flags);

    while (!g_stop) {
        mb->heartbeat = mb->heartbeat + 1;
        while (mbx_pop_cmd(mb, &cmd))
            player_command(&pl, cmd);
        player_poll(&pl);
        if (pl.changes != last_changes) {
            last_changes = pl.changes;
            player_status(&pl, &st);
            mbx_publish(mb, &st);
            printf("[%s] pista %u/%u: %s - %s\n", mbx_state_name(st.state),
                   (unsigned)st.track + 1, (unsigned)st.total, st.title, st.artist);
            fflush(stdout);
        }
        nanosleep(&ts, NULL);
    }

    player_close(&pl);
    mb->magic = 0;
    munmap(lw, LW_BRIDGE_SPAN);
    close(fd);
    return 0;
}
