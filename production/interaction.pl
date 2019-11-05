# Code to parse interaction proformae

use strict;
# A set of global variables for communicating between different proformae.

our (%fsm, $want_next); # Global variables for finite state machine (defines what proforma expected next)
our ($chado, %prepared_queries); # Global variables for communication with Chado.
our %x1a_symbols;						# Hash for detecting duplicate proformae in a record
our $g_FBrf;							# Publication ID from P22 (if valid FBrf number)

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl,

our $standard_symbol_mapping;

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (IN1f IN1d IN2a IN2b IN3 IN6);			# Fields which must be present in the proforma
my %can_dup = (
	       );		# Fields which may be duplicated in a proforma.

# These two variables need to be declared here (and not within do_interaction_proforma)
# if there are any field-specific subroutines (at the bottom of this file) for this particular proforma.
my $hash_entries;						# Number of elements in hash list.
my @primary_symbol_list;				# Dehashed data from primary proforma field (e.g. G1a, MA1a etc)



sub do_interaction_proforma ($$)
{
# Process a interaction proforma, the text of which is in the second argument, which has been read from the file
# named in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();

# The primary proforma field (that which contains the valid symbol) defines the number of expected symbols in a hash list.

    $proforma =~ /!.? IN1f\..*? :(.*)/;		# Get data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count number of symbols in primary proforma field
    }

    @primary_symbol_list = ('Missing_primary_symbol_data');	# Set a default so that other checks don't fail with undef value.

	$change_count = 0;

# clear out the variables at the start of each proforma, so that they are cleared out
# even if the corresponding proforma field is omitted.

    my $IN1d_data = '';			# The y/n data found in IN1d.  Following same pattern as for cambridge proformae



# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
# since they are only required within  the do_interaction_proforma subroutine,
# no need to declare at the top of the file. e.g.
#	my @MA4_list = ();
#   etc.

	my @IN1d_list = ();
	my $IN6_symbol_list;
	my @IN6_list = ();
	my @IN7c_list = ();
	my @IN7d_list = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?)\s+(IN1f)\..*? :(.*)/s)
	{
	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $code, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);

# basic checks of primary symbol field format (must contain data and must be a single line) - now uses 'contains_data' and 'single_line' subroutines.
# Note that this basic format check for the primary symbol field is set up differently for the gene and aberration proformae compared to other proformae.
# For gene and aberration proformae - the two checks are within the 'validate_field' subroutine, which means that if
# either check fails, the rest of the proforma is still checked.
# For other proformae, the two checks occur in the loop where the field is identified, ie. before the 'validate_field' subroutine is called.  This means that if either check fails and the 'or return' is tripped, the rest of the proforma fields are not checked.
# I suspect that the difference is deliberate and is because the gene and aberration proformae are the only 'parent' proformae - those proformae which other proformae (allele and balancer respectively) can hang off. So even though I have changed the code to use the generic 'contains_data' and 'single_line' subroutines I have kept the different set up, as I suspect it is important, although I haven't figured out exactly why yet (I wonder if it might be to ensure that the child proformae are still processed if the parent one fails these basic primary symbol field format checks ??). [gm140226].


		contains_data ($file, $code, $data, $proforma_fields{$code}) or return;
		single_line ($file, $code, $data, $proforma_fields{$code}) or return;

