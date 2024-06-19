# Code to parse aberration proformae

use strict;
# A set of global variables for communicating between different proformae.

our $g_FBrf;			# Publication ID: from P22 to (G31b, GA32b, A27b, AB11b)
our $g_pub_type;		# Publication type: from P1 to (*[12]b, GA10[a-h])
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

# $g_num_syms is the number of symbols in a hash list in either G1a (gene.pl) or A1a (aberration.pl).
# $g_num_syms is used within gene.pl or aberration.pl when calling dehash in checking of fields
# within the gene or aberration proforma, hence these modules have no need for a file-global
# $hash_entries variable, as $g_num_syms is used.
# $g_num_syms is used in allele.pl and balancer.pl (hence it is a Peeves-global variable)
# to check that only one of the gene+allele or aberration+balancer pair contains hashing.
# This should be the only use of $g_num_syms in allele.pl or balancer.pl and these two modules
# use a file-global $hash_entries variable when calling dehash in checking of fields within
# the allele or balancer (variant) proforma. gm131210.
our $g_num_syms;

our @g_assoc_aberr;		
our (%fsm, $want_next, $chado, %prepared_queries);
our %x1a_symbols;		# For detecting duplicate proformae in a record

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl


my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (A1a A1g);	# Fields which must be present in the proforma
my %can_dup = (A90a => 1, A90b => 1, A90c => 1, A90h => 1, A90j => 1, A91a => 1, A91b => 1, A91c => 1, A91d => 1, A91e => 1, A92a => 1, A92b => 1, A92c => 1, A92d => 1, A92e => 1);		# Fields which may be duplicated in a proforma.

my $primary_symbol_list;						# Reference to dehashed data from primary symbol field


my @FBab_list = ();		# List of FBab identifiers given in A1h
my @A1b_list = ();		# List of lists of aberration names given in A1b
my @A1e_list = ();		# Dehashed data from A1e
my @A1f_list = ();		# Dehashed data from A1f
my @A2a_list = ();		# Dehashed data from A2a. (Not currently being used, in place for when tackle DC-423).
my @A2b_list = ();		# List of lists of aberration names given in A2b
my @A2c_list = ();		# Dehashed data from A2c. (Not currently being used, in place for when tackle DC-423).
my @A8a_number = ();		# The number of breakpoints in A8a for each hash-list element.
my $firstAbberation; # because A1h comes before A1a

# the arrays below store data returned by process_field_data, so are dehashed, but have NOT
# been split on \n
my @A6_list = ();		# keeping this here as may eventually need to communicate between aberration and allele data (needs to be our in that case ?) if full checking is implemented. [gm140627]
my @A4_list = ();		# keeping this here as may eventually need to communicate between aberration and allele data (needs to be our in that case ?) if full checking is implemented. [gm140627]


sub do_aberration_proforma ($$)
{
# Process an aberration proforma, the text of which is in the second argument which has been read from the
# file named in the first argument.

    ($file, $proforma) = @_;			# Set global variables for convenience.

    %proforma_fields = ();
	%dup_proforma_fields = ();

# The first occurring A1a record defines the number of expected symbols in a hash list.

    $proforma =~ /!.? A1a\..*? :(.*)/;		# Get A1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$g_num_syms = split / \# /, $1;		# Count fields
	$firstAbberation=$1;
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.
	my $primary_species_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;

# A set of local variables for post-checks.

    my $A1g_data = '';			# The y/n data found in A1g.

# clear out the variables at the start of each proforma, so that they are cleared out
# even if the corresponding proforma field is omitted.
    @FBab_list = ();
    @A1b_list = ();
    @A1e_list = ();
    @A1f_list = ();
    @A2a_list = ();
    @A2b_list = ();
	@A2c_list = ();
    @A8a_number = ();

	my @A1g_list = ();

# the arrays below store data returned by process_field_data, so are dehashed, but have NOT
# been split on \n

# these variables are needed for checking between different types of proforma, so declared above
    @A6_list = ();
    @A4_list = ();


# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
	my @A9_list = ();
	my @A23_list = ();
	my @A26_list = ();
	my @A90a_list = ();
	my @A90b_list = ();
	my @A90c_list = ();
	my @A90h_list = ();
	my @A90j_list = ();
	my @A91a_list = ();
	my @A91b_list = ();
	my @A91c_list = ();
	my @A91d_list = ();
	my @A91e_list = ();
	my @A92a_list = ();
	my @A92b_list = ();
	my @A92c_list = ();
	my @A92d_list = ();
	my @A92e_list = ();
	my @A30_list = ();
	my @A30a_list = ();


FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?) (A1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_A1h ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (A1a)\..*? :(.*)/s)
	{

	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);

