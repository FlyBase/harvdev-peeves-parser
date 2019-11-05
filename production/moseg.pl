# Code to parse molecular segment and construct proformae

use strict;
# A set of global variables for communicating between different proformae.

our (%fsm, $want_next, $chado, %prepared_queries);
our %x1a_symbols;						# For detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dummy_dup_proforma_fields;	# dummy (as no fields can be duplicated in proforma) hash to keep check_dups happy
my @inclusion_essential = qw (MS1a MS1f);			# Fields which must be present in the proforma
my $hash_entries;						# Number of elements in hash list.
my $primary_symbol_list;						# Reference to dehashed data from primary symbol field
my @FBtp_list;							# Dehashed data from MS1f
my @MS1c_list = ();							# Dehashed data from MS1c (rename)
my @MS1g_list = ();							# Dehashed data from MS1g (merge)

sub do_moseg_proforma ($$)
{
# Process a moseg proforma, the text of which is in the second argument which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dummy_dup_proforma_fields = ();

# The first occurring MS1a record defines the number of expected symbols in a hash list.

    $proforma =~ /!.? MS1a\..*? :(.*)/;		# Get MS1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count fields
    }
    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;

	@FBtp_list = ();							# Flush any data remaining from a previous call
	@MS1c_list = ();							
	@MS1g_list = ();							


