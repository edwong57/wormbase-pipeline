#!/usr/local/bin/perl5.6.1 -w
#
# map_microarray.pl
#
# Add information to Microarray_results objects based on overlaps in GFF files 
#
# by Anon
#
# Last updated by: $Author: dl1 $                      
# Last updated on: $Date: 2003-11-10 10:31:50 $        


$|=1;
use strict;
use lib "/wormsrv2/scripts/";
use Wormbase;
use IO::Handle;
use Getopt::Long;
use Cwd;
use Ace;


######################################
# variables and command-line options #
######################################

my $tace        = &tace;                                  # tace executable path
my $dbdir       = "/wormsrv2/autoace";                    # Database path

my $maintainers = "All";
my $rundate = `date +%y%m%d`; chomp $rundate;
my $runtime = `date +%H:%M:%S`; chomp $runtime;
my $help;       # Help perdoc
my $test;       # Test mode
my $debug;      # Debug mode, verbose output to user running script
our $log;

my $outfile = "/wormsrv2/wormbase/misc/misc_microarrays.ace";

GetOptions ("debug=s"   => \$debug,
	    "test"      => \$test,
            "help"      => \$help);


# Display help if required
&usage("Help") if ($help);

# Use debug mode?
if($debug){
  print "DEBUG = \"$debug\"\n\n";
  ($maintainers = $debug . '\@sanger.ac.uk');
}

# connect to database
print  "Opening database ..\n" if ($debug);
my $db = Ace->connect(-path=>$dbdir,
                      -program =>$tace) || do { print "Connection failure: ",Ace->error; die();};

if ($debug) {
    my $count = $db->fetch(-query=> 'find PCR_product where Microarray_results');
    print "checking $count PCR_products\n\n";
}

my $microarray_results;
my @CDS;
my @Pseudo;
my $gene;
my $pseudo;
my $locus;

open (OUTPUT, ">$outfile") or die "Can't open the output file $outfile\n";

my $i = $db->fetch_many(-query=> 'find PCR_product where Microarray_results');  
while (my $obj = $i->next) {
    
    print "$obj\t" if ($debug);

    # Microarray_results
    
    $microarray_results = $obj->Microarray_results;

    @CDS     = $obj->Overlaps_CDS;
    @Pseudo  = $obj->Overlaps_pseudogene;
    
    print "Microarray_results : \"$microarray_results\"\tCDS: " . (scalar @CDS) . " Pseudo: " . (scalar @Pseudo) . "\n" if ($debug);
    
    if (scalar @CDS > 0) {
	print OUTPUT "\nMicroarray_results : \"$microarray_results\"\n";
	foreach $gene (@CDS) {
	    print OUTPUT "Predicted_gene \"$gene\"\n";
	    $locus   = $obj->Overlaps_CDS->Locus_genomic_seq;
	}
	
	print OUTPUT "Locus $locus\n" if (defined $locus);
	print OUTPUT "\n";
    }

    
#    if (scalar @Pseudo > 1) {
#	print OUTPUT "\n// Microarray_results : \"$microarray_results\"\n";
#	foreach $pseudo (@Pseudo) {
#	    print OUTPUT "// Predicted_pseudogene \"$pseudo\"\n";
#	}
#	print OUTPUT "\n";
#    }
    
    @CDS    = "";
    @Pseudo = "";
    $locus  = "";
    $obj->DESTROY();
} 
close OUTPUT;

exit(0);

