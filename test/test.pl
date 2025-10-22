#!/usr/bin/perl

# squelch tests
# - Will create some PCM files in the current directory

use strict;
use warnings;
use Carp;
use List::Util qw(all);

my $binary      = "../build/squelch";
my $input_file  = "input.pcm";
my $output_file = "output.pcm";

my $sample_size_in_bytes = 2;    # 16-bit PCM

my $has_failures = 0;

exit main();

sub main {
  print "Test binary: $binary\n";
  print "System:      ";
  system( "uname", "-rms" );

  testExeRunnable();

  # Can't continue if the exe is not runnable
  if ($has_failures) {
    return $has_failures;
  }

  # Output length should match input
  testOutputLength();

  # Signal is on, then turns off; squelch should mute it
  testOnOff();

  # Signal is off, then turns on; squelch should unmute
  testOffOn();

  print $has_failures
    ? "\n\033[31mTests did not pass\033[0m\n"
    : "\n\033[32mAll tests passed\033[0m\n";

  unlink $input_file;
  unlink $output_file;

  return $has_failures;
}

# testExeRunnable() -> void
sub testExeRunnable {
  print "\nExecutable should exist and be runnable\n";
  check( -x $binary, "$binary should exist" );
}

# testOutputLength() -> void
sub testOutputLength {
  print "\nOutput length should match input\n";

  my $input_length = 48000;
  makeTestFile( [ $input_length, 0 ] );

  system( $binary. "<" . $input_file . ">" . $output_file );

  my @output_samples = getSamples($output_file);

  check(
    @output_samples == $input_length,
    "Should preserve number of samples (expected: $input_length, got: "
      . scalar(@output_samples) . ")"
  );
}

# testOnOff() -> void
sub testOnOff {
  print "\nSignal going quieter should get muted\n";

  makeTestFile( [ 5000, 1 ], [ 5000, 0.1 ] );

  system("$binary -l 5000 -d 64 -t 100 < $input_file > $output_file");

  checkFilesIdenticalInRange( $input_file, $output_file, 100, 5000 - 100 );
  checkFileIsSilenceInRange( $output_file, 5000 + 100 + 64 + 1, 200 );
  checkSamplesSmallerOrEqual( $output_file, $input_file );
}

# testOffOn() -> void
sub testOffOn {
  print "\nAppearing signal should get unmuted\n";

  makeTestFile( [ 5000, 0.1 ], [ 5000, 1 ] );

  system("$binary -l 5000 -d 64 -t 100 < $input_file > $output_file");

  checkFileIsSilenceInRange( $output_file, 100 + 64 + 1, 200 );
  checkFilesIdenticalInRange( $input_file, $output_file, 5000 + 100 + 1, 5000 - 100 - 1 );
  checkSamplesSmallerOrEqual( $output_file, $input_file );
}

# checkFilesIdenticalInRange(file1, file2, start_sample, num_samples) -> void
sub checkFilesIdenticalInRange {
  my ( $file1, $file2, $start_sample, $num_samples ) = @_;

  my @samples1 = getSamples( $file1, $start_sample, $num_samples );
  my @samples2 = getSamples( $file2, $start_sample, $num_samples );

  check(
    ( all { $samples1[$_] == $samples2[$_] } 0 .. $#samples1 ),
    "Output should match input in range [$start_sample, "
      . ( $start_sample + $num_samples - 1 ) . "]"
  );
}

# checkSamplesSmallerOrEqual(file1, file2) -> void
sub checkSamplesSmallerOrEqual {
  my ( $file1, $file2 ) = @_;

  my @samples1 = getSamples($file1);
  my @samples2 = getSamples($file2);

  check( ( all { abs( $samples1[$_] ) <= abs( $samples2[$_] ) } 0 .. $#samples1 ),
    "Output should never exceed input" );
}

# checkFileIsSilenceInRange(filename, start_sample, num_samples) -> void
sub checkFileIsSilenceInRange {
  my ( $filename, $start_sample, $num_samples ) = @_;

  check(
    ( all { $_ == 0 } getSamples( $filename, $start_sample, $num_samples ) ),
    "Output should be zero in range [$start_sample, " . ( $start_sample + $num_samples - 1 ) . "]"
  );
}

sub getSamples {
  my ( $filename, $start_sample, $num_samples ) = @_;

  open( my $fh, '<:raw', $filename )
    or croak "Could not open '$filename' for reading: $!";

  seek( $fh, ( $start_sample // 0 ) * $sample_size_in_bytes, 0 );

  my @samples;
  for ( my $i = 0 ; $i < ( $num_samples // 9e6 ) && not eof $fh ; $i++ ) {
    my $data;
    read( $fh, $data, $sample_size_in_bytes );
    push @samples, unpack( 's<', $data );
  }

  close($fh);

  return @samples;
}

# makeTestFile([<duration_samples>, <amplitude>, ...]) -> void
sub makeTestFile {
  my @args = @_;

  open( my $fh, '>:raw', $input_file )
    or croak "Could not open '$input_file' for writing: $!";

  for my $pair (@args) {
    my ( $duration_samples, $amplitude ) = @$pair;
    writeTestBeep( $fh, $duration_samples, $amplitude );
  }

  close($fh);
}

# Write a snippet of test beep to $fh
# writeTestBeep(fh, num_samples, amplitude) -> void
sub writeTestBeep {
  my ( $fh, $num_samples, $amplitude ) = @_;

  my $position_in_fh = tell($fh);

  for ( my $i = 0 ; $i < $num_samples ; $i++ ) {
    my $wave_phase = ( $position_in_fh + $i ) % 9;
    my $wave       = ( $wave_phase < 3 ) ? 1 : ( $wave_phase < 6 ) ? -1 : 0;
    print $fh pack( 's<', $wave * 32767 * $amplitude );
  }
}

# bool is expected to be true, otherwise fail with message
# check(bool, message) -> void
sub check {
  my ( $bool, $message ) = @_;
  print( ( $bool ? "  \033[32m[ OK ]\033[0m " : "  \033[31m[FAIL]\033[0m " ) . $message . "\n" );

  $has_failures = 1 if ( !$bool );
}
