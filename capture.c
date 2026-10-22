/* Capture packets on a device and print them in hex.
 * Optional -Q selects capture direction like tcpdump.
 */

#include <pcap.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>

static const char *program_name;
static pcap_t *pd;

struct capture_args {
  char *device;
  pcap_direction_t direction;
  int direction_set;
};

static void
usage(void)
{
  fprintf(stderr, "Usage: %s -i <device> [-Q in|out|inout]\n", program_name);
}

static void
error(const char *fmt, ...)
{
  va_list ap;

  fprintf(stderr, "%s: ", program_name);
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  if (*fmt && fmt[strlen(fmt) - 1] != '\n')
    fputc('\n', stderr);
  exit(1);
}

static int
parse_args(int argc, char **argv, struct capture_args *args)
{
  int op;

  if ((program_name = strrchr(argv[0], '/')) != NULL)
    program_name++;
  else
    program_name = argv[0];

  memset(args, 0, sizeof(*args));

  opterr = 0;
  while ((op = getopt(argc, argv, "i:Q:")) != -1) {
    switch (op) {

    case 'i':
      args->device = optarg;
      break;

    case 'Q':
      if (strcmp(optarg, "in") == 0)
        args->direction = PCAP_D_IN;
      else if (strcmp(optarg, "out") == 0)
        args->direction = PCAP_D_OUT;
      else if (strcmp(optarg, "inout") == 0)
        args->direction = PCAP_D_INOUT;
      else {
        fprintf(stderr, "%s: direction must be in, out, or inout\n", program_name);
        return -1;
      }
      args->direction_set = 1;
      break;

    default:
      usage();
      return -1;
    }
  }

  if (args->device == NULL || optind != argc) {
    usage();
    return -1;
  }

  return 0;
}


static void
sigint_handler(int signum)
{
  (void)signum;
  pcap_breakloop(pd);
}

static void
print_packet(u_char *device, const struct pcap_pkthdr *h, const u_char *sp)
{
  printf("%s caplen %u len %u: ", device, h->caplen, h->len);
  for (unsigned int i = 0; i < h->caplen; i++)
    printf("%02x", sp[i]);
  printf("\n");
  fflush(stdout);
}

int
main(int argc, char **argv)
{
  struct capture_args args;
  char ebuf[PCAP_ERRBUF_SIZE];
  int status;
  struct sigaction action;

  if (parse_args(argc, argv, &args) != 0)
    return 1;

  pd = pcap_create(args.device, ebuf);
  if (pd == NULL)
    error("%s", ebuf);

  status = pcap_set_snaplen(pd, 65535);
  if (status != 0)
    error("%s: pcap_set_snaplen failed: %s", args.device, pcap_statustostr(status));
 
  status = pcap_set_timeout(pd, 100);
  if (status != 0)
    error("%s: pcap_set_timeout failed: %s", args.device, pcap_statustostr(status));

  status = pcap_set_immediate_mode(pd, 1);
  if (status != 0)
    error("%s: pcap_set_immediate_mode failed: %s", args.device, pcap_statustostr(status));

  status = pcap_activate(pd);
  if (status < 0)
    error("%s: %s (%s)", args.device, pcap_statustostr(status), pcap_geterr(pd));

  if (args.direction_set && pcap_setdirection(pd, args.direction) != 0)
    error("%s: pcap_setdirection failed: %s", args.device, pcap_geterr(pd));

  memset(&action, 0, sizeof(action));
  action.sa_handler = sigint_handler;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGINT, &action, NULL) == -1)
    error("Can't catch SIGINT: %s", strerror(errno));

  status = pcap_loop(pd, -1, print_packet, (u_char *)args.device);
  if (status == PCAP_ERROR)
    error("%s: pcap_loop: %s", args.device, pcap_geterr(pd));

  pcap_close(pd);

  return 0;
}
