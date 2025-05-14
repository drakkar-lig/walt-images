#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <net/if_arp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#define TUN_DEV_MAJOR       10
#define TUN_DEV_MINOR       200
#define ETHERNET_MAX_SIZE   1514
#define BUFFER_SIZE_BITS    16
#define BUFFER_SIZE         (1<<BUFFER_SIZE_BITS)
#define LENGTH_SIZE         2         /* size to encode packet length */
#define PACKET_BUFFER_SIZE  (LENGTH_SIZE + ETHERNET_MAX_SIZE)

//#define DEBUG
#ifdef DEBUG
#define debug_printf(...) fprintf(stderr, __VA_ARGS__)
#else
#define debug_printf(...)   /* do nothing */
#endif

#define MIN(i, j) (((i) > (j))?(j):(i))
#define MAX(i, j) (((i) > (j))?(i):(j))

/* note: ternary op in this macro is just here to avoid warn unused result */
#define write_stderr(msg) (void)(write(2, msg, strlen(msg))?1:0)


static inline int read_fd_once(int fd, unsigned char *start, ssize_t max_size,
                                 ssize_t *out_length, char *fd_label) {
    ssize_t sres;
    sres = read(fd, start, max_size);
    if (sres < 1) {
        if (fd_label) {
            if (sres == 0) {
                write_stderr("short read on ");
                write_stderr(fd_label);
                write_stderr("\n");
            }
            else {
                write_stderr(fd_label);
                write_stderr(" read error\n");
            }
        }
        return -1;
    }
    start += sres;
    if (out_length != NULL) {
        *out_length = sres;
    }
    return 0;
}


static inline int write_fd(int fd, unsigned char *start, unsigned char *end,
                            char *fd_label) {
    ssize_t sres;
    while (start < end) {
        sres = write(fd, start, end - start);
        if (fd_label) {
            if (sres == 0) {
                write_stderr("short write on ");
                write_stderr(fd_label);
                write_stderr("\n");
            }
            if (sres == -1) {
                write_stderr(fd_label);
                write_stderr(" write error\n");
                return -1;
            }
        }
        start += sres;
    }
    return 0;
}


static void *malloc_or_abort(size_t size) {
    void *res = malloc(size);
    if (res == NULL) {
        perror("malloc");
        exit(1);
    }
    return res;
}


typedef struct {
    int size;
    int level;
    unsigned char *buf;
    unsigned char *buf_end;
    unsigned char *fill_pos;
    unsigned char *flush_pos;
} circular_buffer_t;


static int cbuf_setup(circular_buffer_t *cbuf, int size) {
    cbuf->size = size;
    cbuf->level = 0;
    cbuf->buf = malloc_or_abort(sizeof(unsigned char) * size);
    cbuf->buf_end = cbuf->buf + size;
    cbuf->fill_pos = cbuf->buf;
    cbuf->flush_pos = cbuf->buf;
    return 0;
}


static void cbuf_release(circular_buffer_t *cbuf) {
    free(cbuf->buf);
}


static int cbuf_fill(circular_buffer_t *cbuf, int fd_in) {
    int read_size, iov_idx = 0;
    struct iovec iov[2];
    if (cbuf->fill_pos < cbuf->flush_pos) {
        iov[iov_idx].iov_base = cbuf->fill_pos;
        iov[iov_idx].iov_len = cbuf->flush_pos - cbuf->fill_pos;
        iov_idx += 1;
    }
    else {
        if (cbuf->fill_pos < cbuf->buf_end) {
            iov[iov_idx].iov_base = cbuf->fill_pos;
            iov[iov_idx].iov_len = cbuf->buf_end - cbuf->fill_pos;
            iov_idx += 1;
        }
        if (cbuf->buf < cbuf->flush_pos) {
            iov[iov_idx].iov_base = cbuf->buf;
            iov[iov_idx].iov_len = cbuf->flush_pos - cbuf->buf;
            iov_idx += 1;
        }
    }
    read_size = readv(fd_in, iov, iov_idx);
    if (read_size > 0) {
        cbuf->fill_pos += read_size;
        if (cbuf->fill_pos >= cbuf->buf_end) {
            cbuf->fill_pos -= cbuf->size;
        }
        cbuf->level += read_size;
        return 0;
    }
    if (read_size == 0) {
        fprintf(stderr, "Empty read.\n");
    }
    return -1;
}


