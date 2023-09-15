# Sundry little self-contained utility routines.

use strict;


our $standard_symbol_mapping;
our $change_count;
our %field_specific_checks;
our %x1a_symbols;						# Hash for detecting duplicate proformae in a record

our $g_FBrf;			# Publication ID

# First few tables and routines to perform low-level character munging.  If a non-UTF-8 character is found,
# it's almost always because the Latin-1 character set has been used.  Set up a look-up table and a function
# to look for such characters and issue an appropriate warning.

my @latin1_to_utf8;
for (my $i=0x80; $i<0x100; $i++)
{
    my ($hi, $lo) = (($i & 0xe0)>>6, $i & 0x3f);
    $latin1_to_utf8[$i] = chr(0xc0|$hi) . chr (0x80|$lo);
}

sub check_non_utf8 ($$$)
{
    my ($file, $code, $data) = @_;
    $data =~ /[\x80-\xff]/ or return;				# Cheap test for usual case.
    my @words = split /\s+/, $data;

    foreach my $word (@words)
    {
	my $badchars = $word;
	$badchars =~ s/(?:[\x00-\x7f] |
		    [\xc0-\xdf][\x80-\xbf] |
		    [\xe0-\xef][\x80-\xbf]{2}|
		    [\xf0-\xf7][\x80-\xbf]{3})+//gx;		# Remove all valid UTF-8 characters.
	foreach (split '', $badchars) 
	{
	    report ($file, "%s: Bad UTF-8 character '%s' (%d decimal, %x hex) in '%s'\nUse %s instead.",
		    $code, $_, ord($_), ord($_), $word, $latin1_to_utf8[ord($_)]);

# Under some circumstances (it was found with a o-umlaut in MP2a) the data goes on to be used in a chado query
# which then kills the process.  For safety's sake, remove the UTF-8 character to prevent this unfortunate
# occurrence?

#     $_[2] =~ s/$_/$latin1_to_utf8[ord($_)]/g;
	}
    }
}

# Then handle Greeks in their FlyBase entity form.

my %greek = (                           # Greek alphabet lookup table.
             '&Agr;'  => 'Alpha',   '&Bgr;'  => 'Beta',  '&Ggr;'  => 'Gamma',   '&Dgr;'  => 'Delta',
             '&Egr;'  => 'Epsilon', '&Zgr;'  => 'Zeta',  '&EEgr;' => 'Eta',     '&THgr;' => 'Theta',
             '&Igr;'  => 'Iota',    '&Kgr;'  => 'Kappa', '&Lgr;'  => 'Lambda',  '&Mgr;'  => 'Mu',
             '&Ngr;'  => 'Nu',      '&Xgr;'  => 'Xi',    '&Ogr;'  => 'Omicron', '&Pgr;'  => 'Pi',
             '&Rgr;'  => 'Rho',     '&Sgr;'  => 'Sigma', '&Tgr;'  => 'Tau',     '&Ugr;'  => 'Upsilon',
             '&PHgr;' => 'Phi',     '&KHgr;' => 'Chi',   '&PSgr;' => 'Psi',     '&OHgr;' => 'Omega',
             '&agr;'  => 'alpha',   '&bgr;'  => 'beta',  '&ggr;'  => 'gamma',   '&dgr;'  => 'delta',
             '&egr;'  => 'epsilon', '&zgr;'  => 'zeta',  '&eegr;' => 'eta',     '&thgr;' => 'theta',
             '&igr;'  => 'iota',    '&kgr;'  => 'kappa', '&lgr;'  => 'lambda',  '&mgr;'  => 'mu',
             '&ngr;'  => 'nu',      '&xgr;'  => 'xi',    '&ogr;'  => 'omicron', '&pgr;'  => 'pi',
             '&rgr;'  => 'rho',     '&sgr;'  => 'sigma', '&tgr;'  => 'tau',     '&ugr;'  => 'upsilon',
             '&phgr;' => 'phi',     '&khgr;' => 'chi',   '&psgr;' => 'psi',     '&ohgr;' => 'omega',
             '&cap;' => 'INTERSECTION', # not technically a greek symbol, but added here so that the valid_greek check in the validate_primary_proforma_field sub does not issue a false-positive for FBco
             );

sub valid_greek ($)
{
    return exists ($greek{$_[0]});
}

# no longer used, but keeping just in case
sub spell_greek ($)	# Spell out Greek letters to cope with ludicrous restriction on names in Chado.
{
    my $text = $_[0];
    #if($text){ # get rid of warning... May be something to do with loading ontologies? called by set_symbol in symtab.pl
    $text =~ s/(&[a-z]{1,2}gr;)/$greek{$1}?"$greek{$1}":"$1"/egi;
    #}
    return $text;
}

sub report (@)
{
# Report an error, etc.  This one is very simple but is implemented as a separate sub so that if the reporting
# mechanism changes only this sub needs changing and not every report splattered throughout Peeves.

# Debugging    print STDERR 'report (', join ("+++\n+++", @_), ")\n";

    my $file = shift or warn 'report without $file' and return;
    my $fmt = shift  or warn 'report without $fmt' and  return;
    our $report_text .= sprintf ('%s: ', $file);
    #if(scalar @_){# if any contents other than file and fmt (fudge due to sprintf trying to format nothing)
    	$report_text .= sprintf ($fmt, @_) . "\n\n";
    our $clean_record = 0;					# Found something wrong with the record.
    our $num_reports++;
    #}
}

sub validate_stub {	
# Use this general subroutine to perform some very basic checks for a field
# and to indicate that Peeves does not yet check the field in detail.
	my ($file, $change, $code, $data) = @_;
	
	changes ($file, $code, $change);

# get rid of any lines that just contain returns, as probably mostly harmless	
	$data = silent_trim_space($data);

	if (defined $data && $data ne '') {
# check for basic errors in character formatting		
		check_non_utf8 ($file, $code, $data);
		check_non_ascii ($file, $code, $data);
#check for ??
		double_query ($file, $code, $data);
# warn that only 'stub' checking is carried out
		warn "$file: checking not implemented for $code, so '$data' has not been checked for validity\n";
#	$_[3] and report ($file, "$code. Warning: I don't yet know how to deal with the '%s' proforma field.", $code);
	}
}


