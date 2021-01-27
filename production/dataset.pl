# Code to parse DATASET/COLLECTION PROFORMA proformae

use strict;
# A set of global variables for communicating between different proformae.

our (%fsm, $want_next); # Global variables for finite state machine (defines what proforma expected next)
our ($chado, %prepared_queries); # Global variables for communication with Chado.
our %x1a_symbols;						# Hash for detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22 (if valid FBrf number)
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl,

our %g_dataset_entity_mapping;

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (LC1a LC1f);			# Fields which must be present in the proforma
my %can_dup = ('LC99a' => 1, 'LC99b' => 1, 'LC99c' => 1, 'LC99d' => 1, 'LC12a' => 1, 'LC12b' => 1, 'LC12c'=> 1, );		# Fields which may be duplicated in a proforma.

# These two variables need to be declared here (and not within do_dataset_proforma)
# if there are any field-specific subroutines (at the bottom of this file) for this particular proforma.
my $hash_entries;						# Number of elements in hash list.
my $primary_symbol_list;						# Reference to dehashed data from primary symbol field

sub do_dataset_proforma ($$)
{
# Process a dataset proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();




# The primary proforma field (that which contains the valid symbol) defines the number of expected symbols in a hash list.

    $proforma =~ /!.? LC1a\..*? :(.*)/;		# Get data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in primary proforma field
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;



# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
# since they are only required within  the do_dataset_proforma subroutine,
# no need to declare at the top of the file. e.g.
#	my @MA4_list = ();
#   etc.
	my @primary_id_list = ();
	my @LC1b_list = ();
	my @LC3_list = ();
	my @LC3a_list = ();
	my @LC3b_list = ();
	my @LC3e_list = ();
	my @LC4a_list = ();
	my @LC4i_list = ();
	my @LC6g_list = ();
	my @LC12a_list = ();
	my @LC12b_list = ();
	my @LC12c_list = ();
	my @LC2a_list = ();
	my @LC2b_list = ();
	my @LC6d_list = ();
	my @LC6e_list = ();
	my @LC6f_list = ();
	my @LC11m_list = ();
	my @LC99a_list = ();
	my @LC99b_list = ();
	my @LC99c_list = ();
	my @LC99d_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(LC1a)\..*? :(.*)/s)
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
			$want_next = $fsm{'DATASET/COLLECTION'};
			return;
		}


		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);



	}
	elsif ($field =~ /^(.*?)\s+(LC1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@primary_id_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}	
	elsif ($field =~ /^(.*?)\s+(LC1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC1b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC1d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC6g)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC6g_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC3c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(LC3d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
		    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(LC13a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC13b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC13c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC13d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?)\s+(LC4i)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC4i_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC4j)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC4k)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC3a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@LC3a_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(LC3b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@LC3b_list = validate_merge_using_ids ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(LC3)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC3_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC3e)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC3e_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC14a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC14b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC14c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?)\s+(LC14d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC14e)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC14f)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC14g)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC14h)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC4a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC4a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC4b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC4h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC4f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC4g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		# can't convert TAP_check to process_field_data format as also used to check F9 where cross-checks are required using *part*
