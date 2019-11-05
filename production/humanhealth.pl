# Code to parse humanhealth proformae

use strict;
# A set of global variables for communicating between different proformae.

our (%fsm, $want_next); # Global variables for finite state machine (defines what proforma expected next)
our ($chado, %prepared_queries); # Global variables for communication with Chado.
our %x1a_symbols;						# Hash for detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22 (if valid FBrf number)
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl,


my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (HH1b HH1f);			# Fields which must be present in the proforma
my %can_dup = ('HH8a' => 1, 'HH8c' => 1, 'HH5a' => 1, 'HH5b' => 1, 'HH5c' => 1, 'HH5d' => 1, 'HH7e' => 1, 'HH7d' => 1, 'HH7c' => 1, 'HH14a' => 1, 'HH14b' => 1, 'HH14c' => 1, 'HH14d' => 1, );		# Fields which may be duplicated in a proforma.

# These two variables need to be declared here (and not within do_humanhealth_proforma)
# if there are any field-specific subroutines (at the bottom of this file) for this particular proforma.
my $hash_entries;						# Number of elements in hash list.
my $primary_symbol_list;						# Reference to dehashed data from primary symbol field
my @FBid_list = ();


sub do_humanhealth_proforma ($$)
{
# Process a humanhealth proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The primary proforma field (that which contains the valid symbol) defines the number of expected symbols in a hash list.
# humanhealth proforma does not have a 1a (valid symbol) field, but instead the primary field appears to be HH1b which is valid name,
# so have made that the primary proforma field code
    $proforma =~ /!.? HH1b\..*? :(.*)/;		# Get data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in primary proforma field
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;

# clear out the variables at the start of each proforma, so that they are cleared out
# even if the corresponding proforma field is omitted.
	@FBid_list = ();

# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
# since they are only required within  the do_humanhealth_proforma subroutine,
# no need to declare at the top of the file. e.g.
#	my @MA4_list = ();
#   etc.
	my @HH1g_list = ();
	my @HH2a_list = ();
	my @HH2b_list = ();
	my @HH3a_list = ();
	my @HH7a_list = ();

	my @HH8a_list = ();
	my @HH8c_list = ();
	my @HH8e_list = ();

	my @HH5a_list = ();
	my @HH5b_list = ();
	my @HH5c_list = ();
	my @HH5d_list = ();

	my @HH7e_list = ();
	my @HH7d_list = ();
	my @HH7c_list = ();
	my @HH7b_list = ();

	my @HH14a_list = ();
	my @HH14b_list = ();
	my @HH14c_list = ();
	my @HH14d_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(HH1b)\..*? :(.*)/s)
	{
	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $code, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
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
			$want_next = $fsm{'HUMAN HEALTH MODEL'};
			return;
		}

		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	
	elsif ($field =~ /^(.*?)\s+(HH1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@HH1g_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}

	elsif ($field =~ /^(.*?)\s+(HH1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@FBid_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(HH1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@HH2a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@HH2b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH2c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH2d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH3a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@HH3a_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(HH3c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(HH3d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
		    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(HH15)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH4h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH4a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH4b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH4c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH4g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH4f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH5a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH5a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH5b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH5b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH5c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH5c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH5d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH5d_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH7a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@HH7a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH7e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @HH7e_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH7d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @HH7d_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH7c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @HH7c_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH7b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@HH7b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH20)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH8a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @HH8a_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH8c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @HH8c_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH8e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@HH8e_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(HH14a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH14a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH14b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH14b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH14c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH14c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(HH14d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @HH14d_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	


# fields that are not checked at all yet - validate_stub used to prevent false-positive
# 'Invalid proforma field' message.  Remember to take field codes out of second set of ()
# if checking for the field is implemented.
	elsif ($field =~ /^(.*?)\s+(HH6c|HH7f|HH8d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    validate_stub ($file, $1, $2, $3);
	}

	elsif ($field =~ /^(.*?)\s+HH(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*HH.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in humanhealth.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

# merge field not present in HH.pro yet, but placeholder of HH3b is in proforma parsing code
# so have set a dummy empty array for HH3b, so that can use generic subroutine below
# to do cross-field checks for the rename, primary symbol and id fields which do exist.
# Have set it here for now, rather than with the other field arrays since its not a real
# proforma field at the moment.
	my @HH3b_list = ();
	cross_check_harv_style_symbol_rename_merge_fields ($file, 'HH', $hash_entries, \@FBid_list, $primary_symbol_list, \@HH3a_list, \@HH3b_list, \%proforma_fields);


	compare_duplicated_field_pairs ($file, 'HH8c', \@HH8c_list, 'HH8a', \@HH8a_list, \%dup_proforma_fields, 'dependent', '');


	compare_duplicated_field_pairs ($file, 'HH5a', \@HH5a_list, 'HH5b', \@HH5b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
	compare_duplicated_field_pairs ($file, 'HH5c', \@HH5c_list, 'HH5a', \@HH5a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'HH5d', \@HH5d_list, 'HH5a', \@HH5a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'HH5d', \@HH5d_list, 'HH5b', \@HH5b_list, \%dup_proforma_fields, 'dependent', '');

	compare_duplicated_field_pairs ($file, 'HH7d', \@HH7d_list, 'HH7e', \@HH7e_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'HH7c', \@HH7c_list, 'HH7e', \@HH7e_list, \%dup_proforma_fields, 'dependent', '');

	compare_duplicated_field_pairs ($file, 'HH14a', \@HH14a_list, 'HH14b', \@HH14b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
	compare_duplicated_field_pairs ($file, 'HH14c', \@HH14c_list, 'HH14a', \@HH14a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'HH14d', \@HH14d_list, 'HH14a', \@HH14a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'HH14d', \@HH14d_list, 'HH14b', \@HH14b_list, \%dup_proforma_fields, 'dependent', '');

# checks for fields that should only be filled in for certain 'categories' of FBhh
# currently uses HH2a field, although in fullness of time should also use query to
# chado if HH2a not filled in
# this section does non-duplicated fields

# only attempt the check when the hashing is correct for the HH2a field

	if ($hash_entries and $#{$primary_symbol_list} + 1 == $hash_entries and $#HH2a_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

# work out category in H2a and only do tests when HH2a contains a valid value
			if (my $category = valid_symbol($HH2a_list[$i], 'human_health_category')) {

				if ($category eq 'parent') {

# fields that must not be filled in for parent entity

					if (defined $HH7a_list[$i] && $HH7a_list[$i] ne '') {
						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH7a', $HH2a_list[$i], $proforma_fields{'HH7a'});
					}
					if (defined $HH7b_list[$i] && $HH7b_list[$i] ne '') {
						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH7b', $HH2a_list[$i], $proforma_fields{'HH7b'});
					}

					if (defined $HH8e_list[$i] && $HH8e_list[$i] ne '') {
						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH8e', $HH2a_list[$i], $proforma_fields{'HH8e'});
					}



					if (defined $HH2b_list[$i] && $HH2b_list[$i] ne '') {
						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH2b', $HH2a_list[$i], $proforma_fields{'HH2b'});
					}

				} elsif ($category eq 'group') {

					if (defined $HH2b_list[$i] && $HH2b_list[$i] ne '') {
						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH2b', $HH2a_list[$i], $proforma_fields{'HH2b'});
					}

				} elsif ($category eq 'specific') {

					if (defined $HH2b_list[$i] && $HH2b_list[$i] ne '') {
						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH2b', $HH2a_list[$i], $proforma_fields{'HH2b'});
					}

				} elsif ($category eq 'sub') {


				}
			}
		}
	}

# checks for fields that should only be filled in for certain 'categories' of FBhh
# currently uses HH2a field, although in fullness of time should also use query to
# chado if HH2a not filled in
# this section is for fields that can be duplicated, so only do the checks if no hashing

	if ($hash_entries == 1 && $#HH2a_list + 1 == $hash_entries) {

# work out category in H2a and only do tests when HH2a contains a valid value
		if (my $category = valid_symbol($HH2a_list[0], 'human_health_category')) {

# have to test each field at a time, as the number of duplications may be different for each field

			for (my $i = 0; $i <= $#HH7c_list; $i++) {

				if (defined $HH7c_list[$i] && $HH7c_list[$i] ne '') {

					if ($category eq 'parent') {

						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH7c', $HH2a_list[0], $dup_proforma_fields{'HH7c'}[$i]);

					}

				}
			}


			for (my $i = 0; $i <= $#HH7d_list; $i++) {

				if (defined $HH7d_list[$i] && $HH7d_list[$i] ne '') {

					if ($category eq 'parent') {

						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH7d', $HH2a_list[0], $dup_proforma_fields{'HH7d'}[$i]);

					}

				}
			}

			for (my $i = 0; $i <= $#HH7e_list; $i++) {

				if (defined $HH7e_list[$i] && $HH7e_list[$i] ne '') {

					if ($category eq 'parent') {

						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", 'HH7e', $HH2a_list[0], $dup_proforma_fields{'HH7e'}[$i]);

					}

				}
			}

			for (my $i = 0; $i <= $#HH8a_list; $i++) {

				if (defined $HH8a_list[$i] && $HH8a_list[$i] ne '') {

					if ($category eq 'parent') {

						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", '', $HH2a_list[0], $dup_proforma_fields{'HH8a'}[$i]);

					}

				}
			}

			for (my $i = 0; $i <= $#HH8c_list; $i++) {

				if (defined $HH8c_list[$i] && $HH8c_list[$i] ne '') {

					if ($category eq 'parent') {

						report ($file, "%s must NOT be filled in when HH2a contains '%s':\n!%s", '', $HH2a_list[0], $dup_proforma_fields{'HH8c'}[$i]);

					}

				}
			}
		}
	}


# HH1g cross-checks. only attempt the check when the hashing is correct for the HH1g field

	if ($hash_entries and $#{$primary_symbol_list} + 1 == $hash_entries and $#HH1g_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

# get plingc status for HH1g as nature of cross-check is dependant on this
			my $HH1g_plingc = $proforma_fields{'HH1g'};
			$HH1g_plingc =~ s/^(.*?)\s+HH1g\..*? :.*/$1/s;

# get the 'status' of the human health object being checked
			my $object_status = get_object_status ('HH', $FBid_list[$i], $HH3a_list[$i], $HH3b_list[$i]);

			if ($object_status) {

# HH1g must be filled in when 'HH1f' is new (i.e. brand new or merge)
				if ($object_status eq 'new' || $object_status eq 'merge') {

					unless (defined $HH1g_list[$i] && $HH1g_list[$i] ne '') {

						report ($file, "%s must be filled in for a %s:\n!%s\n!%s\n\n!%s", 'HH1g', ($object_status eq 'new' ? "$object_status human health model" : "human health model $object_status"),  $proforma_fields{'HH1f'}, $proforma_fields{'HH1b'}, (exists $proforma_fields{'HH1g'} ? $proforma_fields{'HH1g'} : ''));

					} else {

						if (changes ($file, 'HH1g', $HH1g_plingc)) {
							report ($file, "%s: Cannot !c for a %s:\n!%s\n!%s\n\n!%s", 'HH1g', ($object_status eq 'new' ? "$object_status human health model" : "human health model $object_status"),  $proforma_fields{'HH1f'}, $proforma_fields{'HH1b'}, $proforma_fields{'HH1g'});
						}
					}

				} else {

					if (defined $HH1g_list[$i]) {

# if HH1g is filled in
						if  ($HH1g_list[$i] ne '') {
# unless plingc-ing for existing FBhh
							unless (changes ($file, 'HH1g', $HH1g_plingc)) {
								report ($file, "%s without a !c must be NOT be filled in for a %s:\n!%s\n!%s\n\n!%s", 'HH1g', ($object_status eq 'existing' ? "$object_status human health model" : "human health model $object_status"),  $proforma_fields{'HH1f'}, $proforma_fields{'HH1b'}, $proforma_fields{'HH1g'});
							}
# HH1g is empty - warn if !c-ing to nothing
						} else {

							if (changes ($file, 'HH1g', $HH1g_plingc)) {
							report ($file, "%s cannot be !c-ed to nothing for a %s:\n!%s\n!%s\n\n!%s", 'HH1g', ($object_status eq 'existing' ? "$object_status human health model" : "human health model $object_status"),  $proforma_fields{'HH1f'}, $proforma_fields{'HH1b'}, $proforma_fields{'HH1g'});
							}

						}

					}
				}
			}
		}
	}



### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of the do proforma subroutine

    $want_next = $fsm{'HUMAN HEALTH MODEL'};
}

sub validate_HH7a {
# process_field_data + %field_specific_checks format.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {


		if (valid_chado_symbol ($datum, 'FBgn')) {

			index ($datum, '\\') or report ($file, "%s: No species before \\ in %s (must be a Hsapp gene)", $code, $datum);

			my ($species) = ($datum =~ /^(.+?)\\/);

			unless ($species eq 'Hsap') {

			report ($file, "%s: Species '%s' given in '%s' is not valid for this field - only Hsap genes are allowed", $code, $species, $datum);

			}
		} else {

			report ($file, "%s: '%s' is not a valid gene symbol in chado", $code, $datum);

		}
	}
}

sub validate_Dmel_gene {
# process_field_data + %field_specific_checks format.
# should really convert to generic subroutine

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {


		if (valid_chado_symbol ($datum, 'FBgn')) {

# hacky way to do this - should really look up species in chado
			my ($species) = ($datum =~ /^(.+?)\\/);
			defined $species or $species = 'Dmel';

			unless ($species eq 'Dmel') {

			report ($file, "%s: Species '%s' given in '%s' is not valid for this field - only Dmel genes are allowed", $code, $species, $datum);

			}
		} else {

			report ($file, "%s: '%s' is not a valid gene symbol in chado", $code, $datum);

		}
	}
}

sub validate_nonDmel_gene {
# process_field_data + %field_specific_checks format.
# should really convert to generic subroutine

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {


		if (valid_chado_symbol ($datum, 'FBgn')) {

# hacky way to do this - should really look up species in chado
			my ($species) = ($datum =~ /^(.+?)\\/);
			defined $species or $species = 'Dmel';

			if ($species eq 'Dmel') {

			report ($file, "%s: Species '%s' given in '%s' is not valid for this field - only NON Dmel genes are allowed", $code, $species, $datum);

			}
		} else {

			report ($file, "%s: '%s' is not a valid gene symbol in chado", $code, $datum);

		}
	}
}



1;				# Standard boilerplate.
