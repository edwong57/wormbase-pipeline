#!/usr/local/bin/perl5.8.0 -w
#
# update_web_gene_names.pl
#
# completely rewritten by Keith Bradnam from list_loci_designations
#
# Last updated by: $Author: krb $     
# Last updated on: $Date: 2003-06-03 12:04:13 $      
#
# This script should be run under a cron job and simply update the webpages that show
# current gene names and sequence connections.  Gets info from geneace.  


#################################################################################
# Initialise variables                                                          #
#################################################################################

use strict;
use lib '/wormsrv2/scripts/';
use Wormbase;
use Ace;
use Carp;

##############################
# Script variables (run)     #
##############################

my $tace  = &tace;
my $www = "/nfs/WWWdev/htdocs/Projects/C_elegans/LOCI";

my $db = Ace->connect(-path  => "/wormsrv1/geneace",
                      -program =>$tace) || do { print "Connection failure: ",Ace->error; croak();};

# Get all Loci
my @loci = $db->fetch(-query=>"Find Locus WHERE Gene AND \(Species = \"Caenorhabditis elegans\"\)");


# Need to open first file in series to make this all work
open (HTML, ">$www/loci_designations_a.shtml") || croak "Couldn't open file for writing to\n";
# Text file for simpler handling
open (TEXT, ">$www/loci_all.txt") || croak "Couldn't open text file for writing to\n";
my $prev_initial = "a";


my $line = 0;

foreach my $locus (@loci){
  my $initial = substr($locus,0,1);
  $initial = lc($initial);
  if ($initial ne $prev_initial){
    close(HTML);
    open (HTML, ">$www/loci_designations_$initial.shtml") || croak "Couldn't open file for writing to\n";
    $prev_initial = $initial;
  }

  if (($line % 2) == 0) { 
      print HTML "<TR BGCOLOR=\"lightblue\">\n";
  }
  else {
         print HTML "<TR BGCOLOR=\"white\">\n";
  }
  
  print HTML "<TD><A HREF=\"http://www.wormbase.org/db/gene/gene?name=${locus}\">${locus}</a></TD>";
  print TEXT "$locus,";
  # Get sequence connections
  if(defined($locus->at('Molecular_information.Genomic_sequence'))){
    my @genomic_sequences = $locus->Genomic_sequence;
    print HTML "<TD>";
    foreach my $i (@genomic_sequences){
      print HTML "<A HREF=\"http://www.wormbase.org/db/seq/sequence?name=${i}\">${i}</a> ";
      print TEXT "$i ";
    }
    print HTML "</TD>";
  }
  else{
    print HTML "<TD>&nbsp</TD>";
  }
  print TEXT ",";


  #Get other names
  if(defined($locus->at('Name.Other_name'))){
    my @other_names = $locus->Other_name;
    print HTML "<TD>";
    foreach my $i (@other_names){
      print HTML "${i} ";
      print TEXT "$i ";
    }
    print HTML "</TD>";
  }
  else{
    print HTML "<TD>&nbsp</TD>";
  }
  print TEXT ",";

  #CGC approved?
  if(defined($locus->at('Type.Gene.CGC_approved'))){
    print HTML "<TD>CGC approved</TD>\n";
    print TEXT "CGC approved"
  }
  else{
    print HTML"<TD>&nbsp<TD>\n";
  }

  $line++;
  print HTML "</TR>\n";
  print TEXT "\n";
  $locus->DESTROY();
}

close(HTML);  

$db->close;

my $rundate    = `date +%y%m%d`; chomp $rundate;
my $log = "/tmp/update_web_gene_names";

open(LOG,">$log") || carp "Couldn't open tmp log file\n";

print LOG "Running update_web_gene_names.pl on $rundate\n\n";

# now update pages using webpublish
chdir($www) || print LOG "Couldn't run chdir\n";

system("/usr/local/bin/webpublish -f -q *.shtml") && print LOG "Couldn't run webpublish on html files\n";
system("/usr/local/bin/webpublish -f -q *.txt") && print LOG "Couldn't run webpublish on text file\n";


&mail_maintainer("update_web_gene_names.pl","krb\@sanger.ac.uk","$log");

close(LOG);
exit(0);


__END__

=pod

=head1 NAME - update_web_gene_names.pl

=back

=head1 USAGE

=over 4

=item update_web_gene_names.pl 

Simply takes the latest set of gene names in geneace and writes to the development web site
a set of HTML pages (one for each letter of the alphabet) containing all gene names starting
with that letter.  Makes these tables hyperlinked to WormBase and also includes other names
and sequence connections.

When script finishes it copies across to the live web site.  This script should normally be
run every night on a cron job.

=back

=head2 camcheck.pl MANDATORY arguments:

=over 4

=item none

=back

=head2 camcheck.pl OPTIONAL arguments:

=over 4

=item none

=back


=head1 AUTHOR - Keith Bradnam

Email krb@sanger.ac.uk

=cut
