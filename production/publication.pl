# Code to parse publication proformae
use strict;

our (%fsm, $want_next, $chado, %prepared_queries);
our ($g_FBrf, $g_pub_type); # For feedback to parse other proforma types. g_FBrf is blank if P22 is blank - otherwise is valid FBrf
our $unattributed; # nothing else can be filled in if P22 is unattributed. Made a global variable so can do cross-checks with other proformae

our $g_P43_flags = ''; # sum of P43 flags in record (and in chado if 'Where_running' is set to Cambridge)

my ($file, $proforma);						# variables global to this file only.
my %proforma_fields ;						# Keep track of what lines have already been seen
my @inclusion_essential = qw (P22);				# P2 swapped for P21. Those fields which must be present in the proforma.

# hashing is not allowed in publication proforma. Have $hash_entries set to 1 so that can re-use
# code containing dehash for publication field checking.  Will also have the useful side-effect
# of reporting any fields in publication.pro that do contain hashes
my $hash_entries = 1;

# Beware: if the FB CV changes, we may need to change any code that compares $g_pub_type with a fixed string.
# Pay particular attention to validate_P{10,23,24}.  The next set of declarations may be
# helpful.

my $book_text  = 'book';
my $err_text   = 'erratum';
my $paper_text = 'paper';
my $PC_text    = 'personal communication to FlyBase';
my $supp_text  = 'supplementary material';

my @needmultipub = ('abstract', 'autobiography', 'bibliographic list', 'biography', 'book review', 'conference report', 'DNA/RNA sequence record', 'editorial', 'erratum', 'film', 'interview', 'letter', 'meeting report', 'news article', 'note', 'obituary', 'paper', 'patent', 'poem', 'poster', 'protein sequence record', 'retraction', 'review', 'species list', 'spoof', 'stock list', 'supplementary material', 'tactile diagram', 'teaching note', 'thesis');
my $first_time = 1;

my ($change2, $change21);			# See validate_P21_P2()
my ($multipub_id, $multipub_abbrev, $series);	# See validate_P21_P2() and validate_P20()
my $pc_summary = 0;				# See P23/P18 processing.

my ($p1_data, $p3_data, $p4_data, $p11a_data, $p11b_data, $p11c_data, $p11d_data);	# For post-checks. p1_data is hif, for checking against @needmultipub, and must always be set (is set from chado after checks if not present)

# gm - adding new variables for cross-checking of P41, P43 and P44 fields
my ($p41_data, $p43_data, $p44_data);

my ($P28_data, $P26_data, $P34_data);

my @dummy_arry;
my %dummy_dup_proforma_fields; # no proforma fields can be duplicated, so called the hash %dummy_dup_proforma_fields


###
# variable for storing data grabbed using support_script modules
# when 'Where_running' is set to 'Cambridge'.
my $triage_flags_in_chado = {};
###

sub do_publication_proforma ($$)
{
# Process a publication proforma, the text of which is in the second argument which has been read from the
# file named in the first argument.
	$unattributed = 0;
    if ($first_time)					# Sanity clause.
    {
	valid_symbol ($book_text, 'FBcv:pub_type')  or warn "$book_text is no longer a valid publication type!\n";
	valid_symbol ($err_text, 'FBcv:pub_type')   or warn "$err_text is no longer a valid publication type!\n";
	valid_symbol ($paper_text, 'FBcv:pub_type') or warn "$paper_text is no longer a valid publication type!\n";
	valid_symbol ($PC_text, 'FBcv:pub_type')    or warn "$PC_text is no longer a valid publication type!\n";
	valid_symbol ($supp_text, 'FBcv:pub_type')  or warn "$supp_text is no longer a valid publication type!\n";
	$first_time = 0;
    }
    $pc_summary = 0;					# To enforce summary of PC in P18 or P23.
    ($file, $proforma) = @_;				# Set global variables for convenience.
    %proforma_fields = ();				# Not seen any proforma lines yet.
	%dummy_dup_proforma_fields = ();
	@dummy_arry = ();

    ($g_FBrf, $g_pub_type) = ('', '');			# Initialize Peeves-global symbols, then file-global.
    ($change2, $change21, $multipub_id, $multipub_abbrev, $series) = ('') x 5;
    ($p1_data, $p3_data, $p4_data, $p11a_data, $p11b_data, $p11c_data, $p11d_data) = ('') x 7;
    my $P29_data = '';
# gm - setting new variables for cross-checking of P41, P43 and P44 fields to empty as done for above
	($p41_data, $p43_data, $p44_data) = ('') x 3;

	$P28_data = '';
	$P34_data = '';
	$P26_data = '';

# make sure reset variables for each publication proforma
	$triage_flags_in_chado = {};

# variables to store values for checking between fields.  Only needed within a single proforma, so
# within the do_publication_proforma subroutine, no need to declare at the top of the file.
# can use scalar variable and not array since hash_entries is forced to be 1 in publication
# proforma.  When populate the variable using process_field_data, have to use list context
# as follows, since process_field_data returns an array.
# ($P30_list) = process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '0');
# 
	my $P30_list = '';
	my $P31_list = '';
	my $P32_list = '';
	my $P46_list = '';

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?) (P22)\..*? :(.*)/s)		# The FBrf id ... cannot be pling c'd
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    validate_P22 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (P32)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    unattributed($2,$3) if ($unattributed);
		unless ($unattributed) {
			($P32_list) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
		}
	}
	elsif ($field =~ /^(.*?) (P1)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P1 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P2)\..*? :(.*)/s) # put P2 first so that change2 can be set for obsolete P21
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P2 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}

# not removing code for P21 below (or called subroutines) as the checking is/was complex and some of this may still being used in the validate_P21_P2 check ?
	elsif ($field =~ /^(.*?) (P21)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P21 ($2, $1, $3);
	    report($file, "P21: Invalid proforma field.");
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P20)\.\s*(.*?)\s*\*.*:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $4);
	    double_query ($file, $2, $4) or $unattributed or validate_P20 ($2, $1, $4);
	    report($file, "P20: Invalid proforma field '$3' ($4)") if($4 ne '');
	    unattributed($2,$4) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P3)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P3 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P4 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P11a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P11a ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P11b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P11b ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P11c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P11c ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P11d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P11d ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P10)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P10 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P12)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P12 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P16)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P16 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P13|P14)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_P13_14 ($2, $1, $3);
		if ($unattributed && $2 eq 'P14'){unattributed($2,$3);}
	}

	elsif ($field =~ /^(.*?) (P25)\.\s*(.*?)\s*\*.*:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $4);
	    double_query ($file, $2, $4) or $unattributed or validate_P25 ($2, $1, $4);
	    report($file, "P25: Invalid proforma field '$3'.") if($4 ne '');
	    unattributed($2,$4) if ($unattributed);
	}

	elsif ($field =~ /^(.*?) (P26)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P26 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P27)\.\s*(.*?)\s*\*.*:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $4);
	    double_query ($file, $2, $4) or $unattributed or validate_P27 ($2, $1, $4);
	    report($file, "P27: Invalid proforma field '$3'.") if($4 ne '');
	    unattributed($2,$4) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P29)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    $P29_data = $3;
	    double_query ($file, $2, $3) or $unattributed or validate_P29 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}


	elsif ($field =~ /^(.*?) (P30)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    unattributed($2,$3) if ($unattributed);
		unless ($unattributed) {
			($P30_list) = process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '0');
		}
	}
	elsif ($field =~ /^(.*?) (P31)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    unattributed($2,$3) if ($unattributed);
		unless ($unattributed) {
			($P31_list) = process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '0');
		}
	}
	elsif ($field =~ /^(.*?) (P23)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
#	    check_non_ascii ($file, $2, $3);
	    $unattributed or validate_P23 ($2, $1, $3);		# P23 is the *only* field which is allowed to have ?? within it.
	    $pc_summary ||= $3 ne '';
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P18)\..*? :(.*)/s)
	{
	    $pc_summary ||= $3 ne '';
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or  $unattributed or validate_P18 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P19)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (P38)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or  validate_P38 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P39)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or  validate_P39 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}
	elsif ($field =~ /^(.*?) (P40)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    unattributed($2,$3) if ($unattributed);
		unless (double_query ($file, $2, $3) || $unattributed) {
			validate_triage_flags ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (P41)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    unattributed($2,$3) if ($unattributed);
		unless (double_query ($file, $2, $3) || $unattributed) {
			$p41_data = validate_triage_flags ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (P42)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    unattributed($2,$3) if ($unattributed);
		unless (double_query ($file, $2, $3) || $unattributed) {
			validate_triage_flags ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (P43)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    unattributed($2,$3) if ($unattributed);
		unless (double_query ($file, $2, $3) || $unattributed) {
			$g_P43_flags = $p43_data = validate_triage_flags ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (P44)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    unattributed($2,$3) if ($unattributed);
		unless ($unattributed) {
			($p44_data) = process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '0');
		}

	}
	elsif ($field =~ /^(.*?) (P45)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P45 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);

	}
	elsif ($field =~ /^(.*?) (P28)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P28 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}

	elsif ($field =~ /^(.*?) (P34)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or $unattributed or validate_P34 ($2, $1, $3);
	    unattributed($2,$3) if ($unattributed);
	}

	elsif ($field =~ /^(.*?) (P46)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    unattributed($2,$3) if ($unattributed);
		unless ($unattributed) {
			($P46_list) = process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '1');
		}

	}
	elsif ($field =~ /^(.*?) P(.+?)\..*? :(.*)$/s)			# Oh Vienna!
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	    unattributed($2,$3) if ($unattributed);
	} elsif ($field =~ /.*P.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in publication.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n!%s", $field);
		}

	}



    }



    
	if($g_FBrf ne '' and !$p1_data){ #normally p1_data set in validate_P1
			$p1_data = chat_to_chado ('pub_pubtype', $g_FBrf)->[0]->[0];
#	    report ($file, "Pub tupe is $p1_data");
	}
 
### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, undef);

	validate_P21_P2 ($multipub_id, $change2, $multipub_abbrev, $series, $p1_data);

