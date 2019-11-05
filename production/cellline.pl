# Code to parse CULTURED CELL LINE proformae

use strict;
# A set of global variables for communicating between different proformae.

our (%fsm, $want_next); # Global variables for finite state machine (defines what proforma expected next)
our ($chado, %prepared_queries); # Global variables for communication with Chado.
our %x1a_symbols;						# Hash for detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22 (if valid FBrf number)

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl,


my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (TC1a TC1f);			# Fields which must be present in the proforma
my %can_dup = ();		# Fields which may be duplicated in a proforma.

# These two variables need to be declared here (and not within do_cellline_proforma)
# if there are any field-specific subroutines (at the bottom of this file) for this particular proforma.
my $hash_entries;						# Number of elements in hash list.
my $primary_symbol_list;				# Dehashed data from primary proforma field (e.g. G1a, MA1a etc)

sub do_cellline_proforma ($$)
{
# Process a cellline proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The primary proforma field (that which contains the valid symbol) defines the number of expected symbols in a hash list.

    $proforma =~ /!.? TC1a\..*? :(.*)/;		# Get data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in primary proforma field
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.


	$change_count = 0;

	my @primary_id_list = ();
	
	my @TC1j_list = ();
	my @TC1e_list = ();
	my @TC1g_list = ();
	my @TC1d_list = ();
	my @TC4a_list = ();
	my @TC4b_list = ();
	my @TC5a_list = ();
	my @TC5c_list = ();
	my @TC5d_list = ();

# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
# since they are only required within  the do_cellline_proforma subroutine,
# no need to declare at the top of the file. e.g.
#	my @MA4_list = ();
#   etc.

FIELD:
	foreach my $field (split (/\n!/, $proforma))
	{
	if ($field =~ /^(.*?)\s+(TC1a)\..*? :(.*)/s)
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
			$want_next = $fsm{'CULTURED CELL LINE'};
			return;
		}

# not trapping species prefix info from symbol because no species prefix is included in the valid symbol for non-Dmel cell lines. eg. DH-33 (FBtc0000023) = Dhyd
		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	
	elsif ($field =~ /^(.*?)\s+(TC1f)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@primary_id_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(TC1j)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TC1j_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC1b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC1c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC1d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TC1d_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@TC1e_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(TC1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@TC1g_list = validate_merge_using_ids ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
		if (defined $3 && $3 ne '') {

			report ($file, "%s: WARNING: this field cannot be filled in (you have '%s') as parsing of this field is not implemented in proforma loading software. Consult Kathleen for how to proceed if you really need to use this field.", $2, $3);
		}

	}
	elsif ($field =~ /^(.*?)\s+(TC1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}

		if (defined $3 && $3 ne '') {

			report ($file, "%s: WARNING: this field cannot be filled in (you have '%s') as parsing of this field is not implemented in proforma loading software. Consult Kathleen for how to proceed if you really need to use this field.", $2, $3);
		}

	}
	elsif ($field =~ /^(.*?)\s+(TC1i)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}
	elsif ($field =~ /^(.*?)\s+(TC2a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC2b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \
$primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC2c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC2d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC2e)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC3a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC4a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TC4a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC4b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TC4b_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC5a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TC5a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC5b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC5c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TC5c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC5d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TC5d_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC8)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TC9)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TC10)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
# fields that are not checked at all yet - validate_stub used to prevent false-positive
# 'Invalid proforma field' message.  Remember to take field codes out of second set of ()
# if checking for the field is implemented.
#	elsif ($field =~ /^(.*?)\s+(<field>)\..*? :(.*)/s)
#	{
#		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
#		check_non_utf8 ($file, $2, $3);
#		check_non_ascii ($file, $2, $3);
#		double_query ($file, $2, $3) or validate_stub ($file, $1, $2, $3);
#	}

	elsif ($field =~ /^(.*?)\s+TC(.+?)\..*?:(.*)$/s)
	{
		report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*TC.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
			report ($file, "Malformed proforma field  (message tripped in cellline.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
	}

### Start of tests that can only be done after parsing the entire proforma. ###

	check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

	plingc_merge_check ($file, $change_count,'TC1g', \@TC1g_list, $proforma_fields{'TC1g'});
	
    rename_merge_check ($file, 'TC1e', \@TC1e_list, $proforma_fields{'TC1e'}, 'TC1g', \@TC1g_list, $proforma_fields{'TC1g'});
	

	cross_check_harv_style_symbol_rename_merge_fields ($file, 'TC', $hash_entries, \@primary_id_list, $primary_symbol_list, \@TC1e_list, \@TC1g_list, \%proforma_fields);


	check_filled_in_for_new_feature ($file, 'TC1d', $hash_entries, \@TC1d_list, \@primary_id_list, \@TC1e_list, \@TC1g_list, \%proforma_fields, 'only');

	check_filled_in_for_new_feature ($file, 'TC1j', $hash_entries, \@TC1j_list, \@primary_id_list, \@TC1e_list, \@TC1g_list, \%proforma_fields, 'only');


	compare_field_pairs ($file, $hash_entries, 'TC4a', \@TC4a_list, 'TC4b', \@TC4b_list, \%proforma_fields, 'pair', '');

	compare_field_pairs ($file, $hash_entries, 'TC1a', $primary_symbol_list, 'TC4a', \@TC4a_list, \%proforma_fields, '', 'not same');

	compare_field_pairs ($file, $hash_entries, 'TC5d', \@TC5d_list, 'TC5c', \@TC5c_list, \%proforma_fields, 'dependent', '');


# check that if TC1j is filled in, that the value in TC1a is not a valid FBtc symbol *in chado*
# only do the checks if the hashing is correct
	if ($hash_entries and $#TC1j_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

# only do the check if TC1j is filled in
			if (defined $TC1j_list[$i] && $TC1j_list[$i] ne '') {

				if (valid_chado_symbol($primary_symbol_list->[$i], "FBtc")) {

					report ($file, "%s is filled in (suggesting a new cell line), but '%s' in %s is a valid symbol in chado, so this looks like some kind of error to me.", 'TC1j', $primary_symbol_list->[$i], 'TC1a');
				}
			}
		}
	}

### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of the do proforma subroutine

	$want_next = $fsm{'CULTURED CELL LINE'};
}

### add any proforma field-specific subroutines here (or better still add to or use
### generic subroutines in tools.pl

sub validate_TC1j {
# converted to process_field_data + %field_specific_checks format. 140703.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {

		unless ($datum =~ m|^FBtc9[0-9]{6}$|) {
			report ($file, "%s: '%s' is not the correct format for this field (it should be 'FBtc9nnnnnn' where 'n' is any number.", $code, $datum);


		}

		if (valid_symbol($datum, 'uniquename')) {

			report ($file, "%s: '%s' is already a valid FBtc id in chado, so I *think* its an error that it is in this field", $code, $datum);
		}


	}


}




1;				# Standard boilerplate.
