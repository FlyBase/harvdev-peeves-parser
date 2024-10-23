# Code to parse gene group proformae

use strict;

# A set of global variables for communicating between different proformae.

our (%fsm, $want_next);			# Global variables for finite state machine.
our ($chado, %prepared_queries);	# Global variables for communication with Chado.



# A set of Peeves-global variables for communicating between different proformae.
our %x1a_symbols;						# For detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (GG1a GG1g);			# Fields which must be present in the proforma
my %can_dup = (GG8a => 1, GG8b => 1, GG8c => 1, GG8d => 1,);		# Fields which may be duplicated in a proforma.
my $hash_entries;						# Number of elements in hash list.

# A set of file-global variables for communicating between different proforma fields.

my $primary_symbol_list;						# Reference to dehashed data from primary symbol field
my @FBid_list = ();							# Dehashed data from GG1h
my @GG1e_list = ();							# Dehashed data from GG1e (rename)
my @GG1f_list = ();							# Dehashed data from GG1f (merge)
my @GG1g_list = ();							# dehashed data from GG1g field

my @GG13_list = ();
my @GG14_list = ();

sub do_genegroup_proforma ($$)
{
# Process a gene group proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The first occurring GG1a record defines the number of expected symbols in a hash list.

    $proforma =~ /!.? GG1a\..*? :(.*)/;		# Get GG1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in GG1a field
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;


    my $GG1g_data = '';			# The y/n data found in GG1g.

# clear out the variables at the start of each proforma, so that they are cleared out
# even if the corresponding proforma field is omitted.
    @FBid_list = ();
	@GG1e_list = ();
	@GG1f_list = ();
	@GG1g_list = ();

# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n

# since they are only required within a given proforma, just have them here within the do_GG_proforma subroutine, no need to declare at the top of the file

	my @GG1b_list = ();
	my @GG2a_list = ();	
	my @GG2c_list = ();	
	my @GG6a_list = ();
	my @GG6b_list = ();
	my @GG6c_list = ();
	my @GG11_list = ();
	my @GG4_list = ();
	my @GG7a_list = ();
	my @GG7c_list = ();
	my @GG8a_list = ();
	my @GG8b_list = ();
	my @GG8c_list = ();
	my @GG8d_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?) (GG1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GG1h ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?)\s+(GG1a)\..*? :(.*)/s)
	{
	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);