# Cross-check P11[a-d] if P22 is empty (i.e. g_Fbrf eq '' or 'new') and the publication type is not on a stop-list.

    unless ($g_FBrf or valid_symbol ($g_pub_type, 'not_regular_pub'))
    {
   	unless($unattributed){
    		
	if ($p11a_data eq '' and $p11b_data eq '' and $p11c_data eq '' and $p11d_data eq '')
	{
	    report ($file, "None of P11a through P11d have any data.");
	}
	if ($p11a_data ne '')
	{
	    $p11b_data eq '' or report ($file, "%s: Must not have data (%s) when %s has data (%s).",
					'P11b', $p11b_data, 'P11a', $p11a_data);
	    $p11c_data eq '' or report ($file, "%s: Must not have data (%s) when %s has data (%s).",
					'P11c', $p11c_data, 'P11a', $p11a_data);
	}
	if ($p11c_data ne '')
	{
	    $p11a_data eq '' or report ($file, "%s: Must not have data (%s) when %s has data (%s).",
					'P11a', $p11a_data, 'P11c', $p11c_data);
	    $p11b_data eq '' or report ($file, "%s: Must not have data (%s) when %s has data (%s).",
					'P11b', $p11b_data, 'P11c', $p11c_data);
	}
	if (!defined $p3_data or $p3_data eq '')
	{
	    report ($file, "%s: Must have data for a new publication of type '%s'",
		    'P3', $g_pub_type);
	}
	if (!defined $p4_data or $p4_data eq '')
	{
	    report ($file, "%s: Must have data for a new publication of type '%s'",
		    'P4', $g_pub_type);
	}
	}
    }# end checks for 'new' P22 FBrf of a 'regular' publication

# Check for *new* pcs

	unless ($g_FBrf || $unattributed) {
		if (defined $g_pub_type and $g_pub_type eq $PC_text and !$pc_summary) {
			report ($file, "P18 and P23 must not both be empty for a new '%s'.", $PC_text);
		}
	}

    if ($P29_data ne '' and $g_pub_type ne $book_text)
    {
	report ($file, "P29: Can not give ISBN data '%s' when publication type is '%s'", $P29_data, $g_pub_type);
    }

	unless ($g_pub_type eq 'review' || valid_symbol($g_pub_type, 'not_regular_pub') || valid_symbol ($file, 'record_type') eq 'BIBL') {
		crosscheck_P41_P43_P44($p41_data,$p43_data,$p44_data);

	}
	if (defined $g_pub_type and $g_pub_type eq $supp_text and $P28_data) {

		report ($file, "P28 must not be filled in when P1 specifies '%s'.", $supp_text);

	}

# doing these checks after the entire proforma has been filled in as more robust,
# and will still generate an error, even if the checked field is not present at all.
	if ($g_FBrf eq '' && $g_pub_type && valid_symbol($g_pub_type, 'needs_pubmed_abstract')) {

		unless ($P34_data) {

			report ($file, "%s: PubMed abstract text must be filled in for a new publication of type '%s'.", 'P34', $g_pub_type);

		}
	}


	if ($g_FBrf eq '' && $g_pub_type && !valid_symbol($g_pub_type, 'not_regular_pub')) {

		unless ($g_pub_type eq 'supplementary material') {
			unless ($P26_data) {
				report ($file, "%s: PMID must be filled in for a new publication of type '%s'.", 'P26', $g_pub_type);
			}

			unless ($p11d_data) {
				report ($file, "%s: DOI must be filled in for a new publication of type '%s'.", 'P11d', $g_pub_type);
			}

		}
	}

	if ($g_FBrf eq '' && $g_pub_type && valid_symbol($g_pub_type, 'needs_related_pub')) {

		unless ($P31_list) {

			report ($file, "%s: Related publication must be filled in for a new publication of type '%s'.", 'P31', $g_pub_type);

		}
	}


# checks that fields which can contain FBrf id(s) do not contain the same FBrf number(s)

	compare_pub_fbrf_containing_fields ($file, 'P22', $g_FBrf, 'P30', $P30_list, \%proforma_fields);
	compare_pub_fbrf_containing_fields ($file, 'P22', $g_FBrf, 'P31', $P31_list, \%proforma_fields);
	compare_pub_fbrf_containing_fields ($file, 'P22', $g_FBrf, 'P32', $P32_list, \%proforma_fields);

	compare_pub_fbrf_containing_fields ($file, 'P30', $P30_list, 'P31', $P31_list, \%proforma_fields);

	compare_pub_fbrf_containing_fields ($file, 'P30', $P30_list, 'P32', $P32_list, \%proforma_fields);
	compare_pub_fbrf_containing_fields ($file, 'P31', $P31_list, 'P32', $P32_list, \%proforma_fields);


# check that P32 is not filled in for new publications

	unless ($g_FBrf) {

		unless ($unattributed) {

			if ($P32_list) {

				report ($file, "%s: Must not have data when P22 is 'new':\n!%s", 'P32', $proforma_fields{'P32'});

			}

		}
	}

#
check_pub_accession_against_chado ($file, 'P11d', $g_FBrf, $P32_list, $p11d_data, 'DOI', 'DOI');
check_pub_accession_against_chado ($file, 'P26', $g_FBrf, $P32_list, $P26_data, 'pubmed', 'PubMed ID');
check_pub_accession_against_chado ($file, 'P28', $g_FBrf, $P32_list, $P28_data, 'PMCID', 'PubMed Central ID');

### End of tests that can only be done after parsing the entire proforma. ###

# the following line should always be at the bottom of this subroutine

    $want_next = $fsm{'PUBLICATION'};

    
}

sub unattributed($$){
	my ($code,$item) = @_;
	if($item and $item ne ''){
	report ($file, "%s: Cannot contain data when P22 is 'unattributed'.",$code);	
	}
}

sub validate_P22 ($$$)
{
    my ($code, $change, $FBrf) = @_;
    #return if $FBrf eq '';			# Absence of data is no longer permissible.
    

    if (changes ($file, $code, $change))
    {
	report ($file, "%s: Can't change the FBrf of a publication! No more checks on P22.", $code);
	return;
    }

    $FBrf = trim_space_from_ends ($file, $code, $FBrf);
    
    if($FBrf eq 'unattributed'){$unattributed = 1;}

    if($FBrf eq ''){
    	report($file, "%s: '%s' cannot be blank: must be 'new', 'unattributed' or 'FBrf{7 digits}'", $code, $FBrf);
    	return;
    }

    unless ($FBrf eq 'unattributed' or $FBrf eq 'new' or $FBrf =~ /^FBrf\d{7}$/)
    {
		if ($FBrf =~ /^\d+$/)
		{
			report ($file, "%s: '%s' is not a FBrf.  Did you mean 'FBrf%07d' perhaps?", $code, $FBrf, $FBrf);
		}
		else
		{
			report ($file, "%s: '%s' is not valid - must be 'new', 'unattributed' or 'FBrf{7 digits}'.", $code, $FBrf);
		}
		return;
    }

    #  Validate $FBrf against Chado and return it if valid
	unless ($FBrf eq 'new' or $FBrf eq 'unattributed'){
    my $obsolete = chat_to_chado ('pub_from_id', $FBrf)->[0]->[0];

    if (!defined $obsolete)
    {
	report ($file, "%s: %s does not exist in Chado.", $code, $FBrf);
    }
    elsif ($obsolete == 1)
    {
	report ($file, "%s: %s is marked as obsolete in Chado.", $code, $FBrf);
    }
    else
    {
	$g_FBrf = $FBrf;

## add initial population of $g_pub_type here once FBrf has passed all checks

	my $existing_pubtype = chat_to_chado ('pub_pubtype', $g_FBrf)->[0]->[0];
	# This should not be able to happen, but copied catasptophe style check from
	# validate_P1 just in case.
	unless (defined $existing_pubtype) {
		report ($file, "Trying to get publication type from chado for %s, but it does not exist !! (Chado should always have this data, so you've found a serious bug.)", $g_FBrf);
	} else {
		$g_pub_type = $existing_pubtype;
	}
##

    }
    }


###
# gm - use support_scripts modules to get information for that FBrf (only when running in Cambridge)
# have to wait until P22 is processed and $g_FBrf has been set (this is only set if P22 contains a
# valid FBrf number).


	if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge' && $g_FBrf) {

		$triage_flags_in_chado->{'P40'} = get_triage_data_from_chado($chado,'cam_flag',$g_FBrf);
		$triage_flags_in_chado->{'P41'} = get_triage_data_from_chado($chado,'harv_flag',$g_FBrf);
		$triage_flags_in_chado->{'P42'} = get_triage_data_from_chado($chado,'onto_flag',$g_FBrf);
		$triage_flags_in_chado->{'P43'} = get_triage_data_from_chado($chado,'dis_flag',$g_FBrf);

	}
###

}



sub validate_P1 ($$$)
{

# P1 specifies the type of publication.  It is a required field if P22 is not filled in (marked by $g_FBrf
# being '').  Its values must be taken from the FB ontology with namespace set to publication.  Set the
# publication type in $g_pub_type if the data is valid.

    my ($code, $change, $type) = @_;
    my $existing_pubtype;

    $type = trim_space_from_ends ($file, $code, $type);
    $change = changes ($file, $code, $change);

	single_line ($file, $code, $type, $proforma_fields{$code});


# First deal with the case of no data.  We're not allowed to change (i.e. delete) the publication type to
# nothing.  If we're not trying to change it, then $g_FBrf must be set, otherwise we're not filling in a
# mandatory piece of information.

    if (!defined $type or $type eq '')
    {
		if ($change)
		{
			report ($file, "%s: Not allowed to delete publication type", $code);
		}
		elsif ($g_FBrf eq '')
		{
			report ($file, "%s: Can't omit publication type without valid data in P22", $code);
		}
		return;
    }

# Now know there is data.  Does it come from the CV?

    unless (valid_symbol ($type, 'FBcv:pub_type'))
    {
		report ($file, "%s: '%s' is not a valid publication type", $code, $type);
		return;
    }
    
    $p1_data = $type; # for eliminating false P2 errors - only some Pub types need multipub

    if ($g_FBrf)
    {

	# If it's data for an existing publication (i.e. $g_FBrf has a value) emit warnings if P1 is
	# changing it to the same thing, or if it is not changing it and there is a mismatch with the
	# data in Chado.
		$existing_pubtype = chat_to_chado ('pub_pubtype', $g_FBrf)->[0]->[0];
	
		unless (defined $existing_pubtype)		# This should not be able to happen!
		{
			my $catastrophe = "%s: Trying to change publication type of %s to '%s' ";
			$catastrophe .= "but the publication type isn't in Chado.\n";
			$catastrophe .= "Chado should always have this data, so you've found a serious bug.\n";
			$catastrophe .= "****** PLEASE CONTACT camdev URGENTLY! ******";
			report ($file, $catastrophe, $code, $g_FBrf, $type);
			return;
		}
		if ($change)
		{
			if ($type eq $existing_pubtype)
			{
			report ($file, "%s: Trying to change publication type to the value (%s) it already has in Chado",
				$code, $type);
			}
			$g_pub_type = $type;			# Make the change for the benefit of later proforma fields.
		}
		else
		{
			if ($type ne $existing_pubtype)
			{
			report ($file, "%s: Trying to set publication type to '%s' but it has type '%s' in Chado",
				$code, $type, $existing_pubtype);
			}
#			$g_pub_type = $existing_pubtype;
		}
    }
    else		    # Data for a new publication.  Must not be a change type.
    {
		report ($file, "%s: Can't change the type of a new publication!", $code) if $change;
		$g_pub_type = $type;
    }
}

