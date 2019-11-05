# Code to parse multipub proformae

use strict;
our (%fsm, $want_next, $chado, %prepared_queries);
our $g_mp;							# The value in MP1, if any.

my ($file, $proforma);
my %proforma_fields;						# Keep track of what fields have already been seen
my @inclusion_essential = qw (MP1 MP2a MP11 MP17);		# Fields which must be present in the proforma

my @dummy_arry;							# Dummy to keep check_dups() happy.
my %dummy_dup_proforma_fields;			# Dummy to keep check_dups() happy.	
my $mp3_check;							# Whether to see if MP2[ab] is consistent with MP3.
my %mp_data = ();						# Store data for post-check phase.
my $mp_type = '';						# Communicate from MP17 to MP6 and MP11

# Beware: if the FB CV changes, we may need to change any code that compares $g_pub_type with a fixed string.
# Pay particular attention to validate_P{6,}11.  The next declarations may be helpful.

my $book_text  = 'book';
my $first_time = 1;

sub do_multipub_proforma ($$)
{
# Process a multipub proforma, the text of which is in the second argument which has been read from the file
# named in the first argument.

    if ($first_time)					# Sanity clause.
    {
	valid_symbol ($book_text, 'FBcv:pub_type')  or warn "$book_text is no longer a valid publication type!\n";
	$first_time = 0;
    }

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dummy_dup_proforma_fields = ();
	@dummy_arry = ();
    $g_mp = '';
    $mp3_check = 0;
    %mp_data = ();

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?) (MP1)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    validate_MP1 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (MP3)\.\s*(.*?)\s*\*.*:(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $4);
	    double_query ($file, $2, $4) or validate_MP3 ($2, $1, $4);
	    report($file, "$2: Invalid proforma field '$3'.") if($4 ne '');	    
	}
	elsif ($field =~ /^(.*?) (MP17)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_MP17 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (MP18)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_MP18 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (MP19)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_MP19 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (MP2[ab])\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_MP2ab ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (MP15)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_MP15 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (MP6)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_MP6 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (MP11)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dummy_dup_proforma_fields, \@dummy_arry, 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_MP11 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) MP(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*MP.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in multipub.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n!%s", $field);
		}
	}
    }

# Tests that can only be done after parsing the entire proforma.

    check_presence ($file, \%proforma_fields, \@inclusion_essential, undef);

    if ($mp3_check)
    {
	my ($title, $mp) = ('', '');
	my $message = "MP3 claims '%s' given in %s is new but Chado already knows '%s' as %s --- is it really new?";

	exists $mp_data{'MP2a'} and $title = $mp_data{'MP2a'};
	if ($title ne '')
	{
	    $mp = chat_to_chado ('pub_id_from_miniref', $title)->[0]->[0];
	    $mp and report ($file, $message, $title, 'MP2a', $title, $mp);
	}
	exists $mp_data{'MP2b'} and $title = $mp_data{'MP2b'};
	if ($title ne '')
	{
	    $mp = chat_to_chado ('pub_id_from_title', $title)->[0]->[0];
	    $mp and report ($file, $message, $title, 'MP2b', $title, $mp);
	}
    }

    $want_next = $fsm{'MULTIPUBLICATION'};
}

sub validate_MP1 ($$$)
{
# Reference unique ID.

    my ($code, $change, $mp_no) = @_;
    if ($mp_no eq ''){
	report ($file, "%s: Not allowed to be blank. It must be 'new' or a valid multipub ID.", $code, $mp_no);			# Absence of data is no longer permissible.
	return;
    }
    changes ($file, $code, $change) and report ($file, "%s: Can't change the multipub_id of a multipub!", $code);
    $mp_no = trim_space_from_ends ($file, $code, $mp_no);

    if ($mp_no =~ /^[1-9]\d*$/ and valid_symbol ("multipub_$mp_no", 'multipub'))
    {
	$g_mp = "multipub_$mp_no";
    }
    elsif($mp_no eq 'new'){}
    else
    {
	report ($file, "%s: %s is not a valid multipub ID. It must be 'new' or a valid multipub ID", $code, $mp_no);
    }
}

