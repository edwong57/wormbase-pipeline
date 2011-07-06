#!/software/bin/perl -w
#
# align_RNASeq.pl
#
# script to process the RNASeq data using Tophat and Cufflinks , etc.
#
# currently we have for elegans:
#
# Waterston elegans RNASeq data:
#
# SRX001872 SRX001875 SRX004865 SRX004868 SRX008138 SRX008144 SRX014007
# SRX014010 SRX036882 SRX036970 SRX037198 SRX037288 SRX001873 SRX004863
# SRX004866 SRX004869 SRX008139 SRX011569 SRX014008 SRX035162 SRX036967
# SRX037186 SRX037199 SRX001874 SRX004864 SRX004867 SRX008136 SRX008140
# SRX014006 SRX014009 SRX036881 SRX036969 SRX037197 SRX037200
#
#
## Andy Fraser's Lab 
#     
# SRX007069	     SRX007170	     SRX007171	     SRX007172	     SRX007173	     
#
## Andy Fire's Lab
#	     
# SRX028190	     SRX028191	     SRX028192	     SRX028193	     SRX028194	     
# SRX028195	     SRX028196	     SRX028197	     SRX028198	     SRX028199	     
# SRX028200	     SRX028202	     SRX028203	     SRX028204
#
#
# and for brugia:
#
# some data taken directly from Matt Berriman group's FTP server
#
#
# and for remanei:
#
# SRX052082 SRX052083
#
# and for briggsae:
#
# SRX052079 SRX052081 SRX053351


# Perl should be set to:
# alias perl /software/bin/perl
# otherwise it can't find LSF.pm

# Run this after TSL Features have been mapped in the Build.
# Run on farm-login2 as:
# bsub -I -q basement align_RNASeq.pl -noalign
#
# omit the '-noalign' if this is a frozen release and a fresh alignment will be done
# add '-check' if the run died and is being resumed
# add '-species' to run on a non-elegans Build
#
# bsub -I -e /nfs/wormpub/BUILD/autoace/logs/align.err -o /nfs/wormpub/BUILD/autoace/logs/align.out -q basement  align_RNASeq.pl [-noalign] [-check] [-species $SPECIES]


# by Gary Williams
#
# Last updated by: $Author: gw3 $
# Last updated on: $Date: 2011-07-04 12:37:15 $

#################################################################################
# Initialise variables                                                          #
#################################################################################

use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Storable;
use Log_files;
use LSF RaiseError => 0, PrintError => 1, PrintOutput => 0;
use LSF::JobManager;
#use Ace;
use Coords_converter;
use GDBM_File; # for tied hash



##############################
# command-line options       #
##############################


my ($test, $store, $debug, $species, $verbose, $expt, $noalign, $check, $solexa, $illumina, $database, $nogtf, $norawjuncs);
GetOptions (
	    "test"               => \$test,
	    "store:s"            => \$store,
	    "debug:s"            => \$debug,
	    "verbose"            => \$verbose,
	    "database:s"         => \$database, # acedb database to use for GTF, splice junctions and TSL Features
	    "species:s"		 => \$species,  # set species explicitly
	    "noalign"            => \$noalign,  # do not run tophat to align unless the old BAM file is missing
	    "check"              => \$check,    # in each experiment, check to see if tophat/cufflinks worked - if not repeat them
	    "nogtf"              => \$nogtf,    # don't use the GTF file of existing gene models to create the predicted gene models
	    "norawjuncs"         => \$norawjuncs,  # don't use the raw junctions file of splice hints (for example in a new brugia assembly)
	    "solexa"             => \$solexa,   # reads have solexa quality scores, not phred + 33 scores
	    "expt:s"             => \$expt,     # do the alignment etc. for this experiment
	    "illumina"           => \$illumina, # read have illumina GA-Pipeline 1.3 quality scores, not phred + 33 scores
	   );

my $wormbase;
if( $store ) {
  $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
			     -test    => $test,
			     -organism => $species
			   );
}

my $log = Log_files->make_build_log( $wormbase );

$species = $wormbase->species;
$log->write_to("Processing RNASeq data for $species\n");


##########################################
# Data to be processed
##########################################

my $currentdb = $wormbase->database('current');
my $dbdir  = $wormbase->autoace;                                     # Database path
$database = $dbdir unless $database;
#$database = $currentdb unless $database;
$species = $wormbase->species;                          # set the species if it was given

# global variables
my $coords;
my $status;

# SRP000401  Deep sequencing of the Caenorhabditis elegans transcriptome using RNA isolated from various developmental stages under various experimental conditions RW0001
#


# quality score description in: http://en.wikipedia.org/wiki/FASTQ_format
my %expts;

