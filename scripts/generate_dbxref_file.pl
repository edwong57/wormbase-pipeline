#!/usr/bin/env perl
#
# generate_dbxrefs_file.pl
#
# Generates a table of xrefs that should be generally useful for
# Uniprot, ENA and Ensembl
# 
#  Last updated on: $Date: 2012-03-09 16:14:44 $
#  Last updated by: $Author: klh $

use strict;
use Getopt::Long;
use Storable;

use lib $ENV{'CVS_DIR'};
use Bio::SeqIO;
use Wormbase;

my ($test,
    $debug,
    $store,
    $species,
    $database,
    $wormbase,
    $outfile,
    );

GetOptions (
  "test"            => \$test,
  "debug=s"         => \$debug,
  "store:s"         => \$store,
  "species:s"       => \$species,
  "database:s"      => \$database,
  "outfile:s"       => \$outfile,
    );


if( $store ) {
  $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
}
else {
  $wormbase = Wormbase->new( -debug    => $debug,
                             -test     => $test,
                             -organism => $species,
                             -autoace  => $database,
      );
}

# establish log file.
my $log = Log_files->make_build_log($wormbase);

$species = $wormbase->species;
my $tace = $wormbase->tace;
my $full_species_name = $wormbase->full_name;
my $dbdir = ($database) ? $database : $wormbase->autoace;
$outfile = $wormbase->acefiles . "/DBXREFs.txt" if not defined $outfile;

my (%wbgene, %gene, %cds, %transcds,%clone2acc, $out_fh);

$wormbase->FetchData('clone2accession', \%clone2acc, "$dbdir/COMMON_DATA");

$log->write_to("Generating protein-coding table\n");

my $query = &generate_coding_query($species);
my $command = "Table-maker -p $query\nquit\n";

open (TACE, "echo '$command' | $tace $dbdir |");
while (<TACE>) {
  chomp; s/\"//g;

  my ($cds, $gene, $trans, $prot, $clone, $pid, $pid_version, $uniprot ) = split(/\t/, $_);

  next if $gene !~ /^WBGene/;

  $wbgene{$gene}->{cds}->{$cds} = 1;
  $wbgene{$gene}->{transcript}->{$trans} = 1;
  $transcds{$trans} = $cds;
  
  $prot =~ s/\S+://;
  $cds{$cds}->{protein} = $prot;
  if ($clone and $pid and $pid_version) {
    $cds{$cds}->{pid}->{"$clone:$pid:$pid_version"} = 1;
  }
  $cds{$cds}->{uniprot} = $uniprot if $uniprot;

}
close TACE;
unlink $query;

foreach my $class ('RNA_genes', 'pseudogenes') {
  $log->write_to("Generating non-coding $class table\n");

  $query = &generate_noncoding_query($species, $class);
  $command = "Table-maker -p $query\nquit\n";
  open (TACE, "echo '$command' | $tace $dbdir |");
  while (<TACE>) {
    chomp; s/\"//g;
    
    my ($trans, $gene, $parent ) = split(/\t/, $_);
    next if $gene !~ /^WBGene/;
            
    $wbgene{$gene}->{transcript}->{$trans} = 1;
    $wbgene{$gene}->{sequence} = $parent;
  }
  close TACE;
  unlink $query;
}  


$log->write_to("Generating gene table\n");

$query = &generate_gene_query($full_species_name);
$command = "Table-maker -p $query\nquit\n";

open (TACE, "echo '$command' | $tace $dbdir |");
while (<TACE>) {
  chomp; s/\"//g;
  
  my ($wbgene, $sequence_name, $cgc_name) = split(/\t/, $_);
  next if $wbgene !~ /^WBGene/;

  $gene{$sequence_name}->{$wbgene} = 1;
  if ($cgc_name) {
    $wbgene{$wbgene}->{cgc} = $cgc_name;
  }      
}
close TACE;
$query;

open($out_fh, ">$outfile") or $log->log_and_die("Could not open $outfile for writing\n");

