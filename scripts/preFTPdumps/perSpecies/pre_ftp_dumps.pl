#!/usr/bin/env perl
#
# do the collected per-species dumps for the build
# these go into the REPORTS directory
#
#  it runs scripts that generate one output file per species
#  in the respective SPECIES/REPORTS/ directory
#
#  it will by default overwrite existing output files and warn


use lib $ENV{CVS_DIR};
use lib "$ENV{CVS_DIR}/Modules/Third_party";

use Wormbase;
use Log_files;
use LSF RaiseError => 0, PrintError => 1, PrintOutput => 0;
use LSF::JobManager;

use Getopt::Long;

use strict;

my ($store,$debug,$test,$database,@species);
GetOptions(
     'store=s'    => \$store,
     'debug=s'    => \$debug,
     'test'       => \$test,
     'species=s@' => \@species,
)||die(@!);


# WormBase build stanza
my $wormbase;
if ($store) { 
  $wormbase = Storable::retrieve($store) or croak("Can't restore wormbase from $store\n");
}else{
  $wormbase = Wormbase->new( -debug => $debug, 
                             -test => $test);
}


my @script_conf = (
  { script => 'dump_species_functional_descriptions.pl', output => 'functional_descriptions.txt', all => 1 },
  { script => 'dump_protein_domains.pl',                 output => 'protein_domains.csv',         all => 1 },
  { script => 'dump_species_orthologs.pl',               output => 'orthologs.txt',               all => 1 },
  { script => 'dump_confirmed_genes.pl',                 output => 'confirmed_genes.fa',          all => 1 },
  { script => 'dump_species_gene_interactions.pl',       output => 'interactions.txt'                },
  { script => 'dump_interpolated.pl',                    output => 'interpolated_clones.txt'         },
  { script => 'dump_promoters.pl',                       output => 'potential_promotors.fa'          },
  { script => 'dump_resource_gene_ids.pl',               output => 'resource_gene_ids.txt'           },
  { script => 'dump_swissprot.pl',                       output => 'swissprot.txt'                   },
  { script => 'dump_ko.pl',                              output => 'knockout_consortium_alleles.xml' },
  { script => 'dump_cdna2orf.pl',                        output => 'cdna2orf.txt'                    },
  { script => 'dump_pcr_list.pl',                        output => 'pcr_product2gene.txt'            },
  { script => 'dump_geneid_list.pl',                     output => 'geneIDs.txt',                 all => 1 },
  { script => 'dump_molecules.pl',                       output => 'molecules.ace'                   },
  { script => 'dump_geneid_list.pl',                     output => 'geneOtherIDs.txt', options => "-other", all=>1 },
);




# global aspects
my $log = Log_files->make_build_log($wormbase);
my $defaultMem = 4000;
my $lsf = LSF::JobManager->new(-M => $defaultMem, 
                               -R => "select[mem>$defaultMem] rusage[mem=$defaultMem]",
                               -J => 'perSpeciesDumps', 
                               -e => '/dev/null',
                               -o => '/dev/null'
                              );

my %files_to_check;
my %core_species = $wormbase->species_accessors;

foreach my $wb ($wormbase, values %core_species ) {
  my $spe = $wb->species;

  next if @species and not grep { $_ eq $spe } @species;

  my $report_dir = $wb->reports;
  
  foreach my $item (@script_conf) {
    my $script = $item->{script};
    my $output = $item->{output};
    # note that all scripts need to be run against autoace, because only that has all
    # of the necessary objects filled in
    my $options = $item->{options} . " -database " . $wormbase->autoace;

    next unless $item->{all} or $spe eq 'elegans';
    next unless &check_script($script);

    my $outfile = "$report_dir/${spe}.${output}";
    &clean_previous_output($outfile);
    &queue_script($wb,$script, $outfile, $options);
    push @{$files_to_check{$script}}, $outfile;
  }  
}

$log->write_to("Waiting for LSF jobs to finish.\n");
$lsf->wait_all_children( history => 1 );
for my $job ( $lsf->jobs ) {
  if ($job->history->exit_status != 0) {
    $log->write_to("WARNING: Job $job (" . $job->history->command . ") exited non zero: " . $job->history->exit_status . "\n");
  }
}
$lsf->clear;


foreach my $script (keys %files_to_check) {
  foreach my $file (@{$files_to_check{$script}}) {
    if (-e $file){
      my $size = -s $file;
      if (-s $file){
        $log->write_to("OK: $script => $file ($size bytes)\n");
      } else{
        $log->write_to("WARNING: $script created an empty $file\n");
      }
    } else{
      $log->write_to("WARNING: $script didn't create $file\n");
    }
  }
}

$log->mail;

# LSF submit $script
sub queue_script {
  my ($wb,$script, $outf, $opts) = @_;
  
  my $cmd = "preFTPdumps/perSpecies/$script";
  $cmd .= " -outfile $outf";
  if (defined $opts) {
    $cmd .= " $opts";
  }
  $cmd = $wb->build_cmd($cmd);
  $lsf->submit($cmd);
}

# basically try to delete $file
sub clean_previous_output{
  my ($file) = @_;
  if (-e $file){
    unlink $file;
    $log->write_to("cleaning up $file from a previous run\n");
    $log->write_to("can't clean up $file, check permissions\n") if -e $file;
  }
}

# assuming CVS_DIR/scripts/preFTPdumps
sub check_script{
  my ($script) = @_;
  my $path = $ENV{CVS_DIR}."/preFTPdumps/perSpecies/$script";
  if (-e $path){
    return 1;
  } else {
    $log->write_to("ERROR: can't find $path\n");
    return undef;
  }
}