if ($species eq 'elegans') {

  %expts = ( # key= SRA 'SRX' experiment ID, values = [Analysis ID, quality score metric]

#	     SRX001872  => ["RNASeq_Hillier.L2_larva", 'phred'], # needs a lot of memory to run tophat
	     SRX001873  => ["RNASeq_Hillier.Young_Adult", 'phred'],
	     SRX001874  => ["RNASeq_Hillier.L4_larva", 'phred'],
	     SRX001875  => ["RNASeq_Hillier.L3_larva", 'phred'],

	     SRX004863  => ["RNASeq_Hillier.early_embryo_Replicate3", 'phred'], 
	     SRX004864  => ["RNASeq_Hillier.early_embryo", 'solexa'], # solexa
	     SRX004865  => ["RNASeq_Hillier.late_embryo", 'phred'],
	     SRX004866  => ["RNASeq_Hillier.late_embryo-Replicate1", 'solexa'], # SRR016678 is phred - the other three are solexa
	     SRX004867  => ["RNASeq_Hillier.L1_larva", 'solexa'], # solexa - paired end reads
	     SRX004868  => ["RNASeq_Hillier.L4_larva_Male", 'solexa'], # solexa
	     SRX004869  => ["RNASeq_Hillier.L1_larva_lin-35", 'solexa'], # SRR016691 and SRR016690 are phred, the other two are solexa

 	     SRX008136  => ["RNASeq_Hillier.Adult_spe-9", 'phred'], # phred, despite what the docs say
 	     SRX008138  => ["RNASeq_Hillier.dauer_daf-2", 'phred'], # phred, despite what the docs say
 	     SRX008139  => ["RNASeq_Hillier.dauer_entry_daf-2", 'phred'], # phred, despite what the docs say
 	     SRX008140  => ["RNASeq_Hillier.dauer_exit_daf-2", 'phred'], # phred, despite what the docs say
 	     SRX008144  => ["RNASeq_Hillier.L4_Larva_Replicate1", 'phred'], # phred, despite what the docs say

 	     SRX011569  => ["RNASeq_Hillier.embryo_him-8", 'phred'], # phred, despite what the docs say

 	     SRX014006  => ["RNASeq_Hillier.young_adult_Harposporium", 'phred'], # phred, despite what the docs say
 	     SRX014007  => ["RNASeq_Hillier.young_adult_Harposporium_control", 'phred'], # phred, despite what the docs say
 	     SRX014008  => ["RNASeq_Hillier.young_adult_S_macescens", 'phred'], # phred, despite what the docs say
 	     SRX014009  => ["RNASeq_Hillier.young_adult_S_macescens_control", 'phred'], # phred, despite what the docs say
 	     SRX014010  => ["RNASeq_Hillier.L4_larva_JK1107", 'phred'], # phred, despite what the docs say

 	     SRX035162  => ["RNASeq_Hillier.adult_D_coniospora_12hrs", 'phred'], # 76 bp reads

 	     SRX036967  => ["RNASeq_Hillier.adult_D_coniospora_control", 'phred'], # 76 bp reads

 	     SRX036881  => ["RNASeq_Hillier.L3_larva_Replicate1", 'phred'], # 76 bp reads
 	     SRX036882  => ["RNASeq_Hillier.adult_D_coniospora_5hrs", 'phred'], # 76 bp reads

 	     SRX036969  => ["RNASeq_Hillier.adult_E_faecalis", 'phred'], # 76 bp reads
 	     SRX036970  => ["RNASeq_Hillier.adult_P_luminescens", 'phred'], # 76 bp reads

 	     SRX037186  => ["RNASeq_Hillier.early_embryo_Replicate2", 'phred'], # 76 bp reads
 	     SRX037197  => ["RNASeq_Hillier.early_embryo_Replicate1", 'phred'],
 	     SRX037198  => ["RNASeq_Hillier.embryo_Male_him-8-Replicate1", 'phred'], # 76 bp reads
 	     SRX037199  => ["RNASeq_Hillier.dauer_exit_daf-2-Replicate1", 'phred'], # 76 bp reads
 	     SRX037200  => ["RNASeq_Hillier.L4_larva_JK1107_Replicate1", 'phred'], # 76 bp reads

 	     SRX037288  => ["RNASeq_Hillier.L1_larva-Replicate1", 'phred'], # 76 bp reads

 	     SRX047446  => ["RNASeq_Hillier.late_embryo_Replicate2", 'phred'], # 76 bp reads
 	     SRX047469  => ["RNASeq_Hillier.L4_larva_Male_Replicate1", 'phred'], # 76 bp reads
 	     SRX047470  => ["RNASeq_Hillier.dauer_entry_daf-2_Replicate1", 'phred'], # 76 bp reads
 	     #SRX047635  => 0, # no runs done
 	     SRX047653  => ["RNASeq_Hillier.L2_larva_Replicate1", 'phred'], # 76 bp reads
 	     SRX047787  => ["RNASeq_Hillier.Young_Adult_Replicate1", 'phred'], # 76 bp reads
	     
## Andy Fraser's Lab 
	     
	     SRX007069   => ["RNASeq.Fraser.L4_larva", 'phred'], # N2, L4 larva
	     SRX007170   => ["RNASeq.Fraser.adult", 'phred'], # N2, Young Adult
	     SRX007171   => ["RNASeq.Fraser.smg-1_L4_larva", 'phred'], # smg-1, L4 larva
	     SRX007172   => ["RNASeq.Fraser.smg-1_adult", 'phred'], # smg-1, Young Adult
	     SRX007173   => ["RNASeq.Fraser.all_stages", 'phred'], # N2, all_stages, paired end reads
	     
## Andy Fire's Lab
	     
	     SRX028190   => ["RNASeq.Fire.all_stages_dsDNALigSeq", 'phred'], # GSM577107: N2_mixed-stage_dsDNALigSeq
	     SRX028191   => ["RNASeq.Fire.all_stages_ssRNALigSeq", 'phred'], # GSM577108: N2_mixed-stage_ssRNALigSeq
	     SRX028192   => ["RNASeq.Fire.fem-3_dsDNALigSeq", 'phred'],      # GSM577110: fem-3_dsDNALigSeq
	     SRX028193   => ["RNASeq.Fire.fem-1_dsDNALigSeq", 'phred'],      # GSM577111: fem-1_dsDNALigSeq
	     SRX028194   => ["RNASeq.Fire.him-8_dsDNALigSeq", 'phred'],      # GSM577112: him-8_dsDNALigSeq
	     SRX028195   => ["RNASeq.Fire.him-8_ssRNALigSeq", 'phred'],      # GSM577113: him-8_ssRNALigSeq
	     SRX028196   => ["RNASeq.Fire.rrf-3_him-8_ssRNALigSeq", 'phred'], # GSM577114: rrf-3_him-8_ssRNALigSeq
	     SRX028197   => ["RNASeq.Fire.L1_larva_ssRNALigSeq", 'phred'],   # GSM577115: N2_L1_ssRNALigSeq
	     SRX028198   => ["RNASeq.Fire.L2_larva_ssRNALigSeq", 'phred'],   # GSM577116: N2_L2_ssRNALigSeq
	     SRX028199   => ["RNASeq.Fire.L3_larva_ssRNALigSeq", 'phred'],   # GSM577117: N2_L3_ssRNALigSeq
	     SRX028200   => ["RNASeq.Fire.L4_larva_ssRNALigSeq", 'phred'],   # GSM577118: N2_L4_ssRNALigSeq
	     SRX028201   => ["RNASeq.Fire.L1_larva_CircLigSeq", 'phred'],    # GSM577119: N2_L1_CircLigSeq
	     SRX028202   => ["RNASeq.Fire.L2_larva_CircLigSeq", 'phred'],    # GSM577120: N2_L2_CircLigSeq
	     SRX028203   => ["RNASeq.Fire.L3_larva_CircLigSeq", 'phred'],    # GSM577121: N2_L3_CircLigSeq
	     SRX028204   => ["RNASeq.Fire.all_stages_polysomes", 'phred'],   # GSM577122: N2_mixed-stage_polysomes

	    );
} elsif ($species eq 'brugia') {

# data from Matt Berriman's group.
# /nfs/disk69/ftp/pub4/pathogens/Brugia/malayi
#
# Seven libraries have thus far been sequenced :-
#
# Adult male
# Adult female
# mature microfillariae
# immature microfillariae
# L3 stage
# L4 stage
# eggs embryos
#
# The directory is structured as follows
#
# DATA : contains the raw sequence data in gzipped fastq files and is
# organised as follows
#
# - DATA/SLX/library_name/lane/lane_1.fastq.gz - first of the pair
# - DATA/SLX/library_name/lane/lane_2.fastq.gz - second of the pair

# The dataset names are what the Berriman group called them - these data are not downloaded from the SRA

  %expts = ( # key= SRA 'SRX' experiment ID, values = [Analysis ID, quality score metric]

	    Adult_female => ["RNASeq.Berriman.Adult_female", 'phred'],
	    Adult_male => ["RNASeq.Berriman.Adult_male", 'phred'],
	    BmL3_1361258 => ["RNASeq.Berriman.BmL3_1361258", 'phred'],
	    eggs_embryos => ["RNASeq.Berriman.eggs_embryos", 'phred'],
	    immature_female => ["RNASeq.Berriman.immature_female", 'phred'],
	    L3_stage => ["RNASeq.Berriman.L3_stage", 'phred'],
	    L4 => ["RNASeq.Berriman.L4", 'phred'],
	    microfillariae => ["RNASeq.Berriman.microfillariae", 'phred'],
	   );
	    
} elsif ($species eq 'remanei') {

  %expts = ( SRX052082 => ["RNASeq.remanei.L2_larva", 'phred'],
	     SRX052083 => ["RNASeq.remanei.L4_larva", 'phred']
	   )

} elsif ($species eq 'briggsae') {

  %expts = ( SRX052079 => ["RNASeq.briggsae.L2_larva", 'phred'],
	     SRX052081 => ["RNASeq.briggsae.L4_larva", 'phred'],
	     SRX053351 => ["RNASeq.briggsae.all_stages", 'phred']
	   )


} else {
  $log->log_and_die("Unkown species: $species\n");
}



