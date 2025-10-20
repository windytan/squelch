/* Zero signal to digital silence when sufficiently quiet
 *
 * Oona Räisänen 2012 */

#include <getopt.h>
#include <unistd.h>

#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <stdexcept>
#include <vector>

using SampleType = std::int16_t;

struct Options {
  int buffer_length{2048};
  int amplitude_limit{1024};
  int min_silence_duration{4096};
  int transition_time{512};
};

namespace {

// Smoothstep coefficient for index in [0, length]
inline float smoothStep(int index, int length) {
  const float x = static_cast<float>(index) / static_cast<float>(length);
  return x * x * (3.f - 2.f * x);
}

// Scale an integer sample by float factor
inline SampleType scale(SampleType sample, float factor) {
  return static_cast<SampleType>(std::lround(static_cast<float>(sample) * factor));
}

// optarg to int
inline int getInt(const char *str) {
  return static_cast<int>(std::strtol(str, nullptr, 10));
}

inline Options getOptions(int argc, char **argv) {
  Options options;
  bool    has_absolute_limit = false;
  bool    has_decibel_limit  = false;

  // clang-format off
  const std::array<option, 6> long_options{{
      {"buffer-length",        no_argument,       nullptr, 'u'},
      {"amplitude-limit-abs",  required_argument, nullptr, 'l'},
      {"amplitude-limit-db",   required_argument, nullptr, 'L'},
      {"min-silence-duration", required_argument, nullptr, 'd'},
      {"fade-time",            required_argument, nullptr, 't'},
      {nullptr,                0,                 nullptr, 0  }
  }};
  // clang-format on

  int option_index{};
  int option_char{};

  while ((option_char =
              ::getopt_long(argc, argv, "u:l:L:d:t:", long_options.data(), &option_index)) >= 0) {
    switch (option_char) {
      case 'u': options.buffer_length = getInt(optarg); break;
      case 'l': options.amplitude_limit = getInt(optarg); break;
      case 'L':
        options.amplitude_limit =
            static_cast<int>(std::pow(10.f, (std::strtof(optarg, nullptr) / 20.f)) *
                             std::numeric_limits<SampleType>::max());
        break;
      case 'd': options.min_silence_duration = getInt(optarg); break;
      case 't': options.transition_time = getInt(optarg); break;
      default:
        static_cast<void>(std::fprintf(
            stderr,
            "Usage: squelch [-u buffer_length] [-l amplitude_limit_abs] [-L amplitude_limit_dB] "
            "[-d min_silence_duration] [-t fade_time]\n"));
        std::exit(EXIT_FAILURE);
    }
  }

  if (options.buffer_length <= 0) {
    throw std::invalid_argument("Invalid buffer length.");
  }

  if (has_absolute_limit && has_decibel_limit) {
    throw std::invalid_argument("Conflicting amplitude limit options.");
  }

  if (options.amplitude_limit <= 0 ||
      options.amplitude_limit > std::numeric_limits<SampleType>::max()) {
    throw std::invalid_argument("Invalid amplitude limit.");
  }

  if (options.transition_time < 0) {
    throw std::invalid_argument("Invalid fade time (must be >= 0 samples).");
  }

  if (options.min_silence_duration <= 0) {
    throw std::invalid_argument("Invalid silence duration (must be > 0 samples).");
  }

  return options;
}

}  // namespace

int main(int argc, char **argv) {
  Options options;

  try {
    options = getOptions(argc, argv);
  } catch (const std::invalid_argument &e) {
    static_cast<void>(std::fprintf(stderr, "Error: %s\n", e.what()));
    return EXIT_FAILURE;
  }

  int silence_count = 0;

  // The input has been below threshold for a while
  bool is_input_staying_silent = false;

  // Currently fading output in or out
  bool       is_output_fading_out = false;
  bool       is_output_fading_in  = false;

  const bool is_fade_enabled = (options.transition_time > 0);

  // Grows up to and shrinks from transition_time as the squelch de/activates
  int                     fader = options.transition_time;

  std::vector<SampleType> buffer(options.buffer_length);

  while (true) {
    const auto bytes_read = ::read(0, buffer.data(), buffer.size() * sizeof(SampleType));
    if (bytes_read == 0) {
      // EOF
      break;
    }
    if (bytes_read < 0) {
      // I/O error
      return EXIT_FAILURE;
    }

    const std::size_t nsamples_read = static_cast<std::size_t>(bytes_read) / sizeof(SampleType);
    for (std::size_t buffer_index = 0; buffer_index < nsamples_read; buffer_index++) {
      auto      &sample = buffer[buffer_index];

      const bool is_input_above_threshold = (std::abs(sample) >= options.amplitude_limit);

      if (is_input_staying_silent) {  // Signal has been silent for a while --> squelching
        if (is_output_fading_out) {   // Smoothstep fade out
          sample = scale(sample, smoothStep(fader, options.transition_time));
          fader--;
          if (fader == 0) {
            is_output_fading_out = false;
          }
        } else {
          // Completely silent
          buffer[buffer_index] = 0;
        }

        // Signal comes back
        if (is_input_above_threshold) {
          is_input_staying_silent = false;
          is_output_fading_in     = is_fade_enabled;
          silence_count           = 0;
        }

      } else {                      // Signal is not silent
        if (is_output_fading_in) {  // Smoothstep fade in
          sample = scale(sample, smoothStep(fader, options.transition_time));
          fader++;
          if (fader == options.transition_time) {
            is_output_fading_in = false;
          }
        } else {
          // Do nothing; signal passes through as-is
        }

        if (is_input_above_threshold) {
          silence_count = 0;
        } else {
          // Signal goes silent
          silence_count++;
          if (silence_count > options.min_silence_duration) {
            is_input_staying_silent = true;
            is_output_fading_out    = is_fade_enabled;
          }
        }
      }
    }

    // Write & flush the current buffer
    if (::write(1, buffer.data(), sizeof(SampleType) * nsamples_read) <= 0) {
      // I/O error
      return EXIT_FAILURE;
    }
    static_cast<void>(std::fflush(stdout));
  }
}
