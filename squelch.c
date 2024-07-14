/* Zero signal to digital silence when sufficiently quiet
 *
 * Oona Räisänen 2012 */

#include <getopt.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
  /* Defaults */
  unsigned int buflen   = 2048;
  int          limit    = 1024;
  unsigned int duration = 4096;
  unsigned int ttime    = 512;

  unsigned int silence_count = 0;
  bool         silent = false, falling = false, rising = false;
  int          c;

  /* Command line options */
  while ((c = getopt(argc, argv, "u:l:L:d:t:")) != -1) switch (c) {
      case 'u': buflen = atoi(optarg); break;
      case 'l': limit = atoi(optarg); break;
      case 'L': limit = lroundf(pow(10, atof(optarg) / 20.0) * pow(2, 15)); break;
      case 'd': duration = atoi(optarg); break;
      case 't': ttime = atoi(optarg); break;
      case '?': fprintf(stderr, "Unknown option `-%c'.\n", optopt); return EXIT_FAILURE;
      default:  break;
    }

  // Grows up to and shrinks from ttime as the squelch de/activates
  unsigned int bellow = ttime;
  short int    pcm[buflen];
  short int    outbuf[buflen];

  /* Actual signal */
  while (read(0, &pcm, buflen * sizeof(short int))) {
    for (unsigned int buffer_index = 0; buffer_index < buflen; buffer_index++) {
      /* Squelch is active */
      if (silent) {
        if (falling) {
          const float amplitude = (float)bellow / ttime;
          outbuf[buffer_index]  = pcm[buffer_index] * amplitude;
          bellow--;
          if (bellow == 0)
            falling = false;
        } else {
          outbuf[buffer_index] = 0x0000;
        }

        /* Signal comes back */
        if (abs(pcm[buffer_index]) > limit) {
          silent        = false;
          rising        = true;
          silence_count = 0;
        }

      } else {
        /* Squelch not active */
        if (rising) {
          const float amplitude = (float)bellow / ttime;
          outbuf[buffer_index]  = pcm[buffer_index] * amplitude;
          bellow++;
          if (bellow == ttime)
            rising = false;
        } else {
          outbuf[buffer_index] = pcm[buffer_index];
        }

        /* Signal goes silent */
        if (abs(pcm[buffer_index]) < limit) {
          silence_count++;
          if (silence_count > duration) {
            silent  = true;
            falling = true;
          }
        }
      }
    }

    if (!write(1, &outbuf, sizeof(short int) * buflen))
      return (EXIT_FAILURE);
    fflush(stdout);
  }
}