static int cbuf_flush(circular_buffer_t *cbuf, int size, int fd_out) {
    int write_size, iov_idx = 0;
    struct iovec iov[2];
    if (cbuf->fill_pos > cbuf->flush_pos) {
        iov[iov_idx].iov_base = cbuf->flush_pos;
        iov[iov_idx].iov_len = size;
        iov_idx += 1;
    }
    else {
        iov[iov_idx].iov_base = cbuf->flush_pos;
        if (size <= cbuf->buf_end - cbuf->flush_pos) {
            iov[iov_idx].iov_len = size;
        }
        else {
            iov[iov_idx].iov_len = cbuf->buf_end - cbuf->flush_pos;
        }
        size -= iov[iov_idx].iov_len;
        iov_idx += 1;
        if (size > 0) {
            iov[iov_idx].iov_base = cbuf->buf;
            iov[iov_idx].iov_len = size;
            iov_idx += 1;
        }
    }
    write_size = writev(fd_out, iov, iov_idx);
    if (write_size == -1) {
        return -1;
    }
    cbuf->flush_pos += write_size;
    if (cbuf->flush_pos >= cbuf->buf_end) {
        cbuf->flush_pos -= cbuf->size;
    }
    cbuf->level -= write_size;
    /* this is not necessary but in case of unnecessarily big buffers, it allows to
     * use the start of the buffer in most cases, thus it improves cache locality */
    if (cbuf->level == 0) {
        cbuf->fill_pos = cbuf->buf;
        cbuf->flush_pos = cbuf->buf;
    }
    return 0;
}


static void cbuf_pass(circular_buffer_t *cbuf, int shift) {
    cbuf->flush_pos += shift;
    if (cbuf->flush_pos >= cbuf->buf_end) {
        cbuf->flush_pos -= cbuf->size;
    }
    cbuf->level -= shift;
}


static int cbuf_peek_big_endian_short(circular_buffer_t *cbuf) {
    int i1 = *(cbuf->flush_pos), i0;
    if (cbuf->flush_pos + 1 == cbuf->buf_end) {
        i0 = *(cbuf->buf);
    }
    else {
        i0 = *(cbuf->flush_pos + 1);
    }
    return (i1 << 8) + i0;
}


/* packet length is encoded as 2 bytes, big endian */
static inline ssize_t compute_packet_len(unsigned char *len_pos) {
    return ((*len_pos) << 8) + *(len_pos+1);
}


static inline void store_packet_len(unsigned char *len_pos, ssize_t sres) {
    len_pos[0] = (unsigned char)(sres >> 8);
    len_pos[1] = (unsigned char)(sres & 0xff);
}