# If the primary proforma field does not pass the basic test that it
# is not empty AND contains a single line of data
# return and do not try to check the remaining fields.
# The $want_next variable is set to that expected next after this
# proforma type, to make sure that the next proforma will be checked
# (this is technically only required for those proformae that have
# child proformae nested under them e.g. gene->allele, aberration->balancer
# but put it in all primary profomra fields, in case the $want_next
# requirements for others change at a later date, to be safe).

		unless (contains_data ($file, $code, $data, $proforma_fields{$code}) && single_line ($file, $code, $data, $proforma_fields{$code})) {
			$want_next = $fsm{'ABERRATION'};
			return;
		}


		($primary_symbol_list, $primary_species_list) = validate_primary_proforma_field ($file, $code, $change, $g_num_syms, $data, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?) (A1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A1b_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		unless (double_query ($file, $2, $3)) {
			@A1e_list = validate_rename ($file, $2, $g_num_syms, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?) (A1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		unless (double_query ($file, $2, $3)) {
			@A1f_list = validate_x1f ($file, $2, $g_num_syms, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?) (A1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    $A1g_data = $3; # for now, keeping $A1g_data (not dehashed) as well as storing @A1g_list (dehashed), until worked out whether its safe/desirable to change existing code to use dehashed @A1g_list version [gm140625]

		unless (double_query ($file, $2, $3)) {
			@A1g_list = validate_x1g ($file, $2, $g_num_syms, $1, $3, $proforma_fields{$2});
		}

#	    double_query ($file, $2, $3) or validate_x1g ($file, $2, $1, $3, $proforma_fields{$2});
	}
	elsif ($field =~ /^(.*?) (A2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A2a_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A2b_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?) (A2c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A2c_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A27a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (A27b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}
	elsif ($field =~ /^(.*?) (A4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A4_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?) (A6)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A6_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A22a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_A22a ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (A22b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A23)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A23_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A7[a-f])\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A7x)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A17)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A19a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_A19a ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (A19b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_A19b ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (A8a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_A8a ($2, $1, $3);
	}

	elsif ($field =~ /^(.*?) (A9)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A9_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}


	elsif ($field =~ /^(.*?) (A18)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A26)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A26_list = process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A24a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A24b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A14)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A25[a-f])\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A25x)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A21)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A28)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A15)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A90a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A90a_list, process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A90b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A90b_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A90c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A90c_list, process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A90h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A90h_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A90j)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A90j_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (A91a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A91a_list, process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A91b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A91b_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A91c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A91c_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A91d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A91d_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A91e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A91e_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A92a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A92a_list, process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A92b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A92b_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');

	}
	elsif ($field =~ /^(.*?) (A92c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A92c_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');

	}
	elsif ($field =~ /^(.*?) (A92d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A92d_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A92e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $g_num_syms, $3);
		push @A92e_list, process_field_data ($file, $g_num_syms, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A29)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_A29 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (A30)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A30_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (A30a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@A30a_list = process_field_data ($file, $g_num_syms, $1, '0', $2, $3, \%proforma_fields, '1');
	}


	elsif ($field =~ /^(.*?) A(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*A.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in aberration.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

# Start of tests that can only be done after parsing the entire proforma.

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

    if ($g_num_syms and exists $proforma_fields{'A1h'})#new at March 09 ie was in test>>production
    {
	cross_check_FBid_symbol ($file, 1, 0, 'FBab', 'aberration', $g_num_syms,
				 'A1h', \@FBab_list, 'A1a', $primary_symbol_list,
				 'A1e', \@A1e_list,  'A1f', \@A1f_list);
    }

    if (exists $proforma_fields{'A1g'})
    {
	cross_check_1a_1g ($file, 'A', 'FBab', 'aberration', $g_num_syms, $A1g_data, $primary_symbol_list);
    }

# If A1e is filled in, check A1g is 'n'
	if ($g_num_syms and exists $proforma_fields{'A1e'}) {

		cross_check_x1e_x1g ($file, 'A1e', $g_num_syms, $A1g_data, \@A1e_list, $proforma_fields{'A1e'});

	}


# A1e and A1f must not both contain data.

    rename_merge_check ($file, 'A1e', \@A1e_list, $proforma_fields{'A1e'}, 'A1f', \@A1f_list, $proforma_fields{'A1f'});

# check for rename across species.
	check_for_rename_across_species ($file, $g_num_syms, 'A', $primary_species_list, \@A1e_list, \%proforma_fields);


# no !c if A1f is filled in

	plingc_merge_check ($file, $change_count,'A1f', \@A1f_list, $proforma_fields{'A1f'});

# cross-checks for fullname renames
	cross_check_full_name_rename ($file, 'A', $g_num_syms, $primary_symbol_list, \@A1e_list, \@A2c_list, \%proforma_fields);

check_filled_in_for_new_feature ($file, 'A9', $g_num_syms, \@A9_list, \@A1g_list, \@A1e_list, \@A1f_list, \%proforma_fields, 'yes');
check_filled_in_for_new_feature ($file, 'A26', $g_num_syms, \@A26_list, \@A1g_list, \@A1e_list, \@A1f_list, \%proforma_fields, 'yes');

# if any of A90[bchj] are filled in, A90a must be filled in.
compare_duplicated_field_pairs ($file, 'A90b', \@A90b_list, 'A90a', \@A90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'A90c', \@A90c_list, 'A90a', \@A90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'A90h', \@A90h_list, 'A90a', \@A90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'A90j', \@A90j_list, 'A90a', \@A90a_list, \%dup_proforma_fields, 'dependent', '');



## checks for the A90b/A90c pair - in almost all cases, both fields must be filled in if one of them is.
## the single exception is when A90b is !c to nothing - in that case, A90c should be blank
# only perform check if no hashing in proforma to ensure correct checking as A90b/A90c can be duplicated
if ($g_num_syms == 1) {

# the following is based on compare_duplicated_field_pairs

	if ($#A90b_list == $#A90c_list) {
		for (my $i = 0; $i <= $#A90b_list; $i++) {

			my $A90b_plingc = $dup_proforma_fields{'A90b'}[$i];
			$A90b_plingc =~ s/^(.*?)\s+A90b\..*? :.*/$1/s;

			# need to build the context information in the correct format to pass to compare_pairs_of_data from the %dup_proforma_fields hash
			my %local_context = ();
			$local_context{'A90b'} = $dup_proforma_fields{'A90b'}[$i];
			$local_context{'A90c'} = $dup_proforma_fields{'A90c'}[$i];

			if (changes ($file, 'A90b', $A90b_plingc)) {


				if (defined $A90b_list[$i] && $A90b_list[$i] ne '') {

					compare_pairs_of_data ($file, 'A90b', $A90b_list[$i], 'A90c', $A90c_list[$i], \%local_context, 'pair::if either is filled in', '');
				} else {

					compare_pairs_of_data ($file, 'A90c', $A90c_list[$i], 'A90b', $A90b_list[$i], \%local_context, 'dependent::(unless you are trying to !c A90b to nothing, in which case leave A90c blank).', '');

				}

			} else {

				compare_pairs_of_data ($file, 'A90b', $A90b_list[$i], 'A90c', $A90c_list[$i], \%local_context, 'pair::if either is filled in', '');

			}
		}
	}
}
## end checks for the A90b/A90c pair


# A91 unit checks
compare_duplicated_field_pairs ($file, 'A91a', \@A91a_list, 'A91b', \@A91b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
compare_duplicated_field_pairs ($file, 'A91a', \@A91a_list, 'A91c', \@A91c_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
compare_duplicated_field_pairs ($file, 'A91a', \@A91a_list, 'A91d', \@A91d_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
compare_duplicated_field_pairs ($file, 'A91a', \@A91a_list, 'A91e', \@A91e_list, \%dup_proforma_fields, 'pair::if either is filled in', '');

compare_duplicated_field_pairs ($file, 'A91d', \@A91d_list, 'A91e', \@A91e_list, \%dup_proforma_fields, 'pair::if either is filled in', 'not same');

# A92 unit checks
compare_duplicated_field_pairs ($file, 'A92a', \@A92a_list, 'A92b', \@A92b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
compare_duplicated_field_pairs ($file, 'A92a', \@A92a_list, 'A92c', \@A92c_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
compare_duplicated_field_pairs ($file, 'A92a', \@A92a_list, 'A92d', \@A92d_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
compare_duplicated_field_pairs ($file, 'A92a', \@A92a_list, 'A92e', \@A92e_list, \%dup_proforma_fields, 'pair::if either is filled in', '');

compare_duplicated_field_pairs ($file, 'A92d', \@A92d_list, 'A92e', \@A92e_list, \%dup_proforma_fields, 'pair::if either is filled in', 'not same');

compare_field_pairs ($file, $g_num_syms, 'A30', \@A30_list, 'A30a', \@A30a_list, \%proforma_fields, 'pair::if either is filled in', '');

# check that the same value does not appear in multiple instances of a 'dupl for multiple'
# field in the same proforma (where that is not appropriate)
check_for_duplicated_field_values ($file, 'A90a', \@A90a_list);
check_for_duplicated_field_values ($file, 'A91a', \@A91a_list);
check_for_duplicated_field_values ($file, 'A92a', \@A92a_list);

# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#A1b_list + 1 == $g_num_syms) {

	check_unattributed_synonym_correction ($file, $g_num_syms, 'A1a', $primary_symbol_list, 'A1b', \@A1b_list, \%proforma_fields, "You must include the valid symbol in A1b when \!c-ing it under the 'unnattributed' publication.");

}


# End of tests that can only be done after parsing the entire proforma.



    $want_next = $fsm{'ABERRATION'};
}

sub validate_A1h ($$$)#new from March 09 ie from test >> production
{
# Data is either a single FBab or empty.  It should be present for author-curated proformae.  Issue a warning if
# it is present in other proforma types.

    my ($code, $change, $FBabs) = @_;
    $FBabs = trim_space_from_ends ($file, $code, $FBabs);

    if (valid_symbol ($file, 'curator_type') eq 'USER' || valid_symbol ($file, 'curator_type') eq 'AUTO')
    {
	$FBabs eq '' and report ($file, "%s: %s-curated proformae should have data.", $code,valid_symbol ($file, 'curator_type'));
    }
    else
    {

		$FBabs eq '' or check_site_specific_field($file, $code, 'Harvard', \%proforma_fields);

    }
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    
	single_line ($file, $code, $FBabs, $proforma_fields{$code}) or return;

    @FBab_list = FBid_list_check ($file, $code, 'FBab', $g_num_syms, $FBabs);#extra sanity check

# More tests at the post-check phase.
}






sub validate_A22a ($$$)
{
# Notes on origin: must be preceded by a valid SoftCV prefix.  The following material is essentially a single
# line of free text, for which we need only check material within stamps.

    my ($code, $change, $n_o_o) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    $n_o_o eq '' and return;			# Absence of data is always acceptable.

    foreach my $notes (dehash ($file, $code, $g_num_syms, $n_o_o))
    {
	next if $notes eq '';						# Absence of data is always acceptable.
	foreach my $note (split /\n/, $notes)
	{
	    $note = trim_space_from_ends ($file, $code, $note);
	    next if $note eq '';					# Ignore blank lines.
	    my (undef, $softcv, $space, $rest) = ($note =~ /^((.*?):)?( )?(.*)/);
	    if (defined $softcv)
	    {
		valid_symbol ($softcv, 'notes on origin') or report ($file, "%s: Invalid SoftCV prefix '%s' in '%s'",
								     $code, $softcv, $note);
		defined $space or report ($file, "%s: I think you omitted the space after the SoftCV prefix in '%s'",
					  $code, $note);

# Add temporary message that 'Associated with:' is not allowed - will eventually just remove
# as allowed value from symtab.pl
		if ($softcv eq 'Associated with') {

			report ($file, "%s: 'Associated with:' is no longer an allowed SoftCV prefix - remove this line and any associated data in A22b, and simply describe the nature of the chromosome in the A25x 'Molecular data - comments' field instead.\n!%s", $code, $proforma_fields{$code});

		}
		
	    }
	    else
	    {
		report ($file, "%s: Missing SoftCV prefix in '%s'", $code, $note);
	    }
	    check_stamps ($file, $code, trim_space_from_ends ($rest));
	}
    }
}

sub validate_A19a ($$$)
{
# The data must be (zero or more of) a SoftCV prefix followed by a valid aberration symbol within stamps
# followed by a '.'

    my ($code, $change, $aberration_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    $aberration_list eq '' and return;		# Absence of data is always acceptable.

    my $inf2overlap = 'Inferred to overlap with: ';				# Required SoftCV prefix.

   foreach my $aberrations (dehash ($file, $code, $g_num_syms, $aberration_list))
    {
	foreach my $aberration (split /\n/, $aberrations)
	{
	    $aberration = trim_space_from_ends ($file, $code, $aberration);
	    next if $aberration eq '';						# Ignore blank lines.
	    if (my ($rest) = ($aberration =~ /^$inf2overlap(.*)/o))
	    {
		$rest = trim_space_from_ends ($file, $code, $rest);

		if ($rest =~ /\.$/)		# data must end in . but
		{
		    chop $rest;			# we've no further interest in it.
		}
		else
		{
		    report ($file, "%s: '%s' does not end in a full-stop", $code, $aberration);
		}

		if ($rest =~ /^\@(.*)\@$/)
		{
		    valid_symbol ($1, 'FBab') or
			report ($file, "%s: '%s' is not a valid aberration symbol in '%s'", $code, $1, $aberration);
		}
		else
		{
		    if (valid_symbol ($rest, 'FBab'))
		    {
			report ($file, "%s: You omitted the stamps.  I think you meant to say '%s\@%s\@.'",
				$code, $inf2overlap, $rest);
		    }
		    else
		    {
			report ($file,
				"%s: You omitted the stamps and %s is not a valid aberration symbol.  " .
				"You need something that looks like %s\@abs-symbol\@.'", $code, $rest, $inf2overlap);
		    }
		}
	    }
	    else
	    {
		report ($file,
			"%s: '%s' doesn't have the required '%s' prefix.  Should this data go into A19b perhaps?",
			$code, $aberration, $inf2overlap);
	    }
	}
    }
}

sub validate_A19b ($$$)
{
    my ($code, $change, $overlaps) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.

    foreach my $overlap (dehash ($file, $code, $g_num_syms, $overlaps))
    {
	$overlap = trim_space_from_ends ($file, $code, $overlap);
	$overlap =~ /^Inferred to overlap with:/ and
	    report ($file, "%s: The 'Inferred to overlap with: ' prefix should only be used in A19a.", $code);
	check_stamps ($file, $code, $overlap);
    }
}

sub validate_A8a ($$$)
{
# Break ranges, cytological or progenitor.

    my ($code, $change, $breaks_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    $breaks_list eq '' and return;		# Absence of data is always acceptable.
    
    my @breaks = dehash ($file, $code, $g_num_syms, $breaks_list);

    for (my $i = 0; $i < $g_num_syms; $i++)
    {
	$A8a_number[$i] = 0;			# Initialise count of number of breaks.

	my @seen = ();				# Keep track of which break numbers have been seen.
	foreach my $break (split (/\n/, $breaks[$i]))
	{
	    next if $break eq '';		# Ignore blank lines
	    if (my ($break_no, $range) = ($break =~ /^(-?\d+): ?(.*)/))
	    {
		if ($break_no > 0 and $break_no !~ /^0/)		# A plausible break number?
		{
		    next if $range eq '';
		    $range = trim_space_from_ends ($file, $code, $range);
		    $A8a_number[$i]++;					# Keep track of number of breaks seen.
		    
		    if (defined $seen[$break_no])			# Can't have same break twice!
		    {
			report ($file, "%s: Already seen break number %d in '%s'", $code, $break_no, $breaks[$i]);
		    }
		    else
		    {
			$seen[$break_no] = 1;
		    }
		    next if $range eq '[]';				# [] is always valid.

		    if ($range =~ /[{}]/)				# It looks like a TI symbol
		    {
			valid_symbol ($range, 'FBti') or
			    report ($file, "%s: '%s' is not a valid FBti symbol in '%s'", $code, $range, $breaks[$i]);
		    }
		    else
		    {
			foreach my $invalid (cyto_check ($range))	# Assume its a cytological range.
			{
			    report ($file, "%s: Invalid cytological map position '%s' in '%s'",
				    $code, $invalid, $breaks[$i]);
			}
		    }			
		}
		else							# An implausible break number?
		{
		    report ($file, "%s: You can't have a break numbered %s in '%s' --- give me a break!",
			    $code, $break_no, $breaks[$i]);
		}
	    }
	    else
	    {
		report ($file, "%s: Invalid data '%s' in '%s'", $code, $break, $breaks[$i]);
	    }

	    my @gaps = ();
	    for (my $break_no = 1; $break_no < $#seen; $break_no++)	# Make sure all breaks have been seen.
	    {
		defined $seen[$break_no] or push @gaps, $break_no;
	    }
	    if ($#gaps >= 0)
	    {
		report ($file, "%s: Break%s %s missing in '%s'",
			$code, $#gaps == 0 ? '' : 's', join (', ', @gaps), $breaks[$i]);
	    }
	}
    }
}


sub validate_A24b {
# converted to process_field_data + %field_specific_checks format. 140627.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {

		# insert field specific checks here
		unless ($datum =~ /(.+)\[[-+*]\]$/ && valid_symbol ($1, 'FBgn')) {
			my @allowed_types = ('FBal');

			valid_symbol_of_list_of_types ($datum, \@allowed_types) or report ($file, "%s: Invalid symbol '%s' (only symbols of type(s) %s are allowed):\n!%s", $code, $datum, (join ', ', @allowed_types), $context->{$code});

		}
	}
}

sub validate_A29 {

    my ($code, $change, $data) = @_;
    changes ($file, $code, $change); # check for garbage after ! but otherwise don't worry about change

    $data eq '' and return;		# Absence of data is acceptable.

	if ($data =~ /\n/)
	{
	    report ($file, "%s: More than one cytological order line in '%s'\n", $code, $data);
	    return;				# Not much point checking anything else.
	}


	foreach my $datum (dehash ($file, $code, $g_num_syms, $data))
	{
	check_allowed_characters($file,$code,$datum,$proforma_fields{$code});
	}
	
}

sub validate_A9_26 {

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	unless (valid_symbol($dehashed_data, 'aberration class shortcut')) {

			validate_ontology_term_id_field ($file, $code, $dehashed_data, $context);

	}
	

}

1;				# Standard boilerplate.