# basic checks of primary symbol field format (must contain data and must be a single line) - now uses 'contains_data' and 'single_line' subroutines.
# Note that this basic format check for the primary symbol field is set up differently for the gene and aberration proformae compared to other proformae.
# For gene and aberration proformae - the two checks are within the 'validate_field' subroutine, which means that if
# either check fails, the rest of the proforma is still checked.
# For other proformae, the two checks occur in the loop where the field is identified, ie. before the 'validate_field' subroutine is called.  This means that if either check fails and the 'or return' is tripped, the rest of the proforma fields are not checked.


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
			$want_next = $fsm{'GENEGROUP'};
			return;
		}

		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}


	elsif ($field =~ /^(.*?) (GG1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG1b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GG1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@GG1e_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?) (GG1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@GG1f_list = validate_x1f ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
		if (defined $3 && $3 ne '') {

			report ($file, "%s: WARNING: this field cannot be filled in (you have '%s') as parsing of this field is not implemented in proforma loading software. Consult Kathleen for how to proceed if you really need to use this field.", $2, $3);
		}

	}
	elsif ($field =~ /^(.*?) (GG1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		$GG1g_data = $3; # for now, keeping $GG1g_data (not dehashed) as well as storing @GG1g_list (dehashed), until worked out whether its safe/desirable to change existing code to use dehashed @GG1g_list version [gm140627]

		unless (double_query ($file, $2, $3)) {
			@GG1g_list = validate_x1g ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}

	}
	elsif ($field =~ /^(.*?) (GG2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG2a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GG2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?) (GG2c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG2c_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GG3a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (GG3b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);

	}
	elsif ($field =~ /^(.*?) (GG4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG4_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GG5)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?) (GG6a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG6a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GG6b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG6b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}	elsif ($field =~ /^(.*?) (GG6c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG6c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GG7a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG7a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?) (GG7c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG7c_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GG9)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(GG10)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');

	}

	elsif ($field =~ /^(.*?) (GG11)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG11_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GG12)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GG8a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @GG8a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GG8b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @GG8b_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GG8c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @GG8c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GG8d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		push @GG8d_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GG13)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG13_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GG14)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GG14_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}

	elsif ($field =~ /^(.*?)\s+GG(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*GG.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in genegroup.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);


    if ($hash_entries and exists $proforma_fields{'GG1g'})
    {
	cross_check_1a_1g ($file, 'GG', 'FBgg', 'gene group', $hash_entries, $GG1g_data, $primary_symbol_list);


    }

	if ($hash_entries and exists $proforma_fields{'GG1h'}) # new from March 09 V.1.3.0 
    {	
		cross_check_FBid_symbol ($file, 1, 0, 'FBgg', 'gene group', $hash_entries,
				 'GG1h', \@FBid_list, 'GG1a', $primary_symbol_list,
				 'GG1e', \@GG1e_list,  'GG1f', \@GG1f_list);
    }


# If GG1e is filled in, check GG1g is 'n'
	if ($hash_entries and exists $proforma_fields{'GG1e'}) {

		cross_check_x1e_x1g ($file, 'GG1e', $hash_entries, $GG1g_data, \@GG1e_list, $proforma_fields{'GG1e'});

	}

# GG1e and GG1f must not both contain data.
    rename_merge_check ($file, 'GG1e', \@GG1e_list, $proforma_fields{'GG1e'}, 'GG1f', \@GG1f_list, $proforma_fields{'GG1f'});

# no !c if GG1f is filled in
	plingc_merge_check ($file, $change_count,'GG1f', \@GG1f_list, $proforma_fields{'GG1f'});

# cross-checks for fullname renames
	cross_check_full_name_rename ($file, 'GG', $hash_entries, $primary_symbol_list, \@GG1e_list, \@GG2c_list, \%proforma_fields);


# If GG2c is filled in, GG2a must be filled in. PLUS value in GG2a and GG2c must not be the same
compare_field_pairs ($file, $hash_entries, 'GG2c', \@GG2c_list, 'GG2a', \@GG2a_list, \%proforma_fields, 'dependent', 'not same');

# GG2c and GG1f must not both be filled in
compare_field_pairs ($file, $hash_entries, 'GG1f', \@GG1f_list, 'GG2c', \@GG2c_list, \%proforma_fields, 'single', '');

# If GG1f is filled in, GG2a must be filled in
compare_field_pairs ($file, $hash_entries, 'GG1f', \@GG1f_list, 'GG2a', \@GG2a_list, \%proforma_fields, 'dependent', '');



# Fields which must only be filled in for new gene groups
check_filled_in_for_new_feature ($file, 'GG2a', $hash_entries, \@GG2a_list, \@GG1g_list, \@GG1e_list, \@GG1f_list, \%proforma_fields, 'yes');

# cross-checks for GG4, only attempt if hashing is correct for GG4
	if ($hash_entries and $#GG4_list + 1 == $hash_entries) {


		# plingc status is the same for all hash entries
		my $GG4_plingc = $proforma_fields{'GG4'};
		$GG4_plingc =~ s/^(.*?)\s+GG4\..*? :.*/$1/s;

		for (my $i = 0; $i < $hash_entries; $i++) {

			my $object_status = get_object_status ('GG', $GG1g_list[$i], $GG1e_list[$i], $GG1f_list[$i]);


			if ($object_status eq 'new' || $object_status eq 'merge') {

				unless (defined $GG4_list[$i] && $GG4_list[$i] ne '') {

					report ($file, "%s must be filled in for a %s:\n!%s\n!%s", 'GG4', ($object_status eq 'new' ? "$object_status gene group" : "gene group $object_status"), $proforma_fields{'GG1a'}, $proforma_fields{'GG4'});

				}

				if (changes ($file, 'GG4', $GG4_plingc)) {
					report ($file, "%s: !c cannot be used for a %s:\n!%s\n!%s", 'GG4', ($object_status eq 'new' ? "$object_status gene group" : "gene group $object_status"), $proforma_fields{'GG1a'}, $proforma_fields{'GG4'});

				}
				

			} elsif ($object_status eq 'existing' || $object_status eq 'rename') {

				if (changes ($file, 'GG4', $GG4_plingc)) {

					unless (defined $GG4_list[$i] && $GG4_list[$i] ne '') {

						report ($file, "%s cannot be !c to nothing for %s:\n!%s\n!%s", 'GG4', ($object_status eq 'existing' ? "an $object_status gene group" : "a gene group $object_status"),  $proforma_fields{'GG1a'}, $proforma_fields{'GG4'});


					}


				} else {

					if (defined $GG4_list[$i] && $GG4_list[$i] ne '') {

						report ($file, "%s cannot be filled in without !c for %s:\n!%s\n!%s", 'GG4', ($object_status eq 'existing' ? "an $object_status gene group" : "a gene group $object_status"),  $proforma_fields{'GG1a'}, $proforma_fields{'GG4'});

					}

				}


			}
		}
	}




# only run the test if the field contains a single line of data, to prevent confusing/repeated error messages
if (exists $proforma_fields{'GG11'} && index ($proforma_fields{'GG11'}, "\n") == -1) {

	check_filled_in_for_new_feature ($file, 'GG11', $hash_entries, \@GG11_list, \@GG1g_list, \@GG1e_list, \@GG1f_list, \%proforma_fields, 'yes');
}
# GG8 unit tests
compare_duplicated_field_pairs ($file, 'GG8a', \@GG8a_list, 'GG8b', \@GG8b_list, \%dup_proforma_fields, 'pair::if either is filled in', '');
compare_duplicated_field_pairs ($file, 'GG8a', \@GG8a_list, 'GG8c', \@GG8c_list, \%dup_proforma_fields, 'pair::if either is filled in', '');

compare_duplicated_field_pairs ($file, 'GG8d', \@GG8d_list, 'GG8a', \@GG8a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GG8d', \@GG8d_list, 'GG8b', \@GG8b_list, \%dup_proforma_fields, 'dependent', '');

# check that GG8d is not filled in for new or merged datasets
# only perform check if no hashing in proforma to ensure correct checking as GG8d can be duplicated

if ($hash_entries == 1) {

	my $object_status = get_object_status ('GG', $GG1g_list[0], $GG1e_list[0], $GG1f_list[0]);
	
	if ($object_status eq 'new' || $object_status eq 'merge') {
		
		for (my $i = 0; $i <= $#GG8d_list; $i++) {
		
		
			if (defined $GG8d_list[$i] && $GG8d_list[$i] ne '') {
			
					report ($file, "%s must NOT be filled in for a %s:\n!%s\n\n!%s\n!%s", 'GG8d', ($object_status eq 'new' ? "$object_status gene group" : "gene group $object_status"),  $proforma_fields{'GG1a'}, $dup_proforma_fields{'GG8a'}[$i], $dup_proforma_fields{'GG8d'}[$i]);
				
			}
		
		}
	}
}


# GG7a must not contain the same gene group as in GG1a
compare_multiple_line_fields_negative($file, $hash_entries, 'GG1a', $primary_symbol_list, 'GG7a', \@GG7a_list, \%proforma_fields);
# GG7a must not contain the same gene group as in GG1a
compare_multiple_line_fields_negative($file, $hash_entries, 'GG1a', $primary_symbol_list, 'GG7c', \@GG7c_list, \%proforma_fields);
# GG7a and GG7c must not contain the same gene group
compare_multiple_line_fields_negative($file, $hash_entries, 'GG7a', \@GG7a_list, 'GG7c', \@GG7c_list, \%proforma_fields);

# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#GG1b_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'GG1a', $primary_symbol_list, 'GG1b', \@GG1b_list, \%proforma_fields, "You must include the valid symbol in GG1b when \!c-ing it under the 'unnattributed' publication.");

}


# check that GG14 is attributed to the correct reference when it is filled in

for (my $i = 0; $i < $hash_entries; $i++) {

	if ($GG14_list[$i] && $GG14_list[$i] ne '') {

		unless ($g_FBrf eq 'FBrf0225556') {

			report ($file, "%s data is usually attributed to the FBrf0225556 reference but P22 specifies '%s'.", 'GG14', $g_FBrf ? $g_FBrf : ($unattributed ? 'unattributed' : 'new'));
		}
	}


}

### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of this subroutine

    $want_next = $fsm{'GENEGROUP'};
}



sub validate_GG1h 
{

# copied from validate_G1h and tweaked slightly - eventually should replace several similar subroutines in
# individual proforma .pl files with generic subroutine in tools.pl, so used generic names
# for variables here, to make that easier in the future.
# Data is either a single FBid or empty.  It must be present for author-curated proformae.
# Issue a warning if it is present in other proforma types.

    my ($code, $change, $FBids) = @_;
    $FBids = trim_space_from_ends ($file, $code, $FBids);

    if (valid_symbol ($file, 'curator_type') eq 'USER' || valid_symbol ($file, 'curator_type') eq 'AUTO')
    {
	$FBids eq '' and report ($file, "%s: %s-curated proformae must have data.", $code,valid_symbol ($file, 'curator_type'));
    }
    else
    {
	$FBids eq '' or report ($file, "%s: Curators don't usually fill in the FBid field.  " .
				"Are you sure you want to for:\n!%s?", $code, $proforma_fields{$code});
    }
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});

	single_line ($file, $code, $FBids, $proforma_fields{$code}) or return;

# can't use generic symbol here as refers to a global variable
    @FBid_list = FBid_list_check ($file, $code, 'FBgg', $hash_entries, $FBids);

# More tests at the post-check phase.
}


1;				# Standard boilerplate.