sub validate_P2($$$) #occurs before validate_P21
{
# P2 specifies the abbreviated form of the title of the multipub in which this publication appears.  Because
# of the close coupling with P21 very little can be checked immediately, so do what we can and save the data
# for the post-check phase.

    my ($code, $change, $ab) = @_;
    $change2 = changes ($file, $code, $change);
    $multipub_abbrev = trim_space_from_ends ($file, $code, $ab);
	single_line ($file, $code, $multipub_abbrev, $proforma_fields{$code});


}

sub validate_P21($$$)
{
# P21 specifies the numeric ID of the multipub in which this publication appears.  Because of the close
# coupling with P2 very little can be checked immediately, so do what we can and save the data for the
# post-check phase.

    my ($code, $change, $id) = @_;
    $change21 = changes ($file, $code, $change);
    $multipub_id = trim_space_from_ends ($file, $_[0], $_[2]);
    index ($multipub_id, "\n") >= 0 and report ($file, "%s: Can not have multiple data '%s'",
						$code, $multipub_id);
	if($multipub_id=~/FBrf\d+/){
		report($file,"$code: You seem to have an FBrf in the multipub ID field");
	}
}

sub validate_P21_P2 ($$$$$$)
{
# P21 (multipub ID), P2 (multipub abbreviation) and P20 (multipub series abbreviation) are so closely coupled
# that non-trivial checks can only be done after the proforma is otherwise parsed, i.e. in the post-check
# phase.  This routine is the post-check.

    my ($m_id, $change2, $m_abbrev, $series, $p1_data) = @_;
    # current multipub abbreviation as written by curator, is $m_abbrev

# There are five binary variables of importance --- the first four in @_ and whether P22 was given a value.
# $change21 and $change2 will be 0 or 1 according to whether a !c was given for P21 and P2 respectively.
# $m_id will either be empty or it will have the data given in P21.  $m_abbrev will either be empty or will
# have the data given in P2.  $g_FBrf will either be empty or will contain the the data given in P22.

# $series is of subsidiary importance in this routine.  If it is present, it must be consistent with the
# value given in Chado, if any.

#    return if ($change21 eq '');		# At least one proforma field was omitted.
    return if ($change2 eq '');		# At least one proforma field was omitted.

    my $multipub;			# Multipub IDs in Chado are prefixed with 'multipub_'
    if ($m_id =~ /^[1-9][0-9]*$/)
    {
	$multipub = sprintf ("multipub_%d", $m_id);
    }
    elsif ($m_id ne '')
    {
	report ($file, "%s: The multipub ID given, '%s', is not a positive integer.  " .
		"Perhaps it should have been given in P2 or, if not, you made a typo.", 'P21', $m_id);
	return;
    }


    unless ($g_FBrf)
    {
	$change2 and report ($file, "%s: Can't change a multipub abbreviation without an FBrf in P22", 'P22');
	return if $change2;		# That removes another 5/32 possibilities.
    }

# Just 4/32 cases remain which are invariably error conditions.  This next test picks them off, but first dig
# out some useful data from Chado for subsequent tests and so more informative reports may be made.

    my($existing_abbreviation,$existing_mid,$abbr_of_mid,$mid_of_abbr) = ('', '', '', '');

        my $fail = 0;

    if ($g_FBrf) # get abbrev from FBrf
    {
	$existing_abbreviation = chat_to_chado ('pub_journal_from_FBrf', $g_FBrf)->[0]->[0];
	$existing_mid          = chat_to_chado ('multipub_of_pub',       $g_FBrf)->[0]->[0];

	defined $existing_abbreviation or $existing_abbreviation = '';
	defined $existing_mid or $existing_mid = '';
	}
	else{
		if( $m_abbrev ne '' and $p1_data ne '') { # new publication
	    foreach (@needmultipub){ 
	    	if($_ eq $p1_data){
	    			 # then you need a multipub abbreviation
	    		$existing_abbreviation = chat_to_chado('pub_abbr_to_pub_abbr',$m_abbrev)->[0]->[0];
	    		defined $existing_abbreviation or 
	    			report ($file, "%s: '$m_abbrev' is not a valid multipub abbreviation in Chado for pubtype '$p1_data'", 'P2', $existing_abbreviation);#, substr ($existing_abbreviation, 9));
	    			$fail = 1;
	    #		defined $existing_abbreviation and report ($file, "%s: Found '$m_abbrev' in Chado for '$p1_data'", 'P2', $existing_abbreviation);#, substr ($existing_abbreviation, 9));
	    		
	    		}
	    	}
	    	$fail and return;
	    }
	}
	

	$abbr_of_mid = $existing_abbreviation;
	$mid_of_abbr = $existing_mid;
    #}
#    report ($file, "%s: This is a $existing_abbreviation", 'P2');


    if ($change2)
    { 	if($m_abbrev eq '')
    	{
    		report ($file, "%s: Can't delete a multipub abbreviation", 'P2');
    		$fail = 1;
    	}
    	elsif($m_abbrev ne ''){
    		if($m_abbrev ne $abbr_of_mid){
    		report ($file, "%s: Are you sure you want to change the multipub of $g_FBrf in chado?", 'P2');
    		}
    		elsif($m_abbrev eq $abbr_of_mid){
    		report ($file, "%s: Cannot use !c here, as '$abbr_of_mid' is already the multipub of $g_FBrf in chado.", 'P2');
    		}
    	}
    	$fail and return;				# That removes 14/32 possibilities.
    }
    
    


    unless ($change2)# $change21 or
    {
	$fail = 0;

	if ($m_abbrev eq '') # if multipub abbrev is empty
	{
	    if ($g_FBrf and $existing_abbreviation ne '')#=~ /^pub_journal_from_FBrf/ ) #FBrf ok, 
	    {
#	    	report ($file, "%s: Testing data for $p1_data - must have multipub abbreviation.", 'P2'); # debug to check record type
	    	foreach (@needmultipub){ 
#	    	report ($file, "%s: Testing $_ is it?? $p1_data", 'P2'); # debug to check record type
	    		if($_ eq $p1_data){
	    			report ($file, "%s: Missing data for $p1_data --- perhaps you mean to put %s", 'P2', $existing_abbreviation);#, substr ($existing_abbreviation, 9));
	    			$fail = 1;
	    		}
	    	}
	    }
	    else
	    {	
	    	foreach (@needmultipub){ 
	    		if($_ eq $p1_data){
	    			report ($file, "%s: Missing data for $p1_data - must have multipub abbreviation.", 'P2');
	    			$fail = 1;
	    		}
	    	}
	    }
	}
	
	
	if ($g_FBrf)
	{	
	    if ($m_abbrev ne '' and $m_abbrev ne $abbr_of_mid) # wrong refc
		{	
			
			# pete's records pm2579.edit, pm2578.edit had 'paper' and 'personal communication to FlyBase' in P2
			# both of these situations are picked up and incorrect - one should be Nature the other blank because for a personal communication no multipub is given
			
			my $multipubno = $mid_of_abbr;
			$multipubno = substr ($mid_of_abbr, 9) if(length($multipubno)>9);
			$multipubno = "not given" if(length($multipubno)==0);
			my $abbrevjournal = $abbr_of_mid;
			$abbrevjournal = "a journal title" if(length($abbr_of_mid)==0);

			report ($file, "%s: Multipub abbreviation (you gave '%s') does not match that associated with $g_FBrf in chado. Perhaps you meant to put $abbrevjournal (multipub ID %s) in %s",
					'P2', 
					 $m_abbrev, # what you gave
					$multipubno,#substr ($mid_of_abbr, 0), # multipub_2703 - if no multipub this throws an error
					'P21');
			$fail = 1;
		}
	}
	$fail and return;
    }

# The remaining five cases are described by this table:

# Case 1     $g_FBrf set  $change21==1  $change2==1  $m_id set  $m_abbrev set
# Case 2     $g_FBrf set  $change21==0  $change2==0  $m_id set  $m_abbrev==''
# Case 3     $g_FBrf set  $change21==0  $change2==0  $m_id set  $m_abbrev set
# Case 4     $g_FBrf==''  $change21==0  $change2==0  $m_id==''  $m_abbrev set
# Case 5     $g_FBrf==''  $change21==0  $change2==0  $m_id set  $m_abbrev set

    if ($change21 and $change2)
    {
# Case 1.  Valid only if the data in Chado differs from that to which it is being changed and if the multipub
# specified $m_id truly has the abbreviation specified by m_abbrev.

	if ($multipub eq $mid_of_abbr and $m_abbrev eq $abbr_of_mid)
	{
	    $series eq '' or $m_abbrev .= " $series";
	    $existing_mid eq $multipub and
		report ($file, "%s: Trying to change multipub ID and abbreviation to the values (%s, '%s') ".
			"they already have in Chado.", 'P21/P2/20', $m_id, $m_abbrev);
	}
	else
	{
		report ($file, "%s: Inconsistent multipub ID and abbreviation.  " .
			"In %s you gave %s which is the multipub ID of '%s' and " .
			"in %s you gave '%s' which is the abbreviation of %s",
			'P21/P2/P20', 'P21', $m_id, $abbr_of_mid, 'P2/P20', $m_abbrev, substr ($mid_of_abbr, 9));
	}
	return;
    }


}