sub validate_MP3 ($$$)
{
# The data must be either 'y' or 'n'.
#
# If the data is 'y', MP1 must be empty and MP2a, (and MP2b if given), must not be present in Chado.
#
# If the data is 'n', MP1 must have data and it must be the id of an existing multipub held in Chado.

    my ($code, $change, $yorn) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    $yorn = trim_space_from_ends ($file, $code, $yorn);

    if ($yorn eq '')
    {
	report ($file, "%s: Missing data --- it must be y or n.", $code);
    }
    elsif ($yorn eq 'y')
    {
	$g_mp eq '' or report ($file, "%s: can not have 'y' when MP1 has data (where you gave %s).",
				   $code, substr ($g_mp, 9));
# Other checks done in the post-check phase.
	$mp3_check = 1;
    }
    elsif ($yorn eq 'n')
    {
	$g_mp eq '' and
	    report ($file, "%s: Can't have 'y' when MP1 doesn't specify an existing multipub id in Chado.", $code);
    }
    else
    {
	report ($file, "%s: Data must be y or n but you gave '%s'.", $code, $yorn);
    }
}

sub validate_MP17 ($$$)
{
# MP17 specifies the type of the multipub.  It is a required field if MP1 is empty (marked by $g_mp being
# '') and its value must be taken from a subset of publication namespace in the FB ontology --- those with
# type "MP17_ref".

    my ($code, $change, $type) = @_;
    my $existing_type;

    $type = trim_space_from_ends ($file, $code, $type);
    $change = changes ($file, $code, $change);

# First deal with the case of no data.  We're not allowed to change (i.e. delete) the multipub type to
# nothing.  If we're not trying to change it, then $g_mp must be set, otherwise we're not filling in a
# mandatory piece of information.

    if (!defined $type or $type eq '')
    {
	if ($change)
	{
	    report ($file, "%s: Not allowed to delete multipub type", $code);
	}
	else
	{
	    report ($file, "%s: Can't omit multipub type without valid data in MP1", $code) if $g_mp eq '';
	}
	return;
    }

# Now know there is data.  Does it come from the CV?

    unless ($mp_type = valid_symbol ($type, 'MP17_ref'))
    {
	report ($file, "%s: %s is not a valid multipub type", $code, $type);
	$mp_type = $type;
	return
    }

    if ($g_mp)
    {

# If it's data for an existing multipub (i.e. $g_mp has a value) emit warnings if MP17 is
# changing it to the same thing, or if it is not changing it and there is a mismatch with the
# data in Chado.

	$existing_type = chat_to_chado ('pub_pubtype', $g_mp)->[0]->[0];

	unless (defined $existing_type)		# This should not be able to happen!
	{
	    my $catastrophe = "%s: Trying to change type of %s to %s but the multipub's type isn't in Chado.\n";
	    $catastrophe .= "Chado should always have this data, so you've found a serious bug.\n";
	    $catastrophe .= "****** PLEASE CONTACT camdev URGENTLY! ******";
	    report ($file, $catastrophe, $code, $g_mp, $type);
	    return;
	}
	if ($change)
	{
	    if ($type eq $existing_type)
	    {
		report ($file, "%s: Trying to change multipub type to the value (%s) it already has in Chado",
			$code, $type);
	    }
	}
	else
	{
	    if ($type ne $existing_type)
	    {
		report ($file, "%s: Trying to set multipub type to '%s' but it has type '%s' in Chado",
			$code, $type, $existing_type);
	    }
	}
    }
    else		    # Data for a new multipub.  Must not be a change type.
    {
	report ($file, "%s: Can't change the type of a new multipub!", $code) if $change;
	$mp_type = $type;
    }
}

sub validate_MP18 ($$$)
{
    $_[2] and warn "$file: validate_MP18('$_[0]', '$_[1]', '$_[2]') stub called\n";
    $_[2] and report ($file, "Warning: I don't yet know how to deal with the '%s' proforma field.", $_[0]);
}