# of the F9 field
		changes ($file, $2, $1) and report ($file, "%s: Can't use !c in this field:\n!%s", $2, $proforma_fields{$3});
		check_non_utf8 ($file, $2, $3);
		double_query ($file, $2, $3) or TAP_check ($file, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(LC4e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC12a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @LC12a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC12b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @LC12b_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC12c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @LC12c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC6a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC2a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC2a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC2b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC2b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC6d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC6d_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC6e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC6e_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC6f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC6f_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC11m)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@LC11m_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC11j)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		 process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC11a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC6b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC11c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC11e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC7a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC7c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC7f)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC99a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @LC99a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC99b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @LC99b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC99c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @LC99c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(LC99d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @LC99d_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields,'1');
	}
	elsif ($field =~ /^(.*?)\s+(LC8a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC8c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1' , $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC8b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC8d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC9)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC9a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(LC10)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

# fields that are not checked at all yet - validate_stub used to prevent false-positive
# 'Invalid proforma field' message.  Remember to take field codes out of second set of ()
# if checking for the field is implemented.
#	elsif ($field =~ /^(.*?)\s+(??insert field code here??)\..*? :(.*)/s)
#	{
#		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
#	    validate_stub ($file, $1, $2, $3);
#	}

	elsif ($field =~ /^(.*?)\s+LC(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*LC.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in dataset.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

	cross_check_harv_style_symbol_rename_merge_fields ($file, 'LC', $hash_entries, \@primary_id_list, $primary_symbol_list, \@LC3a_list, \@LC3b_list, \%proforma_fields);


# no !c in entire proforma if merge field is filled in
	plingc_merge_check ($file, $change_count,'LC3b', \@LC3b_list, $proforma_fields{'LC3b'});

# rename and merge fields must not both contain data
    rename_merge_check ($file, 'LC3a', \@LC3a_list, $proforma_fields{'LC3a'}, 'LC3b', \@LC3b_list, $proforma_fields{'LC3b'});
    
# fields that must ONLY be filled in for new features
	check_filled_in_for_new_feature ($file, 'LC4a', $hash_entries, \@LC4a_list, \@primary_id_list, \@LC3a_list, \@LC3b_list, \%proforma_fields, 'only');

# fields that must be filled in for new features
	check_filled_in_for_new_feature ($file, 'LC6d', $hash_entries, \@LC6d_list, \@primary_id_list, \@LC3a_list, \@LC3b_list, \%proforma_fields, 'yes');


	compare_duplicated_field_pairs ($file, 'LC12a', \@LC12a_list, 'LC12b', \@LC12b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
	compare_duplicated_field_pairs ($file, 'LC12c', \@LC12c_list, 'LC12a', \@LC12a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'LC12c', \@LC12c_list, 'LC12b', \@LC12b_list, \%dup_proforma_fields, 'dependent', '');


#

for (my $i = 0; $i < $hash_entries; $i++) {


# If LC6e is filled in, LC6d must be filled in with 'N'
	if ($LC6e_list[$i]) {

		unless (defined $LC6d_list[$i] && $LC6d_list[$i] eq 'N') {

			report ($file, "%s can only be filled in if LC6d is filled in with 'N'\n!%s\n!%s", 'LC6e', exists $proforma_fields{'LC6d'} ? $proforma_fields{'LC6d'} : '', $proforma_fields{'LC6e'});


		}
	}

# If LC6f is filled in, LC6d must be filled in with 'N'
	if ($LC6f_list[$i]) {

		unless (defined $LC6d_list[$i] && $LC6d_list[$i] eq 'N') {

			report ($file, "%s can only be filled in if LC6d is filled in with 'N'\n!%s\n!%s", 'LC6f', exists $proforma_fields{'LC6d'} ? $proforma_fields{'LC6d'} : '', $proforma_fields{'LC6f'});


		}
	}
# LC2a cross-check of field itself and also of other fields that depend on the value in LC2a

	my $object_status = get_object_status ('LC', $primary_id_list[$i], $LC3a_list[$i], $LC3b_list[$i]);

# only do a number of checks if the primary fields pass basic checks
	if ($object_status) {

# variable required for LC2b cross-check, populate here rather than as do LC2a check so always get what is
# in LC2a if it is filled in (future-proofing for if !c of LC2a is ever allowed, which is unlikely but just
# in case).
		my $required_entity_type;

		if (defined $LC2a_list[$i] && $LC2a_list[$i] ne '') {

			$required_entity_type = summary_check_ontology_term_id_pair($LC2a_list[$i], "FBcv:dataset_entity_type");

		} else {

			$required_entity_type = chat_to_chado ('library_type_from_id', $primary_id_list[$i])->[0]->[0];
		}

# make variable to get the right list of allowed values in various checks (necessary as 'reagent collection' has a space)

		my $temp_entity_type = $required_entity_type;

		if ($temp_entity_type) {
			$temp_entity_type =~ s/ /_/g;
		}

		if ($object_status eq 'new' || $object_status eq 'merge') {

			unless (defined $LC2a_list[$i] && $LC2a_list[$i] ne '') {
			
				report ($file, "%s must be filled in for a %s:\n!%s\n!%s\n\n!%s", 'LC2a', ($object_status eq 'new' ? "$object_status dataset" : "dataset $object_status"),  $proforma_fields{'LC1f'}, $proforma_fields{'LC1a'}, (exists $proforma_fields{'LC2a'} ? $proforma_fields{'LC2a'} : ''));
				
			}

			if (defined $LC3e_list[$i] && $LC3e_list[$i] ne '') {

				report ($file, "%s must NOT be filled in for a %s:\n!%s\n!%s\n\n!%s", 'LC3e', ($object_status eq 'new' ? "$object_status dataset" : "dataset $object_status"),  $proforma_fields{'LC1f'}, $proforma_fields{'LC1a'}, $proforma_fields{'LC3e'});


			}

# must be new or existing dataset
		} else {

			if (defined $LC2a_list[$i] && $LC2a_list[$i] ne '') {
			
				report ($file, "%s must NOT be filled in for a %s:\n!%s\n!%s\n\n!%s", 'LC2a', ($object_status eq 'existing' ? "$object_status dataset" : "dataset $object_status"),  $proforma_fields{'LC1f'}, $proforma_fields{'LC1a'}, $proforma_fields{'LC2a'});
				
			}

		}

# do the LC2b and LC11m checks here - only if LC2a passed
		if ($required_entity_type) {


# LC2b checks
			if ($LC2b_list[$i]) {

				my $specific_error_message = " when the dataset entity type is '$required_entity_type':\n!$proforma_fields{'LC1f'}\n!$proforma_fields{'LC1a'}\n!" . (exists $proforma_fields{'LC2a'} ? $proforma_fields{'LC2a'} : '') . "\n!$proforma_fields{'LC2b'}";

				validate_ontology_term_id_field ($file, 'LC2b', $LC2b_list[$i], \%proforma_fields, ("FBcv:$temp_entity_type" . "_type"), $specific_error_message);

			}


# LC11m checks
			if ($LC11m_list[$i]) {


				my $specific_error_message = " when the dataset entity type is '$required_entity_type':\n!$proforma_fields{'LC1f'}\n!$proforma_fields{'LC1a'}\n!" . (exists $proforma_fields{'LC2a'} ? $proforma_fields{'LC2a'} : '') . "\n!$proforma_fields{'LC11m'}";


				unless ($required_entity_type eq 'project' || $required_entity_type eq 'reagent collection') {
					validate_ontology_term_id_field ($file, 'LC11m', $LC11m_list[$i], \%proforma_fields, ("FBcv:$required_entity_type" . "_attribute"), $specific_error_message);
				} else {


# first split lines in LC11m into single lines
					my $uniqued_term_id_pair_list = check_for_duplicated_lines($file,'LC11m',$LC11m_list[$i],$proforma_fields{'LC11m'});

# then test to see if each line matches completely correctly one of the allowed namespaces
					foreach my $term_id_pair (keys %{$uniqued_term_id_pair_list}) {

						my $allowed_types = valid_symbol (("$temp_entity_type" . '_protocol_types'), 'allowed_type_list');
						my $passed_type = summary_check_ontology_term_id_pair_of_list_of_types ($term_id_pair, $allowed_types);


# report errors if it failed
						unless ($passed_type) {

# check if its a valid FBcv term
							my $passed_format = summary_check_ontology_term_id_pair($term_id_pair, "FBcv:default");

							if ($passed_format) {

								report ($file, "%s: '%s' does not match any of the list of namespaces allowed for this field when the dataset entity type is '%s':\n!%s\n!%s\n!%s\n!%s\n", 'LC11m', $term_id_pair, $required_entity_type, $proforma_fields{'LC1f'}, $proforma_fields{'LC1a'}, (exists $proforma_fields{'LC2a'} ? $proforma_fields{'LC2a'} : ''), $proforma_fields{'LC11m'});

							} else {

								validate_ontology_term_id_field ($file, 'LC11m', $term_id_pair, \%proforma_fields, "FBcv:default", '');
							}
						}

					}


				}
			}


		}

	}


# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#LC1b_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'LC1a', $primary_symbol_list, 'LC1b', \@LC1b_list, \%proforma_fields, "You must include the valid symbol in LC1b when \!c-ing it under the 'unnattributed' publication.");

}

## commented out as need help with sql to get this data and not yet in production chado as new field
# check value in LC6g against what is already in chado (done here rather than during processing of field so can use process_field_data and generic no_stamps to check format).

##	if (defined $LC6g_list[$i] && $LC6g_list[$i] ne '' && $primary_id_list[$i] && $primary_id_list[$i] ne 'new') {

##		my $LC6g_plingc = $proforma_fields{'LC6g'};
##		$LC6g_plingc =~ s/^(.*?)\s+LC6g\..*? :.*/$1/s;
##		check_changes_with_chado ($file, 'LC6g', (changes ($file, 'LC6g', $LC6g_plingc)), $primary_id_list[$i], 'dataset title', chat_to_chado ('chado_dataset_title', $primary_id_list[$i]), $LC6g_list[$i])

##	}

}

	compare_field_pairs ($file, $hash_entries, 'LC6e', \@LC6e_list, 'LC6f', \@LC6f_list, \%proforma_fields, 'pair::if either is filled in', '');

# can use 'not same' test as each field is only allowed a single value
	compare_field_pairs ($file, $hash_entries, 'LC1a', $primary_symbol_list, 'LC3e', \@LC3e_list, \%proforma_fields, '', 'not same');


	compare_duplicated_field_pairs ($file, 'LC99a', \@LC99a_list, 'LC99b', \@LC99b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
	compare_duplicated_field_pairs ($file, 'LC99c', \@LC99c_list, 'LC99a', \@LC99a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'LC99d', \@LC99d_list, 'LC99a', \@LC99a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'LC99d', \@LC99d_list, 'LC99b', \@LC99b_list, \%dup_proforma_fields, 'dependent', '');

# check that LC99d is not filled in for new or merged datasets
# only perform check if no hashing in proforma to ensure correct checking as LC99d can be duplicated

	if ($hash_entries == 1) {

		my $object_status = get_object_status ('LC', $primary_id_list[0], $LC3a_list[0], $LC3b_list[0]);
	
		if ($object_status eq 'new' || $object_status eq 'merge') {
		
			for (my $i = 0; $i <= $#LC99d_list; $i++) {
		
		
				if (defined $LC99d_list[$i] && $LC99d_list[$i] ne '') {
			
						report ($file, "%s must NOT be filled in for a %s:\n!%s\n!%s\n\n!%s\n!%s", 'LC99d', ($object_status eq 'new' ? "$object_status dataset" : "dataset $object_status"),  $proforma_fields{'LC1f'}, $proforma_fields{'LC1a'}, $dup_proforma_fields{'LC99a'}[$i], $dup_proforma_fields{'LC99d'}[$i]);
				
				}
		
			}
		}
	}




### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of the do proforma subroutine
# check this works
    $want_next = $fsm{'DATASET/COLLECTION'};
}

### add any proforma field-specific subroutines here (or better still add to or use
### generic subroutines in tools.pl



sub validate_correct_dataset_entity_type {

	my ($file, $code, $symbol_list, $context) = @_;

	my %allowed_types = (

		'LC14a' => ['biosample'],
		'LC14c' => ['reagent collection', 'project'],

	);

	unless (exists $allowed_types{$code}) {
		report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\nvalidate_dataset_symbol_subset does not contain an entry in the allowed_types hash for the '%s' field, please fix.",$code,$code);
		return;
	}

	$symbol_list eq '' and return;


	my $uniqued_symbols = check_for_duplicated_lines($file,$code,$symbol_list,$context->{$code});

	foreach my $symbol (keys %{$uniqued_symbols}) {

		if (my $id = valid_chado_symbol ($symbol, 'FBlc')) {

			my $entity_type = chat_to_chado ('library_type_from_id', $id)->[0]->[0];
			my $switch = 0;

			foreach my $type (@{$allowed_types{$code}}) {

				if ($type eq $entity_type) {
					$switch++;
					last;
				}
			}

			unless ($switch) {

				report ($file, "%s: '%s' does not match the entity type" . ($#{$allowed_types{$code}} > 0 ? "s" : '') . " allowed for this field ('%s').", $code, $symbol, (join '\', \'', @{$allowed_types{$code}}));

			}




		} else {

			if (my $id = valid_symbol ($symbol, 'FBlc')) {

				report ($file, "%s: Warning: '%s' is a new dataset made in this curation record.  I cannot yet check whether it matches " . ($#{$allowed_types{$code}} > 0 ? "one of the entity types" : 'the entity type') . " allowed for this field ('%s'), so you'll need to double check this yourself (sorry!)", $code, $symbol, (join '\', \'', @{$allowed_types{$code}}));


			} else {

				report ($file, "%s: Invalid symbol '%s' (only symbols of type FBlc are allowed):\n!%s", $code, $symbol, $context->{$code});
			}
		}		

	}
}




1;				# Standard boilerplate.
