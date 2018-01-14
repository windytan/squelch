/* Zero signal to digital silence when sufficiently quiet
 *
 * Oona Räisänen 2012 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <math.h>

int main(int argc, char **argv) {

  /* Defaults */
  short int      ssize    = 16;
  unsigned int   buflen   = 2048;
  int            limit    = 1024;
  unsigned int   duration = 4096;
  unsigned int   ttime    = 512;

  unsigned short bufptr = 0;
  short int      pcm;
  short int      outbuf[buflen];
  short int      silcount = 0, ampcount = 0;
  float          amp = 1.0f;
  bool           silent = false, falling = false, rising = false;
  int            c;

  /* Command line options */
  while ((c = getopt (argc, argv, "u:l:L:d:t:")) != -1)
    switch (c) {
      case 'u':
        buflen = atoi(optarg);
        break;
      case 'l':
        limit = atoi(optarg);
        break;
      case 'L':
        limit = lroundf(pow(10, atof(optarg)/20.0) * pow(2, 15));
        break;
      case 'd':
        duration = atoi(optarg);
        break;
      case 't':
        ttime = atoi(optarg);
        break;
      case '?':
        fprintf (stderr, "Unknown option `-%c'.\n", optopt);
        return EXIT_FAILURE;
      default:
        break;
    }

  /* Actual signal */
  while (read(0, &pcm, ssize/8)) {

    /* Squelch is active */
    if (silent) {

      if (falling) {
        amp = (float)(ttime - ampcount) / ttime;
        outbuf[bufptr] = pcm * amp;
        ampcount ++;
        if (ampcount > ttime)
          falling = false;
      } else {
        outbuf[bufptr] = 0x0000;
      }

      /* Signal comes back */
      if (abs(pcm) > limit) {
        silent   = false;
        rising   = true;
        ampcount = 0;
        silcount = 0;
      }

    /* Squelch not active */
    } else {

      if (rising) {
        amp = ((float)ampcount) / ttime;
        outbuf[bufptr] = pcm * amp;
        ampcount ++;
        if (ampcount > ttime) rising = false;
      } else {
        outbuf[bufptr] = pcm;
      }

      /* Signal is silent */
      if (abs(pcm) < limit) {
        silcount ++;
        if (silcount > duration) {
          silent   = true;
          falling  = true;
          ampcount = 0;
        }
      }
    }

    if (++bufptr == buflen) {
      if (!write(1, &outbuf, 2 * buflen))
        return (EXIT_FAILURE);
      fflush(stdout);
      bufptr = 0;
    }

  }
}
