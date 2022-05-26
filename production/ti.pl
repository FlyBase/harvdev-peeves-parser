# Code to parse transposon insertion proformae

use strict;
# A set of global variables for communicating between different proformae.

our (%fsm, $want_next, $chado, %prepared_queries);
our %x1a_symbols;						# For detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (MA1a MA1f);			# Fields which must be present in the proforma
my %can_dup = (MA19a => 1, MA19b => 1, MA19c => 1, MA19d => 1,MA19e => 1, MA23a => 1, MA23b => 1, MA23c => 1, MA23g => 1);		# Fields which may be duplicated in a proforma.
my $hash_entries;						# Number of elements in hash list.
my $primary_symbol_list;						# Reference to dehashed data from primary symbol field
my @FBti_list = ();							# Dehashed data from MA1f
my @MA1c_list = ();							# Dehashed data from MA1c (rename)
my @MA1g_list = ();							# Dehashed data from MA1g (merge)

sub do_TI_proforma ($$)
{
# Process a TI proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The first occurring MA1a record defines the number of expected symbols in a hash list.

    $proforma =~ /!.? MA1a\..*? :(.*)/;		# Get MA1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in MA1a field
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;

# clear out the variables at the start of each proforma, so that they are cleared out
# even if the corresponding proforma field is omitted.
    @FBti_list = ();
	@MA1c_list = ();
	@MA1g_list = ();




# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n

# since they are only required within a given proforma, just have them here within the do_TI_proforma subroutine, no need to declare at the top of the file
	my @MA1b_list = ();
	my @MA4_list = ();
	my @MA5a_list = ();
	my @MA5c_list = ();
	my @MA5e_list = ();
	my @MA5f_list = ();
	my @MA15a_list = ();
	my @MA15b_list = ();
	my @MA15c_list = ();
	my @MA15d_list = ();
	my @MA20_list = ();
	my @MA21a_list = ();
	my @MA21b_list = ();
	my @MA21e_list = ();
	my @MA27_list = ();

	my @MA23a_list = ();
	my @MA23b_list = ();
	my @MA23c_list = ();
	my @MA23g_list = ();

	my @MA19a_list = ();
	my @MA19b_list = ();
	my @MA19c_list = ();
	my @MA19d_list = ();
	my @MA19e_list = ();
	my @MA21d_list = ();
	my @MA21c_list = ();
	my @MA21f_list = ();
	my @MA30_list = ();
	my @MA30a_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(MA1a)\..*? :(.*)/s)
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
			$want_next = $fsm{'TRANSPOSON INSERTION'};
			return;
		}

		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?)\s+(MA1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		 @MA1b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@FBti_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}

	}
	elsif ($field =~ /^(.*?)\s+(MA27)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA27_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');

	}
	elsif ($field =~ /^(.*?)\s+(MA4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA4_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA20)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA20_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');

	}
	elsif ($field =~ /^(.*?)\s+(MA1c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@MA1c_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(MA1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@MA1g_list = validate_merge_using_ids ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(MA1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(MA1i)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}
	elsif ($field =~ /^(.*?)\s+(MA1d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA22)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA5a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA5a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA5c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA5c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA5e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA5e_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA5f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA5f_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA5d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA7)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '2', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA14)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '2', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?)\s+(MA12)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '2', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?)\s+(MA8)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA21a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA21a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA21b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA21b_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA21e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA21e_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA6)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA21c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA21c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA21f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA21f_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA21d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA21d_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA19a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA19a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA19b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA19b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA19c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA19c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA19d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA19d_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA19e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA19e_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA26)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MA23a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA23a_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA23b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA23b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA23c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA23c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA23g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @MA23g_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA15a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA15a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA15b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA15b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA15c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA15c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA15d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA15d_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA24)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA18)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA9)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?)\s+(MA16)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA10)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MA30)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA30_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MA30a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@MA30a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}

