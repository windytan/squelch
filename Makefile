CC=gcc
CFLAGS=-Wall -Wextra -Wstrict-overflow -Wshadow -Wdouble-promotion -Wundef -Wpointer-arith -Wcast-align -Wcast-qual -Wuninitialized -Wimplicit-fallthrough -pedantic -std=c11 -O2

ifdef EXTRA_CFLAGS
CFLAGS += $(EXTRA_CFLAGS)
endif

squelch: squelch.c
	$(CC) $(CFLAGS) -o $@ $^ -lm