sub validate_P20 ($$$)
{
# P20 specifies the series abbreviation of a publication.

    my ($code, $change);
    ($code, $change, $series) = @_;			# Series is a global variable for postprocessing.

    $change = changes ($file, $code, $change);
    $series = trim_space_from_ends ($file, $code, $series);

# First deal with the case of no data.  We're not allowed to change the series abbreviation to nothing
# (i.e. delete it) but otherwise lack of data is legal.

    if (!defined $series or $series eq '')
    {
	report ($file, "%s: Not allowed to delete the series abbreviation.", $code) if $change;
	return;
    }

    if ($g_FBrf)
    {

# If it's data for an existing publication (i.e. $g_FBrf has a value) emit warnings if P20 is changing it to the
# same thing, or if it is not changing it and there is a mismatch with the data in Chado.  In either case, we
# need to ask Chado for its opinion beforehand.

# Unfortunately, Chado doesn't store the series abbreviation but only the full series name.  The abbreviation
# appears as part of the publication's multipub's miniref and we have to dig it out of there.

	my $existing_series = chat_to_chado ('pub_journal_from_FBrf', $g_FBrf)->[0]->[0];

	if ($change)
	{
	    if (!defined $existing_series)
	    {
		report ($file, "%s: Trying to change the series abbreviation to '%s' " .
			"but the series abbreviation isn't yet in Chado.", $code, $series);
	    }
	    elsif ($existing_series =~ /.+ ${series}$/)
	    {
		report ($file, "%s: Trying to change the series abbreviation to the value (%s) ".
			"it already has in Chado.", $code, $series);
	    }
	}
	else
	{
	    if (defined $existing_series and $existing_series ne '' and $existing_series !~ /.+ ${series}$/)
	    {

# This doesn't actually work very well, but I don't know how to do it any better without requiring the full
# series name in P20.

		report ($file, "%s: Trying to set the series abbreviation to '%s' but it is '%s' in Chado.",
			$code, $series, $existing_series);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the series abbreviation of a new publication!", $code) if $change;
    }
}

sub validate_P3 ($$$)
{
# P3 specifies the volume designation of the publication.  Note that we can't require it to be a sequence of
# decimal digits, or even include Roman numerals in various cases, because of the weird and wonderful things
# that appear in practice.  About all we can do is check for consistency with Chado, and then only in the case
# that the data is given and the FBrf already exists in Chado.  Such is life 8-(

    my ($code, $change, $volume) = @_;
    $change = changes ($file, $code, $change);
    $p3_data = $volume = trim_space_from_ends ($file, $code, $volume);

# First deal with the case of no data.  Attempts to delete the volume designation should be flagged but
# absence of data may be acceptable --- this is checked in the post-test phase.

    if ($volume eq '')
    {
	$change and report ($file, "%s: Do you really want to delete the volume designation?", $code);
    }
    elsif (index ($volume, "\n") >= 0)
    {
	report ($file, "%s: Must not have newlines in volume designation '%s'.", $code, $volume);
    }

    if ($g_FBrf)			# There is data, so check if it's a known publication
    {
	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'volume designation',
				  chat_to_chado ('pub_volume', $g_FBrf), $volume);
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	$change and report ($file, "%s: can't change the volume designation of a new publication!", $code);
    }
}

sub validate_P4 ($$$)
{
# P4 specifies the issue number of the publication.  Note that we can't require it to be a sequence of decimal
# digits, or even include Roman numerals in various cases, because of the weird and wonderful things that
# appear in practice.  About all we can do is check for consistency with Chado, and then only in the case that
# the data is given and the FBrf already exists in Chado.  Such is life 8-(

    my ($code, $change, $issue) = @_;
    $change = changes ($file, $code, $change);
    $p4_data = $issue = trim_space_from_ends ($file, $code, $issue);

# First deal with the case of no data.  Attempts to delete the issue number should be flagged but absence of
# data may be acceptable --- this is checked in the post-test phase.

    if ($issue eq '')
    {
	$change and report ($file, "%s: Do you really want to delete the issue number?", $code);
    }
    elsif (index ($issue, "\n") >= 0)
    {
	report ($file, "%s: Must not have newlines in issue number '%s'.", $code, $issue);
    }

    if ($g_FBrf)			# There is data, so check if it's a known publication
    {
	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'issue number',
				  chat_to_chado ('pub_issue', $g_FBrf), $issue);
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	$change and report ($file, "%s: Can't change the issue number of a new publication!", $code);
    }
}