static void cmd_tap_transfer_loop(int cmd_read_fd, int cmd_write_fd, int tap_fd) {
    unsigned char *buf_tap_to_cmd, *pos_tap_to_cmd;
    int res, max_fd, should_continue = 1;
    ssize_t sres, packet_len;
    fd_set fds, init_fds;
    circular_buffer_t buf_cmd_to_tap;

    /* when reading on tap, 1 read() means 1 packet */
    buf_tap_to_cmd = malloc_or_abort(PACKET_BUFFER_SIZE * sizeof(unsigned char));
    pos_tap_to_cmd = buf_tap_to_cmd + LENGTH_SIZE;
    /* when reading on cmd stdout, we are reading a continuous flow */
    cbuf_setup(&buf_cmd_to_tap, BUFFER_SIZE);

    FD_ZERO(&init_fds);
    FD_SET(cmd_read_fd, &init_fds);
    FD_SET(tap_fd, &init_fds);
    max_fd = MAX(cmd_read_fd, tap_fd) + 1;

    /* start select loop
       we will:
       * transfer packets coming from the tap interface to cmd stdin
       * transfer packets coming from cmd stdout to the tap interface
    */
    while (should_continue) {
        fds = init_fds;
        res = select(max_fd, &fds, NULL, NULL, NULL);
        if (res < 1) {
            perror("select error");
            break;
        }
        if (FD_ISSET(tap_fd, &fds)) {
            /* read new packet on tap */
            res = read_fd_once(tap_fd, pos_tap_to_cmd, ETHERNET_MAX_SIZE, &sres,
                             "tap");
            if (res == -1) {
                break;
            }
            /* prefix packet length as 2 bytes, big endian */
            store_packet_len(buf_tap_to_cmd, sres);
            /* write packet to cmd stdin */
            res = write_fd(cmd_write_fd, buf_tap_to_cmd, pos_tap_to_cmd + sres,
                              "cmd channel");
            if (res == -1) {
                break;
            }
        }
        else {
            /* we have to read network packets from cmd stdout, but these come as a
             * continuous data flow, and we have to write them on a tap interface,
             * with one write() per packet.
             * for efficiency, we read cmd stdout data into a buffer, which means
             * we read several packets at once, and reads might not be on packet
             * boundaries. */
            res = cbuf_fill(&buf_cmd_to_tap, cmd_read_fd);
            if (res == -1) {
                debug_printf("failure while reading cmd channel: %s\n", strerror(errno));
                break;
            }

            /* write all complete packets to tap */
            while (buf_cmd_to_tap.level >= LENGTH_SIZE) {

                packet_len = cbuf_peek_big_endian_short(&buf_cmd_to_tap);
                if (buf_cmd_to_tap.level < LENGTH_SIZE + packet_len) {
                    break;  // not enough data
                }

                /* pass length field */
                cbuf_pass(&buf_cmd_to_tap, LENGTH_SIZE);

                /* write packet on tap */
                res = cbuf_flush(&buf_cmd_to_tap, packet_len, tap_fd);
                if (res == -1) {
                    should_continue = 0;
                    break;
                }
            }
        }
    }
    free(buf_tap_to_cmd);
    cbuf_release(&buf_cmd_to_tap);
}


static void ensure_no_error(int res, const char *err_msg) {
    if (res == -1) {
        perror(err_msg);
        exit(1);
    }
}


static void set_stdin_stdout(int fd_stdin, int fd_stdout) {
    assert(dup2(fd_stdin, 0) != -1);
    assert(dup2(fd_stdout, 1) != -1);
    close(fd_stdin);
    close(fd_stdout);
}


static void spawn_cmd(int tap_fd, char **argv) {
    int res, pipe_cmd_stdin[2], pipe_cmd_stdout[2];
    pid_t pid;

    // reserve fd 0 and 1 (pipe() should not use them)
    assert(tap_fd != 0 && tap_fd != 1);
    assert(dup2(tap_fd, 0) != -1);
    assert(dup2(tap_fd, 1) != -1);
    // create pipes to communicate with future cmd
    assert(pipe(pipe_cmd_stdin) != -1);
    assert(pipe(pipe_cmd_stdout) != -1);
    // un-reserve fd 0 and 1
    close(0);
    close(1);
    // fork
    pid = fork();
    if (pid == 0) {
        // child
        close(tap_fd);
        close(pipe_cmd_stdin[1]);
        close(pipe_cmd_stdout[0]);
        set_stdin_stdout(pipe_cmd_stdin[0],
                         pipe_cmd_stdout[1]);
        res = execvp(argv[0], argv);
        // if it succeeds, execvp() should not return anyway
        ensure_no_error(res, "Trying to run command");
    }
    else {
        // parent
        close(pipe_cmd_stdin[0]);
        close(pipe_cmd_stdout[1]);
        cmd_tap_transfer_loop(
                pipe_cmd_stdout[0],
                pipe_cmd_stdin[1],
                tap_fd);
        close(pipe_cmd_stdin[1]);
        close(pipe_cmd_stdout[0]);
    }
}


static int ignore_sigpipe() {
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
        return -1;
    }
    return 0;
}