# check that FBrf is a valid FBrf as can only fill in this proforma for existing FBrfs

	unless (valid_symbol ($g_FBrf, 'FBrf')) {
		report ($file, "%s: You cannot use an interaction proforma for a new publication:\n!%s", $code, $proforma_fields{$code});
		return;
	}


		@primary_symbol_list = validate_IN1f ($file, $code, $change, $hash_entries, $data, $proforma_fields{$code});

	}
	
	elsif ($field =~ /^(.*?)\s+(IN1d)\..*? :(.*)/s)
	{
		# do not need to call check_non_utf8, check_non_ascii as long as use process_field_data
		# do not need to call double_query here as long as use process_field_data
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		$IN1d_data = $3; # for now, keeping $IN1d_data (not dehashed) as well as storing @IN1d_list (dehashed), until worked out whether its safe/desirable to change existing code to use dehashed @IN1d_list version [gm160520 - following same pattern as for cambridge proformae] 

		unless (double_query ($file, $2, $3)) {
			@IN1d_list = validate_x1g ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}

#		@IN1d_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
		elsif ($field =~ /^(.*?)\s+(IN1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(IN2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		contains_data ($file, $2, $3, $proforma_fields{$2}) and process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(IN2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		contains_data ($file, $2, $3, $proforma_fields{$2}) and process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(IN3)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		contains_data ($file, $2, $3, $proforma_fields{$2}) and process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}	
	elsif ($field =~ /^(.*?)\s+(IN4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN5a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(IN5b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
# can't convert TAP_check to process_field_data format as also used to check F9 where cross-checks are required using *part*
# of the F9 field
		changes ($file, $2, $1) and report ($file, "%s: Can't use !c in this field:\n!%s", $2, $proforma_fields{$3});
		check_non_utf8 ($file, $2, $3);
		double_query ($file, $2, $3) or TAP_check ($file, $2, $3);

	}
	elsif ($field =~ /^(.*?)\s+(IN5d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN5e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN6)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@IN6_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN7b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN7c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@IN7c_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN7d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@IN7d_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN8a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(IN8b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

# fields that are in the master proforma, but for which proforma parsing has not yet
# been implemented - issues a warning if the field is filled in, or plingc-ed
# ideally there should not be any of these fields (would be better to only add them to
# the master proforma once proforma parsing is implemented).
	elsif ($field =~ /^(.*?)\s+(IN1c|IN1g|IN1i|IN7a)\..*? :(.*)/s)
	{
		changes ($file, $2, $1) and report ($file, "%s: WARNING: this field cannot be !c-ed as parsing of this field is not implemented in proforma loading software. Consult Kathleen for how to proceed if you really need to correct data of this type.", $2);

		if (defined $3 && $3 ne '') {

			report ($file, "%s: WARNING: this field cannot be filled in (you have '%s') as parsing of this field is not implemented in proforma loading software. Consult Kathleen for how to proceed if you really need to use this field.", $2, $3);
		}
	}

# fields that are not checked at all yet - validate_stub used to prevent false-positive
# 'Invalid proforma field' message.  Remember to take field codes out of second set of ()
# if checking for the field is implemented.
#	elsif ($field =~ /^(.*?)\s+(??insert field code here??)\..*? :(.*)/s)
#	{
#		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, \@primary_symbol_list, $can_dup{$2} ? 1 : 0);
#	    check_non_utf8 ($file, $2, $3);
#	    check_non_ascii ($file, $2, $3);
#	    double_query ($file, $2, $3) or validate_stub ($file, $1, $2, $3);
#	}

	elsif ($field =~ /^(.*?)\s+IN(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*IN.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field  (message tripped in interaction.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

### Start of tests that can only be done after parsing the entire proforma. ###

    check_presence ($file, \%proforma_fields, \@inclusion_essential, \@primary_symbol_list);


    if ($hash_entries and exists $proforma_fields{'IN1d'})
    {
	cross_check_1a_1g ($file, 'IN', 'FBin', 'interaction', $hash_entries, $IN1d_data, \@primary_symbol_list);


    }

### Validity checking of IN6 field and generation of list of symbols in <symbol> slot
### of field - needed for subsequent cross-checks.

	$IN6_symbol_list = validate_IN6 ($file, $hash_entries, 'IN6', \@IN6_list, \%proforma_fields);

# Validity checking of IN7c and IN7d fields, and cross-checks with IN6 field.
# Validity checks are done here, rather than at point of process_field_data as
# the cross-checking needs to use *part* of each IN7[cd] line, so better to check
# validity (and get this part) at the same time as do cross-checks so only have
# to check field syntax once.

	validate_and_crosscheck_IN7cd ($file, $hash_entries, 'IN7c', \@IN7c_list, 'IN6', $IN6_symbol_list, \%proforma_fields);
	validate_and_crosscheck_IN7cd ($file, $hash_entries, 'IN7d', \@IN7d_list, 'IN6', $IN6_symbol_list, \%proforma_fields);
	


### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of the do proforma subroutine

    $want_next = $fsm{'INTERACTION'};
}

### add any proforma field-specific subroutines here (or better still add to or use
### generic subroutines in tools.pl


sub validate_and_crosscheck_IN7cd {

	my ($file, $num, $code, $data, $symbol_code, $symbol_data, $context) = @_;


	my %allowed_types = (
	
		'IN7c' => ['FBtr', 'FBpp'],
		'IN7d' => ['FBtr', 'FBpp'],


	);
	
	unless ($allowed_types{$code}) {
		report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\nvalidate_and_crosscheck_IN7d does not contain an entry in the allowed_types hash for the '%s' field, please fix.",$code,$code);
		return;
	}
		
	my $LINE_FORMAT =  {

	'IN7c' => '<link to> (.*?) <description> (.*?) <role> (.*?) <coordinates/seq> (.*?) <note>( (.*?))?',
	'IN7d' => '<link to> (.*?) <description> (.*?) <role> (.*?) <note>( (.*?))?',

	};

# only do check if the two fields have based the based process_field_data checks
# (including the correct number of hashes)

# only do the check if:
# a. there is some data in the field represented by $code (have to use $context->{$code}
# as even if the field is empty, these empty values get passed to be stored by process_field data)
# and
# b. that the data has been stored for checking (i.e. has passed basic process_field_data checks)
# using test for @{$data}

	if ($context->{$code} && @{$data}) {

		if ($#$data + 1 == $num) {

			for (my $i = 0; $i < $num; $i++) {
	
				my $uniqued_data = check_for_duplicated_lines($file,$code,$data->[$i],$context->{$code});

				foreach my $datum (keys %{$uniqued_data}) {
####
					my ($symbol, $description, $role, $seq, $note);
	
# check basic syntax according to what is allowed for each field
					my $format_error_message = $LINE_FORMAT->{$code};
					$format_error_message =~ s/\( \(\.\*\?\)\)\?//g;
					$format_error_message =~ s/\(\.\*\?\)//g;
	
					if ($code eq 'IN7c') {
						unless (($symbol, $description, $role, $seq, undef, $note) = ($datum =~ m|^$LINE_FORMAT->{$code}$|)) {
							report ($file, "%s: '%s' does not match basic '%s' format", $code, $datum, $format_error_message);						
							next;
						}
					}
	
	
					if ($code eq 'IN7d') {
						unless (($symbol, $description, $role, undef, $note) = ($datum =~ m|^$LINE_FORMAT->{$code}$|)) {
							report ($file, "%s: '%s' does not match basic '%s' format", $code, $datum, $format_error_message);						
							next;
						}
					}
					
# now check the individual sub-field values						
						
# check symbol			
					if (defined $symbol && $symbol ne '') {
						valid_symbol_of_list_of_types ($symbol, $allowed_types{$code}) or report ($file, "%s: Invalid symbol '%s' in the 'link to' sub-field of the following line (only symbols of type" . ($#{$allowed_types{$code}} > 0 ? "s" : '') . " '%s' are allowed):\n%s", $code, $symbol, (join ', ', @{$allowed_types{$code}}), $datum);

# cross-check that symbol appears in the list in IN6 - only carry out the check if the IN6 lines passed the basic format checks

						if ($#$symbol_data + 1 == $num) {
							unless (exists $symbol_data->[$i]->{$symbol}) {
								report ($file, "%s: symbol '%s' in the 'link to' sub-field of the following line does not appear in any symbol sub-field in %s:\n%s", $code, $symbol, $symbol_code, $datum);
							}
						} else {
								report ($file, "%s: WARNING: The '%s' field is either missing/has too many errors, so cross-checking of the 'link to' sub-field of the following line will not be carried out until the errors in %s are fixed:\n%s", $code, $symbol_code, $symbol_code, $datum);
						}

					} else {
						report ($file, "%s: 'link to' sub-field in the following line is empty - it must be filled in:\n%s", $code, $datum);						

					}
		

# check description
					if (defined $description && $description ne '') {
						check_allowed_characters($file,"${code}_description",$description,$datum);

					} else {
						report ($file, "%s: 'description' sub-field in the following line is empty - it must be filled in:\n%s", $code, $datum);						

					}

# check role - not implemented yet - will need to be different for IN7c vs IN7d

					if (defined $role && $role ne '') {

						if  (valid_symbol ($role, 'MI:default')) {

							unless (valid_symbol ($role, ($code . "_role_common"))) {

								report ($file, "%s: The PSI-MI term '%s' in the 'role' sub-field of the following line is not normally used in this field, are you sure you picked the correct term ?:\n%s", $code, $role, $datum);

							}

						} else {
							report ($file, "%s: invalid term '%s' in the 'role' sub-field of the following line (must be a valid PSI-MI term):\n%s", $code, $role, $datum);
						}
					} else {

						report ($file, "%s: 'role' sub-field in the following line is empty - it must be filled in:\n%s", $code, $datum);						

					}
					


# check note
					if (defined $note && $note ne '') {
						
# use trim_space_from_ends again to check for extra white space
						trim_space_from_ends($file,$code,$note);					
						check_stamps($file,$code,$note);
						
					}
						
# check coordination/seq sub-field - present in IN7c only
						
					if ($code eq 'IN7c') {

# check presence		
						if (defined $seq && $seq ne '') {
# check format - not implemented yet

						}
						

						
					}						
						

####					
				}


			}	
	
	
		}
		
	}
}


sub validate_IN6 {

	my ($file, $num, $code, $data, $context) = @_;

	my @allowed_types = ('FBtr', 'FBpp');

	my $symbol_data;

	my $LINE_FORMAT = '<symbol> (.*?) <ID_as_reported> (.*?) <role> (.*?) <qual\/note>( (.*?))?';

# only do check if the two fields have based the based process_field_data checks
# (including the correct number of hashes)

# only do the check if:
# a. there is some data in the field represented by $code (have to use $context->{$code}
# as even if the field is empty, these empty values get passed to be stored by process_field data)
# and
# b. that the data has been stored for checking (i.e. has passed basic process_field_data checks)
# using test for @{$data}

	if ($context->{$code} && @{$data}) {

		if ($#$data + 1 == $num) {

			for (my $i = 0; $i < $num; $i++) {
	
				my $uniqued_data = check_for_duplicated_lines($file,$code,$data->[$i],$context->{$code});

				foreach my $datum (keys %{$uniqued_data}) {
####
					my ($symbol, $synonym, $role, $note);
					
	
# check basic syntax according to what is allowed for each field
					my $format_error_message = $LINE_FORMAT;
					$format_error_message =~ s/\( \(\.\*\?\)\)\?//g;
					$format_error_message =~ s/\(\.\*\?\)//g;
	
					unless (($symbol, $synonym, $role, undef, $note) = ($datum =~ m|^$LINE_FORMAT$|)) {
						report ($file, "%s: '%s' does not match basic '%s' format", $code, $datum, $format_error_message);
						next;
					}
	
					
# now check the individual sub-field values						
						
# print error message if forgot to fill in one of the compulsory sub-field values that are common to both field

					if (defined $symbol && $symbol ne '') {

# check symbol validity			
						valid_symbol_of_list_of_types ($symbol, \@allowed_types) or report ($file, "%s: Invalid symbol '%s' in the 'link to' sub-field of the following line (only symbols of type" . ($#allowed_types > 0 ? "s" : '') . " '%s' are allowed):\n%s", $code, $symbol, (join ', ', @allowed_types), $datum);

# add symbol to list of symbols present in IN6					
						$symbol_data->[$i]->{$symbol}++;

					} else {
						report ($file, "%s: 'symbol' sub-field in the following line is empty - it must be filled in:\n%s", $code, $datum);						

					}

					if (defined $synonym && $synonym ne '') {

						trim_space_from_ends($file,$code,$synonym);

					} else {

						report ($file, "%s: 'ID_as_reported' sub-field in the following line is empty - it must be filled in:\n%s", $code, $datum);						

					}

					if (defined $role && $role ne '') {

						unless ((valid_symbol ($role, 'MI:experimental role')) || (valid_symbol ($role, 'MI:biological role'))) {
						
							report ($file, "%s: Invalid term '%s' in the 'role' sub-field of the following line (must be a valid PSI-MI term that is a child of either 'experimental role' or 'biological role'):\n%s", $code, $role, $datum);
						
						}
					} else {
						report ($file, "%s: 'role' sub-field in the following line is empty - it must be filled in:\n%s", $code, $datum);						

					}

# check note
					if ($note && $note ne '') {
						
# use trim_space_from_ends again to check for extra white space
						trim_space_from_ends($file,$code,$note);					
						check_stamps($file,$code,$note);
						
					}

####					
				}
			}
		}	
	}
	
# loop to ensure only returns data if all fields pass basic format checks
	if ($#$symbol_data + 1 == $num) {
		return $symbol_data;
	} else {
# if the basic format checks are not passed, this returns undef 
		return;
	}
}



sub validate_IN1f {
	my ($file, $code, $change, $num, $symbols, $context) = @_;

	my $symbol_type = $code;
	$symbol_type =~ s|[0-9]{1,}[a-z]{1,}$||;


	changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context);

	my @primary_symbol_list = ();					# Clear default

# Check for missing final hash element but carry on regardless so that subsequent tests stand a chance of
# giving useful reports for the other elements.

	if ($symbols =~ /\s*\#\s*$/) {
		report ($file, "%s: Trailing hash in list '%s'", $code, $symbols);
		$symbols =~ s/\s*\#\s*$//;				# Remove to avoid future errors from this cause.
	}

	foreach my $symbol (dehash ($file, $code, $num, $symbols)) {

		$symbol = trim_space_from_ends ($file, $code, $symbol);





		my ($interaction_pub, $interaction_number, $remainder);

		if (($interaction_pub, $interaction_number, $remainder) = ($symbol =~ /^([^-]{1,})\-([^.]{1,})\.(.+)$/)) {

# check that the FBrf part of symbol matches FBrf of publication proforma
			unless ($interaction_pub =~ m/^$g_FBrf/) {

			report ($file, "%s: The start of the interaction id '%s' does not match the FBrf '%s' given in P22", $code, $symbol, $g_FBrf);

			}
# check that second part is an integer
			unless ($interaction_number =~ m/^[1-9]{1}[0-9]{0,}$/) { 

				report ($file, "%s: '%s' in '%s' is not valid - only positive integers are allowed in this part of the interaction id.\n!%s", $code, $interaction_number, $symbol, $context);

			}

		} else {

			report ($file, "%s: Invalid interaction id format '%s':\n!%s", $code, $symbol, $context);

		}

# It's an error if the same insertion is given twice (in two dataset proformae) in a single curation record.

		exists $x1a_symbols{$code}{$symbol} and report ($file, "%s: Duplicate %s symbol '%s'", $code, $standard_symbol_mapping->{$symbol_type}->{'type'}, $symbol);
		$x1a_symbols{$code}{$symbol} = 1;
		push @primary_symbol_list, $symbol;				# Store symbol for posterity.


	}

	return @primary_symbol_list;
}

1;				# Standard boilerplate.
