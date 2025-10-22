**squelch** works like a noise gate: it replaces an incoming PCM signal with
digital silence when it's been sufficiently quiet for a sufficient time.

The input is assumed to be raw single-channel 16-bit signed-integer PCM. The
signal comes in through stdin and the output signal is written to
stdout.

*squelch* can be used to remove dithering from intended silence; to block empty radio channel noise; etc. It was
originally made as a preprocessing step for lossless compression.

## Dependencies

* C++11 compiler
* GNU make

## How to compile

```sh
make
```

## Usage

```sh
some_program --producing --samples | squelch [OPTION]... | ...
```

## Command line options

All options are optional and have somewhat reasonable defaults.

`--buffer-length SAMPLES` / `-u SAMPLES`

I/O buffer length, in samples; defaults to 2048.
This can be used to control the frequency of output flushing, to adjust performance.
(It doesn't affect the output samples or squelch behavior in any way.)

`--amplitude-limit-abs LEVEL`/  `-l LEVEL`

Silence threshold, in absolute (semi-)amplitude; defaults to 1024 (-30 dBFS).
The input must stay below this to get squelched.

`--amplitude-limit-db LEVEL` /  `-L LEVEL`

Same as `-l`, but given in dBFS; e.g. `-L -30`.

`--silence-duration SAMPLES`/ `-d SAMPLES`

The signal gets muted when this many successive samples are below the silence threshold.
Defaults to 4096. Unmuting will happen even if a single sample gets above the limit.

`--fade-time SAMPLES` / `-t SAMPLES`

Transition time, in samples; defaults to 512.
This is how long it takes to smoothly fade the signal out after `--silence-duration` has passed;
and how long it takes to fade back in after the first sign of signal.
Use 0 to disable fading (it'll just switch instantly with a snap).

## What's the throughput?

```
$ cat /sys/firmware/devicetree/base/model
Raspberry Pi 3 Model B Plus Rev 1.3

$ git rev-parse HEAD
293ff5023afe4d96442641ada6226de5728512e9

$ pv -k -S -s 100M -F "%{average-rate}" < /dev/random | ./build/squelch > /dev/null
(84.5MB/s)

$ # == 42 Msps
```

```
$ sysctl hw.model
hw.model: MacBookPro18,3

$ git rev-parse HEAD
293ff5023afe4d96442641ada6226de5728512e9

$ pv -k -S -s 1000M -F "%{average-rate}" < /dev/random | ./build/squelch --buffer-length 65536 > /dev/null
( 373MB/s)

$ # == 186 Msps
```
