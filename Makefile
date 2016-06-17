CC=gcc

squelch: squelch.c
	$(CC) -o $@ $^