# arrays below contain data that is dehashed, but has not been split on \n
	my @MS1b_list = ();
	my @MS4a_list = ();
	my @MS4b_list = ();
	my @MS14_list = ();
	my @MS16_list = ();
	my @MS21_list = ();
	my @MS19c_list = ();
	my @MS19e_list = ();
	my @MS30_list = ();
	my @MS30a_list = ();

    my @MS14a_list = ();
    my @MS14b_list = ();
    my @MS14c_list = ();
    my @MS14d_list = ();
    my @MS14e_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(MS1a)\..*? :(.*)/s)
	{
	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $code, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
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
			$want_next = $fsm{'MOLECULAR SEGMENT AND CONSTRUCT'};
			return;
		}

		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?)\s+(MS1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS1b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@FBtp_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(MS16)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS16_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS4a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS4a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS21)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS21_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS14)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS14_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (MS14a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		push @MS14a_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (MS14b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		push @MS14b_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (MS14c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		push @MS14c_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (MS14d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		push @MS14d_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (MS14e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		push @MS14e_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?)\s+(MS22)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MS1c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@MS1c_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(MS1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@MS1g_list = validate_merge_using_ids ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(MS1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(MS1i)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);

	}
	elsif ($field =~ /^(.*?)\s+(MS3b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS3d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS19a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS19b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS19c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS19c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
		if (defined $3 && $3 ne '') {

			report ($file, "%s: **WARNING**: Do NOT fill in this field, it will make your record bounce !! (Parsing of this field is currently broken and it is not clear whether the field is still needed in the proforma at all - see DOC-117)\n!%s", $2, $proforma_fields{$2});

		}
	}
	elsif ($field =~ /^(.*?)\s+(MS19d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS19e)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS19e_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS20)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?)\s+(MS4b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS4b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS4h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS4g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MS1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MS4e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MS5a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS5b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS12)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MS18a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MS18b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(MS10b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS11)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS30)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS30_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS30a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@MS30a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(MS15)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(MS24)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?)\s+(MS9|MS17|MS7a|MS7b|MS7c|MS7e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    validate_stub ($file, $1, $2, $3);
	}

	elsif ($field =~ /^(.*?)\s+MS(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*MS.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in moseg.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

# no !c if MS1g is filled in
	plingc_merge_check ($file, $change_count,'MS1g', \@MS1g_list, $proforma_fields{'MS1g'});

# MS1c and MS1g must not both contain data.

    rename_merge_check ($file, 'MS1c', \@MS1c_list, $proforma_fields{'MS1c'}, 'MS1g', \@MS1g_list, $proforma_fields{'MS1g'});

# Basic cross-checks between MS1f, MS1a, MS1c and MS1g fields that are common to all harvard-style proformae

	cross_check_harv_style_symbol_rename_merge_fields ($file, 'MS', $hash_entries, \@FBtp_list, $primary_symbol_list, \@MS1c_list, \@MS1g_list, \%proforma_fields);




# Cross-checks that are specific to construct proforma, so are not included in above check. Checks are only attempted when the number of entries in the MS1a field (defined by $hash_entries) is the same as that in the MS1f field (defined by @FBtp_list).
# 1. checking syntax of construct symbol - this is currently done in every case (i.e. regardless of
# whether its a new/existing construct, a rename or merge) because it avoids repeating code below.
# It is done here rather than where MS1a field is first processed
# (using validate_primary_proforma_field) as the results of the syntax checking
# are needed for cross-checks with other fields.

	if ($hash_entries and $#FBtp_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

			my $nat_te_end = check_construct_symbol_format ($file, 'MS1a', $primary_symbol_list->[$i], \%proforma_fields);

			my $object_status = get_object_status ('MS', $FBtp_list[$i], $MS1c_list[$i], $MS1g_list[$i]);

### start requirements for MS16 field
# MS16 is filled in
			if (defined $MS16_list[$i] && $MS16_list[$i] ne '') {

# only do the checks if the value in MS16 is valid (to prevent double error messages)
				if (my $MS16_value = valid_symbol($MS16_list[$i], 'MS16_value')) {
# $nat_te_end is only populated if the symbol in MS1a 'looks' like an FBtp symbol (either transposable-element based or TI-style)
					if ($nat_te_end) {

						unless ($MS16_value =~ m/FBtp/) {
							report ($file, "%s: '%s' is not a valid value when the construct in MS1a is of the type FBtp:\n!%s\n!%s\n!%s", 'MS16', $MS16_list[$i], $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS16'});

						} else {

							if ($nat_te_end eq 'TI') {
								if ($MS16_value eq 'FBtp') {
									report ($file, "%s: '%s' is not a valid value when the construct in MS1a is a TI-style construct:\n!%s\n!%s\n!%s", 'MS16', $MS16_list[$i],  $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS16'});
								}
							}
						}

# symbol in MS1a does not look like an FBtp symbol
					} else {

						if ($MS16_value  eq 'FBtp') {
							report ($file, "%s: '%s' is not a valid value when the construct in MS1a is NOT of the type FBtp:\n!%s\n!%s\n!%s", 'MS16', $MS16_list[$i],  $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS16'});
						}
					}

# add test for constraint on filling in MS19e
					if (defined $MS19e_list[$i] && $MS19e_list[$i] ne '') {
						unless ($MS16_value eq 'engineered_construct') {
							report ($file, "%s can ONLY be filled in for a FBmc type of construct:\n!%s\n!%s\n!%s\n!%s",'MS19e', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS16'}, $proforma_fields{'MS19e'});
						}
					}


				}

# MS16 not filled in
			} else {

				if ($object_status eq 'new' || $object_status eq 'merge') {
					report ($file, "%s must be filled in for a %s:\n!%s\n!%s\n!%s", 'MS16', ($object_status eq 'new' ? "$object_status construct" : "construct $object_status"),  $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS16'});
				}


# add test for constraint on filling in MS19e
				if (defined $MS19e_list[$i] && $MS19e_list[$i] ne '') {

# slightly hacky, but works
					if ($FBtp_list[$i] =~ m/^(FBtp|FBms)\d{7,}$/) {

						report ($file, "%s can ONLY be filled in for a FBmc type of construct:\n!%s\n!%s\n!%s",'MS19e', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS19e'});

					}
				}


			}
### end requirements for MS16 field


### start requirements for MS4a field
# MS4a is filled in
			if (defined $MS4a_list[$i] && $MS4a_list[$i] ne '') {

# only do the checks if the value in MS4a is valid (to prevent double error messages)
				if (my $MS4a_value = valid_symbol($MS4a_list[$i], 'MS4a_value')) {
# $nat_te_end is only populated if the symbol in MS1a 'looks' like an FBtp symbol (either transposable-element based or TI-style)
					if ($nat_te_end) {

						if ($nat_te_end eq 'TI') {
							report ($file, "%s must NOT be filled in for a TI-style construct:\n!%s\n!%s\n!%s",'MS4a', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS4a'});

						} else {

							unless ($MS4a_value  eq 'FBtp') {
								report ($file, "%s: '%s' is not a valid value when the construct in MS1a is of the type FBtp:\n!%s\n!%s\n!%s", 'MS4a', $MS4a_list[$i], $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS4a'});
							}

						}

# symbol in MS1a does not look like an FBtp symbol
					} else {

						if ($MS4a_value  eq 'FBtp') {
							report ($file, "%s: '%s' is not a valid value when the construct in MS1a is NOT of the type FBtp:\n!%s\n!%s\n!%s", 'MS4a', $MS4a_list[$i],  $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS4a'});
						}
					}
				}

# MS4a not filled in
			} else {

				if ($object_status eq 'new') {

					unless ($nat_te_end && $nat_te_end eq 'TI') {

						report ($file, "%s must be filled in for a new construct:\n!%s\n!%s\n!%s", 'MS4a', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS4a'});

					}
				}

			}
### end requirements for MS4a field

### start requirements for MS21 field
# MS21 is filled in
			if (defined $MS21_list[$i] && $MS21_list[$i] ne '') {

				if ($nat_te_end) {

					if ($nat_te_end eq 'TI') {
						report ($file, "%s must NOT be filled in for a TI-style FBtp construct:\n!%s\n!%s\n!%s",'MS21', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS21'});

					} else {

# work out the plingc status of MS21:
						my $MS21_plingc = $proforma_fields{'MS21'};
						$MS21_plingc =~ s/^(.*?)\s+MS21\..*? :.*/$1/s;

						unless ($object_status eq 'new' || (changes ($file, 'MS21', $MS21_plingc))) {
							report ($file, "%s must have !c when filled in for an existing insertion:\n!%s\n!%s\n!%s", 'MS21', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS21'});

						} else {

							unless ($nat_te_end eq $MS21_list[$i]) {

								report ($file, "%s: Mismatch between the transposon '%s' and the transposable element end of the symbol '%s' in MS1a:\n!%s\n!%s\n!%s", 'MS21', $MS21_list[$i], $primary_symbol_list->[$i], $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS21'});


							}
						}
					}

				} else {

						report ($file, "%s must NOT be filled in for a non-FBtp entry:\n!%s\n!%s\n!%s",'MS21', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS21'});

				}

		
# MS21 not filled in
			} else {

				if ($object_status eq 'new') {

					if ($nat_te_end && $nat_te_end ne 'TI') {

						report ($file, "%s must be filled in for a new transposable element-based FBtp construct:\n!%s\n!%s\n!%s", 'MS21', $proforma_fields{'MS1f'}, $proforma_fields{'MS1a'}, $proforma_fields{'MS21'});

					}
				}

			}

### end requirements for MS21 field

		}
	}

# Reminder to look for insertions that may need renaming when constructs are being renamed/merged
# rename - only do the check when the hashing is correct and when symbol given in rename field corresponds
# to a valid FBtp in chado (to prevent confusing reminder messages and because its only appropriate
# for FBtp, not FBmc or FBms)
if ($hash_entries and $#{$primary_symbol_list} + 1 == $hash_entries and $#MS1c_list + 1 == $hash_entries) {

	for (my $i = 0; $i < $hash_entries; $i++) {

		if ($MS1c_list[$i]) {

			if (valid_chado_symbol ($MS1c_list[$i], "FBtp")) {

				report ($file, "REMINDER for construct rename: look in ti_data for any insertions of '%s' and rename them in a separate curation record (using the general FlyBase analysis reference FBrf0105495) if necessary:\n!%s\n!%s", $MS1c_list[$i], $proforma_fields{"MS1a"}, $proforma_fields{"MS1c"});
			}
		}
	}
}




check_filled_in_for_new_feature ($file, 'MS14', $hash_entries, \@MS14_list, \@FBtp_list, \@MS1c_list, \@MS1g_list, \%proforma_fields, 'advised');

compare_field_pairs ($file, $hash_entries, 'MS30', \@MS30_list, 'MS30a', \@MS30a_list, \%proforma_fields, 'pair::if either is filled in', '');


# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#MS1b_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'MS1a', $primary_symbol_list, 'MS1b', \@MS1b_list, \%proforma_fields, "You must include the valid symbol in MS1b when \!c-ing it under the 'unnattributed' publication.");

}
### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of this subroutine

    $want_next = $fsm{'MOLECULAR SEGMENT AND CONSTRUCT'};
}




1;				# Standard boilerplate.