static int parse_mac(char *mac, uint8_t *mac_bytes) {
    int res;

    if (strlen(mac) != 17) {
        return 0;  // failed
    }
    res = sscanf(optarg, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
                 &mac_bytes[0],
                 &mac_bytes[1],
                 &mac_bytes[2],
                 &mac_bytes[3],
                 &mac_bytes[4],
                 &mac_bytes[5]);
    return (res == 6);
}


int main(int argc, char **argv) {
    struct ifreq ifr;
    struct stat file_stat;
    int res, tap_fd, conf_fd, c, mac_specified, foreground, wrong_usage;
    uint8_t mac_bytes[6];

    /* parse options */
    foreground = 0;     // default
    mac_specified = 0;  // default
    wrong_usage = 0;

    while (1) {
        static struct option long_options[] = {
            { "foreground",  no_argument,       0,  'f' },
            { "mac",         required_argument, 0,  'm' },
            { 0,             0,                 0,   0  },
        };

        c = getopt_long(argc, argv, "fm:", long_options, NULL);
        if (c == -1)
            break;

        switch (c) {

            case 'f':
                foreground = 1;
                break;

            case 'm':
                if (parse_mac(optarg, mac_bytes)) {
                    mac_specified = 1;
                }
                else {
                    fprintf(stderr, "%s\n",
                        "wrong mac value, expected '<hh>:<hh>:<hh>:<hh>:<hh>:<hh>'.");
                    exit(1);
                }
                break;

            case '?':
                fprintf(stderr, "%s\n", "Unknown option.");
                wrong_usage = 1;
                break;
        }
    }

    if (optind == argc) {
        fprintf(stderr, "%s\n", "No command specified.");
        wrong_usage = 1;
    }

    if (wrong_usage) {
        fprintf(stderr,
            "Usage: %s [-f|--foreground] [-m|--mac <mac-address>] <cmd-args...>\n",
            argv[0]);
        exit(1);
    }

    // create /dev/net/tun device file if missing
    res = stat("/dev/net", &file_stat);
    if ((res == -1) && (errno == ENOENT)) {
        res = mkdir("/dev/net", 0755);
    }
    if (res == 0) {
        res = stat("/dev/net/tun", &file_stat);
        if ((res == -1) && (errno == ENOENT)) {
            res = mknod("/dev/net/tun", S_IFCHR | 0666,
                        makedev(TUN_DEV_MAJOR, TUN_DEV_MINOR));
        }
    }
    ensure_no_error(res, "Creation of /dev/net/tun device file");
    // open /dev/net/tun and get fd of the new interface
    tap_fd = open("/dev/net/tun", O_RDWR);
    ensure_no_error(tap_fd, "Opening /dev/net/tun");
    // tell it we want a TUN device and no packet headers
    memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
    strncpy(ifr.ifr_name, "walt-vpn", IFNAMSIZ);
    res = ioctl(tap_fd, TUNSETIFF, &ifr);
    ensure_no_error(res, "Creating walt-vpn TAP device");
    // set address mac and set it up
    conf_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (mac_specified) {
        memcpy(ifr.ifr_hwaddr.sa_data, mac_bytes, 6*sizeof(uint8_t));
        ifr.ifr_hwaddr.sa_family = ARPHRD_ETHER;
        res = ioctl(conf_fd, SIOCSIFHWADDR, &ifr);
        ensure_no_error(res, "Setting mac address of TAP device");
    }
    res = ioctl(conf_fd, SIOCGIFFLAGS, &ifr);       // get
    if (res == 0) {
        ifr.ifr_flags |= IFF_UP | IFF_RUNNING;      // add flags
        res = ioctl(conf_fd, SIOCSIFFLAGS, &ifr);   // set
    }
    ensure_no_error(res, "Setting TAP device up");
    close(conf_fd);
    // avoid SIGPIPE signals (get EPIPE on write() instead)
    res = ignore_sigpipe();
    ensure_no_error(res, "Trying to ignore SIGPIPE");
    if (!foreground) {
        // daemonize, close stdin/stdout but leave stderr open
        res = daemon(0, 1);
        close(0);
        close(1);
        ensure_no_error(res, "Going to background");
    }
    // run command loop
    spawn_cmd(tap_fd, argv + optind);
}