sub validate_P11a ($$$)
{
# P11a specifies the page range of the publication.  Attempts to delete the page range should be flagged but
# absence of data is otherwise acceptable.

    my ($code, $change, $pages) = @_;

    $pages = trim_space_from_ends ($file, $code, $pages);
    $p11a_data = $pages;					# Preserve for post-check

# First deal with the case of no data.

    if (!defined $pages or $pages eq '')
    {
	changes ($file, $code, $change) and report ($file, "%s: Do you really want to delete the page range?", $code);
	return;
    }

# Now to perform perfunctory checks on the page range(s) given.

    my $pages_copy = $pages;	# So we can test to destruction.
    my $bad_range_count = 0;
    while ($pages_copy =~ /(-+)/g)
    {
	$bad_range_count++ unless $1 eq '--';
    }
    report ($file, "%s: page range '%s' must have double hyphens.", $code, $pages) if $bad_range_count;

# Try to detect typos in page ranges but also try to avoid false positives such as R500--R513 where the leading
# R is almost certainly not a typo because it has been repeated.  Lowercase Roman numerals must be allowed
# because they are so common, as must 'p' for abbreviations such as 42pp.  There may be more than one page
# range in the data, separated by ', ', so those characters are not "bad" either.

    $pages_copy =~ s/([a-zA-Z])(\d+)--\1(\d+)/$2--$3/g;		# Remove common prefix character.

    if ($pages_copy =~ /([^-0-9ivxlcdm ,p])/)
    {	
	report ($file, "%s: Bad character '%s' in page range '%s'.", $code, $1, $pages);
    }
    elsif ($pages_copy =~ /[ivxlcdm]/)
    {
# Contains Roman numerals.  Too much trouble to parse them properly  8-(
    }
    elsif ($pages_copy =~ /p/ and $pages_copy !~ /[^p]pp$/)
    {
	report ($file, "%s: Bad character 'p' in page range '%s'.  Did you mean 'pp'?", $code, $pages);	
    }

    $pages_copy =~ tr/- ,0123456789//cd;		# Obliterate everything but digits, '--', ',' and ' '
    $pages_copy =~ s/-+/, /g;				# Replace a range by its ends, even if only a single hyphen.

    my $base_of_range = -1;				# Lower than any possible page number
    foreach my $page (split (/, /, $pages_copy))
    {
	if ($page =~ /^(0[0-9]*)$/)
	{
	    report ($file, "%s: Leading zero in page number '%s'", $code, $1);
	}
	elsif ($page =~ /^([1-9][0-9]*)$/)
	{
	    report ($file, "%s: page number is out of order (%d is not less than %d)",
		    $code, $base_of_range, $page) if $base_of_range >= $page;
	    $base_of_range = $1;
	}
	else
	{
	    report ($file, "%s: Non-numeric page number '%s'", $code, $page);
	}
    }

    if ($g_FBrf)			# There is data, so check if it's a known publication
    {

# If it's data for an existing publication (i.e. $g_FBrf has a value) emit warnings if P11a is changing it to the
# same thing, or if it is not changing it and there is a mismatch with the data in Chado.  In either case, we
# need to ask Chado for its opinion beforehand.

	my $existing_pages = chat_to_chado ('pub_pages', $g_FBrf)->[0]->[0];

# Important: page ranges will have en-dashes in future (ticket 145), so convert en-dashes in $existing_pages
# to curator en-dash ('--') to en-dash before comparing with $pages.
#
# Code to do this is
#
#	$existing_pages =~ s/\x{2013}/--/g;
#
# or, rather more elegantly,
#
# use charnames ':full';
#	$existing_pages =~ s/\N{EN DASH}/--/g;
#
	if (changes ($file, $code, $change))
	{
	    if (!defined $existing_pages)
	    {
		report ($file, "%s: Trying to change the page range to %s but the page range isn't yet in Chado.", $code, $pages);
	    }
	    elsif ($pages eq $existing_pages)
	    {
		report ($file, "%s: Trying to change page range to the value (%s) it already has in Chado.", $code, $pages);
	    }
	}
	else
	{
	    if (defined $existing_pages and $pages ne $existing_pages)
	    {
		report ($file, "%s: Trying to set page range to %s but it is %s in Chado.", $code, $pages, $existing_pages);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	changes ($file, $code, $change) and report ($file, "%s: Can't change the page range of a new publication!", $code);
    }
}

sub validate_P11b ($$$)
{
# P11b specifies the URL of the publication.

    my ($code, $change, $url) = @_;

    $change = changes ($file, $code, $change);
    $url = trim_space_from_ends ($file, $code, $url);
    $p11b_data = $url;					# Preserve for post-check

# First deal with the case of no data.  We're not allowed to change (i.e. delete) the URL to nothing.

    if (!defined $url or $url eq '')
    {
	$change and report ($file, "%s: Not allowed to delete the URL.", $code);
	return;
    }

# Now we perform perfunctory checks on the URL given.

    if ((my $protocol) = ($url =~ m|^([a-z]+://)|))	# May need to extend this list in the light of experience.
    {
	$url !~ /^(http|https|ftp)/i and
	    report ($file, "%s: Unknown URL protocol '%s' in '%s'.", $code, $protocol, $url);
    }
    else
    {
	report ($file, "%s: Missing or incorrect URL protocol (e.g., http:// or ftp://) in '%s'", $code, $url);
    }

    if ($g_FBrf)			# There is data, so check if it's a known publication
    {

# If it's data for an existing publication (i.e. $g_FBrf has a value) emit warnings if P11b is changing it to
# the same thing, or if it is not changing it and there is a mismatch with the data in Chado.  In either case,
# we need to ask Chado for its opinion beforehand.

	my $existing_url = chat_to_chado ('pub_URL', $g_FBrf)->[0]->[0];

	if ($change)
	{
	    if (!defined $existing_url)
	    {
		report ($file, "%s: Trying to change the URL to %s but the URL isn't yet in Chado.", $code, $url);
	    }
	    elsif ($url eq $existing_url)
	    {
		report ($file, "%s: Trying to change URL to the value (%s) it already has in Chado.", $code, $url);
	    }
	}
	else
	{
	    if (defined $existing_url and $url ne $existing_url)
	    {
		report ($file, "%s: Trying to set URL to %s but it is %s in Chado.", $code, $url, $existing_url);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the URL of a new publication!", $code) if $change;
    }
}

sub validate_P11c ($$$)
{
# P11c specifies the accession number of the publication.  It may have data only if P1 specifies a DNA/RNA or
# protein sequence record.

    my ($code, $change, $a_n) = @_;

    $change = changes ($file, $code, $change);
    $a_n = trim_space_from_ends ($file, $code, $a_n);

    $p11c_data = $a_n;					# Preserve for post-check

# First deal with the case of no data.  We're not allowed to change (i.e. delete) the accession number to
# nothing.

    if (!defined $a_n or $a_n eq '')
    {
	report ($file, "%s: Not allowed to delete the accession number.", $code) if $change;
	return;
    }

# Now we perform perfunctory checks on the accession number given.

#  Very perfunctory, because we don't really know what to do about an accession number yet.  There's no data in
#  Chado nor space to store it there.  The code below should look rather similar to the corresponding portion
#  of validate_P11b().

    if ($g_FBrf)			# There is data, so check if it's a known publication
    {
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the accession number of a new publication!", $code) if $change;
    }
}

sub validate_P11d ($$$)
{
# P11d specifies the DOI of the publication.

    my ($code, $change, $doi) = @_;

    $change = changes ($file, $code, $change);
    $doi = trim_space_from_ends ($file, $code, $doi);
    $p11d_data = $doi;					# Preserve for post-check

# First deal with the case of no data.  We're not allowed to change (i.e. delete) the DOI to
# nothing.

    if (!defined $doi or $doi eq '')
    {
	report ($file, "%s: Not allowed to delete the DOI.", $code) if $change;
	return;
    }

# Now we perform checks on the DOI syntax.

	if (my ($doi_prefix, $doi_suffix) = ($doi =~ m|^(.+?)\/(.+)$|)) {

		if ($doi_prefix =~ m/^(doi:? *)/i) {

			report ($file, "%s: Do NOT include '%s' in '%s'", $code, $1, $doi);
			$doi_prefix =~ s/^(doi:? *)//i;
			$doi =~ s/^(doi:? *)//i;
		}

		unless ($doi_prefix =~ m/^[0-9]{1,}\.[0-9.]{1,}/) {

			report ($file, "%s: The DOI prefix part '%s' does not match expected format (dd.dd, dd.dd.dd etc) in '%s'", $code, $doi_prefix, $doi);

		} else {


			unless ($doi_prefix =~ m/^10\./) {

			report ($file, "%s: The DOI prefix part '%s' does not start with '10' in '%s' (this is unusual, are you sure it is correct?)", $code, $doi_prefix, $doi);

			}

		}

		if ($doi_suffix =~ m/\.$/) {

			report ($file, "%s: The DOI number must not end with a '.' in '%s'", $code, $doi);
			$doi_suffix =~ s/\.$//i;
			$doi =~ s/\.$//i;
		}

		
		if ($doi_suffix =~ m/ /) {

			report ($file, "%s: The DOI suffix part '%s' must not contain a space in '%s'", $code, $doi_suffix, $doi);
		}


	} else {

		report ($file, "%s: DOI does not match the basic syntax (doi_prefix/doi_suffix) in '%s'", $code, $doi);


	}

    if ($g_FBrf)			# There is data, so check if it's a known publication
    {

	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'DOI',
				  chat_to_chado ('pub_accession', $g_FBrf, 'DOI'), $doi);
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the DOI of a new publication!", $code) if $change;
    }

	$p11d_data = $doi; # put the latest version of $doi into $p11_data so that is used for check_pub_accession_against_chado
}

sub validate_P10 ($$$)
{
# P10 specifies the date of publication, the year in most cases but the full yyy.mm.dd for personal
# communications.  It is a required field if P22 is not filled in (marked by $g_FBrf being '').

    my ($code, $change, $date) = @_;

    $date = trim_space_from_ends ($file, $code, $date);

# First deal with the case of no data.  We're not allowed to change the date of publication to nothing
# (i.e. delete it).  If we're not trying to change it, then $g_FBrf must be set, otherwise we're not filling in
# a mandatory piece of information. - now only mandatory for personal communication.
    unless (defined $date and $date ne '')
    {
	if (changes ($file, $code, $change))
	{
	    report ($file, "%s: Not allowed to delete date of publication.", $code);
	}
	elsif ($g_FBrf eq '' and $g_pub_type eq $PC_text){
	    report ($file, "%s: Can't omit date for personal communication.", $code);
	}
	return;
    }
    return if bad_date ($file, $code, $date); # puts out suitable messages

    if (defined $g_pub_type and $g_pub_type eq $PC_text and $date =~ /^\d{4}$/)
    {							# Just the year?  Ok for all but personal communications.
	report ($file, "%s: Date is '%s' but P1 specifies a personal communication, " .
		"which requires full YYYY.M.D date.",	$code, $date);
	return;
    }

# $date is now plausible.  It may even be correct.  The code below is very similar to that for P3, P4, etc.

    if ($g_FBrf)
    {

# If it's data for an existing publication (i.e. $g_FBrf has a value) emit warnings if P10 is changing it to the
# same thing, or if it is not changing it and there is a mismatch with the data in Chado.  In either case, we
# need to ask Chado for its opinion beforehand.

	my $existing_date = chat_to_chado ('pub_date_from_id', $g_FBrf)->[0]->[0];

	if (changes ($file, $code, $change))
	{
	    if (!defined $existing_date)
	    {
		report ($file, "%s: Trying to change date of publication to %s but the date of publication isn't yet in Chado.", $code, $date);
	    }
	    elsif ($date eq $existing_date)
	    {
		report ($file, "%s: Trying to change date of publication to the value (%s) it already has in Chado.", $code, $date);
	    }
	}
	else
	{
	    if (defined $existing_date and $date ne $existing_date)
	    {
		report ($file, "%s: Trying to set date of publication to %s but it is %s in Chado.",
			$code, $date, $existing_date);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the date of publication of a new publication!")
	    if changes ($file, $code, $change);
    }
}

sub validate_P12 ($$$)
{
# P12 specifies the list of authors for the publication.  It is a required field if P22 is not filled in (marked by
# $g_FBrf being ''). 

    my ($code, $change, $authors) = @_;
    $change = changes ($file, $code, $change);

    $authors = trim_space_from_ends ($file, $code, $authors);
    $authors =~ /\n\n/ and report ($file, "%s: Blank line not allowed in %s", $code, $authors);
    $authors =~ /\,/ and report ($file, "%s: Commas not allowed in %s", $code, $authors);

# First deal with the case of no data.  We're not allowed to change (i.e. delete) the list of authors to
# nothing.  If we're not trying to change it, then $g_FBrf must be set, otherwise we're not filling in a
# mandatory piece of information.

    unless (defined $authors and $authors ne '')
    {
	if ($change)
	{
	    report ($file, "%s: Not allowed to delete list of authors.", $code);
	}
	else
	{	if($g_FBrf eq ''){
	    report ($file, "%s: Can't omit list of authors without valid FBrf in P22", $code);
	    }
	}
	return;
    }

# Each author must have a surname, a \t and a list of initials.  Check for old-style data where the initials
# came first and could be omitted (this latter now uses '?.').

    my $fail = 0;
    foreach my $author (split ("\n", $authors))
    {
	$author = trim_space_from_ends ($file, $code, $author);
	next if $author eq '';						# Blank lines already picked up above.

	if (my ($surname, $initials) = ($author =~ /^(.*?)\t(.*)/)) #change out tab?
	{
	    unless ($initials =~ /^([A-Z?]\.)([A-Z]\.)*$/)
	    {
		report ($file, "%s: Invalid initials '%s' in '%s'", $code, $initials, $author);
		$fail = 1;
	    }
	    index ($surname, '.') == -1 or report ($file, "%s: The surname '%s' in '%s' has a dot.  Is this right?",
						   $code, $surname, $author);	# Warning only, don't set $fail.
	}
	elsif ($author =~ /^(([A-Z?]\.)([A-Z]\.)*) (\S[^?\t]*$)/) # change out tab?
	{
	    report ($file, "%s: Old-style data in '%s'.  Please use \"%s\t%s\"", $code, $author, $4, $1);
	    $fail = 1;
	}
	elsif (index ($author, '.') == -1)
	{
	    report ($file, "%s: Must not omit author's initials.  Use \"%s\t?.\" if they are unknown.",
		    $code, $author);
	    $fail = 1;
	}
	else
	{
	    report ($file, "%s: Unrecognized format for author '%s'.  Try checking whitespace and/or initials.",
		    $code, $author);
	    $fail = 1;
	}
    }
    $fail and return;			# No need to check existing data if the given data is bad.

    if ($g_FBrf)			# There is data given, so check if it's a known publication.
    {

# If it's data for an existing publication (i.e. $g_FBrf has a value) emit warnings if P12 is changing it to the
# same thing, or if it is not changing it and there is a mismatch with the data in Chado.  In either case, we
# need to ask Chado for its opinion beforehand.

	my $existing_authors_array = chat_to_chado ('pub_authors', $g_FBrf);

# The returned value is actually a reference to an array of arrays, or an undef array if there are no authors,
# which should not be possible.

	if (!defined $existing_authors_array)
	{
	    my $catastrophe = "%s: Looking for the existing list of authors for %s ";
	    $catastrophe .= "but that information isn't yet in Chado.\n";
	    $catastrophe .= "Chado should always have this data, so you've found a serious bug.\n";
	    $catastrophe .= "****** PLEASE CONTACT camdev URGENTLY! ******";
	    report ($file, $catastrophe, $code, $g_FBrf);
	    warn sprintf ($catastrophe, $code, $g_FBrf);	# Be really, really insistent.
	    return;
	}

# Assuming there is at least one author, each element of the returned value is an array with two elements, the
# givennames and the surname of each author.  The arrays are already sorted by rank, which is exactly the
# order we need.  Convert this data structure to a simple string where each author appears on a separate line.

	foreach my $author (@{$existing_authors_array})
	{
	    defined $author->[0] or $author->[0] = '?.'; # Convert missing initial to '?'
	}

# The innermost "map { join ..." puts the tab character between the family names and the initials of each author.

	my $existing_authors = defined $existing_authors_array->[1] ? 
	    join ("\n", map { join "\t", @{$_} } @{$existing_authors_array}) : '';

	if ($change)
	{
	    if ($authors eq $existing_authors)
	    {
		report ($file, "%s: Trying to change list of authors to the value\n%s\n it already has in Chado.",
			$code, $authors);
	    }
	}
	else
	{
	    if ($existing_authors ne '' and $authors ne $existing_authors)
	    {
		report ($file, "%s: Trying to set list of authors to %s but it is\n%s\n in Chado.",
			$code, $authors, $existing_authors);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the authors of a new publication!") if $change;
    }
}

sub validate_P16 ($$$)
{
# P16 specifies the title of publication.  It is a required field if it's a new publication, marked by $g_FBrf
# not having a value, and if present it must end in '.', '?'  or '!' or be an English translation within
# square brackets.

    my ($code, $change, $title) = @_;

    $title = trim_space_from_ends ($file, $code, $title);

# First deal with the case of no data.  We're not allowed to change the title of publication to nothing
# (i.e. delete it) but otherwise lack of a title is legal if and only if g_FBrf has a value.

    if (!defined $title or $title eq '')
    {	
	changes ($file, $code, $change) and report ($file, "%s: Not allowed to delete title of publication.", $code);
	$g_FBrf or report ($file, "%s: Can't omit title of publication without a valid FBrf in P22.", $code);
	return;
    }

# Simple syntax checks.

    report ($file, "%s: Title '%s' doesn't end with '.', '?' or '!'.", $code, $title) unless $title =~ /[.!?\]]$/;
    report ($file, "%s: Title '%s' must be on a single line.", $code, $title) unless index ($title, "\n") == -1;

    if ($g_FBrf) # FBrf in P22
    {

# If it's data for an existing publication (i.e. $g_FBrf has a value) emit warnings if P16 is changing it to the
# same thing, or if it is not changing it and there is a mismatch with the data in Chado.  In either case, we
# need to ask Chado for its opinion beforehand.

	my $existing_title = chat_to_chado ('pub_title_from_id', $g_FBrf)->[0]->[0];

	if (changes ($file, $code, $change))
	{
	    if (!defined $existing_title)
	    {
		report ($file, "%s: Trying to change title of publication to '%s' but a title isn't yet in Chado.",
			$code, $title);
	    }
	    elsif ($title eq $existing_title)
	    {
		report ($file, "%s: Trying to change title of publication to the value (%s) it already has in Chado.",
			$code, $title);
	    }
	}
	else
	{
	    if (defined $existing_title and $title ne $existing_title)
	    {
		report ($file, "%s: Trying to set title of publication to '%s' but it is '%s' in Chado.",
			$code, $title, $existing_title);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the title of a new publication!") if changes ($file, $code, $change);
    }
}


sub validate_P13_14 ($$$)	# Validate the list of languages for P13 and P14.
{
# P13 and P14 specify a list of languages for the paper and abstract respectively.  P13 is required to have
# data but P14 may be blank.

    my ($code, $change, $languages) = @_;
    $change = changes ($file, $code, $change);
    $languages = trim_space_from_ends ($file, $code, $languages);
    if ($languages eq '')
    {
	$code eq 'P13' and report ($file, "%s: Can't omit language(s)", $code);
	return;
    }
    check_languages ($file, $code, $change, $g_FBrf, $languages,
		     $code eq 'P13' ? 'pub_languages' : 'pub_abs_languages');	# Routine shared with MP8
}



sub validate_P25 ($$$)
{
# BIOSIS id for the publication.  There can only be one value and (for the moment at least) they look like
# /^[1-2]\d{3}\.[1-9]\d*$/.

    my ($code, $change, $biosis_id) = @_;
    $change = changes ($file, $code, $change);
    $biosis_id = trim_space_from_ends ($file, $code, $biosis_id);

    $biosis_id eq '' and return;					# Absence of data is always permissible.
    
    $biosis_id =~ /^[1-2]\d{3}\.[1-9]\d*$/ or report ($file, "%s: Invalid BIOSIS id '%s'", $code, $biosis_id);

    if ($g_FBrf)
    {
	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'BIOSIS id',
				  chat_to_chado ('pub_accession', $g_FBrf, 'biosis'), $biosis_id);
    }
    else
    {
	$change and report ($file, "%s: Can't change the BIOSIS id of a new publication", $code);
    }
}

sub validate_P26 ($$$)
{
# PubMed id for the publication.  There can only be one value and (for the moment at least) PMIDs look like
# /^[1-9]\d{7}$/.

    my ($code, $change, $pmid) = @_;
    $change = changes ($file, $code, $change);			# Call changes() to check for junk after initial !
    $pmid = trim_space_from_ends ($file, $code, $pmid);
    $P26_data = $pmid;  # preserve for checks after whole proforma has been checked
    $pmid eq '' and return;					# Absence of data is always permissible.
    $pmid =~ /^[1-9]\d{7}$/ or report ($file, "%s: Most PubMed id's have 8 digits, are you sure '%s' is a valid id?", $code, $pmid);

    if ($g_FBrf)
    {
	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'PubMed id',
				  chat_to_chado ('pub_accession', $g_FBrf, 'pubmed'), $pmid);
    }
    else
    {
	$change and report ($file, "%s: Can't change the PubMed id of a new publication", $code);
    }
}

sub validate_P27 ($$$)
{
# ZooRec_id for the publication.  There can only be one value and (for the moment at least) ZRIDs look like
# /^[1-9]\d{10}$/.

    my ($code, $change, $zrid) = @_;
    $change = changes ($file, $code, $change);			# Call changes() to check for junk after initial !
    $zrid = trim_space_from_ends ($file, $code, $zrid);
   
    $zrid eq '' and return;					# Absence of data is always permissible.
    $zrid =~ /^[1-9]\d{10}$/ or report ($file, "%s: Invalid ZooRec id '%s'", $code, $zrid);

    if ($g_FBrf)
    {
	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'ZooRec id',
				  chat_to_chado ('pub_accession', $g_FBrf, 'zoorec_id'), $zrid);
    }
    else
    {
	$change and report ($file, "%s: Can't change the ZooRec id of a new publication", $code);
    }
}

sub validate_P29 ($$$)
{
# ISBN for the publication.  At present only if the publication type is "book", though the latter condition is
# not enforced until the post-check phase.  Note a book can have two or more ISBN --- hardback and softback
# editions of the same text, for instance.

    my ($code, $change, $isbn_list) = @_;
    $change = changes ($file, $code, $change);
    $isbn_list = trim_space_from_ends ($file, $code, $isbn_list);
    return if $isbn_list eq '';					# Absence of data is always permissible.

    $isbn_list =~ s/\n\n+/\n/g and report ($file, "%s: Blank line in ISBN-list.", $code);
    my @isbn13_list = ();
    foreach my $isbn (split ('\n', $isbn_list))
    {
	$isbn = trim_space_from_ends ($file, $code, $isbn);
	next if $isbn eq '';					# Absence of data is always permissible.

	if (my $isbn13 = convert_to_ISBN13 ($isbn))		# Returns zero if not valid ISBN-10 or ISBN-13
	{
	    $isbn eq $isbn13 or
		report ($file,"%s: Please change the ISBN-10 %s to the ISBN-13 equivalent, which is %s",
			$code, $isbn, $isbn13);
	    push @isbn13_list, $isbn13
	}
	else
	{
	    report ($file, "%s: Invalid ISBN '%s'", $code, $isbn);
	}

    }
# Each ISBN is now plausible.
    if ($g_FBrf)
    {
	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'ISBN',
				  chat_to_chado ('pub_accession', $g_FBrf, 'isbn'), @isbn13_list);
    }
    else
    {
	$change and report ($file, "%s: Can't change the ISBN of a new publication", $code);
    }
}


sub validate_P23 ($$$)
{
# P23 contains the text of a Personal Communication.  If present, there is very little constraint on its
# contents.

    my ($code, $change, $pc) = @_;
    $change = changes ($file, $code, $change);			# Call changes() to check for junk after initial !

    if (defined $g_pub_type and $g_pub_type eq $PC_text)
    {
	if ($g_FBrf)
	{
	    $pc_summary = 1;					# An existing publication necessarily has a text!
	    if ($change)
	    {
		$pc eq '' and report ($file, "%s: Can't delete the PC text of an existing publication, %s.",
				      $code, $g_FBrf);
	    }
	    else
	    {
		$pc eq '' or report ($file, "%s: Can't set the PC text of an existing publication, %s.",
				     $code, $g_FBrf);
	    }
	}
	else
	{
	    $change and report ($file, "%s: Can't change the PC text of a new publication", $code);
	}
    }
    else
    {
	$pc ne '' and report ($file, "%s: Can't specify the text of a PC when P1 is not '%s'.", $code, $PC_text);
    }
}

sub validate_P18 ($$$)
{
#  Associated text --- essentially nothing to check, apart from attempts to change a non-existent publication.

    my ($code, $change, $pc) = @_;
    if ($change = changes ($file, $code, $change))
    {
	$g_FBrf or report ($file, "%s: Can't change the associated text of a new publication", $code);
    }
}



sub validate_P38 ($$$)
{
# P38 specifies the list of files, one per line, which have been deposited at IU.

    my ($code, $change, $file_list) = @_;

    $change = changes ($file, $code, $change);		# Call changes() to check for junk after initial !
    $file_list =~ s/\s*$//gs;		# Because blank line at end of proforma is common and P38 is the last field.

# Lack of data is always valid.  It means that either we've nothing to add or we wish to delete the reference
# to any deposited files.

    return if $file_list eq '';

    my @dep_files = split (/\n/, $file_list);

    my %dups = ();
    foreach my $dep_file (@dep_files)			# Check for duplicates in @dep_files to pick up pastos.
    {
	$dep_file = trim_space_from_ends ($file, $code, $dep_file);
	if (exists $dups{$dep_file})
	{
	    $dups{$dep_file}++;
	}
	else
	{
	    $dups{$dep_file} = 0;
	}
    }
    foreach my $dep_file (keys %dups)
    {
	report ($file, "%s: Duplicated file specification '%s'", $code, $dep_file) if $dups{$dep_file};
    }

    my %dup_names = ();			# Check individual file names, not likely to be pastos this time around.
    my $fail = 0;
    foreach my $dep_file (keys %dups)	# Validate each file in turn.
    {
	if (my ($date, $size, $format, $name) =
	       ($dep_file =~ /File date: (.*?) ; File size: (.*?) ; File format: (.*?) ; File name: (.*)/))
	{
	    $date = trim_space_from_ends ($file, $code, $date);
	    $size = trim_space_from_ends ($file, $code, $size);
	    $format = trim_space_from_ends ($file, $code, $format);
	    $name = trim_space_from_ends ($file, $code, $name);

	    $fail = bad_date ($file, $code, $date);
	    unless ($size =~ /^[1-9]\d*$/)
	    {
		report ($file, "%s: Bad file size specification '%s'", $code, $size);
		$fail = 1;
	    }
	    unless ($format =~ /^[a-z][a-z0-9]*$/i)
	    {
		report ($file, "%s: Bad file format specification '%s'", $code, $format);
		$fail = 1;
	    }

	    if (exists $dup_names{$name})
	    {
		$dup_names{$name}++;
	    }
	    else
	    {
		$dup_names{$name} = 0;
	    }
	    if ($name =~ /^(\S*?\.)((\d+)((\.\d+)*))(-\d+)?(\.\S+)/)
	    {
		$fail |= bad_date ($file, $code, $2);
	    }
	    else
	    {
		report ($file, "%s: Bad file name specification '%s'", $code, $name);
		$fail = 1;
	    }
	}
	else
	{
	    report ($file, "%s: Bad file specification '%s'", $code, $dep_file);
	    $fail = 1;
	}
    }
    foreach my $name (keys %dup_names)
    {
	report ($file, "%s: Duplicated file name '%s'", $code, $name) if $dups{$name};
	$fail = 1;
    }

    return if $fail;

# Static tests on the file details now completed, so check with Chado at this point.

# WTF do we ask Chado anyway?  The data in there at present is not very helpful:
#
#
# fb_2006_01_11= SELECT pub.uniquename, pubprop.value, pubprop.rank from pub, pubprop, cvterm
# WHERE pub.uniquename = 'FBrf0188617' and pub.pub_id = pubprop.pub_id and cvterm.cvterm_id=pubprop.type_id and
# cvterm.name='deposited_files';
#  uniquename  |                                                value                                                 | rank
#  -------------+------------------------------------------------------------------------------------------------------+------
#  FBrf0188617 | File date: 2005.5.10 ; File size: 80451 ; File format: html ; File name: Rehmsmeier.2005.5.10-1.html
# File date: 2005.5.10 ; File size: 109956 ; File format: txt ; File name: Rehmsmeier.2005.5.10-2.txt |    0
# (1 row)

# We can use the above query to validate just the one file.  If more than one, punt for the moment.  See ticket 203.

    if ($#dep_files > 0)
    {
	report ($file, "%s: Don't yet know how to validate more than one file with Chado.", $code);
	return;
    }

    if ($g_FBrf)
    {
	my $existing_files = chat_to_chado ('pub_files', $g_FBrf)->[0]->[0];

	if ($change)
	{
	    if ($file_list eq $existing_files)
	    {
		report ($file, "%s: Trying to change list of deposited files to the value (%s) " .
			"it already has in Chado.", $code, $file_list);
	    }
	}
	else
	{
	    if ($file_list ne '' and $existing_files ne '' and $file_list ne $existing_files)
	    {
		report ($file, "%s: Trying to set files list to '%s' but it is '%s' in Chado.",
			$code, $file_list, $existing_files);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	$change and report ($file, "%s: Can't change the files list of a new publication", $code);
    }
}

sub validate_P39 ($$$)
{
# Delete FBrf from biblio.  The data, if present, must be the single character 'y' and !c can not be used.

    my ($code, $change, $delete) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c", $code);
    $delete = trim_space_from_ends ($file, $code, $delete);
    $delete eq '' and return;				# Absence of data is always acceptable.

    if ($delete eq 'y')
    {
	if ($g_FBrf)
	{
	    report ($file, "%s: Do you really want to delete %s?", $code, $g_FBrf);
	}
	else
	{
	    report ($file, "%s: Trying to delete something which, according to Chado, " .
		    "is not a currently valid publication", $code);
	}
    }
    else
    {
	report ($file, "%s: Incorrect data '%s' --- must be 'y' or left blank.", $code, $delete);
    }
}


sub crosscheck_P41_P43_P44 ($$$) {

	my ($p41_data,$p43_data,$p44_data) = @_;

	my %crosschecks = ();
	my %p43_flags = ();

    my @p41_flags = split (/\n/, $p41_data);
	foreach my $flag (@p41_flags) {
		if ($flag eq 'disease' || $flag eq 'disease::DONE' || $flag eq 'diseaseHP' || $flag eq 'diseaseHP::DONE')   {
	    	$crosschecks{p41}++;
		}
	}


    my @p43_flags = split (/\n/, $p43_data);
	foreach my $flag (@p43_flags) {
	    	$crosschecks{p43}++;
			$p43_flags{$flag}++;
	}


	if ($crosschecks{p41}) {

		unless ($crosschecks{p43}) {

			if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge') {

				unless (scalar keys %{$triage_flags_in_chado->{'P43'}} >= 1) {
					report ($file, "P41 contains a \'disease'\ flag, but P43 is empty - you must fill in a disease type flag in P43 if P41 contains the \'disease'\ flag");
				}
			} else {
				if (valid_symbol ($file, 'record_type') eq 'AUTHOR' or valid_symbol ($file, 'record_type') eq 'SKIM') {
					report ($file, "P41 contains a disease type flag, but P43 is empty - you must fill in a disease type flag in P43 if P41 contains a disease type flag");

				}
			}


		} else {
			if ($p43_flags{noDOcur}) {
				report ($file, "P41 contains a \'disease'\ flag, and P43 contains \'noDOcur\' - one of these must be wrong.");
			}
		}

## only test p44 for user and skim records
		if (valid_symbol ($file, 'record_type') eq 'AUTHOR' or valid_symbol ($file, 'record_type') eq 'SKIM') {
			unless ($p44_data) {
				report ($file, "P41 contains a \'disease'\ flag, but P44 is empty - you must fill in a disease term in P44 if P41 contains the \'disease'\ flag.");
			}
		}
	}

	if ($crosschecks{p43}) {

		unless ($p43_flags{noDOcur}) {

			unless ($crosschecks{p41}) {

				if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge') {

					unless (exists $triage_flags_in_chado->{'P41'} && (exists $triage_flags_in_chado->{'P41'}->{'disease'} || exists $triage_flags_in_chado->{'P41'}->{'disease::DONE'} || exists $triage_flags_in_chado->{'P41'}->{'diseaseHP'} || exists $triage_flags_in_chado->{'P41'}->{'diseaseHP::DONE'})) {
						report ($file, "P43 contains disease type flag(s), but P41 does not contain a disease type flag - you must fill in a disease type flag in P41 if P43 contains disease type flag(s).");
					}

				} else {
					if (valid_symbol ($file, 'record_type') eq 'AUTHOR' or valid_symbol ($file, 'record_type') eq 'SKIM') {
						report ($file, "P43 contains disease type flag(s), but P41 does not contain a \'disease'\ flag - you must fill in the \'disease'\ flag in P41 if P43 contains disease type flag(s).");

					}
				}
			}

## need to take into account flags in chado here - or could make it so that P44 not compulsory and only do reciprocal check
## only test p44 for user and skim records
			if (valid_symbol ($file, 'record_type') eq 'AUTHOR' or valid_symbol ($file, 'record_type') eq 'SKIM') {
				unless ($p44_data) {
					report ($file, "P43 contains disease type flag(s), but P44 is empty - you must fill in a disease term in P44 if P43 contains disease type flag(s).");
				}
			}
		}
	}

	if ($p44_data) {

		if (valid_symbol ($file, 'record_type') eq 'AUTHOR' or valid_symbol ($file, 'record_type') eq 'SKIM') {

			unless ($crosschecks{p41}) {
				report ($file, "P44 contains data, but P41 does not contain a \'disease'\ flag - you must fill in the \'disease'\ flag in P41 if P44 contains data.");
			}

			unless ($crosschecks{p43}) {
				report ($file, "P44 contains data, but P43 is empty - you must fill in disease type flag(s) in P43 if P44 contains data.");
			}
		}
	}
}


sub validate_P28 ($$$)
{
# PubMed Central ID for the publication.  There can only be one value and (for the moment at least) PMIDs look like
# /^[1-9]\d{7}$/.

    my ($code, $change, $pmcid) = @_;
    $change = changes ($file, $code, $change);			# Call changes() to check for junk after initial !
    $pmcid = trim_space_from_ends ($file, $code, $pmcid);
    $pmcid eq '' and return;					# Absence of data is always permissible.

	single_line ($file, $code, $pmcid, $proforma_fields{$code}) or return;

    $pmcid =~ /^PMC[0-9]{7,}$/ or report ($file, "%s: Invalid PubMed Central ID format '%s'", $code, $pmcid);


	$P28_data = $pmcid; # preserve for checks after whole proforma has been checked

    if ($g_FBrf)
    {

	check_changes_with_chado ($file, $code, $change, $g_FBrf, 'PubMed Central ID',
				  chat_to_chado ('pub_accession', $g_FBrf, 'PMCID'), $pmcid);
    }
    else
    {
	$change and report ($file, "%s: Can't change the PubMed Central ID of a new publication", $code);
    }
}


sub validate_P34 {

    my ($code, $change, $abstract) = @_;
    $change = changes ($file, $code, $change);			# Call changes() to check for junk after initial !

    $abstract = trim_space_from_ends ($file, $code, $abstract);

	$P34_data = $abstract; # preserve for checks after whole proforma has been checked

}

sub validate_P45 ($$$)
{ 
    my ($code, $change, $data) = @_;
    if (changes ($file, $code, $change))
    {
	$g_FBrf or report ($file, "%s: Can not use !c without a valid FBrf", $code);
    }

	single_line ($file, $code, $data, $proforma_fields{$code}) or return;
	$data eq '' and return;

    $data = trim_space_from_ends ($file, $code, $data);
    

	if ($data =~ m/ \# /) {

		report ($file, "%s: No hashes allowed in this field (to ensure robust checking): %s", $code, $data);
		return;
	}

	if ($data eq 'y') {

		report ($file, "%s: Do you REALLY want to mark the '%s' publication(s) as 'NOT about Drosophila'?", $code, $g_FBrf);

	} else {

		report ($file, "%s: '%s' not allowed (field must either contain \'y\' or be empty)", $code, $data);

	}
}

sub validate_triage_flags {
# deliberately not using process_field_data + %field_specific_checks format
# as need to know whether or not !c is present in the field to carry out
# checks in some cases, and that information is not passed on to the
# field specific checks from process_field_data

# Input variables
# $file = curation record filename
# $change = data between the ! of the proforma field text and the proforma field code
# $code = proforma field being checked
# $flags = entire contents of proforma field, without proforma field text



	my ($file, $change, $code, $flags, $context) = @_;

	my $field_specific_info = {

		'allowed_to_be_empty_by_record_type' => {
# only fields which can be compulsory under some circumstances (i.e. P41, P43)
# should be a key here. Fields which are always allowed to be empty (P40, P42)
# should never need to be listed in this section. 
			'P41' => { 'BIBL' => '1', 'EDIT' => '1', 'EXPRESSION' => '1', 'PHEN' => '1'},
			'P43' =>  { 'BIBL' => '1', 'EDIT' => '1', 'EXPRESSION' => '1', 'AUTHOR' => '1', 'SKIM' => '1', 'PHEN' => '1', 'THIN' => '1', 'COLL' => '1'},
		},

		'allowed_to_be_empty_by_pub_type' => {
# only fields which can be compulsory under some circumstances (i.e. P41, P43)
# should be a key here. Fields which are always allowed to be empty (P40, P42)
# should never need to be listed in this section. 

			'P41' => { 'review' => '1', 'FlyBase analysis' => '1' },
			'P43' => { 'review' => '1', 'FlyBase analysis' => '1' },

		},

		'negative_flag' => {
			'P41' => 'no_flag',
			'P43' => 'noDOcur',

		},

		'done_allowed' => {
			'P40' => 0,
			'P41' => 1,
			'P42' => 1,
			'P43' => 1,
		},

	};



# sanity check for data structure above
	foreach my $field (keys %{$field_specific_info->{'allowed_to_be_empty_by_record_type'}}) {
		unless (exists $field_specific_info->{'negative_flag'}->{$field}) {
			report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nThe field_specific_info data structure is missing a negative_flag value for the %s field (which is not allowed to be empty under most circumstances).",$field,$field);
		return;
		}
	}

	foreach my $field (keys %{$field_specific_info->{'allowed_to_be_empty_by_pub_type'}}) {
		unless (exists $field_specific_info->{'negative_flag'}->{$field}) {
			report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nThe field_specific_info data structure is missing a negative_flag value for the %s field (which is not allowed to be empty under most circumstances).",$field,$field);
		return;
		}
	}

	if (changes ($file, $code, $change)) {

		if ($g_FBrf) {
			if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge') {
				unless (scalar keys %{$triage_flags_in_chado->{$code}} >= 1) {
					report ($file, "%s: Can't !c a field that has no data in chado (!).", $code);
				}
			}
    	} else {

			report ($file, "%s: Can not use !c without a valid FBrf", $code);
		}
	}

	$flags = trim_space_from_ends ($file, $code, $flags);


	if ($flags eq '') {

# this loop checks fields which must be filled in under some circumstances
		if (exists $field_specific_info->{'allowed_to_be_empty_by_record_type'}->{$code} || exists $field_specific_info->{'allowed_to_be_empty_by_pub_type'}->{$code}) {

			my $record_type = valid_symbol ($file, 'record_type');
			if (exists $field_specific_info->{'allowed_to_be_empty_by_record_type'}->{$code}->{$record_type}) {
				return $flags;
			}


			if (defined $g_pub_type && $g_pub_type ne '') {
				if (exists $field_specific_info->{'allowed_to_be_empty_by_pub_type'}->{$code}->{$g_pub_type}) {
					return $flags;
				}
			}
			
			if ($change) {
# add code to take into account what it already in chado here. Only done if running in
# Cambridge at the moment, since it requires a copy of the support_scripts folder in
# addition to the Peeves code.

				if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge') {
					if (scalar keys %{$triage_flags_in_chado->{$code}} >= 1) {
						report ($file, "%s: You cannot !c this field to nothing - if there is no positive flag to add, use '%s'", $code,$field_specific_info->{'negative_flag'}->{$code});
					}
				} else {

					report ($file, "%s: You cannot !c this field to nothing - if there is no positive flag to add, use '%s'.\n(NOTE: this may be a false positive if the paper has already been skimmed/user curated).", $code,$field_specific_info->{'negative_flag'}->{$code});

				}

			} else {
				if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge') {

					unless (scalar keys %{$triage_flags_in_chado->{$code}} >= 1) { # triage data already exists in chado
						report ($file, "%s: Missing data - if there is no positive flag to add, use '%s'.", $code, $field_specific_info->{'negative_flag'}->{$code});
					}

				} else {

					if (valid_symbol ($file, 'record_type') eq 'AUTHOR' or valid_symbol ($file, 'record_type') eq 'SKIM') {
						report ($file, "%s: Missing data - if there is no positive flag to add, use '%s'.\n(NOTE: this may be a false positive if the paper has already been skimmed/user curated).", $code, $field_specific_info->{'negative_flag'}->{$code});
					}
				}
		
			}
		}


	} else {

		my $uniqued_flags = check_for_duplicated_lines($file, $code, $flags, $context->{$code});


		foreach my $flag (keys %{$uniqued_flags}) {


# not wild about having this here rather than more robustly encoded for each field, but it will work
			if ($flag eq 'noGOcur') {
				unless (valid_symbol ($file, 'curator_type') eq 'GOCUR') {
					report ($file, "%s: The '%s' flag should only be used by the GO curator, did you add it by mistake ?",$code, $flag);
				}
			}

			if (valid_symbol ($flag, sprintf ("%s_flag", $code))) {

				if (valid_symbol ($flag, sprintf ("%s_flag", $code)) eq 'solo') {

					if (scalar keys %{$uniqued_flags} > 1) {
						report ($file, "%s: '%s' incorrectly used in combination with other flags.", $code, $flag);
					}

					if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge' && scalar keys %{$triage_flags_in_chado->{$code}} >= 1) {
						unless ($change) {

							if (scalar keys %{$triage_flags_in_chado->{$code}} == 1) {

								unless (exists $triage_flags_in_chado->{$code}->{$flag}) {
									report ($file, "%s: '%s' is present in the curation record, but '%s' already exists in chado (did you mean to !c ?)",$code, $flag, (join ", ", sort keys %{$triage_flags_in_chado->{$code}}));
								}

							} else {

								report ($file, "%s: '%s' is present in the curation record, but '%s' already exists in chado (did you mean to !c ?)",$code, $flag, (join ", ", sort keys %{$triage_flags_in_chado->{$code}}));
							}
						}
					}

				}


# not wild about having this here rather than more robustly encoded for each field, but it will work
				if ($code eq 'P43' && valid_symbol ($file, 'record_type') eq 'AUTHOR') {
					unless ($flag eq 'disease') {
						report ($file, "%s: user records should only use the 'disease' flag, please replace the '%s' flag with 'disease'", $code, $flag);
					}
				}



			} else {

				if (exists $field_specific_info->{'done_allowed'}->{$code} && $field_specific_info->{'done_allowed'}->{$code}) {

					if ($flag =~ m|::DONE$|) {

						my $temp_flag = $flag;
						$temp_flag =~ s|::DONE$||;

						if (valid_symbol ($temp_flag, sprintf ("%s_flag", $code))) {

							if (valid_symbol ($temp_flag, sprintf ("%s_flag", $code)) eq 'solo') {
								report ($file, "%s: Can't add '::DONE' to the '%s' flag.", $code, $temp_flag);
							}

						} else {
							report ($file, "%s: Invalid flag used: '%s' ", $code, $flag);
						}
					} else {
						report ($file, "%s: Invalid flag used: '%s' ", $code, $flag);
					}

				} else {
					report ($file, "%s: Invalid flag used: '%s' ", $code, $flag);
				}
			}
		}

		if (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge') {

			foreach my $flag (keys %{$triage_flags_in_chado->{$code}}) {

				if (valid_symbol ($flag, sprintf ("%s_flag", $code)) eq 'solo') {
	
					if (scalar keys %{$uniqued_flags} >= 1) {

						unless ($change) {

							if (scalar keys %{$uniqued_flags} == 1) {

								unless (exists $uniqued_flags->{$flag}) {
									report ($file, "%s: '%s' is already present in chado (chado flags are: %s), but you have added '%s' to the curation record (did you mean to !c ?)",$code, $flag, (join ", ", sort keys %{$triage_flags_in_chado->{$code}}), (join ", ", sort keys %{$uniqued_flags}));
								}

							} else {
								report ($file, "%s: '%s' is already present in chado (chado flags are: %s), but you have added '%s' to the curation record (did you mean to !c ?)",$code, $flag, (join ", ", sort keys %{$triage_flags_in_chado->{$code}}), (join ", ", sort keys %{$uniqued_flags}));
							}
						}
					}
				}
			}
		}


	}

	return $flags;

}


sub compare_pub_fbrf_containing_fields {

# This subroutine checks that the same FBrf is not present
# in a pair of fields given.

	my ($file, $code1, $data1, $code2, $data2, $context) = @_;



	my $field1_data = {};
	my $duplicated_data = {};

	foreach my $datum (split (/\n/, $data1)) {
		$field1_data->{$datum}++;
	}


	foreach my $datum (split (/\n/, $data2)) {

		if (exists $field1_data->{$datum}) {
			$duplicated_data->{$datum}++;

		}
	}

	foreach my $datum (keys %{$duplicated_data}) {

		report ($file, "%s and %s must NOT contain the same data '%s'\n!%s\n!%s", $code1, $code2, $datum, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');
	}
}

sub check_pub_accession_against_chado {

# Check whether the 'accession' (dbxref) in a publication field is already in chado
# If it is in chado already:
# for new publications, warn that are trying to add an accession already in chado to a new publication
# for existing publications, check that the FBrf the accession is associated with in chado is the same as the FBrf in P22 (and warn if not).

	my ($file, $code, $FBrf, $P32_list, $accession, $type, $label) = @_;

	my $chado_ref = chat_to_chado ('accession_pub', $accession, $type);

	if (defined $chado_ref) {

		foreach my $element (@{$chado_ref}) {

			my ($FBrf_in_chado) = @{$element};

			unless ($FBrf_in_chado eq $FBrf) {

				if ($FBrf) {

					unless ($P32_list) {
						report ($file, "%s: The %s '%s' is already in chado under a different FBrf (%s) from the value in P22 (%s)", $code, $label, $accession, $FBrf_in_chado, $FBrf);
					} else {
						my $switch = 0;
						my @losing_FBrfs = split '\n', $P32_list;
						foreach my $losing_FBrf (@losing_FBrfs) {

							if ($FBrf_in_chado eq $losing_FBrf) {
								$switch++;
							}
						}

						unless ($switch) {

							report ($file, "%s: The %s '%s' is already in chado under a different FBrf (%s) from the values in P22 (%s) and in P32 (%s)", $code, $label, $accession, $FBrf_in_chado, $FBrf, (join ', ', @losing_FBrfs));

						}
					}
				} else {


					report ($file, "%s: The %s '%s' is already in chado under %s but you are trying to add it to a new publication.", $code, $label, $accession, $FBrf_in_chado);
				}
			}
		}
	}


}

1;				# Standard boilerplate.