sub summarize_files ($$)
{
# The first argument is a reference to a list of filenames.  The second is a message to be printed out.  It
# summarizes some characteristic of the files and must match the pattern "(hese files.*?){1,1}".

    my ($file_ref, $message) = @_;
    my @files = @{$file_ref};					# Syntactic sugar.	

    defined $files[0] or return '';				# Do nothing if no filenames.
    $message = "\n" . $message;					# Prepend newline for clarity

    if ($#files)						# More than one filename
    {
	my $file_list = join ("\t", sort @files);		# TSV list
	$file_list =~ s/((.*?\t){9}.*?)\t/$1\n/g;		# Up to ten filenames per line.
	$message =~ s/hese files/hese %d files/;		# Report number in list
	$message .= ":\n\n%s\n";				# Append filenames
	return sprintf ($message, $#files+1, $file_list);	# Build report and return.
    }
    else							# Precisely one filename
    {
	$message =~ s/hese files/his file/;			# Convert to singular
	$message .= ":\t%s\n";					# Append filename
	return sprintf ($message, $files[0]);			# Build report and return.
    }
}

sub double_query ($$$)
{
# If the data in the third argument contains a '??' sequence, the curator is flagging that the field should
# not be checked.  In this case, report the presence of '?? and return a true value to the proforma field
# checking code; otherwise silently return zero.

    my ($file, $code, $data) = @_;
    defined $data and $data =~ /\?\?/ or return 0;
    unless (our $qq){report ($file, "%s: Not checking this field because of ?? in '%s'" , $code, $data);}
    return 1;
}

sub check_dups {
# Store proforma data to provide context for error messages and check for fields duplicated in error.
# Data is stored in two ways, depending on whether the field is allowed to be duplicated within a proforma.
# 
# The first argument is the name of the proforma file.
# The second is the proforma code.
# The third is the entire proforma field, including the proforma field text.
# The fourth is a hash reference which contains the latest entry seen for each code (storing the entire proforma field).
# This is used to provide context for error messages.  It should be used for field-specific checks carried out as
# part of process_field_data.  It can also be used for checks carried out once the entire proforma is parsed,
# but ONLY for fields which cannot be duplicated within a proforma, since for fields which can be
# duplicated within a proforma it is not the complete picture.
# The fifth is a hash reference which keeps track of the complete picture for fields which can be duplicated within a proforma.
# This should be used to provide the correct context for checks on these fields which are carried out once the entire proforma
# is parsed, as it stores each entry seen for each 'dup for multiple' code.
# The sixth is a reference to the array containing data from the primary symbol field.
# The seventh indicates whether a field can be duplicated within a proforma (1) or not (0).

	my ($file, $code, $entire_field, $seen, $duplicated_field_seen, $symbol_context, $can_dup) = @_;

	if ($can_dup) {

		push @{$duplicated_field_seen->{$code}}, $entire_field;

	} else {

		if (exists $seen->{$code}) {
			my $symbol_context_message = '';
			if (defined $symbol_context->[0]) {
				$symbol_context_message = "  If it helps,the previous G1a, GA1a, A1a or AB1a contained '" . join (' # ', @{$symbol_context}) . "'\n";
			}
			report ($file, "Found another %s.  An earlier one had\n'%s'\n" . "and this one has\n'%s'\nContinuing to validate, using this one.%s", $code, $seen->{$code}, $entire_field, $symbol_context_message);
		}
	}

# always put the field data into the hash reference that keeps track of the latest instance of a particular field
	$seen->{$code} = $entire_field;

}

sub check_presence ($$$$)
{
# Enforce the rule that some proforma fields must be present in a proforma.
# The first argument is the name of the proforma file.
# The second is a hash reference, used to keep track of what has been seen so far.
# The third is a reference to a list of the obligatory proforma codes.
# The fourth is an arrayref which, if it contains any data, will be the symbols in the most recent
# G1a, GA1a or A1a

    my ($file, $seen, @needed, $context) = ($_[0], $_[1], @{$_[2]});
    foreach my $code (@needed)
    {
	exists $seen->{$code} or report ($file, 'Required proforma field %s missing or malformed.', $code);
    }
    my $context_message = '';
    if (defined $context->[0])
    {
	$context_message = "  If it helps,the previous G1a, GA1a, A1a or AB1a contained '" .
	    join (' # ', @{$context}) . "'\n";
	}
}

sub trim_space_from_ends ($$$)
{
    my ($file, $code, $string) = @_;	# Consider using $_ directly to avoid data copying.

    defined $string or return '';	# Always return a valid string, even with undef input.
    if ($string =~ /^\s+/)
    {
	#report ($file, "%s: superfluous leading whitespace in '%s'", $code, $string);
	$string =~ s/^\s+//;
    }
    if ($string =~ /\s+$/)
    {
	#report ($file, "%s: superfluous trailing whitespace in '%s'", $code, $string);
	$string =~ s/\s+$//;
    }
    return $string;
}

sub silent_trim_space {

# copied from trim subroutine in proforma parsing software
	my @s = @_;
    for (@s) {s/^\s+//; s/\s+$//;}
    return wantarray ? @s : $s[0];

}

sub trim_leading_return {
# take care when using this subroutine - it should only be used for fields where it is safe to remove
# a leading return (and where curators are in the habit of adding that leading return) to prevent
# unecessary error messages.
    my ($code, $string) = @_;	# Consider using $_ directly to avoid data copying.

    defined $string or return '';	# Always return a valid string, even with undef input.

	$string =~ s/^\n//;
    return $string;
}

sub changes ($$$) # pling c (!c)
{

# The standard way to call this if a field can have !c is:
# changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
# The standard way to call this if a field must not have !c is:
# changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});


    my ($file, $code, $change) = @_;

    return 0 unless defined $change and $change ne '';	# No change character.
 
	if ($change eq 'c') { # A change character after the !
		$change_count++;
		return 1;
	}
    
    report ($file, "%s: Junk (%s) found between ! and %s.", $code, $change, $code);
    return 0;
}

sub non_numeric ($$$)
{
    my ($file, $code, $data) = @_;

    return 1 if (!defined $data or $data eq '');	# No data, so definitely non-numeric, but not an error per se.
    return 0 if $data =~ /^\d+$/;			# A sequence of digits is the only kind of number recognized.

    report ($file, "%s: Non-numeric data '%s'", $code, $data);
    return 1;
}

sub dehash ($$$$)
{
# Split a hash list into a list of separate objects.  If the hash list has only one element, replicate it to
# the number required.  If the correct number of elements is not found, return an empty list.  Note this is
# distinguishable from the case where the hash list itself is undef and only one element is required.  In that
# case, a list containing a single undef element is returned.

# Arguments are filename of proforma being parsed, the proforma field code being checked, the number of
# elements required and the data for that field.

    my ($file, $code, $num, $data) = @_;
    if ($data =~ /\s*\#\s*$/)
    {
	report ($file, "%s: Trailing hash in list '%s' so not unhashing this list: please fix and retest", $code, $data);
	return ();
    }
    $data =~ / \# / or return ($data) x $num;		# Elements are separated by ' # '. If only one item, return it (replicated to the number of elements required (defined by $num))
    my @list = split (/ \# /, $data);
    return @list if $#list+1 == $num;			# All ok.
    report ($file, "%s: Wrong number of entries in hash list '%s': please fix and retest.  Found %d, expected %d.",
	    $code, $data, $#list+1, $num);
    return ();
}

sub check_y_or_n ($$$$)
{

# Enforce a response of 'y' or 'n' for those proformae fields that require it.  Return a list containing zero
# values where 'n' appears in the hashed list and +1 for 'y'.  Return an empty list for no data, if the list
# does not have the correct number of entries, or if the list contains anything but 'y' or 'n'.  Report error
# conditions.

# Arguments are filename of proforma being parsed, the proforma field code being checked, the number of
# elements required and the data for that field.

    return () if (!defined $_[3] or $_[3] eq '');
    return (1) x $_[2] if $_[3] eq 'y';				# Very common and easy cases dealt with first
    return (0) x $_[2] if $_[3] eq 'n';

    my ($file, $code, $num, $data) = @_;

    unless ($data =~ /^[yn]( \# [yn])*$/)
    {
	report ($file, "%s: Bad value (%s) in y or n data.", $code, $data);
	return ();
    }
    $data =~ tr/yn//cd;				# Obliterate all but yn
    unless (length $data == $num)
    {
	report ($file, "%s: Wrong number of entries in hash list.  Found %d, expected %d.", $code, length $data, $num);
	return ();
    }
    $data =~ tr/yn/10/;				# Convert yn to 10.
    return split ('', $data);
}

sub check_changes_with_chado ($$$$$@)
{
#  See whether a list of items in the proforma field is the same as that already stored in Chado, then give
#  reports if these values are not consistent with the use of !c.
#
# The first argument is the name of the curation record being validated.
# The second is the code for the proforma field.
# The third is 1 or 0 according to whether !c is being used or not.
# The fourth is the FBid of the object to be checked.
# The fifth is the name of the list of things to be checked.
# The sixth is the result of a chat_to_chado() which extracts a list of items to be checked against
# the seventh, which is the list of items given in the proforma field.
# Note, although this is apparently set up to work with multiple values, it currently does not
# since @new_list and @existing_list are not sorted.

    my ($file, $code, $change, $object, $list_name, $chado_list_ref, @new_list) = @_;
    my @existing_list = map $_->[0], @{$chado_list_ref};

# @existing_list must contain values and must be different from @new_list if $changes is set, and must be
# identical otherwise.  Omitting a value in @new_list is always acceptable.

    my $identical = defined $existing_list[0] &&
	defined $new_list[0] &&
	$#existing_list == $#new_list;	# Same number in lists?

    for (my $i = 0; $identical && $i <= $#new_list && $i <= $#existing_list; $i++)
    {
	$identical = ($new_list[$i] eq '') || ($existing_list[$i] eq $new_list[$i]);
    }
    if ($change)
    {
	unless (defined $existing_list[0]) # Nothing came back from the Chado query. This was originally 'if ($#existing_list == -1)' but it did not work.
	{
	    report ($file, "%s: Trying to change %s to '%s' but there is no %s data in Chado.",
		    $code, $list_name, join ("\n", @new_list), $list_name);
	}
	elsif ($identical)
	{
	    report ($file, "%s: Trying to change %s to the value (%s) it already has in Chado.",
		    $code, $list_name, join ("\n", @new_list));
	}
    }
    else
    {
	if (!$identical and defined $existing_list[0])
	{
	    report ($file, "%s: Trying to add the %s '%s' but it is already set to '%s' in Chado - were you trying to change the data using !c (or equivalent) ?",
		    $code, $list_name, join ("\n", @new_list), join ("\n", @existing_list));
	}
    }
}

sub must_be_dataless ($$$$)	# This proforma field must be blank and must not have !c to indicate a change.
{
    my ($file, $change, $code, $data) = @_;
    
    changes ($file, $code, $change) and report ($file, "%s: can't use !c in this field", $code);
    report ($file, "%s: Must not specify data, but you gave '%s'.", $code, $data) if defined $data and $data ne '';
}

sub no_stamps {
# process_field_data + %field_specific_checks format. 150315.
# We don't really care what the data is, as long as it does not contain stamps.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;
	
	report ($file, "%s: Unwanted stamp in '%s'", $code, $dehashed_data) if $dehashed_data =~ /@.*@/s;

}

sub check_stamps ($$$)
{
    return if index ($_[2], '@') == -1;			# No @ so no stamps possible.
    my ($file, $code, $data) = @_;

    if ($data =~ s/@/@/g % 2)				# Odd number of @ can't be right.
    {
	report ($file, "%s: Odd number of \@-characters in '%s'", $code, $data);
	return;
    }
    while ($data =~ /@(.*?)@/g)
    {
	if ($1 eq '')
	{
	    report ($file, "%s: Double-\@ in '%s'", $code, $data);
	}
	else
	{


# list of FlyBase types that can be used in @@ - tried to order them so that most likely types are checked first
# not included by might want to consider adding: FBgg
		my @allowed_types = ('FBgn', 'FBto', 'FBal', 'FBti', 'FBtp', 'FBab', 'FBba', 'FBte', 'FBmc', 'FBlc', 'FBcl', 'FBtr', 'FBpp', 'FBtc', 'FBco');
		valid_symbol_of_list_of_types ($1, \@allowed_types) or report ($file, "%s: Invalid stamp \@%s\@ in '%s'", $code, $1, $data);
	}
    }
}


sub check_stamps_with_ids {

# subroutine designed to check stamped free text where the @@ may contain either the standard
# @symbol@ format or the @FBid:symbol@ format (eg. in <note> of TAP statements in F9 for automatically
# generated proformae containing split-GAL4 expression data)

# has standard check_stamps logic, plus new elsif loop for checking @FBid:symbol@ format.
# includes 'allowed_types_for_id_symbol' hash argument, so that it can check that only symbols of the expected
# id types are included in the @FBid:symbol@ format, where appropriate


	return if index ($_[2], '@') == -1; # No @ so no stamps possible.
	my ($file, $code, $data, $allowed_types_for_id_symbol) = @_;

# Odd number of @ can't be right.
	if ($data =~ s/@/@/g % 2) {
		report ($file, "%s: Odd number of \@-characters in '%s'", $code, $data);
		return;
	}

	while ($data =~ /@(.*?)@/g) {
		if ($1 eq '') {
			report ($file, "%s: Double-\@ in '%s'", $code, $data);
# @@ that have the FBid:symbol format
		} elsif ($1 =~ m/^(FB[a-z]{2}[0-9]{7,}):(.*)$/) {

			my $FBid = $1;
			my $symbol = $2;

			my $id_type = $FBid;
			$id_type =~ s/\d+$//;		

# do the checks if either there is no limitation on FBid type, or if its of the type expected in the context
			if ((scalar keys %{$allowed_types_for_id_symbol} == 0) || exists $allowed_types_for_id_symbol->{$id_type}) {

				my $purported_symbol = valid_symbol ($FBid, 'uniquename'); # returns symbol if FBid is valid, 0 if not
				my $purported_id = valid_symbol ($symbol, $id_type);


# the following condition occurs when a symbol is newly-instantiated in a record
# (this includes brand new symbols or renames), so need to reset some of the variables
# so that the subsequent checking works -  copied logic from check_evidence_data sub
				if ($purported_id eq "good_$symbol") {

					if ($purported_symbol) {
						$purported_symbol = $symbol; # rename_case
						$purported_id = $FBid;
					} else {

						$purported_id = valid_chado_symbol ($symbol, $id_type); # invalid id case

					}
				}

#				warn "symbol: $symbol,  purported id: $purported_id, id: $FBid,purported symbol: $purported_symbol\n";

				if ($purported_symbol) {
					if ($purported_id) {
						unless ($symbol eq $purported_symbol && $FBid eq $purported_id) {
							report ($file, "%s: Mismatched FBid and symbol in '%s'\n'%s' is '%s' and '%s' is '%s'.", $code, $data, $FBid, $purported_symbol, $symbol, $purported_id);
						}
					} else {
						report ($file, "%s: Invalid symbol '%s' in '%s'", $code, $symbol, $data);
					}
				} else {
					if ($purported_id) {
						report ($file, "%s: Invalid FBid '%s' in '%s'", $code, $FBid, $data);
					} else {
						report ($file, "%s: Invalid FBid '%s' in '%s'", $code, $FBid, $data);
					}
				}

			} else {

				report ($file, "%s: FBid '%s' in '%s' is not allowed (only uniquenames of type" . (scalar keys %{$allowed_types_for_id_symbol} > 1 ? "s" : '') . " '%s' are allowed in this context).", $code, $FBid, $data, (join '\', \'', keys %{$allowed_types_for_id_symbol}));

			}

		} elsif ($1 =~ m/^(.*:FB[a-z]{2}[0-9]{7,})$/) {


			report ($file, "%s: FBid and symbol in \@%s\@ are the wrong way round in '%s' - correct format is \@FBid:symbol\@.", $code, $1, $data);

		} else {

			# list of FlyBase types that can be used in @@ - tried to order them so that most likely types are checked first
			# not included by might want to consider adding: FBgg
			my @allowed_types = ('FBgn', 'FBto', 'FBal', 'FBti', 'FBtp', 'FBab', 'FBba', 'FBte', 'FBmc', 'FBlc', 'FBcl', 'FBtr', 'FBpp', 'FBtc', 'FBco');
			valid_symbol_of_list_of_types ($1, \@allowed_types) or report ($file, "%s: Invalid stamp \@%s\@ in '%s'", $code, $1, $data);
		}
	}
}


sub check_stamped_free_text {
# converted to process_field_data + %field_specific_checks format. 150315.
# This is now really just a wrapper so that check_stamps can still be used
# to check parts of lines as well as whole lines. 

	my ($file, $code, $dehashed_data, $context) = @_;

# hash containing extra checks required for some fields, where it is easy to
# miss and put neighbouring CV data into a free text field
	my $extra_check_mapping = {

# key is field, value is regular expression to test for to see if put
# CV term field data from neighbouring field in free text field by mistake 
		'GA7a' => ' [|{] ',
		'GA28c' => ' [|{] ',
		'GA29c' => ' [|{] ',

		'GA22' => ' \{ |DOID:',

		'GA34b' => ' \| |DOID:',
		
		'GA12b' => '(^(?:Amino acid replacement: |Nucleotide substitution: |Tag:))|(DOID:)',

		'G28a' => '^(Source for identity of: | Source for merge of: )',
		'G27' => '^(Source for identity of: | Source for merge of: )',

	};


	$dehashed_data eq '' and return;

	check_stamps ($file, $code, $dehashed_data);

	if (exists $extra_check_mapping->{$code}) {

		if ($dehashed_data =~ m/($extra_check_mapping->{$code})/) {

			report ($file, "%s: has data containing '%s', did you miss and put data intended for a nearby CV field into this free text field by mistake ?:\n!%s", $code, $1, $context->{$code});

		}
	}

}


sub check_stamped_free_text_with_ids {

# wrapper for check_stamps_with_ids that uses process_field_data + %field_specific_checks format
# this makes it easy to check whole lines that contain stamps with ids (ie. @FBid:symbol@ format),
# while keeping check_stamps_with_ids as a separate subroutine that can be used to check parts of lines
# as needed (e.g. note part of F9 data).

	my ($file, $code, $dehashed_data, $context) = @_;

# hash containing extra checks required for some fields, where it is easy to
# miss and put neighbouring CV data into a free text field
# currently empty, but left in place in case we start to replace some
# check_stamped_free_text checks with check_stamped_free_text_with_ids checks.
	my $extra_check_mapping = {

# key is field, value is regular expression to test for to see if put
# CV term field data from neighbouring field in free text field by mistake 

	};


	$dehashed_data eq '' and return;

# hash that can be used to limit the expected type of object allowed in @FBid:symbol@ for a particular field
# only add a field if want to limit the allowed types for that field.
	my $allowed_types_for_field = {

# format should be as follows to limit allowed types
#		'field' => {
#			'FBid_prefix' => '1',
#		},
# e.g. (hypothetical example_
#		'TC9' => {
#			'FBgn' => '1',
#			'FBtc' => '1',
#		},


	};

	check_stamps_with_ids ($file, $code, $dehashed_data, $allowed_types_for_field->{$code});

	if (exists $extra_check_mapping->{$code}) {

		if ($dehashed_data =~ m/($extra_check_mapping->{$code})/) {

			report ($file, "%s: has data containing '%s', did you miss and put data intended for a nearby CV field into this free text field by mistake ?:\n!%s", $code, $1, $context->{$code});

		}
	}

}


my (undef, undef, undef, $today, $tomonth, $toyear) = localtime;	# For checking the date given for plausibility.
$toyear += 1900;		# Local time is based at 1900.
$tomonth++;			# Local time counts months from 0.
my @days_of_month = (undef, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

sub bad_date ($$$)
{
    my ($file, $code, $date) = @_;
    my ($year, $month, $day);

    if ($date =~ /^\d{4}$/)				# Just the year?  Ok for all but personal communications.
    {
	if ($date < 1990)				# Is 1990 a reasonable cut off?
	{
	    report ($file, "%s: Implausible date %s", $code, $date);
	    return 1;
	}
	if ($date > $toyear)
	{
	    report ($file, "%s: Date %s is in the future!", $code, $date);	# It's just a jump to the left ...
	    return 1;
	}
    }
    elsif (($year, $month) = ($date =~ /^(\d{4})\.(\d\d?)$/))
    {
	report ($file, "%s: Incomplete date specification %s", $code, $date);
	if ($year < 1990)					# Is 1990 a reasonable cut off?
	{
	    report ($file, "%s: Implausible year '%s' in %s", $code, $year, $date);
	    return 1;
	}
	if ($month =~ /^0/ or $month > 12)
	{
	    report ($file, "%s: Incorrect month '%s' in %s", $code, $month, $date);
	    return 1;
	}
    }
    elsif (($year, $month, $day) = ($date =~ /^(\d{4})\.(\d\d?)\.(\d\d?)$/))
    {
	if ($year < 1990)					# Is 1990 a reasonable cut off?
	{
	    report ($file, "%s: Implausible year '%s' in %s", $code, $year, $date);
	    return 1;
	}

	my $leap_year = ($year%4 == 0 and $month == 2);	# It breaks in 2100 but frankly, my dear, I don't give a damn.

	if ($month =~ /^0/ or $month > 12)
	{
	    report ($file, "%s: Incorrect month '%s' in %s", $code, $month, $date);
	    return 1;
	}
	if ($day =~ /^0/ or $day > $days_of_month [$month] + $leap_year)
	{
	    report ($file, "%s: Incorrect day of month '%s' in %s", $code, $day, $date);
	    return 1;
	}
	if (($year > $toyear) or
	    ($year == $toyear and $month > $tomonth) or
	    ($year == $toyear and $month == $tomonth and $day > $today))
	{
	    report ($file, "%s: Date %s is in the future!", $code, $date);	# It's just a jump to the left ...
	    return 1;
	}
    }
    else
    {
	report ($file, "%s: Incorrect date specification '%s'", $code, $date);
	return 1;
    }
    return 0;			# Successfully passed all tests.
}

sub bad_iso_date ($$$)
{
    my ($file, $code, $date) = @_;

    if (my ($year, $month, $day) = ($date =~ /^(\d{4})([01]\d)([0123]\d)$/))
    {
	if ($year < 1990)					# Is 1990 a reasonable cut off?
	{
	    report ($file, "%s: Implausible year '%s' in %s", $code, $year, $date);
	    return 1;
	}
	if ($month < 1 or $month > 12)
	{
	    report ($file, "%s: Incorrect month '%s' in %s", $code, $month, $date);
	    return 1;
	}
	my $leap_year = ($year%4 == 0 and $month == 2);	# It breaks in 2100 but frankly, my dear, I don't give a damn.
	if ($day < 1 or $day > $days_of_month [$month] + $leap_year)
	{
	    report ($file, "%s: Incorrect day of month '%s' in %s", $code, $day, $date);
	    return 1;
	}
	if (($year > $toyear) or
	    ($year == $toyear and $month > $tomonth) or
	    ($year == $toyear and $month == $tomonth and $day > $today))
	{
	    report ($file, "%s: Date %s is in the future!", $code, $date);	# It's just a jump to the left ...
	    return 1;
	}
    }
    else
    {
	report ($file, "%s: '%s' doesn't look like a date, which must have YYYYMMMDD format.", $code, $date);
	return 1;
    }
    return 0;			# Successfully passed all tests.
}

sub valid_isbn ($)
{
# return 1 if the argument appears to be a valid ISBN-10 or ISBN-13, 0 otherwise.

    my $isbn = $_[0];

    my @digits = split //, $isbn;	# Split the isbn into separate digits.
    my $check = pop @digits;		# Split off the checksum digit provided.

    if ($isbn =~ /^[0-9]{9}[0-9X]$/)
    {					# This is deep magic.  Go learn some coding theory to appreciate its beauty.
	$check eq 'X' and $check = 10;
	for (my $i = 0; $i < 9; $i++)
	{
	    $check -= ($i+1) * $digits[$i];
	}
	return $check % 11 == 0;
    }
    if ($isbn =~ /^[0-9]{13}$/)
    {					# This is differently deep magic.  You still need to learn coding theory.
	my $weight = 1;
	for (my $i = 0; $i < 12; $i++)
	{
	    $check += $weight * $digits[$i];
	    $weight = 4 - $weight;
	}
	return $check % 10 == 0;
    }
    return 0;
}

sub convert_to_ISBN13 ($)
{
# If the argument is a valid ISBN-10 or ISBN-13, return the corresponding ISBN-13.  Otherwise return zero
# (which is not a valid ISBN-13) to allow idioms such as "if convert_to_ISBN13($isbn) { ... }".

    my $isbn = $_[0];

    if (valid_isbn ($isbn))
    {
	return $isbn if length ($isbn) == 13;		# Already ISBN-13, so nothing to do.

	my ($weight, $check) = (1, 0);
	my @digits = (9, 7, 8, split (//, $isbn));	# Split ISBN-10 into digits and prepend the ISBN-13 prefix.
	pop @digits;					# Remove the ISBN-10 checksum.

	for (my $i = 0; $i < 12; $i++)			# Calculate the ISBN-13 checksum
	{
	    $check -= $weight * $digits[$i];
	    $weight = 4 - $weight;
	}
	return join ('', (@digits, $check % 10));	# Append the newly calculated check digit and return.
    }
    return 0;
}

sub valid_issn ($)
{
# return 1 if the argument appears to be a valid ISSN, 0 otherwise.

    my $issn = $_[0];
    return 0 unless $issn =~ /^([0-9]{4})-([0-9]{3}[0-9X])$/;

    my @digits = split //, $1 . $2;			# Snip out the '-' from the middle
    my $check = pop @digits;				# From here on the algorithm is very similar
    $check eq 'X' and $check = 10;			# to the ISBN-10 case (vid. sup.)
    for (my $i = 0; $i < 7; $i++)			# but with only 7 meaningful digits.
    {
	$check -= ($i+3) * $digits[$i];
    }
    return $check % 11 == 0;
}

sub check_languages ($$$$$$)
{
    my ($file, $code, $change, $ref, $language_list, $query) = @_;
    my @languages = split ("\n", $language_list);
    my $fail = 0;

    foreach my $language (@languages)
    {
	$language = trim_space_from_ends ($file, $code, $language);
	unless (valid_symbol ($language, 'FBcv:language'))
	{						# Wash your mouth out with soap, you naughty curator!
	    report ($file, "%s: Bad language '%s'", $code, $language);
	    $fail = 1;
	}
    }
    $fail and return;

# @languages is now plausible.

    if ($ref)
    {
	my $list_name = ($code eq 'P14' ? 'abstract ' : '');
	$list_name .= 'languages list';
	check_changes_with_chado ($file, $code, $change, $ref, $list_name,
				  chat_to_chado ($query, $ref), @languages);
    }
    else
    {
	$change and report ($file, "%s: Can't change the languages list of a new publication", $code);
    }
}

sub rename_merge_check {
# In any one proforma, an object may not be both renamed and merged.  Issue a warning if this condition is
# violated.
# $file = curation record
# $r_code = rename proforma field code
# $r_list = dehashed rename list
# $r_context = entire contents of 'rename' proforma field, including proforma field text, should be provided using %proforma_fields hash
# $m_code = merge proforma field code
# $m_list = dehashed merge list
# $m_context = entire contents of 'merge' proforma field, including proforma field text, should be provided using %proforma_fields hash

    my ($file, $r_code, $r_list, $r_context, $m_code, $m_list, $m_context) = @_;

	@$r_list and @$m_list and report ($file, "rename field (%s) and merge field (%s) must not both contain data:\n!%s\n!%s", $r_code, $m_code, $r_context, $m_context);

}

sub  FBid_list_check ($$$$$)
{
# Each proforma type has a field, such as G1h and MA1f, which may filled in with either the word 'new' or a
# FBid which must be a valid uniquename in Chado.  This function checks each value in a hash list and issues a
# report if the value does not pass the validity requirements.  Superfluous whitespace is removed and the
# cleaned value, whether valid or not, is returned in a list.
#
# The first argument is the name of the curation record being validated.
# The second is the code for the type of proforma (G1h, GA1h, ...).
# The third is the FBid-type of symbol being checked (FBgn, FBal, FBab, FBba, ...).
# The fourth is the hashlist of FBid or 'new' values.
# The fifth is the number of symbols expected to be in the hash list.

    my ($file, $code, $FBid_type, $hash_entries, $FBid_list) = @_;
    my @FBid_list = ();

    foreach my $FBid (dehash ($file, $code, $hash_entries, $FBid_list))
    {
	$FBid = trim_space_from_ends ($file, $code, $FBid);

# Very simple sanity check.  More tests at the post-check phase.

	unless ($FBid eq 'new' or $FBid eq '' or $FBid =~ /^${FBid_type}\d{7,}$/)
	{
	    if ($hash_entries == 1)
	    {
		report ($file, "%s: Invalid %s '%s'", $code, $FBid_type, $FBid);
	    }
	    else
	    {
		report ($file, "%s: Invalid %s '%s' in '%s'", $code, $FBid_type, $FBid, $FBid_list);
	    }
	}
	push @FBid_list, $FBid;				# Store symbol for posterity.
    }
    return  @FBid_list;
}

sub cross_check_FBid_symbol
#sub cross_check_FBid_symbol ($$$$$$$\@$\@$\@$\@)
{
# In each proforma type, the X1a field declares a set of symbols and another, usually X1h or X1f, defines a
# set of FB identifiers or the word 'new' (the latter for the X1f field only).  This routine checks
# consistency of those two sets and ensures that the renaming/merging fields do not have data.
#
# The first argument is the name of the curation record being validated.
# The second is true if the data may be blank, false otherwise.
# The third is true if the word 'new' is valid data, false otherwise.
# The fourth is the FBid-type of symbol being checked (e.g. FBgn).
# The fifth is the type of symbol being checked (e.g. gene)
# The sixth is the number of symbols expected to be in the hash list.
# The seventh is the FBid field code (e.g. G1h).
# The eighth is a reference to a list of FBids.
# The ninth is the symbol field code (e.g. G1a).
# The tenth is a reference to the list of symbols declared in the symbol field.
# The eleventh is the rename field code (e.g. G1e).
# The twelfth is a reference to the list of symbols declared in the rename field.
# The thirteenth is the merge field code (e.g. G1f).
# The fourteenth is a reference to the list of lists of symbols declared in the merge field.

# Note that we assume earlier checks have ensured that any two lists have the same number of elements (and at
# least one in each).

    my ($file,        $null_ok,     $new_ok,     $FB_type,    $type,     $num_syms,
	$FBid_code,   $FBid_list,   $sym_code,   $sym_list,
	$rename_code, $rename_list, $merge_code, $merge_list) = @_;

    $#$rename_list + 1 == $num_syms and	report ($file, "%s must not have data '%s' when %s has data '%s' (if the %s field is empty (i.e. data is ''), you still need to delete the field to prevent parsing errors)",
						$FBid_code, join (' # ', @$FBid_list),
						$rename_code, join (' # ', @$rename_list), $FBid_code);

    $#$merge_list + 1 == $num_syms and report ($file, "%s must not have data '%s' when %s has data '%s' (if the %s field is empty (i.e. data is ''), you still need to delete the field to prevent parsing errors)",
					       $FBid_code, join (' # ', @$FBid_list),
					       $merge_code, join (' # ', map (join ("\n", @$_), @$merge_list)), $FBid_code);
    for (my $i=0; $i<$num_syms; $i++)
    {
	my $sym = $sym_list->[$i];
	my $chado_id = valid_chado_symbol_used_in_cross_check_FBid_symbol ($sym, $FB_type);
	my $chado_sym = valid_symbol ($chado_id, 'uniquename');
	my $FBid = $FBid_list->[$i];

	if (!defined $FBid or $FBid eq '')
	{
	    $null_ok or report ($file, "%s: missing data", $FBid_code);
	}
	elsif ($FBid eq 'new')
	{
	    unless ($new_ok)
	    {
		report ($file, "%s: the word 'new' is not allowed in this field", $FBid_code);
		next;
	    }

# The corresponding symbol must also be pre-instantiated.  If this is the case, the result of valid_symbol
# will begin with 'good_'.  If the symbol is not new it will have a value in Chado.

	    if ($chado_id)
	    {
		report ($file, "%s claims '%s' is new, but %s is already known to Chado as %s",
			$FBid_code, $sym, $sym, $chado_id);
	    }
	    elsif (valid_symbol ($sym, $FB_type) ne "good_$sym")	# Not in Chado at all.
	    {
		report ($file, "%s claims '%s' is new, but no other field has created that symbol",
			$FBid_code, $sym);
	    }
	}
	else
	{
	    if ($chado_id)
	    {
		next if $chado_id eq $FBid and $chado_sym eq $sym;
		report ($file, "%s: The FBid given in %s, '%s', does not match the symbol given in %s, '%s'.",
			$FBid_code, $FBid_code, $FBid, $sym_code, $sym);
	    }
	    else
	    {
		valid_symbol ($FBid, 'uniquename') and
		    report ($file, "%s: The FBid given in %s, '%s', does not match the symbol given in %s, '%s'.",
			    $FBid_code, $FBid_code, $FBid, $sym_code, $sym);
	    }
#=for comment

#I rather prefer this version because it is more informative.  Gillian thinks it is too informative.
# Sian asked for this to go back in DC-146

	    if ($chado_id)
	    {
		$chado_id eq $FBid or report ($file,
					      "%s: The FBid is given as %s and %s gives the symbol as '%s', " .
					      "but Chado knows '%s' as %s",
					      $FBid_code, $FBid, $sym_code, $sym, $sym, $chado_id);
		$chado_sym eq $sym or report ($file,
					      "%s: The FBid is given as %s and %s gives the symbol as '%s', " .
					      "but Chado thinks %s is '%s'",
					      $FBid_code, $FBid, $sym_code, $sym, $chado_id, $chado_sym);
	    }
	    else
	    {
		my $chado_FBid_sym = valid_symbol ($FBid, 'uniquename');
		$chado_FBid_sym and report ($file,
					    "%s: The FBid is given as %s and %s gives the symbol as '%s', " .
					    "but Chado thinks %s is '%s'",
					    $FBid_code, $FBid, $sym_code, $sym, $FBid, $chado_FBid_sym);
	    }
#=cut
	}
    }
}

sub cross_check_1a_1g
{
# In each proforma type, the *1a field declares a set of symbols.  Some may already exist in Chado while
# others may be newly instantiated by this proforma.  The *1g field should contain y or n according to whether
# or not the symbol exists in Chado.  This routine performs that check.
#
# The first argument is the name of the curation record being validated.
# The second is the code for the type of proforma (G, GA, A, AB, ...).
# The third is the FBid-type of symbol being checked (FBgn, FBal, FBab, FBba, ...).
# The fourth is the type of symbol being checked (gene, allele, aberration, balancer, ...)
# The fifth is the number of symbols expected to be in the hash list.
# The sixth is (a possibly hashed list of) the raw *1g y/n data.
# The seventh is a reference to the list of symbols declared in the *1a field.

    my ($file, $code, $FB_type, $type, $num_syms, $g_data, $sym_list) = @_;

# A call to check_y_or_n() will detect any mismatch between the number of values in the two proforma fields
# and report on them.  If there is a mismatch, it will return a null array and we use this to determine
# whether further checks are feasible.

    if (my @g_list = check_y_or_n ($file, "${code}1g", $num_syms, $g_data))
    {
	for (my $i = 0; $i <= $#g_list; $i++)	# Cross-check consistency of @g_list and @sym_list
	{
	    my $a_sym = $sym_list->[$i];
	    my $FBid = valid_chado_symbol ($a_sym, $FB_type);

	    if ($g_list[$i])
	    {
		$FBid or report ($file, "%s1g claims that %s is an existing %s symbol, " .
				 "but Chado has never heard of it.", $code, $a_sym, $type);
	    }
	    else
	    {
		$FBid and report ($file, "%s1g claims that %s is not an existing %s symbol, " .
				  "but Chado knows it as %s", $code, $a_sym, $type, $FBid);
	    }
	}
    }
}

sub cyto_check ($)
{
# The single argument is a cytological range to be checked.  It may be either a single location or a pair
# separated by '--'.  Return value is a list of invalid locations.

    my ($loc1, $range, $loc2) = ($_[0] =~ /^([^-]*)(--(.*))?/);
    $loc1 or return ($range);		# Empty location is not invalid for present purposes, but a leading '--' is.

    my @retval = ();

    valid_symbol ($loc1, 'cyto loc') or push @retval, $loc1;
    $range or return @retval;		# No need to check a range?

    if ($loc2)
    {
	valid_symbol ($loc2, 'cyto loc') or push @retval, $loc2;
    }
    else
    {
	push @retval, $range;		# Missing right hand value?
    }
    return @retval;
}

sub check_non_ascii ($$$)
{
	my ($file, $code, $data) = @_;
	my @words = split /\s+/, $data;

	foreach my $word (@words) {

		if($word =~ m/[[:^ascii:]]/) { # perl format required for check provided by Ray
			report ($file, "%s: non-ASCII character(s) in '%s'.\n", $code, $word);
		}

	}
}

sub set_provenance {

# This subroutine deals with any provenance string in a GO/DO style annotation line.
# The valid provenance string(s) for each type of annotation line are stored in a %provenance_mapping
# hash in this subroutine, and not in the %symbol_table
# because the valid values need to be used in a different way from the way entries
# in the %symbol_table are used and so putting them in the %symbol_table didn't fit.
# The subroutine does two things:
# 1. REMOVES any valid provenance string from the beginning of the annotation line (which
# is stored in $datum), so that subsequent checks can be done on the format of the rest
# of the annotation line (this checking is done in the relevant validate_<field> subroutine).
# 2. sets the provenance value in $provenance for subsequent checks done in the
# do_go_evidence/do_do_evidence subroutine.
# NOTE: the subroutine does NOT explicitly check that a provenance given at the beginning 
# of the line is a valid value, instead it removes it if there is a match to a valid value.
# This follows how the progenitor do_go_provenance subrtouine was originally set up and is
# presumably because the regular expression to check explicity would be too complicated.
# Invalid provenances will be caught by Peeves implicitly, because they will not be removed
# from the beginning of the annotation line, and so will generate an error when the other
# checking is done in the relevant validate_<valid> subroutine (it reports it as an
# 'Unknown term' as the provenance is still stuck on the front of the annotation line).
# (gm131206).

	my ($datum,$provenance,$type) = @_;

	my %provenance_mapping = (

		'DO' => 'FlyBase',
		'GO' => 'FlyBase|UniProtKB|BHF-UCL|GOC|HGNC|IntAct|InterPro|MGI|PINC|Reactome|RefGenome',

	);

	my $PROVENANCE = $provenance_mapping{$type};

	if ($datum =~ s/^($PROVENANCE)://) {

		$provenance = $1;

	} else {
# This sets the provenance to the default value of 'FlyBase' for those lines with no explicit provenance term in them.

		$provenance = 'FlyBase';
	}

	return ($datum, $provenance);

}

sub check_qualifier {


	my ($file, $code, $datum, $qualified_term) = @_;

	my $qualifier = '';
	my $term = '';

	my %qualifier_mapping = (

# 		'GA34a' => 'models|suppresses|enhances|DOES NOT model|DOES NOT suppress|DOES NOT enhance',
		'GA34a' => 'model of|ameliorates|exacerbates|DOES NOT model|DOES NOT ameliorate|DOES NOT exacerbate',
		'G24a' => 'colocalizes_with|part_of|located_in|is_active_in',
		'G24b' => 'contributes_to|enables',
		'G24c' => 'involved_in|acts_upstream_of|acts_upstream_of_positive_effect|acts_upstream_of_negative_effect',
	);


	my $QUALIFIER = $qualifier_mapping{$code};
	
	if ($qualified_term =~ /^($QUALIFIER) (.*)/) {

		$qualifier = $1;
		$term = $2;

	} else {

# In this case, there is either no qualifier, or someone has entered an invalid qualifier.
# The whole string (ie. $qualified_term) is put into $term to ensure that something is always returned for the subsequent term<->id match testing (this is necessary, since GO lines don't have to have a qualifier, so in this case need to return what you started out with so that it goes into the term<->id match check).  It does mean that if an invalid/missing qualifier is put for DO that a single line will generate two error reports, but that is necessary to make sure that it doesn't miss possible errors in GO lines.

		$term = $qualified_term;

# qualifier is compulsory, so print an error if there isn't one

		unless ($qualifier) {

			report ($file, "%s: No valid qualifier in '%s'",$code,$datum);
		}
	}

	return ($qualifier,$term);
}

sub check_evidence_data {

# This subroutine checks objects given after an evidence code in a DO/GO style annotation line for those evidence codes that have ' with ' after the code
# List of arguments
# $file = curation record number
# $code = proforma code
# $context = full line entered into proforma, primarily to give context when reporting errors
# $ev_code = evidence code
# $ev_data = evidence data directly after the evidence code.  This includes the evidence suffix e.g. ' with ' when passed in to
# subroutine.  The suffix is stripped off later if some basic checks are passed, to allow the final formatting checks to take place

# $ev_code could also be used in the future to limit what kind of format is allowed for a particular evidence code e.g. for IGI in GO data could add code to only allow @@ format and not "split ('; ', $db_group)" format which is external databases ?.

# objects after the ' with ' are separated with a ', ' and can be in one of two formats:
# @@
# <database_abbrev>:symbol; <database_abbrev>:id

# The check_evidence_data subroutine is based on the check_go_databases subroutine which it replaces.  The differences are:
# a. new subroutine takes more arguements as it is in tools.pl (so can be used for both GO and DO checking).
# b. added a check that the evidence suffix matches what is expected for the evidence code using information in symtab.pl
# c. the 'if ($db_group =~ m/^\@(.*)\@$/)' loop has been added so that objects after the evidence code and evidence suffix (bit after the evidence code, e.g. 'with')
# can be either be in @@ or in the original 'database_abbreviation:identifier' or (for symbols) database_abbreviation:<symbol>; database_abbreviation:<ID_for_that_symbol> format


    my ($file,$code, $context, $ev_code, $ev_data) = @_;

	my $ev_suffix = "";
	my $symbol_type = $code;
	$symbol_type =~ s|[0-9]{1,}([a-z]?)$||;

# fix so that only need to store expected values for GO fields once in symtab.pl - ought to be able to make this neater
	if ($code =~ m|^G24|) {
		my $short_code = $code;
		$short_code =~ s|[a-z]$||;
		$ev_suffix = valid_symbol (($short_code . '_evidence'), $ev_code); # note that this is called the otherway around from many valid symbol calls due to the way this info is stored in the symbol_table
	} else {
		$ev_suffix = valid_symbol (($code . '_evidence'), $ev_code); # note that this is called the otherway around from many valid symbol calls due to the way this info is stored in the symbol_table
	}


	if ($ev_data) {

		if ($ev_suffix eq 'null') {

			report ($file, "%s: Must not have data '%s' after the '%s' evidence code in '%s'", $code, $ev_data, $ev_code, $context);
			return;

		} else {

# where having data after the evidence code is optional, remove the ? from the corresponding expected evidence suffix
# before testing that the value in the proforma matches what is expected.
			$ev_suffix =~ s|\?$||;

			unless ($ev_data =~ m|^ $ev_suffix |) {
				report ($file, "%s: '%s' must start with ' %s ' after the '%s' evidence code:\n%s", $code, $ev_data, $ev_suffix, $ev_code, $context);
				return;
			}
		}

	} else {

		unless ($ev_suffix eq 'null') {

# don't report an error if having data after the evidence code is optional.
			unless ($ev_suffix =~ m|\?$|) {

				my $extra_error_text = "";

				if ($code =~ m|^G24|) {
					if ($ev_code =~m/^(inferred from sequence alignment|ISA|inferred from sequence orthology|ISO|inferred from sequence or structural similarity|ISS)$/) {
						$extra_error_text = "\n(if you cannot provide a database identifier, consider using the ISM evidence code instead).";
					}
				}

				report ($file, "%s: Must have '%s ' data after the '%s' evidence code in '%s'%s", $code, $ev_suffix, $ev_code, $context,$extra_error_text);
				return;
			}
		}
	}


# remove the evidence suffix to allow subsequent checking
    $ev_data =~ s/^ $ev_suffix //;

# use check_stamps subroutine to check for basic formatting errors in any @@ e.g. odd number, empty stamps etc.
# Check whole line once rather than in the 'if ($db_group =~ m/^\@(.*)\@$/)' loop below so that the case where
# a single @ is present is caught, and to provide better context in any error messages.
# Similarly, check $context rather than $ev_data so that any error messages provide better context.
	check_stamps ($file,$code,$context);


    foreach my $db_group (split (', ', $ev_data)) {

# symbols in @@ format
		if ($db_group =~ m/^\@(.*)\@$/) {

			my $obj_symbol = $1;


			valid_symbol_of_list_of_types ($obj_symbol, $standard_symbol_mapping->{$symbol_type}->{id}) or
				report ($file, "%s: '%s' in '%s' is not a valid %s symbol.", $code, $obj_symbol, $context,$standard_symbol_mapping->{$symbol_type}->{type});

# 'database_abbreviation:identifier' or (for symbols) database_abbreviation:<symbol>; database_abbreviation:<ID_for_that_symbol> format

		} else {

# this entire section taken straight from check_go_databases
			my ($obj_symbol, $obj_id) = ('', '');

# We insist that if either of FLYBASE or FB appear, they must both do so and, further, that they appear in
# that order.

			my ($seen_fb, $seen_flybase, $fb_before_flybase) = (0, 0, 0);

			foreach my $db_object (split ('; ', $db_group)) {
				if (my ($db, $object) = ($db_object =~ /(.*?):(.*)/)) {
					if (valid_symbol ($db, 'GO_database')) {
						if ($db eq 'FLYBASE') {
# Only emit one report, even if it occurs several times.
							if ($seen_flybase == 1)	{
								report ($file, "%s: '%s' has more than one FLYBASE in '%s'", $code, $db_group, $context);
							} else {
								$seen_flybase++;				# Track number of occurrences.
								$obj_id eq '' or $fb_before_flybase = 1;	# $obj_id has a value only if FB has been seen.
								$obj_symbol = $object;			# Preserve last one seen.
							}
						} elsif ($db eq 'FB') {
# Only emit one report, even if it occurs several times.
							if ($seen_fb == 1) {
								report ($file, "%s: '%s' has more than one FB in '%s'", $code, $db_group, $context);
							} else {
								$seen_fb++;					# Track number of occurrences.
								$obj_id = $object;				# Preserve last one seen.
							}
						}
					} else {
						report ($file, "%s: '%s' is not a valid database abbreviation in '%s'", $code, $db, $context);
					}
				} else {
					report ($file, "%s: I don't recognize '%s' in '%s'.  Did you forget a '\@' ',' or ':' perhaps?", $code, $db_object, $context);
				}
			}

			if ($seen_flybase) {
				if ($seen_fb) {						# Seen both.  Enforce identity and validity of them.
					if (my ($fb_type) = ($obj_id =~ /^(FB[a-z][a-z])\d{7,}$/)) {
						my $purported_symbol = valid_symbol ($obj_id, 'uniquename');
						my $purported_id = valid_symbol ($obj_symbol, $fb_type);
						if ($purported_id eq "good_$obj_symbol") {

# A newly-instantiated symbol.  Dig out what is in Chado, if anything, then restore the symbol_table entry.
							delete_symbol ($obj_symbol, $fb_type);
							my $chado_id = valid_symbol ($obj_symbol, $fb_type);
							set_symbol ($obj_symbol, $fb_type, "good_$obj_symbol");

							if ($purported_symbol) {
								$purported_symbol = $obj_symbol;	# The rename case
								$purported_id = $obj_id;
							} else {
								$purported_id = $chado_id;		# The invalid object_id case.
							}
						}

						if ($purported_symbol) {
							if ($purported_id) {
								unless ($obj_symbol eq $purported_symbol && $obj_id eq $purported_id) {
									report ($file, "%s: Mismatched symbol and FB-ids in '%s'\n'%s' is '%s' and '%s' is '%s'.", $code, $context, $obj_symbol, $purported_id, $obj_id, $purported_symbol);
								}
							} else {
								report ($file, "%s: Invalid symbol '%s' in '%s', did you mean 'FLYBASE:%s; FB:%s' perhaps?", $code, $obj_symbol, $context, $purported_symbol, $obj_id);
							}			
						} else {
							if ($purported_id) {
								report ($file, "%s: Invalid FB-id '%s' in '%s', did you mean 'FLYBASE:%s; FB:%s' perhaps?", $code, $obj_id, $context, $obj_symbol, $purported_id);
							} else {
								report ($file, "%s: Invalid FB-id '%s' in '%s'", $code, $obj_id, $context);
							}
						}
					} else {
# the error message below is for when an FBid does not match FB[a-z]{2}[0-9]{7,} format
						report ($file, "%s: Invalid FB-id '%s' in '%s'", $code, $obj_id, $context);
					}
				} else {
					report ($file, "%s: '%s' is missing its FB data in '%s'", $code, $db_group, $context);
				}
			} else {
				if ($seen_fb) {
					report ($file, "%s: '%s' is missing its FLYBASE data in '%s'", $code, $db_group, $context);
				}

#  Much too hard to check data validity of external databases, so we don't even try --- which is why there's
#  no else-clause here.

			}

			if ($fb_before_flybase) {
				report ($file, "%s: FB must not appear before FLYBASE in %s", $code, $context);
			}

		}

    }
}


sub no_hashes_in_proforma {

# Check that there are no hashes in the entire proforma if the proforma field
# being checked ($code) contains data.
# The check looks at whether there is hashing in the primary symbol field of the
# proforma (i.e. G1a, GA1a, A1a, AB1a) rather than looking directly at the field
# being checked to ensure that there is no hashing in the entire proforma.
#
# $file = curation record
# $code = proforma code
# $num = number of entries in the primary symbol field of the proforma
# $data = data in proforma field being checked

	my ($file, $code, $num, $data) = @_;

    return if $data eq '';			# If there is no data in the field, no need to check

	$num > 1 and report ($file, "%s: entire proforma must not contain hashes when this field contains data ('%s')",$code,$data);




}

sub check_allowed_characters {

# This subroutine checks whether a symbol contains only the allowed characters for that 
# proforma field ($code) and generates an error message if not.
# It is designed to check a single symbol at a time, so should be called after the data 
# has been dehashed (all fields) and after each value has been separated out (for fields
# with multiple values allowed).
# This generic subroutine is based on code written by Paul Leyland which was originally
# included within individual validate_x subroutines in the <proforma>.pl modules.
# I added added a mapping hash that defines which characters are allowed in each field, so
# that the subroutine can be called from different field checking sections.
# I had to change the first substitution from a tr/// to a s/// so that the information
# from the mapping table can be put in a variable ($ALLOWED_CHARACTERS) and interpolated
# in the substitution, as tr/// does not allow interpolation. [gm131211].

# The metacharacters that will require backslashing in the mapping table ought to apparently be this:
#       \ | ( ) [ { ^ $ * + ? .

# ^ $ * ? should never be allowed in a symbol so should not ever be in the mapping table.
# I found from testing that:
# you need to backslash '  as single quotes are used in the mapping table
# you need to backslash ] so that $ALLOWED_CHARACTERS inserts properly into the s/[]//g as a set of characters to remove
# you need to backslash - so that $ALLOWED_CHARACTERS inserts properly into the s/[]//g (otherwise tries to interpret it as a range).  Put it at the end of the list to stop it causing problems
# ) and { and + seemed to work both with and without the backslash
#
#
# So the final list of characters that you need to backslash is:
#      \ | ( [] . ' - 
#
# and possibly:
#      ) { +


	my ($file,$code,$symbol,$field_data) = @_;

	my $temp_copy = $symbol;

	my %mapping_table = (

# single quotes in the mapping table so that the exact string is put into the substitution

# symbol fields
		'G1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.\-',
# note that the GA1a character set is used to check the superscripted portion of the allele symbol only, since the non-superscripted part corresponds to the parent gene symbol (which will be checked in G1a)
		'GA1a' => 'a-zA-Z0-9:;&\\\()\'\.,\+\-', # same characters as for G1a, EXCEPT no [ or ] (to prevent nesting of superscripts) Has in addition , and +
		'A1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\?\-', # same characters as for G1a, and has in addition ? , and + (? is for cases when one of the chromosomes is not known)
		'AB1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\{}\-', # same characters as for G1a, and has in addition , + { and }
		'MA1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\?\{}\-', # same characters as for G1a, and has in addition ? , + { and }

		'GG1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.\-', # same as G1a
		

		'GA10c' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\?\{}\-', # must be the same as MA1a
		'GA10e' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\?\{}\-', # must be the same as MA1a

		'MS1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\?\{}\-', # same characters as MA1a

		'GA10a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\?\{}\-', # must be the same as MS1a


		'TE1a' => 'a-zA-Z0-9:;&\\\.\-\'', # same characters as G1a, except no [ ] ( )

		'F1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+\-', # same as G1a (so includes [ ]), plus , and +, so that it has all the characters that could be in either a gene or allele symbol (which is what the symbols in this field are based on)

		'TO1a' => 'a-zA-Z0-9:;&\\\[\]\()\'\.\+\-', # same as G1a, plus + Have allowed \ for now.

# proformae for which the valid symbol does not include a species prefix, even if the
# species isn't Dmel (species is defined by a separate field in the proforma).
# No species prefix is included in the valid symbol for non-Dmel cell lines.
		'TC1a' => 'a-zA-Z0-9:;&>\[\]\()\'\.\+\-', # same as G1a with removal of \ and addition of +. Also added > (DC-1042)
		'LC1a' => 'a-zA-Z0-9_:;&\[\]\()\'\.\+\-', # same as TC1a, plus _

# proformae where probably won't include the species prefix in the symbol for non-Dmel
# based on proforma parsing software, but there are no examples to check yet.
# For now, exluded \ in allowed list

		'SF1a' => 'a-zA-Z0-9_:;&\[\]\()\'\.\+\-\/', # same as LC1a, but with / added (DC-895)

#		'' => '',

# name fields
		'G2a' => 'a-zA-Z0-9:;&\[\]\()\'\.,\+/ \-', # same characters as for G1a, EXCEPT no \ (has [ ] to allow for things like Ca[2+]-channel). Has in addition , + / and space
		'GA2a' => 'a-zA-Z0-9:;&\[\]\()\'\.,\+/ \-', # same characters as for G2a
		'A2a' => 'a-zA-Z0-9:;&\[\]\()\'\.,\+/ \?\-', # same characters as for G2a plus ?
		'AB2a' => 'a-zA-Z0-9:;&\[\]\()\'\.,\+/ \-', # same characters as for G2a
		'GG2a' => 'a-zA-Z0-9:;&\[\]\()\'\.,\+/ \-', # same characters as for G2a

		'TO2a' => 'a-zA-Z0-9:;&\[\]\()\'\.,\+/ \-', # same characters as for G1a, EXCEPT no \ (has [ ] to allow for things like Ca[2+]-channel). Has in addition , + / and space

# the primary symbol field for the HH proforma is a name so allowed characters is more like the
# fullname sets for other proformae
		'HH1b' => 'a-zA-Z0-9:;&\\\[\]\()\'\.,\+/ \-', # same characters as for G1a, plus , + / and space (kept \ as there is a HH entry already with this character)

# database name is more like a name field, even though its a 1a field
		'DB1a' => 'a-zA-Z0-9:;&\[\]\()\'\.,\+/ \-', # same characters as for G2a
		
#		'' => '',
# other fields
		'A29' => 'ABCDEFLRSXYcehnt0-9;\() \|\-', # cytological order field.  Temporary check until work out how to check for format properly
#		'' => '',
#		'' => '',

# checks for sub-field portions in complex interaction.pro lines

		'IN7c_description' => 'a-zA-Z0-9:;&\\\[\]\()\.\- ', # same as for G1a, but without the ' and including space
		'IN7d_description' => 'a-zA-Z0-9:;&\\\[\]\()\.\- ', # same as for G1a, but without the ' and including space

		'SP1a' => 'a-zA-Z',
		'SP1b' => 'a-zA-Z ',
		'SP2' => 'a-zA-Z0-9',
	);

	unless (exists $mapping_table{$code}) {

		report ($file,"%s proforma has not been set up to check for valid characters in symbol - please let Gillian know if you see this error, so that it can be set up properly",$code);
		return;
	}

	my $ALLOWED_CHARACTERS = $mapping_table{$code};

	$temp_copy =~ s/[$ALLOWED_CHARACTERS]//g;	# First remove all valid characters. Had to change from tr///d to s///g to allow interpolation of $ALLOWED_CHARACTERS

# only generate an error message if there is something left, ie. invalid character(s), this is unchanged from original version written by Paul
	if ($temp_copy ne '') {
		$temp_copy = join ('', sort (split (//, $temp_copy))); # split into single characters and sort them
		$temp_copy =~ tr///cs; # convert everything down to a single instance of each invalid character
		
# usually the context reported is the whole proforma line (including any hashes)		
		if ($code =~ m|^[A-Z]{1,}[0-9]{1,}[a-z]{0,}$|) {
			report ($file, "%s: Invalid character%s '%s' in %s from\n!%s", $code, length ($temp_copy) == 1 ? '' : 's', join ("' '", split (//, $temp_copy)), $symbol, $field_data);

# but if only part of a field line is being checked (e.g. sub-field in complex interaction.pro field), the context reported is just the single line being checked
		} else {

			report ($file, "%s: Invalid character%s '%s' in %s from '%s'", $code, length ($temp_copy) == 1 ? '' : 's', join ("' '", split (//, $temp_copy)), $symbol, $field_data);
		
		}
	}

}

sub check_for_duplicated_lines {

# this checks for duplicated lines within a field that contains data separated by returns.
# It reports any duplicates and returns a uniqued list in a hash for any further checking.
# Since it returns a hash, the lines in the Peeves error report will not necessarily appear
# in the same order as they appear in the proforma, but this should not matter providing the
# error message has enough context.
# It calls trim_space_from_ends to make sure any leading/trailing spaces are removed before
# looking for duplicates, in case there has not already been a trim_space_from_ends in the
# validate_x subroutine from which it is called
# It should be called after the 'dehash' subroutine, so that the data is already dehashed. This
# is particularly important as it returns a hash, to make sure that any hashed data in the field
# is compared against the intended data in any corresponding hashed symbol field.

# $file = curation record name
# $code = proforma field code
# $data = data entered into proforma field
# $context = entire proforma field plus data to give context in any error message

	my ($file, $code, $data, $context) = @_;

	my $uniqued_data = {};

	my @data_lines = split (/\n/, $data);
	foreach my $datum (@data_lines) {

		$datum = trim_space_from_ends ($file, $code, $datum);
		if (exists $uniqued_data->{$datum}) {

			$uniqued_data->{$datum}++;
		} else {

			$uniqued_data->{$datum} = 0;
		}


	}

	foreach my $datum (keys %{$uniqued_data}) {
		report ($file, "%s: Duplicated data '%s' in:\n!%s'", $code, $datum, $context) if $uniqued_data->{$datum};

		if ($datum eq '') {
			report ($file, "%s: Blank line in data:\n!%s", $code, $context); # report empty lines
			delete $uniqued_data->{$datum}; # then remove so don't interfere with further checks
		}

	}


	

	return $uniqued_data;


}


sub get_triage_data_from_chado {

	my ($chado, $type, $FBrf) = @_;
	my $data = {};

	my $chado_data = &get_flag_data($chado,$type,$FBrf);

# remove FBrf that hangs off the flag in $chado_data, so that its
# in the right format to add data from proforma to the chado data.

	foreach my $flag (keys %{$chado_data}) {
		$data->{$flag}++;

	}

	return ($data);

}


sub validate_rename {

# This subroutine validates the rename field. It can be used for all types of proforma (ie. both 'Cambridge'
# and 'Harvard' style).
# It does three things:
# 1. checks that the field is either empty or contains a single value
# 2. checks that the value (if filled in) is a valid symbol of the expected type in chado
# 3. returns a list of the values in the field (so that these can be used in later cross-checks between different proforma fields) 

# $file = curation record
# $code = proforma field code
# $num = number of entries in the primary symbol field of the proforma
# $change = whatever is between ! and code i.e. nothing if no !c, 'c' if !c
# $rename = entire contents of rename proforma field, without proforma field text
# $context = entire contents of rename proforma field, including proforma field text, should be provided using %proforma_fields hash

    my ($file, $code, $num, $change, $rename, $context) = @_;

	my @rename_list;

	my $symbol_type = $code;
	$symbol_type =~ s|[0-9]{1,}[a-z]{1,}$||;

	unless (exists $standard_symbol_mapping->{$symbol_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nvalidate_rename subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$symbol_type,$code);
		return ();
	}

    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context);

    return () if $rename eq '';			# Absence of data is permissible.

    foreach my $symbol (dehash ($file, $code, $num, $rename))
    {
	$symbol = trim_space_from_ends ($file, $code, $symbol);
	if ($symbol =~ /\n/)
	{
	    report ($file, "%s: More than one %s symbol in '%s'", $code, $standard_symbol_mapping->{$symbol_type}->{type}, $symbol);
	    return ();				# Not much point checking anything else.
	}

	push @rename_list, $symbol;			# Save for post-check regardless of validity checks below.

# The pre-instantiation code should have already ensured that $symbol has been invalidated in the symbol table
# (so that everyone else knows that it will be invalid for the purposes of this curation record) but we also
# want to know whether it is really in Chado.  So what we do is find the symbol's value in the symbol table
# and ensure that it is indeed invalid.  If it aint, x1a will also have the same symbol and this will
# have trumped the rename field --- in which case complain bitterly but leave it valid, thereby assuming
# that its presence in the rename field is a pasto.  Assuming $symbol is invalid, valid_chado_symbol
# is used to check that the symbol is valid *in chado*.

	if (valid_symbol_of_list_of_types ($symbol, $standard_symbol_mapping->{$symbol_type}->{id}))
	{
	    report ($file, "Conflict between %s1a and %s --- '%s' can not be present in both fields.\n(NOTE, if this error message appears wrong and you can't see the symbol in both fields of the same proforma, you've made a subtle error - either you have renamed a symbol in one proforma and then used that symbol to make a new feature in another proforma, or you have renamed an insertion/construct in their own proforma but then used the old symbol in a GA10 field.  Eventually Peeves will hopefully distinguish between these errors but for now, leaving as is and printing this warning, so at least all the errors are still flagged).", $symbol_type, $code, $symbol);
	}
	else
	{
	    unless (valid_chado_symbol_of_list_of_types ($symbol, $standard_symbol_mapping->{$symbol_type}->{id})) {
			report ($file, "%s: %s is not a valid %s symbol in Chado", $code, $symbol, $standard_symbol_mapping->{$symbol_type}->{type});
		}
	}
    }

	return @rename_list;

}

sub validate_x1f {
# The data must either be empty or a list of at least two symbols, all different and given one per line,
# all of which must exist as valid symbols in Chado.  Don't worry about whether G1e has buggered up the
# validity data for now.  It will all be sorted out in the post-check phase.

# This subroutine validates the merge field ('x1f') for the 'Cambridge' style proformae
# i.e. gene, allele, aberration and balancer
# $file = curation record
# $code = proforma field code
# $num = number of entries in the primary symbol field of the proforma
# $change = whatever is between ! and code i.e. nothing if no !c, 'c' if !c
# $merge_list = entire contents of 'x1f' proforma field, without proforma field text
# $context = entire contents of 'x1f' proforma field, including proforma field text, should be provided using %proforma_fields hash


    my ($file, $code, $num, $change, $merge_list, $context) = @_;

	my @x1f_list;

	my $symbol_type = $code;
	$symbol_type =~ s|1f$||;

	unless (exists $standard_symbol_mapping->{$symbol_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nvalidate_x1f subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$symbol_type,$code);
		return ();
	}


    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context);

    return () if $merge_list eq '';			# Absence of data is permissible.

	my @symbols = dehash ($file, $code, $num, $merge_list);

# only run the test if dehash found the correct number of hash entries, prevents
# warnings in the terminal
	if (@symbols) {
	    for (my $i = 0; $i < $num; $i++) {

		my @s_list = ();

			my $uniqued_symbols = check_for_duplicated_lines($file,$code,$symbols[$i],$context);

			scalar (keys %{$uniqued_symbols}) >1 or report ($file, "%s: You have entered only the symbol '%s' here.  " .
					    "%s requires at least two symbols or no merge can occur.",
					    $code, $symbols[$i], $code);

			foreach my $symbol (keys %{$uniqued_symbols}) {


	    		$symbol = trim_space_from_ends ($file, $code, $symbol);
	    		push @s_list, $symbol;
				valid_chado_symbol_of_list_of_types ($symbol, $standard_symbol_mapping->{$symbol_type}->{id}) or report ($file, "%s: '%s' is not a valid %s symbol", $code, $symbol, $standard_symbol_mapping->{$symbol_type}->{type});



			}

			push @x1f_list, [@s_list];

		}
	}

	return @x1f_list;
}


sub validate_new_full_name {
# converted validate_x2a to process_field_data + %field_specific_checks format and renamed to validate_new_full_name. 140703.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	# the following shouldn't be necessary as this subroutine should always be called via process_field_data from a field that has the single_line_status set to '1', but including it again for belts and braces
	single_line ($file, $code, $dehashed_data, $context->{$code}) or return;

	$dehashed_data = trim_space_from_ends ($file, $code, $dehashed_data);
	check_allowed_characters($file,$code,$dehashed_data,$context->{$code});

	while ($dehashed_data =~ /(&.*?;)/g)
	{
	    valid_greek($1) or report ($file, "%s: Malformed Greek symbol %s in %s.", $code, $1, $dehashed_data);
	}
}

sub validate_existing_full_name {
# converted validate_x2c to process_field_data + %field_specific_checks format and renamed to validate_existing_full_name. 140703.
# cross checks with chado are not done here, but are done at the end of checking the whole
# proforma since need the value in the primary symbol field to check against chado
	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	# the following shouldn't be necessary as this subroutine should always be called via process_field_data from a field that has the single_line_status set to '1', but including it again for belts and braces
	single_line ($file, $code, $dehashed_data, $context->{$code}) or return;

	$dehashed_data = trim_space_from_ends ($file, $code, $dehashed_data);


}

sub validate_x1g {

    my ($file, $code, $num, $change, $data, $context) = @_;


	my @return_list;

    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context);

	contains_data ($file, $code, $data, $context) or return ();

	single_line ($file, $code, $data, $context) or return ();

	foreach my $datum (dehash ($file, $code, $num, $data)) {
		$datum = trim_space_from_ends ($file, $code, $datum);

		push @return_list, $datum;			# Save for post-check.

	}
	return @return_list;

# Other checks have to be done later.

}

sub cross_check_x1e_x1g {

# Check that if x1e is filled in, x1g is 'n' and print an error message if not
# for the 'Cambridge' style proformae i.e. gene, allele, aberration and balancer
# NOTE: this subroutine does not take into account the value in x1a (validate_rename
# does checks between the x1a and x1e fields)
# $file = curation record
# $code = proforma field code
# $num = number of entries in the primary symbol field of the proforma
# $x1g_data = entire contents of 'x1g' field, without proforma field text, note that this is NOT dehashed
# $rename_list = dehashed contents of x1e field (should be provided using e.g. \@G1e_list)
# $rename_context = entire contents of 'x1e' proforma field, including proforma field text, should be provided using %proforma_fields hash

    my ($file, $code, $num, $x1g_data, $rename_list, $rename_context) = @_;

	my $symbol_type = $code;
	$symbol_type =~ s|1e$||;

	unless (exists $standard_symbol_mapping->{$symbol_type}) {

		report ($file,"MAJOR PEEVES ERROR, no cross-checking will be done between the '%s' and '%s1g' fields until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\ncross_check_x1e_x1g is asking the \$standard_symbol_mapping variable about a '%s' type proforma field, but the variable has no information about that type of proforma.",$code,$symbol_type,$symbol_type,$code);
		return;
	}

# Copied the below from cross_check_1a_1g:
# A call to check_y_or_n() will detect any mismatch between the number of values
# in the two proforma fields and report on them.  If there is a mismatch, it will
# return a null array and we use this to determine whether further checks are feasible.

# only do the checks if x1g has the correct number of entries and correct value(s)
# note that check_y_or_n turns 'n' into 0 and 'y' into 1
    if (my @g_list = check_y_or_n ($file, $code, $num, $x1g_data)) {

		for (my $i = 0; $i <= $#g_list; $i++) {	# Cross-check consistency of @g_list and @rename_list

			my $rename = $rename_list->[$i];

			if ($rename) {

				if ($g_list[$i]) {

					report ($file, "You have filled in the '%s' field, but %s1g contains 'y'\n- if you are trying to do a rename, change the value in %s1g to 'n' and double-check that the symbol you have put in %s1a is new to chado (if its already in chado, maybe you were trying to do a merge and filled in %s1e instead of %s1f by mistake ?)\n!%s", $code, $symbol_type, $symbol_type, $symbol_type, $symbol_type, $symbol_type, $rename_context);

				}
			}

		}
	}
}


sub plingc_merge_check {

# In any one proforma, !c must not be used (in any field) if the merge field is filled in.
# Issue a warning if this condition is violated.
# $file = curation record
# $change_count = count of the number of fields with !c in the proforma
# $m_code = merge proforma field code
# $m_list = dehashed merge list
# $m_context = entire contents of 'merge' proforma field, including proforma field text, should be provided using %proforma_fields hash
	my ($file, $change_count, $m_code, $m_list, $m_context) = @_;

	$change_count and @$m_list and report ($file, "%s: You must not !c in the same proforma as a filled in merge field (please submit the !c data in a different curation record):\n!%s", $m_code, $m_context);


}

sub validate_merge_using_ids {

# Validate a merge field that uses FBids to specify the features to be merged.
#
# Does equivalent checks to validate_x1f (whch validates a merge field that uses symbols to specify the features to be merged):
# !c is not allowed in the field
# The data must either be empty or a list of at least two FBids, all different and given one per line.
# All FBids must be valid (i.e. be the primary FBid of a current symbol) in Chado.

# Extra check with no equivalent in validate_x1f:
# Warns if an FBid is not the type expected for that field.
# If a value does not match the general format of an FBid, checks to see if it is a valid symbol of the feature type expected for the field,
# and if it is, suggests the valid FBid of that symbol, so that it can easily be entered instead.

# Note that cross-checks with other fields are done elsewhere, once the entire proforma has been parsed.

# $file = curation record
# $code = proforma field code
# $num = number of entries in the primary symbol field of the proforma
# $change = whatever is between ! and code i.e. nothing if no !c, 'c' if !c
# $merge_field_list = entire contents of merge proforma field, without proforma field text
# $context = entire contents of merge proforma field, including proforma field text, should be provided using %proforma_fields hash


    my ($file, $code, $num, $change, $merge_field_list, $context) = @_;

	my @merge_list;

	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{1,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nvalidate_merge_using_ids subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$proforma_type,$code);
		return ();
	}

	my $id_types = join '|', @{$standard_symbol_mapping->{$proforma_type}->{id}};


    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context);

    return () if $merge_field_list eq '';			# Absence of data is permissible.

	my @ids = dehash ($file, $code, $num, $merge_field_list);

# only run the test if dehash found the correct number of hash entries, prevents
# warnings in the terminal
	if (@ids) {
	    for (my $i = 0; $i < $num; $i++) {

		my @id_list = ();

			my $uniqued_ids = check_for_duplicated_lines($file,$code,$ids[$i],$context);

			scalar (keys %{$uniqued_ids}) >1 or report ($file, "%s: You have entered only the id '%s' here.  " .
					    "%s requires at least two ids or no merge can occur.",
					    $code, $ids[$i], $code);

			foreach my $id (keys %{$uniqued_ids}) {

	    		$id = trim_space_from_ends ($file, $code, $id);

	    		push @id_list, $id;

				if ($id =~ m/^($id_types)\d{7,}$/) {
					unless (valid_symbol ($id, 'uniquename')) {
						report ($file, "%s: '%s' is not a valid id in Chado.", $code, $id);
					}
				} else {

					if ($id =~ m|^FB[a-z]{2}[0-9]{7,}$|) {
						report ($file, "%s: FBid '%s' is not of the expected type" . ($#{$standard_symbol_mapping->{$proforma_type}->{id}} > 0 ? "s" : '') . " (%s) for this field.", $code, $id, (join '\', \'', @{$standard_symbol_mapping->{$proforma_type}->{id}}));
					} else {

# See if a symbol of the expected type has been entered by mistake, instead of its FBid number
# Because its presence in the merge field will have invalidated it in the symbol table
# (as the merge field is a bad_symbol field used in the "First pass" in Peeves), 
# use valid_chado_symbol to see whether it is valid *in chado*

						if (my $chado_id = valid_chado_symbol_of_list_of_types ($id, $standard_symbol_mapping->{$proforma_type}->{id})) {
							report ($file, "%s: You have entered a symbol '%s' instead of an FBid number, did you mean '%s' (the valid id of %s) instead ?",$code, $id, $chado_id, $id);
						} else {
							report ($file, "%s: '%s' is not a valid FBid format:\n!%s", $code, $id, $context);
						}

					}
				}

			}

			push @merge_list, [@id_list];

		}
	}

	return @merge_list;



}


sub validate_primary_FBid_field {

# Validate the field that stores the primary FBid of the feature that is the subject of the proforma
# This is the x1f field in 'harvard' style proformae.
# Can't just use FBid_list_check as that allows the field to be empty, and it must be filled in for 'harvard' style proformae.
# May be possible to merge this subroutine and FBid_list_check eventually, but starting by making a separate subroutine for now [gm140225].

# Checks:
# !c is not allowed in the field.
# The field must not be empty.
# Only a single line of data is allowed.
# The number of entries in the list must match the number of entries in the primary symbol field of the proforma
# An entry must be either the string 'new' or an FBid number of the type expected for the proforma
# If the entry is an FBid number, it must be valid in chado.
# If the entry is a hashed list, reports there are any empty values within the list.

# It returns a list of the values in the field (so that these can be used in later cross-checks between different proforma fields)

# Note that cross-checks with other fields are done elsewhere, once the entire proforma has been parsed.

# $file = curation record
# $code = proforma field code
# $num = number of entries in the primary symbol field of the proforma
# $change = whatever is between ! and code i.e. nothing if no !c, 'c' if !c
# $ids = entire contents of primary proforma field, without proforma field text
# $context = entire contents of primary proforma field, including proforma field text, should be provided using %proforma_fields hash


    my ($file, $code, $num, $change, $ids, $context) = @_;

	my @id_list;

	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{1,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nvalidate_primary_FBid_field subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$proforma_type,$code);
		return ();
	}

	my $id_types = join '|', @{$standard_symbol_mapping->{$proforma_type}->{id}};

    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context);


	contains_data ($file, $code, $ids, $context) or return ();

	single_line ($file, $code, $ids, $context) or return ();

# ensure that number of ids in list matches the number in the primary symbol field
# cannot just use dehash to check this because an FBid is a unique value so if there
# is a single FBid number in this field, it is not correct to use dehash to populate
# it to multiple symbols

# if there are hashes in MA1f, then the number of hash entries in MA1f must equal the
# number of hash entries in MA1a (ie. $num). This will catch errors both when MA1f and MA1a each contain hashes
# and will also catch the error when MA1a has no hash, but MA1f does
	if ($ids =~ / \# /) {
		
		my @temp_number = (split / \# /, $ids);
		my $hash_number = @temp_number;
		unless ($hash_number == $num) {
			report ($file, "%s: Number of ids does not match the number of symbols in the corresponding %s" ."1a symbol field:\n!%s", $code, $proforma_type, $context);
			return ();
		} else {
# force an error when have 'new # new' (etc) in MA1f as not sure it is legal for parsing
			my $test = $ids;
			$test =~ s/ \# //g;
			if ($test =~ m/^(new){1,}$/) {
				report ($file, "%s: Do not use hashed 'new' entries when making new insertions, change %s value to a single 'new':\n!%s", $code, $code, $context);

			}
		}

	} else {

# if there are no hashes in MA1f and MA1f != 'new', there must only be one entry in MA1a (i.e. $num = 1)
		if ($ids ne 'new') {
			unless ($num == 1) {

				report ($file, "%s: Number of ids does not match the number of symbols in the corresponding %s" ."1a symbol field:\n!%s", $code, $proforma_type, $context);
				return ();
			}
		}


	}

	foreach my $id (dehash ($file, $code, $num, $ids)) {
		$id = trim_space_from_ends ($file, $code, $id);

		push @id_list, $id;				# Store id for posterity.


# this if loop will catch empty entries in a hashed-list, required on top of earlier test for entire field being empty,
# so that cases where an entry is missed out in the middle of a hashed list are caught.

		if ($id eq '') {

					report ($file, "%s: Empty value in hashed list\n!%s", $code, $context);

		} elsif ($id =~ m/^(($id_types)\d{7,})|(new)$/) {

			unless ($id =~ m/^new$/) {

				unless (valid_symbol ($id, 'uniquename')) {
					report ($file, "%s: '%s' is not a valid id in Chado.", $code, $id);
				}
			}

		} else {
		
			if ($id =~ m|^FB[a-z]{2}[0-9]{7,}$|) {
				report ($file, "%s: FBid '%s' is not of the expected type" . ($#{$standard_symbol_mapping->{$proforma_type}->{id}} > 0 ? "s" : '') . " (%s) for this field.", $code, $id, (join '\', \'', @{$standard_symbol_mapping->{$proforma_type}->{id}}));
			} else {
				report ($file, "%s: '%s' is not a valid FBid format:\n!%s", $code, $id, $context);
			}
		}
    }



	return @id_list;
}

sub single_line {
# Test whether field data is on a single line and issue a warning if not.
# Also returns 1 if true (single line) and 0 if false, as its often useful
# to know the result of the test in the section of code that calls the subroutine.

    my ($file, $code, $data, $context) = @_;
	if (index ($data, "\n") >= 0) {
		report ($file, "%s: Multiple values NOT allowed:\n!%s", $code, $context);
		return 0;
	}
	return 1;
}


sub contains_data {
# Test whether a field contains data and issue a warning if it is empty.
# Also returns 1 if true (field does contain data) and 0 if false, as its often useful
# to know the result of the test in the section of code that calls the subroutine.

    my ($file, $code, $data, $context) = @_;

	if ($data eq '') {
		report ($file, "%s: Empty field\n!%s", $code, $context);
		return 0;
	}

	return 1;

}


sub cross_check_harv_style_symbol_rename_merge_fields {

# This subroutine cross-checks the following fields of a harvard-style proforma,
# to check that the combination of fields filled in and their values is correct.
# Cross-checks
# the primary FBid field: x1f
# the primary symbol field: x1a
# the rename field: x1c
# the merge field: x1g
# The subroutine should be called once the entire proforma has been parsed,
# so that the contents of all the checked fields will have already been gathered.
#
# $file = curation record
# $proforma_type = type of proforma being checked - use the letter prefix of the proforma eg. MA, MS, TE
# $num = number of entries in the primary symbol field of the proforma
# $FBid_list = dehashed primary FBid list
# $symbol_list = dehashed primary symbol list
# $rename_list = dehashed rename list (symbol(s))
# $merge_list = dehashed merge list (FBid(s))
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages
#
# call as e.g. cross_check_harv_style_symbol_rename_merge_fields ($file, 'MA', $hash_entries, \@FBti_list, \@TI_sym_list, \@MA1c_list, \@MA1g_list, \%proforma_fields);

    my ($file, $proforma_type, $num, $FBid_list, $symbol_list, $rename_list, $merge_list, $context) = @_;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR - Please let Gillian know the following, so that it can be fixed:\ncross_check_harv_style_symbol_rename_merge_fields subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field, but the variable has no information about that type of proforma.",$proforma_type);
		return ();
	}

	my $id_types = join '|', @{$standard_symbol_mapping->{$proforma_type}->{id}};

	my $primary_symbol_field = exists $standard_symbol_mapping->{$proforma_type}->{primary_field} ? ($proforma_type . $standard_symbol_mapping->{$proforma_type}->{primary_field}) : ($proforma_type . "1a");

	my $primary_id_field = exists $standard_symbol_mapping->{$proforma_type}->{primary_id_field} ? ($proforma_type . $standard_symbol_mapping->{$proforma_type}->{primary_id_field}) : ($proforma_type . "1f");


	my $merge_field = exists $standard_symbol_mapping->{$proforma_type}->{merge_field} ? ($proforma_type . $standard_symbol_mapping->{$proforma_type}->{merge_field}) : ($proforma_type . "1g");

	my $rename_field = exists $standard_symbol_mapping->{$proforma_type}->{rename_field} ? ($proforma_type . $standard_symbol_mapping->{$proforma_type}->{rename_field}) : ($proforma_type . "1c");

# Only attempt the checks if the number of items in both $symbol_list and $FBid_list is the same.
	if ($num and $#{$symbol_list} + 1 == $num and $#{$FBid_list} + 1 == $num) {

# go through each symbol/FBid pair at a time and run the cross-checks with the other fields

		for (my $i = 0; $i < $num; $i++) {

# if the value in the primary FBid field is an FBid number
			if ($FBid_list->[$i] =~ m/^($id_types)[0-9]{7,}$/) {

# merge field must be empty (this means there is no need to worry about whether the merge field is present at all in the proforma,
# since if its not there, by definition it must be empty !)
				if ($merge_list->[$i]) {
					report ($file, "%s must be empty if %s contains an FBid number\n!%s\n!%s", $merge_field, $primary_id_field ,$context->{$primary_id_field},$context->{$merge_field});
				}


# test whether rename field is empty or not
# if rename field is filled in
				if ($rename_list->[$i]) {

# check that the FBid *in chado* of the symbol in the rename field matches the FBid given in the primary FBid field
					my $chado_id = valid_chado_symbol_of_list_of_types ($rename_list->[$i], $standard_symbol_mapping->{$proforma_type}->{id});

					unless ($chado_id eq $FBid_list->[$i]) {
						report ($file, "Symbol-ID mismatch in rename: the FBid given in %s (%s) does not match the symbol given in %s (%s):\n\n!%s\n!%s", $primary_id_field, $FBid_list->[$i], $rename_field, $rename_list->[$i], $context->{$primary_id_field},$context->{$rename_field});
					}

# check that the value in the primary symbol field is NOT a valid symbol in chado
					if (valid_chado_symbol_of_list_of_types ($symbol_list->[$i], $standard_symbol_mapping->{$proforma_type}->{id})) {

						report ($file, "%s: Rename to an existing chado symbol ('%s') is not allowed. (You need to choose another symbol, or perhaps you meant to fill in the merge field instead of the rename field?):\n\n!%s\n!%s\n!%s", $primary_symbol_field, $symbol_list->[$i],$context->{$primary_id_field},$context->{$primary_symbol_field},$context->{$rename_field});

					}

# check that the value in the primary symbol field and in the rename field are not the same

				if ($symbol_list->[$i] eq $rename_list->[$i]) {
				    report ($file, "Conflict between %s and %s --- '%s' can not be present in both fields.", $primary_symbol_field, $rename_field, $symbol_list->[$i]);
				}


# if the rename field is empty (again, no need to worry about if the field is completely missing from the proforma, since if
# its not there, by definition it must be empty !)
				} else {

					my $chado_id = valid_chado_symbol_of_list_of_types ($symbol_list->[$i], $standard_symbol_mapping->{$proforma_type}->{id});

# check that the value in the primary symbol field is a valid symbol in chado
					unless ($chado_id) {

						report ($file, "%s: '%s' is not a valid %s symbol in chado\n!%s",$primary_symbol_field, $symbol_list->[$i], $standard_symbol_mapping->{$proforma_type}->{type}, $context->{$primary_symbol_field});

					} else {
# if the symbol is valid, check that its FBid *in chado* matches the FBid given in the primary FBid field
						unless ($chado_id eq $FBid_list->[$i]) {
							report ($file, "Symbol-ID mismatch: the FBid given in %s (%s) does not match the symbol given in %s (%s):\n\n!%s\n!%s", $primary_id_field, $FBid_list->[$i], $primary_symbol_field, $symbol_list->[$i], $context->{$primary_id_field},$context->{$primary_symbol_field});
						}
					}

				}

# if the value in the primary FBid field is 'new'
			} elsif ($FBid_list->[$i] =~ m|^new$|) {


# rename field must be empty (this means there is no need to worry about whether rename field field is present in the proforma
# at all, since if its not there, by definition it must be empty !)
				if ($rename_list->[$i]) {

					report ($file, "%s must be empty if %s contains 'new'\n!%s\n!%s",$rename_field,$primary_id_field,$context->{$primary_id_field},$context->{$rename_field});
				}



# test whether the merge field is empty or not
# if the merge field is filled in

				if ($merge_list->[$i]) {

# check whether the value in the primary symbol field is valid in chado, if it is, the corresponding FBid in chado should match one of the entries in merge field

					my $chado_id = valid_chado_symbol_of_list_of_types ($symbol_list->[$i], $standard_symbol_mapping->{$proforma_type}->{id});

					if ($chado_id) {

						my $match = 0; # counter to see if find a match

						foreach my $merge_id (@{$merge_list->[$i]}) {
							if ($merge_id eq $chado_id) {
								$match++;
							}
						}

						unless ($match) {

							report ($file, "Symbol-ID mismatch in merge: The symbol '%s' in %s is already in chado, but none of the FBids in %s correspond to its FBid. (You need to check that the FBids are correct and/or choose a new symbol):\n\n!%s\n!%s", $symbol_list->[$i], $primary_symbol_field, $merge_field, $context->{$primary_symbol_field}, $context->{$merge_field});
						}


					}
				


# if the merge field is empty (again, no need to worry about if the field is completely missing from the proforma, since if
# its not there, by definition it must be empty !)
				} else {

					my $chado_id = valid_chado_symbol_of_list_of_types ($symbol_list->[$i], $standard_symbol_mapping->{$proforma_type}->{id});

# check that the value in the primary symbol field is NOT a current symbol in chado
					if ($chado_id) {

						report ($file, "%s claims that %s is not an existing %s symbol, but Chado knows it as %s", $primary_id_field, $symbol_list->[$i], $standard_symbol_mapping->{$proforma_type}->{type}, $chado_id);

					}

				}

# don't think the following loop should ever be tripped, as don't think $symbol_list and $FBid_list will be populated unless there is an equal number of items in each, but just in case
			} else {

				report ($file, "%s: '%s' is not of expected format in\n!%s", $primary_id_field, $FBid_list->[$i], $context->{$primary_id_field});

			}


		}
	}
}

sub validate_synonym_field {
# converted to process_field_data + %field_specific_checks format. 140627.

# This subroutine validates any synonym field.  It can be used for all types of proforma (ie. both 'Cambridge' and 'Harvard' style).
# It:
# 1. uses 'check_for_duplicated'_lines to check that there are no duplicated synonyms and no empty lines (empty lines cause problems in proforma loading into the db, and the problems are hard to identify as there is no error in the parsing log files).
# 2. For the G1b and G2b fields, it also checks that none of the synonyms correspond to antibody information (as it is a common error to mislocate the antibody information in the neighbouring G1b and G2b fields of the gene_mini.pro).

# The arguments are:
# $file = curation record
# $code = proforma field code
# $synonym_list = dehashed contents of a proforma field containing synonyms, without proforma field text
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages

    my ($file, $code, $synonym_list, $context) = @_;

    $synonym_list eq '' and return;			# Absence of data is permissible.


	if (valid_symbol ($file, 'curator_type') eq 'USER' || valid_symbol ($file, 'curator_type') eq 'AUTO') {

		report ($file, "%s: Synonym field must not be filled in for %s-curated proformae.\n!%s",$code,valid_symbol ($file, 'curator_type'),$context->{$code});

	}

# include check_for_duplicated_lines so that subroutine works for both single and multiple line fields
	my $uniqued_synonyms = check_for_duplicated_lines($file,$code,$synonym_list,$context->{$code});

	foreach my $synonym (keys %{$uniqued_synonyms}) {

		if ($code eq "G1b" || $code eq "G2b") {

			if (valid_symbol ($synonym, 'antibody')) {
				report ($file, "Antibody term '%s' present in %s field (are you sure they called the gene that ?):\n%s\n%s", $synonym, $code, $context->{'G1a'}, $context->{$code});
			}
		}

# check that the synonym is not just made up of punctuation
		if($synonym=~ m/^[[:punct:]]+$/) { # 
			report ($file, "%s: synonym '%s' consists only of punctuation character(s) (are you sure they called it that ?).", $code, $synonym);

		}
	}
}


sub check_valid_symbol_field {
# converted to process_field_data + %field_specific_checks format. 140627.
# NOTE: the check_valid_symbol_field and validate_cvterm_field subroutines are basically
# doing the same thing - which is checking that a field only contains values from defined
# list(s) of symbols/terms, by calling 'valid_symbol_of_list_of_types' which just returns true
# if the value given is a valid 'symbol' in any of the type(s) allowed for that field.
# In this instance 'symbol' means a valid entry in the %symbol_table populated by symtab.pl,
# so it doesn't just mean 'symbols' as in gene symbol, allele symbol etc, it also means
# valid cvterms from an ontology or values stored in symtab.pl.
# The two subroutines could be merged, but kept separate for now so that its easier to have
# more helpful error messages, since curators think of 'symbol' as just meaning things like
# gene symbol, allele symbol etc.

# The arguments are:
# $file = curation record
# $code = proforma field code
# $symbol_list = dehashed contents of a proforma field containing valid symbols, without proforma field text
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages

	my ($file, $code, $symbol_list, $context) = @_;

# each the key is a proforma field code and the value is a reference to an array containing the list of id types (e.g. FBtp, FBmc, FBms) that are allowed in that field
	my %allowed_types = (

		'A6' => ['FBal', 'FBti', 'FBab', 'FBtp'],
		'A23' => ['FBab'],
		'A7a' => ['FBgn'], 'A7b' => ['FBgn'], 'A7c' => ['FBgn'], 'A7d' => ['FBgn'], 'A7e' => ['FBgn'], 'A7f' => ['FBgn'],
		'A25a' => ['FBgn'], 'A25b' => ['FBgn'], 'A25c' => ['FBgn'], 'A25d' => ['FBgn'], 'A25e' => ['FBgn'], 'A25f' => ['FBgn'],
		'A24a' => ['FBti'],

		'MA4' => ['FBtp', 'FBte'],
		'MA15a' => ['FBti'], 'MA15b' => ['FBti'], 'MA15c' => ['FBti'], 'MA15d' => ['FBti'],
		'MA5d' => ['FBgn'],
		'MA21c' => ['FBte'],
		'MA7' => ['FBab'],
		'MA12' => ['FBal'],
		'MA14' => ['FBba'],
		'MA18' => ['FBti'],
		'MA23a' => ['FBgn'],

		'MS4h' => ['FBal'],
		'MS19a' => ['FBtp', 'FBmc'],
		'MS19c' => ['FBte'],
		'MS19d' => ['FBcl'],
		'MS19e' => ['FBgn'],
		'MS20' => ['FBtp', 'FBmc'],
		'MS21' => ['FBte'],
		'MS24' => ['FBal'],

		'AB9' => ['FBab', 'FBba'],
		'AB5a' => ['FBti'],

		'GA11' => ['FBal', 'FBti', 'FBab', 'FBtp'],

		'G7a' => ['FBgn', 'FBti'],
		'G7b' => ['FBgn', 'FBti'],
		'G37' => ['FBgg'],


		'GG7a' => ['FBgg'],
		'GG7c' => ['FBgg'],

		'P30' => ['FBrf'],
		'P31' => ['FBrf'],
		'P32' => ['FBrf'],

		'TE8' => ['FBgn'],

		'F17' => ['FBal'],

		'G91' => ['FBlc'],
		'GA91' => ['FBlc'],
		'A30' => ['FBlc'],
		'MA30' => ['FBlc'],
		'MS30' => ['FBlc'],
		'F91' => ['FBlc'],

		'LC3' => ['FBlc'],
		'LC14b' => ['FBlc'],
		'LC14d' => ['FBlc'],
		'LC14e' => ['FBlc'],
		'LC14f' => ['FBlc'],
		'LC14g' => ['FBlc'],
		'LC12a'=> ['FBgn'],

		'IN4' => ['FBlc'],

		'F11' => ['FBgn'],
		'IN5a' => ['FBtc'],
		'LC4e' => ['FBtc'],
		'LC4h' => ['FBsn'],

		'TC4a' => ['FBtc'],
		'TC8' => ['FBlc'],

		'TO7a' => ['FBto'],
		'TO7b' => ['FBto'],
		'TO7c' => ['FBgn'],

		'GA30a' => ['FBto'],
		'GA30b' => ['FBto'],
		'GA30c' => ['FBto'],
		'GA30e' => ['FBgn', 'FBto'],

		'MS14a' => ['FBto'],
		'MS14b' => ['FBto'],
		'MS14c' => ['FBto'],
		'MS14e' => ['FBgn', 'FBto'],

		'MS23' => ['FBal'],

	);

	unless ($allowed_types{$code}) {
		report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\ncheck_valid_symbol_field does not contain an entry in the allowed_types hash for the '%s' field, please fix.",$code,$code);
		return;
	}



    $symbol_list eq '' and return;			# Absence of data is permissible.


# include check_for_duplicated_lines so that subroutine works for both single and multiple line fields
	my $uniqued_symbols = check_for_duplicated_lines($file,$code,$symbol_list,$context->{$code});

	foreach my $symbol (keys %{$uniqued_symbols}) {

		if ($code =~ /^P[0-9]{1,}/) {

			valid_symbol_of_list_of_types ($symbol, $allowed_types{$code}) or report ($file, "%s: Invalid %s id '%s':\n!%s", $code, (join ', ', @{$allowed_types{$code}}), $symbol, $context->{$code});

		} else {
			valid_symbol_of_list_of_types ($symbol, $allowed_types{$code}) or report ($file, "%s: Invalid symbol '%s' (only symbols of type" . ($#{$allowed_types{$code}} > 0 ? "s" : '') . " '%s' are allowed):\n!%s", $code, $symbol, (join '\', \'', @{$allowed_types{$code}}), $context->{$code});
		}
	}
}

sub check_insertion_symbol_format {


# subroutine to check basic format of an insertion (i.e. FBti) symbol.
# Used when checking new insertion symbols in either MA1a (for new insertions of renames of existing ones)
# or insertions instantiated in GA10c/GA10e (ie. when prefixed with 'NEW:').
# Because it can be used in the GA10 fields which are not primary proforma fields, need to
# keep check_allowed_characters and check for malformed greek in this subroutine (or would
# need to add it in appropriate place in GA10 field checking)
# Designed to check one symbol at a time, since the format of the MA1a vs GA10c/GA10e fields differs, 
# so should be used after data has been dehashed.

# The input arguments are:
# $file = curation record
# $code = proforma field code
# $insertion = insertion symbol to check
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages



# returns:
# $inserted_element - the string used in the original symbol to describe the inserted element, may be empty if the insertion has incorrect format
# $identifier - the identifier portion of the insertion (ie. after the last '}') - may be empty if the identifier is missing or the insertion has incorrect format
# $full_symbol_of_inserted_element
# - for insertions of transgenic constructs (FBtp), will either be the FBtp symbol, i.e. the same as $inserted_element (if it is a valid FBtp symbol) or empty (if it is not a valid FBtp symbol).
# - for insertions of natTE, will either be the full symbol of that natTE (this may be the same as $inserted_element if the original symbol included the full symbol, OR it may be different, if the original symbol used a shorthand for a natTE) or empty (if an invalid symbol or shorthand was used).


	my ($file, $code, $insertion, $context) = @_;

	my ($inserted_element, $identifier, $full_symbol_of_inserted_element);

# hash containing fields where we don't want to do full checking because its not a primary symbol field
# that can assign a valid symbol to an insertion, but we want to use this subroutine to split insertion 
# symbol into component parts for other checks.
# This is to prevent false-positive error messages because there are occasions when it is legitimate for
# the insertion symbol in a non-primary symbol field to have an invalid construct symbol as part of its
# symbol (e.g. when renaming an insertion of a construct, when the construct symbol was changed the previous epicycle).
	my %shortcut = (
		'MA1c' => '1', # insertion renaming field

	);

	unless ($shortcut{$code}) {
		check_allowed_characters($file,$code,$insertion,$context->{$code});
	}
	while ($insertion =~ /(&.*?;)/g)
	{
		valid_greek($1) or report ($file, "%s: Malformed Greek symbol %s in %s.", $code, $1, $insertion);
	}

# First see if the insertion can be divided into an "$inserted_element" and a "$identifier" portion	
	if (($inserted_element, $identifier) = ($insertion =~ m/^([^{}]{1,}\{[^{}]{0,}\})(.*)$/)) {

		if ($shortcut{$code}) {
			return ($inserted_element, $identifier, $full_symbol_of_inserted_element);

		}

# check "$identifier" portion
		if ($identifier) {
			if (my ($allele) = ($identifier =~ m/(.+\[.+\])$/)) {
				unless (valid_symbol ($allele, 'FBal')) {
	    			report ($file, "%s: The identifier portion '%s' of the symbol '%s' matches allele format, but is not a valid allele symbol.", $code, $allele, $insertion);
				}
			}

		} else {
			report ($file, "%s: symbol given, '%s', is missing an identifier portion.", $code, $insertion);
		}

# Second determine whether the $inserted_element looks like an insertion of a natTE (FBte) or of a transgenic construct (FBtp)

# insertion of natTE (FBte)
		if ($inserted_element =~ m/.+\{\}$/) {

# remove the trailing {}
			$inserted_element =~ s/{}$//;

			$full_symbol_of_inserted_element = check_natTE_end ($file, $code, $inserted_element, $insertion, 'insertion');


# insertion of transgenic construct (FBtp)
		} else {

			unless (valid_symbol ($inserted_element, 'FBtp')) {

	    		report ($file, "%s: The construct portion '%s' of the symbol '%s' is not a valid construct.", $code, $inserted_element, $insertion);


			}

			$full_symbol_of_inserted_element = $inserted_element;
		}

	} else {

		report ($file, "%s: Invalid insertion symbol format '%s' in\n!%s", $code, $insertion, $context->{$code});

	}

	return ($inserted_element, $identifier, $full_symbol_of_inserted_element);

}

sub check_natTE_end {

# subroutine to check the symbol used to indicate:
# i. the inserted natTE element in an insertion of a natural transposon. 
# In this case it checks that the 'end' symbol is either a valid natTE symbol (drosophilid only)
# or a valid shorthand for a natTE (drosophilid only).
#
# or
#
# ii. the origin of the ends of an FBtp construct.
# In this case it checks that the 'end' symbol is either a valid natTE symbol (drosophilid plus foreign natTE such as Tni\piggyBac)
# or a valid shorthand for a natTE (drosophilid plus foreign natTE such as PBac)
#
# It also warns if a full natTE symbol is used, but a shortcut is available.
#
# Designed to check one symbol at a time, so should be used after data has been dehashed.


# The input arguments are:
# $file = curation record
# $code = proforma field code
# $end = symbol used to indicate either the inserted natTE element (the bit before the {}) or the origin of the ends of the FBtp construct (the bit before the first '{')
# $symbol = symbol context in which the end appears (used to make more helpful error messages).  i.e. the whole FBtp or insertion symbol.
# $type = type of end being checked - 'insertion' where the inserted natTE element of an insertion is being checked, 'construct' where the ends of an FBtp construct are being checked

# returns the value of the $nat_te variable as follows:
# if $end corresponds to either a valid FBte symbol or a valid natTE shorthand, $nat_te = full symbol of natTE from which the ends come from
# otherwise, $nat_te = ''

	my ($file, $code, $end, $symbol, $type) = @_;

	my $nat_te;

# if the end is not a valid natTE symbol, check if its one of the allowed natTE shorthands e.g, P for P{}
	unless (valid_symbol ($end, 'FBte')) {

# if the end is a valid shorthand, store the full symbol in $nat_te
		if ($nat_te = valid_symbol ($end, "$type" . "_natTE_shorthand_to_full")) {


# unless the shorthand is 'TI',
# if the full symbol of the shorthand is no longer valid in chado, report as an error that needs fixing in Peeves itself
			unless ($end eq 'TI' || (valid_symbol ($nat_te, 'FBte'))) {

				report ($file,"MAJOR PEEVES ERROR, please let Gillian know the following, so that Peeves can be fixed:\nsymbol '%s' for the natTE shorthand '%s' is no longer a valid natTE in chado, the \$valid_natTE_shorthand in symtab.pl needs updating with the current value.", $nat_te, $end);

			}

# otherwise report the error
		} else {

			unless ($end eq '?') {
				report ($file, "%s: The natural transposon portion '%s' of the symbol '%s' is not a valid natural transposon.", $code, $end, $symbol);

			}
		}


	} else {

# check whether a full symbol used as a construct end has a shorthand and report if so
		if (valid_symbol ($end, "$type" . "_natTE_full_to_shorthand")) {

			report ($file, "%s: You used the string '%s' to describe the transposable element%spresent in '%s', but in this context the '%s' natTE has the valid shorthand '%s' which should be used instead.", $code, $end, ($type eq 'construct' ? " ends " : " "), $symbol, $end, valid_symbol ($end, "$type" . "_natTE_full_to_shorthand"));


		}

		$nat_te = $end;

	}


	return $nat_te;
}


sub check_construct_symbol_format {

# subroutine to check basic format of a transgenic construct (i.e. FBtp) symbol.

# Designed to check one symbol at a time, since the format of the MS1a vs GA10a fields differs, 
# so should be used after data has been dehashed.

# It is also designed to check what is considered to be a genuine construct symbol, so if it
# is checking a symbol entered into GA10a, any 'NEW:' should have been removed before passing
# the symbol to the subroutine, and if it is checking a construct that is part of an insertion
# symbol, the construct portion only should be passed.
# Because it can be used in the GA10a field which is not a primary proforma field, need to
# keep check_allowed_characters and check for malformed greek in this subroutine (or would
# need to add it in appropriate place in GA10a field checking)
# The input arguments are:
# $file = curation record
# $code = proforma field code
# $construct = construct symbol to check
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages

# returns the value of the $nat_te variable as follows:
# if the symbol used to indicate the origin of the ends of the FBtp construct (the bit before the first '{') corresponds to either a valid FBte symbol or a valid natTE shorthand, $nat_te = full symbol of natTE from which the ends come from
# otherwise, $nat_te = ''

	my ($file, $code, $construct, $context) = @_;

	my $nat_te;

	check_allowed_characters($file,$code,$construct,$context->{$code});

	while ($construct =~ /(&.*?;)/g)
	{
		valid_greek($1) or report ($file, "%s: Malformed Greek symbol %s in %s.", $code, $1, $construct);
	}


	if ($construct =~ /^([^{}]{1,})\{([^{}]{1,})\}$/) {
			
		$nat_te = check_natTE_end ($file, $code, $1, $construct, 'construct');

	} else {

		report ($file, "%s: '%s' doesn't look much like a FBtp symbol to me\n\! %s", $code, $construct, $context->{$code});

	}


	return $nat_te;

}


sub check_filled_in_for_new_feature {

# subroutine to check the requirements for a field being filled in against whether or not the feature is new.
# All field data passed in to this subroutine must be dehashed and passed as a reference.

# $file = curation record
# $code = proforma field code
# $num = number of entries in the primary symbol field of the proforma
# $data = reference to array containing dehashed data being checked
# $status_data = reference to array containing dehashed data from the 'status' field (x1g for 'cam' style proformae, x1f for 'harv' style proformae
# $rename_list = reference to array containing dehashed data from the rename field (x1e for 'cam' style proformae, x1c for 'harv' style proformae)
# $merge_list = reference to array containing dehashed data from the merge field (x1f for 'cam' style proformae, x1g for 'harv' style proformae)
# $context = reference to %proforma_fields hash so can provide context for error
# $test: 'yes' if the field MUST be filled in for a new feature (regardless of whether or not it is filled in for an existing feature), 'only' if the field MUST be filled in for a new feature AND MUST NOT be filled in for an existing feature, 'advised' if its good to try and fill it in for a new feature (regardless of whether or not it is filled in for an existing feature)

	my ($file, $code, $num, $data, $status_data, $rename_list, $merge_list, $context, $test) = @_;

# work out what type of proforma is being checked
	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{0,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\ncheck_filled_in_for_new_feature subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$proforma_type,$code);
		return;
	}

	($test eq 'yes' || $test eq 'only' || $test eq 'advised') or report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\ncheck_filled_in_for_new_feature subroutine has been called using the test value of '%s' which is not implemented - either fix the subroutine call, or add the new type of test condition.", $code, $test);


# different proforma styles have a different string for indicating a 'new' symbol
	my $proforma_style = $standard_symbol_mapping->{$proforma_type}->{style};
	my $new_string = $proforma_style eq 'Cambridge' ?'n' : 'new';



#	if ($num and $#{$data} + 1 == $num) {
	if ($num) {

		for (my $i = 0; $i < $num; $i++) {

# first check that status_data exists for this hash element (needed to avoid error message in terminal)
			if ($status_data->[$i]) {
# if its a new feature
				if ($status_data->[$i] eq $new_string && !$rename_list->[$i] && !$merge_list->[$i]) {

					if ($test eq 'yes' || $test eq 'only') {

# issue a warning if the data field is not filled in for those fields which must be filled in for new features
						unless ($data->[$i]) {

							report ($file, "%s must be filled in for a new %s:\n!%s\n!%s", $code, $standard_symbol_mapping->{$proforma_type}->{type}, $context->{"$proforma_type" . "1a"}, exists $context->{$code} ? $context->{$code} : '');

						}

# location dependent checking - stricter requirement for curation done at the site which matches the proforma style
					} elsif ($test eq 'advised') {

						unless ($data->[$i]) {

							if ($proforma_style eq valid_symbol ('Where_running', '_Peeves_')) {

								report ($file, "%s must be filled in for a new %s:\n!%s\n!%s", $code, $standard_symbol_mapping->{$proforma_type}->{type}, $context->{"$proforma_type" . "1a"}, exists $context->{$code} ? $context->{$code} : '');

							}

						}
					}

				} else {

					if ($test eq 'only') {

						if ($data->[$i]) {

							report ($file, "%s must not be filled in for an existing %s:\n!%s\n!%s", $code, $standard_symbol_mapping->{$proforma_type}->{type}, $context->{"$proforma_type" . "1a"}, exists $context->{$code} ? $context->{$code} : '');


						}

					}
				}
			}
		}
	}
}


sub process_field_data {

# subroutine that does the common basic checks required for a field that does not always have to be filled in.
# The basic checks are:
# 1. plingc checks - using the 'changes' subroutine (uses $change_status variable to determine
# whether or not !c is allowed for the field:
# ($change_status = '0' if !c not allowed, $change_status = '1' if !c is allowed).
# 2. checks that the data is a single line for those fields where only a single line is allowed
# ($single_status = '0' if multiple lines are allowed, $single_status = '1' if only a single line is allowed).
# 3. uses the 'dehash' subroutine to check that the number of hash elements in the field is compatible
# with the number of symbols in the primary symbol field of the proforma.


# If the data is successfully dehashed, it is
# a. checked for whitespace at the beginning/end using 'trim_space_from_ends' subroutine,
# b. passed on to another subroutine (using the %field_specific_checks hash) for field-specific checking,
# c. returned, so that it can be stored for checks that have to happen once the entire proforma is parsed.

# Note that the data is dehashed, but is not further split on \n (even if the field can contain multiple data),
# so that the passed on/returned data is in the form of an array, each item corresponding to the entire
# field data for that hash element.  This consistent format makes it easier to do end-of-proforma checks 
# involving presence/absence of data in the field, regardless of the single/multiple nature of the data.
# When the individual lines in the returned/passed on data need to be checked, they can be split on '\n
# at that point to carry out the checking.

# If the field is COMPLETELY empty, the subroutine returns early, before the dehash, returning an array
# of '' entries (with the number of entries in the array matching the number of hash entries in the primary
# symbol field of the proforma), so that the format of the returned data is consistent with what happens when
# the field contains data.


# Outline of dataflow:
# dehash data
# only do the processing if dehash found the correct number of hash entries,
# go through each hash element in turn, and:
# 1. remove whitespace and warn if errors
# 2. pass each hash element to appropriate subroutine for field-specific data checks
# 3. add hash element to return list


# Input variables
# $file = curation record filename
# $num = number of hash entries in the primary symbol field of the proforma
# $code = proforma field being checked
# $data = entire contents of proforma field, without proforma field text
# $change = data between the ! of the proforma field text and the proforma field code
# $change_status = '0' if !c not allowed or '1' if !c is allowed and '2' if !c is compulsory (rare case)
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages
# $single_status = '0' if multiple lines are allowed, or '1' if only a single line is allowed in the field


	my ($file, $num, $change, $change_status, $code, $data, $context, $single_status) = @_;

	my %specific_change_messages = (

		'GA10b' => ', if you need to correct synonyms for a construct, use the moseg.pro instead',
		'GA10d' => ', if you need to correct synonyms for an insertion, use the ti.pro instead',
		'GA10f' => ', if you need to correct synonyms for an insertion, use the ti.pro instead',
		'MA7'  => 'aberration ',
		'MA14'  => 'balancer ',
		'MA12'  => 'allele ',
		'P19' => ' for a new publication',
		'P30' => ' for a new publication',
		'P31' => ' for a new publication',

	);


# field codes for which it is safe to trim the leading return and for which curators (mostly HarvCur)
# are in the habit of starting with a return
	my %safe_to_trim_return = (
		'F9' => '1',
		'IN6' => '1',
		'IN7c' => '1',
		'IN7d' => '1',
	);

	my @return_list = ();

	unless ($change_status == 1 || $change_status == 0 || $change_status == 2) {

		report ($file,"***MAJOR PEEVES ERROR***, no checking will be done until this is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nprocess_field_data has been called using the 'change_status' value of '%s', the subroutine call needs fixing as this must have a value of either '0', '1' or '2'.", $change_status);
		return;

	}
	unless ($single_status == 1 || $single_status == 0) {

		report ($file,"***MAJOR PEEVES ERROR***, no checking will be done until this is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nprocess_field_data has been called using the 'single_status' value of '%s', the subroutine call needs fixing as this must have a value of either '0' or '1'.", $single_status);
		return;
	}

	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{0,}$||;


	if ($change_status) {
		changes ($file, $code, $change);		# Check for garbage between the ! and proforma field code,
                                                # but otherwise don't worry about $change.
	} else {
		changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field%s:\n!%s", $code, $specific_change_messages{$code} ? $specific_change_messages{$code} : '', $context->{$code});
	}


# if the field is completely empty, return early, but return the number of elements corresponding
# to the number of items in the primary symbol field, so that this is consistent with what dehash
# does when there IS data.  Think that this will make checks done once the entire proforma is checked
# more robust [gm140626]
	return ('') x $num if (!defined $data or $data eq '');

	if ($change_status == 2) {
		changes ($file, $code, $change) or report ($file, "%s: This field should only be used to correct existing data (see curation manual for details).  To submit new data use the appropriate %sproforma field.\n!%s", $code, $specific_change_messages{$code} ? $specific_change_messages{$code} : '', $context->{$code});

	}

# check for basic errors in character formatting		
	check_non_utf8 ($file, $code, $data);

# do not do the non_ascii check for publication fields since they may legitimately contain things
# like umlauts
	unless ($standard_symbol_mapping->{$proforma_type}->{type} eq 'publication' || $code eq 'G39d') {
		check_non_ascii ($file, $code, $data);
	}
# check for '??' and return if they are present
	double_query ($file, $code, $data) and return;

	if ($single_status) {
		single_line ($file, $code, $data, $context->{$code}) or return; # return at this point
                                                              # otherwise the data goes through
                                                              # to field checking, which results
                                                              # in confusing error messages
	}


	my @dehashed_data = dehash ($file, $code, $num, $data);

	if (@dehashed_data) {

	    for (my $i = 0; $i < $num; $i++) {


# removing leading return for those fields where this is allowed and curators are in the habit
# of starting with an empty line (mostly HarvCur fields). Doing it here means it will remove
# the leading return of each dehashed element

			if ($safe_to_trim_return{$code}) {
				$dehashed_data[$i] = trim_leading_return ($code, $dehashed_data[$i]);
			}

			$dehashed_data[$i] = trim_space_from_ends ($file, $code, $dehashed_data[$i]);

			if (defined $field_specific_checks{$code}) {
# Only perform field specific checks if they are required.
# If no specific checks are required, the field will be a key
# in the %field_specific_checks hash, with the value of ''
				if ($field_specific_checks{$code}) {
					$field_specific_checks{$code}->($file, $code, $dehashed_data[$i], $context);
				}
			} else {

# If the field is not a key in the %field_specific_checks hash, print a warning
# in case the required checks were omitted by mistake. 
				warn "No field-specific checks implemented for $code.\n";
			}

			push @return_list, $dehashed_data[$i];


		}
	}

	return @return_list;

}


sub compare_field_pairs {


# compare_field_pairs compares a pair of fields for presence/absence/identity
# and reports errors depending on value of test variable passed as argument.
# It is simply a wrapper so that each corresponding hash entry in a pair of fields
# can be passed to the compare_pairs_of_data subroutine (which checks a single pair
# of data at a time) for those field pairs where this easy shortcut is possible.
# field1: a # b # c
# field2: x # y # z
# compare_field_pairs will pass a and x to compare_pairs_of_data for checking, then b and y, then c and z.
# $num = number of entries in the primary symbol field of the proforma
# $data1 = reference to array containing dehashed field entry
# $data2 = reference to array containing dehashed field entry
# ie. the data passed for checking using $data1 and $dataq should have already been dehashed
# and stored as an array (eg. an array generated by process_field_data).
# For all other arguments, see compare_pairs_of_data subroutine for details.
# compare_pairs_of_data can also be used directly (i.e. not via compare_field_pairs) to compare a single
# hash entry pair between two fields (e.g. just a and x above), if the checking requirements need it
# (eg. when the requirement for how the field is filled in depends on a third field or when the value
# in one field affects the requirement for presence/absence in the second field.

# NB. for the $identity test, this wrapper (and the compare_pairs_of_data sub it calls)
# can only cope with testing multiple line fields if you are testing whether or not the
# two fields are *completely* identical across all lines of data in each field.
# If you need to check that a single value (out of a possible many) in one of the fields is not present in
# the other field you should use compare_multiple_line_fields_negative.

	my ($file, $num, $code1, $data1, $code2, $data2, $context, $pair_test, $identity_test) = @_;

	for (my $i = 0; $i < $num; $i++) {

		compare_pairs_of_data ($file, $code1, $data1->[$i], $code2, $data2->[$i], $context, $pair_test, $identity_test);

	}
}

sub compare_pairs_of_data {


# compare_pairs_of_data subroutine compares a pair of data entries for presence/absence/identity
# and reports errors depending on value of test variable passed as argument.

# For the $pair_test, it can cope with both single line data and data composed of multiple lines
# of single line data (eg. symbols, CV lines).

# For the $identity test, it can only cope with testing multiple line fields if you are testing
# whether or not the two fields are *completely* identical across all lines of data in each field.
# If you need to check that a single value (out of a possible many) in one of the fields is not present in
# the other field you should use compare_multiple_line_fields_negative.

# It is designed to compare a pair of single entries, NOT an array containing an entire dehashed list,
# ie. if two fields contain:
# field1: a # b # c
# field2: x # y # z
# compare_pairs_of_data is designed to be passed first a and x for comparison, then b and y, then c and z.
# This single pair testing is sometimes necessary when the requirement for how the field is filled in depends
# on a third field or when the value in one field affects the requirement for presence/absence in the second field.
# If you want to check a pair of arrays containing entire dehashed lists, and the test requirements are simple
# enough to allow it, you can often use the compare_field_pairs subroutine (a wrapper which passes a single pair at a time
# to the compare_pairs_of_data subroutine), rather than having to call compare_pairs_of_data directly.


# $file = curation record
# $code1 = code of field where first piece of data comes from
# $data1 = first piece of data to be compared (usually single hash entry from field)
# $code2 = code of field where second piece of data comes from
# $data2 = second piece of data to be compared (usually single hash entry from field)
# $context = reference to %proforma_fields hash so can provide context for error
# $pair_test and $identity_test are the types of test being done. If there is a specific error message
# text to add in addition to the standard ones in this subroutine), it is added to the end of
# the initial $pair_test and $identity_test value after the string '::'. 
# The specific error message is pulled out $pair_test and $identity_test test for inserting into any error
# messages, and once this has been done,
# $pair_test must be one of the following values:
# '' (ie. empty) if it doesn't matter whether or not both are filled in
# 'single' (if only one must be filled in)
# 'pair' (both fields must be filled in if either field contains data)
# 'dependent' (if field 1 is filled in, field 2 must be filled in)
# $identity_test must be one of the following values:
# '' (ie. empty) if it doesn't matter whether or not they are the same
# 'not same' (the value in each field must be different if both are filled in)
# 'same' (the value in each field must be the same if both are filled in)


	my ($file, $code1, $data1, $code2, $data2, $context, $pair_test, $identity_test) = @_;

# pull out any specific error message text from test values
	my $specific_pair_message = '';
	my $specific_identity_message = '';

	if ($pair_test =~ m|^(.+?)::(.+)$|ms) {

		$specific_pair_message = $2;
		$pair_test = $1;

	}

	if ($identity_test =~ m|^(.+?)::(.+)$|ms) {

		$specific_identity_message = $2;
		$identity_test = $1;

	}

	if ($pair_test ne '') {
		($pair_test eq 'single' || $pair_test eq 'pair' || $pair_test eq 'dependent') or report ($file,"MAJOR PEEVES ERROR, please let Gillian know the following, so that Peeves can be fixed:\ncompare_pairs_of_data subroutine has been called using the pair_test value of '%s' which is not implemented - the subroutine call needs fixing.", $pair_test);
	}
	if ($identity_test ne '') {
		($identity_test eq 'not same' || $identity_test eq 'same') or report ($file,"MAJOR PEEVES ERROR, please let Gillian know the following, so that Peeves can be fixed:\ncompare_pairs_of_data subroutine has been called using the identity_test value of '%s' which is not implemented - the subroutine call needs fixing.", $identity_test);
	}



# use defined x && ne '' in loops below to make sure accurately test cases where a hash-entry is filled in with '0'
	if (defined $data1 && $data1 ne '') {

# both code1 and code2 fields filled in
		if (defined $data2 && $data2 ne '') {

			if ($pair_test eq 'single') {
				report ($file, "%s and %s must NOT both contain data %s:\n!%s\n!%s", $code1, $code2, $specific_pair_message, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');

			}


# both entries are exactly the same
			if ($data1 eq $data2) {
				if ($identity_test eq 'not same') {

					report ($file, "%s and %s must NOT contain the same data '%s' %s\n!%s\n!%s", $code1, $code2, $data1, $specific_identity_message, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');
				}

# both entries are not exactly the same
			} else {

				my $sorted_data1 = join ('', sort (split ('\n', $data1)));
				my $sorted_data2 = join ('', sort (split ('\n', $data2)));

# if the entries are the same after splitting on \n and sorting (ie. identical multiple lines of single line data (eg. symbols, CV lines) entered in a different order)
				if ($sorted_data1 eq $sorted_data2) {


					report ($file, "%s and %s must NOT contain the same data '%s' %s\n(note that the data in the two fields is not in the same order, but it is otherwise identical)\n!%s\n!%s", $code1, $code2, $data1, $specific_identity_message, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');


				} else {
					if ($identity_test eq 'same') {

						report ($file, "%s and %s MUST contain the same data %s:\n!%s\n!%s", $code1, $code2, $specific_identity_message, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');
					}
				}

		
			}

# only code1 field filled in
		} else {


			if ($pair_test eq 'pair') {


				report ($file, "%s and %s must both contain data %s\n!%s\n!%s", $code1, $code2, $specific_pair_message, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');
			}


			if ($pair_test eq 'dependent') {


				report ($file, "%s must be filled in if %s is filled in %s\n!%s\n!%s", $code2, $code1, $specific_pair_message, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');
			}
		}

	} else {

# only code2 field filled in
		if (defined $data2 && $data2 ne '') {

			if ($pair_test eq 'pair') {
				report ($file, "%s and %s must both contain data %s\n!%s\n!%s", $code1, $code2, $specific_pair_message, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');

			}

# neither fields filled in
		} else {


		}
	}
}

sub check_genome_release {
# process_field_data + %field_specific_checks format. 140701.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{0,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\ncheck_genome_release subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$proforma_type,$code);
		return;
	}

	my $current_release = valid_symbol ('genome_release', 'current_value');

	unless ($dehashed_data eq $current_release) {

		report ($file, "%s: value given, '%s', does not correspond to the current genome release, '%s'. If the data given in the reference is not from the current release, you must convert it to the corresponding value for the current release and add an internal note explaining what you've done.\n!%s\n!%s", $code, $dehashed_data, $current_release, $context->{"$proforma_type" . "1a"}, exists $context->{$code} ? $context->{$code} : '');
	}
}



sub check_single_allowed_value {
# process_field_data + %field_specific_checks format. 150226.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my %mapping = (

		'GA20' => 'availablity',
		'GA36' => 'positive',
		'A21' => 'availablity',
		'MA16' => 'availablity',
		'MA21f' => 'MA21f_value',
		'LC99d' => 'positive',
		'GG8d' => 'positive',		
		'IN2b' => 'IN2b_value',
		'HH5d' => 'positive',
		'HH14d' => 'positive',
		'SP3b' => 'positive',
		'HH14b' => 'HH14b_value',

		'F2' => 'F2_value',
		
		'DB2b' => 'positive',
		'DB3c' => 'positive',
		'DB3d' => 'positive',
		'LC12c' => 'positive',
		'LC11j' => 'positive',
		'TO6d' => 'positive',

		'GA30f' => 'negative',

	);

	
	unless ($mapping{$code}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\ncheck_single_allowed_value is asking the mapping variable about a '%s' type proforma field, but the variable has no information about that field.",$code,$code);
		return;
	}

	my $current_availability_text = valid_symbol ($mapping{$code}, 'current_value');

	unless ($dehashed_data eq $current_availability_text) {

		report ($file, "%s: '%s' is not a valid value for this field, the only allowed value is '%s'\n!%s", $code, $dehashed_data, $current_availability_text, $context->{$code});

	}

}

sub validate_species_abbreviation_field {
# process_field_data + %field_specific_checks format. 140703.

	my ($file, $code, $dehashed_data, $context) = @_;

	my %species_limit = (

		'MA20' => 'drosophilid',
		'TC1d' => 'drosophilid',



	);

	$dehashed_data eq '' and return;

	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{0,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nvalidate_species_abbreviation_field subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$proforma_type,$code);
		return;
	}

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {

		# insert field specific checks here
		unless (valid_symbol ($datum, 'chado_species_abbreviation')) {

			report ($file, "%s: '%s' is not a valid species abbreviation:\n!%s\n!%s", $code, $datum, $context->{"$proforma_type" . "1a"}, $context->{$code});

		} else {

			if ($species_limit{$code}) {

				unless (valid_symbol ($datum, "taxgroup:$species_limit{$code}")) {
					report ($file, "%s: '%s' is not a valid '%s' species abbreviation:\n!%s\n!%s", $code, $datum, $species_limit{$code}, $context->{"$proforma_type" . "1a"}, $context->{$code});

				}

			}

		}
	}
}

sub validate_sequence_location {
# check that a sequence location matches the general format arm:coor_x..coor_y (where ..coor_y is optional and fmax must be >= fmin)
# designed to check a single coordinate at a time, and should be used after data has been dehashed.

	my ($file, $code, $sequence_location, $context) = @_;

	my ($arm, $min, $range, $max);

	$sequence_location eq '' and return;

	$sequence_location = trim_space_from_ends ($file, $code, $sequence_location);

	if (($arm, $min, $range, $max) = ($sequence_location =~ m/^([^:]{1,}):(\d{1,})(\.\.(\d{1,}))?$/)) {

		# check chromosomal arm
		unless (valid_symbol ($arm, 'chromosome arm') || valid_symbol ($arm, 'chromosome arm scaffold')) {

			report ($file, "%s: Invalid chromosome arm '%s' in '%s'", $code, $arm, $sequence_location);

		}

		# if max exists, check that min <= max
		if ($range) {

			if ($min > $max) {

			report ($file, "%s: '%s' must not be greater than '%s' in sequence location '%s'", $code, $min, $max, $sequence_location);

			}

		}


	} else {

		report ($file, "%s: Invalid sequence_location format '%s'", $code, $sequence_location);


	}

}


sub validate_cytological_location {
# converted to process_field_data and %field_specific_checks format 141128
# check that a Dmel cytological location matches the general format x--y, where --y is optional
# (when it is a single band) and x and y are both valid cytological bands
# designed to check a single location at a time, and should be used after data has been dehashed.
# this subroutine only checks that the values given are valid - cross-checks with other fields
# to check that the data is only filled in for Dmel features should be done after the entire
# proforma is processed

	my ($file, $code, $dehashed_data, $context) = @_;


	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});


		foreach my $datum (keys %{$uniqued_data}) {

		my ($min, $range, $max);


		if (($min, $range, $max) = ($datum =~ m/^([^-]{1,})(--(.*))?$/)) {

			# check that min is a valid cytological band
			valid_symbol ($min, 'cyto loc') or report ($file, "%s: Invalid cytological band '%s' in '%s':\n!%s", $code, $min, $datum, $context->{$code});

			# if max exists, check that max is a valid cytological band
			if ($range) {
				valid_symbol ($max, 'cyto loc') or report ($file, "%s: Invalid cytological band '%s' in '%s':\n!%s", $code, $max, $datum, $context->{$code});
			}

		} else {

			report ($file, "%s: Invalid cytological location format '%s':\n!%s", $code, $datum, $context->{$code});

		}
	}
}



sub validate_obsolete {
# deliberately not using process_field_data + %field_specific_checks format, as don't want allow
# hashes in the obsolete data field (this is to prevent a hashed proforma passing the checks where one value of 'y' is missed from a hashed list in an obsolete data field). 140702.

	my ($file, $change, $code, $data, $context) = @_;

    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context->{$code});

    $data = trim_space_from_ends ($file, $code, $data);
	$data eq '' and return;

	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{0,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nvalidate_obsolete subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$proforma_type,$code);
		return;
	}

# work out field to report error for (have "1a" as a default as that is usually the primary
# symbol field)
	my $primary_symbol = exists $standard_symbol_mapping->{$proforma_type}->{primary_field} ? ($proforma_type . $standard_symbol_mapping->{$proforma_type}->{primary_field}) : ($proforma_type . "1a");

	single_line ($file, $code, $data, $context->{$code}) or return;

	if ($data =~ m/ \# /) {

		report ($file, "%s: No hashes allowed in this field (to ensure robust checking)\n!%s\n!%s", $code, $context->{$primary_symbol}, $context->{$code});
		return;
	}

	if ($data eq 'y') {

		report ($file, "%s: Do you REALLY want to delete the following $standard_symbol_mapping->{$proforma_type}->{type}(s) from the database ?:\n!%s\n!%s", $code, $context->{$primary_symbol}, $context->{$code});

	} else {

		report ($file, "%s: '%s' not allowed (field must either contain \'y\' or be empty):\n!%s\n!%s", $code, $data, $context->{$primary_symbol}, $context->{$code});

	}
}

sub validate_dissociate {
# similar to validate_obsolete, deliberately not using
# process_field_data + %field_specific_checks format, as don't want allow
# hashes in the obsolete data field (this is to prevent a hashed proforma passing the checks
# where one value of 'y' is missed from a hashed list in an obsolete data field). 141125.

	my ($file, $change, $code, $data, $context) = @_;

    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context->{$code});

    $data = trim_space_from_ends ($file, $code, $data);
	$data eq '' and return;

	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{0,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed.\nPlease let Gillian know the following, so that Peeves can be fixed:\nvalidate_obsolete subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field (when trying to check data in '%s'), but the variable has no information about that type of proforma.",$code,$proforma_type,$code);
		return;
	}

# work out field to report error for (have "1a" as a default as that is usually the primary
# symbol field)
	my $primary_symbol = exists $standard_symbol_mapping->{$proforma_type}->{primary_field} ? ($proforma_type . $standard_symbol_mapping->{$proforma_type}->{primary_field}) : ($proforma_type . "1a");

	unless (valid_symbol ($g_FBrf, 'FBrf')) {
		report ($file, "%s: You cannot fill in this field for a new publication:\n!%s\n!%s", $code, $context->{$primary_symbol}, $context->{$code});
		return;
	}

	single_line ($file, $code, $data, $context->{$code}) or return;

	if ($data =~ m/ \# /) {

		report ($file, "%s: No hashes allowed in this field (to ensure robust checking)\n!%s\n!%s", $code, $context->{$primary_symbol}, $context->{$code});
		return;
	}

	if ($data eq 'y') {

		report ($file, "%s: Do you REALLY want to dissociate the following $standard_symbol_mapping->{$proforma_type}->{type}(s) from %s:\n!%s\n!%s", $code, $g_FBrf, $context->{$primary_symbol}, $context->{$code});

	} else {

		report ($file, "%s: '%s' not allowed (field must either contain \'y\' or be empty):\n!%s\n!%s", $code, $data, $context->{$primary_symbol}, $context->{$code});

	}

}

sub check_ontology_term_id_pair {

# Checks that an ontology term ; id pair match each other.
# Designed to work on a single term ; id pair that have already been split
# into separate variables, so basic syntax check should have been already been
# done to generate $term and $id before passing to this subroutine

    my ($file, $code, $term, $id, $namespace, $line, $specific_error_message) = @_;

# $namespace = namespace of ontology term (either the default namespace for the whole ontology, or a subset if appropriate)
# e.g. "DO" for disease ontology
# $line is the whole line containing the $term ; $id pair, for context
# $term = the ontology term name given in the proforma
# $id = the ontology id given in the proforma
# $purported_id = the id you get when you look up $term, if $term is not valid, $purported_id = 0
# $purported_term = the term name you get when you look up $id, if $id is not valid, $purported_term = 0


	my $purported_id = valid_symbol ($term, $namespace);
    my $purported_term = valid_symbol ($id, "$namespace:id");
    #print STDOUT "id is $purported_id and term $purported_term\n";

# required for special checks for GO lines    
	my $short_namespace = $namespace;
	$short_namespace =~ s/:.+$//;


	if (valid_symbol ($term, "$short_namespace:do_not_annotate")) {
		report ($file, "%s: '%s' term should not be used for %s annotation. Please read the comment field associated with the %s term for guidance.", $code, $term, $short_namespace, $short_namespace);
		return;

	}

	if (valid_symbol ($term, "$short_namespace:do_not_manually_annotate")) {
		report ($file, "%s: '%s' term should not be used for manual %s annotation. Please make a more specific annotation using a child term, request a new term or omit this annotation.", $code, $term, $short_namespace);
		return;
	}    

    if ($purported_id) { # in this case $term is valid
		if ($purported_term) { # in this case both $term and $id are valid
	    	unless ($term eq $purported_term && $id eq $purported_id) { # check that the valid $term and $id match each other
				report ($file, "%s: Mismatched %s term and ids in '%s'\n'%s' is '%s' and '%s' is '%s'.",
				$code, ($namespace =~ m|:default$| ? $short_namespace : $namespace), $line, $term, $purported_id, $id, $purported_term);
	    	}
		} else { # in this case $term is valid, but $id is not valid
			report ($file, "%s: Unknown %s id '%s' in '%s', did you mean '%s ; %s' perhaps?",
			$code, ($namespace =~ m|:default$| ? $short_namespace : $namespace), $id, $line, $term, $purported_id);
	    
		}
    } else { # in this case, $term is not valid
		if ($purported_term) { # in this case, $term is not valid, but the $id is valid

			report ($file, "%s: Unknown %s term '%s' in '%s', did you mean '%s ; %s' perhaps?",
			$code, ($namespace =~ m|:default$| ? $short_namespace : $namespace), $term, $line, $purported_term, $id);
		} else { # in this case, both $term and $id are not valid

# test whether term and id are swapped around and report if so

			if ((valid_symbol ($term, "$namespace:id")) && (valid_symbol ($id, "$namespace"))) {

				report ($file, "%s: The term and id parts of the %s line '%s' appear to be swapped around.", $code, ($namespace =~ m|:default$| ? $short_namespace : $namespace), $line);
				return;

			}

# start of special check for GO terms, since putting a valid term ; id pair from the wrong namespace into a field is a common error
			if ($namespace =~ m|^GO:|) {

# if the term ; id pair is valid in GO, but not in the namespace given, suggest that curator might have missed and put in wrong field
				my $purported_go_id = valid_symbol ($term, "GO:default");
				my $purported_go_term = valid_symbol ($id, "GO:default:id");
    			if ($purported_go_id) { # in this case $term is a GO valid term but in wrong namespace
					if ($purported_go_term) { # in this case both $term and $id are valid but in wrong GO namespace

				    	unless ($term eq $purported_go_term && $id eq $purported_go_id) { # check that the valid $term and $id match each other
							report ($file, "%s: Mismatched %s term and ids in '%s'\n'%s' is '%s' and '%s' is '%s' (You may also have meant to put this in a neighbouring field, as neither the term or id is from the namespace expected for this field).", $code, $namespace, $line, $term, $purported_go_id, $id, $purported_go_term);
	    				} else {
							report ($file, "%s: '%s' is not from the namespace expected for this field - did you mean to put this in a neighbouring field ?", $code, $line);
						}

					} else { # in this case $term is a valid GO term  but in the wrong GO namespace, but $id is not valid
						report ($file, "%s: Unknown GO id '%s' in '%s', did you mean '%s ; %s' perhaps? (You may also have meant to put this in a neighbouring field, as '%s' is not from the namespace expected for this field).", $code, $id, $line, $term, $purported_go_id, $term);
	    
					}
				} else { # in this case, $term is not a valid GO term
					if ($purported_go_term) { # in this case, $term is not a valid GO term, but the $id is a valid GO id, but in the wrong namespace
						report ($file, "%s: Unknown GO term '%s' in '%s', did you mean '%s ; %s' perhaps?  (You may also have meant to put this in a neighbouring field, as '%s' is not from the namespace expected for this field).", $code, $term, $line, $purported_go_term, $id, $purported_go_term);
					} else { # in this case, both $term and $id are not valid GO items
						report ($file, "%s: Unknown GO term '%s' and GO id '%s' in '%s'", $code, $term, $id, $line);
					}
    			}
# end of special check for GO terms



			} else {
#				report ($file, "%s: Unknown %s term '%s' and %s id '%s' in '%s'", $code, ($namespace =~ m|:default$| ? $short_namespace : $namespace), $term, ($namespace =~ m|:default$| ? $short_namespace : $namespace), $id, $line);


				report ($file, "%s: '%s' is not from the %s namespace which is expected for this field%s", $code, $line, ($namespace =~ m|:default$| ? $short_namespace : $namespace), $specific_error_message ? $specific_error_message : ".");
			}
		}
    }
}

sub validate_ontology_term_id_field {

# Can be used from process_field_data + %field_specific_checks (in which case the
# first four arguments only are supplied and the final two arguments are provided
# from within the subroutine (from %allowed_types).
# Can also be used outside process_field_data, in which case all arguments are
# supplied by the call to the subroutine.  This flexibility is to allow for
# cases where the expected namespace can vary within a field depending on other
# information. eg. for the case of LC2b, the expected namespace depends on the 'entity
# type' of the dataset (which either comes from LC2a or chado).

# The arguments are:
# $file = curation record
# $code = proforma field code
# $term_id_pair_list = dehashed contents of a proforma field containing a list of ontology term ; id pairs, without proforma field text
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages
# $expected_namespace = the namespace expected for the field
# $specific_error_message.  This is used in some cases where both the term and the id are not from the expected namespace, to provide context to help make sense of this error message (e.g. for LC2b, additional proforma fields are included in the error message for context).  If a specific error message is required in this case, it is passed as an argument to the subroutine, along with the $expected_namespace.


# use shift so that can cope with variable number of arguments

	my $file = shift;
	my $code = shift;
	my $term_id_pair_list = shift;
	my $context = shift;

# defined as empty as a default
	my $expected_namespace = '';
	my $specific_error_message = '';

	my %allowed_types = (

		'GG6a' => 'GO:cellular_component',
		'GG6b' => 'GO:molecular_function',
		'GG6c' => 'GO:biological_process',
		'TE4a' => 'SO:transposable_element',
		'G30' => 'SO:default',
		'A9' => 'SO:chromosome_structure_variation',
		'A26' => 'SO:chromosome_structure_variation',
		'LC13a' => 'GO:cellular_component',
		'LC13b' => 'GO:molecular_function',
		'LC13c' => 'GO:biological_process',
		'LC2a' => 'FBcv:dataset_entity_type',
		'LC4j' => 'FBbt:default',
		'LC4k' => 'FBdv:default',
		'LC13d' => 'SO:default',

	);



	if (@_) {

		unless (@_ == 2) {

			report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\nwrong number of optional arguments supplied in a non-process_field_data call to validate_ontology_term_id_field, please fix.",$code,$code);
			return;			

		}

		$expected_namespace = shift;
		$specific_error_message = shift;

	} else {

		if ($allowed_types{$code}) {

			$expected_namespace = $allowed_types{$code};

		} else {
			report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\nvalidate_ontology_term_id_field does not contain an entry in the allowed_types hash for the '%s' field, but is being called expecting there to be one, please fix.",$code,$code);
			return;

		}
	}



    $term_id_pair_list eq '' and return;			# Absence of data is permissible.


# include check_for_duplicated_lines so that subroutine works for both single and multiple line fields
	my $uniqued_term_id_pair_list = check_for_duplicated_lines($file,$code,$term_id_pair_list,$context->{$code});

	foreach my $term_id_pair (keys %{$uniqued_term_id_pair_list}) {

		unless ($term_id_pair =~ / ; /) {
			report ($file, "%s: Missing ' ; ' separator in '%s'", $code, $term_id_pair);
			next;
		}

		my ($term, $id) = ($term_id_pair =~ /(.*?) ; (.*)/);

		check_ontology_term_id_pair($file, $code, $term, $id, $expected_namespace, $term_id_pair, $specific_error_message);

	}
}

sub validate_date_field {
# process_field_data + %field_specific_checks format. 141125.

   my ($file, $code, $dehashed_data, $context) = @_;

   $dehashed_data eq '' and return;		# Absence of data is always acceptable.

# currently only used for single line fields, but having this here means that the
# code will work if we ever have a multiple-line date field in the future
	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {
		bad_iso_date ($file, $code, $datum);
	}

}


sub validate_cvterm_field {
# process_field_data + %field_specific_checks format. 141125.
# Can use to check fields containing genuine CV terms from an ontology
# or any other field where the allowed values are specified in symtab.pl
# NOTE: the check_valid_symbol_field and validate_cvterm_field subroutines are basically
# doing the same thing - which is checking that a field only contains values from defined
# list(s) of symbols/terms, by calling 'valid_symbol_of_list_of_types' which just returns true
# if the value given is a valid 'symbol' in any of the type(s) allowed for that field.
# In this instance 'symbol' means a valid entry in the %symbol_table populated by symtab.pl,
# so it doesn't just mean 'symbols' as in gene symbol, allele symbol etc, it also means
# valid cvterms from an ontology or values stored in symtab.pl.
# The two subroutines could be merged, but kept separate for now so that its easier to have
# more helpful error messages, since curators think of 'symbol' as just meaning things like
# gene symbol, allele symbol etc.

	my ($file, $code, $dehashed_data, $context) = @_;

	my %allowed_types = (

		'GG4' => ['FBcv:group_descriptor'],
		'A4' => ['FBcv:origin_of_mutation'],
		'GA4' => ['FBcv:allele_class'],
		'GA35' => ['SO:structural_variant', 'SO:functional_effect_variant', 'additional_GA35', 'SO:oligo', 'additional_targeting_GA35'],
		'GA8' => ['FBcv:origin_of_mutation'],
		'G34' => ['antibody'],
		'MA8' => ['insertion_phenotype'],
		'MA27' => ['insertion_category'],
		'GA90k' => ['lesion_type'],
		'GA90i' => ['orientation'],
		'A9' => ['aberration class shortcut','SO'],
		'A26' => ['aberration class shortcut','SO'],
		'A91b' => ['cyto loc'],
		'A91c' => ['cyto loc'],
		'A91d' => ['y or n'],
		'A91e' => ['y or n'],
		'A92b' => ['cyto loc'],
		'A92c' => ['cyto loc'],
		'A92d' => ['y or n'],
		'A92e' => ['y or n'],
		'MA5a' => ['chromosome', 'chromosome arm'],
		'MA23b' => ['MA23b_value'],
		'MA24' => ['MA24_value'],
		'MA23g' => ['orientation', 'additional_orientation'],
		'MA6' => ['orientation', 'additional_orientation'],
		'MA19b' => ['MA19b_value'],
		'MA19e' => ['MA19e_value'],
		'AB8' => ['y or n'],
		'MS16' => ['MS16_value'],
		'MS4a' => ['MS4a_value'],

		'F11a' => ['y or n'],
		'F11b' => ['y or n'],
		'F12' => ['antibody'],

		'G91a' => ['relationship_to_dataset'],
		'GA91a' => ['relationship_to_dataset'],
		'A30a' => ['relationship_to_dataset'],
		'MA30a' => ['relationship_to_dataset'],
		'MS30a' => ['relationship_to_dataset'],
		'F91a' => ['relationship_to_dataset'],

		'LC6d' => ['Y or N'],
		'HH1g' => ['HH1g_value'],
		'HH2a' => ['human_health_category'],
		
		'IN1d' => ['y or n'],
		'IN2a' => ['IN2a_value'],
		'IN3' => ['MI:default'],

		'SP5' => ['tax group'],
		'SP6' => ['chado database name'],
		'GG8b' => ['chado database name'],
		'HH5b' => ['chado database name'],
		'LC7c' => ['chado database name'],
		'LC99b' => ['chado database name'],
		'LC8a' => ['chado database name'],
		'LC8b' => ['chado database name'],


		'SF2a' => ['SF2a_value'],
		'SF2b' => ['SF2b_value'],
		'SF3c' => ['relationship_to_dataset'],
		'SF4h' => ['orientation'],
		'SF5e' => ['SF5e_value'],
		'SF10a' => ['SF10a_value'],
		'SF20a' => ['SF20a_value'],

		'LC12b' => ['LC12b_value'],

		'G39b' => ['y or n'],

		'TC4b' => ['TC4b_value'],

		'TO4' => ['FBcv:experimental_tool_descriptor'],
		'TC2d' => ['FBbt:default'],
		'TC2e' => ['FBdv:default'],
		'TC5c' => ['TC5c_value'],

		'TO6b' => ['chado database name'],

		'GA30d' => ['FBcv:experimental_tool_descriptor'],
		'MS14d' => ['FBcv:experimental_tool_descriptor'],
		'G40' => ['FBcv:experimental_tool_descriptor'],

	);

	unless ($allowed_types{$code}) {
		report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\nvalidate_cvterm_field does not contain an entry in the allowed_types hash for the '%s' field, please fix.",$code,$code);
		return;
	}

# only print type of term in error message if the cv term is from a real ontology or the type is useful to see
	my $additional_error_text = '';

	unless ($#{$allowed_types{$code}} == 0 && $allowed_types{$code}[-1] =~ m|^$code\_|) {
		$additional_error_text = " (only terms of type" . ($#{$allowed_types{$code}} > 0 ? "s" : '') .  " '" . (join '\', \'', @{$allowed_types{$code}}) . "' are allowed)";
	}

# make sensible error message for fields that can contain a single cytological band
	if ($#{$allowed_types{$code}} == 0 && $allowed_types{$code}[-1] eq 'cyto loc') {

		$additional_error_text = " (only a single cytological band (not a range) is allowed)";
	}

# make sensible error message for fields that can contain a chado database name
	if ($#{$allowed_types{$code}} == 0 && $allowed_types{$code}[-1] eq 'chado database name') {
		$additional_error_text = ", the value must be a valid $allowed_types{$code}[-1]";
	}

	$dehashed_data eq '' and return;

# will work for both single and multiple line fields
	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {

		if (valid_symbol_of_list_of_types ($datum, $allowed_types{$code})) {

# specific message for GA35 - warnings that some sub-branches of the structural_variant branch
# are not allowed.
# only testing for this once have established that the term is a valid SO term of the main branches allowed for the field.
			if ($code eq 'GA35') {

				valid_symbol ($datum, "SO:translational_product_structure_variant") and report ($file, "%s: '%s' is not valid for this field%s:\n!%s", $code, $datum, " (it is from the translational_product_structure_variant branch). Use a term from the 'coding_sequence_variant' branch instead", $context->{$code});

				valid_symbol ($datum, "SO:incomplete_transcript_variant") and report ($file, "%s: '%s' is not valid for this field%s:\n!%s", $code, $datum, " (it is from the incomplete_transcript_variant branch). This branch of SO describes variants in 'an incompletely *annotated* transcript' and this definition is not applicable to transgenic product class", $context->{$code});

## message to remind curators to use parent 'in vitro construct' term in most cases now we are curating GA35
			} elsif ($code eq 'GA8') {

				valid_symbol ($datum, 'FBcv:in vitro construct') and report ($file, "%s: '%s' is deprecated for this field now that we are using GA35, use 'in vitro construct' instead:\n!%s", $code, $datum, $context->{$code});

			}


		} else {

			report ($file, "%s: '%s' is not valid for this field%s:\n!%s", $code, $datum, $additional_error_text, $context->{$code});
		}


	}


}




sub compare_duplicated_field_pairs {


# compare_duplicated_field_pairs compares a pair of fields for presence/absence/identity
# and reports errors depending on value of test variable passed as argument.
# It is designed to be used for pairs of fields that are allowed to be duplicated
# within the same proforma.
# It is simply a wrapper so that each corresponding entry in a pair of fields
# can be passed to the compare_pairs_of_data subroutine (which checks a single pair
# of data at a time) for those field pairs where this easy shortcut is possible.
# eg. for a proforma containing
# field 1:a
# field 2:b
# field 1:x
# field 2:y
# compare_duplicated_field_pairs will pass a and b to compare_pairs_of_data for checking, then x and y.
# These values are passed to compare_duplicated_field_pairs by the following arguments:
# $data1 = reference to array containing entries for field1, stored as ['a','x']
# $data2 = reference to array containing entries for field2, stored as ['b','y']
# ie. the data passed for checking using $data1 and $data2 is in this format because duplicated fields
# are not allowed to have hashes in, and the data returned from process_field_data is pushed into the
# storage array for these kind of fields, rather than just assigned.
# $context is a reference to the %dup_proforma_fields hash which contains the complete picture for
# fields which can be duplicated within a proforma.
# For all other arguments, see compare_pairs_of_data subroutine for details.
#
# compare_duplicated_field_pairs first compares the number of entries in the arrays referred to by $data1
# and $data2.  If the number of entries are not the same for both arrays, an error is printed and no further
# checking is done until the error is fixed.
# If the number of entries are the same, the pairs of data are passed one at a time to compare_pairs_of_data for checking.
#
# compare_pairs_of_data can also be used directly (i.e. not via compare_field_pairs) to compare a single
# hash entry pair between two fields (e.g. just a and x above), if the checking requirements need it
# (eg. when the requirement for how the field is filled in depends on a third field or when the value
# in one field affects the requirement for presence/absence in the second field.


	my ($file, $code1, $data1, $code2, $data2, $context, $pair_test, $identity_test) = @_;
# first check that number of duplications of the two fields match, if not, then complain and do not do the test

#		warn "data1 info ($code1):\n";
#		warn Dumper ($data1);
#		warn "no of entries: $#$data1\n";
#		warn "data2 info ($code2):\n";
#		warn Dumper ($data2);
#		warn "no of entries: $#$data2\n";

# check there is data in the first field, and that the data has been stored for checking (i.e. passed basic process_field_data checks) otherwise get false-positive messages 
	if ($context->{$code1} && @{$data1}) {
		unless ($#$data1 == $#$data2) {

			report ($file, "There is a mismatch in the number of %s and %s fields duplicated in this proforma (or one of the fields failed another basic sanity check), please check and fix.", $code1, $code2);
			return;
		}
	}

	for (my $i = 0; $i <= $#$data1; $i++) {

# need to build the context information in the correct format to pass to compare_pairs_of_data from the %dup_proforma_fields hash
		my %local_context = ();
		$local_context{$code1} = $context->{$code1}[$i];
		$local_context{$code2} = $context->{$code2}[$i];

#		warn "Here is local context:\n";
#		warn Dumper (\%local_context);
#		warn "End of local context:\n";


		compare_pairs_of_data ($file, $code1, $data1->[$i], $code2, $data2->[$i], \%local_context, $pair_test, $identity_test);

	}
}


sub check_site_specific_field {
# Checks that a site-specific field is only filled in for the expected site.
# Should be called after a test has been done to establish that the field contains data, as
# does not do this test itself

	my ($file, $code, $site, $context) = @_;

	unless (valid_symbol ('Where_running', '_Peeves_') eq $site) {
 		report ($file, "%s: Only %s curators normally fill in this field, are you sure you meant to fill it in ?\n!%s", $code, $site, $context->{$code});

	}

}

sub check_for_duplicated_field_values {
# this checks for duplicated values in different instances of the same field code in a single proforma
# i.e. it is designed to check 'dupl for multiple' proforma fields.
# It is similar in design to check_for_duplicated_lines, but the format of the input $data is different
# - in this case, $data is a reference to an array containing the values in each instance of the
# 'dupl for multiple' field.
# It will print an error if a value is present in more than one of the repeated proforma lines.


	my ($file, $code, $data) = @_;

	my $uniqued_data = {};

	foreach my $datum (@{$data}) {
		if (exists $uniqued_data->{$datum}) {
			$uniqued_data->{$datum}++;
		} else {
			$uniqued_data->{$datum} = 0;
		}
	}


	foreach my $datum (keys %{$uniqued_data}) {
		report ($file, "%s: Duplicated data '%s' in different instances of the %s field in the same proforma.", $code, $datum, $code) if $uniqued_data->{$datum};
	}
}


sub validate_sequence_change {
# process_field_data + %field_specific_checks format. 150223.

# have not used check_for_duplicated_lines as in some fields, it is possible to get the same lesion twice (GA12a - if they are vague about a mutation)
	my ($file, $code, $dehashed_data, $context) = @_;

	my $mapping_table = {

# value of each allowed SoftCV is the characters allowed after that SoftCV for the field
# For the amino acid replacement, it is what is allowed both before and after the coordinates of the change i.e. both X and Y in XNY
# For the nucleotide substitution, it is what is allowed AFTER the coordinates of the change i.e. Y in XNY as X is ACGT for all fields
# (and is specified in the regular expression below)
		'GA12a' => {
			'Amino acid replacement:' => 'ACDEFGHIKLMNPQRSTVWY?',
			'Nucleotide substitution:' => 'ACGT?',
		},

		'GA90d' => {
			'Nucleotide substitution:' => 'ACGTMRWSYKVDBN?',
		},

		'GA90e' => {
			'Nucleotide substitution:' => 'ACGTMRWSYKVDBN?',
		},
		'GA90f' => {
			'Amino acid replacement:' => 'ACDEFGHIKLMNPQRSTVWY?',
		},

	};

	$dehashed_data eq '' and return;

	foreach my $datum (split /\n/, $dehashed_data) {

		# insert field specific checks here
	    next if $datum eq '';		# Ignore a completely empty line.

		my ($softcv, $space, $sequence_change) = ($datum =~ /^(.*?:)( ?)(.*)/);

		$softcv or $softcv = '';
		defined $space or $space = '';
		$space eq ' ' or report ($file, "%s: I think you omitted the space after the SoftCV prefix in '%s'", $code, $datum);


		if (exists $mapping_table->{$code}) {

			unless (exists $mapping_table->{$code}->{$softcv}) {

				report ($file, "%s: Invalid SoftCV prefix '%s' in '%s'", $code, $softcv, $datum);

			}

		} else {
			report ($file, "%s: A SoftCV prefix is not allowed in '%s', but you have used '%s'", $code, $datum, $softcv);
		}

		if (defined $sequence_change and $sequence_change ne '') {

			if ($sequence_change =~ m|\.$|) {

				$sequence_change =~ s/\.$//;

			} else {

				report ($file, "%s: I think you omitted the full stop at the end of '%s'", $code, $datum)
			}
		}


		if ($softcv eq 'Amino acid replacement:') {

			if (defined $sequence_change and $sequence_change ne '') {

				$sequence_change =~ /^[$mapping_table->{$code}->{$softcv}](\?|[1-9][0-9]*)([$mapping_table->{$code}->{$softcv}]|term)$/ or report ($file, "%s: Invalid amino acid replacement data '%s' in %s", $code, $sequence_change, $datum);
			} else {
				report ($file, "%s: Missing amino acid replacement data in '%s'", $code, $datum);
			}

		} elsif ($softcv eq 'Nucleotide substitution:') {

			if (defined $sequence_change and $sequence_change ne '') {

				$sequence_change =~ /^[ACGT?](\?|[1-9][0-9]*)[$mapping_table->{$code}->{$softcv}]$/ or report ($file, "%s: Invalid nucleotide substitution data '%s' in '%s'", $code, $sequence_change, $datum);

			} else {
				report ($file, "%s: Missing nucleotide substitution data in '%s'", $code, $datum);
			}
		}
	}


}

sub check_positive_integer {
# process_field_data + %field_specific_checks format. 150224.
# Designed to check a single line at a time, so does not use check_for_duplicated_lines

   my ($file, $code, $dehashed_data, $context) = @_;

   $dehashed_data eq '' and return;		# Absence of data is always acceptable.

	unless ($dehashed_data =~ m/^[1-9]{1}[0-9]{0,}$/) {

		report ($file, "%s: '%s' is not a valid value for this field, only positive integers are allowed.\n!%s", $code, $dehashed_data, $context->{$code});


	}
}


sub validate_approximate_number {
# process_field_data + %field_specific_checks format. 150224.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {

		# insert field specific checks here
		if (my ($number) = ($datum =~ m/^Approximately (.+?)$/)) {

			unless ($number =~ s/\.$//) {

				report ($file, "%s: You have missed the '.' after the value '%s' :\n!%s'", $code, $datum, $context->{$code});
			}

			check_positive_integer($file, $code, $number, $context);

		} else {

			check_positive_integer($file, $code, $datum, $context);

		}

	}


}

sub get_object_status {

# subroutine to check the 'status' of an object in a proforma according to what action fields are filled in.

# It is designed to check a single object at a time, not a dehashed list, and returns one of the following values:
# 'new' - brand new to chado
# 'rename' - rename of existing object
# 'merge' - merge of existing object
# 'existing' - existing object, no change to symbol
# '' - if the fields are not filled in correctly and do not match one of the four values above.
# This makes it easy for cross-checks between fields which depend on the object status to only
# be carried out if the action fields have been filled in correctly, and thus to avoid spurious
# error messages which are due to more basic errors in filling out these fields.

# $type = type of proforma 'G' for gene, 'MA' for insertion etc.
# $status = reference to array containing dehashed data from the 'status' field (x1g for 'cam' style proformae, x1f for 'harv' style proformae
# $rename = reference to array containing dehashed data from the rename field (x1e for 'cam' style proformae, x1c for 'harv' style proformae)
# $merge = reference to array containing dehashed data from the merge field (x1f for 'cam' style proformae, x1g for 'harv' style proformae)

	my ($type, $status, $rename, $merge) = @_;

	unless (exists $standard_symbol_mapping->{$type}) {

		report ('WARNING',"MAJOR PEEVES ERROR, please let Gillian know the following, so that Peeves can be fixed: get_object_status subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field, but the variable has no information about that type of proforma (the error is probably the first variable in the code that calls get_object_status).",$type);
		return;
	}

# different proforma styles have a different string for indicating a 'new' symbol
	my $proforma_style = $standard_symbol_mapping->{$type}->{style};
	my $new_string = $proforma_style eq 'Cambridge' ? 'n' : 'new';

	my $object_status = ''; # default for cases which don't pass one of the checks


# first check that status exists (needed to avoid error message in terminal)
	if ($status) {

# both merge and rename fields are empty
		if (!$rename && !$merge) {
# brand new object
			if ($status eq $new_string) {
				$object_status = "new";
			} else {
				$object_status = "existing";
			}

# at least one of merge and rename fields are filled in
		} else {

			if ($rename) {

				unless ($merge) {
# only rename is filled in
					if ($proforma_style eq 'Cambridge') {

						if ($status eq $new_string) {
							$object_status = "rename";
						}

					} else {
						unless ($status eq $new_string) {
							$object_status = "rename";
						}
					}
				}

# merge field only MUST be filled in else would not have got here
			} else {
				$object_status = "merge";
			}
		}
	}

	return $object_status;
}



## subroutine for processing primary proforma field - should probably eventually be replaced
## by generic process_field_data format subroutine, but difficult to do that due to special
# check for trailing hash below
sub validate_primary_proforma_field
{
    my ($file, $code, $change, $num, $symbols, $context) = @_;

	my $symbol_type = $code;
	$symbol_type =~ s|[0-9]{1,}[a-z]{1,}$||;


	unless (exists $standard_symbol_mapping->{$symbol_type}) {

		report ($file,"MAJOR PEEVES ERROR - Please let Gillian know the following, so that it can be fixed: validate_TE1a subroutine is asking the $standard_symbol_mapping variable about a '%s' type proforma field, but the variable has no information about that type of proforma.",$symbol_type);
	}

    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$context->{$code});


    my $primary_symbol_list;					# Clear default
    my $species_from_symbol_list;				# Clear default

# Check for missing final hash element but carry on regardless so that subsequent tests stand a chance of
# giving useful reports for the other elements.

    if ($symbols =~ /\s*\#\s*$/)
    {
	report ($file, "%s: Trailing hash in list '%s'", $code, $symbols);
	$symbols =~ s/\s*\#\s*$//;				# Remove to avoid future errors from this cause.
    }

    foreach my $symbol (dehash ($file, $code, $num, $symbols))
    {
		$symbol = trim_space_from_ends ($file, $code, $symbol);

# It's an error if the same object is given twice (in two separate proformae) in a single curation record.
		exists $x1a_symbols{$code}{$symbol} and report ($file, "%s: Duplicate %s symbol %s", $code, $standard_symbol_mapping->{$symbol_type}->{'type'}, $symbol);
	$x1a_symbols{$code}{$symbol} = 1;

# Store symbol for returning.
		push @{$primary_symbol_list}, $symbol;


# Get species prefix information for those symbol types where it is appropriate - do this for all
# symbols, regardless of symbol new-ness as may need for cross-checking with other fields
		if (exists $standard_symbol_mapping->{$symbol_type}->{species_prefix}) {

			my $prefix = get_species_prefix_from_symbol($symbol, $standard_symbol_mapping->{$symbol_type}->{id});

# the subroutine returns '' for the case where there is a \, but nothing in front of it
			if ($prefix eq '') {

				report ($file, "%s: No species before '\\' in '%s'", $code, $symbol)
			} else {
				valid_symbol ($prefix, 'chado_species_abbreviation') or report ($file, "%s: Invalid species prefix '%s' in '%s'", $code, $prefix, $symbol);

			}
			push @{$species_from_symbol_list}, $prefix;
		}


# Very important that this the storage and species checking done above happen before the
# the following syntax checks, since the symbol is changed to a sub-portion to be checked
# for some types of object (eg. alleles).

# do additional checks on the basic symbol syntax if it is not already a valid symbol of the appropriate type in chado		
		unless (valid_chado_symbol_of_list_of_types ($symbol, $standard_symbol_mapping->{$symbol_type}->{id})) {

# if its an allele, split into gene and superscript portions before proceeding further
# so only checking the superscript portion. This allows checking of a more limited set
# of allowed characters in the superscript portion compared to the gene symbol portion
# (any errors in the gene symbol portion will be flagged either when the parent G1a field
# is checked, or if there is a mismatch between the gene portion of GA1a and the G1a symbol.

			if ($symbol_type eq 'GA') {
				if (my ($gene, $super) = ($symbol =~ /(.+)\[(.+)\]$/)) {

# check any species abbreviations within the superscript - find the species, each of which is ended by a backslash
					while ($super =~ /(.*?)\\/g) {
						my $super_species = $1;
		    			$super_species =~ s/.*[.,]//;		# Drop everything before . or , (used to separate tags)
		    			$super_species =~ s/(T:)?//;		# Drop tags - cannot remove this until tools retrofit done else get false-positives
		    			if ($super_species) {
							valid_symbol ($super_species, 'chado_species_abbreviation') or
			    			report ($file, "%s: Invalid species '%s' in the '%s' superscript of\n!%s", $code, $super_species, $super, $context->{$code});
		    			} else {
							report ($file, "%s: No species before '\\' in the '%s' superscript of\n!%s", $code, $super, $context->{$code});
		    			}
					}

# for the rest of the subroutine, just check the allele superscript part
					$symbol = $super;

# do allele allowed characters check here to avoid false-positive message - as only check if 
# has basic gene[allele] format
					check_allowed_characters($file,$code,$symbol,$context->{$code});

				} else {

	    				report ($file, "%s: Symbol '%s' is not a correct allele format:\n%s", $code, $symbol, $context->{$code});

				}
			}

# unless is to avoid duplicate error as checking within if loop above
			unless ($symbol_type eq 'GA') {
				check_allowed_characters($file,$code,$symbol,$context->{$code});
			}


			
# check for malformed greek symbls
			while ($symbol =~ /(&.*?;)/g) {
				valid_greek($1) or report ($file, "%s: Malformed Greek symbol '%s' in '%s' from\n!%s", $code, $1, $symbol,$context->{$code});
			}

# check that there are no subscripts
			$symbol =~ /\[\[|\]\]/ and report ($file, "%s: Must not have subscripts in '%s'", $code, $symbol);

# check that there isn't a 'blank' species prefix for those types which do not have the species prefix in the symbol
# (and so are not already checked above). Ought to be unecessary, as curators should not be tempted to put \ in for 
# new symbols of these types, but will catch any cases where a symbol starts with \ just in case.

			unless (exists $standard_symbol_mapping->{$symbol_type}->{species_prefix}) {
				index ($symbol, '\\') or report ($file, "%s: No species before '\\' in '%s'", $code, $symbol);
			}
		}

    }

	return ($primary_symbol_list, $species_from_symbol_list);
}

# TAP statement subroutines - pulled from expression.pl so that they can be re-used to check IN5b field which uses identical format
# deliberately not turned into process_field_data format, because F9 checking would ideally cross-check the value in <e> against the value in F1a (transcript vs polypeptide)
# and so should implement this in similar way to IN6, IN7cd cross-checks

sub TAP_check {


    my ($file, $code, $data) = @_;

# mapping table for codes that do NOT use the assay (<e>) slot
	my %no_assay_mapping = (

		'LC4g' => '1',
		'IN5b' => '1',

	);

# mapping table for fields with <note> that can contain @@ with @FBid:symbol@ format
# plus allowed FBid types for the field (if any are allowed, an
	my $note_with_ids = {

		'F9' => {

			'FBtp' => '1',
			'FBti' => '1',

		},

	};

# mapping of fields and FBrfs where <e> and <t> are often empty, so we want the normal warning
# message to be suppressed.
	my $allow_empty_ref = {


		'F9' => {

			'FBrf0237128' => '1',

		},



	};

	$data eq '' and return;		# Absence of data is always acceptable.
	my @TAPS = split /\n/, $data;

	foreach my $TAP (@TAPS) {


	$TAP = silent_trim_space($TAP); # safe to silently trim spaces off ends of the statement, as proforma parser does this before processing

	next if $TAP eq ''; # this is required so that there is no error message for a leading blank line
	unless ($TAP =~ m/^<e>(.*)<t>(.*)<a>(.*)<s>(.*)<note>(.*)$/) {
		report ($file, "%s: Badly formed TAP statement: %s", $code, $TAP);
		next;  # Don't bother trying to check content if syntax is screwed up.
    }
# safe to silently trim spaces off ends of each portion of statement, as proforma parser does this before processing
    my $e = silent_trim_space($1), if ($1);
    my $t = silent_trim_space($2), if ($2);
    my $a = silent_trim_space($3), if ($3);
    my $s = silent_trim_space($4), if ($4);
    my $note = silent_trim_space($5), if ($5);

# checking '<e> = assay abbreviation' element
	if ($e) {
		unless (valid_symbol($e, 'assay')) {
			report ($file, "%s: '%s' is not a valid assay term in '%s'", $code, $e, $TAP);
		}
	} else {

		unless ($no_assay_mapping{$code} || (exists $allow_empty_ref->{$code} && exists $allow_empty_ref->{$code}->{$g_FBrf})) {
			report ($file, "%s: Looks like you forgot to include an assay term in %s", $code, $TAP);

		}
	}


# checking '<a> = anatomy ontology (FBbt) term - optionally followed by spatial qualifiers from FBcv' element

	if ($a) {
		TAPas_portion_check($file, $code, 'anatomy', $TAP, $a);
	}

# checking '<t> = temporal - developmental temporal shorthand CV or FBdv term' element
 	if ($t) {

		my $cvt = 'stage';
		my @split_bits;
## first split on the non-qualifier delimiters

		if ($t =~m/\&\&/) {
# TAP notes imply that spaces either side of && are required (although not convinced that is the
# case from looking at parsing code) so included a space in the split to be on the
# safe side. Used silent_trim_space on the results of the split so that will get rid of spaces
# if there is more than one space either side of term
			@split_bits = silent_trim_space(split / && /, $t);

		} elsif ($t =~m/\-\-/) {

# TAP notes and parsing code indicate that the presence of spaces either side of -- is optional
# so safe to use silent_trim_space here.
			@split_bits = silent_trim_space(split /--/, $t);

			if (@split_bits > 2) {
				report ($file, "%s: %s range statement should not contain more than 2 %s terms: %s", $code, $cvt, $cvt, $TAP);
			}
		} else {
# don't need a silent_trim_space here as simple statement with no sub bits so any spaces on
# ends already removed in TAP_check sub where split TAP statement into portions
			push (@split_bits, $t);
		}

## then try splitting each bit into term + any qualifiers and do checking


		foreach my $statement (@split_bits) {

			my $term;
			my $qualifiers;

			if ($statement =~ m/(.+) \| (.+)/) {

				$term = $1;
				$qualifiers = $2;

			} else {

				$term = $statement;

			}

# start of actual checking
# first, the case where $term IS a valid FBdv term

			if (valid_symbol($term, 'FBdv:default')) {

# check qualifiers are valid sex qualifiers
				if ($qualifiers) {

					my @qualifiers = split / & /, $qualifiers;

					foreach my $qualifier (@qualifiers) {

						unless  (valid_symbol($qualifier, 'FBcv:sex_qualifier')) {
							report ($file, "%s: '%s' is not a valid temporal qualifier in '%s'", $code, $qualifier, $TAP);    
	    				}
					}
				}

# second, the case where the $term is a valid short-cut term
			} elsif (valid_symbol($term, 'dv short')) {


# check qualifiers - this is the complicated bit, since need to cope with short-cut syntax
				if ($qualifiers) {

					my @qualifiers = split / & /, $qualifiers;

					foreach my $qualifier (@qualifiers) {

# if it is a valid sex qualifier, no need to do complex testing
						unless (valid_symbol($qualifier, 'FBcv:sex_qualifier')) {

# try splitting qualifier into range (separated by - or ,)
							my ($min, $range, $max);

							if (($min, $range, $max) = ($qualifier =~ m/^([^-,]{1,})([-,]([^-,]{1,}))?$/)) { ###

#									warn "Q: $qualifier, min: ^^$min^^, range: ^^$range^^, max: ^^$max^^\n";

# check min first as should always be a valid qualifier for the dv shortcut used in $term
								unless (valid_symbol($min, "dv_short_qualifier:$term")) {

									report ($file, "%s: The stage '%s' is not valid in the '%s' temporal qualifier in '%s'", $code, $min, $qualifier, $TAP);

								} else {

# if there is a range, attempt to check it, but only do this if the min passed the test above, since using the value of min to test validity of max
									if ($range) {

# split min into number and non-number part
										my ($min_string, $min_number) = ($min =~ m/^(.+?)(\d+([ABCD])?)$/);

#										warn "Q: $qualifier, min: ^^$min^^, min_string: ^^$min_string^^, min number: ^^$min_number^^\n";

# check that the string given as the max part of the range is actually valid - use the string part of the
# min term to work out what the full range would be (e.g. 'stage 5-6' actually means the max is 'stage 6')

										my $max_equivalent = $min_string . $max;

										unless (valid_symbol($max_equivalent, "dv_short_qualifier:$term")) {

											report ($file, "%s: The qualifier '%s' in '%s' is not valid (there is no '%s' for the '%s' developmental stage) in '%s'", $code, $max, $statement, $max_equivalent, $term, $TAP);

										} else {

# the if loop below is necessary because some stages are not just numbers
											if ($min_number eq $max) {

												report ($file, "%s: Identical stage given for both min and max in the temporal qualifier '%s' in '%s'", $code, $qualifier, $TAP);

											} else {
# if the max string is valid, test that the max value given is greater than the min (i.e. stage 4-6 is OK, stage 6-4 is not)
												$max =~ s/[^\d]//g;
												$min_number =~ s/[^\d]//g;

												unless ($min_number <= $max ) {
													report ($file, "%s: '%s' must be smaller than '%s' in the temporal qualifier '%s' in %s", $code, $min_number, $max, $qualifier, $TAP);
												}
											}

										}

									}

								}

# this is tripped if a stage range without a max , e.g. 'stage15-' is present
							} else { ###

								report ($file, "%s: '%s' is not a valid temporal qualifier in '%s'", $code, $qualifier, $TAP);    

							}


						}
					}
				}


# term is neither a valid FBdv or short-cut term
			} else {

# print error message for $term
				report ($file, "%s: '%s' is not a valid %s term in '%s'", $code, $term, $cvt, $TAP);

# check qualifiers
# check qualifiers are valid sex qualifiers
				if ($qualifiers) {

					my @qualifiers = split / & /, $qualifiers;

					foreach my $qualifier (@qualifiers) {

						unless  (valid_symbol($qualifier, 'FBcv:sex_qualifier')) {
							report ($file, "%s: '%s' is not a valid temporal qualifier in '%s'", $code, $qualifier, $TAP);
	    				}
					}
				}
			}

		}
	} else {

		unless (exists $allow_empty_ref->{$code} && exists $allow_empty_ref->{$code}->{$g_FBrf}) {
			report ($file, "%s: Looks like you forgot to include a temporal term in %s", $code, $TAP);
		}
	}


# checking '<s> = subcellular - a term from the GO cellular component ontology optionally followed by spatial qualifiers from FBcv' element
	if ($s) {
		TAPas_portion_check($file, $code, 'cell component', $TAP, $s);
	}

	if ($note) {

		if ($note_with_ids->{$code}) {
			check_stamps_with_ids ($file,$code,$note,$note_with_ids->{$code});

		} else {

			check_stamps ($file,$code,$note);

		}
	}

	}
}


sub TAPas_portion_check {

	my ($file, $code, $type, $TAP, $portion) = @_;


	my $type_mapping = {

		'anatomy' => ['FBbt:default'],
		'cell component' => ['GO:cellular_component'],


	};

	unless (exists $type_mapping->{$type}) {

		report ($file,"MAJOR PEEVES ERROR - Please let Gillian know the following, so that it can be fixed:\nTAPas_portion_check subroutine is asking the \$type_mapping variable about a '%s' portion of a TAP statement, but the variable has no information about that type of TAP statement portion.",$type);
		return ();
	}


	my @split_bits;

## split on the non-qualifier delimiters first
# include the space either side of &&of in both the match and the split so that it is safe
# (and does not split if a curator had put && and then a term starting with 'of' with no space)
	if  ($portion =~m/ \&\&of /) {
# can use silent_trim_space on the results of the split so that will get rid of spaces if there
# is more than one space either side of term
		@split_bits = silent_trim_space(split / &&of /, $portion);

    } elsif ($portion =~m/\&\&/) {
# TAP notes imply that spaces either side of && are required (although not convinced that is the
# case from looking at parsing code) so included a space in the split, as above, to be on the
# safe side. Used silent_trim_space on the results of the split so that will get rid of spaces
# if there is more than one space either side of term
		@split_bits = silent_trim_space(split / && /, $portion);

	} else {
# don't need a silent_trim_space here as simple statement with no sub bits so any spaces on
# ends already removed in TAP_check sub where split TAP statement into portions
		push (@split_bits, $portion);
	}

## then try splitting each bit into anatomy term + any qualifiers and checking

	foreach my $statement (@split_bits) {

		my $term;
		my $qualifiers;
		if ($statement =~ m/(.+?)\s+\|\s+(.+)/) {

			$term = $1;
			$qualifiers = $2;

		} else {

			$term = $statement;
		}

# check term first
		unless (valid_symbol_of_list_of_types($term, $type_mapping->{$type})) {

# test to see if range with --
			if ($term =~ m/--/) {

# add test for more than two -- here


### test each bit of range - the reg exp. and logic for bit of code basically copied
# from parse_anat_cc in ExpressionParser.pm. The way the regular expression is set up,
# it will only successfully split if the first thing after the -- other than space(s) 
# is a number.  So if the number after the space is forgotten
# e.g. A1-7 dorsal acute muscle 1--
# or the full valid term is used after the --
# e.g. A1-7 dorsal acute muscle 1--A1-7 dorsal acute muscle 2
# the whole thing will end up in $firstpart, and as this won't be a valid ontology term, it will
# trip the error in the first unless loop 
				my ($firstpart, $numbers, $lastpart) = split /(\d+\s*--\s*\d+)/, $term;

#				warn "$file: firstpart: ^^$firstpart^^, numbers: &&$numbers&&, lastpart: ##$lastpart##\n";

# add this loop to cope with the case where it cannot populate $numbers, because the first thing
# after the -- is not a number. This prevents warnings in the terminal
				my $firstnum = '';
				my $lastnum = '';
				if ($numbers) {
					($firstnum, $lastnum) = silent_trim_space(split /--/, $numbers);
				}
#				warn "$file: firstnum: ^^$firstnum^^, lastnum: &&$lastnum&&\n";

				my $fromterm = "$firstpart$firstnum";
      			$fromterm .= "$lastpart" if $lastpart;

      			my $toterm = "$firstpart$lastnum";
      			$toterm .= "$lastpart" if $lastpart;

# first check that the first anatomy term is valid
				unless (valid_symbol_of_list_of_types($fromterm, $type_mapping->{$type})) {

# add hint for cases where it has not split on the -- because it is not a number after the --

					if ($fromterm =~ m/--/) {

						report ($file, "%s: '%s' is not a valid %s term (a number shortcut, not the whole anatomy term, should be used for the second part of a range when using --) in '%s'", $code, $fromterm, $type, $TAP);


					} else {

						report ($file, "%s: '%s' is not a valid %s term in '%s'", $code, $fromterm, $type, $TAP);
					}
				} else {

# check the second part of the range - only do this if the first part is valid, since checking the second
# part uses information from the first part
# Do not need to test here for $lastnum (and thus $toterm) being empty, since if that is the case the
# unless loop will have already been tripped above

					unless (valid_symbol_of_list_of_types($toterm, $type_mapping->{$type})) {

						report ($file, "%s: '%s' in '%s' is not valid (the expanded '%s' term is not a valid %s term) in '%s'", $code, $lastnum, $term, $toterm, $type, $TAP);

					}


				}

### end of bit basically copied from parse_anat_cc

# term has no -- so must be invalid
			} else {

				report ($file, "%s: '%s' is not a valid %s term in '%s'", $code, $term, $type, $TAP);

			}
		}

# then check any qualifiers (which after the initial | are separated by a ' & ')

		if ($qualifiers) {

# add another silent_trim_space to get rid of any extra spaces
			my @qualifiers = silent_trim_space(split / & /, $qualifiers);

			foreach my $qualifier (@qualifiers) {

				my $allowed_types = valid_symbol('TAPas', 'allowed_qualifier_list');
				unless (valid_symbol_of_list_of_types ($qualifier, $allowed_types)) {

					report ($file, "%s: '%s' is not a valid anatomy qualifier in '%s'", $code, $qualifier, $TAP);
	    		}
			}
		}


	}

}


sub validate_primary_species_field {
# process_field_data + %field_specific_checks format. 160106.

	my ($file, $code, $dehashed_data, $context) = @_;

	my @return_list;

	# the following shouldn't be necessary as this subroutine should always be called via process_field_data from a field that has the single_line_status set to '1', but including it again for belts and braces
	single_line ($file, $code, $dehashed_data, $context->{$code}) or return;

	$dehashed_data = trim_space_from_ends ($file, $code, $dehashed_data);

# this may be too strict and may need to do at end of proforma in field cross-checks, but left in for now
	check_allowed_characters($file,$code,$dehashed_data,$context->{$code});

	push @return_list, $dehashed_data;

	return @return_list;

}

sub type_gene_product {

# Subroutine which 'types' a gene product symbol as either FBtr or FBpp based on the format of the symbol.
# Returns the gene product type, symbol(s) of the parent(s) to which the product is attached (a single gene symbol
# for regular transcripts/polypeptides, a single allele symbol for expression of transgenic constructs/insertions,
# multiple alleles for combinations), and the expected type of the parent symbols if $return_value is '1'.
# If $return_value is '0', returns just the type of the gene product.
# If the symbol does not match any of the expected formats, then empty values will be returned.

	my ($gene_product, $return_value) = @_;

	my ($parent_symbols, $suffix, $product_type, $parent_type);


# valid formats are:
# genesymbol-XR (FBtr)
# genesymbol-XP (FBpp)
# allelesymbolRA (FBtr)
# allelesymbolPA (FBpp)
# allelesymbol&cap;allelesymbol (FBco)

	my $suffix_mapping = {
	
		'RA' => {		
			'product_type' => 'FBtr',
			'parent_type' => 'FBal',
		},
		
		'PA' => {		
			'product_type' => 'FBpp',
			'parent_type' => 'FBal',
		},		

		'-XR' => {		
			'product_type' => 'FBtr',
			'parent_type' => 'FBgn',
		},		

		'-XP' => {		
			'product_type' => 'FBpp',
			'parent_type' => 'FBgn',
		},

		'&cap;' => {
			'product_type' => 'FBco',
			'parent_type' => 'FBal',
		},		
	};

	if ($gene_product =~ m/^.+?(&cap;).+$/) {

		$suffix = $1;

# capture $parent_symbols as an array to allow for multiple parents in combinations
		@{$parent_symbols} = split '&cap;', $gene_product;

		$product_type = $suffix_mapping->{$suffix}->{'product_type'};
		$parent_type = $suffix_mapping->{$suffix}->{'parent_type'};


	} elsif ($gene_product =~ m/^(.+\[.+\])([PR]A)$/ || $gene_product =~ m/^(.+)(-X[RP])$/) {
	
		@{$parent_symbols} = $1;
		$suffix = $2;
	
		$product_type = $suffix_mapping->{$suffix}->{'product_type'};
		$parent_type = $suffix_mapping->{$suffix}->{'parent_type'};

	}

	if ($return_value) {
		return ($product_type, $parent_symbols, $parent_type);
	}
	
	return $product_type;
}

sub summary_check_ontology_term_id_pair {

# checks validity of ontology 'term ; id' pair but does not give error messages.
# instead returns $term if it passes, 0 if it does not.
    my ($term_id_pair, $namespace) = @_;

	my ($term, $id) = ($term_id_pair =~ /(.*?) ; (.*)/);

	unless ($term && $id) {

		return 0;

	}


	my $purported_id = valid_symbol ($term, $namespace);
    my $purported_term = valid_symbol ($id, "$namespace:id");


	if ($purported_id && $purported_term) {

		if ($term eq $purported_term && $id eq $purported_id) {

			return $term;
		}

	}
	return 0;
}


sub summary_check_ontology_term_id_pair_of_list_of_types {

# subroutine that tests whether a 'cvterm ; id' line is completely correct for at least
# one of a list of allowed namespaces.
# $term_id_pair = line to be tested for validity
# $list_of_namespaces = reference to an array containing a list of the allowed namespaces for
# the line, e.g. FBcv:assay_attribute, FBcv:assay_type etc.
# Returns 1 if the line is completely correct for any of the allowed namespaces, otherwise returns 0.

	my ($term_id_pair, $list_of_namespaces) = @_;

	foreach my $type (@{$list_of_namespaces}) {
		summary_check_ontology_term_id_pair ($term_id_pair, $type) and return 1;

	}

	return 0;
}

sub check_valid_chado_symbol_field {

# wrapper for valid_chado_symbol_of_list_of_types
# Checks that each value in a field is a valid symbol *in chado* of a defined
# list of allowed type(s) of symbol.

# The arguments are:
# $file = curation record
# $code = proforma field code
# $symbol_list = dehashed contents of a proforma field containing valid symbols, without proforma field text
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages

	my ($file, $code, $symbol_list, $context) = @_;

# each the key is a proforma field code and the value is a reference to an array containing the list of id types (e.g. FBtp, FBmc, FBms) that are allowed in that field
	my %allowed_types = (

		'LC3e' => ['FBlc'],
		'MS19a' => ['FBtp','FBmc'],

		'SF3a' => ['FBlc'],
		'SF5a' => ['FBgn'],
		'SF5b' => ['FBal'],
		'SF5g' => ['FBtr'],
		'SF5c' => ['FBtp'],
		'SF5h' => ['FBmc'],
		'SF5d' => ['FBms'],
		'SF11a' => ['FBpp'],
		'G38' => ['FBgn'],



	);

	unless ($allowed_types{$code}) {
		report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\ncheck_valid_chado_symbol_field does not contain an entry in the allowed_types hash for the '%s' field, please fix.",$code,$code);
		return;
	}


    $symbol_list eq '' and return;			# Absence of data is permissible.


# include check_for_duplicated_lines so that subroutine works for both single and multiple line fields
	my $uniqued_symbols = check_for_duplicated_lines($file,$code,$symbol_list,$context->{$code});

	foreach my $symbol (keys %{$uniqued_symbols}) {

		valid_chado_symbol_of_list_of_types ($symbol, $allowed_types{$code}) or report ($file, "%s: Invalid symbol '%s' (only symbols of type" . ($#{$allowed_types{$code}} > 0 ? "s" : '') . " '%s' *already in chado* are allowed - either try putting this record in a later phase (if the symbol is made in another record) or putting the proforma in a separate record in a later phase (if this symbol is made new elsewhere in this record):\n!%s", $code, $symbol, (join '\', \'', @{$allowed_types{$code}}), $context->{$code});
	}
}

sub check_valid_uniquename_field {
# process_field_data + %field_specific_checks format.
# designed for non-primary fields that contain uniquenames of a defined set of type(s)

# The arguments are:
# $file = curation record
# $code = proforma field code
# $FBid_list = dehashed contents of a proforma field containing uniquenames, without proforma field text
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages

	my ($file, $code, $FBid_list, $context) = @_;


	my %allowed_types = (
		'LC12a' => ['FBab', 'FBal', 'FBcl', 'FBgn', 'FBti', 'FBtp', 'FBtr', 'FBpp', 'FBsf', 'FBmc'],
		'TC5a' => ['FBti'],

	);

	unless ($allowed_types{$code}) {
		report ($file, "MAJOR PEEVES ERROR, no checking will be done on the '%s' field until it is fixed. Please let Gillian know the following:\ncheck_valid_uniquename_field does not contain an entry in the allowed_types hash for the '%s' field, please fix.",$code,$code);
		return;
	}

# work out what type of proforma is being checked
	my $proforma_type = $code;
	$proforma_type =~ s|[0-9]{1,}[a-z]{0,}$||;

	unless (exists $standard_symbol_mapping->{$proforma_type}) {

		report ($file,"MAJOR PEEVES ERROR - Please let Gillian know the following, so that it can be fixed:\ncheck_valid_uniquename_field subroutine is asking the \$standard_symbol_mapping variable about a '%s' type proforma field, but the variable has no information about that type of proforma.",$proforma_type);
		return ();
	}


    $FBid_list eq '' and return;			# Absence of data is permissible.

	my $primary_symbol_field = exists $standard_symbol_mapping->{$proforma_type}->{primary_field} ? ($proforma_type . $standard_symbol_mapping->{$proforma_type}->{primary_field}) : ($proforma_type . "1a");


# include check_for_duplicated_lines so that subroutine works for both single and multiple line fields
	my $uniqued_FBids = check_for_duplicated_lines($file,$code,$FBid_list,$context->{$code});

	foreach my $FBid (keys %{$uniqued_FBids}) {

		if (my $chado_symbol = valid_symbol ($FBid, 'uniquename')) {

			valid_symbol_of_list_of_types ($chado_symbol, $allowed_types{$code}) or report ($file, "%s: Invalid uniquename '%s' (only uniquenames of type" . ($#{$allowed_types{$code}} > 0 ? "s" : '') . " '%s' are allowed):\n!%s", $code, $FBid, (join '\', \'', @{$allowed_types{$code}}), $context->{$code});

		} else {

# in this case, curator has entered a symbol by mistake instead of a uniquename
			if (my $chado_id = valid_chado_symbol_of_list_of_types ($FBid, $allowed_types{$code})) {

				report ($file, "%s: You have entered a symbol '%s' instead of an FBid number, did you mean '%s' (the valid id of %s) instead ?",$code, $FBid, $chado_id, $FBid);


			} else {
				report ($file, "%s: '%s' is not a valid uniquename in chado:\n!%s\n!%s", $code, $FBid, $context->{$primary_symbol_field}, $context->{$code});

			}
		}
	}
}

sub compare_multiple_line_fields_negative {

# subroutine  (based on compare_pub_fbrf_containing_fields) to check
# that none of the values in the first field are present in the second field.
# Can cope if one/both of the fields has multiple lines of data.

# subroutine (based on compare_pub_fbrf_containing_fields) which checks
# that the same value is not present in two fields.
# Can cope if one/both of the fields has multiple lines of data.

	my ($file, $num, $code1, $data1, $code2, $data2, $context) = @_;

	for (my $i = 0; $i < $num; $i++) {

		if (defined $data1->[$i] && $data1->[$i] ne '') {

			if (defined $data2->[$i] && $data2->[$i] ne '') {


				my $field1_data = {};
				my $duplicated_data = {};

				foreach my $datum (split (/\n/, $data1->[$i])) {
					$field1_data->{$datum}++;
				}

				foreach my $datum (split (/\n/, $data2->[$i])) {

					if (exists $field1_data->{$datum}) {
						$duplicated_data->{$datum}++;

					}
				}

				foreach my $datum (keys %{$duplicated_data}) {

					report ($file, "%s and %s must NOT contain the same data '%s'\n!%s\n!%s", $code1, $code2, $datum, exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');
				}

			}
		}



	}


}

sub compare_multiple_line_fields_positive {
# subroutine to check that all the values in the first field are
# present in the second field (not necessarily in the same order)
# Can cope if one/both of the fields has multiple lines of data.


	my ($file, $num, $code1, $data1, $code2, $data2, $context, $specific_error_message) = @_;


	for (my $i = 0; $i < $num; $i++) {

		if (defined $data1->[$i] && $data1->[$i] ne '') {



			my $field1_data = {};
			my $duplicated_data = {};

			foreach my $datum (split (/\n/, $data1->[$i])) {
				$field1_data->{$datum}++;
			}

			if (defined $data2->[$i] && $data2->[$i] ne '') {
				foreach my $datum (split (/\n/, $data2->[$i])) {
					if (exists $field1_data->{$datum}) {
						$duplicated_data->{$datum}++;
					}
				}
			}

			foreach my $datum (keys %{$field1_data}) {
				unless (exists $duplicated_data->{$datum}) {
					report ($file, "'%s' is present in %s, but not in %s. This is an error. %s\n!%s\n!%s", $datum, $code1, $code2, $specific_error_message ? $specific_error_message : '.', exists $context->{$code1} ? $context->{$code1} : '', exists $context->{$code2} ? $context->{$code2} : '');
				}
			}

		}
	}
}

sub utf2sgml {

=head1 SUBROUTINE:
=cut

=head1

	Title:    utf2sgml
	Usage:    utf2sgml(scalar variable);
	Function: Converts utf-8 characters from chado into sgml format. Inside the subroutine, the string is first checked to see whether it is already in perl's internal utf-8 format and then, if not, the decode method (from Encode) is used to convert it to perl's internal utf-8 format, before the sgml conversion (need to do the check before using decode, because if it is already in perl's internal utf-8 format and you try to decode it, it complains about double encoding [see email 'XORT UTF-8 problem']
	Example:  my $sgmlsym = &utf2sgml($pr{sname});
	Returns:  string to check converted into sgml
	Args   :  string to check

=cut

    my ($string) = $_[0];

	unless (utf8::is_utf8($string)) {
    	$string = decode("utf-8",$string);

	}



    $string =~ s/\x{03B1}/&agr\;/g;
    $string =~ s/\x{0391}/&Agr\;/g;
    $string =~ s/\x{03B2}/&bgr\;/g;
    $string =~ s/\x{0392}/&Bgr\;/g;
    $string =~ s/\x{03B3}/&ggr\;/g;
    $string =~ s/\x{0393}/&Ggr\;/g;
    $string =~ s/\x{03B4}/&dgr\;/g;
    $string =~ s/\x{0394}/&Dgr\;/g;
    $string =~ s/\x{03B5}/&egr\;/g;
    $string =~ s/\x{0395}/&Egr\;/g;
    $string =~ s/\x{03B6}/&zgr\;/g;
    $string =~ s/\x{0396}/&Zgr\;/g;
    $string =~ s/\x{03B7}/&eegr\;/g;
    $string =~ s/\x{039F}/&EEgr\;/g;
    $string =~ s/\x{03B8}/&thgr\;/g;
    $string =~ s/\x{0398}/&THgr\;/g;
    $string =~ s/\x{03B9}/&igr\;/g;
    $string =~ s/\x{0399}/&Igr\;/g;
    $string =~ s/\x{03BA}/&kgr\;/g;
    $string =~ s/\x{039A}/&Kgr\;/g;
    $string =~ s/\x{03BB}/&lgr\;/g;
    $string =~ s/\x{039B}/&Lgr\;/g;
    $string =~ s/\x{03BC}/&mgr\;/g;
    $string =~ s/\x{039C}/&Mgr\;/g;
    $string =~ s/\x{03BD}/&ngr\;/g;
    $string =~ s/\x{039D}/&Ngr\;/g;
    $string =~ s/\x{03BE}/&xgr\;/g;
    $string =~ s/\x{039E}/&Xgr\;/g;
    $string =~ s/\x{03BF}/&ogr\;/g;
    $string =~ s/\x{039F}/&Ogr\;/g;
    $string =~ s/\x{03C0}/&pgr\;/g;
    $string =~ s/\x{03A0}/&Pgr\;/g;
    $string =~ s/\x{03C1}/&rgr\;/g;
    $string =~ s/\x{03A1}/&Rgr\;/g;
    $string =~ s/\x{03C3}/&sgr\;/g;
    $string =~ s/\x{03A3}/&Sgr\;/g;
    $string =~ s/\x{03C4}/&tgr\;/g;
    $string =~ s/\x{03A4}/&Tgr\;/g;
    $string =~ s/\x{03C5}/&ugr\;/g;
    $string =~ s/\x{03A5}/&Ugr\;/g;
    $string =~ s/\x{03C6}/&phgr\;/g;
    $string =~ s/\x{03A6}/&PHgr\;/g;
    $string =~ s/\x{03C7}/&khgr\;/g;
    $string =~ s/\x{03A7}/&KHgr\;/g;
    $string =~ s/\x{03C8}/&psgr\;/g;
    $string =~ s/\x{03A8}/&PSgr\;/g;
    $string =~ s/\x{03C9}/&ohgr\;/g;
    $string =~ s/\x{03A9}/&OHgr\;/g;

    $string =~ s/\x{2229}/&cap\;/g; # adding conversion of intersection sign for FBco


    $string =~ s/\<\/down\>/\]\]/g;
    $string =~ s/\<down\>/\[\[/g;
    $string =~ s/\<up\>/\[/g;
    $string =~ s/\<\/up\>/\]/g;

    return ($string);

}


sub sgml2utf {


# adapted from toutf subroutine in proforma parsing Util.pm moduel
# NOTE, this does not 'protect' literal square brackets denoted by
# '[' or ']' or "[" or "]" so should not be used in code for synonym
# fields, but only for valid symbol fields, and if there are any cases
# where the valid symbol of something has a literal [] instead of <up></up>
# then it will incorrectly convert these (since we only use '[' or ']' or "[" or "]"
# in synonym fields I think), but the number of symbols with  are few and far between
# so hopefully won't be an issue. May have to do special end-around for FBsf as have []
# not <up></up>, and not sure about strain, but the rest appear to use <up></up>

    my ($string) = $_[0];

### without the following unless loop, if a user enters a genuine greek symbol 
### e.g. ζ or Δ in the valid symbol field of a proforma (x1a) then the query in
### valid_symbol that populates 'my $symlist' does not work even if the symbol IS
### valid e.g. 14-3-3ζ (FBgn0004907) or Df(2R)Δ5kb (FBab0044978) [valid as of 7.2.2019].
### If the unless loop is present, then the query does work, and returns the FBid and validity
### status as for a 'regular' symbol that either has no funky characters, or is in sgml format
### i.e. 14-3-3&zgr; or Df(2R)&Dgr;5kb.
### The debugging output is confusing as in both cases (unless loop present/absent) the ζ or Δ
### symbols 'look' the same in the terminal, but they must be in different formats at some
### machiney level.
### I *think* that this is to do with whether or not the string is in perl's internal utf-8 format
### when it is given to the chado query used to populate 'my $symlist' (and I guess the results of
### my testing show that it DOES need to be in perl's internal utf-8 format to work, since that
### is what the unless loop does [see email 'XORT UTF-8 problem']).
### Note, that since the valid symbols are stored in the %symbol_table as sgml format (i.e. &zgr;)
### then each time a symbol with an actual greek is encountered it has to do the full lookup again
### so if we do allow actual greek symbols in future, would need to also (?) store utf8 version (i.e. ζ)
### as well for speed efficiency.
### Adding the unless loop does not seem to break the chado query for 'regular' symbols from testing.
### Right now, curators are not allowed to put actual greek symbols in valid proforma fields (x1a) as
### the parser can't take it (there is a separate check for non-ASCII in these fields so if a curator
### did put in an put actual greek symbol when the unless loop is uncommented, they will still get an
### error message).
###
### I have uncommented the unless loop in case not having it breaks Peeves in some versions of perl/postgres
### (we have had similar issues in the past with other scripts and adding this test fixed the problem).
### [gm190207].

	unless (utf8::is_utf8($string)) {
    	$string = decode("utf-8",$string);

	}


    $string =~ s/&agr\;/\x{03B1}/g;
    $string =~ s/&Agr\;/\x{0391}/g;
    $string =~ s/&bgr\;/\x{03B2}/g;
    $string =~ s/&Bgr\;/\x{0392}/g;
    $string =~ s/&ggr\;/\x{03B3}/g;
    $string =~ s/&Ggr\;/\x{0393}/g;
    $string =~ s/&dgr\;/\x{03B4}/g;
    $string =~ s/&Dgr\;/\x{0394}/g;
    $string =~ s/&egr\;/\x{03B5}/g;
    $string =~ s/&Egr\;/\x{0395}/g;
    $string =~ s/&zgr\;/\x{03B6}/g;
    $string =~ s/&Zgr\;/\x{0396}/g;
    $string =~ s/&eegr\;/\x{03B7}/g;
    $string =~ s/&EEgr\;/\x{0397}/g;
    $string =~ s/&thgr\;/\x{03B8}/g;
    $string =~ s/&THgr\;/\x{0398}/g;
    $string =~ s/&igr\;/\x{03B9}/g;
    $string =~ s/&Igr\;/\x{0399}/g;
    $string =~ s/&kgr\;/\x{03BA}/g;
    $string =~ s/&Kgr\;/\x{039A}/g;
    $string =~ s/&lgr\;/\x{03BB}/g;
    $string =~ s/&Lgr\;/\x{039B}/g;
    $string =~ s/&mgr\;/\x{03BC}/g;
    $string =~ s/&Mgr\;/\x{039C}/g;
    $string =~ s/&ngr\;/\x{03BD}/g;
    $string =~ s/&Ngr\;/\x{039D}/g;
    $string =~ s/&xgr\;/\x{03BE}/g;
    $string =~ s/&Xgr\;/\x{039E}/g;
    $string =~ s/&ogr\;/\x{03BF}/g;
    $string =~ s/&Ogr\;/\x{039F}/g;
    $string =~ s/&pgr\;/\x{03C0}/g;
    $string =~ s/&Pgr\;/\x{03A0}/g;
    $string =~ s/&rgr\;/\x{03C1}/g;
    $string =~ s/&Rgr\;/\x{03A1}/g;
    $string =~ s/&sgr\;/\x{03C3}/g;
    $string =~ s/&Sgr\;/\x{03A3}/g;
    $string =~ s/&tgr\;/\x{03C4}/g;
    $string =~ s/&Tgr\;/\x{03A4}/g;
    $string =~ s/&ugr\;/\x{03C5}/g;
    $string =~ s/&Ugr\;/\x{03A5}/g;
    $string =~ s/&phgr\;/\x{03C6}/g;
    $string =~ s/&PHgr\;/\x{03A6}/g;
    $string =~ s/&khgr\;/\x{03C7}/g;
    $string =~ s/&KHgr\;/\x{03A7}/g;
    $string =~ s/&psgr\;/\x{03C8}/g;
    $string =~ s/&PSgr\;/\x{03A8}/g;
    $string =~ s/&ohgr\;/\x{03C9}/g;
    $string =~ s/&OHgr\;/\x{03A9}/g;

    $string =~ s/&cap\;/\x{2229}/g; # adding conversion of intersection sign for FBco


    $string =~ s/\]\]/\<\/down\>/g;
    $string =~ s/\[\[/\<down\>/g;
    $string =~ s/\[/\<up\>/g;
    $string =~ s/\]/\<\/up\>/g;


#    $string =~ s/BEFORE/\[/g;
#    $string =~ s/AFTER/\]/g;

    return ($string);

}

sub check_unattributed_synonym_correction {

# subroutine to check that the valid symbol of an object
# is in the symbol synonym field when !c-ing that field
# for the 'unattributed' pub (this is required, else the
# object ends up with no valid symbol in chado!)

	my ($file, $num, $primary_symbol_field, $primary_symbol_data, $synonym_field, $synonym_data, $context, $specific_error_message) = @_;

# work out plingc status of field
	my $synonym_plingc = $context->{$synonym_field};
	$synonym_plingc =~ s/^(.*?)\s+$synonym_field\..*? :.*/$1/s;

	if (changes ($file, $synonym_field, $synonym_plingc)) {
		compare_multiple_line_fields_positive($file, $num, $primary_symbol_field, $primary_symbol_data, $synonym_field, $synonym_data, $context, "You must include the valid symbol in G1b when \!c-ing it under the 'unnattributed' publication.");
	}


}

sub get_species_prefix_from_symbol {
# subroutine to get the species prefix from a symbol.

# $symbol is the symbol to be checked
# $type is a reference to an array of the possible types that the symbol can be.
# This is usually a reference to the $standard_symbol_mapping->{$symbol_type}->{id}
# array, but does not have to be.  It is used to determine whether a sub-portion of
# the original symbol should be tested, and what regular expression should be used for
# the test.  The subroutine can currently only cope if the array contains a single value.

	my ($symbol, $type) = @_;


	my ($symbol_type, $species_prefix, $backslash);

	unless ($#{$type} > 0) {

		$symbol_type = join '', @{$type};

	} else {

		print ("***MAJOR PEEVES ERROR in species prefix checking: there is a call to get_species_prefix_from_symbol to check a symbol that could be from multiple types, and the subroutine cannot cope with this, so some checking involving the '$symbol' symbol may not be complete\n");

	}

	if ($symbol_type eq 'FBal') {

# this special reg exp for alleles makes sure that it will only take a species abbreviation
# from the gene part of the gene[superscript] allele symbol, as the first captured part
# must not contain [ or ].  This works as species abbreviations are not allowed to contain [ or ]
		my ($species_prefix, $backslash) = ($symbol =~ /^([^\\\[\]]*)(\\)?/);


##		warn "**Remaining from FBal: $symbol: prefix: ^$species_prefix^\n";

	} elsif ($symbol_type eq 'FBba') {

# this will not work correctly for the rare cases where the species abbreviation contains a -
		($species_prefix, $backslash) = ($symbol =~ /^([^\\-]*)(\\)?/);

##		warn "**Remaining from FBba: $symbol: prefix: ^$species_prefix^\n";

	} else {

# this reg exp should work for the remaining types. Cannot try to trap the \\ here to put into $backslash
# because if there is no backslash it does not cope

# originally had regexp of ($symbol =~ /^(T:)?(.+?)\\/) but this cannot be converted to try and trap the
# presence of a \ into $backslash simply be changing \\ to (\\?) because it does not cope when there is
# no backslash
# new regexp finds the longest string without a \ before any \ so it works when there *is* a \
# e.g. $species_prefix is 'springer' for 'springer\env', 'Dafs' for 'Dafs\gypsy\env'
# when there is no \, the entire symbol string ends up in species_prefix, but backslash is not
# initialised, so later on, the '' line overwrites the prefix with Dmel
#		(undef, $species_prefix) = ($symbol =~ /^(T:)?(.+?)\\/);
#		(undef, $species_prefix, $backslash) = ($symbol =~ /^(T:)?([^\\]*)(\\)?/);
# removed (T:)? from above as no longer relevant (tags now captured as experimental tools
# with no species info in symbol)
# Note, if allow curators to enter actual greek symbols in x1a fields, I don't think that the following 
# works - so would need to put it through utf2sgml first maybe ? (have not tested this)
		($species_prefix, $backslash) = ($symbol =~ /^([^\\]*)(\\)?/);

##		warn "**Remaining from $symbol: prefix: ^$species_prefix^\n";

	}

# for genes encoded by Dmel natTEs, the $species_prefix will incorrectly pick up
# the valid natTE symbol e.g. for springer\env, species_prefix will pick up 'springer'
# so check whether the $species_prefix is a valid FBte symbol, and if it is set
# $species_prefix to 'Dmel'.  Note that could add a double-check that in addition, the
# prefix must NOT be a valid species abbreivation, before changing, but this won't work
# until chado is tidied up to remove 'species' entries for natTEs.

	if ($species_prefix && valid_symbol($species_prefix,'FBte')) {

##		warn "FYI: re-setting species prefix of '$symbol' from '$species_prefix' to 'Dmel' for species cross-checks\n";
		$species_prefix = 'Dmel';

	}

# set to Dmel when there is no backslash in the symbol
	$backslash or $species_prefix = 'Dmel';

# do not check validity within subroutine as might result in multiple messages for same error.
# return value can be '' only in the case where there is a \ but nothing before it.
	return ($species_prefix);

}

sub get_allele_type {


# subroutine to get the 'type' of an allele in a proforma according to what GA10 fields are filled in.

# It is designed to check a single object at a time, not a dehashed list, and returns one of the following values:
# 'construct' - GA10a is filled in
# 'regular insertion' - one of GA10c/GA10e is filled in and the insertion is not a 'TI' insertion
# 'TI insertion' - one of GA10c/GA10e is filled in and the insertion is a 'TI' insertion
# 'classical' - none of the GA10a, GA10c, GA10e fields are filled in
# have not done any extra integrity checking as to whether multiple of GA10a, GA10c, GA10e are filled in at the same time.
# Note that $GA10a_value, $GA10c_value, $GA10e_value are all references to an array of
# values, since these GA10 fields can take multiple values 


	my ($allele, $GA10a_value, $GA10c_value, $GA10e_value) = @_;

	my $allele_type;




	if (defined $GA10a_value && $GA10a_value ne '') {
		$allele_type = 'construct';
	}  else {

		unless ((defined $GA10c_value && $GA10c_value ne '') || (defined $GA10e_value && $GA10e_value ne '')) {

			$allele_type = 'classical';

		} else {


			if (defined $GA10c_value && $GA10c_value ne '') {

			
				foreach my $insertion (@{$GA10c_value}) {

					$insertion =~ s/^NEW://;
					if ($insertion =~ m/^TI\{/) {
						$allele_type = 'TI insertion';
						return $allele_type; # return early since if there is any TI insertion, this should trump any additional regular insertion (this is true for cross-checks with GA30a-GA30f, not sure if will hold if use this subroutine for other cross-checks
					} else {
						$allele_type = 'regular insertion';
					}
				}

			} elsif (defined $GA10e_value && $GA10e_value ne '') {

				foreach my $insertion (@{$GA10e_value}) {

					$insertion =~ s/^NEW://;
					if ($insertion =~ m/^TI\{/) {
						$allele_type = 'TI insertion';
						return $allele_type; # return early since if there is any TI insertion, this should trump any additional regular insertion (this is true for cross-checks with GA30a-GA30f, not sure if will hold if use this subroutine for other cross-checks
					} else {
						$allele_type = 'regular insertion';
					}
				}
			}
		}
	

	}



	return $allele_type;
}


sub python_parser_field_stub {	
# Subroutine for fields that are not checked by Peeves because they are only implemented
# in the new Harvard python parser (and thus the checking is done in that).
# Does very basic checks and also issues a warning if the field is filled in,
# alerting curator that they need to run the record through the Harvard python parser for checking.

# and to indicate that Peeves does not yet check the field in detail.
	my ($file, $change, $code, $data, $context) = @_;
	
	changes ($file, $code, $change);

# get rid of any lines that just contain returns, as probably mostly harmless	
	$data = silent_trim_space($data);

	if (defined $data && $data ne '') {

# check for basic errors in character formatting		
		check_non_utf8 ($file, $code, $data);
		check_non_ascii ($file, $code, $data);
#check for ??
		double_query ($file, $code, $data);

		report ($file, "%s: This field is not checked by Peeves, because it is parsed using the new Harvard python parser and checks have been implemented in that. So you should run this record through the new Harvard python parser before loading.\n! %s\n" , $code, $context);
	}
}

1;					# Boilerplate
