#!/usr/bin/perl
#
# epn-test.pm
# Eric Nawrocki
# EPN, Thu Jul 12 10:00:53 2018
# version: 0.01
#
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

require "epn-options.pm";
require "epn-ofile.pm";

#####################################################################
#
# List of subroutines:
# 
#   test_ParseTestFile()
#   test_DiffTwoFiles()
#
#################################################################
#################################################################
# Subroutine:  test_ParseTestFile()
# Incept:      EPN, Wed May 16 16:03:40 2018
#
# Purpose:     Parse an input test file and store the relevant information
#              in passed in array references.
#
# Arguments:
#   $testfile:    name of file to parse
#   $pkgstr:      package string, from caller, e.g. "RIBO"
#   $cmd_AR:      ref to array of commands to fill here
#   $desc_AR:     ref to array of descriptions to fill here
#   $outfile_AAR: ref to 2D array of output files to fill here
#   $expfile_AAR: ref to 2D array of expected files to fill here
#   $rmdir_AAR:   ref to 2D array of directories to remove after calling each command
#   $opt_HHR:     ref to 2D hash of option values, see top of epn-options.pm for description
#   $FH_HR:       ref to hash of file handles, including "log" and "cmd"
#
# Returns:    number of commands read in $testfile
#
# Dies:       - if any of the expected files do not exist
#             - if number of expected files is not equal to number of output files
#               for any command
#             - if there are 0 output files for a given command
#             - if output file already exists
#################################################################
sub test_ParseTestFile { 
  my $sub_name = "test_ParseTestFile";
  my $nargs_expected = 9;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($testfile, $pkgstr, $cmd_AR, $desc_AR, $outfile_AAR, $expfile_AAR, $rmdir_AAR, $opt_HHR, $FH_HR) = @_;

  open(IN, $testfile) || ofile_FileOpenFailure($testfile, $pkgstr, $sub_name, $!, "reading", $FH_HR);
  my $ncmd = 0;
  my $ndesc = 0;
  my $outfile;
  my $expfile;
  my $rmdir;

  while(my $line = <IN>) { 
    if(($line !~ m/^\#/) && ($line =~ m/\w/)) { 
      # example input file:
      # # comment line (ignored)
      # command: perl $DNAORGDIR/dnaorg_scripts/dnaorg_classify.pl -f -A /panfs/pan1/dnaorg/virseqannot/dnaorg-build-directories/norovirus-builds --infasta testfiles/noro.9.fa --dirbuild /panfs/pan1/dnaorg/virseqannot/dnaorg-build-directories/norovirus-builds --dirout test-noro.9
      # out: test-noro.9/test-noro.9-NC_001959.dnaorg_annotate.sqtable 
      # exp: testfiles/testout.1/test-noro.9/test-noro.9-NC_001959.dnaorg_annotate.sqtable 
      chomp $line;
      if($line =~ m/\r$/) { chop $line; } # remove ^M if it exists

      if($line =~ s/^command\:\s+//) { 
        my $cmd = $line;
        if($ncmd > 0) { 
          # make sure we have read >= 1 outfiles and expfiles for previous command
          if(! (@{$outfile_AAR->[($ncmd-1)]})) { ofile_FAIL("ERROR did not read any out: lines for command " . ($ncmd+1), $pkgstr, 1, $FH_HR); }
          if(! (@{$expfile_AAR->[($ncmd-1)]})) { ofile_FAIL("ERROR did not read any exp: lines for command " . ($ncmd+1), $pkgstr, 1, $FH_HR); }
          my $nout_prv = scalar(@{$outfile_AAR->[($ncmd-1)]});
          my $nexp_prv = scalar(@{$expfile_AAR->[($ncmd-1)]});
          if($nout_prv != $nexp_prv) { 
            ofile_FAIL("ERROR different number of output and expected lines for command " . ($ncmd+1), $pkgstr, 1, $FH_HR);
          }
        }
        # replace !<s>! with value of --<s> from options, die if it wasn't set or doesn't exist
        while($cmd =~ /\!(\w+)\!/) { 
          my $var = $1;
          my $varopt = "--" . $var;
          if(! opt_Exists($varopt, $opt_HHR)) { 
            ofile_FAIL("ERROR trying to replace !$var! in test file but option --$var does not exist in command line options", $pkgstr, 1, $FH_HR); 
          }
          if(! opt_IsUsed($varopt, $opt_HHR)) { 
            ofile_FAIL("ERROR trying to replace !$var! in test file but option --$var was not specified on the command line, please rerun with --$var", $pkgstr, 1, $FH_HR); 
          }
          my $replacevalue = opt_Get($varopt, $opt_HHR);
          $cmd =~ s/\!$var\!/$replacevalue/g;
        }
        push(@{$cmd_AR}, $cmd); 
        $ncmd++;
      }
      elsif($line =~ s/^desc\:\s+//) { 
        my $desc = $line;
        push(@{$desc_AR}, $desc); 
        $ndesc++;
      }
      elsif($line =~ s/^out\:\s+//) { 
        $outfile = $line;
        $outfile =~ s/^\s+//;
        $outfile =~ s/\s+$//;
        if($outfile =~ m/\s/) { ofile_FAIL("ERROR output file has spaces: $outfile", $pkgstr, 1, $FH_HR); }
        if(scalar(@{$outfile_AAR}) < $ncmd) { 
          @{$outfile_AAR->[($ncmd-1)]} = ();
        }
        push(@{$outfile_AAR->[($ncmd-1)]}, $outfile);
        if((opt_IsUsed("-s", $opt_HHR)) && (opt_Get("-s", $opt_HHR))) { 
          # -s used, we aren't running commands, just comparing files, output files must already exist
          if(! -e $outfile) { ofile_FAIL("ERROR, output file $outfile does not already exist (and -s used)", $pkgstr, 1, $FH_HR); }
        }
        else { 
          # -s not used
          if(-e $outfile) { ofile_FAIL("ERROR, output file $outfile already exists (and -s not used)", $pkgstr, 1, $FH_HR); }
        }
      }
      elsif($line =~ s/^exp\:\s+//) { 
        $expfile = $line;
        $expfile =~ s/^\s+//;
        $expfile =~ s/\s+$//;
        # replace @<s>@ with value of $ENV{'<s>'}
        while($expfile =~ /\@(\w+)\@/) { 
          my $envvar = $1;
          my $replacevalue = $ENV{"$envvar"};
          $expfile =~ s/\@$envvar\@/$replacevalue/g;
        }
        if($expfile =~ m/\s/) { ofile_FAIL("ERROR expected file has spaces: $expfile", $pkgstr, 1, $FH_HR) }
        if(scalar(@{$expfile_AAR}) < $ncmd) { 
          @{$expfile_AAR->[($ncmd-1)]} = ();
        }
        push(@{$expfile_AAR->[($ncmd-1)]}, $expfile);
        if(! -e $expfile) { ofile_FAIL("ERROR, expected file $expfile does not exist", $pkgstr, 1, $FH_HR); }
      }
      elsif($line =~ s/^rmdir\:\s+//) { 
        $rmdir = $line;
        $rmdir =~ s/^\s+//;
        $rmdir =~ s/\s+$//;
        if(! defined $rmdir_AAR->[($ncmd-1)]) { 
          @{$rmdir_AAR->[($ncmd-1)]} = ();
        }
        push(@{$rmdir_AAR->[($ncmd-1)]}, "$rmdir");
      }
      else { 
        ofile_FAIL("ERROR unable to parse line $line in $testfile", $pkgstr, 1, $FH_HR);
      }
    }
  }
  close(IN);

  if($ndesc != $ncmd) { ofile_FAIL("ERROR did not read same number of descriptions and commands", $pkgstr, 1, $FH_HR); }

  # for final command, check that number of exp and out files is equal
  if(! (@{$outfile_AAR->[($ncmd-1)]})) { ofile_FAIL("ERROR did not read any out: lines for command " . ($ncmd+1), $pkgstr, 1, $FH_HR); }
  if(! (@{$expfile_AAR->[($ncmd-1)]})) { ofile_FAIL("ERROR did not read any exp: lines for command " . ($ncmd+1), $pkgstr, 1, $FH_HR); }
  my $nout_prv = scalar(@{$outfile_AAR->[($ncmd-1)]});
  my $nexp_prv = scalar(@{$expfile_AAR->[($ncmd-1)]});
  if($nout_prv != $nexp_prv) { 
    ofile_FAIL("ERROR different number of output and expected lines for command " . ($ncmd+1), $pkgstr, 1, $FH_HR);
  }

  return $ncmd;
}

#################################################################
# Subroutine:  test_DiffTwoFiles()
# Incept:      EPN, Thu May 17 14:24:06 2018
#
# Purpose:     Diff two files, and output whether they are identical or not.
#
# Arguments:
#   $out_file:    name of output file
#   $exp_file:    name of expected file
#   $diff_file:   output file for diff command
#   $pkgstr:      package string, from caller, e.g. "RIBO"
#   $FH_HR:       REF to hash of file handles, including "log" and "cmd"
#
# Returns:    '1' if $outfile is identical to $expfile as determined by diff
#
# Dies:       If an expected file does not exist or is empty.
#
#################################################################
sub test_DiffTwoFiles { 
  my $sub_name = "test_DiffTwoFiles";
  my $nargs_expected = 5;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($out_file, $exp_file, $diff_file, $pkgstr, $FH_HR) = @_;

  my $out_file_exists   = (-e $out_file) ? 1 : 0;
  my $exp_file_exists   = (-e $exp_file) ? 1 : 0;
  my $out_file_nonempty = (-s $out_file) ? 1 : 0;
  my $exp_file_nonempty = (-s $exp_file) ? 1 : 0;

  my $conclusion = "";
  my $pass = 0;

  if(! $exp_file_exists) { 
    ofile_FAIL("ERROR in $sub_name, expected file $exp_file does not exist", $pkgstr, 1, $FH_HR) ;
  }
  if(! $exp_file_nonempty) { 
    ofile_FAIL("ERROR in $sub_name, expected file $exp_file exists but is empty", $pkgstr, 1, $FH_HR);
  }
    
  ofile_OutputString($FH_HR->{"log"}, 1, sprintf("#\t%-60s ... ", "checking $out_file"));

  if($out_file_nonempty) { 
    my $cmd = "diff -U 0 $out_file $exp_file > $diff_file";
    # don't use runCommand() because diff 'fails' if files are not identical
    ofile_OutputString($FH_HR->{"cmd"}, 0, "$cmd\n");
    system($cmd);
    if(-s $diff_file) { 
      # copy the two files here:
      my $copy_of_out_file = $diff_file . ".out";
      my $copy_of_exp_file = $diff_file . ".exp";
      ribo_RunCommand("cp $out_file $copy_of_out_file", 0, $FH_HR);
      ribo_RunCommand("cp $exp_file $copy_of_exp_file", 0, $FH_HR);
      # analyze the diff file and print out how many lines 
      if($out_file =~ m/\.sqtable/ && $exp_file =~ m/\.sqtable/) { 
        my $sqtable_diff_file = $diff_file . ".man";
        test_DnaorgCompareTwoSqtableFiles($out_file, $exp_file, $sqtable_diff_file, $FH_HR);
        $conclusion = "FAIL [files differ, see $sqtable_diff_file]";
      }
      else { 
        $conclusion = "FAIL [files differ, see $diff_file]";
      }
    }
    else { 
      $conclusion = "pass";
      $pass = 1;
    }
  }
  else { 
    $conclusion = ($out_file_exists) ? "FAIL [output file exists but is empty]" : "FAIL [output file does not exist]";
  }

  ofile_OutputString($FH_HR->{"log"}, 1, "$conclusion\n");

  return $pass;
}

#################################################################
# Subroutine:  test_DnaorgCompareTwoSqtableFiles()
# Incept:      EPN, Mon Jun 11 09:42:11 2018
#
# Purpose:     Compare two sqtable files outputting the number of 
#              lost, added, and changed features.
#
# Arguments:
#   $out_file:    name of output sqtable file
#   $exp_file:    name of expected sqtable file
#   $diff_file:   name of file to create with differences
#   $pkgstr:      package string, from caller, e.g. "DNAORG"
#   $FH_HR:       REF to hash of file handles, including "log" and "cmd"
#
# Returns:    void
#
# Dies:       If sequences are not in the same order in the two files
#
#################################################################
sub test_DnaorgCompareTwoSqtableFiles { 
  my $sub_name = "test_DnaorgCompareTwoSqtableFiles";
  my $nargs_expected = 5;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($out_file, $exp_file, $diff_file, $pkgstr, $FH_HR) = @_;

  my $out_file_exists   = (-e $out_file) ? 1 : 0;
  my $exp_file_exists   = (-e $exp_file) ? 1 : 0;
  my $out_file_nonempty = (-s $out_file) ? 1 : 0;
  my $exp_file_nonempty = (-s $exp_file) ? 1 : 0;

  my $conclusion = "";
  my $pass = 0;

  if(! $exp_file_exists) { 
    ofile_FAIL("ERROR in $sub_name, expected file $exp_file does not exist", $pkgstr, 1, $FH_HR) ;
  }
  if(! $exp_file_nonempty) { 
    ofile_FAIL("ERROR in $sub_name, expected file $exp_file exists but is empty", $pkgstr, 1, $FH_HR);
  }
    
  my @out_line_A = ();  # array of all lines in out file
  my @exp_line_A = ();  # array of all lines in exp file
  my $out_line;         # single line from out file
  my $exp_line;         # single line from exp file

  my %exp_seq_lidx_H = (); # key: sequence name, value line index where sequence annotation starts for key in $exp_file
  my @exp_seq_A      = (); # array of all sequence name keys in order in %exp_seq_lidx_H

  my %out_seq_lidx_H = (); # key: sequence name, value line index where sequence annotation starts for key in $out_file
  my @out_seq_A      = (); # array of all sequence name keys in order in %out_seq_lidx_H

  my %seq_exists_H = ();   # key is a sequence name, value is '1' if sequence exists in either @exp_seq_A or @out_seq_A

  my $lidx = 0; # line index
  my $seq;      # a sequence name         

  my $nseq = 0; # total number of sequences
  my $tot_nseq_ftr_identical = 0; # number of sequences with all features identically annotated between output and expected
  my $tot_nseq_ftr_diff      = 0; # number of sequences with >=1 feature differently annotated between output and expected
  my $tot_nseq_ftr_out_only  = 0; # number of sequences with >=1 feature only in the output file (not in the expected file)
  my $tot_nseq_ftr_exp_only  = 0; # number of sequences with >=1 feature only in the expected file (not in the output file)

  my $tot_nseq_note_identical = 0; # number of sequences with all notes identically annotated between output and expected
  my $tot_nseq_note_diff      = 0; # number of sequences with >=1 note differently annotated between output and expected
  my $tot_nseq_note_out_only  = 0; # number of sequences with >=1 note only in the output file (not in the expected file)
  my $tot_nseq_note_exp_only  = 0; # number of sequences with >=1 note only in the expected file (not in the output file)

  if($out_file_nonempty) { 
    open(OUT, $out_file) || ofile_FileOpenFailure($out_file, $pkgstr, $sub_name, $!, "reading", $FH_HR);
    $lidx = 0;
    while($out_line = <OUT>) { 
      if($out_line =~ m/^\>/) { 
        $seq = $out_line;
        chomp $seq;
        push(@out_seq_A, $seq);
        $out_seq_lidx_H{$seq} = $lidx;
        if(! exists $seq_exists_H{$seq}) { 
          $seq_exists_H{$seq} = 1;
        }
      }
      push(@out_line_A, $out_line);
      $lidx++;
    }
    close(OUT);

    open(EXP, $exp_file) || ofile_FileOpenFailure($exp_file, $pkgstr, $sub_name, $!, "reading", $FH_HR);
    $lidx = 0;
    while($exp_line = <EXP>) { 
      if($exp_line =~ m/^\>/) { 
        $seq = $exp_line;
        chomp $seq;
        push(@exp_seq_A, $seq);
        $exp_seq_lidx_H{$seq} = $lidx;
        if(! exists $seq_exists_H{$seq}) { 
          $seq_exists_H{$seq} = 1;
        }
      }
      push(@exp_line_A, $exp_line);
      $lidx++;
    }
    close(EXP);

    # make sure all sequences existed in both files
    foreach $seq (sort keys %seq_exists_H) { 
      if(! exists $out_seq_lidx_H{$seq}) { 
        ofile_FAIL("ERROR in $sub_name, $seq not in out_seq_lidx_H", $pkgstr, 1, $FH_HR);
      }
      if(! exists $exp_seq_lidx_H{$seq}) { 
        ofile_FAIL("ERROR in $sub_name, $seq not in exp_seq_lidx_H", $pkgstr, 1, $FH_HR);
      }
      #printf("HEYA $seq $out_seq_lidx_H{$seq} $exp_seq_lidx_H{$seq}\n");
    }
    # make sure all sequences are in the same order in both files
    $nseq = scalar(@out_seq_A);
    my $s;
    for($s = 0; $s < $nseq; $s++) { 
      if($out_seq_A[$s] ne $exp_seq_A[$s]) { 
        ofile_FAIL("ERROR in $sub_name, $seq not in same order in both files", $pkgstr, 1, $FH_HR);
      }
      #printf("HEYA $out_seq_A[$s] " . $out_seq_lidx_H{$out_seq_A[$s]} . " " . $exp_seq_lidx_H{$out_seq_A[$s]} . "\n");
    }
    
    open(DIFFOUT, ">", $diff_file) || ofile_FileOpenFailure($diff_file, $pkgstr, $sub_name, $!, "writing", $FH_HR);

    # for each sequence, compare the annotations
    my $lidx;        # counter over lines
    my $first_lidx;  # first line index of annotation for a sequence
    my $final_lidx;  # final line index of annotation for a sequence
    my %cur_out_H = ();    # key: feature line, value: current annotation in out file for that feature
    my %cur_exp_H = ();    # key: feature line, value: current annotation in exp file for that feature
    my %cur_exists_H = (); # key: feature line, value '1'
    my @cur_A = ();        # array of feature lines in order they were read

    for($s = 0; $s < $nseq; $s++) { 
      $seq = $out_seq_A[$s];
      #printf("\ns: $s\n");
      %cur_exists_H = ();
      @cur_A = ();

      # parse information from out_file
      %cur_out_H = ();
      $first_lidx = $out_seq_lidx_H{$seq} + 1; # first line after a sequence is the beginning of its annotation
      if($s < ($nseq-1)) { $final_lidx = $out_seq_lidx_H{$out_seq_A[($s+1)]} - 1; }
      else               { $final_lidx = scalar(@out_line_A) - 1; }
      my $fline = undef;
      my $cline = undef;
      my $cur_cline = "";
      #printf("OUT $first_lidx..$final_lidx\n");
      for($lidx = $first_lidx; $lidx <= $final_lidx; $lidx++) { 
        #printf("OUT line: $out_line_A[$lidx]\n");
        if($out_line_A[$lidx] =~ m/^\<?\d+/) { 
          # coordinate line
          $cline = $out_line_A[$lidx];
          $cur_cline .= $cline;
        }
        else { 
          # feature line
          $fline = $out_line_A[$lidx];
          $cur_out_H{$fline} = $cur_cline;
          if(! exists $cur_exists_H{$fline}) { 
            push(@cur_A, $fline);
            $cur_exists_H{$fline} = 1;
          }
          $cur_cline = "";
        }
      }
      
      # parse information from exp_file
      %cur_exp_H = ();
      $first_lidx = $exp_seq_lidx_H{$seq} + 1; # first line after a sequence is the beginning of its annotation
      if($s < ($nseq-1)) { $final_lidx = $exp_seq_lidx_H{$exp_seq_A[($s+1)]} - 1; }
      else               { $final_lidx = scalar(@exp_line_A) - 1; }
      $fline = undef;
      $cline = undef;
      $cur_cline = "";
      #printf("EXP $first_lidx..$final_lidx\n");
      for($lidx = $first_lidx; $lidx <= $final_lidx; $lidx++) { 
        #printf("EXP line: $exp_line_A[$lidx]\n");
        if($exp_line_A[$lidx] =~ m/^\<?\d+/) { 
          # coordinate line
          $cline = $exp_line_A[$lidx];
          $cur_cline .= $cline;
        }
        else { 
          # feature line
          $fline = $exp_line_A[$lidx];
          $cur_exp_H{$fline} = $cur_cline;
          if(! exists $cur_exists_H{$fline}) { 
            push(@cur_A, $fline);
            $cur_exists_H{$fline} = 1;
          }
          $cur_cline = "";
        }
      }

      # compare annotation from exp_file and out_file
      my $cur_ftr_nidentical  = 0; # number of features that are identical (all lines) between output and expected
      my $cur_ftr_ndiff       = 0; # number of features that are different (at least one line different) between output and expected
      my $cur_ftr_nout_only   = 0; # number of features that are only in output file
      my $cur_ftr_nexp_only   = 0; # number of features that are only in expected file
      my $cur_nftr            = 0; # number of features in the sequence
      my $cur_outstr          = ""; # output string

      my $cur_note_nidentical  = 0; # number of 'notes' that are identical (all lines) between output and expected
      my $cur_note_ndiff       = 0; # number of 'notes' that are different (at least one line different) between output and expected
      my $cur_note_nout_only   = 0; # number of 'notes' that are only in output file
      my $cur_note_nexp_only   = 0; # number of 'notes' that are only in expected file
      my $cur_nnote            = 0; # number of 'notes' in the sequence

      my $is_note = 0; # '1' if this line is a note, '0' if it is a feature

      foreach $fline (@cur_A) { 
        # determine if it is a 'note' or not, we treat them differently
        $is_note = ($fline =~ m/^\s+note/) ? 1 : 0;

        if($is_note) { 
          $cur_nnote++;
        }
        else { 
          $cur_nftr++;
        }

        if((! exists $cur_exp_H{$fline}) && (! exists $cur_out_H{$fline})) { 
          DNAORG_FAIL("ERROR in $sub_name, $fline does not exist in either exp or out", 1, $FH_HR);
        }
        elsif((exists $cur_exp_H{$fline}) && (! exists $cur_out_H{$fline})) { 
          if($is_note) { $cur_note_nexp_only++; }
          else         { $cur_ftr_nexp_only++; }
          $cur_outstr .= "EXP only: $fline$cur_exp_H{$fline}"; 
        }
        elsif((! exists $cur_exp_H{$fline}) && (exists $cur_out_H{$fline})) { 
          if($is_note) { $cur_note_nout_only++; }
          else         { $cur_ftr_nout_only++; }
          $cur_outstr .= "OUT only: $fline$cur_out_H{$fline}"; 
        }
        elsif($cur_exp_H{$fline} ne $cur_out_H{$fline}) { 
          if($is_note) { $cur_note_ndiff++; }
          else         { $cur_ftr_ndiff++; }
          if(! exists $cur_exp_H{$fline}) { 
            printf("exp does not exists $fline\n");
          }
          if(! exists $cur_out_H{$fline}) { 
            printf("out does not exists $fline\n");
          }
          $cur_outstr .= "DIFFERENT: " . $fline . "OUT:\n$cur_out_H{$fline}EXP:\n$cur_exp_H{$fline}"; 
        }
        else { 
          if($is_note) { $cur_note_nidentical++; }
          else         { $cur_ftr_nidentical++; }
        }
      }
      printf DIFFOUT ("%s %s %-50s %2d features [%2d %2d %2d %2d] %2d notes [%2d %2d %2d %2d]\n", 
                      ($cur_ftr_nidentical == $cur_nftr)   ? "FTR-IDENTICAL" : "FTR-DIFFERENT", 
                      ($cur_note_nidentical == $cur_nnote) ? "NOTE-IDENTICAL" : "NOTE-DIFFERENT", 
                      $seq,
                      $cur_nftr, $cur_ftr_nidentical, $cur_ftr_ndiff, $cur_ftr_nout_only, $cur_ftr_nexp_only, 
                      $cur_nnote, $cur_note_nidentical, $cur_note_ndiff, $cur_note_nout_only, $cur_note_nexp_only);
      if($cur_outstr ne "") { 
        printf DIFFOUT $cur_outstr;
      }
      if($cur_ftr_nidentical == $cur_nftr) { $tot_nseq_ftr_identical++; }
      if($cur_ftr_ndiff > 0)               { $tot_nseq_ftr_diff++; }
      if($cur_ftr_nout_only > 0)           { $tot_nseq_ftr_out_only++; }
      if($cur_ftr_nexp_only > 0)           { $tot_nseq_ftr_exp_only++; }

      if($cur_note_nidentical == $cur_nftr) { $tot_nseq_note_identical++; }
      if($cur_note_ndiff > 0)               { $tot_nseq_note_diff++; }
      if($cur_note_nout_only > 0)           { $tot_nseq_note_out_only++; }
      if($cur_note_nexp_only > 0)           { $tot_nseq_note_exp_only++; }
    }
  }

  printf DIFFOUT ("SUMMARY %5d sequences FEATURES: [identical:%5d;  different:%5d;  out-only:%5d;  exp-only:%5d;] NOTES: [identical:%5d;  different:%5d;  out-only:%5d;  exp-only:%5d;]\n", $nseq,
                  $tot_nseq_ftr_identical, $tot_nseq_ftr_diff, $tot_nseq_ftr_out_only, $tot_nseq_ftr_exp_only, 
                  $tot_nseq_note_identical, $tot_nseq_note_diff, $tot_nseq_note_out_only, $tot_nseq_note_exp_only);

  close(DIFFOUT);
  return;
}

####################################################################
# the next line is critical, a perl module must return a true value
return 1;
####################################################################
