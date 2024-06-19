# Code to parse balancer proformae

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


our (%fsm, $want_next, $chado, %prepared_queries);
our %x1a_symbols;		# For detecting duplicate proformae in a record

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dummy_dup_proforma_fields;	# dummy (as no fields can be duplicated in proforma) hash to keep check_dups happy
my @inclusion_essential = qw (AB1a AB1e AB1f AB1g AB8);	# Fields which must be present in the proforma

my $hash_entries;		# Number of elements in hash list, whether aberrations or balancers.
my $primary_symbol_list;						# Reference to dehashed data from primary symbol field


my @FBba_list = ();		# List of FBba identifiers given in AB1h
my @AB1b_list = ();		# List of lists of balancer names given in AB1b
my @AB1e_list = ();		# Dehashed data from AB1e
my @AB1f_list = ();		# Dehashed data from AB1f
my @AB2a_list = ();		# Dehashed data from AB2a. (Not currently being used, in place for when tackle DC-423).
my @AB2b_list = ();		# List of lists of balancer names given in AB2b
my @AB2c_list = ();		# Dehashed data from AB2c. (Not currently being used, in place for when tackle DC-423).
my $firstAB; #because AB1h comes before AB1a

sub do_balancer_proforma ($$)
{
# Process a balancer proforma, the text of which is in the second argument which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dummy_dup_proforma_fields = ();
# The first occurring AB1a record defines the number of expected symbols in a hash list.

    $proforma =~ /!.? AB1a\..*? :(.*)/;		# Get AB1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;	# Count fields
	$firstAB=$1;
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.
	my $primary_species_list;

	$change_count = 0;

# A set of local variables for post-checks.

    my $AB1g_data = '';			# The y/n data found in AB1g.

    @AB1b_list = ();			# Ensure this lot is cleared out, even if the corresponding
    @AB1e_list = ();			# proforma field is omitted.
    @AB1f_list = ();
	@AB2a_list = ();	
    @AB2b_list = ();
    @AB2c_list = ();


	my @AB1g_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?) (AB1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_AB1h ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (AB1a)\..*? :(.*)/s)
	{
	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $code, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);

# Enforce the rule that at most one of A1a and AB1a may use hash lists.  This is a fatal error condition and
# it's not safe trying to validate anything else in the proforma.  $g_num_syms contains the number of entries
# in A1a's hash list.

	    if ($g_num_syms > 1 and $hash_entries > 1)
	    {

		report ($file, "%s: Can't use a hashed balancer proforma after a hashed aberration proforma.\n!%s", $code, $proforma_fields{$code});
			$want_next = $fsm{'GENOTYPE VARIANT'};
		return;
	    }

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
			$want_next = $fsm{'GENOTYPE VARIANT'};
			return;
		}

		($primary_symbol_list, $primary_species_list) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	elsif ($field =~ /^(.*?) (AB1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@AB1b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (AB1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@AB1e_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?) (AB1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@AB1f_list = validate_x1f ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?) (AB1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    $AB1g_data = $3; # for now, keeping $AB1g_data (not dehashed) as well as storing @AB1g_list (dehashed), until worked out whether its safe/desirable to change existing code to use dehashed @AB1g_list version [gm140625]
		unless (double_query ($file, $2, $3)) {
			@AB1g_list = validate_x1g ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}

#	    double_query ($file, $2, $3) or validate_x1g ($file, $2, $1, $3, $proforma_fields{$2});
	}
	elsif ($field =~ /^(.*?) (AB2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@AB2a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (AB2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@AB2b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?) (AB2c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		@AB2c_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (AB11a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (AB11b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}
	elsif ($field =~ /^(.*?) (AB10)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (AB8)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		contains_data ($file, $2, $3, $proforma_fields{$2}) and process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (AB3)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (AB9)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (AB5a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (AB5b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (AB6)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (AB7)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, $primary_symbol_list, 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) AB(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*AB.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in balancer.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma.

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

    if ($hash_entries and exists $proforma_fields{'AB1h'})
    {
	cross_check_FBid_symbol ($file, 1, 0, 'FBba', 'balancer', $hash_entries,
				 'AB1h', \@FBba_list, 'AB1a', $primary_symbol_list,
				 'AB1e', \@AB1e_list, 'AB1f', \@AB1f_list);
    }

    if (exists $proforma_fields{'AB1g'})
    {
	cross_check_1a_1g ($file, 'AB', 'FBba', 'balancer', $hash_entries, $AB1g_data, $primary_symbol_list);
    }


# If AB1e is filled in, check AB1g is 'n'
	if ($hash_entries and exists $proforma_fields{'AB1e'}) {

		cross_check_x1e_x1g ($file, 'AB1e', $hash_entries, $AB1g_data, \@AB1e_list, $proforma_fields{'AB1e'});

	}


# AB1e and AB1f must not both contain data.

    rename_merge_check ($file, 'AB1e', \@AB1e_list, $proforma_fields{'AB1e'}, 'AB1f', \@AB1f_list, $proforma_fields{'AB1f'});

# check for rename across species.
	check_for_rename_across_species ($file, $hash_entries, 'AB', $primary_species_list, \@AB1e_list, \%proforma_fields);


# no !c if AB1f is filled in

	plingc_merge_check ($file, $change_count,'AB1f', \@AB1f_list, $proforma_fields{'AB1f'});

# cross-checks for fullname renames
	cross_check_full_name_rename ($file, 'AB', $hash_entries, $primary_symbol_list, \@AB1e_list, \@AB2c_list, \%proforma_fields);


# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#AB1b_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'AB1a', $primary_symbol_list, 'AB1b', \@AB1b_list, \%proforma_fields, "You must include the valid symbol in AB1b when \!c-ing it under the 'unnattributed' publication.");

}
### End of tests that can only be done after parsing the entire proforma.


    $want_next = $fsm{'GENOTYPE VARIANT'};
}

sub validate_AB1h ($$$)
{
# Data is either a single FBba or empty.  It should be present for author-curated proformae.  Issue a warning if
# it is present in other proforma types.

    my ($code, $change, $FBbas) = @_;
    $FBbas = trim_space_from_ends ($file, $code, $FBbas);

    if (valid_symbol ($file, 'curator_type') eq 'USER' || valid_symbol ($file, 'curator_type') eq 'AUTO')
    {
	$FBbas eq '' and report ($file, "%s: %s-curated proformae should have data.", $code,valid_symbol ($file, 'curator_type'));
    }
    else
    {
	$FBbas eq '' or report ($file, "%s: Curators don't usually fill in the FBba field.  " .
				"Are you sure you want to for '%s'?", $code, $firstAB, join (' # ', @{$primary_symbol_list}));
    }
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});

	single_line ($file, $code, $FBbas, $proforma_fields{$code}) or return;

    @FBba_list = FBid_list_check ($file, $code, 'FBba', $hash_entries, $FBbas);

# More tests at the post-check phase.
}



sub validate_AB5b {
# converted to process_field_data + %field_specific_checks format. 140701.

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

1;				# Standard boilerplate.