##########################################
# Set up database paths                  #
##########################################

my $script = "align_RNASeq.pl";
my $lsf;
my $store_file;
my $scratch_dir;
my $job_name;
$wormbase->checkLSF;
$lsf = LSF::JobManager->new();
$store_file = $wormbase->build_store; # make the store file to use in all wormpub perl commands
$scratch_dir = $wormbase->logs;
$job_name = "worm_".$wormbase->species."_RNASeq";


my $RNASeqDir   = $wormbase->rnaseq;
chdir $RNASeqDir;

my @SRX = keys %expts;
  
if (!$expt) {

  if (!$check) {

    # delete results from the previous run
    foreach my $SRX (@SRX) {
      chdir "$RNASeqDir/$SRX";
      $wormbase->run_command("rm -rf tophat_out/", $log) unless ($noalign);
      $wormbase->run_command("rm -rf cufflinks/genes.expr", $log);
      $wormbase->run_command("rm -rf TSL/TSL_evidence.ace", $log);
      $wormbase->run_command("rm -rf Introns/Intron.ace", $log);
    }

    my @chrom_files;
    if ($wormbase->assembly_type eq 'contig') {
      @chrom_files = ('supercontigs.fa');
    } else {
      @chrom_files = $wormbase->get_chromosome_names('-prefix' => 1, '-mito' => 1);
    }

    if (! $noalign) { # only create the genome sequence index if the assembly changed
      # Build the bowtie index for the reference sequences by:
      mkdir "/nfs/wormpub/RNASeq/$species/", 0777;
      mkdir "/nfs/wormpub/RNASeq/$species/reference-indexes/", 0777;
      chdir "/nfs/wormpub/RNASeq/$species/reference-indexes/";
      my $G_species = $wormbase->full_name('-g_species' => 1);
      unlink glob("${G_species}*");
      
      foreach my $chrom_file (@chrom_files) {
	if ($wormbase->assembly_type eq 'chromosome') {$chrom_file .= '.dna'} # changes the contents of @chrom_files
	my $copy_cmd = "cp ${database}/CHROMOSOMES/${chrom_file} .";
	
	###################################################################
#	# debug for brugia to get the latest assembly
#	if ($species eq 'brugia') { # +++ debug 
#	  $log->write_to("USING THE NEW ASSEMBLY OF BRUGIA IN ~wormpub/tmp/brugia.dna!\n");
#	  $copy_cmd = "cp /nfs/wormpub/tmp/brugia.dna ."; # +++ debug
#	  @chrom_files = ('brugia.dna'); # +++ debug 
#	}  # +++ debug 
	###################################################################
	
	$status = $wormbase->run_command($copy_cmd, $log);
      }
      my $bowtie_cmd = "bsub -I /software/worm/bowtie/bowtie-build " . (join ',', @chrom_files) . " $G_species";
      $status = $wormbase->run_command($bowtie_cmd, $log);
      if ($status != 0) {  $log->log_and_die("Didn't create the bowtie indexes /nfs/wormpub/RNASeq/$species/reference-indexes/${G_species}.*\n"); }
    }

    # make the file of splice junctions:    
    # CDS, Pseudogene and non-coding-transcript etc introns
    # allows:
    # Coding_transcript Transposon_CDS Pseudogene tRNAscan-SE-1.23 Non_coding_transcript ncRNA Confirmed_cDNA Confirmed_EST Confirmed_UTR
    # Note: the curated CDS model introns are also added to this file
    
    my $splice_juncs_file = "/nfs/wormpub/RNASeq/$species/reference-indexes/splice_juncs_file";
    unless ($norawjuncs) {
      unlink $splice_juncs_file;
      unlink "${splice_juncs_file}.tmp";
      $status = $wormbase->run_command("touch ${splice_juncs_file}.tmp", $log);
      foreach my $chrom_file (@chrom_files) {
	my $splice_junk_cmd = "bsub -I grep -h intron ${database}/CHROMOSOMES/$chrom_file.gff | egrep 'curated|Coding_transcript|Transposon_CDS|Pseudogene|tRNAscan-SE-1.23|Non_coding_transcript|ncRNA Confirmed_cDNA|Confirmed_EST|Confirmed_UTR' | awk '{OFS=\"\t\"}{print \$1,\$4-2,\$5,\$7}' >> ${splice_juncs_file}.tmp";
	$status = $wormbase->run_command($splice_junk_cmd, $log);
      }
      $status = $wormbase->run_command("bsub -I sort -u ${splice_juncs_file}.tmp > $splice_juncs_file", $log);
      if ($status != 0) {  $log->log_and_die("Didn't create the splice_juncs_file\n"); }
    }
    
    # Make a GTF file of current transcripts. Used by cufflinks.
    my $gtf_file = "/nfs/wormpub/RNASeq/$species/transcripts.gtf";
    unless ($nogtf) {
      unlink $gtf_file;
      my $scripts_dir = $ENV{'CVS_DIR'};
      $status = $wormbase->run_command("bsub -q long $scripts_dir/make_GTF_transcript.pl -database $database -out $gtf_file -species $species", $log);
      if ($status != 0) {  $log->log_and_die("Didn't create the $gtf_file file\n"); }
      if ($species eq 'elegans') {
	$wormbase->check_file($gtf_file, $log,
			      minsize => 17000000,
			     );
      }
    }
  }

  # run tophat against a few experiments at a time - we don't want to
  # have too many fastq files ungzipped at a time otherwise we may run
  # out of quota filespace.

  my @arg;
  for ( my $i=0; $i < @SRX; $i++) {
    push @arg, $SRX[$i];
    if (($i % 10) == 9) {
      $log->write_to("Running alignments on: @arg\n");
      print "Running alignments on: @arg\n";
      &run_align($check, $noalign, @arg);
      @arg=();
    }
  }
  if (@arg) {
    $log->write_to("Running alignments on: @arg\n");
    print "Running alignments on: @arg\n";
    &run_align($check, $noalign, @arg);
  }
  


 # now write out a table of what has worked

  $log->write_to("\nResults\n");
  $log->write_to("-------\n\n");

  chdir $RNASeqDir;
  foreach my $SRX (@SRX) {
    $log->write_to("$SRX");
    if (-e "$SRX/tophat_out/accepted_hits.bam") {$log->write_to("\ttophat OK");} else {{$log->write_to("\ttophat ERROR");}}
    if (-e "$SRX/cufflinks/genes.expr") {$log->write_to("\tcufflinks OK");} else {$log->write_to("\tcufflinks ERROR");}
    if (-e "$SRX/TSL/TSL_evidence.ace") {$log->write_to("\tTSL OK");} else {$log->write_to("\tTSL ERROR");}
    if (-e "$SRX/Introns/Intron.ace") {$log->write_to("\tIntrons OK");} else {$log->write_to("\tintron ERROR");}
    $log->write_to("\n");

    # make the expresssion tarball for Wen to put into SPELL

# Wen says: "Gary, the file is good, I just wonder what should we do
# with the "0" values. SPELL data are all log2 transformed. That is
# how they are stored in mysql and on the website there are also
# options for users to disply linear or log2 transformed data.  I will
# not be able to handle the "0" in SPELL. Can we replace "0" with a
# very small value, such as 0.0000000001?  If you have a lot tables,
# you tarzip them together and place them on a ftp site for me to
# download."
    
    if (-e "$SRX/cufflinks/genes.expr") {
      open (EXPR, "<$SRX/cufflinks/genes.expr") || $log->log_and_die("Can't open $SRX/cufflinks/genes.expr\n");
      open (EXPROUT, ">$SRX.out") || $log->log_and_die("Can't open $SRX.out\n");
      while (my $line = <EXPR>) {
	my @f = split /\s+/, $line;
	if ($f[0] eq 'gene_id') {next;}
	if ($f[5] == 0) {$f[5] = 0.0000000001}
	if ($f[8] eq "OK") {print EXPROUT "$f[0]\t$f[5]\n"}
      }
      close(EXPROUT);
      close (EXPR);
    }
  }
  $log->write_to("\n");

  # make a tarball
  $status = $wormbase->run_command("tar cf expr.tar *.out", $log);
  unlink "expr.tar.gz";
  $status = $wormbase->run_command("gzip -f expr.tar", $log);
  my $autoace = $wormbase->autoace;
  $status = $wormbase->run_command("cp expr.tar.gz $autoace", $log); # this will probably be changed to the autoace/OUTPUT directory soon


  # make the ace file of RNASeq spanned introns to load into acedb
  my $splice_file = $wormbase->misc_dynamic."/RNASeq_splice_${species}.ace";
  chdir $RNASeqDir;
  $status = $wormbase->run_command("rm -f $splice_file", $log);
  $status = $wormbase->run_command("cat */Introns/virtual_objects.elegans.RNASeq.ace > $splice_file", $log);
  $status = $wormbase->run_script("acezip.pl -file $splice_file", $log);
  $status = $wormbase->run_command("cat */Introns/Intron.ace >> ${splice_file}.tmp", $log);
  $status = $wormbase->run_script("acezip.pl -file ${splice_file}.tmp", $log);
  # flatten the results of all libraries at a position into one entry
  open (FEAT, "< ${splice_file}.tmp") || $log->log_and_die("Can't open file ${splice_file}.tmp\n");
  open (FLAT, ">> $splice_file") || $log->log_and_die("Can't open file $splice_file\n");
  my %splice;
  while (my $line = <FEAT>) {
    if ($line =~ /^Feature_data/ || $line =~ /^\s*$/) { # new clone
      foreach my $start (keys %splice) {
	foreach my $end (keys %{$splice{$start}}) {
	  my $total= 0;
	  my $string = "";
	  foreach my $library (keys %{$splice{$start}{$end}}) {
	    my $value = $splice{$start}{$end}{$library};
	    $total += $value;
	    $string .= "$library $value "
	  }
	  # filter out any spurious introns with only 1 or 2 reads
	  if ($total > 2) {print FLAT "Feature RNASeq_splice $start $end $total \"$string\"\n";}
	}
      }
      # reset things for the new clone
      %splice = ();
      print FLAT $line;
    } else {
      my @feat = split /\s+/, $line;
      $splice{$feat[2]}{$feat[3]}{$feat[5]} = $feat[4];
    }
  }
  # and do the last clone
  foreach my $start (keys %splice) {
    foreach my $end (keys %{$splice{$start}}) {
      my $total= 0;
      my $string = "";
      foreach my $library (keys %{$splice{$start}{$end}}) {
	my $value = $splice{$start}{$end}{$library};
	$total += $value;
	$string .= "$library $value "
      }
	  # filter out any spurious introns with only 1 or 2 reads
      if ($total > 2) {print FLAT "Feature RNASeq_splice $start $end $total \"$string\"\n";}
    }
  }
  close(FLAT);
  close(FEAT);
  $status = $wormbase->run_command("rm -f ${splice_file}.tmp", $log);


} else { # we have a -expt parameter
  
  &run_tophat($check, $noalign, $expt, $solexa, $illumina);
}


