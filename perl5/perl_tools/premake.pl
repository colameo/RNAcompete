#!/usr/bin/perl -w

require "libfile.pl";
require "$ENV{MYPERLDIR}/lib/libstats.pl";
require "$ENV{MYPERLDIR}/lib/libstring.pl";

use POSIX qw(ceil floor); # import the ceil(ing) and floor functions for handling fractions/integers
use List::Util qw(max min); # import the max and min functions
use Term::ANSIColor;

use strict;
use warnings;
use diagnostics;

use File::Basename;
use Getopt::Long;

sub main();  

sub printUsage() {
    print STDOUT <DATA>;
    exit(0);
}

sub make { # prints to the output makefile. Use this in the Makefiles, instead of having to use "print OUTPUT". Just plain "print" will not work.
  print OUTPUT ($_[0]) . "\n";
}

sub maket { # prints to the output makefile.
  make("\t" . $_[0]); # calls make, but with a prepending tab! This is used for rules
}

sub printPremakeWarning() {
	print OUTPUT "\n\n";
	print OUTPUT "#PREMAKE\n";
	print OUTPUT "# ******* This file was run through premake.pl *******" . "\n";
	print OUTPUT "# ******* DO NOT EDIT THIS FILE MANUALLY *******" . "\n";
	print OUTPUT "# ******* Instead, edit YOUR_MAKEFILE, and then run it through premake.pl *******" . "\n";
	print OUTPUT "# ******* The syntax for this is:  premake.pl -f YOUR_MAKEFILE YOUR_ARGUMENTS_TO_MAKE; ******" . "\n";
	print OUTPUT "# ******* This will both create the \"premake\" file, and run it with make. *****\n";
	print OUTPUT "\n\n";
}

