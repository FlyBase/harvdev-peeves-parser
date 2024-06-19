# Code to parse experimental tool proformae

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
my @inclusion_essential = qw (TO1a TO1f);			# Fields which must be present in the proforma
my %can_dup = ('TO6a' => 1, 'TO6b' => 1, 'TO6c' => 1, 'TO6d' => 1,
	       );		# Fields which may be duplicated in a proforma.

# These two variables need to be declared here (and not within do_experimental_tool_proforma)
# if there are any field-specific subroutines (at the bottom of this file) for this particular proforma.
my $hash_entries;						# Number of elements in hash list.
my $primary_symbol_list;						# Reference to dehashed data from primary symbol field

sub do_experimental_tool_proforma ($$)
{
# Process an experimental tool proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The primary proforma field (that which contains the valid symbol) defines the number of expected symbols in a hash list.

    $proforma =~ /!.? TO1a\..*? :(.*)/;		# Get data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in primary proforma field
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.
# only require line below if species abbreviation is included primary symbol
#	my $primary_species_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;

	my @primary_id_list = ();

	my @TO1c_list = ();
	my @TO1g_list = ();
	my @TO2a_list = ();
	my @TO2c_list = ();
	my @TO4_list = ();
	my @TO5_list = ();
	my @TO6a_list = ();
	my @TO6b_list = ();
	my @TO6c_list = ();
	my @TO6d_list = ();
	my @TO7c_list = ();
	my @TO10_list = ();

# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
# since they are only required within  the do_experimental_tool_proforma subroutine,
# no need to declare at the top of the file. e.g.
#	my @MA4_list = ();
#   etc.

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(TO1a)\..*? :(.*)/s)
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
			$want_next = $fsm{'EXPERIMENTAL TOOL'};
			return;
		}

		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?)\s+(TO1f)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@primary_id_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}

	elsif ($field =~ /^(.*?)\s+(TO1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TO1c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@TO1c_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(TO1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@TO1g_list = validate_merge_using_ids ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}

	}
	elsif ($field =~ /^(.*?)\s+(TO1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}

	}
	elsif ($field =~ /^(.*?)\s+(TO1i)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}
	elsif ($field =~ /^(.*?) (TO2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TO2a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (TO2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (TO2c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TO2c_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TO4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TO4_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TO5)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TO5_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TO6a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TO6a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TO6b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TO6b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TO6c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TO6c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TO6d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @TO6d_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields,'1');
	}
	elsif ($field =~ /^(.*?)\s+(TO7a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TO7b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TO7c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TO7c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(TO8)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TO9)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(TO10)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@TO10_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}


# fields that are not checked at all yet - validate_stub used to prevent false-positive
# 'Invalid proforma field' message.  Remember to take field codes out of second set of ()
# if checking for the field is implemented.
#	elsif ($field =~ /^(.*?)\s+(??insert field code here??)\..*? :(.*)/s)
#	{
#		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
#	    check_non_utf8 ($file, $2, $3);
#	    check_non_ascii ($file, $2, $3);
#	    double_query ($file, $2, $3) or validate_stub ($file, $1, $2, $3);
#	}

	elsif ($field =~ /^(.*?)\s+TO(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*TO.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in experimental_tool.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

    plingc_merge_check ($file, $change_count,'TO1g', \@TO1g_list, $proforma_fields{'TO1g'});
	
    rename_merge_check ($file, 'TO1c', \@TO1c_list, $proforma_fields{'TO1c'}, 'TO1g', \@TO1g_list, $proforma_fields{'TO1g'});
	
# cross-checks for fullname renames
	cross_check_full_name_rename ($file, 'TO', $hash_entries, $primary_symbol_list, \@TO1c_list, \@TO2c_list, \%proforma_fields);

	cross_check_harv_style_symbol_rename_merge_fields ($file, 'TO', $hash_entries, \@primary_id_list, $primary_symbol_list, \@TO1c_list, \@TO1g_list, \%proforma_fields);

# If TO2c is filled in, TO2a must be filled in. PLUS value in TO2a and TO2c must not be the same
	compare_field_pairs ($file, $hash_entries, 'TO2c', \@TO2c_list, 'TO2a', \@TO2a_list, \%proforma_fields, 'dependent', 'not same');

# TO2c and TO1g must not both be filled in
	compare_field_pairs ($file, $hash_entries, 'TO1g', \@TO1g_list, 'TO2c', \@TO2c_list, \%proforma_fields, 'single', '');

# field that generally ought to be filled in for new tool (not made compulsory in case waiting on FBcv update, so can get a new tool in and hooked up to the relevant alleles and/or transgenic constructs without having to wait for the FBcv update)

	check_filled_in_for_new_feature ($file, 'TO4', $hash_entries, \@TO4_list, \@primary_id_list, \@TO1c_list, \@TO1g_list, \%proforma_fields, 'advised');

# must be filled in for new feature

	check_filled_in_for_new_feature ($file, 'TO5', $hash_entries, \@TO5_list, \@primary_id_list, \@TO1c_list, \@TO1g_list, \%proforma_fields, 'only');


# check that TO10 is filled in when TO1f = 'new' (brand new tool or tool merge) and not in other cases
# only attempt if hashing is correct for TO10
	if ($hash_entries and $#TO10_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

			my $object_status = get_object_status ('TO', $primary_id_list[$i], $TO1c_list[$i], $TO1g_list[$i]);

# if TO10 is filled in
			if (defined $TO10_list[$i] && $TO10_list[$i] ne '') {
				unless ($object_status eq 'new' || $object_status eq 'merge') {
					report ($file, "%s should ONLY be filled in when TO1f contains 'new' (new tool or merge):\n!%s\n!%s\n!%s",'TO10', $proforma_fields{'TO1f'}, $proforma_fields{'TO1a'}, $proforma_fields{'TO10'});
				}
			} else {

				if ($object_status eq 'new' || $object_status eq 'merge') {
					report ($file, "%s MUST be filled in for a %s:\n!%s\n!%s\n!%s",'TO10', ($object_status eq 'new' ? "$object_status tool" : "tool $object_status"), $proforma_fields{'TO1f'}, $proforma_fields{'TO1a'}, $proforma_fields{'TO10'});
				}
			}
		}
	}




	compare_duplicated_field_pairs ($file, 'TO6a', \@TO6a_list, 'TO6b', \@TO6b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
	compare_duplicated_field_pairs ($file, 'TO6c', \@TO6c_list, 'TO6a', \@TO6a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'TO6d', \@TO6d_list, 'TO6a', \@TO6a_list, \%dup_proforma_fields, 'dependent', '');
	compare_duplicated_field_pairs ($file, 'TO6d', \@TO6d_list, 'TO6b', \@TO6b_list, \%dup_proforma_fields, 'dependent', '');

# check that TO6d is not filled in for new or merged datasets
# only perform check if no hashing in proforma to ensure correct checking as TO6d can be duplicated

	if ($hash_entries == 1) {

		my $object_status = get_object_status ('TO', $primary_id_list[0], $TO1c_list[0], $TO1g_list[0]);
	
		if ($object_status eq 'new' || $object_status eq 'merge') {
		
			for (my $i = 0; $i <= $#TO6d_list; $i++) {
		
		
				if (defined $TO6d_list[$i] && $TO6d_list[$i] ne '') {
			
						report ($file, "%s must NOT be filled in for a %s:\n!%s\n!%s\n\n!%s\n!%s", 'TO6d', ($object_status eq 'new' ? "$object_status experimental tool" : "experimental tool $object_status"),  $proforma_fields{'TO1f'}, $proforma_fields{'TO1a'}, $dup_proforma_fields{'TO6a'}[$i], $dup_proforma_fields{'TO6d'}[$i]);
				
				}
		
			}
		}
	}


	if ($hash_entries and $#TO7c_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

			if (defined $TO7c_list[$i] && $TO7c_list[$i] ne '') {

				if (my $id = valid_chado_symbol($TO7c_list[$i], 'FBgn')) {

					my $common_tool_uses = chat_to_chado ('common_tool_uses', $id)->[0];

# check that the gene is typically used as a tool
					unless (defined $common_tool_uses && (scalar @{$common_tool_uses} > 0)) {
						report ($file, "%s: '%s' does not have any 'common_tool_uses' in chado. Either this gene symbol should not be in this field, or you need to make a separate curation record (attributed under FBrf0199194) to add the relevant 'common use' to the gene (in G40), before you submit this curation record\n!%s\n!%s", 'TO7c', $TO7c_list[$i], $proforma_fields{'TO1a'}, $proforma_fields{'TO7c'});
					}
				}

			}

		}
	}

### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of the do proforma subroutine

    $want_next = $fsm{'EXPERIMENTAL TOOL'};
}

### add any proforma field-specific subroutines here (or better still add to or use
### generic subroutines in tools.pl





1;				# Standard boilerplate.