sub validate_MP19 ($$$)
{
# Delete a multipub.  The only valid value is the single character 'y' and even if this is given we must issue
# a warning because of the possibility of accidental data loss.

    my ($code, $change, $data) = @_;

    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    $data or return;		# Absence of data is always permissible.

    if ($data eq 'y')
    {
	if ($g_mp eq '')
	{
	    report ($file, "%s: the data in MP1 is not a valid multipub, according to Chado.", $code);
	}
	else
	{
	    report ($file, "%s: Do you REALLY want to delete %s?", $code, $g_mp);
	}
    }
    else
    {
	report ($file, "%s: Bad data '%s'", $code, $data);
    }
}

sub validate_MP2ab ($$$)
{

# MP2a contains an abbreviated title for a multipub and MP2b the full title.  MP2a is mandatory data when MP1
# has data; MP2b is not.  These are the only significant differences between the two and so the same code may
# be used to parse them.

    my ($code, $change, $title) = @_;

    my $query = $code eq 'MP2a' ? 'pub_miniref_from_id' : 'pub_title_from_id';
    my $type = $code eq 'MP2a' ? 'abbreviation' : 'title';

    $title = trim_space_from_ends ($file, $code, $title);
    $mp_data{$code} = $title;				# Squirrel away for post-check phase.

    if ($title eq '')
    {
	if (changes ($file, $code, $change))
	{
	    report ($file, "%s: Can't delete the reference %s of a multipub.", $code, $type);
	}
	else						# Mandatory for MP2a.
	{
	    $code eq 'MP2a' and $g_mp and
		report ($file, "%s: Must not omit reference %s of a multipub.", $code, $type);
	}
    }
    else
    {
	my $catastrophe = "%s: Looking for the %s for %s ";
	$catastrophe .= "but that information isn't yet in Chado.\n";
	$catastrophe .= "Chado should always have this data, so you've found a serious bug.\n";
	$catastrophe .= "****** PLEASE CONTACT camdev URGENTLY! ******";

	if (changes ($file, $code, $change))
	{
	    if ($g_mp ne '')			# Data for an existing multipub given in MP1
	    {
		my $existing_title = chat_to_chado ($query, $g_mp)->[0]->[0];

		if (defined $existing_title and $existing_title ne '')
		{
		    $existing_title eq $title and
			report ($file, "%s: Can't change the reference %s " .
				"to the same value '%s' as it already has in Chado",
				$code, $title, $existing_title);
		}
		else
		{
		    report ($file, $catastrophe, $code, $type, $g_mp);
		}
	    }
	}
	else
	{
	    if ($g_mp ne '')			# Data for an existing multipub given in MP1
	    {
		my $existing_title = chat_to_chado ($query, $g_mp)->[0]->[0];

		if (defined $existing_title and $existing_title ne '')
		{
		    $existing_title eq $title or
			report ($file,
				"%s: You gave the %s '%s' but Chado thinks %s has the %s '%s'.",
				$code, $type, $title, $g_mp, $type, $existing_title);
		}
		else
		{
		    report ($file, $catastrophe, $code, $type, $g_mp);
		}
	    }
	    else
	    {
		# No checks possible because this proforma defines a new multipub.
	    }
	}
    }
}

sub validate_MP15 ($$$)
{

# The optional data is one or more ISBN and/or ISSN.  It may be possible to decide which it ought to be in
# particular circumstances but for the moment we'll accept either or both.  ISBN-10 have not been valid since
# 20070101 so complain, but be helpful and say what the corresponding ISBN-13 should be.

# Eventually we'll check the value in Chado too.

    my ($code, $change, $isxn_list) = @_;
    $change = changes ($file, $code, $change);			# Call changes() to check for junk after initial !
    $isxn_list = trim_space_from_ends ($file, $code, $isxn_list);

    foreach my $isxn (split ('\n', $isxn_list))
    {
	$isxn = trim_space_from_ends ($file, $code, $isxn);
	next if $isxn eq '';					# Absence of data is always permissible.

	if (valid_issn ($isxn))
	{
	    # Nothing to do.
	}
	elsif (my $isbn13 = convert_to_ISBN13 ($isxn))		# Returns zero if not valid ISBN-10 or ISBN-13
	{
	    $isxn eq $isbn13 or report ($file,
					"%s: Please change the ISBN-10 %s to the ISBN-13 equivalent, which is %s",
					$code, $isxn, $isbn13);
	}
	else
	{
	    report ($file, "%s: Invalid ISSN or ISBN '%s'", $code, $isxn);
	}
    }
}