# ==1==
sub main() { # Main program
    my ($delim) = "\t";
	my ($infile) = undef;
	my ($dryRun) = 0; # if dryrun, then don't actually run it--generate the file only
	my ($alwaysRegen) = 0; # always regenerate the makefile
	$Getopt::Long::passthrough = 1;

    GetOptions("help|?|man" => sub { printUsage(); }
			   , "f=s" => \$infile
			   , "dry|d!" => \$dryRun
			   , "Z!" => \$alwaysRegen
	       ) or printUsage();

	#foreach (@ARGV) {
	#	print STDERR "Unprocessed argument: $_\n";
	#}

	my $makeArgs = ' ';
	if (scalar(@ARGV) > 0) {
	  $makeArgs .= join(' ', @ARGV[0..$#ARGV]);
	}

	if (!defined($infile)) {
	  # if the input file was not explicitly specified...
	  
	  my $hasRegularMakefile = (-e "makefile" || -e "Makefile" || -e "MAKEFILE");
	  
	  if ($hasRegularMakefile && !(-e "Makefile.pre.mak")) {
		# I guess there's no "pre.mak" file, and there IS a makefile, so let's just run regular make
		print STDERR "premake.pl: Running <make$makeArgs> directly, skipping any .pre.mak file...\n";
		exec(qq{make $makeArgs});
	  } else {
		$infile = "Makefile.pre.mak";
	  }
	}
	
	if ($infile =~ /\"/) {
	  die "ERROR! Makefiles cannot have quotation marks in their name and expect to work! Why does your file have a quotation mark in its name, anyway?\n";
	}

	my ($outfile) = "PREMAKE_$infile.tmp";

	# See if the to-be-read makefile is more recently edited than the PREMAKE file.
	# If it is newer than PREMAKE, then regenerate premake. Otherwise, quit.

	my ($inModifyTime, $outModifyTime);
	if (-e $outfile) {
	  {
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($infile);
		$inModifyTime = $mtime; # time in seconds or something since 1977
	  }
	  {
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($outfile);
		$outModifyTime = $mtime; # time in seconds or something since 1977
	  }
	}
	
	if (!$alwaysRegen && (-e $outfile) && ($inModifyTime < $outModifyTime)) {
	  # The input file hasn't been changed since the output file was written, so no need to update it.
	  print STDERR "Not updating the file <$outfile> (modified at $outModifyTime), becaues the source file <$infile> has not been changed since it was generated at $inModifyTime.\n";
	} else {

	  my $readingPerl = 0;
	  my $command;
	  my $lineNum = 0;
	  my $timeSinceLastWarningMessage = 0;
	  my $frequencyOfWarningMessages  = 10;
	  open(INPUT, "< $infile") or die "Could not open input makefile <$infile>.\n"; {

		if (-e $outfile) {
		  my $chPlusCommand = qq{chmod u+w "$outfile"};
		  (system($chPlusCommand) == 0) or die "Failed to execute the command: <$chPlusCommand>.\n";
		}
		open(OUTPUT, "> $outfile") or die "Could not open output file <$outfile>.\n"; {
		  printPremakeWarning();
		
		  while (my $line = <INPUT>) {
			$lineNum++;

			if ($line =~ /^#PREMAKE/) {
			  die "ERROR! You are trying to run a premake'd file through premake AGAIN.\n";
			}

			if ($line =~ /tail \+[0-9]/) {
			  die "SUPER DUPER INCOMPATIBLE TAIL UTILITY PROBLEM! In the file $infile, you have the code: \"tail +NUMBER\", but this no longer works on all machines (newer versions of tail do not accept this syntax). Change it to tail -n +NUMBER instead.\n";
			}

			if ($line =~ /^\$\(error \"?PREMAKE/) {
			  # We will remove this "hey you, make sure to run this in premake" warning/error
			  next;
			}

			if ($line =~ /^PERL_START/) {
			  $readingPerl = 1;
			  $command = '';	# reset the command
			  next;
			}
			if ($line =~ /^PERL_END/) {
			  $readingPerl = 0;
			  my $result = eval("use strict; use warnings; " . ${command});
			  if (!defined($result)) {
				my $errorMessage = "$@";
				die "ERROR in a PERL section in the makefile. Here is the error message:\n\n$errorMessage\n";
			  }
			  print OUTPUT "\n";
			  next;
			}

			if ($readingPerl) {
			  $command .= $line; # add to the command that we will execute...
			} else {

			  if (($line =~ /^$/) && ($timeSinceLastWarningMessage > $frequencyOfWarningMessages)) {
				# If there is ONLY a blank line, then add a warning message! (but only if we haven't just written one recently)
				print OUTPUT "\n\n# ******* DO NOT EDIT THIS FILE MANUALLY (see top of file) *******" . "\n\n";
				$timeSinceLastWarningMessage = 0;
			  }

			  # reading a makefile
			  if ($line =~ /^[ ]/) {
				die "Makefile error on line $lineNum: This line begins with a SPACE (not a tab), which Make hates more than anything.\n";
			  }
			  print OUTPUT $line;
			}
			$lineNum++;
			$timeSinceLastWarningMessage++;
		  }

		  printPremakeWarning();
		}
		close (OUTPUT);
	  }
	  close(INPUT);
	}
	
	
	print STDERR "Running make on the file <$outfile>, with the argument list: <$makeArgs>.\n";

	my $chCommand = qq{chmod a-w "$outfile"};
	(system($chCommand) == 0) or die "Failed to execute the command: <$chCommand>.\n";

	if (!$dryRun) {
	  
	  my $makeCommand = qq{make -f "$outfile" $makeArgs};
	  
	  print STDERR "Running the make command: $makeCommand\n";
	  system($makeCommand);
	} else {
	  print STDERR "Since this was a dry run, we did not actually run the command.\n";
	}

} # end main()


main();


END {
  # Runs after everything else.
  # Makes sure that the terminal text is back to its normal color.
  resetColor();
}

exit(0);
# ====

__DATA__

premake.pl  [OPTIONS]

by Alex Williams, 2008

This program preprocesses makefiles to allow arbitrary perl commands to
be executed in Makefiles (between PERL_BEGIN and PERL_END blocks).

It also checks for invalid whitespace at the beginning of lines.

See the examples below for more information.

CAVEATS:

If you are using this program, then you probably do not really want
to be using makefiles in the first place. Beware!

OPTIONS:

  --delim = DELIMITER   (Default: tab)
     Sets the input delimiter to DELIMITER.

  --dry or -d
     Dry run. Only generates the output makefile, does not run it.

  -Z
     Force a remake of the Makefile.pre -> Makefile, regardless of modification.

EXAMPLES:

premake.pl --help
  Displays this help


premake.pl my-annotated-makefile.mak

KNOWN BUGS:

  This program is an unholy monstrosity born from our use of Make in
  crazy situations. Beware. It is still easier than writing out lots
  of make rules, though.

TO DO:


--------------