foreach my $g (sort keys %gene) {
  foreach my $wbgeneid (keys %{$gene{$g}}) {
    my $cgc_name = (exists $wbgene{$wbgeneid}->{cgc}) ? $wbgene{$wbgeneid}->{cgc} : ".";
    foreach my $trans (keys %{$wbgene{$wbgeneid}->{transcript}}) {
      my ($cds, $pepid, $uniprot, @pid_list);
      
      if (exists $transcds{$trans}) {
        # coding
        $cds = $transcds{$trans};        
        $pepid = $cds{$cds}->{protein};
        
        if (exists $cds{$cds}->{pid}) {
          foreach my $str (keys %{$cds{$cds}->{pid}}) {
            my ($clone, $pid) = split(/:/, $str);
            push @pid_list, [$clone2acc{$clone}, $pid];
          }
        } else {
          @pid_list = (['.', '.']);
        }
        
        $uniprot = (exists $cds{$cds}->{uniprot}) ? $cds{$cds}->{uniprot} : ".";

      } else {
        ($uniprot, $pepid) = (".",".");
        my ($pid, $clone) = (".", ".", ".");

        if (exists $wbgene{$wbgeneid}->{sequence}) {
          $clone = $wbgene{$wbgeneid}->{sequence};
          if (exists $clone2acc{$clone}) {
            $clone = $clone2acc{$clone};
          } else {
            $clone = "$clone:NOACC";
          }
        }
        @pid_list =  ([$clone, $pid]);
      }

      foreach my $pidpair (@pid_list) {
        my ($clone, $pid) = @$pidpair;
        
        print $out_fh join("\t", $g, 
                           $wbgeneid, 
                           $cgc_name, 
                           $trans,
                           $pepid,
                           $clone,
                           $pid, 
                           $uniprot), "\n";
      }
    }
  }
}

close($out_fh) or $log->log_and_die("Could not cleanly close output file\n");

$log->mail();
exit(0);

##########################################
sub generate_coding_query {
  my ($species) = @_;

  my $tmdef = "/tmp/cod_tmquery.$$.def";
  open my $qfh, ">$tmdef" or 
      $log->log_and_die("Could not open $tmdef for writing\n");  

  my $tablemaker_template = <<"EOF";


Sortcolumn 1

Colonne 1 
Width 12 
Optional 
Visible 
Class 
Class ${species}_CDS 
From 1 
 
Colonne 2 
Width 12 
Optional 
Visible 
Class 
Class Gene 
From 1 
Tag Gene 
 
Colonne 3 
Width 12 
Optional 
Visible 
Class 
Class Transcript 
From 1 
Tag Corresponding_transcript 
 
Colonne 4
Width 12 
Optional 
Visible 
Class 
Class Protein
From 1 
Tag Corresponding_protein

Colonne 5
Width 12 
Optional 
Visible 
Class 
Class Sequence 
From 1 
Tag Protein_id 
 
Colonne 6 
Width 12 
Optional 
Visible 
Text 
Right_of 5 
Tag  HERE  
 
Colonne 7 
Width 12 
Optional 
Visible 
Integer 
Right_of 6 
Tag  HERE  
 
Colonne 8 
Width 12 
Optional 
Hidden 
Class 
Class Database 
From 1 
Tag Database 
Condition UniProt
 
Colonne 9 
Width 12 
Optional 
Hidden 
Class 
Class Database_field 
Right_of 8 
Tag  HERE  
Condition UniProtAcc
 
Colonne 10 
Width 12 
Optional 
Visible 
Class 
Class Accession_number 
Right_of 9 
Tag  HERE  

EOF

  print $qfh $tablemaker_template;
  return $tmdef;


}


sub generate_noncoding_query {
  my ($species, $class) = @_;

  my $tmdef = "/tmp/nc_tmquery.$$.def";
  open my $qfh, ">$tmdef" or 
      $log->log_and_die("Could not open $tmdef for writing\n");  

  my $condition = "";

  my $tablemaker_template = <<"EOF";

Sortcolumn 1

Colonne 1 
Width 12 
Optional 
Visible 
Class 
Class ${species}_${class}
From 1 
 
Colonne 2 
Width 12 
Optional 
Visible 
Class 
Class Gene 
From 1 
Tag Gene 
 
Colonne 3 
Width 12 
Optional 
Visible 
Class 
Class Sequence 
From 1 
Tag Sequence 
 
EOF

  print $qfh $tablemaker_template;
  return $tmdef;

}



sub generate_gene_query {
  my ($full_species) = @_;

  my $tmdef = "/tmp/gene_tmquery.$$.def";
  open my $qfh, ">$tmdef" or 
      $log->log_and_die("Could not open $tmdef for writing\n");  

  my $condition = "";

  my $tablemaker_template = <<"EOF";

Sortcolumn 1

Colonne 1 
Width 12 
Optional 
Visible 
Class 
Class Gene 
From 1 
Condition Species = "$full_species"
 
Colonne 2 
Width 12 
Mandatory 
Visible 
Class 
Class Gene_name 
From 1 
Tag Sequence_name 
 
Colonne 3 
Width 12 
Optional 
Visible 
Class 
Class Gene_name 
From 1 
Tag CGC_name 
 
EOF

  print $qfh $tablemaker_template;
  return $tmdef;


}
__END__