sub validate_MP6 ($$$)
{
# Publication year(s).  Either a single year or a range of years separated by '--' or a single year followed
# by a '--' for a live publication.

    my ($code, $change, $dates) = @_;
    $change = changes ($file, $code, $change);
    $dates = trim_space_from_ends ($file, $code, $dates);

    if ($dates eq '')
    {
	$change and report ($file, "%s: Do you REALLY want to delete the date of publication for %s?",
			    $code, $g_mp);
	return;
    }

    if (index ($dates, "\n") >= 0)
    {
	report ($file, "%s: Must not have newlines in date of publication '%s'.", $code, $dates);
	return;
    }

    my ($year1, $range, $year2);
    ($year1, $range) = ($dates =~ /^(\d{4})(.*)/);

    unless (defined $year1)
    {
	report ($file, "%s: Invalid format for year range '%s'", $code, $dates);
	return;
    }
    bad_date ($file, $code, $year1);

    if ($range ne '')
    {
	($range, $year2) = ($range =~ /^(-+)(.*)$/);
	unless ($range eq '--')
	{
	    report ($file, "%s: You need to use a '--' in the year range but gave '%s'", $code, $dates);
	    return;
	}
    }
    if (defined $year2 and $year2 ne '')
    {
	if ($year2 =~ /\d{4}/)
	{
	    bad_date ($file, $code, $year2);
	    unless ($year2 > $year1)
	    {
		report ($file, "%s: Second year in range '%s' is not after the the first!", $code, $dates);
		return;
	    }
	}
	else
	{
	    report ($file, "%s: Invalid format for second year in range '%s'.", $code, $dates);
	    return;
	}
    }

# If we get this far the year range exists and looks ok.  Check the value against that in Chado, if any, and
# perform the usual !c checks.

    if ($change)
    {
	if ($g_mp ne '')			# Data for an existing multipub given in MP1
	{
	    my $existing_dates = chat_to_chado ('pub_date_from_id', $g_mp)->[0]->[0];

	    if (defined $existing_dates and $existing_dates ne '' and $existing_dates eq $dates)
	    {
		report ($file, "%s: Can't change the publication date " .
			"to the same value '%s' as it already has in Chado", $code, $dates);
	    }
	}
    }
    elsif ($g_mp ne '')			# Data for an existing multipub given in MP1
    {
	my $existing_dates = chat_to_chado ('pub_date_from_id', $g_mp)->[0]->[0];

	if (defined $existing_dates and $existing_dates ne '')
	{
	    $existing_dates eq $dates or
		report ($file, "%s: You gave a publication date of '%s' but Chado thinks %s has '%s'.",
			$code, $dates, $g_mp, $existing_dates);
	}
    }
}

