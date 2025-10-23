**squelch** works like a noise gate: it replaces an incoming PCM signal with
digital silence when it's been sufficiently quiet for a sufficient time.

The input is assumed to be raw 16-bit signed-integer PCM. The
signal comes in through stdin and the output signal is written to
stdout.

The program treats the signal as a single channel, but it should work okay
for stereo and IQ as well. It won't work correctly with 8-bit input though.

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

| Long option | Short option | Default | Description |
| ----------- | ------------ | ------- | ----------- |
| `--amplitude-limit-db` | `-L` | -30 | Silence threshold in dBFS. The input must stay below this to get squelched. |
| `--amplitude-limit-abs` | `-l` | 1024 (-30 dBFS) | Same as `-L`, but in absolute (semi-)amplitude. You can provide one or the other. |
| `--silence-duration` | `-d` | 4096 | The signal gets muted when this many successive samples are below the silence threshold. Unmuting will happen even if a single sample gets above the limit. |
| `--fade-time` | `-t` | 512 | Transition time, in samples. This is how long it takes to smoothly fade the signal out after `--silence-duration` has passed; and how long it takes to fade back in after the first sign of signal.<br/>Use 0 to disable fading; it'll just instantly switch with a 'snap'. |
| `--buffer-length` | `-u` | 2048 | I/O buffer length, in samples. This can be used to control the frequency of output flushing, to fine-tune performance. It doesn't affect the output samples or squelch behavior in any way. |

## What's the throughput?

```
$ git rev-parse HEAD && cat /sys/firmware/devicetree/base/model
293ff5023afe4d96442641ada6226de5728512e9
Raspberry Pi 3 Model B Plus Rev 1.3

$ pv -k -S -s 1000M -F "%{average-rate}" < /dev/random | ./build/squelch > /dev/null
(88.9MB/s)

$ pv -k -S -s 1000M -F "%{average-rate}" < /dev/zero | ./build/squelch > /dev/null
( 197MB/s)

$ # RasPi 3B+:
$ # From /dev/random: 44 Msps single-channel
$ # From /dev/zero:   98 Msps single-channel
```

```
$ git rev-parse HEAD && sysctl hw.model
293ff5023afe4d96442641ada6226de5728512e9
hw.model: MacBookPro18,3

$ pv -k -S -s 1000M -F "%{average-rate}" < /dev/random | ./build/squelch --buffer-length 65536 > /dev/null
( 373MB/s)

$ pv -k -S -s 1000M -F "%{average-rate}" < /dev/zero | ./build/squelch --buffer-length 65536 > /dev/null
(1.57GB/s)

$ # Apple M1:
$ # From /dev/random: 186 Msps single-channel
$ # From /dev/zero:   785 Msps single-channel
```