# fields that are not checked at all yet - validate_stub used to prevent false-positive
# 'Invalid proforma field' message.  Remember to take field codes out of second set of ()
# if checking for the field is implemented.
#	elsif ($field =~ /^(.*?)\s+(??insert field code here??)\..*? :(.*)/s)
#	{
#		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
#	    validate_stub ($file, $1, $2, $3);
#	}

	elsif ($field =~ /^(.*?)\s+MA(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*MA.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in ti.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

# no !c in entire proforma if MA1g is filled in
	plingc_merge_check ($file, $change_count,'MA1g', \@MA1g_list, $proforma_fields{'MA1g'});

# MA1c and MA1g must not both contain data.

    rename_merge_check ($file, 'MA1c', \@MA1c_list, $proforma_fields{'MA1c'}, 'MA1g', \@MA1g_list, $proforma_fields{'MA1g'});

# Basic cross-checks between MA1f, MA1a, MA1c and MA1g fields that are common to all harvard-style proformae

	cross_check_harv_style_symbol_rename_merge_fields ($file, 'MA', $hash_entries, \@FBti_list, $primary_symbol_list, \@MA1c_list, \@MA1g_list, \%proforma_fields);

# Cross-checks that are specific to insertion proforma, so are not included in above check. Checks are only attempted when the number of entries in the MA1a field (defined by $hash_entries) is the same as that in the MA1f field (defined by @FBti_list).
# Checks below are
# 1. checking syntax of insertion symbol - this is currently done in every case (i.e. regardless of
# whether its a new/existing insertion, a rename or merge) because it avoids repeating code below.
# It is done here using check_insertion_symbol_format rather than where MA1a field is first processed
# (using validate_primary_proforma_field) as the results of the syntax checking
# are needed for cross-checks with other fields, plus check_insertion_symbol_format is also needed
# to check the cases where a new insertion is made using a GA10 field.
# 2. cross-checks for MA4



	if ($hash_entries and $#FBti_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

			my ($inserted_element, $identifier, $full_symbol_of_inserted_element) = check_insertion_symbol_format ($file, 'MA1a', $primary_symbol_list->[$i], \%proforma_fields);


			if ($inserted_element) {

# MA27 is filled in with a valid term
				if (defined $MA27_list[$i] && (my $valid_MA27 = valid_symbol ($MA27_list[$i], 'insertion_category'))) {
# have used the following if rather than getting the $nat_te_end of the $inserted_element (via check_construct_symbol_format)
# because using check_construct_symbol_format can result in mutltiple error messages for a single error as the construct
# symbol format has already been checked within the earlier check_insertion_symbol_format call above
					if ($inserted_element =~ m/^TI\{/) {

						unless ($valid_MA27 eq 'TI') {
							report ($file, "%s: the insertion category '%s' cannot be used for a TI-style insertion:\n!%s\n!%s", 'MA27', $MA27_list[$i], $proforma_fields{'MA1a'}, $proforma_fields{'MA27'});

						}

					} else {

						if ($valid_MA27 eq 'TI') {

							report ($file, "%s: the insertion category '%s' cannot be used for a regular transposable-element based insertion:\n!%s\n!%s", 'MA27', $MA27_list[$i], $proforma_fields{'MA1a'}, $proforma_fields{'MA27'});
						}

					}

				}



				if ($MA4_list[$i]) {

# if MA4 is filled in, check that it matches the full symbol of the inserted element part of the the symbol in MA1a
					unless ($MA4_list[$i] eq $full_symbol_of_inserted_element) {
# first see if you've put a valid shorthand in by mistake

						if (valid_symbol ($MA4_list[$i], 'insertion_natTE_shorthand_to_full')) {


							if (valid_symbol ($MA4_list[$i], 'insertion_natTE_shorthand_to_full') eq $full_symbol_of_inserted_element) {

								report ($file, "%s: You have used the shorthand '%s', but you need to fill in the full natural transposon symbol in this field, did you mean '%s' instead ?\n!%s\n!%s", 'MA4', $MA4_list[$i], valid_symbol ($MA4_list[$i], 'insertion_natTE_shorthand_to_full'), $proforma_fields{'MA1a'}, $proforma_fields{'MA4'});

							} else {

		    				report ($file, "Mismatch between inserted element '%s' in %s and the inserted element portion of the symbol '%s' in %s", $MA4_list[$i], 'MA4', $primary_symbol_list->[$i], 'MA1a');


							}

						} else {

		    				report ($file, "Mismatch between inserted element '%s' in %s and the inserted element portion '%s' of the symbol '%s' in %s", $MA4_list[$i], 'MA4', $inserted_element, $primary_symbol_list->[$i], 'MA1a');

						}

					}

# if it is a simple existing insertion or a rename of an existing insertion
					if ($FBti_list[$i] =~ m|^FBti[0-9]{7}$|) {

# work out the plingc status of MA4:
						my $MA4_plingc = $proforma_fields{'MA4'};
						$MA4_plingc =~ s/^(.*?)\s+MA4\..*? :.*/$1/s;

# and report an error if MA4 is filled in without using !c
						unless (changes ($file, 'MA4', $MA4_plingc)) {
							report ($file, "%s must have !c when filled in for an existing insertion:\n!%s\n!%s", 'MA4', $proforma_fields{'MA1a'}, $proforma_fields{'MA4'});
						}

					} else {

						if ($MA1g_list[$i]) {
							report ($file, "%s cannot be filled in for a merge - if you are trying to simultaneously merge insertions and change the inserted element, please separate these actions into two different curation records:\n!%s\n!%s\n!%s", 'MA4', $proforma_fields{'MA1a'}, $proforma_fields{'MA4'}, $proforma_fields{'MA1g'});
						}

					}
						
# MA4 is empty
				} else {

					if ($FBti_list[$i] eq 'new') {

# MA4 must be filled in for a brand new insertion
						unless ($MA4_list[$i]) {
	    					report ($file, "%s must be filled in for a new insertion:\n!%s", 'MA4', $proforma_fields{'MA1a'});
						}

					} else {

# if it is a rename
## commented out the below until I work out how to get inserted element of an insertion out of chado
## need to remove double ## at start of lines below once figure this out - see DC-434
##						if ($MA1c_list[$i]) {

# need to add check here to see whether the inserted element associated with the symbol in chado
# already corresponds to the inserted_element part of the new symbol - if it does, no need to
# print an error message if MA4 is empty, as the data is already correct in chado
##							my $inserted_element_in_chado = (work out how to get this info out of chado using the symbol in MA1c as the insertion query);
##							unless ($inserted_element eq $inserted_element_in_chado) {

##	    						report ($file, "The 'inserted element' portion '%s' of the insertion symbol does not match the value '%s" in chado.  You must !c the MA4 field to also change the inserted element:\n!%s\n!%s\n!%s", $inserted_element, $inserted_element_in_chado, $proforma_fields{'MA1a'}, $proforma_fields{'MA1c'}, $proforma_fields{'MA4'});

##							}
##
##						}
					}
				}
			}

		}
	}


check_filled_in_for_new_feature ($file, 'MA20', $hash_entries, \@MA20_list, \@FBti_list, \@MA1c_list, \@MA1g_list, \%proforma_fields, 'only');

check_filled_in_for_new_feature ($file, 'MA27', $hash_entries, \@MA27_list, \@FBti_list, \@MA1c_list, \@MA1g_list, \%proforma_fields, 'yes');

# MA27 must be filled in when MA1f = 'new'
for (my $i = 0; $i < $hash_entries; $i++) {

	if ($FBti_list[$i] && $FBti_list[$i] eq 'new') {

		compare_pairs_of_data ($file, 'MA1f', $FBti_list[$i], 'MA27', $MA27_list[$i], \%proforma_fields, "pair::when MA1f contains \'new\'\n\!$proforma_fields{MA1a}", '');

	}

}

# MA15 field cross-checks

# check value in each MA15 field is not the same as in MA1a
compare_field_pairs ($file, $hash_entries, 'MA1a', $primary_symbol_list, 'MA15a', \@MA15a_list, \%proforma_fields, '', 'not same');
compare_field_pairs ($file, $hash_entries, 'MA1a', $primary_symbol_list, 'MA15b', \@MA15b_list, \%proforma_fields, '', 'not same');
compare_field_pairs ($file, $hash_entries, 'MA1a', $primary_symbol_list, 'MA15c', \@MA15c_list, \%proforma_fields, '', 'not same');
compare_field_pairs ($file, $hash_entries, 'MA1a', $primary_symbol_list, 'MA15d', \@MA15d_list, \%proforma_fields, '', 'not same');


# check combination of MA15 fields filled in is correct
compare_field_pairs ($file, $hash_entries, 'MA15a', \@MA15a_list, 'MA15b', \@MA15b_list, \%proforma_fields, 'single', '');
compare_field_pairs ($file, $hash_entries, 'MA15a', \@MA15a_list, 'MA15c', \@MA15c_list, \%proforma_fields, 'single', '');
compare_field_pairs ($file, $hash_entries, 'MA15a', \@MA15a_list, 'MA15d', \@MA15d_list, \%proforma_fields, 'single', '');
compare_field_pairs ($file, $hash_entries, 'MA15b', \@MA15b_list, 'MA15d', \@MA15d_list, \%proforma_fields, 'single', '');
compare_field_pairs ($file, $hash_entries, 'MA15c', \@MA15c_list, 'MA15d', \@MA15d_list, \%proforma_fields, 'single', '');


compare_field_pairs ($file, $hash_entries, 'MA15b', \@MA15b_list, 'MA15c', \@MA15c_list, \%proforma_fields, 'dependent', 'not same');

## checks for the MA21a/MA21b pair - in almost all cases, both fields must be filled in if one of them is.
## the single exception is when MA21a is !c to nothing - in that case, MA21b should be blank
if ($proforma_fields{'MA21a'}) {
	my $MA21a_plingc = $proforma_fields{'MA21a'};
	$MA21a_plingc =~ s/^(.*?)\s+MA21a\..*? :.*/$1/s;

	if (changes ($file, 'MA21a', $MA21a_plingc)) {

		# loop round hashing
		for (my $i = 0; $i < $hash_entries; $i++) {

			if (defined $MA21a_list[$i] && $MA21a_list[$i] ne '') {

				compare_pairs_of_data ($file, 'MA21a', $MA21a_list[$i], 'MA21b', $MA21b_list[$i], \%proforma_fields, 'pair::if either is filled in', '');

			} else {
			
				compare_pairs_of_data ($file, 'MA21b', $MA21b_list[$i], 'MA21a', $MA21a_list[$i], \%proforma_fields, 'dependent::(unless you are trying to !c MA21a to nothing, in which case leave MA21b blank).', '');


			}

		}


	} else {

		compare_field_pairs ($file, $hash_entries, 'MA21a', \@MA21a_list, 'MA21b', \@MA21b_list, \%proforma_fields, 'pair::if either is filled in', '');

	}

}


compare_field_pairs ($file, $hash_entries, 'MA5e', \@MA5e_list, 'MA5f', \@MA5f_list, \%proforma_fields, 'pair', '');

# MA23 unit checks
compare_duplicated_field_pairs ($file, 'MA23b', \@MA23b_list, 'MA23a', \@MA23a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'MA23c', \@MA23c_list, 'MA23a', \@MA23a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'MA23g', \@MA23g_list, 'MA23a', \@MA23a_list, \%dup_proforma_fields, 'dependent', '');

# MA19 unit checks

compare_duplicated_field_pairs ($file, 'MA19b', \@MA19b_list, 'MA19a', \@MA19a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'MA19c', \@MA19c_list, 'MA19a', \@MA19a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'MA19d', \@MA19d_list, 'MA19a', \@MA19a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'MA19e', \@MA19e_list, 'MA19a', \@MA19a_list, \%dup_proforma_fields, 'dependent', '');

compare_field_pairs ($file, $hash_entries, 'MA21c', \@MA21c_list, 'MA21f', \@MA21f_list, \%proforma_fields, 'single', '');
compare_field_pairs ($file, $hash_entries, 'MA30', \@MA30_list, 'MA30a', \@MA30a_list, \%proforma_fields, 'pair::if either is filled in', '');


# check that the same value does not appear in multiple instances of a 'dupl for multiple'
# field in the same proforma (where that is not appropriate)
check_for_duplicated_field_values ($file, 'MA19a', \@MA19a_list);
check_for_duplicated_field_values ($file, 'MA23a', \@MA23a_list);

# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#MA1b_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'MA1a', $primary_symbol_list, 'MA1b', \@MA1b_list, \%proforma_fields, "You must include the valid symbol in MA1b when \!c-ing it under the 'unnattributed' publication.");

}
### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of this subroutine

    $want_next = $fsm{'TRANSPOSON INSERTION'};
}





1;				# Standard boilerplate.