$log->mail();
print "Finished.\n" if ($verbose);

exit(0);


###################################
##########  SUBROUTINES  ##########
###################################

# submit this script to LSF on the farm2 head node for each experiment
# and wait for the jobs to complete.  Check that the job worked.

sub run_align {
  my ($check, $noalign, @args) = @_;

  foreach my $arg (@args) {

    # "the normal queue can deal with memory requests of up to 15 Gb, but 14 Gb is better" - Peter Clapham, ISG
    my $err = "$scratch_dir/align_RNASeq.pl.lsf.${arg}.err";
    my $out = "$scratch_dir/align_RNASeq.pl.lsf.${arg}.out";
    my @bsub_options = (-e => "$err", -o => "$out");
    push @bsub_options, (-q =>  "long",
                         -F =>  "100000000", # maybe increase this?
			 -M =>  "14000000", 
			 -R => "\"select[mem>14000 && tmp>10000] rusage[mem=14000]\"", # want 10Gb free on /tmp for the hash tie file
			 -J => $job_name);
    my $cmd = "$script -expt $arg";      # -expt is the parameter to make the script run an alignment and analysis on a dataset $arg
    if ($check) {$cmd .= " -check";}
    if ($noalign) {$cmd .= " -noalign";}
    if ($nogtf) {$cmd .= " -nogtf";}
    if ($database) {$cmd .= " -database $database";}
    if ($norawjuncs) {$cmd .= " -norawjuncs";}
    if ($expts{$arg}[1] eq 'solexa') {$cmd .= " -solexa";}
    if ($expts{$arg}[1] eq 'illumina1.3') {$cmd .= " -illumina";}
    $log->write_to("$cmd\n");
    $cmd = $wormbase->build_cmd($cmd);
    $lsf->submit(@bsub_options, $cmd);
  }
  
  $lsf->wait_all_children( history => 1 );
  $log->write_to("This set of Tophat jobs have completed!\n");
  for my $job ( $lsf->jobs ) {
    if ($job->history->exit_status ne '0') {
      $log->write_to("Job $job (" . $job->history->command . ") exited non zero: " . $job->history->exit_status . "\n");
    }
  }
  $lsf->clear;



}

#####################################################################
# run tophat on one experiment to create the accepted_hits.bam file
# this can fail through lack of memory if that happens, try running it
# again on the hugemem queue 

# ARG: list of names of SRX* directories in the $wormbase->rnaseq
# directory

# probably best to only give about five/ten input directories at a
# time otherwise your filesize quota may be exceeded

