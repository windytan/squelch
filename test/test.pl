#!/usr/bin/perl

# squelch tests
# - Will create some PCM files in the current directory

use strict;
use warnings;
use IPC::Cmd qw(can_run);
use Carp;

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
    testName("Executable should exist and be runnable");
    check( -x $binary, "$binary should exist" );
}

# testOutputLength() -> void
sub testOutputLength {
    testName("Output length should match input");

    my $length_in_samples = 48000;
    createQuietTestFile( $input_file, $length_in_samples );

    system( $binary. "<" . $input_file . ">" . $output_file );

    my $output_length_in_samples = getFileLengthInSamples($output_file);

    check(
        $output_length_in_samples == $length_in_samples,
        "Should preserve number of samples "
          . "(expected: $length_in_samples, got: $output_length_in_samples)"
    );

    return;
}

# testOnOff() -> void
sub testOnOff {
    testName("Signal going quieter should get muted");

    open( my $fh, '>:raw', $input_file )
      or croak "Could not open '$input_file' for writing: $!";

    writeTestSamples( $fh, 5000, 1 );
    writeTestSamples( $fh, 5000, 0.1 );

    close $fh;

    system( $binary
          . " -l 5000 -d 64 -t 100 <"
          . $input_file . ">"
          . $output_file );

    checkFilesIdenticalInRange( $input_file, $output_file, 100, 5000 - 100 );
    checkFileZeroInRange( $output_file, 5000 + 100 + 64 + 1, 200 );
    checkSamplesSmallerOrEqual( $output_file, $input_file );
}

# testOffOn() -> void
sub testOffOn {
    testName("Signal coming back should get unmuted");

    open( my $fh, '>:raw', $input_file )
      or croak "Could not open '$input_file' for writing: $!";

    writeTestSamples( $fh, 5000, 0.1 );
    writeTestSamples( $fh, 5000, 1 );

    close $fh;

    system( $binary
          . " -l 5000 -d 64 -t 100 <"
          . $input_file . ">"
          . $output_file );

    checkFileZeroInRange( $output_file, 100 + 64 + 1, 200 );
    checkFilesIdenticalInRange(
        $input_file, $output_file,
        5000 + 100 + 1,
        5000 - 100 - 1
    );
    checkSamplesSmallerOrEqual( $output_file, $input_file );
}

# checkFilesIdenticalInRange(file1, file2, start_sample, num_samples) -> void
sub checkFilesIdenticalInRange {
    my ( $file1, $file2, $start_sample, $num_samples ) = @_;

    open( my $fh1, '<:raw', $file1 )
      or croak "Could not open '$file1' for reading: $!";
    open( my $fh2, '<:raw', $file2 )
      or croak "Could not open '$file2' for reading: $!";

    seek( $fh1, $start_sample * $sample_size_in_bytes, 0 );
    seek( $fh2, $start_sample * $sample_size_in_bytes, 0 );

    my $identical = 1;
    for ( my $i = 0 ; $i < $num_samples ; $i++ ) {
        my $data1;
        my $data2;

        read( $fh1, $data1, $sample_size_in_bytes );
        read( $fh2, $data2, $sample_size_in_bytes );

        if ( $data1 ne $data2 ) {
            $identical = 0;
            print "Files differ at sample "
              . ( $start_sample + $i ) . ": '"
              . unpack( 's<', $data1 )
              . "' vs '"
              . unpack( 's<', $data2 ) . "'\n";
            last;
        }
    }

    close($fh1);
    close($fh2);

    check( $identical,
            "Output should match input "
          . "in range [$start_sample, "
          . ( $start_sample + $num_samples - 1 )
          . "]" );

    return;
}