sub validate_MP11 ($$$)
{

# MP11 specifies the list of editors for the publication.  It is required data for a book and must be blank
# for other types of multipubs.

    my ($code, $change, $editors) = @_;
    $change = changes ($file, $code, $change);

    $editors = trim_space_from_ends ($file, $code, $editors);
    $editors =~ /\n\n/ and report ($file, "%s: Blank line not allowed in %s", $code, $editors);

    if ($editors eq '')
    {
	$mp_type eq $book_text and
	    report ($file, "%s: Editors must not be blank when MP17 is '$mp_type'", $code, $mp_type);
	return;			# Absence of data required for all other types.
    }
    else
    {
	if ($mp_type ne $book_text)
	{
	    report ($file, "%s: Editors must be blank when MP17 is '$mp_type'", $code, $mp_type);
	    return;
	}
    }

# First deal with the case of no data.  We're not allowed to change (i.e. delete) the list of editors to
# nothing.  If we're not trying to change it, then $g_mp must be set, otherwise we're not filling in a
# mandatory piece of information.

    unless (defined $editors and $editors ne '')
    {
	if ($change)
	{
	    report ($file, "%s: Not allowed to delete list of editors.", $code);
	}
	else
	{
	    report ($file, "%s: Can't omit list of editors without valid data in MP1", $code) if $g_mp eq '';
	}
	return;
    }

# Each editor must have a surname, a \t and a list of initials.  Check for old-style data where the initials
# came first and could be omitted (this latter now uses '?.').

    my $fail = 0;
    foreach my $editor (split ("\n", $editors))
    {
	$editor = trim_space_from_ends ($file, $code, $editor);
	next if $editor eq '';						# Blank lines already picked up above.

	if (my ($surname, $initials) = ($editor =~ /^(.*?)\t(.*)/))
	{
	    unless ($initials =~ /^([A-Z?]\.)([A-Z]\.)*$/)
	    {
		report ($file, "%s: Invalid initials '%s' in '%s'", $code, $initials, $editor);
		$fail = 1;
	    }
	    index ($surname, '.') == -1 or report ($file, "%s: The surname '%s' in '%s' has a dot.  Is this right?",
						   $code, $surname, $editor);	# Warning only, don't set $fail.
	}
	elsif ($editor =~ /^(([A-Z?]\.)([A-Z]\.)*) (\S[^?\t]*$)/)
	{
	    report ($file, "%s: Old-style data in '%s'.  Please use \"%s\t%s\"", $code, $editor, $4, $1);
	    $fail = 1;
	}
	elsif (index ($editor, '.') == -1)
	{
	    report ($file, "%s: Must not omit editor's initials.  Use \"%s\t?.\" if they are unknown.",
		    $code, $editor);
	    $fail = 1;
	}
	else
	{
	    report ($file, "%s: Unrecognized format for editor '%s'.  Try checking whitespace and/or initials.",
		    $code, $editor);
	    $fail = 1;
	}
    }
    $fail and return;			# No need to check existing data if the given data is bad.

    if ($g_mp)			# There is data given, so check if it's a known publication.
    {

# If it's data for an existing publication (i.e. $g_mp has a value) emit warnings if MP11 is changing it to the
# same thing, or if it is not changing it and there is a mismatch with the data in Chado.  In either case, we
# need to ask Chado for its opinion beforehand.

	my $existing_editors_array = chat_to_chado ('pub_authors', $g_mp);

# The returned value is actually a reference to an array of arrays, or an undef array if there are no editors,
# which should not be possible.

	if (!defined $existing_editors_array)
	{
	    my $catastrophe = "%s: Looking for the existing list of editors for %s ";
	    $catastrophe .= "but that information isn't yet in Chado.\n";
	    $catastrophe .= "Chado should always have this data, so you've found a serious bug.\n";
	    $catastrophe .= "****** PLEASE CONTACT camdev URGENTLY! ******";
	    report ($file, $catastrophe, $code, $g_mp);
	    warn sprintf ($catastrophe, $code, $g_mp);		# Be really, really insistent.
	    return;
	}

# Assuming there is at least one editor, each element of the returned value is an array with two elements, the
# givennames and the surname of each editor.  The arrays are already sorted by rank, which is exactly the
# order we need.  Convert this data structure to a simple string where each editor appears on a separate line.

	foreach my $editor (@{$existing_editors_array})
	{
	    defined $editor->[0] or $editor->[0] = '?.'; # Convert missing initial to '?'
	}

# The innermost "map { join ..." puts the tab character between the family names and the initials of each editor.

	my $existing_editors = join ("\n", map { join "\t", @{$_} } @{$existing_editors_array});

	if ($change)
	{
	    if ($editors eq $existing_editors)
	    {
		report ($file, "%s: Trying to change list of editors to the value\n%s\n it already has in Chado.",
			$code, $editors);
	    }
	}
	else
	{
	    if ($editors ne $existing_editors)
	    {
		report ($file, "%s: Trying to set list of editors to %s but it is\n%s\n in Chado.",
			$code, $editors, $existing_editors);
	    }
	}
    }
    else	    # Data for a new publication.  Must not be a change type but otherwise nothing else to do.
    {
	report ($file, "%s: Can't change the editors of a new publication!") if $change;
    }
}

1;				# Standard boilerplate.