sub run_tophat {
  
  my ($check, $noalign, $arg, $solexa, $illumina) = @_;
  
  chdir "$RNASeqDir/$arg";
  my $G_species = $wormbase->full_name('-g_species' => 1);

  my $cmd_extra = "";
  if ($solexa)   {$cmd_extra = "--solexa-quals"} 
  if ($illumina) {$cmd_extra = "--solexa1.3-quals"} 

  if ((!$check && !$noalign) || !-e "tophat_out/accepted_hits.bam") {
    $wormbase->run_command("rm -rf tophat_out/", $log);

    $log->write_to("gunzipping fastq files\n");
    foreach my $gzip_file (glob("SRR/*/*.fastq*.gz")) {
      my $gunzip_file = $gzip_file;
      $gunzip_file =~ s/.gz$//;
      my $status = $wormbase->run_command("gunzip -c $gzip_file > $gunzip_file", $log);
    }
    my @files = glob("SRR/*/*.fastq");
    my $joined_file = join ",", @files;
    
    # do we have paired reads?
    my @files1 = sort glob("SRR/*/*_1.fastq"); # sort to ensure the two sets of files are in the same order
    my @files2 = sort glob("SRR/*/*_2.fastq");
    if ((@files1 == @files2) && @files2 > 0) {
      $log->write_to("Have paired-end files.\n");
      my $joined1 = join ",", @files1;
      my $joined2 = join ",", @files2;
      $joined_file = "$joined1 $joined2";
      print "Made paired-read joined files: $joined_file\n";
      # set the inner-distance -r parameter
      # assume the read length is 36 and the insert size is 200 bp (we only have one example of a read-paired experiment)
      # so the inner-distance is 200 - (2*36) = 128
      $cmd_extra .= ' -r 128';
    }

    $log->write_to("run tophat $joined_file\n");
    my $raw_juncs = ''; # use the raw junctions hint file unless we specify otherwise
    $raw_juncs = "--raw-juncs /nfs/wormpub/RNASeq/$species/reference-indexes/splice_juncs_file" unless $norawjuncs;
    $status = $wormbase->run_command("/software/worm/tophat/tophat $cmd_extra --min-intron-length 30 --max-intron-length 5000 $raw_juncs /nfs/wormpub/RNASeq/$species/reference-indexes/$G_species $joined_file", $log);
    $log->write_to("remove fastq files\n");
    $wormbase->run_command("rm -f SRR/*/*.fastq", $log);
    if ($status != 0) {  $log->log_and_die("Didn't run tophat to do the alignment successfully\n"); } # only exit on error after gzipping the files

  }

##############################################################################
# now get the RPKM values
##############################################################################

# cufflinks
# use a GTF of our known transcripts - CDS, Pseudogene and non-coding-transcript
# to restrict the created gene structures to our own


# now run cufflinks
  if (!$check || !-e "cufflinks/genes.expr") {
    $log->write_to("run cufflinks\n");
    chdir "$RNASeqDir/$arg";
    mkdir "cufflinks", 0777;
    chdir "cufflinks";
    my $gtf = ''; # use the existing gene models unless we specify otherwise
    $gtf = "--GTF /nfs/wormpub/RNASeq/$species/transcripts.gtf" unless $nogtf;
    $status = $wormbase->run_command("/software/worm/cufflinks/cufflinks $gtf ../tophat_out/accepted_hits.bam", $log);
    if ($status != 0) {  $log->log_and_die("Didn't run cufflinks to get the isoform/gene expression successfully\n"); }
  }

#############################################################
# now get the TSL sites
#############################################################

# now run TSL stuff
  if (!$check || !-e "TSL/TSL_evidence.ace") {
    $log->write_to("run TSL\n");
    chdir "$RNASeqDir/$arg";
    mkdir "TSL", 0777;
    my $analysis = $expts{$arg}[0];
    $status = &TSL_stuff($cmd_extra, $analysis);

    if ($status != 0) {  $log->log_and_die("Didn't run the TSL stuff successfully\n"); }
  }


#############################################################
# now get the intron spans
#############################################################

  if (!$check || !-e "Introns/Intron.ace") {
    $log->write_to("run Introns\n");
    chdir "$RNASeqDir/$arg";
    mkdir "Introns", 0777;
    my $analysis = $expts{$arg}[0];
    my $status = &Intron_stuff($cmd_extra, $analysis);

    if ($status != 0) {  $log->log_and_die("Didn't run the Intron stuff successfully\n"); }
  }


}

#################################################################################################################
# gets the reads that don't align and which have a bit of TSL sequence
# on them - runs tophat using this library and parses out the TSL
# sites from the bam file then matches to the known TSL sites and
# writes evidence for the TSL Features.
#
# Assumes we have a TSL directory set up to get the results and that
# the current working directory is "$RNASeqDir/$arg"


# TSL sequences from 
# PLOS Genetics
# Nov 2006
# Operon Conservation and the Evolution of trans-Splicing in the Phylum Nematoda
# David B. Guiliano, Mark L. Blaxter
# http://www.plosgenetics.org/article/info%3Adoi%2F10.1371%2Fjournal.pgen.0020198
# Figure 4

# C. elegans
#   Ce_SL1  GGTTTAATTACCCAAGTTTGAG
# P. pacificus
#   Pp_SL1a GGTTTTAATTACCCAAGTTTGAG
# B. malayi
#   Bm_SL1a GGTTTTAATTACCCAAGTTTGAG
#   Bm_SL1b GGTTTAATCACCCAAGTTTGAG
#   Bm_SL1c GGTTTAACTACCCAAGTTTGAG
# A. suum
#   As_SL1a GGTTTAACTACCCAAGTTTGAG
#   As_SL1b GGTTTAATTGCCCAAGTTTGAG
# N. brasiliensis
#   Nb_SL1a GGTTTAATAACCCAAGTTTGAG
# M. javanica
#   Mj_SL1M GGTTTAATTACCCTAGTTTAAG
# A. acenae
#   Aa_SL1a GGTTTATATACCCAAGTTTGAG
#   Aa_SL1b GGTTTTATTACCCAAGTTTGAG
#   Aa_SL1c GGTTTAAATACCCAAATTTGAG
#   Aa_SL1d GGTTTAAATACCCTAATTTGAG
# S. ratti
#   Sr_SL1a GGTTTATAAAACCCAGTTTGAG
#   Sr_SL1b GGTTTAAAAAACCCAGTTTGAG
#   Sr_SL1c GGTTTAAAAACCCAGTTTGAG
#   Sr_SL1d GGTTTTAAAACCCAGTTTGAG
#   Sr_SL1e GGTTTAAAAACCCAATTTGAG
#   Sr_SL1f GGTTTAAATAACCCAGTTTGAG
#   Sr_SL1g GGTTTAAATAACCCATATAGAG
#   Sr_SL1h GTTTTTTAAATAACCAAGTTTGAG
#   Sr_SL1i GGTTTAAGAAAACCCATTCAAG
#   Sr_SL1j GGTTTTATAAAACCCAGTTTGAG
#   Sr_SL1k GGTTTATAAAACCCAGTTTAAG
#   Sr_SL1l GGTTTAAAAACCCGATTTTGAG
#   Sr_SL1m GGTTTTAAATAACCCAGTTTGAG
#   Sr_SL1n GGTTTATATAACCCAGTTTGAG
#   Sr_SL1o GGTTTAAAAACCCAAATTAAA
#   Sr_SL1p GGTTTTAAAAACCCAGTTTGAG
#   Sr_SL1q GGTTTATACAACCCAGTTTGAG
#   Sr_SL1r GGTTTAAGAAACCCTGTTTGAG
#   Sr_SL1s GGTTTAAAAAACCCAGTTTAAG
# C. elegans
#   Ce_SL2 GGTTTTAACCCAGTTACTCAAG
#   Ce_SL3 GGTTTTAACCCAGTTAACCAAG
#   Ce_SL4 GGTTTTAACCCAGTTTAACCAAG
#   Ce_SL5 GGTTTTAACCCAGTTACCAAG
#   Ce_SL6 GGTTTAAAACCCAGTTACCAAG
#   Ce_SL7 GGTTTTAACCCAGTTAATTGAG
#   Ce_SL8 GGTTTTTACCCAGTTAACCAAG
#   Ce_SL9 GGTTTATACCCAGTTAACCAAG
#   Ce_SL10 GGTTTTAACCCAAGTTAACCAAG
#   Ce_SL11 GGTTTTAACCAGTTAACTAAG
#   Ce_SL12 GTTTTAACCCATATAACCAAG
#   Ce_SL13 GGTTTTAACCCAGTTAACTAAG
# C. briggsae
#   Cb_SL2 GGTTTTAACCCAGTTACTCAAG
#   Cb_SL3 GGTTTTAACCCAGTTAACCAAG
#   Cb_SL4 GGTTTTAACCCAGTTTAACCAAG
#   Cb_SL10 GGTTTTAACCCAAGTTAACCAAG
#   Cb_SL13 GGATTTATCCCAGATAACCAAG
#   Cb_SL14 GGTTTTTACCCTGATAACCAAG
# N. brasiliensis
#   Nb_SL2a GGTAATTAACCAAGTATCTCAAG
#   Nb_SL2b GGTTAATACCCAGTATCTCAAG
#   Nb_SL2c GGTAATTAACCCAGTATCTCAAG
#   Nb_SL2d GGTAATTACCCAGTATCTCAAG
#   Nb_SL2e GGTTTAAACCCAGTATCTCAAG
#   Nb_SL2f GGTTTTTACCCGGTATCTTAAG
# P. pacificus
#   Pp_SL2a GGTTTTTACCCAGTATCTCAAG
#   Pp_SL2b GGTTTTAACCCAGTATCTCAAG
#   Pp_SL2c GGTTTATACCCAGTATCTCAAG
#   Pp_SL2d GGTTTTTAACCCAGTATCTCAAG
#   Pp_SL2e GGTTTTTACTCAGTATCTCAAG
#   Pp_SL2f GGTCTTTACCCAGTATCTCAAG
#   Pp_SL2g GGTTTTAACCCGGTATCTCAAG
#   Pp_SL2h GGTTTTAACCCAGTATCTTAAG
#   Pp_SL2i GGTTTTGACCCAGTATCTCAAG
#   Pp_SL2j GTTTTATACCCAGTATCTCAAG
#   Pp_SL2k GGTTTATACCCAGTATCTCAAG
#   Pp_SL2l GGTTTAAACCCAGTATCTCAAG
# H. contortus
#   Hc_SL2a GGTTTTAACCCAGTATCTCAAG
# O. tipilae
#   Ot_SL2a GGTTTTTTACCCAGTATCTCAAG
#   Ot_SL2b GGTTTTTACCCAGTATCTCAAG


