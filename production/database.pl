# Code to parse DATABASE proformae

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
my @inclusion_essential = qw (DB1a DB1g);			# Fields which must be present in the proforma
my %can_dup = (
	       );		# Fields which may be duplicated in a proforma.


# hashing is not allowed in database proforma. Have $hash_entries set to 1 so that can re-use
# code containing dehash for database field checking.  Will also have the useful side-effect
# of reporting any fields in database.pro that do contain hashes
my $hash_entries = 1;


my $primary_symbol_list;				# Dehashed data from primary proforma field (e.g. G1a, MA1a etc)

sub do_database_proforma ($$)
{
# Process a DATABASE proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The primary proforma field (that which contains the valid symbol) defines the number of expected symbols in a hash list.

    $proforma =~ /!.? DB1a\..*? :(.*)/;		# Get data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in primary proforma field
    }

    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;



# variables to store values for checking between fields.  Only needed within a single proforma, so
# within the do_publication_proforma subroutine, no need to declare at the top of the file.
# can use scalar variable and not array since hash_entries is forced to be 1 in publication
# proforma.  When populate the variable using process_field_data, have to use list context
# as follows, since process_field_data returns an array.
# ($P30_list) = process_field_data ($file, $hash_entries, $1, ($g_FBrf ? '1' : '0'), $2, $3, \%proforma_fields, '0');

	my $DB1g = '';
	my $DB2a = '';
	my $DB2b = '';
	my $DB3a = '';
	my $DB3b = '';
	my $DB3c = '';
	my $DB3d = '';
	
FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(DB1a)\..*? :(.*)/s)
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
			$want_next = $fsm{'DATABASE'};
			return;
		}

		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

	}
	
	elsif ($field =~ /^(.*?)\s+(DB1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		contains_data ($file, $2, $3, $proforma_fields{$2});
		($DB1g) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(DB2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($DB2a) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(DB2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($DB2b) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(DB3a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($DB3a) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(DB3c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($DB3c) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(DB3b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($DB3b) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(DB3d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		($DB3d) = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
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

	elsif ($field =~ /^(.*?)\s+DB(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*DB.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in database.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

	compare_pairs_of_data ($file, 'DB2b', $DB2b, 'DB2a', $DB2a, \%proforma_fields, 'dependent', '');
	compare_pairs_of_data ($file, 'DB3c', $DB3c, 'DB3a', $DB3a, \%proforma_fields, 'dependent', '');
	compare_pairs_of_data ($file, 'DB3d', $DB3d, 'DB3b', $DB3b, \%proforma_fields, 'dependent', '');



# cross check DB1a and DB1g - not used cross_check_1a_1g at the moment as I think it has
# a small bug in it (DC-661).

	my $object_status;
	
	
	if (defined $DB1g && $DB1g ne '') {
	
		if (my @g_list = check_y_or_n ($file, "DB1g", $hash_entries, $DB1g)) {

			for (my $i = 0; $i <= $#g_list; $i++) {

				my $chado_validity = valid_symbol ($primary_symbol_list->[$i], 'chado database name');

				if ($g_list[$i]) {

					if ($chado_validity) {
						$object_status = 'existing';
					} else {
						report ($file, "DB1g claims that the following database name exists in Chado, but Chado has never heard of it:\n!%s\n!%s", $proforma_fields{'DB1a'}, $proforma_fields{'DB1g'});
					}

				} else {

					unless ($chado_validity) {
						$object_status = 'new';
						
# as it is new, check DB1a within field format here
						check_allowed_characters($file,'DB1a',$primary_symbol_list->[$i],$proforma_fields{'DB1a'});						
					} else {
						report ($file, "DB1g claims that the following database is new, but it already exists:\n!%s\n!%s", $proforma_fields{'DB1a'}, $proforma_fields{'DB1g'});
					}
				}

			}
		}
	}

 # only go on to perform further checks if $object_status successfully set above as that means that the primary fields have passed their cross-checks.

	if ($object_status) {

# cross-check against what is already in chado

# DB2a

	check_changes_with_chado ($file, 'DB2a', ($DB2b ? "1" : "0"), 'DB2a', 'database description', chat_to_chado ('chado database description', $primary_symbol_list->[-1]), $DB2a);

# DB3a
	check_changes_with_chado ($file, 'DB3a', ($DB3c ? "1" : "0"), 'DB3a', 'database url', chat_to_chado ('chado database url', $primary_symbol_list->[-1]), $DB3a);

# DB3b
	check_changes_with_chado ($file, 'DB3b', ($DB3d ? "1" : "0"), 'DB3b', 'database urlprefix', chat_to_chado ('chado database urlprefix', $primary_symbol_list->[-1]), $DB3b);

	}

### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of the do proforma subroutine

    $want_next = $fsm{'DATABASE'};
}

### add any proforma field-specific subroutines here (or better still add to or use
### generic subroutines in tools.pl





1;				# Standard boilerplate.
