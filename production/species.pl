# Code to parse SPECIES proformae

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
my @inclusion_essential = qw (SP1a SP1b SP1g);			# Fields which must be present in the proforma
my %can_dup = (
	       );		# Fields which may be duplicated in a proforma.

# These two variables need to be declared here (and not within do_species_proforma)
# if there are any field-specific subroutines (at the bottom of this file) for this particular proforma.

# hashing is not allowed in species proforma. Have $hash_entries set to 1 so that can re-use
# code containing dehash for species field checking.  Will also have the useful side-effect
# of reporting any fields in species.pro that do contain hashes
my $hash_entries = 1;

my $primary_symbol_list;				# Not actually populated in this proforma, but variable requireedso that subroutines set up for other proformae still work for this proforma.

sub do_species_proforma ($$)
{
# Process a species proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();


	unless (valid_symbol ('Where_running', '_Peeves_') eq 'Cambridge') {
		report ($file, "***WARNING: This record contains a species proforma.  Please do not submit this yourself, but submit this via camcur so that additional 'between record' checks can be performed as part of the epicycle process (this is to prevent potential clashes of species information getting into the database).");
	}

# The primary proforma field (that which contains the valid symbol) defines the number of expected symbols in a hash list.



    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value. Its not actually populated in this proforma, so this is just to set a value so that subroutines set up for other proformae still work for this proforma.


	$change_count = 0;



# variables to store values for checking between fields.  Only needed within a single proforma, so
# within the do_species_proforma subroutine, no need to declare at the top of the file.
# can use scalar variable and not array since hash_entries is forced to be 1 in species
# proforma.  When populate the variable using process_field_data, have to use list context
# as follows, since process_field_data returns an array.
# ($P30_list) = process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '0');

	my $SP1a = '';
	my $SP1b = '';
	my $SP1g = '';
	my $SP2 = '';
	my $SP3a = '';
	my $SP3b = '';
	my $SP4 = '';
	my $SP5 = '';
	my $SP6 = '';

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(SP1a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		contains_data ($file, $2, $3, $proforma_fields{$2});
		($SP1a) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(SP1b)\..*? :(.*)/s)
	{
		# do not need to call double_query here as long as use process_field_data
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		contains_data ($file, $2, $3, $proforma_fields{$2});
		($SP1b) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');

	}	
	elsif ($field =~ /^(.*?)\s+(SP1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		contains_data ($file, $2, $3, $proforma_fields{$2});
		($SP1g) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(SP2)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($SP2) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(SP3a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($SP3a) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(SP3b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($SP3b) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(SP4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($SP4) = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(SP5)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($SP5) = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(SP6)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($SP6) = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
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

	elsif ($field =~ /^(.*?)\s+SP(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*SP.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in species.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

# simpler tests that don't require cross-checking with SP1a, SP1b or SP1g

# test that the same species abbreviation has not been given more than once in the same curation record
	if (defined $SP2 && $SP2 ne '') {
		exists $x1a_symbols{"SP2"}{$SP2} and report ($file, "%s: Duplicate species abbreviation '%s' in same record", 'SP2', $SP2);
		$x1a_symbols{"SP2"}{$SP2} = 1;

	}


	compare_pairs_of_data ($file, 'SP3b', $SP3b, 'SP3a', $SP3a, \%proforma_fields, 'dependent', '');



# only perform the tests if both SP1a and SP1b passed the basic format checks
	if (defined $SP1a && $SP1a ne '' && defined $SP1b && $SP1b ne '') {	

# test that the same species+genus combination has not been given more than once in the same curation record

		exists $x1a_symbols{"SP1a+SP1b"}{"$SP1a" . ":::" . "$SP1b"} and report ($file, "Duplicate organism in same record:\n!%s\n!%s", $proforma_fields{'SP1a'}, $proforma_fields{'SP1b'});
		$x1a_symbols{"SP1a+SP1b"}{"$SP1a" . ":::" . "$SP1b"} = 1;


		my $object_status;

# first cross-check SP1a, SP1b and SP1g - store in my @g_list even though the number
# of elements will always be 1, so that the object status can be reliably set at the
# same time (it is not set if SP1g does not contain 'n' or 'y')
		if (defined $SP1g && $SP1g ne '') {

			if (my @g_list = check_y_or_n ($file, "SP1g", $hash_entries, $SP1g)) {

				for (my $i = 0; $i <= $#g_list; $i++) {

					my $chado_validity = valid_species ($SP1a, $SP1b, 'chado_full_species_validity');

					if ($g_list[$i]) {

						if ($chado_validity) {
							$object_status = 'existing';
						} else {
							report ($file, "SP1g claims that the following organism exists in Chado, but Chado has never heard of it:\n!%s\n!%s\n!%s", $proforma_fields{'SP1a'}, $proforma_fields{'SP1b'}, $proforma_fields{'SP1g'});
						}

					} else {

						unless ($chado_validity) {
							$object_status = 'new';
						} else {
							report ($file, "SP1g claims that the following organism is new, but it already exists:\n!%s\n!%s\n!%s", $proforma_fields{'SP1a'}, $proforma_fields{'SP1b'}, $proforma_fields{'SP1g'});
						}
					}

				}
			}
		}



# only go on to perform further checks if $object_status successfully set above as that means that the primary fields have passed their cross-checks.

		if ($object_status) {



# cross-check against what is already in chado for SP4 and then SP6 (quite a bit hacky, but unless modify
# process_field_data to return !c info in addition to everything else, can't be helped).
# Only do the test if the primary fields passed their cross-checks and SP4 and SP6 passed basic checks. 

			if (defined $SP4) {
				my $SP4_plingc = $proforma_fields{'SP4'};
				$SP4_plingc =~ s/^(.*?)\s+SP4\..*? :.*/$1/s;
				check_changes_with_chado ($file, 'SP4', (changes ($file, 'SP4', $SP4_plingc)), "$SP1a $SP1b", 'taxon ID', chat_to_chado ('chado_full_taxon', $SP1a, $SP1b), $SP4);
			}

			if (defined $SP6) {
				my $SP6_plingc = $proforma_fields{'SP6'};
				$SP6_plingc =~ s/^(.*?)\s+SP6\..*? :.*/$1/s;
				check_changes_with_chado ($file, 'SP6', (changes ($file, 'SP6', $SP6_plingc)), "$SP1a $SP1b", 'official database', chat_to_chado ('chado_full_official_db', $SP1a, $SP1b), $SP6);
			}

#### new organisms
			if ($object_status eq 'new') {

# cross-checks for SP2
				if (defined $SP2 && $SP2 ne '') {

					valid_symbol ($SP2, 'chado_species_abbreviation') and report ($file, "%s: '%s' cannot be added as an abbreviation for '%s %s' as it is already in Chado as an abbreviation for '%s'", 'SP2', $SP2, $SP1a, $SP1b, (valid_symbol ($SP2, 'chado_species_abbreviation')));

				} else {

					report ($file, "%s must be filled in for a new organism:\n!%s\n!%s", 'SP2', $proforma_fields{'SP1a'}, $proforma_fields{'SP1b'});

				}

# cross-checks for SP3

				(defined $SP3b && $SP3b ne '') and report ($file, "%s must NOT be filled in for a new organism:\n!%s\n!%s", 'SP3b', $proforma_fields{'SP1a'}, $proforma_fields{'SP1b'});


#### existing organisms

			} elsif ($object_status eq 'existing') {

# cross-checks for SP2
				if (defined $SP2 && $SP2 ne '') {

					if (my $chado_abbreviation = valid_species ($SP1a, $SP1b, 'chado_full_species_abbreviation')) {

						if ($chado_abbreviation eq $SP2) {

							report ($file, "%s: Must not be filled in with '%s' as '%s %s' already has this as its valid abbreviation in chado.", 'SP2', $SP2, $SP1a, $SP1b);

						} else {

							report ($file, "%s: is filled in with '%s' but '%s %s' has '%s' as its valid abbreviation in chado.  Changing a species abbrevation cannot be done via proforma, remove the entry from SP2 and consult Hardev if this is what you were trying to do.", 'SP2', $SP2, $SP1a, $SP1b, $chado_abbreviation);

						}



					} else {

						valid_symbol ($SP2, 'chado_species_abbreviation') and report ($file, "%s: '%s' cannot be added as an abbreviation for '%s %s' as it is already in Chado as an abbreviation for '%s'", 'SP2', $SP2, $SP1a, $SP1b, (valid_symbol ($SP2, 'chado_species_abbreviation')));


					}

				}

# cross-checks for SP3
				if (defined $SP3a && $SP3a ne '') {

					check_changes_with_chado ($file, 'SP3a', ($SP3b ? "1" : "0"), "$SP1a $SP1b", 'common name', chat_to_chado ('chado_full_common_name', $SP1a, $SP1b), $SP3a);
#					(defined $SP3b && $SP3b ne '') or report "";



				}
			}
		}


	}

### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of the do proforma subroutine

    $want_next = $fsm{'SPECIES'};
}

### add any proforma field-specific subroutines here (or better still add to or use
### generic subroutines in tools.pl






1;				# Standard boilerplate.