sub TSL_stuff {

  my ($cmd_extra, $analysis) = @_;

  my %SL = (
	    'SL1',   'GGTTTAATTACCCAAGTTTGAG',
	    'SL2',   'GGTTTTAACCCAGTTACTCAAG',
	    'SL2a',  'GGTTTATACCCAGTTAACCAAG',
	    'SL2b', 'GGTTTTAACCCAGTTTAACCAAG',
	    'SL2c',   'GGTTTTAACCCAGTTACCAAG',
	    'SL2d',  'GGTTTTTACCCAGTTAACCAAG',
	    'SL2e',  'GGTTTAAAACCCAGTTAACAAG',
	    'SL2f',  'GGTTTTAACCCAGTTAACCAAG',
	    'SL2g',   'GGTTTTAACCAGTTAACTAAG',
	    'SL2h',  'GGTTTTAACCCATATAACCAAG',
	    'SL2i', 'GGTTTTAACCCAAGTTAACCAAG',
	    'SL2j',  'GGTTTAAAACCCAGTTACCAAG',
	    'SL2k',  'GGTTTTAACCCAGTTAATTGAG',
	   );

  $coords = Coords_converter->invoke($database, 0, $wormbase);

  my $output = "TSL/TSL_reads.fastq";

  # read the hits - this uses a lot of memory and so is done with a tied hash
  $log->write_to("Reading hits\n");
  my $samtools = "/software/worm/samtools/samtools view tophat_out/accepted_hits.bam";
  my $hitsdb   = "/tmp/hitsdb$$.dbm"; # put -R "select [tmp>10000] rusage[mem=10000]" on the command line to have 10 Gb free on /tmp
  tie my %hits, 'GDBM_File', "$hitsdb", &GDBM_WRCREAT, 0666 or $log->log_and_die("cannot open $hitsdb\n");

  open (HITS, "$samtools |") || $log->log_and_die("can't run samtools\n");
  while (my $line = <HITS>) {
    $line =~ /^(\S+)/;
    $hits{$1} = 1;
  }
  close(HITS);
  $log->write_to("Finished reading hits\n");
  $wormbase->run_command("ls -l $hitsdb", $log);
    
  $log->write_to("Finding non-hits\n");
  open (OUT, ">$output") || $log->log_and_die("can't open $output\n");
  # now go through the read files looking for reads that don't match
  my @readfiles = glob("SRR/*/*.gz");
  my $id;
  my $seq;
  my $line3;
  my $line4;
  my $tslname;
  my $tsllen;
  foreach my $readfile (@readfiles) {
    $log->write_to("\nStarting to read $readfile\n");
    open (READ, "gunzip -c $readfile |") || $log->log_and_die("can't open read file: $readfile\n");
    while (my $line = <READ>) {
      
      #@SRR006514.1 length=36
      #AAAGCTATGCGGATTATGTACTGAACTAGGATCTGG
      #+SRR006514.1 length=36
      #I?8:=9I).'&%&,/-+%+)#+#&&"%'#""""%%$
      
      # read the ID
      ($id) = ($line =~ /^@(\S+)/);
      #print "$id ";
      # read the sequence
      $seq = <READ>;
      # and the other two lines
      $line3 = <READ>;
      $line4 = <READ>;
      # is this read not aligned?
      if (!exists $hits{$id}) {
	#print "\n\t\t\t$id is not aligned: $seq";
	# check for sequence in forward sense
	($tslname, $tsllen) = match_tsl($seq, '+', \%SL);
	if (defined $tslname) {
	  #print "$seq has $tslname, len = $tsllen\n\n";
	  # change the 'length=' in lines 1 and 3
	  my ($orig_len) = ($line =~ /=(\d+)/);
	  $orig_len -= $tsllen;
	  $orig_len += 2; # add back two for the 'AG' we will append to the sequence
	  $line  =~ s/=\d+/=$orig_len/;
	  $line3 =~ s/=\d+/=$orig_len/;
	  # add the TSL type to the ID
	  $line  =~ s/$id/${id}\.\+\.${tslname}/;
	  $line3 =~ s/$id/${id}\.\+\.${tslname}/;	
	  # remove the TSL from the sequence
	  # stick 'AG' on the front of the sequence
	  substr($seq, 0, $tsllen) = 'AG';
	  # remove the TSL quality
	  if ($cmd_extra eq '') { # fake a phred quality score 'II' on the front
	    substr($line4, 0, $tsllen) = 'II';
	  } else { # fake a solexa good quality score 'hh'
	    substr($line4, 0, $tsllen) = 'hh';	    
	  }
	  # print it out
	  print OUT "${line}${seq}${line3}${line4}";
	  
	}
      }
    }
    close(READ);
    $log->write_to("\nFinished reading $readfile\n");
  }
  close(OUT);
  untie %hits;
  unlink $hitsdb;

  # now run tophat on this set of TSL reads
  my $G_species = $wormbase->full_name('-g_species' => 1);
  $log->write_to("run tophat $output\n");
  $status = $wormbase->run_command("/software/worm/tophat/tophat $cmd_extra --output-dir TSL /nfs/wormpub/RNASeq/$species/reference-indexes/$G_species $output", $log);
  $log->write_to("remove TSL fastq files\n");
  $wormbase->run_command("rm -f $output", $log);
  if ($status != 0) { return $status;  } # only exit on error after gzipping the files

  # now parse the results looking for TSL sites
  my $TSLfile = "TSL/accepted_hits.bam";
  $samtools = "/software/worm/samtools/samtools view $TSLfile";

  my %results; # hash of TSL sites found by RNAseq alignment
  $log->write_to("get the TSL sites found by alignment\n");
  open (HITS, "$samtools |") || $log->log_and_die("can't run samtools\n");
  while (my $line = <HITS>) {
    my $sense = '+';
    my ($id, $flags, $chrom, $pos, $seq) = ($line =~ /^(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)/);
    my ($tsl) = ($id =~ /\.(SL\d+)/);
    if ($flags & 0x10) { # find and deal with reverse alignments
      $sense = '-';
      $pos = $pos + (length $seq) - 2; # go past the 'A' of the 'AG' we added on to ensure we hit a splice site
    } else {
      $pos = $pos + 1; # go past the 'A' of the 'AG' we added on to ensure we hit a splice site
    }
    $results{$chrom}{$pos}{$sense}{$tsl}++;
    print "store: ${chrom} ${pos} ${sense} ${tsl} value: $results{$chrom}{$pos}{$sense}{$tsl} $seq\n";
  }
  close(HITS);

  # now check that the TSL sites match known TSL Feature objects and add evidence to the Features
  $log->write_to("check that the TSL sites match known TSL Feature objects\n");
  my %found; # hash of TSL Feature object IDs with evidence from RNASeq - holds no. of supporting reads
  my %not_found; # hash of TSL Feature object IDs with no evidence from this RNASeq experiment

  my $table_def = &write_feature_def;
  my $table_query = $wormbase->table_maker_query($database, $table_def);
  while(<$table_query>) {
    chomp;
    s/\"//g;  #remove "
    next if (/acedb/ or /\/\//);
    my @data = split("\t",$_);
    my ($feature, $clone, $start, $end, $method) = @data;
    if (!defined $feature) {next}
    if (!defined $clone) {$log->write_to("Feature $feature does not have a position mapped\n"); next}
    if (!defined $start) {$log->write_to("Feature $feature does not have a position mapped\n"); next}
    my ($TSL_chrom, $TSL_coord) = $coords->Coords_2chrom_coords( $clone, $start );
    if ($start < $end) { # forward sense
      print "looking for: ${TSL_chrom} ${TSL_coord} + ${method}\n";

      if (exists $results{$TSL_chrom}{$TSL_coord}{'+'}{$method}) {
	$found{$feature} = $results{$TSL_chrom}{$TSL_coord}{'+'}{$method};
	delete $results{$TSL_chrom}{$TSL_coord}{'+'}{$method};
	print "found $feature +\n";
      } else {
	$not_found{$feature} = 1;
	print "NOT found $feature +\n";
      }
    } else { # reverse sense
      print "looking for: ${TSL_chrom} ${TSL_coord} - ${method}\n";
      if (exists $results{$TSL_chrom}{$TSL_coord}{'-'}{$method}) {
	$found{$feature} = $results{$TSL_chrom}{$TSL_coord}{'-'}{$method};
	delete $results{$TSL_chrom}{$TSL_coord}{'-'}{$method};
	print "found $feature -\n";
      } else {
	$not_found{$feature} = 1;
	print "NOT found $feature -\n";
      }
    }    
  }


  # the only data left in %results now are the matches to the genome
  # where there is no defined TSL Feature object, so these are all new
  # TSL sies that we could define a new Feature for. This has been
  # started, but needs more work to get the flanking sequences and the
  # clone name.

  my $total_matches = keys %results; # so we can work out the no. of alignments per million (or billion?) matches
  my $full_species = $wormbase->full_name;
  # find all RNASeq evidence for TSL sites that do not have Features
  my $newaceout = "TSL/TSL_new_features.ace";

  open (NEWACE, ">$newaceout") || $log->log_and_die("Can't open ace file $newaceout\n");
  $log->write_to("find all RNASeq evidence for TSL sites that do not have Features\n");
  foreach my $TSL_chrom (keys %results) {
    foreach my $TSL_coord (keys %{$results{$TSL_chrom}}) {
      foreach my $sense (keys %{$results{$TSL_chrom}{$TSL_coord}}) {
	foreach my $method (keys %{$results{$TSL_chrom}{$TSL_coord}{$sense}}) {
	  if (!defined $results{$TSL_chrom}{$TSL_coord}{'+'}{$method}) {next}
	  my $ft_id = "WBsf#${TSL_chrom}#${TSL_coord}#${sense}#${method}"; # totally bogus Feature ID, needs to be changed before loading to acedb
	  print NEWACE "\n\nFeature : \"$ft_id\"\n";
#	  print NEWACE "Sequence \n";
#	  print NEWACE "Flanking_sequences\n";
	  print NEWACE "Species \"$full_species\"\n";
	  print NEWACE "Description \"$method trans-splice leader acceptor site\"\n";
	  print NEWACE "SO_term SO:0000706\n";
	  print NEWACE "Method $method\n";
	  my $reads =  $results{$TSL_chrom}{$TSL_coord}{'+'}{$method}; # reads
	  print NEWACE "Defined_by_analysis $analysis $reads\n";

	  #$log->write_to("No Feature object for: chrom: $TSL_chrom pos: $TSL_coord sense: $sense type: $method, reads= $results{$TSL_chrom}{$TSL_coord}{$sense}{$method}\n");
	}
      }
    }
  }
  close(NEWACE);

  # show all Feature objects that do not have evidence from this RNASeq data-set
#  $log->write_to("show all Feature objects that do not have evidence from this RNASeq data-set\n");
#  foreach my $feature (keys %not_found) {
#    $log->write_to("Not found: $feature\n");
#  }

  # write out evidence for matched existing Feature objects
  my $aceout = "TSL/TSL_evidence.ace";
  open (ACE, ">$aceout") || $log->log_and_die("Can't open ace file $aceout\n");
  foreach my $feature (keys %found) {
    print ACE "\n\nFeature : \"$feature\"\n";
    my $reads = $found{$feature}; # reads
    print ACE "Defined_by_analysis $analysis $reads\n";
  }
  close(ACE);





  return $status;
}

######################################
# finds matches to the TSL sequences #
######################################

# Returns name of type of TSL and length of TSL at start of sequence

sub match_tsl {

  my ($seq, $sense, $SL_hashref)=@_;

  # searches for n-mers of the TLS (max 18, not 23 so that we have a decent 16 bases left to search with)
  # min 8 so that we are fairly confident that we have a TSL
  if ($sense eq '+') {
    for (my $i=18; $i>8; $i--) {
      
      # loops through the TLS sequences 
      foreach my $slname (keys %{$SL_hashref}){
	
	#next if $i > length $SL_hashref->{$slname};
	my $nmer=substr($SL_hashref->{$slname}, -$i);
	
	if ($seq=~ /^${nmer}/) { # both sequences are already in upercase
	  return ($slname, $i);
	}
      }
    }
  }
  return undef;
}


############################################################################
# this will write out an acedb tablemaker defn to a temp file
############################################################################

sub write_feature_def {
  my $def = "/tmp/Features_$$.def";
  open TMP,">$def" or $log->log_and_die("cant write $def: $!\n");
  my $species = $wormbase->full_name;
  my $txt = <<END;

Sortcolumn 1

Colonne 1
//Subtitle Feature
Width 20
Optional
Visible
Class
Class Feature
From 1
Condition ((Method = "SL1") OR (Method = "SL2")) AND (Species = "$species")

Colonne 2
//Subtitle Clone
Width 12
Mandatory
Visible
Class
Class Sequence
From 1
Tag Sequence

Colonne 3
//Subtitle Feature2
Width 12
Optional
Hidden
Class
Class Feature
From 2
Tag Feature_object
Condition IS \\%1

Colonne 4
//Subtitle Start_pos
Width 12
Optional
Visible
Integer
Right_of 3
Tag HERE

Colonne 5
//Subtitle End_pos
Width 12
Optional
Visible
Integer
Right_of 4
Tag HERE

Colonne 6
//Subtitle Type
Width 12
Optional
Visible
Class
Class Method
From 1
Tag Method

END

  print TMP $txt;
  close TMP;
  return $def;
}

############################################################################
# Reads the Junction file to create confirmed an intron ACE file
############################################################################


sub Intron_stuff {

  my ($cmd_extra, $analysis) = @_;

  $log->write_to("Reading splice junctions BED file\n");

  my $status = 0;

# BED format provides a flexible way to define the data lines that are
# displayed in an annotation track. BED lines have three required fields
# and nine additional optional fields. The number of fields per line
# must be consistent throughout any single set of data in an annotation
# track. The order of the optional fields is binding: lower-numbered
# fields must always be populated if higher-numbered fields are used.

# The first three required BED fields are:

#    1. chrom - The name of the chromosome (e.g. chr3, chrY,
#       chr2_random) or scaffold (e.g. scaffold10671).
#    2. chromStart - The starting position of the feature in the
#       chromosome or scaffold. The first base in a chromosome is
#       numbered 0.
#    3. chromEnd - The ending position of the feature in the chromosome
#       or scaffold. The chromEnd base is not included in the display of
#       the feature. For example, the first 100 bases of a chromosome
#       are defined as chromStart=0, chromEnd=100, and span the bases
#       numbered 0-99.

# The 9 additional optional BED fields are:

#    4. name - Defines the name of the BED line. This label is displayed
#       to the left of the BED line in the Genome Browser window when
#       the track is open to full display mode or directly to the left
#       of the item in pack mode.
#    5. score - A score between 0 and 1000. If the track line useScore
#       attribute is set to 1 for this annotation data set, the score
#       value will determine the level of gray in which this feature is
#       displayed (higher numbers = darker gray).
#    6. strand - Defines the strand - either '+' or '-'.
#    7. thickStart - The starting position at which the feature is drawn
#       thickly (for example, the start codon in gene displays).
#    8. thickEnd - The ending position at which the feature is drawn
#       thickly (for example, the stop codon in gene displays).
#    9. itemRgb - An RGB value of the form R,G,B (e.g. 255,0,0). If the
#       track line itemRgb attribute is set to "On", this RBG value will
#       determine the display color of the data contained in this BED
#       line. NOTE: It is recommended that a simple color scheme (eight
#       colors or less) be used with this attribute to avoid
#       overwhelming the color resources of the Genome Browser and your
#       Internet browser.
#   10. blockCount - The number of blocks (exons) in the BED line.
#   11. blockSizes - A comma-separated list of the block sizes. The
#       number of items in this list should correspond to blockCount.
#   12. blockStarts - A comma-separated list of block starts. All of the
#       blockStart positions should be calculated relative to
#       chromStart. The number of items in this list should correspond
#       to blockCount.

  my %seqlength;
  my %virtuals;

  $coords = Coords_converter->invoke($database, 0, $wormbase);

  my $output = "Introns/Intron.ace";
  my $junctions = "tophat_out/junctions.bed";
  my $old_virtual = "";
  open (ACE, ">$output") || $log->log_and_die("Can't open the file $output\n");
  open(BED, "<$junctions") || $log->log_and_die("Can't open the file $junctions\n");
  while (my $line = <BED>) {
    if ($line =~ /^track/) {next}
    my @cols = split /\s+/, $line;
    my $chrom = $cols[0];
    my $start = $cols[1] + 1;
    my $end = $cols[2];
    my $reads = $cols[4];
    my $sense = $cols[5];
    my @blocksizes = split /,/, $cols[10];
    my $splice_5 = $start + $blocksizes[0]; # first base of intron
    my $splice_3 = $end - $blocksizes[1]; # last base of intron

    # get the clone that this intron is on
    my ($clone, $clone_start, $clone_end) = $coords->LocateSpan($chrom, $splice_5, $splice_3);

    
    if (not exists $seqlength{$clone}) {
      $seqlength{$clone} = $coords->Superlink_length($clone);
    }

    my $virtual = "${clone}:Confirmed_intron_RNASeq";
      
    if ($old_virtual ne $virtual) {
      print ACE "\nFeature_data : \"$virtual\"\n";
      $old_virtual = $virtual
    }

    if ($sense eq '-') {
      ($clone_end, $clone_start) = ($clone_start, $clone_end)
    }

# when we have changes to acedb that can deal with a Feature_data Confirmed_intron from RNASeq, then do this:
#    print ACE "Confirmed_intron $clone_start $clone_end RNASeq $analysis $reads\n";
# until then we store it as a Feature_data Feature, which works quite well:
    print ACE "Feature RNASeq_splice $clone_start $clone_end $reads $analysis\n";

  }
  close(BED);
  close(ACE);

  
  # now add the Feature_data objects to the chromosome objects
  my $vfile = "Introns/virtual_objects." . $wormbase->species . ".RNASeq.ace";
  open(my $vfh, ">$vfile") or $log->log_and_die("Could not open $vfile for writing\n");
  foreach my $clone (keys %seqlength) {
    print $vfh "\nSequence : \"$clone\"\n";
    my $virtual = "${clone}:Confirmed_intron_RNASeq";
          printf $vfh "S_Child Feature_data $virtual 1 $seqlength{$clone}\n";
  }
  close($vfh);


  return $status;
}


__END__

=pod

=head1 NAME - align_RNASeq.pl

=head2 DESCRIPTION

This aligns RNASeq data to the current genome. It requires the Transcript data to be available in the Build.

Run on the 'long' queue as:

bsub -I -e align.err -o align.out -q long  align_RNASeq.pl [-check]


=over 4

=item *

-verbose - output verbose chatter

=back

=over 4

=item *

-check - don't run everything, resume running and only run the things that appear to have failed or not run yet.

=back

=over 4

=item *

-noalign - don't do a short-read alignment against the genome - use the results remaining from the previous alignment in the rest of the analyses

=back

=over 4

=item *

-species $SPECIES - specify the species to use

=back

=over 4

=item *

-expt <name of SRX data> - only process the specified SRX set of data - this is usually only used by this script to LSF submit another instance of this script to run the mapping of one of a set of SRX data.

=back

=over 4

=item *

-species - set the species explicitly

=back

=over 4

=item *

-database - set the data to read, the default is autoace.

=back

=cut