# Check that the samples in file1 are never larger (in absolute amplitude) than those in file2
# checkSamplesSmallerOrEqual(file1, file2) -> void
sub checkSamplesSmallerOrEqual {
    my ( $file1, $file2 ) = @_;

    open( my $fh1, '<:raw', $file1 )
      or croak "Could not open '$file1' for reading: $!";
    open( my $fh2, '<:raw', $file2 )
      or croak "Could not open '$file2' for reading: $!";

    my $samples_ok   = 1;
    my $sample_index = 0;
    while (1) {
        my $data1;
        my $data2;

        my $bytes_read1 = read( $fh1, $data1, $sample_size_in_bytes );
        my $bytes_read2 = read( $fh2, $data2, $sample_size_in_bytes );

        last if ( $bytes_read1 == 0 || $bytes_read2 == 0 );

        if ( abs( unpack( 's<', $data1 ) ) > abs( unpack( 's<', $data2 ) ) ) {
            $samples_ok = 0;
            print "e: Output gets amplified at sample index "
              . $sample_index . ": '"
              . unpack( 's<', $data1 )
              . "' vs '"
              . unpack( 's<', $data2 ) . "'\n";
            last;
        }

        $sample_index++;
    }

    close($fh1);
    close($fh2);

    check( $samples_ok, "Output should never exceed input" );

    return;
}

# Check that the given range is digital silence, set failure otherwise
# checkFileZeroInRange(filename, start_sample, num_samples) -> void
sub checkFileZeroInRange {
    my ( $filename, $start_sample, $num_samples ) = @_;

    open( my $fh, '<:raw', $filename )
      or croak "Could not open '$filename' for reading: $!";

    seek( $fh, $start_sample * $sample_size_in_bytes, 0 );

    my $is_zero = 1;
    for ( my $i = 0 ; $i < $num_samples ; $i++ ) {
        my $data;

        read( $fh, $data, $sample_size_in_bytes );

        if ( unpack( 's<', $data ) != 0 ) {
            $is_zero = 0;
            print "File '$filename' is not zero at sample "
              . ( $start_sample + $i ) . ": '"
              . unpack( 's<', $data ) . "'\n";
            last;
        }
    }

    close($fh);

    check( $is_zero,
            "Output should be zero "
          . "in range [$start_sample, "
          . ( $start_sample + $num_samples - 1 )
          . "]" );

    return;
}

# Write a snippet of test beep to $fh
# writeTestSamples(fh, num_samples, amplitude) -> void
sub writeTestSamples {
    my ( $fh, $num_samples, $amplitude ) = @_;

    my $position_in_fh = tell($fh);

    for ( my $i = 0 ; $i < $num_samples ; $i++ ) {
        my $wave_phase = ( $position_in_fh + $i ) % 9;
        my $wave       = ( $wave_phase < 3 ) ? 1 : ( $wave_phase < 6 ) ? -1 : 0;
        print $fh pack( 's<', $wave * 32767 * $amplitude );
    }
}

# createQuietTestFile(filename, length_in_samples) -> void
sub createQuietTestFile {
    my ( $filename, $length_in_samples ) = @_;

    open( my $fh, '>:raw', $filename )
      or croak "Could not open '$filename' for writing: $!";

    for ( my $i = 0 ; $i < $length_in_samples ; $i++ ) {
        print $fh pack( 's<', 0 );
    }

    close($fh);

    return;
}

# getFileLengthInSamples(filename) -> size_in_samples
sub getFileLengthInSamples {
    my ($filename) = @_;

    my $size_in_bytes   = -s $filename;
    my $size_in_samples = $size_in_bytes / $sample_size_in_bytes;

    return $size_in_samples;
}

# bool is expected to be true, otherwise fail with message
# check(bool, message) -> void
sub check {
    my ( $bool, $message ) = @_;
    print(
          ( $bool ? "  \033[32m[ OK ]\033[0m " : "  \033[31m[FAIL]\033[0m " )
        . $message
          . "\n" );

    $has_failures = 1 if ( !$bool );

    return;
}

sub testName {
    my ($name) = @_;
    print "\n$name\n";
}
