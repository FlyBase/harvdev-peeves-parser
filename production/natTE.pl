# Code to parse natural transposable element proformae

use strict;
# A set of global variables for communicating between different proformae.

our (%fsm, $want_next, $chado, %prepared_queries);
our %x1a_symbols;						# For detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

our $standard_symbol_mapping;
our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (TE1a TE1f TE1b);			# Fields which must be present in the proforma
my %can_dup = (TE5a => 1, TE5b => 1, TE5c => 1, TE5d => 1);	# Fields which may be duplicated in a proforma.
my $hash_entries;						# Number of elements in hash list.
my $primary_symbol_list;						# Reference to dehashed data from TE1a
my @primary_id_list;							# Dehashed data from TE1f
my @TE1c_list = ();							# Dehashed data from TE1c (rename)
my @TE1g_list = ();							# Dehashed data from TE1g (merge)
my @TE1b_list = ();							# List of lists of symbols given in TE1b

sub do_natTE_proforma ($$)
{
# Process a natTE proforma, the text of which is in the second argument which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The first occurring TE1a record defines the number of expected symbols in a hash list.

    $proforma =~ /!.? TE1a\..*? :(.*)/;		# Get TE1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count fields
    }
    $primary_symbol_list = ['Missing_TE1a_data'];	# Set a default so that other checks don't fail with undef value.

	my $primary_species_list;

	$change_count = 0;

	@primary_id_list = ();							# Flush any data remaining from a previous call
	@TE1c_list = ();							
	@TE1g_list = ();							
	@TE1b_list = ();

# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n

	my @TE3_list = ();# dehashed data from TE3
	my @TE4a_list = (); # dehashed data from TE4a (but NOT split into individual entries if multiple lines present)

	my @TE5a_list = ();
	my @TE5b_list = ();
	my @TE5c_list = ();
	my @TE5d_list = ();
	my @TE8_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(TE1a)\..*? :(.*)/s)
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
			$want_next = $fsm{'NATURAL TRANSPOSON'};
			return;
		}

		($primary_symbol_list, $primary_species_list) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?)\s+(TE1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TE1b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TE1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@primary_id_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(TE3)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TE3_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}

	elsif ($field =~ /^(.*?)\s+(TE1c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@TE1c_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(TE1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@TE1g_list = validate_merge_using_ids ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(TE1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(TE1i)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}


	elsif ($field =~ /^(.*?)\s+(TE4a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TE4a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TE4b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TE4c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TE4d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');

	}
	elsif ($field =~ /^(.*?)\s+(TE4e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TE5a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TE5a_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TE5b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TE5b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TE5c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TE5c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TE5d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TE5d_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TE6a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(TE6b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(TE6c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(TE7)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(TE8)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TE8_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TE9)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(TE10)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(TE11)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(TE12)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TE13)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+TE(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*TE.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in natTE.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

# no !c if TE1g is filled in
	plingc_merge_check ($file, $change_count,'TE1g', \@TE1g_list, $proforma_fields{'TE1g'});

# TE1c and TE1g must not both contain data.

    rename_merge_check ($file, 'TE1c', \@TE1c_list, $proforma_fields{'TE1c'}, 'TE1g', \@TE1g_list, $proforma_fields{'TE1g'});


# Basic cross-checks between TE1f, TE1a, TE1c and TE1g fields that are common to all harvard-style proformae

	cross_check_harv_style_symbol_rename_merge_fields ($file, 'TE', $hash_entries, \@primary_id_list, $primary_symbol_list, \@TE1c_list, \@TE1g_list, \%proforma_fields);


check_filled_in_for_new_feature ($file, 'TE3', $hash_entries, \@TE3_list, \@primary_id_list, \@TE1c_list, \@TE1g_list, \%proforma_fields, 'only');

check_filled_in_for_new_feature ($file, 'TE4a', $hash_entries, \@TE4a_list, \@primary_id_list, \@TE1c_list, \@TE1g_list, \%proforma_fields, 'yes');

compare_duplicated_field_pairs ($file, 'TE5b', \@TE5b_list, 'TE5a', \@TE5a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'TE5d', \@TE5d_list, 'TE5c', \@TE5c_list, \%dup_proforma_fields, 'dependent', '');

# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#TE1b_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'TE1a', $primary_symbol_list, 'TE1b', \@TE1b_list, \%proforma_fields, "You must include the valid symbol in TE1b when \!c-ing it under the 'unnattributed' publication.");

}


if ($hash_entries and $#TE3_list + 1 == $hash_entries) {
	for (my $i = 0; $i < $hash_entries; $i++) {

		if (defined $TE3_list[$i] && $TE3_list[$i] ne '') {

			if (valid_symbol ($TE3_list[$i], 'chado_species_abbreviation')) {
				unless ($TE3_list[$i] eq $primary_species_list->[$i]) {

					report ($file, "Species (%s) of symbol '%s' given in TE1a does not match the species abbreviation '%s' given in TE3.\n!%s\n!%s", $primary_species_list->[$i], $primary_symbol_list->[$i], $TE3_list[$i], $proforma_fields{TE1a}, $proforma_fields{TE3});

				}
			}

		}

	}
}

### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of this subroutine

    $want_next = $fsm{'NATURAL TRANSPOSON'};
}




1;				# Standard boilerplate.
