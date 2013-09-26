#!/usr/bin/env perl
#
# overload_gff_gene.pl
#
# Adds interpolated map positions and other information to gene and allele lines
#
# Last updated by: $Author: klh $
# Last updated on: $Date: 2013-09-26 11:49:18 $


use strict;                                      
use lib $ENV{CVS_DIR};
use Wormbase;
use Getopt::Long;
use Log_files;
use Storable;
use Ace;
use File::Copy;

my ($help, $debug, $test, $store, $wormbase, $species);
my ( $gff3, $infile, $outfile, $changed_lines);

GetOptions (
  "debug=s"   => \$debug,
  "test"      => \$test,
  "store:s"   => \$store,
  "species:s" => \$species,
  "gff3"      => \$gff3,
  "infile:s"  => \$infile,
  "outfile:s" => \$outfile,
    );

if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug    => $debug,
                             -test     => $test,
                             -organism => $species
			     );
}

# establish log file.
my $log = Log_files->make_build_log($wormbase);

if (not defined $infile or not defined $outfile) { 
  $log->log_and_die("You must define -infile and -outfile\n");
}
my $species_full = $wormbase->full_name;

open(my $gff_in_fh, $infile) or $log->log_and_die("Could not open $infile for reading\n");
open(my $gff_out_fh, ">$outfile") or $log->log_and_die("Could not open $outfile for writing\n");  

my ($locus_h, $sequence_name_h, $biotype_h) = &get_data();

while (<$gff_in_fh>) {
  if (/^\#/) {
    print $gff_out_fh $_;
    next;
  }
  chomp;
  my @f = split(/\t/, $_);

  my $orig_attr = $f[8];

  my ($gene, $changed_source);

  if ($f[2] eq 'gene' and ($f[1] eq 'gene' or $f[1] eq 'WormBase')) {


    if ($gff3) {
      my ($first) = split(/;/, $f[8]);
      ($gene) = $first =~ /ID=Gene:(\S+)/;

      $f[8] .= ";locus=$locus_h->{$gene}" 
          if exists $locus_h->{$gene} and $f[8] !~ /locus/;

      $f[8] .= ";sequence_name=$sequence_name_h->{$gene}" 
          if exists $sequence_name_h->{$gene} and $f[8] !~ /sequence_name/;

      $f[8] .= ";biotype=$biotype_h->{$gene}" 
          if exists $biotype_h->{$gene} and $f[8] !~ /biotype/;
    } else {
      ($gene) = $f[8] =~ /Gene\s+\"(\S+)\"/;

      $f[8] .= " ; Locus \"$locus_h->{$gene}\"" 
          if exists $locus_h->{$gene} and $f[8] !~ /Locus/;

      $f[8] .= " ; Sequence_name \"$sequence_name_h->{$gene}\"" 
          if exists $sequence_name_h->{$gene} and $f[8] !~ /Sequence_name/;

      $f[8] .= " ; Biotype\"$biotype_h->{$gene}\"" 
          if exists $biotype_h->{$gene} and $f[8] !~ /Biotype/;
    }
    
    if ($biotype_h->{$gene} eq 'transposon') {
      $f[2] = 'transposon_gene';
      $changed_source = 1;
    }
  }

  $changed_lines++ if $orig_attr ne $f[8] or $changed_source;
  print $gff_out_fh join("\t", @f), "\n";
}
close($gff_out_fh) or $log->log_and_die("Could not close $outfile after writing\n");
$log->write_to("Finished processing : $changed_lines lines modified\n");
$log->mail();
exit(0);

#######################
sub get_data {
  my $db = Ace->connect('-path' => $wormbase->autoace) 
      or $log->log_and_die("cant open Ace connection to db\n".Ace->error."\n");

  my (%locus, %sequence_name, %biotype);
  
  # get the CGC/WGN name of the Genes
  $log->write_to("Reading Gene info\n");
  
  my $query = "find Gene where Species = \"$species_full\"";
  my $genes = $db->fetch_many('-query' => $query);
  while (my $gene = $genes->next){
    if ($gene->CGC_name) {        
      $locus{$gene->name} = $gene->CGC_name;
    }
    if ($gene->Sequence_name) {
      $sequence_name{$gene->name} = $gene->Sequence_name;
    }
    if ($gene->Corresponding_CDS) {
      if ($gene->Corresponding_Transposon) {
        $biotype{$gene} = 'transposon';
      } else {
        $biotype{$gene}= 'protein_coding';     
      }
    } elsif ($gene->Corresponding_pseudogene) {
      $biotype{$gene} = "pseudogene";
    } elsif ($gene->Corresponding_transcript) {
      my %ttypes;
      foreach my $tr ($gene->Corresponding_transcript) {
        if ($tr->Transcript) {
          $ttypes{$tr->Transcript} = 1;
        }
      }
      if (not scalar(keys %ttypes)) {
        $log->log_and_die("Could not obtain biotype for gene $gene\n");
      } 
      my @types = sort keys %ttypes;
      $biotype{$gene} = join(",", @types);
    }
  }

  return (\%locus, \%sequence_name, \%biotype);
}
