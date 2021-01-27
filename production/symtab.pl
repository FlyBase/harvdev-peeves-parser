#!/usr/bin/perl -w
use strict;

# Routines and data structures to support symbol checking.

our $chado;				# Data structure for interfacing to Chado.
our %prepared_queries;

# each chado type has the FBid type as the key and the main table where the type is stored in the database as the value
# [change from previous version where value was '1' for all - gm141126].  This allows different prepared chado queries
# to be called in the valid_symbol subroutine, so that Peeves looks in the correct place for symbol validity checking
# wrt what is in chado.
my %chadotypes = (

	'FBab' => 'feature',
	'FBal' => 'feature',
	'FBba' => 'feature',
	'FBcl' => 'simple_feature',
	'FBgn' => 'feature',
	'FBmc' => 'feature',
	'FBms' => 'feature',
	'FBti' => 'feature',
	'FBtp' => 'feature',
	'FBtr' => 'feature',
	'FBpp' => 'feature',
	'FBte' => 'feature',
	'FBsf' => 'feature',
	'FBto' => 'feature',

	'FBrf' => 'pub', # not using this value yet, but added in case useful in future
	'multipub' => 'pub', # not using this value yet, but added in case useful in future

	'FBlc' => 'library',
	'FBgg' => 'grp',
	'FBhh' => 'humanhealth', # NOTE: FBhh do not have valid symbol in chado, only name, but as not querying synonym table yet, just the main table where the type is stored (humanhealth in this case) should be able to use same kind of query as for other main tables.
	'FBtc' => 'cell_line',
	'FBsn' => 'strain',

	'FBin' => 'interaction', # FBin is a made up FBid type so that can re-use code in valid_symbol, but treat it as a special case (the uniquenames actually start with an FBrf id, so have to be careful not to pollute the FBrf part of the symbol table).

);


our %Peeves_config;

my $GO_obo    = "$Peeves_config{'Ontology_path'}/go-basic.obo";
my $GO_dbxref = "$Peeves_config{'Ontology_path'}/GO.xrf_abbs";
my $SO_obo    = "$Peeves_config{'Ontology_path'}/so.obo";
my $FBbt_obo  = "$Peeves_config{'Ontology_path'}/fly_anatomy.obo";
my $FBcv_obo  = "$Peeves_config{'Ontology_path'}/flybase_controlled_vocabulary.obo";
my $FBdv_obo  = "$Peeves_config{'Ontology_path'}/fly_development.obo";
my $DO_obo  = "$Peeves_config{'Ontology_path'}/doid.obo";
my $psi_mi_obo  = "$Peeves_config{'Ontology_path'}/psi-mi.obo";

# The symbol table is a hash of hashes, for which the primary key is the symbol name and the secondary key is
# its type.  If the symbol is invalid, its value is zero.  If the symbol is a deprecated term from an ontology
# its value is '' (the empty string) which allows the if(valid_symbol(sym,typ)) idiom to work as expected but
# also allows the distinction to be drawn between invalid and deprecated symbols if required.  Ontologies
# should never have the empty string in their data!

my %symbol_table;

sub create_symbol_table # for Jui
{	my ($aa,$bb,$cc) = @_; #$Peeves_version,$pcfg,$ccfg
	init_symbol_table($aa,$bb,$cc);
	my $pointer = \%symbol_table;
	return $pointer;
}

sub set_symbol ($$$)
{
# Set the symbol in the first argument, with type in the second, to the value in the third.

    $symbol_table{$_[0]}{$_[1]} = $_[2];
}

sub invalidate_symbol ($$)
{
# Invalidate the symbol in the first argument of type in the second, creating it if it doesn't already exist.

    $symbol_table{$_[0]}{$_[1]} = 0;
}

sub delete_symbol ($$)				# Delete the symbol of the specified type.
{
    my $symbol = $_[0];
    delete $symbol_table{$symbol}{$_[1]};
    return if keys %{$symbol_table{$symbol}};	# Any symbols still remaining?

# And there are no letters in the mailbox,
# and there are no grapes upon the vine,
# and there are no chocolates in the boxes anymore,
# and there are no diamonds in the mine.

    delete $symbol_table{$symbol};		# No, remove the entry entirely.
}

sub delete_chado_symbols ($)
{
# Remove all symbols named by the argument where they may subsequently be looked up again in Chado.  This
# function is used to flush symbols instantiated or invalidated by a curation record before going on to
# process the next record.  Inter-record reconciliation is not Peeves' task!

    my $symbol = $_[0];
    foreach my $key (keys %chadotypes)		# Only flush symbols of a restricted set of types.
    {
	delete $symbol_table{$symbol}{$key}
    }
    return if keys %{$symbol_table{$symbol}};	# Any symbols still remaining?
    delete $symbol_table{$symbol};		# No, remove the entry entirely.
}

sub valid_symbol ($$)
{
# If the first argument is a valid symbol of the type specified by the second argument, return its value.
# Otherwise return zero.

    my ($symbol, $type) = @_;

# We could test for either argument being undefined and return zero.  However, calling valid_symbol with undef
# arguments is almost certainly a bug for which an error message on stderr is a welcome indication.

# First the simple case in which the symbol is already in the symbol table.  Note that invalid symbols have a
# zero value if they appear in the table. The symbols for FlyBase objects that can contain utf8 (greek) characters
# and <up></up> or <down></down> type super-/sub-scripts in the synonym.sgml column in chado are stored in 'sgml'
# format in the Peeves %symbol_table (i.e. &agr;Tub67C[1]) as this is the format that curators currently use in
# curation and which is in the support files

   exists $symbol_table{$symbol}{$type} and return $symbol_table{$symbol}{$type};


# If the symbol is of a type that may exist in Chado, ask there, then cache the result in %symbol_table so we
# don't ask again. (Be careful not to destroy validity information of symbols instantiated in the curation
# record!)  Otherwise return zero (and no need to cache the result because the type test is so cheap that we
# may as well save the memory).

    if ($type eq 'uniquename')		# Uniquename is unique in Chado!  Does the symbol exist and is it obsolete?
    {
	$symbol =~ /^FB[a-z][a-z]\d{7,}$/ or return 0;		# Invalid symbol format (FBid). No need to cache the result.

# get the name of the primary table where the FBid is used as the uniquename, using the first 4 characters of the FBid being tested ($symbol)
# set 'feature' as a default table to prevent Peeves breaking if valid_symbol is called to check a uniquename whose FBid type isn't yet in the %chadotypes hash

	unless ($symbol =~ m/^FBtc/) {
		my $table = substr ($symbol, 0,4);
		$table = (defined $chadotypes{$table} ? $chadotypes{$table} : 'feature');

	
		my $chado_ref = chat_to_chado (sprintf("%s_symbol_from_id", $table), $symbol)->[0];
	
		if (defined $chado_ref)		# Does it exist?
		{
	    	my ($name, $obsolete) = @{$chado_ref};
			set_symbol ($symbol, $type, (defined $obsolete && $obsolete == 0) ? &utf2sgml($name) : 0);	# Is it obsolete?
	    	return $symbol_table{$symbol}{$type};
		}
		else
		{
		    invalidate_symbol ($symbol, $type);		# Doesn't exist, so undoubtedly invalid.
		    return 0;
		}

	} else {

		my $chado_ref = chat_to_chado ('cell_line_name_from_id', $symbol)->[0];

		if (defined $chado_ref) {
			my ($name) = @{$chado_ref};
			set_symbol ($symbol, $type, $name);
			return $symbol_table{$symbol}{$type};

		} else {
			invalidate_symbol ($symbol, $type);		# Doesn't exist, so undoubtedly invalid.
			return 0;
		}

	}
    }


## adding species information here

	if ($type eq 'chado_species_abbreviation') {

		my $chado_ref = chat_to_chado ('chado_species_abbreviation', $symbol);

#		warn Dumper ($chado_ref);

		foreach my $element (@{$chado_ref}) {
	    	my ($abbreviation, $genus, $species) = @{$element};

#			warn "Setting symbols: $symbol, $abbreviation, $genus, $species\n";
# set abbreviation as valid with value corresponding to full name of species
			set_symbol ($abbreviation, $type, ("$genus $species"));

# this OK as an abbreviation in chado should be unique, so should only ever go the
# foreach loop once
			return $symbol_table{$abbreviation}{$type};

		}

	}
	
	
	if ($type =~ m|^taxgroup:|) {

		my $chado_ref = chat_to_chado ('chado_species_taxgroup', $symbol);

#		warn Dumper ($chado_ref);

		foreach my $element (@{$chado_ref}) {
	    	my ($taxgroup) = @{$element};

# a species can potentially belong to more than one taxgroup, so need to set
# each taxgroup as a type, with the value set to '1'
			set_symbol ($symbol, "taxgroup:$taxgroup", '1');

		}
		
		return $symbol_table{$symbol}{$type};


	}

## end add species information

## adding database table information here

	if ($type eq 'chado database name') {

		my $chado_ref = chat_to_chado ('chado database name', $symbol)->[0];

		if (defined $chado_ref) {
			my ($name) = @{$chado_ref};
			set_symbol ($name, $type, '1');
			return $symbol_table{$name}{$type};

		} else {
			invalidate_symbol ($symbol, $type);		# Doesn't exist, so undoubtedly invalid.
			return 0;
		}
	  
	}

## end add database table information here


    $chadotypes{$type} or return 0;			# If the $type is not a key (i.e. an FBid type) in the %chadotypes hash the subroutine returns 0 here (and thus goes no further)

    if ($type eq 'FBrf' or $type eq 'multipub')
    {

# The symbol in this case is a full FBrf or multipub ID.  Only things which match FBrf\d{7} or multipub_\d+
# respectively can possibly be valid and only then do we need to ask Chado's opinion.

	$symbol =~ /^FBrf\d{7}$/ or $symbol =~ /^multipub_\d+$/ or return 0;	# No need to cache the result.

	my $obsolete = chat_to_chado ('pub_from_id', $symbol)->[0]->[0];

# A curation record can neither instantiate nor invalidate an FBrf nor a multipub ID so stomp on the symbol
# regardless.

	set_symbol ($symbol, $type, (defined $obsolete && $obsolete == 0));
    } elsif ($type eq 'FBtc') {

# cell_line has no 'is_obsolete' so cannot use else loop below

		my $chado_ref = chat_to_chado ('cell_line_id_from_name', $symbol)->[0];

		if (defined $chado_ref) {
			my ($id) = @{$chado_ref};
			set_symbol ($symbol, $type, $id);
			return $symbol_table{$symbol}{$type};

		} else {
			invalidate_symbol ($symbol, $type);		# Doesn't exist, so undoubtedly invalid.
			return 0;
		}
	  

    }
	else
    {

# this else loop will be used for any FBid type other than 'cell_line', 'FBrf' or 'multipub' that is listed as a key in the %chadotypes hash

## useful for de-bugging
##	warn "else loop: FBid type: $type, symbol: $symbol, chadotypes,type: $chadotypes{$type}\n";

# get the name of the chado table to be queried, using the $type given.
# do not need a default, as will only get this far in the subroutine if the FBid $type given to check against is in
# the %chadotypes hash

	my $symlist = undef;

# convert to utf8 format for query for those types that use synony.synonym_sgml to store the valid symbol
# (this is pretty much every type of 'thing' apart from FBcl

	unless ($type eq 'FBcl') {

## see also comments in tools.pl sgml2utf and get_species_prefix_from_symbol subroutines for situation if
## symbol contains utf8 greek symbols to start with (at the moment this still trips a 'non-ASCII' error)
		my $utf_symbol = &sgml2utf($symbol); # utf8 version to use in query

		$symbol = &utf2sgml($utf_symbol); # explicitly sgml-ise the symbol, in case original symbol was a mixture of utf8 and sgml types, so that what is stored in symbol table is definitely sgml version. Put this back into $symbol (even though this is scary), so that the rest of the subroutine works without having to re-do this kind of conversion again later outside this loop.
		$symlist = chat_to_chado (sprintf("%s_id_from_symbol", $chadotypes{$type}), $utf_symbol);

	} else {

		$symlist = chat_to_chado (sprintf("%s_id_from_symbol", $chadotypes{$type}), $symbol);

	}
## useful for de-bugging
##	warn "symlist returned from chado\n";
##	warn Dumper ($symlist);
##	warn "symbol_table state for $symbol BEFORE going through symlist pairs\n";
##	warn Dumper ($symbol_table{$symbol});

# $symlist now contains a list of (uniquename is_obsolete) pairs.  Store the results in the symbol table,
# being careful to preserve pre-existing validity information.
# Validity always trumps invalidity.  Careful with pre-instantion phase invalidity!
# The following note now only applies to the 'simple_feature' type of search (i.e. for FBcl) as for the
# other searches, the sql now includes a thing.is_obsolete = 'f' style component
# Note that a symbol.type pair may be both valid and invalid depending on context.  For instance, 'amn' is
# in the feature table more than once:
# with is_obsolete = 'f' for the uniquename 'FBgn0086782' **this is the valid symbol and uniquename combination**
# and with is_obsolete = 't' for the uniquename 'FBgn0000076'
# At the end of the foreach loop, any {$symbol}{FBid type} combination that has the value '__INVALID__' is one that
# is only present in a chado table as is_obsolete = 't' (i.e. no is_obsolete = 'f' line is also present for that symbol)
# and which has no pre-instantiation phase information to trump that.

# Note also that even though valid_symbol must have been called with $type corresponding to a particular FBid type
# (e.g. FBgn, FBgg) to get to this point in the subroutine, the query used above to get $symlist does not
# use that FBid type, it simply queries the table that this FBid type is found in (the value of $chadotypes{$type})
# for all cases where $symbol is in the name column of that table and returns all (uniquename is_obsolete) pairs.
# This means that e.g. if valid_symbol is called like so:
# valid_symbol('a[1]','FBgn')
# where an allele symbol has incorrectly been put in a gene field,
# then the pair ('FBal0000040', 0) is returned, since it looks for all cases of a[1] in the feature table
# not just cases where the uniquename is of the type 'FBgn'. All pairs returned are then assessed for validity,
# and if appropriate added to the symbol table.
# So in the example above, a[1] would be added to the symbol table as  $symbol_table{'a[1]'}{FBal} = 'FBal0000040'
# (unless this was trumped by some pre-instantion phase information).
# This feature turns out to be useful as it means that the following foreach loop adds all the results it found
# for the tested $symbol from a whole chado table (e.g. feature) BUT care has to be taken to make sure that $symbol_table
# is only populated for those cases in the same table where the symbols are stored in the same way in the database, to
# make sure that only the correct combinations are invalidated - this is why the test $chadotypes{$key} eq $chadotypes{$type}
# has been added to the if loop.
# The foreach loop below only adds information for the FBid type(s) where it got (uniquename is_obsolete) data back
# from the chado table and ONLY where the **. The gaps for the remaining FBid type(s) that also live in that chado table are filled in
# later on, in the final foreach loop of the subroutine. Now that this else loop can query different chado tables
# depending on the $type of FBid given when valid_symbol is called, extra care must be taken in the final foreach
# loop of the subroutine (see **NOTE** below).

	foreach my $pair (@{$symlist})
	{
	    my ($id, $obsolete) = @{$pair};
	    my $key = substr ($id, 0,4);

# special case required for interactions so don't pollute the FBrf part of the symbol table
# and put the interaction ids in their own space for checking
		if ($type eq 'FBin') {
			$key = $type;
		}


		if ($chadotypes{$key} && $chadotypes{$key} eq $chadotypes{$type}) {
			next if exists $symbol_table{$symbol}{$key} and $symbol_table{$symbol}{$key} ne '__INVALID__';
			set_symbol ($symbol, $key, $obsolete ? '__INVALID__' : $id);
		}
	}

## useful for de-bugging
##	warn "symbol_table state for $symbol AFTER going through symlist pairs:\n";
##	warn Dumper ($symbol_table{$symbol});


    }

# The following foreach loop is only run when the $type given is one of the FBid types listed as a key in %chadotypes
# (including FBrf or multipub).
# It adds information to the symbol_table for {$symbol}{FBid type} combinations that must be invalid based on earlier tests
# done in either the 'FBrf/multipub if loop' or the 'else loop that deals with the rest of the FBid types'.
# It does two things:
# 1. any {$symbol}{FBid type} combinations that have ended up with the value '__INVALID__' are passed through
# invalidate_symbol, which converts the value to zero. This is required to get the correct error messages, since
# many valid_symbol calls check whether or not the return value is true, and is why simply deleting this foreach
# loop is not an option.  These combinations will be {$symbol}{FBid type} combinations that are only present in a
# chado table as is_obsolete = 't' (i.e. no is_obsolete = 'f' line is also present for that symbol) and which have
# no pre-instantiation phase information to trump that.
# 2. it fills in the 'gaps' for other {$symbol}{FBid type} combinations that must be invalid because no results were
# found from the chado table query in the 'else loop that deals with the rest of the FBid types' (and there is no other
# pre-instantiation phase information to trump that).  **NOTE** Now that that else loop can query different chado tables
# depending on the $type of FBid given when valid_symbol is called, extra care has to be taken here to make sure that the
# following foreach loop only invalidates {$symbol}{FBid type} combinations that have actually been tested.
# To acheive this, the extra 'if ($chadotypes{$key} eq $chadotypes{$type})' requirement has been added, so that it only
# invalidates FBid types that live in the same chado table as the one queried in the else loop,
# ie. the chado table defined by the $type of FBid given when valid_symbol is called.
# I think that this will still do the right thing for FBrf/multipubs, but need to test further. [gm150410].



    foreach my $key (keys %chadotypes)		# Everything else is invalid.
    {

# only invalidate those FBid types that live in the same chado table AND whose valid symbol as stored the same way
# as the FBid type that was given when valid_symbol was called.
	if ($chadotypes{$key} eq $chadotypes{$type}) {
		next if exists $symbol_table{$symbol}{$key} and $symbol_table{$symbol}{$key} ne '__INVALID__';
		invalidate_symbol ($symbol, $key);
	}
    }

## useful for de-bugging
##	warn "Final symbol_table state for $symbol before end of valid_symbol:\n";
##	warn Dumper ($symbol_table{$symbol});


    return $symbol_table{$symbol}{$type};
}

sub valid_chado_symbol_used_in_cross_check_FBid_symbol ($$)
{
# As valid_symbol(), except that the symbol must exist as a non-obsolete symbol of the requisite type in
# Chado.  That is, pre-instantiation of symbols doesn't count towards validity.

     my ($symbol, $type) = @_;
     my $value = valid_symbol ($symbol, $type);

# think that the following is a bug - if a symbol has been put in a 'rename' field, it will have been
# invalidated (i.e. its value set to 0), but it could still be in chado, but because its in a rename field, it will return 0 here
# so its not really checking against chado because if its a symbol in a rename field, it never gets past here
     $value or return 0;			# Undoubtedly invalid, even in the presence of pre-instantiation.


     $value =~ /^good_.+/ or return $value;	# Pre-instantiation prepends 'good_' to the symbol.
     delete_symbol ($symbol, $type);		# Delete the pre-instantiated version.
     my $rv = valid_symbol ($symbol, $type);	# Find out whether it's *really* in Chado
     $symbol_table{$symbol}{$type} = $value;	# Restore status quo.
     return $rv					# Return true Chado validity.
}

sub descendents_of ($$%)
{
# Find all the descendents of the node in the second argument in the pedigree hash given by the third, then
# enter them into the symbol table with the type given in the first argument.  Note it is important that the
# hash be passed by value and not by reference because we'll be performing surgery on it and should not
# destroy the original data in case descendents_of() needs to be called again with a different node.
# Note - this may not be reliable if multiple inheritance is present. In future, should probably be replaced or populated by ontology server query. (DOS).

    my $type = shift;
    my $adam = shift;
    my %pedigree = @_;

    my $changes = 1;
    while ($changes)
    {
	$changes = 0;
	while (my ($object, $parent) = each (%pedigree))
	{
	    if ($parent ne $adam and defined $pedigree{$parent} and $pedigree{$parent} eq $adam)
	    {
		$pedigree{$object} = $adam;
		$changes = 1;
	    }
	}
    }

# At this point, all the nodes which are descendents of $adam have their parents marked as $adam.  Put them into
# the symbol table.

    while (my ($object, $parent) = each (%pedigree))
    {
	set_symbol ($object, $type, 1) if $parent eq $adam;
    }
}




sub GO_dbxrefs ($)
{
# Store the abbreviated name of a database which has been blessed by the GO consortium.  Don't bother storing
# any other information because it is presently much too hard to validate any data which may appear in a
# curation record with that which is held in an external database.

    my $version;
    local $/ = "\n\n";						# OBO terms are separated by double-newline.
    open (ONT, $_[0]) or die "$0: Can't open ontology file $_[0]\n";
    while (my $term = <ONT>)
    {
	$version or ($version) = ($term =~ /\n!date: \$Date: (.+) \$\n/);
	set_symbol ($1, 'GO_database', 1) if $term =~ /abbreviation: (.+)/;
	print '';
    }
    close (ONT);
    $version and set_symbol ('Ontologies', '_Peeves_',
			      valid_symbol ('Ontologies', '_Peeves_') . "GO_dbxrefs: $_[0] dated $version\n");
}



sub process_ontology_file {

# Generic subroutine for processing and storing information from
# an obo format ontology file.

	my ($ontology_file, $id_format, $store_id, $ancestors) = @_;
	
	unless ($store_id == 1 || $store_id == 0) {
		print "***MAJOR PEEVES ERROR in basic ontology processing: there is a call to the 'process_ontology_file' subroutine where the '\$store_id\' variable is not set to either '0' or '1' - let Gillian know so this can be fixed.\n\n";
	}

	my $id_type = $id_format;
	$id_type =~ s/:.+//;

	my ($term, $name, $id, $namespace, $version, $annotation_check);
    
# Store immediate parent->child relationship for each term that is a parent.
# Format is $pedigree->{$immediate_parent}->{$child}
	my $pedigree = {};

	local $/ = "\n\n"; # OBO terms are separated by double-newline.

	open (ONT, $ontology_file) or die "$0: Can't open ontology file $ontology_file\n";
	
	while ($term = <ONT>) {
		$version or ($version) = ($term =~ /\ndate: (.+)\n/);
		
		if ($term =~ /default-namespace: (.+)/) {
			next;
		}
		
		next if $term =~ /\nis_obsolete: true\n/; # Not interested in obsolete things.

		next unless ($name) = ($term =~ /\nname: (.+)/);
		next unless ($id) = ($term =~ /\nid: ($id_format)/);

		($namespace) = ($term =~ /\nnamespace: (.+?)\n/s);
		
# If the term is deprecated, reset 'id' to ''. This allows distinction to be made between obsolete and deprecated terms if desired (not currently being used to distinguish).
		$term =~ /\nsubset: deprecated/ and $id = '';

# Store the name and id pairs.
# First store based on term name.

# Always store under the 'default' namespace for the ontology
		set_symbol ($name, "$id_type:default", $id); # Use the namespace to 'type' the valid term name.
# If there is a more specific namespace for the particular term, also store under that
		if ($namespace) {
			set_symbol ($name, "$id_type:$namespace", $id); # Use the namespace to 'type' the valid term name.
		}

		
# Second, in some cases, it is also useful to store by id (so can provide suggestions in case of
# errors for lines of the format 'term ; id').
		if ($store_id) {

# only store for non-deprecated terms
			if ($id) {
				set_symbol ($id, "$id_type:default:id", $name);
				if ($namespace) {
					set_symbol ($id, "$id_type:$namespace:id", $name);
				}				
			}	
		}

# record if term should not be used in annotation

		($annotation_check) = ($term =~ /\nsubset: .*?(do_not_(manually_)?annotate)\n/);
		if ($annotation_check) {
			set_symbol ($name, "$id_type:$annotation_check", $id);
		}


# get all immediate 'is_a' parents - currently storing by term name.
		while ($term =~ /\nis_a: ($id_format) \! (.+)/g) {
			$pedigree->{$2}->{$name}++;
# commented out line below shows the line needed to store by id
#			$pedigree_by_id->{$1}->{$id}++;
		}

	}
	
	close (ONT);

# Find the children of each ancestor specified by the $ancestors data structure, if it contains data.

	if ($ancestors) {
		foreach my $ancestor (keys %{$ancestors}) {
	
# first check that the ancestor is still a valid term name in this ontology, and also has child terms
			if (exists $pedigree->{$ancestor}) {

    			&get_all_descendents_of ($id_type, $ancestor, $pedigree, $ancestors->{$ancestor}, $store_id);
		
			} else {
# ancestor is valid, but has no child term - should be rare, but can happen (e.g. SO:polypeptide), perhaps if anticipating
# possibility of child terms in future versions of an ontology.

				if (my $id = valid_symbol($ancestor,"$id_type:default")) {
					if ($ancestors->{$ancestor}) {
						set_symbol ($ancestor, "$id_type:$ancestor", $id);
						if ($store_id) {
							set_symbol ($id, "$id_type:$ancestor:id", $ancestor);
						}
					} else {
					
						print "***MAJOR PEEVES ERROR in basic ontology processing: Peeves has been asked to identify the descendants of \'$ancestor\' (but not store the \'$ancestor\' itself in the descendant tree), but it has no descendants  - let Gillian know so this can be fixed.\n\n";
					
					}
				
				} else {

					print "***MAJOR PEEVES ERROR in basic ontology processing: \'$ancestor\' is no longer a valid \'$id_type\' term, but Peeves has been asked to identify its descendents - let Gillian know so this can be fixed.\n\n";
				}
			}

		}
	}




    $version and set_symbol ('Ontologies', '_Peeves_', valid_symbol ('Ontologies', '_Peeves_') . "$id_type: $ontology_file dated $version\n");


}

sub get_all_descendents_of {

# Subroutine gets all is_a descendents of the $specified_ancestor term,
# using information in the supplied $pedigree data structure.
# The descendents are then stored in the symbol table, typed using $type.
# The $specified_ancestor term itself can either be included in the symbol
# table, or not, as desired, depending on the value of the $include_ancestor variable.

	my ($type, $specified_ancestor, $pedigree, $include_ancestor, $store_id) = @_;
	
	unless ($include_ancestor == 1 || $include_ancestor == 0) {

		print "***MAJOR PEEVES ERROR in basic ontology processing: there is a call to the 'get_all_descendents_of' subroutine where the '\$include_ancestor\' variable is not set to either '0' or '1' - let Gillian know so this can be fixed.\n\n";

	}
	
	unless ($store_id == 1 || $store_id == 0) {
		print "***MAJOR PEEVES ERROR in basic ontology processing: there is a call to the 'get_all_descendents_of' subroutine where the '\$store_id\' variable is not set to either '0' or '1' - let Gillian know so this can be fixed.\n\n";
	}

	my $tree = {};
	my @children = ();
	push @children, $specified_ancestor;
	
	while (@children) {

		my $child = shift @children;
		$tree->{$child}++;
		push @children, &get_immediate_children($child, $pedigree);
	}

# use the $include_ancestor variable to strip out the $specified_ancestor from
# the tree, if that is desired

	unless ($include_ancestor) {
		delete $tree->{$specified_ancestor};
	}
	
	
	foreach my $term (keys %{$tree}) {
		my $id = valid_symbol($term,"$type:default");
		set_symbol ($term, "$type:$specified_ancestor", $id);
		if ($store_id) {
			set_symbol ($id, "$type:$specified_ancestor:id", $term);
		}
	}
}


sub get_immediate_children {

# Subroutine gets (and then returns) all immediate is_a descendents of the
# $specified_ancestor term, using information in the supplied $pedigree data structure.

	my ($specified_ancestor, $pedigree) = @_;
	my @children = ();
	
	if (exists $pedigree->{$specified_ancestor}) {
	
		foreach my $child (keys %{$pedigree->{$specified_ancestor}}) {
		
			push @children, $child;
		}
		

	}
	
	return @children;
}

sub init_symbol_table ($$$)
{
# Fill in all the symbols which are independent of the contents of Chado and of the contents of any curation
# records.  Some are almost never changed and can be hard-coded here.  Others are to be found in, or derived
# from, various ontology files which are maintained independently.


# First, install various configuration variables.

    set_symbol ('Peeves_version', '_Peeves_', $_[0]);
    set_symbol ('Peeves_config' , '_Peeves_', $_[1]);
    set_symbol ('Curator_config', '_Peeves_', $_[2]);

    foreach my $cfg_var (keys %Peeves_config)
    {
	set_symbol ($cfg_var, '_Peeves_', $Peeves_config{$cfg_var});
    }


# end around to add 'P' as valid species abbreviation since it is used in the P\T
# symbol.  This should be altered once sorted out how to give proper species to
# natTEs and to their encoded genes

    set_symbol ('P', 'chado_species_abbreviation', 1);
    set_symbol ('P', 'taxgroup:drosophilid', 1);


#  Second, populate symbols which come from the ontologies.

    set_symbol ('Ontologies', '_Peeves_', '');			# No ontologies loaded yet.
    GO_dbxrefs ($GO_dbxref);
	
# store and process anatomy obo file, no descendents to get,
# do not store by id, so third argument set to '0'

	my $fbbt_ancestors = {
 		'cell component' => '1',
 
	};

	&process_ontology_file ($FBbt_obo, 'FBbt:\d{1,}', '1', $fbbt_ancestors);

# store and process FBdv file, no descendents to get, so last argument is just ''

	&process_ontology_file ($FBdv_obo, 'FBdv:\d{1,}', '1', '');

# Adding development shorthand for HarvCur expression curation.
# Note new typing of 'dv short', preventing this from bleeding through
# to phenotype checking.

my $dv_short_qualifiers = {


	'E' => ['stage 1', 'stage 2', 'stage 3', 'stage 4', 'stage 5', 'stage 6', 'stage 7', 'stage 8', 'stage 9', 'stage 10', 'stage 11', 'stage 12', 'stage 13', 'stage 14', 'stage 15', 'stage 16', 'stage 17', 'cycle 1', 'cycle 2', 'cycle 3', 'cycle 4', 'cycle 5', 'cycle 6', 'cycle 7', 'cycle 8', 'cycle 9', 'cycle 10', 'cycle 11', 'cycle 12', 'cycle 13', 'cycle 14', 'cycle 15', 'cycle 16'],

	'L' => ['first instar','second instar','third instar', 'third instar stage 1','third instar stage 2','late third instar larval stage','early third instar larval stage'],


	'P' => ['stage P1', 'stage P2', 'stage P3', 'stage P4', 'stage P5', 'stage P6', 'stage P7', 'stage P8', 'stage P9', 'stage P10', 'stage P11', 'stage P12', 'stage P13', 'stage P14', 'stage P15'],

	'A' => ['stage 1', 'stage 2', 'stage 3'],

	'O' => ['stage S1', 'stage S2', 'stage S3', 'stage S4', 'stage S5', 'stage S6', 'stage S7', 'stage S8', 'stage S9', 'stage S10', 'stage S11', 'stage S12', 'stage S13', 'stage S14', 'stage S10A', 'stage S10B', 'stage S12A', 'stage S12B', 'stage S12C', 'stage S13A', 'stage S13B', 'stage S13C', 'stage S13D', 'stage S14A', 'stage S14B'],


};


# this has no valid qualifiers
    set_symbol ('S', 'dv short', '1');

	foreach my $dv_short (keys %{$dv_short_qualifiers}) {

# set the developmental stage shortcutt
			set_symbol ($dv_short, 'dv short', '1');

			foreach my $term (@{$dv_short_qualifiers->{$dv_short}}) {

				set_symbol ($term, "dv_short_qualifier:$dv_short", '1');

			}

	}

# store and process DO obo file

	&process_ontology_file ($DO_obo, 'DOID:\d{1,}', '1', '');

# store and process GO obo file

	&process_ontology_file ($GO_obo, 'GO:\d{1,}', '1', '');

# store and process SO obo file

	my $so_ancestors = {
	
		'transcript' => '1',
		'polypeptide' => '1',
		'chromosome_structure_variation' => '1',
		'transposable_element' => '1',
		'synthetic_sequence' => '1',
	
	};

	&process_ontology_file ($SO_obo, 'SO:\d{1,}', '1', $so_ancestors);


# The block used in A9 are various types of aberrations.

	my %aberration_class_shortcut = (
	
		'Df' => 'chromosomal_deletion',
		'tDp' => 'tandem_duplication',
		'In' => 'chromosomal_inversion',
		'T'  => 'chromosomal_translocation',
		'R'  => 'ring_chromosome',
		'AS' => 'autosynaptic_chromosome',
		'DS' => 'dextrosynaptic_chromosome',
		'LS' => 'laevosynaptic_chromosome',
		'fDp' => 'free_duplication',
		'fR' => 'free_ring_duplication',
		'DfT' => 'deficient_translocation',
		'DfIn' => 'deficient_inversion',
		'InT' => 'inversion_cum_translocation',
		'bDp' => 'bipartite_duplication',
		'cT' => 'cyclic_translocation',
		'cIn' => 'bipartite_inversion',
		'eDp' => 'uninverted_insertional_duplication',
		'eTp1' => 'uninverted_intrachromosomal_transposition',
		'eTp2' => 'uninverted_interchromosomal_transposition',
		'iDp' => 'inverted_insertional_duplication',
		'iTp1' => 'inverted_intrachromosomal_transposition',
		'iTp2' => 'inverted_interchromosomal_transposition',
		'uDp' => 'unoriented_insertional_duplication',
		'uTp1' => 'unoriented_intrachromosomal_transposition',
		'uTp2' => 'unoriented_interchromosomal_transposition',
		'Int' => 'introgressed_chromosome_region',	
	);


	foreach my $shortcut (keys %aberration_class_shortcut) {

		my $term = $aberration_class_shortcut{$shortcut};
		set_symbol ($shortcut, 'aberration class shortcut', $term);
		valid_symbol ($term, 'SO:default') or print "MAJOR PEEVES ERROR in basic ontology processing: the '$term' term listed in Peeves as the value for the $shortcut shortcut is no longer a valid SO term, Peeves will need altering to cope (probably by replacing this obsolete term with a new valid one).\n\n";

	}


# store and process psi-mi obo file
	my $psi_mi_ancestors = {
# list of ancestor terms that need to store descendents of for subsequent checks
# term name is the key, whether (1) or not (0) to store the ancestor itself is the value
		'experimental role' => '0',
		'biological role' => '0',
#		'interaction detection method' => '0',
#		'participant identification method' => '0',
	};
	
	&process_ontology_file ($psi_mi_obo, 'MI:\d{1,}', '0', $psi_mi_ancestors);

# store and process fbcv obo file

 	my $fbcv_ancestors = {
 		'modifier of variegation' => '1',
		'increased mortality during development' => '1',
	};

	&process_ontology_file ($FBcv_obo, 'FBcv:\d{1,}', '1', $fbcv_ancestors);


# adding list of allowed qualifers for phenotypic_class to symbol table

# Data structure to  add individual qualifiers to a made up namespace
# which can then be used in lists of allowed qualifiers below.  Hopefully will
# not be necessary once namespace of 'progressive' vs 'precursor' is sorted out
	my $misc_qualifier = {

		'progressive' => {

			'actual' => 'FBcv:temporal_qualifier',
			'needed' => 'misc_pheno_class_qualifier',
		},

	};

	foreach my $qualifier (keys %{$misc_qualifier}) {

		valid_symbol ($qualifier, $misc_qualifier->{$qualifier}->{actual}) or print "BASIC PEEVES ERROR: '$qualifier' is no longer a valid '$misc_qualifier->{$qualifier}->{actual}', Peeves will need changing to cope\n";

		set_symbol ($qualifier, $misc_qualifier->{$qualifier}->{needed}, '1');


	}

	my @phenotypic_class_qualifiers = ('FBdv:default', 'FBcv:genotype_to_phenotype_relation', 'FBcv:environmental_qualifier', 'FBcv:sex_qualifier', 'FBcv:clone_qualifier', 'FBcv:dominance_qualifier', 'FBcv:intensity_qualifier', 'misc_pheno_class_qualifier');
	set_symbol ('phenotypic class', 'allowed_qualifier_list', \@phenotypic_class_qualifiers);


	my @phenotype_manifest_qualifiers = ('FBdv:default', 'FBcv:genotype_to_phenotype_relation', 'FBcv:environmental_qualifier', 'FBcv:sex_qualifier', 'FBcv:clone_qualifier', 'FBcv:spatial_qualifier', 'FBcv:structural_qualifier', 'FBcv:temporal_qualifier');
	set_symbol ('phenotype manifest', 'allowed_qualifier_list', \@phenotype_manifest_qualifiers);
	
# allowed qualifiers for <a> and <s> portions of TAP statement
	my @TAP_a_and_s_qualifiers = ('FBcv:spatial_qualifier', 'FBcv:temporal_qualifier', 'FBcv:expression_qualifier', 'FBcv:embryonic_pattern_qualifier');
	set_symbol ('TAPas', 'allowed_qualifier_list', \@TAP_a_and_s_qualifiers);

# allowed namespaces for 'experimental protocol - dataset' (LC11m) field for datasets of type 'project'
# this could probably be done by simply getting all the descendants of 'dataset attribute' as its all
# the namespaces under there, but a. not clear if that will always be the case, b. there is a loop in
# the fb_2016_03 version of FBcv which needs fixing before that method would work at all.
	my @project_protocol_types = ('FBcv:assay_attribute', 'FBcv:assay_type', 'FBcv:biosample_attribute', 'FBcv:biosample_type', 'FBcv:dataset_entity_type', 'FBcv:project_attribute', 'FBcv:project_type', 'FBcv:reagent_collection_type', 'FBcv:result_attribute', 'FBcv:result_type');
	set_symbol ('project_protocol_types', 'allowed_type_list', \@project_protocol_types);

# allowed namespaces for 'experimental protocol - dataset' (LC11m) field for datasets of type 'reagent collection'

	my @reagent_collection_protocol_types = ('FBcv:assay_attribute', 'FBcv:biosample_attribute');
	set_symbol ('reagent_collection_protocol_types', 'allowed_type_list', \@reagent_collection_protocol_types);


#  Then various classes of essentially static symbols.  This code looks ugly but the lists have to live
#  somewhere and this is as good a place as any.


# Curation record types. Now distinguished by location

# set record types for Cambridge (crec_type)
# (also currently used for IU).

    set_symbol ('bibl',  'crec_type', 'BIBL');
    set_symbol ('edit',  'crec_type', 'EDIT');
    set_symbol ('full',  'crec_type', 'FULL');
    set_symbol ('skim',  'crec_type', 'SKIM');
    set_symbol ('user',  'crec_type', 'AUTHOR');
# set 'phen' to PHEN so don't get warnings about missing synonyms
    set_symbol ('phen',  'crec_type', 'PHEN');
# set 'thin' to EDIT so don't get warnings about missing synonyms
# (should change this to 'THIN' so can distinguish between real 'edit' records and thin records
    set_symbol ('thin',  'crec_type', 'EDIT');
    set_symbol ('auto',  'crec_type', 'EDIT');


# set record types for Harvard (hrec_type)

# those left commented out are to avoid unnecessary false-positives
# as there is currently not specific code to either:
# a. deal with these record types
# or
# b. suppress error messages that e.g. are only appropriate in cam and not harv
# the types can be uncommented as and when the appropriate code is added

    set_symbol ('annot', 'hrec_type', 'ANNOTATION');
    set_symbol ('exp', 'hrec_type', 'EXPRESSION');
    set_symbol ('edit',  'hrec_type', 'EDIT');
    set_symbol ('fex',   'hrec_type', 'EXPRESSION');
    set_symbol ('full',  'hrec_type', 'FULL');
    set_symbol ('pc',    'hrec_type', 'FULL');
#    set_symbol ('seq',  'hrec_type', 'ACCESSION');
    set_symbol ('skim',  'hrec_type', 'SKIM');
    set_symbol ('int',  'hrec_type', 'FULL');
    set_symbol ('int_miRNA',  'hrec_type', 'FULL');
    set_symbol ('args',  'hrec_type', 'FULL');
    set_symbol ('hh',  'hrec_type', 'FULL');
    set_symbol ('hds',  'hrec_type', 'FULL');
    set_symbol ('hds_multiple',  'hrec_type', 'FULL');
    set_symbol ('sf',  'hrec_type', 'FULL');
    set_symbol ('db',  'hrec_type', 'FULL');
    set_symbol ('coll',  'hrec_type', 'FULL');
    set_symbol ('lib',  'hrec_type', 'FULL');
    set_symbol ('dataset',  'hrec_type', 'FULL');
    set_symbol ('cell',  'hrec_type', 'FULL');
    set_symbol ('DO',  'hrec_type', 'FULL');

# Mapping of curator abbreviation used in filename to type of curator
# Uses the same categorisation as used in Get_cam_unparsed.pm and Get_curation_log.pm
# in support scripts, except that only current curators are listed here.

    set_symbol ('al', 'cur_type', 'CAMCUR');
    set_symbol ('am', 'cur_type', 'CAMCUR');
    set_symbol ('ao', 'cur_type', 'CAMCUR');
    set_symbol ('cp', 'cur_type', 'CAMCUR');
    set_symbol ('gm', 'cur_type', 'CAMCUR');
    set_symbol ('sm', 'cur_type', 'CAMCUR');
    set_symbol ('vt', 'cur_type', 'CAMCUR');
    set_symbol ('ga', 'cur_type', 'GOCUR');
    set_symbol ('ha', 'cur_type', 'GOCUR');
    set_symbol ('pg', 'cur_type', 'GOCUR');
    set_symbol ('up', 'cur_type', 'GOEXT');
    set_symbol ('pl', 'cur_type', 'BIBLIO');
    set_symbol ('as', 'cur_type', 'USER');
    set_symbol ('us', 'cur_type', 'USER');
    set_symbol ('bev', 'cur_type', 'HARVCUR');
    set_symbol ('ct', 'cur_type', 'HARVCUR');
    set_symbol ('gds', 'cur_type', 'HARVCUR');
    set_symbol ('jma', 'cur_type', 'HARVCUR');
    set_symbol ('lc', 'cur_type', 'HARVCUR');
    set_symbol ('sian', 'cur_type', 'HARVCUR');
    set_symbol ('vj', 'cur_type', 'HARVCUR');
    set_symbol ('vfb', 'cur_type', 'HARVCUR');
    set_symbol ('pt', 'cur_type', 'AUTO');
    set_symbol ('tl', 'cur_type', 'UNMCUR');


#  Curator shortcuts are integers or abbreviations which translate into proforma-dependent strings on parsing.
#  Peeves doesn't care about their values, only their validity, but the translations are given here so that
#  other code may use them if desired.


# Valid SoftCV prefices for "Notes on origin" proforma fields

#    set_symbol ('Associated with',                 'notes on origin', 1);
#    set_symbol ('Isolated from',                   'notes on origin', 1);
#    set_symbol ('Induced with',                    'notes on origin', 1);
#    set_symbol ('Induced in',                      'notes on origin', 1);
#    set_symbol ('Induced on',                      'notes on origin', 1);
    set_symbol ('Separable from',                  'notes on origin', 1);
#    set_symbol ('Arose in',                        'notes on origin', 1);
#    set_symbol ('Arose with',                      'notes on origin', 1);
#    set_symbol ('Arose on',                        'notes on origin', 1);
#    set_symbol ('Arose as',                        'notes on origin', 1);
#    set_symbol ('Segregated from',                 'notes on origin', 1);
#    set_symbol ('Selected as',                     'notes on origin', 1);
#    set_symbol ('Revertant',                       'notes on origin', 1);
#    set_symbol ('P-element or transposase source', 'notes on origin', 1);
#    set_symbol ('Mutagen comment',                 'notes on origin', 1);


# Table of publication types for which laxer checking is required.

    set_symbol ('advertisement',                     'not_regular_pub', 1);
    set_symbol ('archive',                           'not_regular_pub', 1);
    set_symbol ('automatic genome annotation',       'not_regular_pub', 1);
    set_symbol ('bibliographic list',                'not_regular_pub', 1);
    set_symbol ('biography',                         'not_regular_pub', 1);
    set_symbol ('computer file',                     'not_regular_pub', 1);
    set_symbol ('curated genome annotation',         'not_regular_pub', 1);
    set_symbol ('DNA/RNA sequence record',           'not_regular_pub', 1);
    set_symbol ('death certificate',                 'not_regular_pub', 1);
    set_symbol ('demonstration',                     'not_regular_pub', 1);
    set_symbol ('film',                              'not_regular_pub', 1);
    set_symbol ('FlyBase analysis',                  'not_regular_pub', 1);
    set_symbol ('interview',                         'not_regular_pub', 1);
    set_symbol ('jigsaw puzzle',                     'not_regular_pub', 1);
    set_symbol ('letter',                            'not_regular_pub', 1);
    set_symbol ('microscope slides',                 'not_regular_pub', 1);
    set_symbol ('patent',                            'not_regular_pub', 1);
    set_symbol ('personal communication to FlyBase', 'not_regular_pub', 1);
    set_symbol ('poem',                              'not_regular_pub', 1);
    set_symbol ('postage stamp',                     'not_regular_pub', 1);
    set_symbol ('poster',                            'not_regular_pub', 1);
    set_symbol ('press release',                     'not_regular_pub', 1);
    set_symbol ('protein sequence record',           'not_regular_pub', 1);
    set_symbol ('obituary',                          'not_regular_pub', 1);
    set_symbol ('recording',                         'not_regular_pub', 1);
    set_symbol ('slides',                            'not_regular_pub', 1);
    set_symbol ('species list',                      'not_regular_pub', 1);
    set_symbol ('spoof',                             'not_regular_pub', 1);
    set_symbol ('stock list',                        'not_regular_pub', 1);
    set_symbol ('tactile diagram',                   'not_regular_pub', 1);
    set_symbol ('teaching note',                     'not_regular_pub', 1);
    set_symbol ('T-shirt',                           'not_regular_pub', 1);
    set_symbol ('unpublished',                       'not_regular_pub', 1);
    set_symbol ('website',                           'not_regular_pub', 1);

# Publication types which should have a PubMed abstract

    set_symbol ('paper', 'needs_pubmed_abstract', 1);
    set_symbol ('review', 'needs_pubmed_abstract', 1);
    set_symbol ('note', 'needs_pubmed_abstract', 1);
    set_symbol ('letter', 'needs_pubmed_abstract', 1);

# Table of reference types for MP17.

    set_symbol ('compendium', 'MP17_ref', 'compendium');
    set_symbol ('journal',    'MP17_ref', 'journal');
    set_symbol ('book',       'MP17_ref', 'journal');

# Publication flags for triage fields (P40, P41, P42 and P43)

    set_symbol ('nocur',      'P40_flag', 'solo');
    set_symbol ('nocur_abs',      'P40_flag', 'solo');
    set_symbol ('merge',      'P40_flag', 'multi');
    set_symbol ('split',      'P40_flag', 'multi');
    set_symbol ('rename',     'P40_flag', 'multi');
    set_symbol ('new_char',   'P40_flag', 'multi');
#    set_symbol ('new_gene',   'P40_flag', 'multi');
    set_symbol ('new_al',     'P40_flag', 'multi');
    set_symbol ('GOcur',      'P40_flag', 'multi');
    set_symbol ('pheno',      'P40_flag', 'multi');
    set_symbol ('pheno_chem',      'P40_flag', 'multi');
    set_symbol ('pheno_anat',      'P40_flag', 'multi');
    set_symbol ('new_transg', 'P40_flag', 'multi');
#    set_symbol ('orthologs', 'P40_flag', 'multi');
    set_symbol ('noGOcur', 'P40_flag', 'multi');
    set_symbol ('gene_group', 'P40_flag', 'multi');
    set_symbol ('pathway', 'P40_flag', 'multi');
# for now, hard-coded 'gene_group::DONE'
    set_symbol ('gene_group::DONE', 'P40_flag', 'multi');


    set_symbol ('no_flag',           'P41_flag', 'solo');
    set_symbol ('wt_exp',            'P41_flag', 'multi');

#Temporary end-around to prevent error warnings for 'pert_exp' in user records
# until checkbox can be removed from FTYP tool	
	if ($Peeves_config{'Where_running'} eq 'IU') {
		    set_symbol ('pert_exp',          'P41_flag', 'multi');

	}
    set_symbol ('neur_exp',          'P41_flag', 'multi');
#    set_symbol ('marker',            'P41_flag', 'multi');
    set_symbol ('gene_model',        'P41_flag', 'multi');
#    set_symbol ('gene_model_nonmel', 'P41_flag', 'multi');
    set_symbol ('phys_int',          'P41_flag', 'multi');
    set_symbol ('cis_reg',           'P41_flag', 'multi');
    set_symbol ('genom_feat',        'P41_flag', 'multi');
    set_symbol ('disease',           'P41_flag', 'multi');
    set_symbol ('diseaseHP',           'P41_flag', 'multi');
    set_symbol ('diseaseF',           'P41_flag', 'multi');
    set_symbol ('dataset',           'P41_flag', 'multi');
    set_symbol ('cell_line',           'P41_flag', 'multi');
    set_symbol ('cell_line(commercial)',           'P41_flag', 'multi');
    set_symbol ('cell_line(stable)',           'P41_flag', 'multi');

#    set_symbol ('cell_cult',         'P41_flag', 1);
#    set_symbol ('trans_assay',       'P41_flag', 1);
#    set_symbol ('RNAi',              'P41_flag', 1);

    set_symbol ('novel_anat',        'P42_flag', 'multi');

# set value to 'solo' for those triage flags that if present in the
# appropriate field, must be the only value
# set value to 'multi' for those triage flags that can be present in the
# appropriate field with other flags
    set_symbol ('disease',           'P43_flag', 'solo');
    set_symbol ('diseaseHP',         'P43_flag', 'solo');
    set_symbol ('noDOcur',           'P43_flag', 'solo');
    set_symbol ('dm_gen',            'P43_flag', 'multi');
    set_symbol ('dm_other',          'P43_flag', 'multi');


# evidence codes allowed for GA34a and what is expected after them in a DO line.
# Note that these are stored the opposite way around compared to most values in the symbol_table.
# I don't think it matters as some ontologies have the name<->id pairs stored both
# ways around to allow for different kinds of look up.
# In most cases the allowed value is the first argument and the 'type' (i.e. which
# field you expect to find it in, or what kind of thing it is) is the second argument.
# In this case the allowed value is the second argument, and the 'type' i.e.
# where you expect to find it e.g. which field etc. is the first argument.
# I've set it up this way as I think it'll make it easier in the future to
# improve the do_do_evidence subroutine so that there is less repetition of
# similar code

# require evidence data after code
    set_symbol ('GA34a_evidence', 'modeled', 'by');

# optionally has evidence data after code, but is NOT compulsory,
# which is indicated by the ? at the end of the expected evidence suffix
    set_symbol ('GA34a_evidence', 'CEA', 'with?');
    set_symbol ('GA34a_evidence', 'CEC', 'with?');


# evidence codes allowed for G24 (GO) fields and what is expected after them ('evidence suffix') in a GO line.
# following not in use yet in code as IC in GO is a special case
    set_symbol ('G24_evidence', 'inferred by curator', 'from');
    set_symbol ('G24_evidence', 'IC', 'from');
# require evidence data after code
    set_symbol ('G24_evidence', 'inferred from sequence alignment', 'with');
    set_symbol ('G24_evidence', 'ISA', 'with');
    set_symbol ('G24_evidence', 'inferred from sequence orthology', 'with');
    set_symbol ('G24_evidence', 'ISO', 'with');
    set_symbol ('G24_evidence', 'inferred from physical interaction', 'with');
    set_symbol ('G24_evidence', 'IPI', 'with');
    set_symbol ('G24_evidence', 'inferred from genetic interaction', 'with');
    set_symbol ('G24_evidence', 'IGI', 'with');
    set_symbol ('G24_evidence', 'inferred from biological ancestor', 'with');
    set_symbol ('G24_evidence', 'IBA', 'with');
    set_symbol ('G24_evidence', 'inferred from biological descendant', 'with');
    set_symbol ('G24_evidence', 'IBD', 'with');
    set_symbol ('G24_evidence', 'inferred from electronic annotation', 'with');
    set_symbol ('G24_evidence', 'IEA', 'with');
    set_symbol ('G24_evidence', 'inferred from sequence or structural similarity', 'with');
    set_symbol ('G24_evidence', 'ISS', 'with');
    set_symbol ('G24_evidence', 'inferred from rapid divergence', 'with');
    set_symbol ('G24_evidence', 'IRD', 'with');
# must not have evidence data after code, indicated by 'null'
    set_symbol ('G24_evidence', 'inferred from reviewed computational analysis', 'null');
    set_symbol ('G24_evidence', 'RCA', 'null');
    set_symbol ('G24_evidence', 'non-traceable author statement', 'null');
    set_symbol ('G24_evidence', 'NAS', 'null');
    set_symbol ('G24_evidence', 'traceable author statement', 'null');
    set_symbol ('G24_evidence', 'TAS', 'null');
    set_symbol ('G24_evidence', 'inferred from mutant phenotype', 'null');
    set_symbol ('G24_evidence', 'IMP', 'null');
    set_symbol ('G24_evidence', 'inferred from direct assay', 'null');
    set_symbol ('G24_evidence', 'IDA', 'null');
    set_symbol ('G24_evidence', 'inferred from expression pattern', 'null');
    set_symbol ('G24_evidence', 'IEP', 'null');
    set_symbol ('G24_evidence', 'no biological data available', 'null');
    set_symbol ('G24_evidence', 'ND', 'null');
    set_symbol ('G24_evidence', 'inferred from experiment', 'null');
    set_symbol ('G24_evidence', 'EXP', 'null');
# optionally has evidence data after code, but is NOT compulsory,
# which is indicated by the ? at the end of the expected evidence suffix
    set_symbol ('G24_evidence', 'inferred from genomic context', 'with?');
    set_symbol ('G24_evidence', 'IGC', 'with?');
    set_symbol ('G24_evidence', 'inferred from sequence model', 'with?');
    set_symbol ('G24_evidence', 'ISM', 'with?');
    set_symbol ('G24_evidence', 'inferred from key residues', 'with?');
    set_symbol ('G24_evidence', 'IKR', 'with?');




# Cytological locations.  First the complete set of valid locations.  We have no need for a specific value as
# only its validity need be recorded, so use the value 1.  If anyone were feeling really bored they could try
# to fill in the sequence locations.

    set_symbol ('YLt', 'cyto loc', 1);
    set_symbol ('h1', 'cyto loc', 1);
    set_symbol ('h2', 'cyto loc', 1);
    set_symbol ('h3', 'cyto loc', 1);
    set_symbol ('h4', 'cyto loc', 1);
    set_symbol ('h5', 'cyto loc', 1);
    set_symbol ('h6', 'cyto loc', 1);
    set_symbol ('h7', 'cyto loc', 1);
    set_symbol ('h8', 'cyto loc', 1);
    set_symbol ('h9', 'cyto loc', 1);
    set_symbol ('h10', 'cyto loc', 1);
    set_symbol ('h11', 'cyto loc', 1);
    set_symbol ('h12', 'cyto loc', 1);
    set_symbol ('h13', 'cyto loc', 1);
    set_symbol ('h14', 'cyto loc', 1);
    set_symbol ('h15', 'cyto loc', 1);
    set_symbol ('h16', 'cyto loc', 1);
    set_symbol ('h17', 'cyto loc', 1);
    set_symbol ('Ycen', 'cyto loc', 1);
    set_symbol ('h18', 'cyto loc', 1);
    set_symbol ('h19', 'cyto loc', 1);
    set_symbol ('h20', 'cyto loc', 1);
    set_symbol ('h21', 'cyto loc', 1);
    set_symbol ('h22', 'cyto loc', 1);
    set_symbol ('h23', 'cyto loc', 1);
    set_symbol ('h24', 'cyto loc', 1);
    set_symbol ('h25', 'cyto loc', 1);
    set_symbol ('h25A', 'cyto loc', 1);
    set_symbol ('h25B', 'cyto loc', 1);
    set_symbol ('YSt', 'cyto loc', 1);
    set_symbol ('XLt', 'cyto loc', 1);
    set_symbol ('h26', 'cyto loc', 1);
    set_symbol ('h27', 'cyto loc', 1);
    set_symbol ('h28', 'cyto loc', 1);
    set_symbol ('h29', 'cyto loc', 1);
    set_symbol ('h30', 'cyto loc', 1);
    set_symbol ('h31', 'cyto loc', 1);
    set_symbol ('h32', 'cyto loc', 1);
    set_symbol ('1cen', 'cyto loc', 1);
    set_symbol ('h33', 'cyto loc', 1);
    set_symbol ('h34', 'cyto loc', 1);
    set_symbol ('20h', 'cyto loc', 1);
    set_symbol ('XRt', 'cyto loc', 1);
    set_symbol ('2Lt', 'cyto loc', 1);
    set_symbol ('h35', 'cyto loc', 1);
    set_symbol ('h36', 'cyto loc', 1);
    set_symbol ('h37', 'cyto loc', 1);
    set_symbol ('h38', 'cyto loc', 1);
    set_symbol ('h38L', 'cyto loc', 1);
    set_symbol ('40h', 'cyto loc', 1);
    set_symbol ('2cen', 'cyto loc', 1);
    set_symbol ('41h', 'cyto loc', 1);
    set_symbol ('h38R', 'cyto loc', 1);
    set_symbol ('h39', 'cyto loc', 1);
    set_symbol ('h40', 'cyto loc', 1);
    set_symbol ('h41', 'cyto loc', 1);
    set_symbol ('h42', 'cyto loc', 1);
    set_symbol ('h42A', 'cyto loc', 1);
    set_symbol ('h42B', 'cyto loc', 1);
    set_symbol ('h43', 'cyto loc', 1);
    set_symbol ('h44', 'cyto loc', 1);
    set_symbol ('h45', 'cyto loc', 1);
    set_symbol ('h46', 'cyto loc', 1);
    set_symbol ('2Rt', 'cyto loc', 1);
    set_symbol ('3Lt', 'cyto loc', 1);
    set_symbol ('h47', 'cyto loc', 1);
    set_symbol ('h48', 'cyto loc', 1);
    set_symbol ('h49', 'cyto loc', 1);
    set_symbol ('h50', 'cyto loc', 1);
    set_symbol ('h51', 'cyto loc', 1);
    set_symbol ('h52', 'cyto loc', 1);
    set_symbol ('h53', 'cyto loc', 1);
    set_symbol ('h53L', 'cyto loc', 1);
    set_symbol ('80h', 'cyto loc', 1);
    set_symbol ('3cen', 'cyto loc', 1);
    set_symbol ('81h', 'cyto loc', 1);
    set_symbol ('h53R', 'cyto loc', 1);
    set_symbol ('h54', 'cyto loc', 1);
    set_symbol ('h55', 'cyto loc', 1);
    set_symbol ('h56', 'cyto loc', 1);
    set_symbol ('h57', 'cyto loc', 1);
    set_symbol ('h58', 'cyto loc', 1);
    set_symbol ('3Rt', 'cyto loc', 1);
    set_symbol ('4Lt', 'cyto loc', 1);
    set_symbol ('h59', 'cyto loc', 1);
    set_symbol ('h60', 'cyto loc', 1);
    set_symbol ('h61', 'cyto loc', 1);
    set_symbol ('4cen', 'cyto loc', 1);
    set_symbol ('101h', 'cyto loc', 1);
    set_symbol ('4Rt', 'cyto loc', 1);
    set_symbol ('1', 'cyto loc', 1);
    set_symbol ('2', 'cyto loc', 1);
    set_symbol ('3', 'cyto loc', 1);
    set_symbol ('4', 'cyto loc', 1);
    set_symbol ('5', 'cyto loc', 1);
    set_symbol ('6', 'cyto loc', 1);
    set_symbol ('7', 'cyto loc', 1);
    set_symbol ('8', 'cyto loc', 1);
    set_symbol ('9', 'cyto loc', 1);
    set_symbol ('10', 'cyto loc', 1);
    set_symbol ('11', 'cyto loc', 1);
    set_symbol ('12', 'cyto loc', 1);
    set_symbol ('13', 'cyto loc', 1);
    set_symbol ('14', 'cyto loc', 1);
    set_symbol ('15', 'cyto loc', 1);
    set_symbol ('16', 'cyto loc', 1);
    set_symbol ('17', 'cyto loc', 1);
    set_symbol ('18', 'cyto loc', 1);
    set_symbol ('19', 'cyto loc', 1);
    set_symbol ('20', 'cyto loc', 1);
    set_symbol ('21', 'cyto loc', 1);
    set_symbol ('22', 'cyto loc', 1);
    set_symbol ('23', 'cyto loc', 1);
    set_symbol ('24', 'cyto loc', 1);
    set_symbol ('25', 'cyto loc', 1);
    set_symbol ('26', 'cyto loc', 1);
    set_symbol ('27', 'cyto loc', 1);
    set_symbol ('28', 'cyto loc', 1);
    set_symbol ('29', 'cyto loc', 1);
    set_symbol ('30', 'cyto loc', 1);
    set_symbol ('31', 'cyto loc', 1);
    set_symbol ('32', 'cyto loc', 1);
    set_symbol ('33', 'cyto loc', 1);
    set_symbol ('34', 'cyto loc', 1);
    set_symbol ('35', 'cyto loc', 1);
    set_symbol ('36', 'cyto loc', 1);
    set_symbol ('37', 'cyto loc', 1);
    set_symbol ('38', 'cyto loc', 1);
    set_symbol ('39', 'cyto loc', 1);
    set_symbol ('40', 'cyto loc', 1);
    set_symbol ('41', 'cyto loc', 1);
    set_symbol ('42', 'cyto loc', 1);
    set_symbol ('43', 'cyto loc', 1);
    set_symbol ('44', 'cyto loc', 1);
    set_symbol ('45', 'cyto loc', 1);
    set_symbol ('46', 'cyto loc', 1);
    set_symbol ('47', 'cyto loc', 1);
    set_symbol ('48', 'cyto loc', 1);
    set_symbol ('49', 'cyto loc', 1);
    set_symbol ('50', 'cyto loc', 1);
    set_symbol ('51', 'cyto loc', 1);
    set_symbol ('52', 'cyto loc', 1);
    set_symbol ('53', 'cyto loc', 1);
    set_symbol ('54', 'cyto loc', 1);
    set_symbol ('55', 'cyto loc', 1);
    set_symbol ('56', 'cyto loc', 1);
    set_symbol ('57', 'cyto loc', 1);
    set_symbol ('58', 'cyto loc', 1);
    set_symbol ('59', 'cyto loc', 1);
    set_symbol ('60', 'cyto loc', 1);
    set_symbol ('61', 'cyto loc', 1);
    set_symbol ('62', 'cyto loc', 1);
    set_symbol ('63', 'cyto loc', 1);
    set_symbol ('64', 'cyto loc', 1);
    set_symbol ('65', 'cyto loc', 1);
    set_symbol ('66', 'cyto loc', 1);
    set_symbol ('67', 'cyto loc', 1);
    set_symbol ('68', 'cyto loc', 1);
    set_symbol ('69', 'cyto loc', 1);
    set_symbol ('70', 'cyto loc', 1);
    set_symbol ('71', 'cyto loc', 1);
    set_symbol ('72', 'cyto loc', 1);
    set_symbol ('73', 'cyto loc', 1);
    set_symbol ('74', 'cyto loc', 1);
    set_symbol ('75', 'cyto loc', 1);
    set_symbol ('76', 'cyto loc', 1);
    set_symbol ('77', 'cyto loc', 1);
    set_symbol ('78', 'cyto loc', 1);
    set_symbol ('79', 'cyto loc', 1);
    set_symbol ('80', 'cyto loc', 1);
    set_symbol ('81', 'cyto loc', 1);
    set_symbol ('82', 'cyto loc', 1);
    set_symbol ('83', 'cyto loc', 1);
    set_symbol ('84', 'cyto loc', 1);
    set_symbol ('85', 'cyto loc', 1);
    set_symbol ('86', 'cyto loc', 1);
    set_symbol ('87', 'cyto loc', 1);
    set_symbol ('88', 'cyto loc', 1);
    set_symbol ('89', 'cyto loc', 1);
    set_symbol ('90', 'cyto loc', 1);
    set_symbol ('91', 'cyto loc', 1);
    set_symbol ('92', 'cyto loc', 1);
    set_symbol ('93', 'cyto loc', 1);
    set_symbol ('94', 'cyto loc', 1);
    set_symbol ('95', 'cyto loc', 1);
    set_symbol ('96', 'cyto loc', 1);
    set_symbol ('97', 'cyto loc', 1);
    set_symbol ('98', 'cyto loc', 1);
    set_symbol ('99', 'cyto loc', 1);
    set_symbol ('100', 'cyto loc', 1);
    set_symbol ('101', 'cyto loc', 1);
    set_symbol ('102', 'cyto loc', 1);
    set_symbol ('1A', 'cyto loc', 1);
    set_symbol ('1B', 'cyto loc', 1);
    set_symbol ('1C', 'cyto loc', 1);
    set_symbol ('1D', 'cyto loc', 1);
    set_symbol ('1E', 'cyto loc', 1);
    set_symbol ('1F', 'cyto loc', 1);
    set_symbol ('2A', 'cyto loc', 1);
    set_symbol ('2B', 'cyto loc', 1);
    set_symbol ('2C', 'cyto loc', 1);
    set_symbol ('2D', 'cyto loc', 1);
    set_symbol ('2E', 'cyto loc', 1);
    set_symbol ('2F', 'cyto loc', 1);
    set_symbol ('3A', 'cyto loc', 1);
    set_symbol ('3B', 'cyto loc', 1);
    set_symbol ('3C', 'cyto loc', 1);
    set_symbol ('3D', 'cyto loc', 1);
    set_symbol ('3E', 'cyto loc', 1);
    set_symbol ('3F', 'cyto loc', 1);
    set_symbol ('4A', 'cyto loc', 1);
    set_symbol ('4B', 'cyto loc', 1);
    set_symbol ('4C', 'cyto loc', 1);
    set_symbol ('4D', 'cyto loc', 1);
    set_symbol ('4E', 'cyto loc', 1);
    set_symbol ('4F', 'cyto loc', 1);
    set_symbol ('5A', 'cyto loc', 1);
    set_symbol ('5B', 'cyto loc', 1);
    set_symbol ('5C', 'cyto loc', 1);
    set_symbol ('5D', 'cyto loc', 1);
    set_symbol ('5E', 'cyto loc', 1);
    set_symbol ('5F', 'cyto loc', 1);
    set_symbol ('6A', 'cyto loc', 1);
    set_symbol ('6B', 'cyto loc', 1);
    set_symbol ('6C', 'cyto loc', 1);
    set_symbol ('6D', 'cyto loc', 1);
    set_symbol ('6E', 'cyto loc', 1);
    set_symbol ('6F', 'cyto loc', 1);
    set_symbol ('7A', 'cyto loc', 1);
    set_symbol ('7B', 'cyto loc', 1);
    set_symbol ('7C', 'cyto loc', 1);
    set_symbol ('7D', 'cyto loc', 1);
    set_symbol ('7E', 'cyto loc', 1);
    set_symbol ('7F', 'cyto loc', 1);
    set_symbol ('8A', 'cyto loc', 1);
    set_symbol ('8B', 'cyto loc', 1);
    set_symbol ('8C', 'cyto loc', 1);
    set_symbol ('8D', 'cyto loc', 1);
    set_symbol ('8E', 'cyto loc', 1);
    set_symbol ('8F', 'cyto loc', 1);
    set_symbol ('9A', 'cyto loc', 1);
    set_symbol ('9B', 'cyto loc', 1);
    set_symbol ('9C', 'cyto loc', 1);
    set_symbol ('9D', 'cyto loc', 1);
    set_symbol ('9E', 'cyto loc', 1);
    set_symbol ('9F', 'cyto loc', 1);
    set_symbol ('10A', 'cyto loc', 1);
    set_symbol ('10B', 'cyto loc', 1);
    set_symbol ('10C', 'cyto loc', 1);
    set_symbol ('10D', 'cyto loc', 1);
    set_symbol ('10E', 'cyto loc', 1);
    set_symbol ('10F', 'cyto loc', 1);
    set_symbol ('11A', 'cyto loc', 1);
    set_symbol ('11B', 'cyto loc', 1);
    set_symbol ('11C', 'cyto loc', 1);
    set_symbol ('11D', 'cyto loc', 1);
    set_symbol ('11E', 'cyto loc', 1);
    set_symbol ('11F', 'cyto loc', 1);
    set_symbol ('12A', 'cyto loc', 1);
    set_symbol ('12B', 'cyto loc', 1);
    set_symbol ('12C', 'cyto loc', 1);
    set_symbol ('12D', 'cyto loc', 1);
    set_symbol ('12E', 'cyto loc', 1);
    set_symbol ('12F', 'cyto loc', 1);
    set_symbol ('13A', 'cyto loc', 1);
    set_symbol ('13B', 'cyto loc', 1);
    set_symbol ('13C', 'cyto loc', 1);
    set_symbol ('13D', 'cyto loc', 1);
    set_symbol ('13E', 'cyto loc', 1);
    set_symbol ('13F', 'cyto loc', 1);
    set_symbol ('14A', 'cyto loc', 1);
    set_symbol ('14B', 'cyto loc', 1);
    set_symbol ('14C', 'cyto loc', 1);
    set_symbol ('14D', 'cyto loc', 1);
    set_symbol ('14E', 'cyto loc', 1);
    set_symbol ('14F', 'cyto loc', 1);
    set_symbol ('15A', 'cyto loc', 1);
    set_symbol ('15B', 'cyto loc', 1);
    set_symbol ('15C', 'cyto loc', 1);
    set_symbol ('15D', 'cyto loc', 1);
    set_symbol ('15E', 'cyto loc', 1);
    set_symbol ('15F', 'cyto loc', 1);
    set_symbol ('16A', 'cyto loc', 1);
    set_symbol ('16B', 'cyto loc', 1);
    set_symbol ('16C', 'cyto loc', 1);
    set_symbol ('16D', 'cyto loc', 1);
    set_symbol ('16E', 'cyto loc', 1);
    set_symbol ('16F', 'cyto loc', 1);
    set_symbol ('17A', 'cyto loc', 1);
    set_symbol ('17B', 'cyto loc', 1);
    set_symbol ('17C', 'cyto loc', 1);
    set_symbol ('17D', 'cyto loc', 1);
    set_symbol ('17E', 'cyto loc', 1);
    set_symbol ('17F', 'cyto loc', 1);
    set_symbol ('18A', 'cyto loc', 1);
    set_symbol ('18B', 'cyto loc', 1);
    set_symbol ('18C', 'cyto loc', 1);
    set_symbol ('18D', 'cyto loc', 1);
    set_symbol ('18E', 'cyto loc', 1);
    set_symbol ('18F', 'cyto loc', 1);
    set_symbol ('19A', 'cyto loc', 1);
    set_symbol ('19B', 'cyto loc', 1);
    set_symbol ('19C', 'cyto loc', 1);
    set_symbol ('19D', 'cyto loc', 1);
    set_symbol ('19E', 'cyto loc', 1);
    set_symbol ('19F', 'cyto loc', 1);
    set_symbol ('20A', 'cyto loc', 1);
    set_symbol ('20B', 'cyto loc', 1);
    set_symbol ('20C', 'cyto loc', 1);
    set_symbol ('20D', 'cyto loc', 1);
    set_symbol ('20E', 'cyto loc', 1);
    set_symbol ('20F', 'cyto loc', 1);
    set_symbol ('21A', 'cyto loc', 1);
    set_symbol ('21B', 'cyto loc', 1);
    set_symbol ('21C', 'cyto loc', 1);
    set_symbol ('21D', 'cyto loc', 1);
    set_symbol ('21E', 'cyto loc', 1);
    set_symbol ('21F', 'cyto loc', 1);
    set_symbol ('22A', 'cyto loc', 1);
    set_symbol ('22B', 'cyto loc', 1);
    set_symbol ('22C', 'cyto loc', 1);
    set_symbol ('22D', 'cyto loc', 1);
    set_symbol ('22E', 'cyto loc', 1);
    set_symbol ('22F', 'cyto loc', 1);
    set_symbol ('23A', 'cyto loc', 1);
    set_symbol ('23B', 'cyto loc', 1);
    set_symbol ('23C', 'cyto loc', 1);
    set_symbol ('23D', 'cyto loc', 1);
    set_symbol ('23E', 'cyto loc', 1);
    set_symbol ('23F', 'cyto loc', 1);
    set_symbol ('24A', 'cyto loc', 1);
    set_symbol ('24B', 'cyto loc', 1);
    set_symbol ('24C', 'cyto loc', 1);
    set_symbol ('24D', 'cyto loc', 1);
    set_symbol ('24E', 'cyto loc', 1);
    set_symbol ('24F', 'cyto loc', 1);
    set_symbol ('25A', 'cyto loc', 1);
    set_symbol ('25B', 'cyto loc', 1);
    set_symbol ('25C', 'cyto loc', 1);
    set_symbol ('25D', 'cyto loc', 1);
    set_symbol ('25E', 'cyto loc', 1);
    set_symbol ('25F', 'cyto loc', 1);
    set_symbol ('26A', 'cyto loc', 1);
    set_symbol ('26B', 'cyto loc', 1);
    set_symbol ('26C', 'cyto loc', 1);
    set_symbol ('26D', 'cyto loc', 1);
    set_symbol ('26E', 'cyto loc', 1);
    set_symbol ('26F', 'cyto loc', 1);
    set_symbol ('27A', 'cyto loc', 1);
    set_symbol ('27B', 'cyto loc', 1);
    set_symbol ('27C', 'cyto loc', 1);
    set_symbol ('27D', 'cyto loc', 1);
    set_symbol ('27E', 'cyto loc', 1);
    set_symbol ('27F', 'cyto loc', 1);
    set_symbol ('28A', 'cyto loc', 1);
    set_symbol ('28B', 'cyto loc', 1);
    set_symbol ('28C', 'cyto loc', 1);
    set_symbol ('28D', 'cyto loc', 1);
    set_symbol ('28E', 'cyto loc', 1);
    set_symbol ('28F', 'cyto loc', 1);
    set_symbol ('29A', 'cyto loc', 1);
    set_symbol ('29B', 'cyto loc', 1);
    set_symbol ('29C', 'cyto loc', 1);
    set_symbol ('29D', 'cyto loc', 1);
    set_symbol ('29E', 'cyto loc', 1);
    set_symbol ('29F', 'cyto loc', 1);
    set_symbol ('30A', 'cyto loc', 1);
    set_symbol ('30B', 'cyto loc', 1);
    set_symbol ('30C', 'cyto loc', 1);
    set_symbol ('30D', 'cyto loc', 1);
    set_symbol ('30E', 'cyto loc', 1);
    set_symbol ('30F', 'cyto loc', 1);
    set_symbol ('31A', 'cyto loc', 1);
    set_symbol ('31B', 'cyto loc', 1);
    set_symbol ('31C', 'cyto loc', 1);
    set_symbol ('31D', 'cyto loc', 1);
    set_symbol ('31E', 'cyto loc', 1);
    set_symbol ('31F', 'cyto loc', 1);
    set_symbol ('32A', 'cyto loc', 1);
    set_symbol ('32B', 'cyto loc', 1);
    set_symbol ('32C', 'cyto loc', 1);
    set_symbol ('32D', 'cyto loc', 1);
    set_symbol ('32E', 'cyto loc', 1);
    set_symbol ('32F', 'cyto loc', 1);
    set_symbol ('33A', 'cyto loc', 1);
    set_symbol ('33B', 'cyto loc', 1);
    set_symbol ('33C', 'cyto loc', 1);
    set_symbol ('33D', 'cyto loc', 1);
    set_symbol ('33E', 'cyto loc', 1);
    set_symbol ('33F', 'cyto loc', 1);
    set_symbol ('34A', 'cyto loc', 1);
    set_symbol ('34B', 'cyto loc', 1);
    set_symbol ('34C', 'cyto loc', 1);
    set_symbol ('34D', 'cyto loc', 1);
    set_symbol ('34E', 'cyto loc', 1);
    set_symbol ('34F', 'cyto loc', 1);
    set_symbol ('35A', 'cyto loc', 1);
    set_symbol ('35B', 'cyto loc', 1);
    set_symbol ('35C', 'cyto loc', 1);
    set_symbol ('35D', 'cyto loc', 1);
    set_symbol ('35E', 'cyto loc', 1);
    set_symbol ('35F', 'cyto loc', 1);
    set_symbol ('36A', 'cyto loc', 1);
    set_symbol ('36B', 'cyto loc', 1);
    set_symbol ('36C', 'cyto loc', 1);
    set_symbol ('36D', 'cyto loc', 1);
    set_symbol ('36E', 'cyto loc', 1);
    set_symbol ('36F', 'cyto loc', 1);
    set_symbol ('37A', 'cyto loc', 1);
    set_symbol ('37B', 'cyto loc', 1);
    set_symbol ('37C', 'cyto loc', 1);
    set_symbol ('37D', 'cyto loc', 1);
    set_symbol ('37E', 'cyto loc', 1);
    set_symbol ('37F', 'cyto loc', 1);
    set_symbol ('38A', 'cyto loc', 1);
    set_symbol ('38B', 'cyto loc', 1);
    set_symbol ('38C', 'cyto loc', 1);
    set_symbol ('38D', 'cyto loc', 1);
    set_symbol ('38E', 'cyto loc', 1);
    set_symbol ('38F', 'cyto loc', 1);
    set_symbol ('39A', 'cyto loc', 1);
    set_symbol ('39B', 'cyto loc', 1);
    set_symbol ('39C', 'cyto loc', 1);
    set_symbol ('39D', 'cyto loc', 1);
    set_symbol ('39E', 'cyto loc', 1);
    set_symbol ('39F', 'cyto loc', 1);
    set_symbol ('40A', 'cyto loc', 1);
    set_symbol ('40B', 'cyto loc', 1);
    set_symbol ('40C', 'cyto loc', 1);
    set_symbol ('40D', 'cyto loc', 1);
    set_symbol ('40E', 'cyto loc', 1);
    set_symbol ('40F', 'cyto loc', 1);
    set_symbol ('41A', 'cyto loc', 1);
    set_symbol ('41B', 'cyto loc', 1);
    set_symbol ('41C', 'cyto loc', 1);
    set_symbol ('41D', 'cyto loc', 1);
    set_symbol ('41E', 'cyto loc', 1);
    set_symbol ('41F', 'cyto loc', 1);
    set_symbol ('42A', 'cyto loc', 1);
    set_symbol ('42B', 'cyto loc', 1);
    set_symbol ('42C', 'cyto loc', 1);
    set_symbol ('42D', 'cyto loc', 1);
    set_symbol ('42E', 'cyto loc', 1);
    set_symbol ('42F', 'cyto loc', 1);
    set_symbol ('43A', 'cyto loc', 1);
    set_symbol ('43B', 'cyto loc', 1);
    set_symbol ('43C', 'cyto loc', 1);
    set_symbol ('43D', 'cyto loc', 1);
    set_symbol ('43E', 'cyto loc', 1);
    set_symbol ('43F', 'cyto loc', 1);
    set_symbol ('44A', 'cyto loc', 1);
    set_symbol ('44B', 'cyto loc', 1);
    set_symbol ('44C', 'cyto loc', 1);
    set_symbol ('44D', 'cyto loc', 1);
    set_symbol ('44E', 'cyto loc', 1);
    set_symbol ('44F', 'cyto loc', 1);
    set_symbol ('45A', 'cyto loc', 1);
    set_symbol ('45B', 'cyto loc', 1);
    set_symbol ('45C', 'cyto loc', 1);
    set_symbol ('45D', 'cyto loc', 1);
    set_symbol ('45E', 'cyto loc', 1);
    set_symbol ('45F', 'cyto loc', 1);
    set_symbol ('46A', 'cyto loc', 1);
    set_symbol ('46B', 'cyto loc', 1);
    set_symbol ('46C', 'cyto loc', 1);
    set_symbol ('46D', 'cyto loc', 1);
    set_symbol ('46E', 'cyto loc', 1);
    set_symbol ('46F', 'cyto loc', 1);
    set_symbol ('47A', 'cyto loc', 1);
    set_symbol ('47B', 'cyto loc', 1);
    set_symbol ('47C', 'cyto loc', 1);
    set_symbol ('47D', 'cyto loc', 1);
    set_symbol ('47E', 'cyto loc', 1);
    set_symbol ('47F', 'cyto loc', 1);
    set_symbol ('48A', 'cyto loc', 1);
    set_symbol ('48B', 'cyto loc', 1);
    set_symbol ('48C', 'cyto loc', 1);
    set_symbol ('48D', 'cyto loc', 1);
    set_symbol ('48E', 'cyto loc', 1);
    set_symbol ('48F', 'cyto loc', 1);
    set_symbol ('49A', 'cyto loc', 1);
    set_symbol ('49B', 'cyto loc', 1);
    set_symbol ('49C', 'cyto loc', 1);
    set_symbol ('49D', 'cyto loc', 1);
    set_symbol ('49E', 'cyto loc', 1);
    set_symbol ('49F', 'cyto loc', 1);
    set_symbol ('50A', 'cyto loc', 1);
    set_symbol ('50B', 'cyto loc', 1);
    set_symbol ('50C', 'cyto loc', 1);
    set_symbol ('50D', 'cyto loc', 1);
    set_symbol ('50E', 'cyto loc', 1);
    set_symbol ('50F', 'cyto loc', 1);
    set_symbol ('51A', 'cyto loc', 1);
    set_symbol ('51B', 'cyto loc', 1);
    set_symbol ('51C', 'cyto loc', 1);
    set_symbol ('51D', 'cyto loc', 1);
    set_symbol ('51E', 'cyto loc', 1);
    set_symbol ('51F', 'cyto loc', 1);
    set_symbol ('52A', 'cyto loc', 1);
    set_symbol ('52B', 'cyto loc', 1);
    set_symbol ('52C', 'cyto loc', 1);
    set_symbol ('52D', 'cyto loc', 1);
    set_symbol ('52E', 'cyto loc', 1);
    set_symbol ('52F', 'cyto loc', 1);
    set_symbol ('53A', 'cyto loc', 1);
    set_symbol ('53B', 'cyto loc', 1);
    set_symbol ('53C', 'cyto loc', 1);
    set_symbol ('53D', 'cyto loc', 1);
    set_symbol ('53E', 'cyto loc', 1);
    set_symbol ('53F', 'cyto loc', 1);
    set_symbol ('54A', 'cyto loc', 1);
    set_symbol ('54B', 'cyto loc', 1);
    set_symbol ('54C', 'cyto loc', 1);
    set_symbol ('54D', 'cyto loc', 1);
    set_symbol ('54E', 'cyto loc', 1);
    set_symbol ('54F', 'cyto loc', 1);
    set_symbol ('55A', 'cyto loc', 1);
    set_symbol ('55B', 'cyto loc', 1);
    set_symbol ('55C', 'cyto loc', 1);
    set_symbol ('55D', 'cyto loc', 1);
    set_symbol ('55E', 'cyto loc', 1);
    set_symbol ('55F', 'cyto loc', 1);
    set_symbol ('56A', 'cyto loc', 1);
    set_symbol ('56B', 'cyto loc', 1);
    set_symbol ('56C', 'cyto loc', 1);
    set_symbol ('56D', 'cyto loc', 1);
    set_symbol ('56E', 'cyto loc', 1);
    set_symbol ('56F', 'cyto loc', 1);
    set_symbol ('57A', 'cyto loc', 1);
    set_symbol ('57B', 'cyto loc', 1);
    set_symbol ('57C', 'cyto loc', 1);
    set_symbol ('57D', 'cyto loc', 1);
    set_symbol ('57E', 'cyto loc', 1);
    set_symbol ('57F', 'cyto loc', 1);
    set_symbol ('58A', 'cyto loc', 1);
    set_symbol ('58B', 'cyto loc', 1);
    set_symbol ('58C', 'cyto loc', 1);
    set_symbol ('58D', 'cyto loc', 1);
    set_symbol ('58E', 'cyto loc', 1);
    set_symbol ('58F', 'cyto loc', 1);
    set_symbol ('59A', 'cyto loc', 1);
    set_symbol ('59B', 'cyto loc', 1);
    set_symbol ('59C', 'cyto loc', 1);
    set_symbol ('59D', 'cyto loc', 1);
    set_symbol ('59E', 'cyto loc', 1);
    set_symbol ('59F', 'cyto loc', 1);
    set_symbol ('60A', 'cyto loc', 1);
    set_symbol ('60B', 'cyto loc', 1);
    set_symbol ('60C', 'cyto loc', 1);
    set_symbol ('60D', 'cyto loc', 1);
    set_symbol ('60E', 'cyto loc', 1);
    set_symbol ('60F', 'cyto loc', 1);
    set_symbol ('61A', 'cyto loc', 1);
    set_symbol ('61B', 'cyto loc', 1);
    set_symbol ('61C', 'cyto loc', 1);
    set_symbol ('61D', 'cyto loc', 1);
    set_symbol ('61E', 'cyto loc', 1);
    set_symbol ('61F', 'cyto loc', 1);
    set_symbol ('62A', 'cyto loc', 1);
    set_symbol ('62B', 'cyto loc', 1);
    set_symbol ('62C', 'cyto loc', 1);
    set_symbol ('62D', 'cyto loc', 1);
    set_symbol ('62E', 'cyto loc', 1);
    set_symbol ('62F', 'cyto loc', 1);
    set_symbol ('63A', 'cyto loc', 1);
    set_symbol ('63B', 'cyto loc', 1);
    set_symbol ('63C', 'cyto loc', 1);
    set_symbol ('63D', 'cyto loc', 1);
    set_symbol ('63E', 'cyto loc', 1);
    set_symbol ('63F', 'cyto loc', 1);
    set_symbol ('64A', 'cyto loc', 1);
    set_symbol ('64B', 'cyto loc', 1);
    set_symbol ('64C', 'cyto loc', 1);
    set_symbol ('64D', 'cyto loc', 1);
    set_symbol ('64E', 'cyto loc', 1);
    set_symbol ('64F', 'cyto loc', 1);
    set_symbol ('65A', 'cyto loc', 1);
    set_symbol ('65B', 'cyto loc', 1);
    set_symbol ('65C', 'cyto loc', 1);
    set_symbol ('65D', 'cyto loc', 1);
    set_symbol ('65E', 'cyto loc', 1);
    set_symbol ('65F', 'cyto loc', 1);
    set_symbol ('66A', 'cyto loc', 1);
    set_symbol ('66B', 'cyto loc', 1);
    set_symbol ('66C', 'cyto loc', 1);
    set_symbol ('66D', 'cyto loc', 1);
    set_symbol ('66E', 'cyto loc', 1);
    set_symbol ('66F', 'cyto loc', 1);
    set_symbol ('67A', 'cyto loc', 1);
    set_symbol ('67B', 'cyto loc', 1);
    set_symbol ('67C', 'cyto loc', 1);
    set_symbol ('67D', 'cyto loc', 1);
    set_symbol ('67E', 'cyto loc', 1);
    set_symbol ('67F', 'cyto loc', 1);
    set_symbol ('68A', 'cyto loc', 1);
    set_symbol ('68B', 'cyto loc', 1);
    set_symbol ('68C', 'cyto loc', 1);
    set_symbol ('68D', 'cyto loc', 1);
    set_symbol ('68E', 'cyto loc', 1);
    set_symbol ('68F', 'cyto loc', 1);
    set_symbol ('69A', 'cyto loc', 1);
    set_symbol ('69B', 'cyto loc', 1);
    set_symbol ('69C', 'cyto loc', 1);
    set_symbol ('69D', 'cyto loc', 1);
    set_symbol ('69E', 'cyto loc', 1);
    set_symbol ('69F', 'cyto loc', 1);
    set_symbol ('70A', 'cyto loc', 1);
    set_symbol ('70B', 'cyto loc', 1);
    set_symbol ('70C', 'cyto loc', 1);
    set_symbol ('70D', 'cyto loc', 1);
    set_symbol ('70E', 'cyto loc', 1);
    set_symbol ('70F', 'cyto loc', 1);
    set_symbol ('71A', 'cyto loc', 1);
    set_symbol ('71B', 'cyto loc', 1);
    set_symbol ('71C', 'cyto loc', 1);
    set_symbol ('71D', 'cyto loc', 1);
    set_symbol ('71E', 'cyto loc', 1);
    set_symbol ('71F', 'cyto loc', 1);
    set_symbol ('72A', 'cyto loc', 1);
    set_symbol ('72B', 'cyto loc', 1);
    set_symbol ('72C', 'cyto loc', 1);
    set_symbol ('72D', 'cyto loc', 1);
    set_symbol ('72E', 'cyto loc', 1);
    set_symbol ('72F', 'cyto loc', 1);
    set_symbol ('73A', 'cyto loc', 1);
    set_symbol ('73B', 'cyto loc', 1);
    set_symbol ('73C', 'cyto loc', 1);
    set_symbol ('73D', 'cyto loc', 1);
    set_symbol ('73E', 'cyto loc', 1);
    set_symbol ('73F', 'cyto loc', 1);
    set_symbol ('74A', 'cyto loc', 1);
    set_symbol ('74B', 'cyto loc', 1);
    set_symbol ('74C', 'cyto loc', 1);
    set_symbol ('74D', 'cyto loc', 1);
    set_symbol ('74E', 'cyto loc', 1);
    set_symbol ('74F', 'cyto loc', 1);
    set_symbol ('75A', 'cyto loc', 1);
    set_symbol ('75B', 'cyto loc', 1);
    set_symbol ('75C', 'cyto loc', 1);
    set_symbol ('75D', 'cyto loc', 1);
    set_symbol ('75E', 'cyto loc', 1);
    set_symbol ('75F', 'cyto loc', 1);
    set_symbol ('76A', 'cyto loc', 1);
    set_symbol ('76B', 'cyto loc', 1);
    set_symbol ('76C', 'cyto loc', 1);
    set_symbol ('76D', 'cyto loc', 1);
    set_symbol ('76E', 'cyto loc', 1);
    set_symbol ('76F', 'cyto loc', 1);
    set_symbol ('77A', 'cyto loc', 1);
    set_symbol ('77B', 'cyto loc', 1);
    set_symbol ('77C', 'cyto loc', 1);
    set_symbol ('77D', 'cyto loc', 1);
    set_symbol ('77E', 'cyto loc', 1);
    set_symbol ('77F', 'cyto loc', 1);
    set_symbol ('78A', 'cyto loc', 1);
    set_symbol ('78B', 'cyto loc', 1);
    set_symbol ('78C', 'cyto loc', 1);
    set_symbol ('78D', 'cyto loc', 1);
    set_symbol ('78E', 'cyto loc', 1);
    set_symbol ('78F', 'cyto loc', 1);
    set_symbol ('79A', 'cyto loc', 1);
    set_symbol ('79B', 'cyto loc', 1);
    set_symbol ('79C', 'cyto loc', 1);
    set_symbol ('79D', 'cyto loc', 1);
    set_symbol ('79E', 'cyto loc', 1);
    set_symbol ('79F', 'cyto loc', 1);
    set_symbol ('80A', 'cyto loc', 1);
    set_symbol ('80B', 'cyto loc', 1);
    set_symbol ('80C', 'cyto loc', 1);
    set_symbol ('80D', 'cyto loc', 1);
    set_symbol ('80E', 'cyto loc', 1);
    set_symbol ('80F', 'cyto loc', 1);
    set_symbol ('81F', 'cyto loc', 1);
    set_symbol ('82A', 'cyto loc', 1);
    set_symbol ('82B', 'cyto loc', 1);
    set_symbol ('82C', 'cyto loc', 1);
    set_symbol ('82D', 'cyto loc', 1);
    set_symbol ('82E', 'cyto loc', 1);
    set_symbol ('82F', 'cyto loc', 1);
    set_symbol ('83A', 'cyto loc', 1);
    set_symbol ('83B', 'cyto loc', 1);
    set_symbol ('83C', 'cyto loc', 1);
    set_symbol ('83D', 'cyto loc', 1);
    set_symbol ('83E', 'cyto loc', 1);
    set_symbol ('83F', 'cyto loc', 1);
    set_symbol ('84A', 'cyto loc', 1);
    set_symbol ('84B', 'cyto loc', 1);
    set_symbol ('84C', 'cyto loc', 1);
    set_symbol ('84D', 'cyto loc', 1);
    set_symbol ('84E', 'cyto loc', 1);
    set_symbol ('84F', 'cyto loc', 1);
    set_symbol ('85A', 'cyto loc', 1);
    set_symbol ('85B', 'cyto loc', 1);
    set_symbol ('85C', 'cyto loc', 1);
    set_symbol ('85D', 'cyto loc', 1);
    set_symbol ('85E', 'cyto loc', 1);
    set_symbol ('85F', 'cyto loc', 1);
    set_symbol ('86A', 'cyto loc', 1);
    set_symbol ('86B', 'cyto loc', 1);
    set_symbol ('86C', 'cyto loc', 1);
    set_symbol ('86D', 'cyto loc', 1);
    set_symbol ('86E', 'cyto loc', 1);
    set_symbol ('86F', 'cyto loc', 1);
    set_symbol ('87A', 'cyto loc', 1);
    set_symbol ('87B', 'cyto loc', 1);
    set_symbol ('87C', 'cyto loc', 1);
    set_symbol ('87D', 'cyto loc', 1);
    set_symbol ('87E', 'cyto loc', 1);
    set_symbol ('87F', 'cyto loc', 1);
    set_symbol ('88A', 'cyto loc', 1);
    set_symbol ('88B', 'cyto loc', 1);
    set_symbol ('88C', 'cyto loc', 1);
    set_symbol ('88D', 'cyto loc', 1);
    set_symbol ('88E', 'cyto loc', 1);
    set_symbol ('88F', 'cyto loc', 1);
    set_symbol ('89A', 'cyto loc', 1);
    set_symbol ('89B', 'cyto loc', 1);
    set_symbol ('89C', 'cyto loc', 1);
    set_symbol ('89D', 'cyto loc', 1);
    set_symbol ('89E', 'cyto loc', 1);
    set_symbol ('89F', 'cyto loc', 1);
    set_symbol ('90A', 'cyto loc', 1);
    set_symbol ('90B', 'cyto loc', 1);
    set_symbol ('90C', 'cyto loc', 1);
    set_symbol ('90D', 'cyto loc', 1);
    set_symbol ('90E', 'cyto loc', 1);
    set_symbol ('90F', 'cyto loc', 1);
    set_symbol ('91A', 'cyto loc', 1);
    set_symbol ('91B', 'cyto loc', 1);
    set_symbol ('91C', 'cyto loc', 1);
    set_symbol ('91D', 'cyto loc', 1);
    set_symbol ('91E', 'cyto loc', 1);
    set_symbol ('91F', 'cyto loc', 1);
    set_symbol ('92A', 'cyto loc', 1);
    set_symbol ('92B', 'cyto loc', 1);
    set_symbol ('92C', 'cyto loc', 1);
    set_symbol ('92D', 'cyto loc', 1);
    set_symbol ('92E', 'cyto loc', 1);
    set_symbol ('92F', 'cyto loc', 1);
    set_symbol ('93A', 'cyto loc', 1);
    set_symbol ('93B', 'cyto loc', 1);
    set_symbol ('93C', 'cyto loc', 1);
    set_symbol ('93D', 'cyto loc', 1);
    set_symbol ('93E', 'cyto loc', 1);
    set_symbol ('93F', 'cyto loc', 1);
    set_symbol ('94A', 'cyto loc', 1);
    set_symbol ('94B', 'cyto loc', 1);
    set_symbol ('94C', 'cyto loc', 1);
    set_symbol ('94D', 'cyto loc', 1);
    set_symbol ('94E', 'cyto loc', 1);
    set_symbol ('94F', 'cyto loc', 1);
    set_symbol ('95A', 'cyto loc', 1);
    set_symbol ('95B', 'cyto loc', 1);
    set_symbol ('95C', 'cyto loc', 1);
    set_symbol ('95D', 'cyto loc', 1);
    set_symbol ('95E', 'cyto loc', 1);
    set_symbol ('95F', 'cyto loc', 1);
    set_symbol ('96A', 'cyto loc', 1);
    set_symbol ('96B', 'cyto loc', 1);
    set_symbol ('96C', 'cyto loc', 1);
    set_symbol ('96D', 'cyto loc', 1);
    set_symbol ('96E', 'cyto loc', 1);
    set_symbol ('96F', 'cyto loc', 1);
    set_symbol ('97A', 'cyto loc', 1);
    set_symbol ('97B', 'cyto loc', 1);
    set_symbol ('97C', 'cyto loc', 1);
    set_symbol ('97D', 'cyto loc', 1);
    set_symbol ('97E', 'cyto loc', 1);
    set_symbol ('97F', 'cyto loc', 1);
    set_symbol ('98A', 'cyto loc', 1);
    set_symbol ('98B', 'cyto loc', 1);
    set_symbol ('98C', 'cyto loc', 1);
    set_symbol ('98D', 'cyto loc', 1);
    set_symbol ('98E', 'cyto loc', 1);
    set_symbol ('98F', 'cyto loc', 1);
    set_symbol ('99A', 'cyto loc', 1);
    set_symbol ('99B', 'cyto loc', 1);
    set_symbol ('99C', 'cyto loc', 1);
    set_symbol ('99D', 'cyto loc', 1);
    set_symbol ('99E', 'cyto loc', 1);
    set_symbol ('99F', 'cyto loc', 1);
    set_symbol ('100A', 'cyto loc', 1);
    set_symbol ('100B', 'cyto loc', 1);
    set_symbol ('100C', 'cyto loc', 1);
    set_symbol ('100D', 'cyto loc', 1);
    set_symbol ('100E', 'cyto loc', 1);
    set_symbol ('100F', 'cyto loc', 1);
    set_symbol ('101F', 'cyto loc', 1);
    set_symbol ('102A', 'cyto loc', 1);
    set_symbol ('102B', 'cyto loc', 1);
    set_symbol ('102C', 'cyto loc', 1);
    set_symbol ('102D', 'cyto loc', 1);
    set_symbol ('102E', 'cyto loc', 1);
    set_symbol ('102F', 'cyto loc', 1);
    set_symbol ('1A1', 'cyto loc', 1);
    set_symbol ('1A2', 'cyto loc', 1);
    set_symbol ('1A3', 'cyto loc', 1);
    set_symbol ('1A4', 'cyto loc', 1);
    set_symbol ('1A5', 'cyto loc', 1);
    set_symbol ('1A6', 'cyto loc', 1);
    set_symbol ('1A7', 'cyto loc', 1);
    set_symbol ('1A8', 'cyto loc', 1);
    set_symbol ('1B1', 'cyto loc', 1);
    set_symbol ('1B2', 'cyto loc', 1);
    set_symbol ('1B3', 'cyto loc', 1);
    set_symbol ('1B4', 'cyto loc', 1);
    set_symbol ('1B5', 'cyto loc', 1);
    set_symbol ('1B6', 'cyto loc', 1);
    set_symbol ('1B7', 'cyto loc', 1);
    set_symbol ('1B8', 'cyto loc', 1);
    set_symbol ('1B9', 'cyto loc', 1);
    set_symbol ('1B10', 'cyto loc', 1);
    set_symbol ('1B11', 'cyto loc', 1);
    set_symbol ('1B12', 'cyto loc', 1);
    set_symbol ('1B13', 'cyto loc', 1);
    set_symbol ('1B14', 'cyto loc', 1);
    set_symbol ('1C1', 'cyto loc', 1);
    set_symbol ('1C2', 'cyto loc', 1);
    set_symbol ('1C3', 'cyto loc', 1);
    set_symbol ('1C4', 'cyto loc', 1);
    set_symbol ('1C5', 'cyto loc', 1);
    set_symbol ('1D1', 'cyto loc', 1);
    set_symbol ('1D2', 'cyto loc', 1);
    set_symbol ('1D3', 'cyto loc', 1);
    set_symbol ('1D4', 'cyto loc', 1);
    set_symbol ('1E1', 'cyto loc', 1);
    set_symbol ('1E2', 'cyto loc', 1);
    set_symbol ('1E3', 'cyto loc', 1);
    set_symbol ('1E4', 'cyto loc', 1);
    set_symbol ('1E5', 'cyto loc', 1);
    set_symbol ('1F1', 'cyto loc', 1);
    set_symbol ('1F2', 'cyto loc', 1);
    set_symbol ('1F3', 'cyto loc', 1);
    set_symbol ('1F4', 'cyto loc', 1);
    set_symbol ('2A1', 'cyto loc', 1);
    set_symbol ('2A2', 'cyto loc', 1);
    set_symbol ('2A3', 'cyto loc', 1);
    set_symbol ('2A4', 'cyto loc', 1);
    set_symbol ('2B1', 'cyto loc', 1);
    set_symbol ('2B2', 'cyto loc', 1);
    set_symbol ('2B3', 'cyto loc', 1);
    set_symbol ('2B4', 'cyto loc', 1);
    set_symbol ('2B5', 'cyto loc', 1);
    set_symbol ('2B6', 'cyto loc', 1);
    set_symbol ('2B7', 'cyto loc', 1);
    set_symbol ('2B8', 'cyto loc', 1);
    set_symbol ('2B9', 'cyto loc', 1);
    set_symbol ('2B10', 'cyto loc', 1);
    set_symbol ('2B11', 'cyto loc', 1);
    set_symbol ('2B12', 'cyto loc', 1);
    set_symbol ('2B13', 'cyto loc', 1);
    set_symbol ('2B14', 'cyto loc', 1);
    set_symbol ('2B15', 'cyto loc', 1);
    set_symbol ('2B16', 'cyto loc', 1);
    set_symbol ('2B17', 'cyto loc', 1);
    set_symbol ('2B18', 'cyto loc', 1);
    set_symbol ('2C1', 'cyto loc', 1);
    set_symbol ('2C2', 'cyto loc', 1);
    set_symbol ('2C3', 'cyto loc', 1);
    set_symbol ('2C4', 'cyto loc', 1);
    set_symbol ('2C5', 'cyto loc', 1);
    set_symbol ('2C6', 'cyto loc', 1);
    set_symbol ('2C7', 'cyto loc', 1);
    set_symbol ('2C8', 'cyto loc', 1);
    set_symbol ('2C9', 'cyto loc', 1);
    set_symbol ('2C10', 'cyto loc', 1);
    set_symbol ('2D1', 'cyto loc', 1);
    set_symbol ('2D2', 'cyto loc', 1);
    set_symbol ('2D3', 'cyto loc', 1);
    set_symbol ('2D4', 'cyto loc', 1);
    set_symbol ('2D5', 'cyto loc', 1);
    set_symbol ('2D6', 'cyto loc', 1);
    set_symbol ('2E1', 'cyto loc', 1);
    set_symbol ('2E2', 'cyto loc', 1);
    set_symbol ('2E3', 'cyto loc', 1);
    set_symbol ('2F1', 'cyto loc', 1);
    set_symbol ('2F2', 'cyto loc', 1);
    set_symbol ('2F3', 'cyto loc', 1);
    set_symbol ('2F4', 'cyto loc', 1);
    set_symbol ('2F5', 'cyto loc', 1);
    set_symbol ('2F6', 'cyto loc', 1);
    set_symbol ('3A1', 'cyto loc', 1);
    set_symbol ('3A2', 'cyto loc', 1);
    set_symbol ('3A3', 'cyto loc', 1);
    set_symbol ('3A4', 'cyto loc', 1);
    set_symbol ('3A5', 'cyto loc', 1);
    set_symbol ('3A6', 'cyto loc', 1);
    set_symbol ('3A7', 'cyto loc', 1);
    set_symbol ('3A8', 'cyto loc', 1);
    set_symbol ('3A9', 'cyto loc', 1);
    set_symbol ('3A10', 'cyto loc', 1);
    set_symbol ('3B1', 'cyto loc', 1);
    set_symbol ('3B2', 'cyto loc', 1);
    set_symbol ('3B3', 'cyto loc', 1);
    set_symbol ('3B4', 'cyto loc', 1);
    set_symbol ('3B5', 'cyto loc', 1);
    set_symbol ('3B6', 'cyto loc', 1);
    set_symbol ('3C1', 'cyto loc', 1);
    set_symbol ('3C2', 'cyto loc', 1);
    set_symbol ('3C3', 'cyto loc', 1);
    set_symbol ('3C4', 'cyto loc', 1);
    set_symbol ('3C5', 'cyto loc', 1);
    set_symbol ('3C6', 'cyto loc', 1);
    set_symbol ('3C7', 'cyto loc', 1);
    set_symbol ('3C8', 'cyto loc', 1);
    set_symbol ('3C9', 'cyto loc', 1);
    set_symbol ('3C10', 'cyto loc', 1);
    set_symbol ('3C11', 'cyto loc', 1);
    set_symbol ('3C12', 'cyto loc', 1);
    set_symbol ('3D1', 'cyto loc', 1);
    set_symbol ('3D2', 'cyto loc', 1);
    set_symbol ('3D3', 'cyto loc', 1);
    set_symbol ('3D4', 'cyto loc', 1);
    set_symbol ('3D5', 'cyto loc', 1);
    set_symbol ('3D6', 'cyto loc', 1);
    set_symbol ('3D7', 'cyto loc', 1);
    set_symbol ('3E1', 'cyto loc', 1);
    set_symbol ('3E2', 'cyto loc', 1);
    set_symbol ('3E3', 'cyto loc', 1);
    set_symbol ('3E4', 'cyto loc', 1);
    set_symbol ('3E5', 'cyto loc', 1);
    set_symbol ('3E6', 'cyto loc', 1);
    set_symbol ('3E7', 'cyto loc', 1);
    set_symbol ('3E8', 'cyto loc', 1);
    set_symbol ('3F1', 'cyto loc', 1);
    set_symbol ('3F2', 'cyto loc', 1);
    set_symbol ('3F3', 'cyto loc', 1);
    set_symbol ('3F4', 'cyto loc', 1);
    set_symbol ('3F5', 'cyto loc', 1);
    set_symbol ('3F6', 'cyto loc', 1);
    set_symbol ('3F7', 'cyto loc', 1);
    set_symbol ('3F8', 'cyto loc', 1);
    set_symbol ('3F9', 'cyto loc', 1);
    set_symbol ('4A1', 'cyto loc', 1);
    set_symbol ('4A2', 'cyto loc', 1);
    set_symbol ('4A3', 'cyto loc', 1);
    set_symbol ('4A4', 'cyto loc', 1);
    set_symbol ('4A5', 'cyto loc', 1);
    set_symbol ('4A6', 'cyto loc', 1);
    set_symbol ('4B1', 'cyto loc', 1);
    set_symbol ('4B2', 'cyto loc', 1);
    set_symbol ('4B3', 'cyto loc', 1);
    set_symbol ('4B4', 'cyto loc', 1);
    set_symbol ('4B5', 'cyto loc', 1);
    set_symbol ('4B6', 'cyto loc', 1);
    set_symbol ('4C1', 'cyto loc', 1);
    set_symbol ('4C2', 'cyto loc', 1);
    set_symbol ('4C3', 'cyto loc', 1);
    set_symbol ('4C4', 'cyto loc', 1);
    set_symbol ('4C5', 'cyto loc', 1);
    set_symbol ('4C6', 'cyto loc', 1);
    set_symbol ('4C7', 'cyto loc', 1);
    set_symbol ('4C8', 'cyto loc', 1);
    set_symbol ('4C9', 'cyto loc', 1);
    set_symbol ('4C10', 'cyto loc', 1);
    set_symbol ('4C11', 'cyto loc', 1);
    set_symbol ('4C12', 'cyto loc', 1);
    set_symbol ('4C13', 'cyto loc', 1);
    set_symbol ('4C14', 'cyto loc', 1);
    set_symbol ('4C15', 'cyto loc', 1);
    set_symbol ('4C16', 'cyto loc', 1);
    set_symbol ('4D1', 'cyto loc', 1);
    set_symbol ('4D2', 'cyto loc', 1);
    set_symbol ('4D3', 'cyto loc', 1);
    set_symbol ('4D4', 'cyto loc', 1);
    set_symbol ('4D5', 'cyto loc', 1);
    set_symbol ('4D6', 'cyto loc', 1);
    set_symbol ('4D7', 'cyto loc', 1);
    set_symbol ('4E1', 'cyto loc', 1);
    set_symbol ('4E2', 'cyto loc', 1);
    set_symbol ('4E3', 'cyto loc', 1);
    set_symbol ('4F1', 'cyto loc', 1);
    set_symbol ('4F2', 'cyto loc', 1);
    set_symbol ('4F3', 'cyto loc', 1);
    set_symbol ('4F4', 'cyto loc', 1);
    set_symbol ('4F5', 'cyto loc', 1);
    set_symbol ('4F6', 'cyto loc', 1);
    set_symbol ('4F7', 'cyto loc', 1);
    set_symbol ('4F8', 'cyto loc', 1);
    set_symbol ('4F9', 'cyto loc', 1);
    set_symbol ('4F10', 'cyto loc', 1);
    set_symbol ('4F11', 'cyto loc', 1);
    set_symbol ('4F12', 'cyto loc', 1);
    set_symbol ('4F13', 'cyto loc', 1);
    set_symbol ('4F14', 'cyto loc', 1);
    set_symbol ('5A1', 'cyto loc', 1);
    set_symbol ('5A2', 'cyto loc', 1);
    set_symbol ('5A3', 'cyto loc', 1);
    set_symbol ('5A4', 'cyto loc', 1);
    set_symbol ('5A5', 'cyto loc', 1);
    set_symbol ('5A6', 'cyto loc', 1);
    set_symbol ('5A7', 'cyto loc', 1);
    set_symbol ('5A8', 'cyto loc', 1);
    set_symbol ('5A9', 'cyto loc', 1);
    set_symbol ('5A10', 'cyto loc', 1);
    set_symbol ('5A11', 'cyto loc', 1);
    set_symbol ('5A12', 'cyto loc', 1);
    set_symbol ('5A13', 'cyto loc', 1);
    set_symbol ('5A14', 'cyto loc', 1);
    set_symbol ('5B1', 'cyto loc', 1);
    set_symbol ('5B2', 'cyto loc', 1);
    set_symbol ('5B3', 'cyto loc', 1);
    set_symbol ('5B4', 'cyto loc', 1);
    set_symbol ('5B5', 'cyto loc', 1);
    set_symbol ('5B6', 'cyto loc', 1);
    set_symbol ('5B7', 'cyto loc', 1);
    set_symbol ('5B8', 'cyto loc', 1);
    set_symbol ('5B9', 'cyto loc', 1);
    set_symbol ('5B10', 'cyto loc', 1);
    set_symbol ('5C1', 'cyto loc', 1);
    set_symbol ('5C2', 'cyto loc', 1);
    set_symbol ('5C3', 'cyto loc', 1);
    set_symbol ('5C4', 'cyto loc', 1);
    set_symbol ('5C5', 'cyto loc', 1);
    set_symbol ('5C6', 'cyto loc', 1);
    set_symbol ('5C7', 'cyto loc', 1);
    set_symbol ('5C8', 'cyto loc', 1);
    set_symbol ('5C9', 'cyto loc', 1);
    set_symbol ('5C10', 'cyto loc', 1);
    set_symbol ('5D1', 'cyto loc', 1);
    set_symbol ('5D2', 'cyto loc', 1);
    set_symbol ('5D3', 'cyto loc', 1);
    set_symbol ('5D4', 'cyto loc', 1);
    set_symbol ('5D5', 'cyto loc', 1);
    set_symbol ('5D6', 'cyto loc', 1);
    set_symbol ('5D7', 'cyto loc', 1);
    set_symbol ('5D8', 'cyto loc', 1);
    set_symbol ('5E1', 'cyto loc', 1);
    set_symbol ('5E2', 'cyto loc', 1);
    set_symbol ('5E3', 'cyto loc', 1);
    set_symbol ('5E4', 'cyto loc', 1);
    set_symbol ('5E5', 'cyto loc', 1);
    set_symbol ('5E6', 'cyto loc', 1);
    set_symbol ('5E7', 'cyto loc', 1);
    set_symbol ('5E8', 'cyto loc', 1);
    set_symbol ('5F1', 'cyto loc', 1);
    set_symbol ('5F2', 'cyto loc', 1);
    set_symbol ('5F3', 'cyto loc', 1);
    set_symbol ('5F4', 'cyto loc', 1);
    set_symbol ('5F5', 'cyto loc', 1);
    set_symbol ('5F6', 'cyto loc', 1);
    set_symbol ('6A1', 'cyto loc', 1);
    set_symbol ('6A2', 'cyto loc', 1);
    set_symbol ('6A3', 'cyto loc', 1);
    set_symbol ('6A4', 'cyto loc', 1);
    set_symbol ('6B1', 'cyto loc', 1);
    set_symbol ('6B2', 'cyto loc', 1);
    set_symbol ('6B3', 'cyto loc', 1);
    set_symbol ('6B4', 'cyto loc', 1);
    set_symbol ('6C1', 'cyto loc', 1);
    set_symbol ('6C2', 'cyto loc', 1);
    set_symbol ('6C3', 'cyto loc', 1);
    set_symbol ('6C4', 'cyto loc', 1);
    set_symbol ('6C5', 'cyto loc', 1);
    set_symbol ('6C6', 'cyto loc', 1);
    set_symbol ('6C7', 'cyto loc', 1);
    set_symbol ('6C8', 'cyto loc', 1);
    set_symbol ('6C9', 'cyto loc', 1);
    set_symbol ('6C10', 'cyto loc', 1);
    set_symbol ('6C11', 'cyto loc', 1);
    set_symbol ('6C12', 'cyto loc', 1);
    set_symbol ('6C13', 'cyto loc', 1);
    set_symbol ('6D1', 'cyto loc', 1);
    set_symbol ('6D2', 'cyto loc', 1);
    set_symbol ('6D3', 'cyto loc', 1);
    set_symbol ('6D4', 'cyto loc', 1);
    set_symbol ('6D5', 'cyto loc', 1);
    set_symbol ('6D6', 'cyto loc', 1);
    set_symbol ('6D7', 'cyto loc', 1);
    set_symbol ('6D8', 'cyto loc', 1);
    set_symbol ('6E1', 'cyto loc', 1);
    set_symbol ('6E2', 'cyto loc', 1);
    set_symbol ('6E3', 'cyto loc', 1);
    set_symbol ('6E4', 'cyto loc', 1);
    set_symbol ('6E5', 'cyto loc', 1);
    set_symbol ('6E6', 'cyto loc', 1);
    set_symbol ('6E7', 'cyto loc', 1);
    set_symbol ('6F1', 'cyto loc', 1);
    set_symbol ('6F2', 'cyto loc', 1);
    set_symbol ('6F3', 'cyto loc', 1);
    set_symbol ('6F4', 'cyto loc', 1);
    set_symbol ('6F5', 'cyto loc', 1);
    set_symbol ('6F6', 'cyto loc', 1);
    set_symbol ('6F7', 'cyto loc', 1);
    set_symbol ('6F8', 'cyto loc', 1);
    set_symbol ('6F9', 'cyto loc', 1);
    set_symbol ('6F10', 'cyto loc', 1);
    set_symbol ('6F11', 'cyto loc', 1);
    set_symbol ('7A1', 'cyto loc', 1);
    set_symbol ('7A2', 'cyto loc', 1);
    set_symbol ('7A3', 'cyto loc', 1);
    set_symbol ('7A4', 'cyto loc', 1);
    set_symbol ('7A5', 'cyto loc', 1);
    set_symbol ('7A6', 'cyto loc', 1);
    set_symbol ('7A7', 'cyto loc', 1);
    set_symbol ('7A8', 'cyto loc', 1);
    set_symbol ('7B1', 'cyto loc', 1);
    set_symbol ('7B2', 'cyto loc', 1);
    set_symbol ('7B3', 'cyto loc', 1);
    set_symbol ('7B4', 'cyto loc', 1);
    set_symbol ('7B5', 'cyto loc', 1);
    set_symbol ('7B6', 'cyto loc', 1);
    set_symbol ('7B7', 'cyto loc', 1);
    set_symbol ('7B8', 'cyto loc', 1);
    set_symbol ('7C1', 'cyto loc', 1);
    set_symbol ('7C2', 'cyto loc', 1);
    set_symbol ('7C3', 'cyto loc', 1);
    set_symbol ('7C4', 'cyto loc', 1);
    set_symbol ('7C5', 'cyto loc', 1);
    set_symbol ('7C6', 'cyto loc', 1);
    set_symbol ('7C7', 'cyto loc', 1);
    set_symbol ('7C8', 'cyto loc', 1);
    set_symbol ('7C9', 'cyto loc', 1);
    set_symbol ('7D1', 'cyto loc', 1);
    set_symbol ('7D2', 'cyto loc', 1);
    set_symbol ('7D3', 'cyto loc', 1);
    set_symbol ('7D4', 'cyto loc', 1);
    set_symbol ('7D5', 'cyto loc', 1);
    set_symbol ('7D6', 'cyto loc', 1);
    set_symbol ('7D7', 'cyto loc', 1);
    set_symbol ('7D8', 'cyto loc', 1);
    set_symbol ('7D9', 'cyto loc', 1);
    set_symbol ('7D10', 'cyto loc', 1);
    set_symbol ('7D11', 'cyto loc', 1);
    set_symbol ('7D12', 'cyto loc', 1);
    set_symbol ('7D13', 'cyto loc', 1);
    set_symbol ('7D14', 'cyto loc', 1);
    set_symbol ('7D15', 'cyto loc', 1);
    set_symbol ('7D16', 'cyto loc', 1);
    set_symbol ('7D17', 'cyto loc', 1);
    set_symbol ('7D18', 'cyto loc', 1);
    set_symbol ('7D19', 'cyto loc', 1);
    set_symbol ('7D20', 'cyto loc', 1);
    set_symbol ('7D21', 'cyto loc', 1);
    set_symbol ('7D22', 'cyto loc', 1);
    set_symbol ('7E1', 'cyto loc', 1);
    set_symbol ('7E2', 'cyto loc', 1);
    set_symbol ('7E3', 'cyto loc', 1);
    set_symbol ('7E4', 'cyto loc', 1);
    set_symbol ('7E5', 'cyto loc', 1);
    set_symbol ('7E6', 'cyto loc', 1);
    set_symbol ('7E7', 'cyto loc', 1);
    set_symbol ('7E8', 'cyto loc', 1);
    set_symbol ('7E9', 'cyto loc', 1);
    set_symbol ('7E10', 'cyto loc', 1);
    set_symbol ('7E11', 'cyto loc', 1);
    set_symbol ('7F1', 'cyto loc', 1);
    set_symbol ('7F2', 'cyto loc', 1);
    set_symbol ('7F3', 'cyto loc', 1);
    set_symbol ('7F4', 'cyto loc', 1);
    set_symbol ('7F5', 'cyto loc', 1);
    set_symbol ('7F6', 'cyto loc', 1);
    set_symbol ('7F7', 'cyto loc', 1);
    set_symbol ('7F8', 'cyto loc', 1);
    set_symbol ('7F9', 'cyto loc', 1);
    set_symbol ('7F10', 'cyto loc', 1);
    set_symbol ('8A1', 'cyto loc', 1);
    set_symbol ('8A2', 'cyto loc', 1);
    set_symbol ('8A3', 'cyto loc', 1);
    set_symbol ('8A4', 'cyto loc', 1);
    set_symbol ('8A5', 'cyto loc', 1);
    set_symbol ('8B1', 'cyto loc', 1);
    set_symbol ('8B2', 'cyto loc', 1);
    set_symbol ('8B3', 'cyto loc', 1);
    set_symbol ('8B4', 'cyto loc', 1);
    set_symbol ('8B5', 'cyto loc', 1);
    set_symbol ('8B6', 'cyto loc', 1);
    set_symbol ('8B7', 'cyto loc', 1);
    set_symbol ('8B8', 'cyto loc', 1);
    set_symbol ('8C1', 'cyto loc', 1);
    set_symbol ('8C2', 'cyto loc', 1);
    set_symbol ('8C3', 'cyto loc', 1);
    set_symbol ('8C4', 'cyto loc', 1);
    set_symbol ('8C5', 'cyto loc', 1);
    set_symbol ('8C6', 'cyto loc', 1);
    set_symbol ('8C7', 'cyto loc', 1);
    set_symbol ('8C8', 'cyto loc', 1);
    set_symbol ('8C9', 'cyto loc', 1);
    set_symbol ('8C10', 'cyto loc', 1);
    set_symbol ('8C11', 'cyto loc', 1);
    set_symbol ('8C12', 'cyto loc', 1);
    set_symbol ('8C13', 'cyto loc', 1);
    set_symbol ('8C14', 'cyto loc', 1);
    set_symbol ('8C15', 'cyto loc', 1);
    set_symbol ('8C16', 'cyto loc', 1);
    set_symbol ('8C17', 'cyto loc', 1);
    set_symbol ('8D1', 'cyto loc', 1);
    set_symbol ('8D2', 'cyto loc', 1);
    set_symbol ('8D3', 'cyto loc', 1);
    set_symbol ('8D4', 'cyto loc', 1);
    set_symbol ('8D5', 'cyto loc', 1);
    set_symbol ('8D6', 'cyto loc', 1);
    set_symbol ('8D7', 'cyto loc', 1);
    set_symbol ('8D8', 'cyto loc', 1);
    set_symbol ('8D9', 'cyto loc', 1);
    set_symbol ('8D10', 'cyto loc', 1);
    set_symbol ('8D11', 'cyto loc', 1);
    set_symbol ('8D12', 'cyto loc', 1);
    set_symbol ('8E1', 'cyto loc', 1);
    set_symbol ('8E2', 'cyto loc', 1);
    set_symbol ('8E3', 'cyto loc', 1);
    set_symbol ('8E4', 'cyto loc', 1);
    set_symbol ('8E5', 'cyto loc', 1);
    set_symbol ('8E6', 'cyto loc', 1);
    set_symbol ('8E7', 'cyto loc', 1);
    set_symbol ('8E8', 'cyto loc', 1);
    set_symbol ('8E9', 'cyto loc', 1);
    set_symbol ('8E10', 'cyto loc', 1);
    set_symbol ('8E11', 'cyto loc', 1);
    set_symbol ('8E12', 'cyto loc', 1);
    set_symbol ('8F1', 'cyto loc', 1);
    set_symbol ('8F2', 'cyto loc', 1);
    set_symbol ('8F3', 'cyto loc', 1);
    set_symbol ('8F4', 'cyto loc', 1);
    set_symbol ('8F5', 'cyto loc', 1);
    set_symbol ('8F6', 'cyto loc', 1);
    set_symbol ('8F7', 'cyto loc', 1);
    set_symbol ('8F8', 'cyto loc', 1);
    set_symbol ('8F9', 'cyto loc', 1);
    set_symbol ('8F10', 'cyto loc', 1);
    set_symbol ('9A1', 'cyto loc', 1);
    set_symbol ('9A2', 'cyto loc', 1);
    set_symbol ('9A3', 'cyto loc', 1);
    set_symbol ('9A4', 'cyto loc', 1);
    set_symbol ('9A5', 'cyto loc', 1);
    set_symbol ('9B1', 'cyto loc', 1);
    set_symbol ('9B2', 'cyto loc', 1);
    set_symbol ('9B3', 'cyto loc', 1);
    set_symbol ('9B4', 'cyto loc', 1);
    set_symbol ('9B5', 'cyto loc', 1);
    set_symbol ('9B6', 'cyto loc', 1);
    set_symbol ('9B7', 'cyto loc', 1);
    set_symbol ('9B8', 'cyto loc', 1);
    set_symbol ('9B9', 'cyto loc', 1);
    set_symbol ('9B10', 'cyto loc', 1);
    set_symbol ('9B11', 'cyto loc', 1);
    set_symbol ('9B12', 'cyto loc', 1);
    set_symbol ('9B13', 'cyto loc', 1);
    set_symbol ('9B14', 'cyto loc', 1);
    set_symbol ('9B15', 'cyto loc', 1);
    set_symbol ('9C1', 'cyto loc', 1);
    set_symbol ('9C2', 'cyto loc', 1);
    set_symbol ('9C3', 'cyto loc', 1);
    set_symbol ('9C4', 'cyto loc', 1);
    set_symbol ('9C5', 'cyto loc', 1);
    set_symbol ('9C6', 'cyto loc', 1);
    set_symbol ('9D1', 'cyto loc', 1);
    set_symbol ('9D2', 'cyto loc', 1);
    set_symbol ('9D3', 'cyto loc', 1);
    set_symbol ('9D4', 'cyto loc', 1);
    set_symbol ('9E1', 'cyto loc', 1);
    set_symbol ('9E2', 'cyto loc', 1);
    set_symbol ('9E3', 'cyto loc', 1);
    set_symbol ('9E4', 'cyto loc', 1);
    set_symbol ('9E5', 'cyto loc', 1);
    set_symbol ('9E6', 'cyto loc', 1);
    set_symbol ('9E7', 'cyto loc', 1);
    set_symbol ('9E8', 'cyto loc', 1);
    set_symbol ('9E9', 'cyto loc', 1);
    set_symbol ('9E10', 'cyto loc', 1);
    set_symbol ('9F1', 'cyto loc', 1);
    set_symbol ('9F2', 'cyto loc', 1);
    set_symbol ('9F3', 'cyto loc', 1);
    set_symbol ('9F4', 'cyto loc', 1);
    set_symbol ('9F5', 'cyto loc', 1);
    set_symbol ('9F6', 'cyto loc', 1);
    set_symbol ('9F7', 'cyto loc', 1);
    set_symbol ('9F8', 'cyto loc', 1);
    set_symbol ('9F9', 'cyto loc', 1);
    set_symbol ('9F10', 'cyto loc', 1);
    set_symbol ('9F11', 'cyto loc', 1);
    set_symbol ('9F12', 'cyto loc', 1);
    set_symbol ('9F13', 'cyto loc', 1);
    set_symbol ('10A1', 'cyto loc', 1);
    set_symbol ('10A2', 'cyto loc', 1);
    set_symbol ('10A3', 'cyto loc', 1);
    set_symbol ('10A4', 'cyto loc', 1);
    set_symbol ('10A5', 'cyto loc', 1);
    set_symbol ('10A6', 'cyto loc', 1);
    set_symbol ('10A7', 'cyto loc', 1);
    set_symbol ('10A8', 'cyto loc', 1);
    set_symbol ('10A9', 'cyto loc', 1);
    set_symbol ('10A10', 'cyto loc', 1);
    set_symbol ('10A11', 'cyto loc', 1);
    set_symbol ('10B1', 'cyto loc', 1);
    set_symbol ('10B2', 'cyto loc', 1);
    set_symbol ('10B3', 'cyto loc', 1);
    set_symbol ('10B4', 'cyto loc', 1);
    set_symbol ('10B5', 'cyto loc', 1);
    set_symbol ('10B6', 'cyto loc', 1);
    set_symbol ('10B7', 'cyto loc', 1);
    set_symbol ('10B8', 'cyto loc', 1);
    set_symbol ('10B9', 'cyto loc', 1);
    set_symbol ('10B10', 'cyto loc', 1);
    set_symbol ('10B11', 'cyto loc', 1);
    set_symbol ('10B12', 'cyto loc', 1);
    set_symbol ('10B13', 'cyto loc', 1);
    set_symbol ('10B14', 'cyto loc', 1);
    set_symbol ('10B15', 'cyto loc', 1);
    set_symbol ('10B16', 'cyto loc', 1);
    set_symbol ('10B17', 'cyto loc', 1);
    set_symbol ('10C1', 'cyto loc', 1);
    set_symbol ('10C2', 'cyto loc', 1);
    set_symbol ('10C3', 'cyto loc', 1);
    set_symbol ('10C4', 'cyto loc', 1);
    set_symbol ('10C5', 'cyto loc', 1);
    set_symbol ('10C6', 'cyto loc', 1);
    set_symbol ('10C7', 'cyto loc', 1);
    set_symbol ('10C8', 'cyto loc', 1);
    set_symbol ('10C9', 'cyto loc', 1);
    set_symbol ('10C10', 'cyto loc', 1);
    set_symbol ('10D1', 'cyto loc', 1);
    set_symbol ('10D2', 'cyto loc', 1);
    set_symbol ('10D3', 'cyto loc', 1);
    set_symbol ('10D4', 'cyto loc', 1);
    set_symbol ('10D5', 'cyto loc', 1);
    set_symbol ('10D6', 'cyto loc', 1);
    set_symbol ('10D7', 'cyto loc', 1);
    set_symbol ('10D8', 'cyto loc', 1);
    set_symbol ('10E1', 'cyto loc', 1);
    set_symbol ('10E2', 'cyto loc', 1);
    set_symbol ('10E3', 'cyto loc', 1);
    set_symbol ('10E4', 'cyto loc', 1);
    set_symbol ('10E5', 'cyto loc', 1);
    set_symbol ('10E6', 'cyto loc', 1);
    set_symbol ('10F1', 'cyto loc', 1);
    set_symbol ('10F2', 'cyto loc', 1);
    set_symbol ('10F3', 'cyto loc', 1);
    set_symbol ('10F4', 'cyto loc', 1);
    set_symbol ('10F5', 'cyto loc', 1);
    set_symbol ('10F6', 'cyto loc', 1);
    set_symbol ('10F7', 'cyto loc', 1);
    set_symbol ('10F8', 'cyto loc', 1);
    set_symbol ('10F9', 'cyto loc', 1);
    set_symbol ('10F10', 'cyto loc', 1);
    set_symbol ('10F11', 'cyto loc', 1);
    set_symbol ('11A1', 'cyto loc', 1);
    set_symbol ('11A2', 'cyto loc', 1);
    set_symbol ('11A3', 'cyto loc', 1);
    set_symbol ('11A4', 'cyto loc', 1);
    set_symbol ('11A5', 'cyto loc', 1);
    set_symbol ('11A6', 'cyto loc', 1);
    set_symbol ('11A7', 'cyto loc', 1);
    set_symbol ('11A8', 'cyto loc', 1);
    set_symbol ('11A9', 'cyto loc', 1);
    set_symbol ('11A10', 'cyto loc', 1);
    set_symbol ('11A11', 'cyto loc', 1);
    set_symbol ('11A12', 'cyto loc', 1);
    set_symbol ('11B1', 'cyto loc', 1);
    set_symbol ('11B2', 'cyto loc', 1);
    set_symbol ('11B3', 'cyto loc', 1);
    set_symbol ('11B4', 'cyto loc', 1);
    set_symbol ('11B5', 'cyto loc', 1);
    set_symbol ('11B6', 'cyto loc', 1);
    set_symbol ('11B7', 'cyto loc', 1);
    set_symbol ('11B8', 'cyto loc', 1);
    set_symbol ('11B9', 'cyto loc', 1);
    set_symbol ('11B10', 'cyto loc', 1);
    set_symbol ('11B11', 'cyto loc', 1);
    set_symbol ('11B12', 'cyto loc', 1);
    set_symbol ('11B13', 'cyto loc', 1);
    set_symbol ('11B14', 'cyto loc', 1);
    set_symbol ('11B15', 'cyto loc', 1);
    set_symbol ('11B16', 'cyto loc', 1);
    set_symbol ('11B17', 'cyto loc', 1);
    set_symbol ('11B18', 'cyto loc', 1);
    set_symbol ('11B19', 'cyto loc', 1);
    set_symbol ('11C1', 'cyto loc', 1);
    set_symbol ('11C2', 'cyto loc', 1);
    set_symbol ('11C3', 'cyto loc', 1);
    set_symbol ('11C4', 'cyto loc', 1);
    set_symbol ('11D1', 'cyto loc', 1);
    set_symbol ('11D2', 'cyto loc', 1);
    set_symbol ('11D3', 'cyto loc', 1);
    set_symbol ('11D4', 'cyto loc', 1);
    set_symbol ('11D5', 'cyto loc', 1);
    set_symbol ('11D6', 'cyto loc', 1);
    set_symbol ('11D7', 'cyto loc', 1);
    set_symbol ('11D8', 'cyto loc', 1);
    set_symbol ('11D9', 'cyto loc', 1);
    set_symbol ('11D10', 'cyto loc', 1);
    set_symbol ('11D11', 'cyto loc', 1);
    set_symbol ('11E1', 'cyto loc', 1);
    set_symbol ('11E2', 'cyto loc', 1);
    set_symbol ('11E3', 'cyto loc', 1);
    set_symbol ('11E4', 'cyto loc', 1);
    set_symbol ('11E5', 'cyto loc', 1);
    set_symbol ('11E6', 'cyto loc', 1);
    set_symbol ('11E7', 'cyto loc', 1);
    set_symbol ('11E8', 'cyto loc', 1);
    set_symbol ('11E9', 'cyto loc', 1);
    set_symbol ('11E10', 'cyto loc', 1);
    set_symbol ('11E11', 'cyto loc', 1);
    set_symbol ('11E12', 'cyto loc', 1);
    set_symbol ('11E13', 'cyto loc', 1);
    set_symbol ('11F1', 'cyto loc', 1);
    set_symbol ('11F2', 'cyto loc', 1);
    set_symbol ('11F3', 'cyto loc', 1);
    set_symbol ('11F4', 'cyto loc', 1);
    set_symbol ('11F5', 'cyto loc', 1);
    set_symbol ('11F6', 'cyto loc', 1);
    set_symbol ('11F7', 'cyto loc', 1);
    set_symbol ('11F8', 'cyto loc', 1);
    set_symbol ('12A1', 'cyto loc', 1);
    set_symbol ('12A2', 'cyto loc', 1);
    set_symbol ('12A3', 'cyto loc', 1);
    set_symbol ('12A4', 'cyto loc', 1);
    set_symbol ('12A5', 'cyto loc', 1);
    set_symbol ('12A6', 'cyto loc', 1);
    set_symbol ('12A7', 'cyto loc', 1);
    set_symbol ('12A8', 'cyto loc', 1);
    set_symbol ('12A9', 'cyto loc', 1);
    set_symbol ('12A10', 'cyto loc', 1);
    set_symbol ('12B1', 'cyto loc', 1);
    set_symbol ('12B2', 'cyto loc', 1);
    set_symbol ('12B3', 'cyto loc', 1);
    set_symbol ('12B4', 'cyto loc', 1);
    set_symbol ('12B5', 'cyto loc', 1);
    set_symbol ('12B6', 'cyto loc', 1);
    set_symbol ('12B7', 'cyto loc', 1);
    set_symbol ('12B8', 'cyto loc', 1);
    set_symbol ('12B9', 'cyto loc', 1);
    set_symbol ('12B10', 'cyto loc', 1);
    set_symbol ('12C1', 'cyto loc', 1);
    set_symbol ('12C2', 'cyto loc', 1);
    set_symbol ('12C3', 'cyto loc', 1);
    set_symbol ('12C4', 'cyto loc', 1);
    set_symbol ('12C5', 'cyto loc', 1);
    set_symbol ('12C6', 'cyto loc', 1);
    set_symbol ('12C7', 'cyto loc', 1);
    set_symbol ('12C8', 'cyto loc', 1);
    set_symbol ('12D1', 'cyto loc', 1);
    set_symbol ('12D2', 'cyto loc', 1);
    set_symbol ('12D3', 'cyto loc', 1);
    set_symbol ('12D4', 'cyto loc', 1);
    set_symbol ('12D5', 'cyto loc', 1);
    set_symbol ('12E1', 'cyto loc', 1);
    set_symbol ('12E2', 'cyto loc', 1);
    set_symbol ('12E3', 'cyto loc', 1);
    set_symbol ('12E4', 'cyto loc', 1);
    set_symbol ('12E5', 'cyto loc', 1);
    set_symbol ('12E6', 'cyto loc', 1);
    set_symbol ('12E7', 'cyto loc', 1);
    set_symbol ('12E8', 'cyto loc', 1);
    set_symbol ('12E9', 'cyto loc', 1);
    set_symbol ('12E10', 'cyto loc', 1);
    set_symbol ('12E11', 'cyto loc', 1);
    set_symbol ('12F1', 'cyto loc', 1);
    set_symbol ('12F2', 'cyto loc', 1);
    set_symbol ('12F3', 'cyto loc', 1);
    set_symbol ('12F4', 'cyto loc', 1);
    set_symbol ('12F5', 'cyto loc', 1);
    set_symbol ('12F6', 'cyto loc', 1);
    set_symbol ('12F7', 'cyto loc', 1);
    set_symbol ('13A1', 'cyto loc', 1);
    set_symbol ('13A2', 'cyto loc', 1);
    set_symbol ('13A3', 'cyto loc', 1);
    set_symbol ('13A4', 'cyto loc', 1);
    set_symbol ('13A5', 'cyto loc', 1);
    set_symbol ('13A6', 'cyto loc', 1);
    set_symbol ('13A7', 'cyto loc', 1);
    set_symbol ('13A8', 'cyto loc', 1);
    set_symbol ('13A9', 'cyto loc', 1);
    set_symbol ('13A10', 'cyto loc', 1);
    set_symbol ('13A11', 'cyto loc', 1);
    set_symbol ('13A12', 'cyto loc', 1);
    set_symbol ('13B1', 'cyto loc', 1);
    set_symbol ('13B2', 'cyto loc', 1);
    set_symbol ('13B3', 'cyto loc', 1);
    set_symbol ('13B4', 'cyto loc', 1);
    set_symbol ('13B5', 'cyto loc', 1);
    set_symbol ('13B6', 'cyto loc', 1);
    set_symbol ('13B7', 'cyto loc', 1);
    set_symbol ('13B8', 'cyto loc', 1);
    set_symbol ('13B9', 'cyto loc', 1);
    set_symbol ('13C1', 'cyto loc', 1);
    set_symbol ('13C2', 'cyto loc', 1);
    set_symbol ('13C3', 'cyto loc', 1);
    set_symbol ('13C4', 'cyto loc', 1);
    set_symbol ('13C5', 'cyto loc', 1);
    set_symbol ('13C6', 'cyto loc', 1);
    set_symbol ('13C7', 'cyto loc', 1);
    set_symbol ('13C8', 'cyto loc', 1);
    set_symbol ('13D1', 'cyto loc', 1);
    set_symbol ('13D2', 'cyto loc', 1);
    set_symbol ('13D3', 'cyto loc', 1);
    set_symbol ('13D4', 'cyto loc', 1);
    set_symbol ('13D5', 'cyto loc', 1);
    set_symbol ('13E1', 'cyto loc', 1);
    set_symbol ('13E2', 'cyto loc', 1);
    set_symbol ('13E3', 'cyto loc', 1);
    set_symbol ('13E4', 'cyto loc', 1);
    set_symbol ('13E5', 'cyto loc', 1);
    set_symbol ('13E6', 'cyto loc', 1);
    set_symbol ('13E7', 'cyto loc', 1);
    set_symbol ('13E8', 'cyto loc', 1);
    set_symbol ('13E9', 'cyto loc', 1);
    set_symbol ('13E10', 'cyto loc', 1);
    set_symbol ('13E11', 'cyto loc', 1);
    set_symbol ('13E12', 'cyto loc', 1);
    set_symbol ('13E13', 'cyto loc', 1);
    set_symbol ('13E14', 'cyto loc', 1);
    set_symbol ('13E15', 'cyto loc', 1);
    set_symbol ('13E16', 'cyto loc', 1);
    set_symbol ('13E17', 'cyto loc', 1);
    set_symbol ('13E18', 'cyto loc', 1);
    set_symbol ('13F1', 'cyto loc', 1);
    set_symbol ('13F2', 'cyto loc', 1);
    set_symbol ('13F3', 'cyto loc', 1);
    set_symbol ('13F4', 'cyto loc', 1);
    set_symbol ('13F5', 'cyto loc', 1);
    set_symbol ('13F6', 'cyto loc', 1);
    set_symbol ('13F7', 'cyto loc', 1);
    set_symbol ('13F8', 'cyto loc', 1);
    set_symbol ('13F9', 'cyto loc', 1);
    set_symbol ('13F10', 'cyto loc', 1);
    set_symbol ('13F11', 'cyto loc', 1);
    set_symbol ('13F12', 'cyto loc', 1);
    set_symbol ('13F13', 'cyto loc', 1);
    set_symbol ('13F14', 'cyto loc', 1);
    set_symbol ('13F15', 'cyto loc', 1);
    set_symbol ('13F16', 'cyto loc', 1);
    set_symbol ('13F17', 'cyto loc', 1);
    set_symbol ('13F18', 'cyto loc', 1);
    set_symbol ('14A1', 'cyto loc', 1);
    set_symbol ('14A2', 'cyto loc', 1);
    set_symbol ('14A3', 'cyto loc', 1);
    set_symbol ('14A4', 'cyto loc', 1);
    set_symbol ('14A5', 'cyto loc', 1);
    set_symbol ('14A6', 'cyto loc', 1);
    set_symbol ('14A7', 'cyto loc', 1);
    set_symbol ('14A8', 'cyto loc', 1);
    set_symbol ('14A9', 'cyto loc', 1);
    set_symbol ('14B1', 'cyto loc', 1);
    set_symbol ('14B2', 'cyto loc', 1);
    set_symbol ('14B3', 'cyto loc', 1);
    set_symbol ('14B4', 'cyto loc', 1);
    set_symbol ('14B5', 'cyto loc', 1);
    set_symbol ('14B6', 'cyto loc', 1);
    set_symbol ('14B7', 'cyto loc', 1);
    set_symbol ('14B8', 'cyto loc', 1);
    set_symbol ('14B9', 'cyto loc', 1);
    set_symbol ('14B10', 'cyto loc', 1);
    set_symbol ('14B11', 'cyto loc', 1);
    set_symbol ('14B12', 'cyto loc', 1);
    set_symbol ('14B13', 'cyto loc', 1);
    set_symbol ('14B14', 'cyto loc', 1);
    set_symbol ('14B15', 'cyto loc', 1);
    set_symbol ('14B16', 'cyto loc', 1);
    set_symbol ('14B17', 'cyto loc', 1);
    set_symbol ('14B18', 'cyto loc', 1);
    set_symbol ('14C1', 'cyto loc', 1);
    set_symbol ('14C2', 'cyto loc', 1);
    set_symbol ('14C3', 'cyto loc', 1);
    set_symbol ('14C4', 'cyto loc', 1);
    set_symbol ('14C5', 'cyto loc', 1);
    set_symbol ('14C6', 'cyto loc', 1);
    set_symbol ('14C7', 'cyto loc', 1);
    set_symbol ('14C8', 'cyto loc', 1);
    set_symbol ('14D1', 'cyto loc', 1);
    set_symbol ('14D2', 'cyto loc', 1);
    set_symbol ('14D3', 'cyto loc', 1);
    set_symbol ('14D4', 'cyto loc', 1);
    set_symbol ('14E1', 'cyto loc', 1);
    set_symbol ('14E2', 'cyto loc', 1);
    set_symbol ('14E3', 'cyto loc', 1);
    set_symbol ('14E4', 'cyto loc', 1);
    set_symbol ('14F1', 'cyto loc', 1);
    set_symbol ('14F2', 'cyto loc', 1);
    set_symbol ('14F3', 'cyto loc', 1);
    set_symbol ('14F4', 'cyto loc', 1);
    set_symbol ('14F5', 'cyto loc', 1);
    set_symbol ('14F6', 'cyto loc', 1);
    set_symbol ('15A1', 'cyto loc', 1);
    set_symbol ('15A2', 'cyto loc', 1);
    set_symbol ('15A3', 'cyto loc', 1);
    set_symbol ('15A4', 'cyto loc', 1);
    set_symbol ('15A5', 'cyto loc', 1);
    set_symbol ('15A6', 'cyto loc', 1);
    set_symbol ('15A7', 'cyto loc', 1);
    set_symbol ('15A8', 'cyto loc', 1);
    set_symbol ('15A9', 'cyto loc', 1);
    set_symbol ('15A10', 'cyto loc', 1);
    set_symbol ('15A11', 'cyto loc', 1);
    set_symbol ('15B1', 'cyto loc', 1);
    set_symbol ('15B2', 'cyto loc', 1);
    set_symbol ('15B3', 'cyto loc', 1);
    set_symbol ('15B4', 'cyto loc', 1);
    set_symbol ('15B5', 'cyto loc', 1);
    set_symbol ('15C1', 'cyto loc', 1);
    set_symbol ('15C2', 'cyto loc', 1);
    set_symbol ('15C3', 'cyto loc', 1);
    set_symbol ('15C4', 'cyto loc', 1);
    set_symbol ('15C5', 'cyto loc', 1);
    set_symbol ('15C6', 'cyto loc', 1);
    set_symbol ('15D1', 'cyto loc', 1);
    set_symbol ('15D2', 'cyto loc', 1);
    set_symbol ('15D3', 'cyto loc', 1);
    set_symbol ('15D4', 'cyto loc', 1);
    set_symbol ('15D5', 'cyto loc', 1);
    set_symbol ('15D6', 'cyto loc', 1);
    set_symbol ('15E1', 'cyto loc', 1);
    set_symbol ('15E2', 'cyto loc', 1);
    set_symbol ('15E3', 'cyto loc', 1);
    set_symbol ('15E4', 'cyto loc', 1);
    set_symbol ('15E5', 'cyto loc', 1);
    set_symbol ('15E6', 'cyto loc', 1);
    set_symbol ('15E7', 'cyto loc', 1);
    set_symbol ('15F1', 'cyto loc', 1);
    set_symbol ('15F2', 'cyto loc', 1);
    set_symbol ('15F3', 'cyto loc', 1);
    set_symbol ('15F4', 'cyto loc', 1);
    set_symbol ('15F5', 'cyto loc', 1);
    set_symbol ('15F6', 'cyto loc', 1);
    set_symbol ('15F7', 'cyto loc', 1);
    set_symbol ('15F8', 'cyto loc', 1);
    set_symbol ('15F9', 'cyto loc', 1);
    set_symbol ('16A1', 'cyto loc', 1);
    set_symbol ('16A2', 'cyto loc', 1);
    set_symbol ('16A3', 'cyto loc', 1);
    set_symbol ('16A4', 'cyto loc', 1);
    set_symbol ('16A5', 'cyto loc', 1);
    set_symbol ('16A6', 'cyto loc', 1);
    set_symbol ('16A7', 'cyto loc', 1);
    set_symbol ('16B1', 'cyto loc', 1);
    set_symbol ('16B2', 'cyto loc', 1);
    set_symbol ('16B3', 'cyto loc', 1);
    set_symbol ('16B4', 'cyto loc', 1);
    set_symbol ('16B5', 'cyto loc', 1);
    set_symbol ('16B6', 'cyto loc', 1);
    set_symbol ('16B7', 'cyto loc', 1);
    set_symbol ('16B8', 'cyto loc', 1);
    set_symbol ('16B9', 'cyto loc', 1);
    set_symbol ('16B10', 'cyto loc', 1);
    set_symbol ('16B11', 'cyto loc', 1);
    set_symbol ('16B12', 'cyto loc', 1);
    set_symbol ('16C1', 'cyto loc', 1);
    set_symbol ('16C2', 'cyto loc', 1);
    set_symbol ('16C3', 'cyto loc', 1);
    set_symbol ('16C4', 'cyto loc', 1);
    set_symbol ('16C5', 'cyto loc', 1);
    set_symbol ('16C6', 'cyto loc', 1);
    set_symbol ('16C7', 'cyto loc', 1);
    set_symbol ('16C8', 'cyto loc', 1);
    set_symbol ('16C9', 'cyto loc', 1);
    set_symbol ('16C10', 'cyto loc', 1);
    set_symbol ('16D1', 'cyto loc', 1);
    set_symbol ('16D2', 'cyto loc', 1);
    set_symbol ('16D3', 'cyto loc', 1);
    set_symbol ('16D4', 'cyto loc', 1);
    set_symbol ('16D5', 'cyto loc', 1);
    set_symbol ('16D6', 'cyto loc', 1);
    set_symbol ('16D7', 'cyto loc', 1);
    set_symbol ('16E1', 'cyto loc', 1);
    set_symbol ('16E2', 'cyto loc', 1);
    set_symbol ('16E3', 'cyto loc', 1);
    set_symbol ('16E4', 'cyto loc', 1);
    set_symbol ('16E5', 'cyto loc', 1);
    set_symbol ('16F1', 'cyto loc', 1);
    set_symbol ('16F2', 'cyto loc', 1);
    set_symbol ('16F3', 'cyto loc', 1);
    set_symbol ('16F4', 'cyto loc', 1);
    set_symbol ('16F5', 'cyto loc', 1);
    set_symbol ('16F6', 'cyto loc', 1);
    set_symbol ('16F7', 'cyto loc', 1);
    set_symbol ('16F8', 'cyto loc', 1);
    set_symbol ('17A1', 'cyto loc', 1);
    set_symbol ('17A2', 'cyto loc', 1);
    set_symbol ('17A3', 'cyto loc', 1);
    set_symbol ('17A4', 'cyto loc', 1);
    set_symbol ('17A5', 'cyto loc', 1);
    set_symbol ('17A6', 'cyto loc', 1);
    set_symbol ('17A7', 'cyto loc', 1);
    set_symbol ('17A8', 'cyto loc', 1);
    set_symbol ('17A9', 'cyto loc', 1);
    set_symbol ('17A10', 'cyto loc', 1);
    set_symbol ('17A11', 'cyto loc', 1);
    set_symbol ('17A12', 'cyto loc', 1);
    set_symbol ('17B1', 'cyto loc', 1);
    set_symbol ('17B2', 'cyto loc', 1);
    set_symbol ('17B3', 'cyto loc', 1);
    set_symbol ('17B4', 'cyto loc', 1);
    set_symbol ('17B5', 'cyto loc', 1);
    set_symbol ('17B6', 'cyto loc', 1);
    set_symbol ('17C1', 'cyto loc', 1);
    set_symbol ('17C2', 'cyto loc', 1);
    set_symbol ('17C3', 'cyto loc', 1);
    set_symbol ('17C4', 'cyto loc', 1);
    set_symbol ('17C5', 'cyto loc', 1);
    set_symbol ('17C6', 'cyto loc', 1);
    set_symbol ('17C7', 'cyto loc', 1);
    set_symbol ('17D1', 'cyto loc', 1);
    set_symbol ('17D2', 'cyto loc', 1);
    set_symbol ('17D3', 'cyto loc', 1);
    set_symbol ('17D4', 'cyto loc', 1);
    set_symbol ('17D5', 'cyto loc', 1);
    set_symbol ('17D6', 'cyto loc', 1);
    set_symbol ('17E1', 'cyto loc', 1);
    set_symbol ('17E2', 'cyto loc', 1);
    set_symbol ('17E3', 'cyto loc', 1);
    set_symbol ('17E4', 'cyto loc', 1);
    set_symbol ('17E5', 'cyto loc', 1);
    set_symbol ('17E6', 'cyto loc', 1);
    set_symbol ('17E7', 'cyto loc', 1);
    set_symbol ('17E8', 'cyto loc', 1);
    set_symbol ('17E9', 'cyto loc', 1);
    set_symbol ('17F1', 'cyto loc', 1);
    set_symbol ('17F2', 'cyto loc', 1);
    set_symbol ('17F3', 'cyto loc', 1);
    set_symbol ('18A1', 'cyto loc', 1);
    set_symbol ('18A2', 'cyto loc', 1);
    set_symbol ('18A3', 'cyto loc', 1);
    set_symbol ('18A4', 'cyto loc', 1);
    set_symbol ('18A5', 'cyto loc', 1);
    set_symbol ('18A6', 'cyto loc', 1);
    set_symbol ('18A7', 'cyto loc', 1);
    set_symbol ('18B1', 'cyto loc', 1);
    set_symbol ('18B2', 'cyto loc', 1);
    set_symbol ('18B3', 'cyto loc', 1);
    set_symbol ('18B4', 'cyto loc', 1);
    set_symbol ('18B5', 'cyto loc', 1);
    set_symbol ('18B6', 'cyto loc', 1);
    set_symbol ('18B7', 'cyto loc', 1);
    set_symbol ('18B8', 'cyto loc', 1);
    set_symbol ('18B9', 'cyto loc', 1);
    set_symbol ('18B10', 'cyto loc', 1);
    set_symbol ('18B11', 'cyto loc', 1);
    set_symbol ('18C1', 'cyto loc', 1);
    set_symbol ('18C2', 'cyto loc', 1);
    set_symbol ('18C3', 'cyto loc', 1);
    set_symbol ('18C4', 'cyto loc', 1);
    set_symbol ('18C5', 'cyto loc', 1);
    set_symbol ('18C6', 'cyto loc', 1);
    set_symbol ('18C7', 'cyto loc', 1);
    set_symbol ('18C8', 'cyto loc', 1);
    set_symbol ('18C9', 'cyto loc', 1);
    set_symbol ('18D1', 'cyto loc', 1);
    set_symbol ('18D2', 'cyto loc', 1);
    set_symbol ('18D3', 'cyto loc', 1);
    set_symbol ('18D4', 'cyto loc', 1);
    set_symbol ('18D5', 'cyto loc', 1);
    set_symbol ('18D6', 'cyto loc', 1);
    set_symbol ('18D7', 'cyto loc', 1);
    set_symbol ('18D8', 'cyto loc', 1);
    set_symbol ('18D9', 'cyto loc', 1);
    set_symbol ('18D10', 'cyto loc', 1);
    set_symbol ('18D11', 'cyto loc', 1);
    set_symbol ('18D12', 'cyto loc', 1);
    set_symbol ('18D13', 'cyto loc', 1);
    set_symbol ('18E1', 'cyto loc', 1);
    set_symbol ('18E2', 'cyto loc', 1);
    set_symbol ('18E3', 'cyto loc', 1);
    set_symbol ('18E4', 'cyto loc', 1);
    set_symbol ('18E5', 'cyto loc', 1);
    set_symbol ('18F1', 'cyto loc', 1);
    set_symbol ('18F2', 'cyto loc', 1);
    set_symbol ('18F3', 'cyto loc', 1);
    set_symbol ('18F4', 'cyto loc', 1);
    set_symbol ('18F5', 'cyto loc', 1);
    set_symbol ('19A1', 'cyto loc', 1);
    set_symbol ('19A2', 'cyto loc', 1);
    set_symbol ('19A3', 'cyto loc', 1);
    set_symbol ('19A4', 'cyto loc', 1);
    set_symbol ('19A5', 'cyto loc', 1);
    set_symbol ('19A6', 'cyto loc', 1);
    set_symbol ('19B1', 'cyto loc', 1);
    set_symbol ('19B2', 'cyto loc', 1);
    set_symbol ('19B3', 'cyto loc', 1);
    set_symbol ('19C1', 'cyto loc', 1);
    set_symbol ('19C2', 'cyto loc', 1);
    set_symbol ('19C3', 'cyto loc', 1);
    set_symbol ('19C4', 'cyto loc', 1);
    set_symbol ('19C5', 'cyto loc', 1);
    set_symbol ('19C6', 'cyto loc', 1);
    set_symbol ('19D1', 'cyto loc', 1);
    set_symbol ('19D2', 'cyto loc', 1);
    set_symbol ('19D3', 'cyto loc', 1);
    set_symbol ('19E1', 'cyto loc', 1);
    set_symbol ('19E2', 'cyto loc', 1);
    set_symbol ('19E3', 'cyto loc', 1);
    set_symbol ('19E4', 'cyto loc', 1);
    set_symbol ('19E5', 'cyto loc', 1);
    set_symbol ('19E6', 'cyto loc', 1);
    set_symbol ('19E7', 'cyto loc', 1);
    set_symbol ('19E8', 'cyto loc', 1);
    set_symbol ('19F1', 'cyto loc', 1);
    set_symbol ('19F2', 'cyto loc', 1);
    set_symbol ('19F3', 'cyto loc', 1);
    set_symbol ('19F4', 'cyto loc', 1);
    set_symbol ('19F5', 'cyto loc', 1);
    set_symbol ('19F6', 'cyto loc', 1);
    set_symbol ('20A1', 'cyto loc', 1);
    set_symbol ('20A2', 'cyto loc', 1);
    set_symbol ('20A3', 'cyto loc', 1);
    set_symbol ('20A4', 'cyto loc', 1);
    set_symbol ('20A5', 'cyto loc', 1);
    set_symbol ('20B1', 'cyto loc', 1);
    set_symbol ('20B2', 'cyto loc', 1);
    set_symbol ('20B3', 'cyto loc', 1);
    set_symbol ('20C1', 'cyto loc', 1);
    set_symbol ('20C2', 'cyto loc', 1);
    set_symbol ('20C3', 'cyto loc', 1);
    set_symbol ('20D1', 'cyto loc', 1);
    set_symbol ('20D2', 'cyto loc', 1);
    set_symbol ('20E1', 'cyto loc', 1);
    set_symbol ('20E2', 'cyto loc', 1);
    set_symbol ('20F1', 'cyto loc', 1);
    set_symbol ('20F2', 'cyto loc', 1);
    set_symbol ('20F3', 'cyto loc', 1);
    set_symbol ('20F4', 'cyto loc', 1);
    set_symbol ('21A1', 'cyto loc', 1);
    set_symbol ('21A2', 'cyto loc', 1);
    set_symbol ('21A3', 'cyto loc', 1);
    set_symbol ('21A4', 'cyto loc', 1);
    set_symbol ('21A5', 'cyto loc', 1);
    set_symbol ('21B1', 'cyto loc', 1);
    set_symbol ('21B2', 'cyto loc', 1);
    set_symbol ('21B3', 'cyto loc', 1);
    set_symbol ('21B4', 'cyto loc', 1);
    set_symbol ('21B5', 'cyto loc', 1);
    set_symbol ('21B6', 'cyto loc', 1);
    set_symbol ('21B7', 'cyto loc', 1);
    set_symbol ('21B8', 'cyto loc', 1);
    set_symbol ('21C1', 'cyto loc', 1);
    set_symbol ('21C2', 'cyto loc', 1);
    set_symbol ('21C3', 'cyto loc', 1);
    set_symbol ('21C4', 'cyto loc', 1);
    set_symbol ('21C5', 'cyto loc', 1);
    set_symbol ('21C6', 'cyto loc', 1);
    set_symbol ('21C7', 'cyto loc', 1);
    set_symbol ('21C8', 'cyto loc', 1);
    set_symbol ('21D1', 'cyto loc', 1);
    set_symbol ('21D2', 'cyto loc', 1);
    set_symbol ('21D3', 'cyto loc', 1);
    set_symbol ('21D4', 'cyto loc', 1);
    set_symbol ('21E1', 'cyto loc', 1);
    set_symbol ('21E2', 'cyto loc', 1);
    set_symbol ('21E3', 'cyto loc', 1);
    set_symbol ('21E4', 'cyto loc', 1);
    set_symbol ('21F1', 'cyto loc', 1);
    set_symbol ('21F2', 'cyto loc', 1);
    set_symbol ('21F3', 'cyto loc', 1);
    set_symbol ('21F4', 'cyto loc', 1);
    set_symbol ('22A1', 'cyto loc', 1);
    set_symbol ('22A2', 'cyto loc', 1);
    set_symbol ('22A3', 'cyto loc', 1);
    set_symbol ('22A4', 'cyto loc', 1);
    set_symbol ('22A5', 'cyto loc', 1);
    set_symbol ('22A6', 'cyto loc', 1);
    set_symbol ('22A7', 'cyto loc', 1);
    set_symbol ('22A8', 'cyto loc', 1);
    set_symbol ('22B1', 'cyto loc', 1);
    set_symbol ('22B2', 'cyto loc', 1);
    set_symbol ('22B3', 'cyto loc', 1);
    set_symbol ('22B4', 'cyto loc', 1);
    set_symbol ('22B5', 'cyto loc', 1);
    set_symbol ('22B6', 'cyto loc', 1);
    set_symbol ('22B7', 'cyto loc', 1);
    set_symbol ('22B8', 'cyto loc', 1);
    set_symbol ('22B9', 'cyto loc', 1);
    set_symbol ('22C1', 'cyto loc', 1);
    set_symbol ('22C2', 'cyto loc', 1);
    set_symbol ('22C3', 'cyto loc', 1);
    set_symbol ('22D1', 'cyto loc', 1);
    set_symbol ('22D2', 'cyto loc', 1);
    set_symbol ('22D3', 'cyto loc', 1);
    set_symbol ('22D4', 'cyto loc', 1);
    set_symbol ('22D5', 'cyto loc', 1);
    set_symbol ('22D6', 'cyto loc', 1);
    set_symbol ('22E1', 'cyto loc', 1);
    set_symbol ('22E2', 'cyto loc', 1);
    set_symbol ('22E3', 'cyto loc', 1);
    set_symbol ('22E4', 'cyto loc', 1);
    set_symbol ('22F1', 'cyto loc', 1);
    set_symbol ('22F2', 'cyto loc', 1);
    set_symbol ('22F3', 'cyto loc', 1);
    set_symbol ('22F4', 'cyto loc', 1);
    set_symbol ('23A1', 'cyto loc', 1);
    set_symbol ('23A2', 'cyto loc', 1);
    set_symbol ('23A3', 'cyto loc', 1);
    set_symbol ('23A4', 'cyto loc', 1);
    set_symbol ('23A5', 'cyto loc', 1);
    set_symbol ('23A6', 'cyto loc', 1);
    set_symbol ('23A7', 'cyto loc', 1);
    set_symbol ('23B1', 'cyto loc', 1);
    set_symbol ('23B2', 'cyto loc', 1);
    set_symbol ('23B3', 'cyto loc', 1);
    set_symbol ('23B4', 'cyto loc', 1);
    set_symbol ('23B5', 'cyto loc', 1);
    set_symbol ('23B6', 'cyto loc', 1);
    set_symbol ('23B7', 'cyto loc', 1);
    set_symbol ('23B8', 'cyto loc', 1);
    set_symbol ('23C1', 'cyto loc', 1);
    set_symbol ('23C2', 'cyto loc', 1);
    set_symbol ('23C3', 'cyto loc', 1);
    set_symbol ('23C4', 'cyto loc', 1);
    set_symbol ('23C5', 'cyto loc', 1);
    set_symbol ('23D1', 'cyto loc', 1);
    set_symbol ('23D2', 'cyto loc', 1);
    set_symbol ('23D3', 'cyto loc', 1);
    set_symbol ('23D4', 'cyto loc', 1);
    set_symbol ('23D5', 'cyto loc', 1);
    set_symbol ('23D6', 'cyto loc', 1);
    set_symbol ('23E1', 'cyto loc', 1);
    set_symbol ('23E2', 'cyto loc', 1);
    set_symbol ('23E3', 'cyto loc', 1);
    set_symbol ('23E4', 'cyto loc', 1);
    set_symbol ('23E5', 'cyto loc', 1);
    set_symbol ('23E6', 'cyto loc', 1);
    set_symbol ('23F1', 'cyto loc', 1);
    set_symbol ('23F2', 'cyto loc', 1);
    set_symbol ('23F3', 'cyto loc', 1);
    set_symbol ('23F4', 'cyto loc', 1);
    set_symbol ('23F5', 'cyto loc', 1);
    set_symbol ('23F6', 'cyto loc', 1);
    set_symbol ('24A1', 'cyto loc', 1);
    set_symbol ('24A2', 'cyto loc', 1);
    set_symbol ('24A3', 'cyto loc', 1);
    set_symbol ('24A4', 'cyto loc', 1);
    set_symbol ('24A5', 'cyto loc', 1);
    set_symbol ('24B1', 'cyto loc', 1);
    set_symbol ('24B2', 'cyto loc', 1);
    set_symbol ('24B3', 'cyto loc', 1);
    set_symbol ('24C1', 'cyto loc', 1);
    set_symbol ('24C2', 'cyto loc', 1);
    set_symbol ('24C3', 'cyto loc', 1);
    set_symbol ('24C4', 'cyto loc', 1);
    set_symbol ('24C5', 'cyto loc', 1);
    set_symbol ('24C6', 'cyto loc', 1);
    set_symbol ('24C7', 'cyto loc', 1);
    set_symbol ('24C8', 'cyto loc', 1);
    set_symbol ('24C9', 'cyto loc', 1);
    set_symbol ('24D1', 'cyto loc', 1);
    set_symbol ('24D2', 'cyto loc', 1);
    set_symbol ('24D3', 'cyto loc', 1);
    set_symbol ('24D4', 'cyto loc', 1);
    set_symbol ('24D5', 'cyto loc', 1);
    set_symbol ('24D6', 'cyto loc', 1);
    set_symbol ('24D7', 'cyto loc', 1);
    set_symbol ('24D8', 'cyto loc', 1);
    set_symbol ('24E1', 'cyto loc', 1);
    set_symbol ('24E2', 'cyto loc', 1);
    set_symbol ('24E3', 'cyto loc', 1);
    set_symbol ('24E4', 'cyto loc', 1);
    set_symbol ('24E5', 'cyto loc', 1);
    set_symbol ('24F1', 'cyto loc', 1);
    set_symbol ('24F2', 'cyto loc', 1);
    set_symbol ('24F3', 'cyto loc', 1);
    set_symbol ('24F4', 'cyto loc', 1);
    set_symbol ('24F5', 'cyto loc', 1);
    set_symbol ('24F6', 'cyto loc', 1);
    set_symbol ('24F7', 'cyto loc', 1);
    set_symbol ('24F8', 'cyto loc', 1);
    set_symbol ('25A1', 'cyto loc', 1);
    set_symbol ('25A2', 'cyto loc', 1);
    set_symbol ('25A3', 'cyto loc', 1);
    set_symbol ('25A4', 'cyto loc', 1);
    set_symbol ('25A5', 'cyto loc', 1);
    set_symbol ('25A6', 'cyto loc', 1);
    set_symbol ('25A7', 'cyto loc', 1);
    set_symbol ('25A8', 'cyto loc', 1);
    set_symbol ('25B1', 'cyto loc', 1);
    set_symbol ('25B2', 'cyto loc', 1);
    set_symbol ('25B3', 'cyto loc', 1);
    set_symbol ('25B4', 'cyto loc', 1);
    set_symbol ('25B5', 'cyto loc', 1);
    set_symbol ('25B6', 'cyto loc', 1);
    set_symbol ('25B7', 'cyto loc', 1);
    set_symbol ('25B8', 'cyto loc', 1);
    set_symbol ('25B9', 'cyto loc', 1);
    set_symbol ('25B10', 'cyto loc', 1);
    set_symbol ('25C1', 'cyto loc', 1);
    set_symbol ('25C2', 'cyto loc', 1);
    set_symbol ('25C3', 'cyto loc', 1);
    set_symbol ('25C4', 'cyto loc', 1);
    set_symbol ('25C5', 'cyto loc', 1);
    set_symbol ('25C6', 'cyto loc', 1);
    set_symbol ('25C7', 'cyto loc', 1);
    set_symbol ('25C8', 'cyto loc', 1);
    set_symbol ('25C9', 'cyto loc', 1);
    set_symbol ('25C10', 'cyto loc', 1);
    set_symbol ('25D1', 'cyto loc', 1);
    set_symbol ('25D2', 'cyto loc', 1);
    set_symbol ('25D3', 'cyto loc', 1);
    set_symbol ('25D4', 'cyto loc', 1);
    set_symbol ('25D5', 'cyto loc', 1);
    set_symbol ('25D6', 'cyto loc', 1);
    set_symbol ('25D7', 'cyto loc', 1);
    set_symbol ('25E1', 'cyto loc', 1);
    set_symbol ('25E2', 'cyto loc', 1);
    set_symbol ('25E3', 'cyto loc', 1);
    set_symbol ('25E4', 'cyto loc', 1);
    set_symbol ('25E5', 'cyto loc', 1);
    set_symbol ('25E6', 'cyto loc', 1);
    set_symbol ('25F1', 'cyto loc', 1);
    set_symbol ('25F2', 'cyto loc', 1);
    set_symbol ('25F3', 'cyto loc', 1);
    set_symbol ('25F4', 'cyto loc', 1);
    set_symbol ('25F5', 'cyto loc', 1);
    set_symbol ('26A1', 'cyto loc', 1);
    set_symbol ('26A2', 'cyto loc', 1);
    set_symbol ('26A3', 'cyto loc', 1);
    set_symbol ('26A4', 'cyto loc', 1);
    set_symbol ('26A5', 'cyto loc', 1);
    set_symbol ('26A6', 'cyto loc', 1);
    set_symbol ('26A7', 'cyto loc', 1);
    set_symbol ('26A8', 'cyto loc', 1);
    set_symbol ('26A9', 'cyto loc', 1);
    set_symbol ('26B1', 'cyto loc', 1);
    set_symbol ('26B2', 'cyto loc', 1);
    set_symbol ('26B3', 'cyto loc', 1);
    set_symbol ('26B4', 'cyto loc', 1);
    set_symbol ('26B5', 'cyto loc', 1);
    set_symbol ('26B6', 'cyto loc', 1);
    set_symbol ('26B7', 'cyto loc', 1);
    set_symbol ('26B8', 'cyto loc', 1);
    set_symbol ('26B9', 'cyto loc', 1);
    set_symbol ('26B10', 'cyto loc', 1);
    set_symbol ('26B11', 'cyto loc', 1);
    set_symbol ('26C1', 'cyto loc', 1);
    set_symbol ('26C2', 'cyto loc', 1);
    set_symbol ('26C3', 'cyto loc', 1);
    set_symbol ('26C4', 'cyto loc', 1);
    set_symbol ('26D1', 'cyto loc', 1);
    set_symbol ('26D2', 'cyto loc', 1);
    set_symbol ('26D3', 'cyto loc', 1);
    set_symbol ('26D4', 'cyto loc', 1);
    set_symbol ('26D5', 'cyto loc', 1);
    set_symbol ('26D6', 'cyto loc', 1);
    set_symbol ('26D7', 'cyto loc', 1);
    set_symbol ('26D8', 'cyto loc', 1);
    set_symbol ('26D9', 'cyto loc', 1);
    set_symbol ('26D10', 'cyto loc', 1);
    set_symbol ('26D11', 'cyto loc', 1);
    set_symbol ('26E1', 'cyto loc', 1);
    set_symbol ('26E2', 'cyto loc', 1);
    set_symbol ('26E3', 'cyto loc', 1);
    set_symbol ('26E4', 'cyto loc', 1);
    set_symbol ('26F1', 'cyto loc', 1);
    set_symbol ('26F2', 'cyto loc', 1);
    set_symbol ('26F3', 'cyto loc', 1);
    set_symbol ('26F4', 'cyto loc', 1);
    set_symbol ('26F5', 'cyto loc', 1);
    set_symbol ('26F6', 'cyto loc', 1);
    set_symbol ('26F7', 'cyto loc', 1);
    set_symbol ('27A1', 'cyto loc', 1);
    set_symbol ('27A2', 'cyto loc', 1);
    set_symbol ('27B1', 'cyto loc', 1);
    set_symbol ('27B2', 'cyto loc', 1);
    set_symbol ('27B3', 'cyto loc', 1);
    set_symbol ('27B4', 'cyto loc', 1);
    set_symbol ('27C1', 'cyto loc', 1);
    set_symbol ('27C2', 'cyto loc', 1);
    set_symbol ('27C3', 'cyto loc', 1);
    set_symbol ('27C4', 'cyto loc', 1);
    set_symbol ('27C5', 'cyto loc', 1);
    set_symbol ('27C6', 'cyto loc', 1);
    set_symbol ('27C7', 'cyto loc', 1);
    set_symbol ('27C8', 'cyto loc', 1);
    set_symbol ('27C9', 'cyto loc', 1);
    set_symbol ('27D1', 'cyto loc', 1);
    set_symbol ('27D2', 'cyto loc', 1);
    set_symbol ('27D3', 'cyto loc', 1);
    set_symbol ('27D4', 'cyto loc', 1);
    set_symbol ('27D5', 'cyto loc', 1);
    set_symbol ('27D6', 'cyto loc', 1);
    set_symbol ('27D7', 'cyto loc', 1);
    set_symbol ('27E1', 'cyto loc', 1);
    set_symbol ('27E2', 'cyto loc', 1);
    set_symbol ('27E3', 'cyto loc', 1);
    set_symbol ('27E4', 'cyto loc', 1);
    set_symbol ('27E5', 'cyto loc', 1);
    set_symbol ('27E6', 'cyto loc', 1);
    set_symbol ('27E7', 'cyto loc', 1);
    set_symbol ('27E8', 'cyto loc', 1);
    set_symbol ('27F1', 'cyto loc', 1);
    set_symbol ('27F2', 'cyto loc', 1);
    set_symbol ('27F3', 'cyto loc', 1);
    set_symbol ('27F4', 'cyto loc', 1);
    set_symbol ('27F5', 'cyto loc', 1);
    set_symbol ('27F6', 'cyto loc', 1);
    set_symbol ('27F7', 'cyto loc', 1);
    set_symbol ('28A1', 'cyto loc', 1);
    set_symbol ('28A2', 'cyto loc', 1);
    set_symbol ('28A3', 'cyto loc', 1);
    set_symbol ('28A4', 'cyto loc', 1);
    set_symbol ('28A5', 'cyto loc', 1);
    set_symbol ('28A6', 'cyto loc', 1);
    set_symbol ('28B1', 'cyto loc', 1);
    set_symbol ('28B2', 'cyto loc', 1);
    set_symbol ('28B3', 'cyto loc', 1);
    set_symbol ('28B4', 'cyto loc', 1);
    set_symbol ('28C1', 'cyto loc', 1);
    set_symbol ('28C2', 'cyto loc', 1);
    set_symbol ('28C3', 'cyto loc', 1);
    set_symbol ('28C4', 'cyto loc', 1);
    set_symbol ('28C5', 'cyto loc', 1);
    set_symbol ('28C6', 'cyto loc', 1);
    set_symbol ('28C7', 'cyto loc', 1);
    set_symbol ('28C8', 'cyto loc', 1);
    set_symbol ('28C9', 'cyto loc', 1);
    set_symbol ('28D1', 'cyto loc', 1);
    set_symbol ('28D2', 'cyto loc', 1);
    set_symbol ('28D3', 'cyto loc', 1);
    set_symbol ('28D4', 'cyto loc', 1);
    set_symbol ('28D5', 'cyto loc', 1);
    set_symbol ('28D6', 'cyto loc', 1);
    set_symbol ('28D7', 'cyto loc', 1);
    set_symbol ('28D8', 'cyto loc', 1);
    set_symbol ('28D9', 'cyto loc', 1);
    set_symbol ('28D10', 'cyto loc', 1);
    set_symbol ('28D11', 'cyto loc', 1);
    set_symbol ('28D12', 'cyto loc', 1);
    set_symbol ('28E1', 'cyto loc', 1);
    set_symbol ('28E2', 'cyto loc', 1);
    set_symbol ('28E3', 'cyto loc', 1);
    set_symbol ('28E4', 'cyto loc', 1);
    set_symbol ('28E5', 'cyto loc', 1);
    set_symbol ('28E6', 'cyto loc', 1);
    set_symbol ('28E7', 'cyto loc', 1);
    set_symbol ('28E8', 'cyto loc', 1);
    set_symbol ('28E9', 'cyto loc', 1);
    set_symbol ('28F1', 'cyto loc', 1);
    set_symbol ('28F2', 'cyto loc', 1);
    set_symbol ('28F3', 'cyto loc', 1);
    set_symbol ('28F4', 'cyto loc', 1);
    set_symbol ('28F5', 'cyto loc', 1);
    set_symbol ('29A1', 'cyto loc', 1);
    set_symbol ('29A2', 'cyto loc', 1);
    set_symbol ('29A3', 'cyto loc', 1);
    set_symbol ('29A4', 'cyto loc', 1);
    set_symbol ('29A5', 'cyto loc', 1);
    set_symbol ('29B1', 'cyto loc', 1);
    set_symbol ('29B2', 'cyto loc', 1);
    set_symbol ('29B3', 'cyto loc', 1);
    set_symbol ('29B4', 'cyto loc', 1);
    set_symbol ('29C1', 'cyto loc', 1);
    set_symbol ('29C2', 'cyto loc', 1);
    set_symbol ('29C3', 'cyto loc', 1);
    set_symbol ('29C4', 'cyto loc', 1);
    set_symbol ('29C5', 'cyto loc', 1);
    set_symbol ('29D1', 'cyto loc', 1);
    set_symbol ('29D2', 'cyto loc', 1);
    set_symbol ('29D3', 'cyto loc', 1);
    set_symbol ('29D4', 'cyto loc', 1);
    set_symbol ('29D5', 'cyto loc', 1);
    set_symbol ('29D6', 'cyto loc', 1);
    set_symbol ('29D7', 'cyto loc', 1);
    set_symbol ('29E1', 'cyto loc', 1);
    set_symbol ('29E2', 'cyto loc', 1);
    set_symbol ('29E3', 'cyto loc', 1);
    set_symbol ('29E4', 'cyto loc', 1);
    set_symbol ('29E5', 'cyto loc', 1);
    set_symbol ('29E6', 'cyto loc', 1);
    set_symbol ('29F1', 'cyto loc', 1);
    set_symbol ('29F2', 'cyto loc', 1);
    set_symbol ('29F3', 'cyto loc', 1);
    set_symbol ('29F4', 'cyto loc', 1);
    set_symbol ('29F5', 'cyto loc', 1);
    set_symbol ('29F6', 'cyto loc', 1);
    set_symbol ('29F7', 'cyto loc', 1);
    set_symbol ('29F8', 'cyto loc', 1);
    set_symbol ('30A1', 'cyto loc', 1);
    set_symbol ('30A2', 'cyto loc', 1);
    set_symbol ('30A3', 'cyto loc', 1);
    set_symbol ('30A4', 'cyto loc', 1);
    set_symbol ('30A5', 'cyto loc', 1);
    set_symbol ('30A6', 'cyto loc', 1);
    set_symbol ('30A7', 'cyto loc', 1);
    set_symbol ('30A8', 'cyto loc', 1);
    set_symbol ('30A9', 'cyto loc', 1);
    set_symbol ('30B1', 'cyto loc', 1);
    set_symbol ('30B2', 'cyto loc', 1);
    set_symbol ('30B3', 'cyto loc', 1);
    set_symbol ('30B4', 'cyto loc', 1);
    set_symbol ('30B5', 'cyto loc', 1);
    set_symbol ('30B6', 'cyto loc', 1);
    set_symbol ('30B7', 'cyto loc', 1);
    set_symbol ('30B8', 'cyto loc', 1);
    set_symbol ('30B9', 'cyto loc', 1);
    set_symbol ('30B10', 'cyto loc', 1);
    set_symbol ('30B11', 'cyto loc', 1);
    set_symbol ('30B12', 'cyto loc', 1);
    set_symbol ('30C1', 'cyto loc', 1);
    set_symbol ('30C2', 'cyto loc', 1);
    set_symbol ('30C3', 'cyto loc', 1);
    set_symbol ('30C4', 'cyto loc', 1);
    set_symbol ('30C5', 'cyto loc', 1);
    set_symbol ('30C6', 'cyto loc', 1);
    set_symbol ('30C7', 'cyto loc', 1);
    set_symbol ('30C8', 'cyto loc', 1);
    set_symbol ('30C9', 'cyto loc', 1);
    set_symbol ('30D1', 'cyto loc', 1);
    set_symbol ('30D2', 'cyto loc', 1);
    set_symbol ('30D3', 'cyto loc', 1);
    set_symbol ('30D4', 'cyto loc', 1);
    set_symbol ('30E1', 'cyto loc', 1);
    set_symbol ('30E2', 'cyto loc', 1);
    set_symbol ('30E3', 'cyto loc', 1);
    set_symbol ('30E4', 'cyto loc', 1);
    set_symbol ('30F1', 'cyto loc', 1);
    set_symbol ('30F2', 'cyto loc', 1);
    set_symbol ('30F3', 'cyto loc', 1);
    set_symbol ('30F4', 'cyto loc', 1);
    set_symbol ('30F5', 'cyto loc', 1);
    set_symbol ('30F6', 'cyto loc', 1);
    set_symbol ('31A1', 'cyto loc', 1);
    set_symbol ('31A2', 'cyto loc', 1);
    set_symbol ('31A3', 'cyto loc', 1);
    set_symbol ('31B1', 'cyto loc', 1);
    set_symbol ('31B2', 'cyto loc', 1);
    set_symbol ('31B3', 'cyto loc', 1);
    set_symbol ('31B4', 'cyto loc', 1);
    set_symbol ('31B5', 'cyto loc', 1);
    set_symbol ('31C1', 'cyto loc', 1);
    set_symbol ('31C2', 'cyto loc', 1);
    set_symbol ('31C3', 'cyto loc', 1);
    set_symbol ('31C4', 'cyto loc', 1);
    set_symbol ('31C5', 'cyto loc', 1);
    set_symbol ('31C6', 'cyto loc', 1);
    set_symbol ('31C7', 'cyto loc', 1);
    set_symbol ('31D1', 'cyto loc', 1);
    set_symbol ('31D2', 'cyto loc', 1);
    set_symbol ('31D3', 'cyto loc', 1);
    set_symbol ('31D4', 'cyto loc', 1);
    set_symbol ('31D5', 'cyto loc', 1);
    set_symbol ('31D6', 'cyto loc', 1);
    set_symbol ('31D7', 'cyto loc', 1);
    set_symbol ('31D8', 'cyto loc', 1);
    set_symbol ('31D9', 'cyto loc', 1);
    set_symbol ('31D10', 'cyto loc', 1);
    set_symbol ('31D11', 'cyto loc', 1);
    set_symbol ('31E1', 'cyto loc', 1);
    set_symbol ('31E2', 'cyto loc', 1);
    set_symbol ('31E3', 'cyto loc', 1);
    set_symbol ('31E4', 'cyto loc', 1);
    set_symbol ('31E5', 'cyto loc', 1);
    set_symbol ('31E6', 'cyto loc', 1);
    set_symbol ('31E7', 'cyto loc', 1);
    set_symbol ('31F1', 'cyto loc', 1);
    set_symbol ('31F2', 'cyto loc', 1);
    set_symbol ('31F3', 'cyto loc', 1);
    set_symbol ('31F4', 'cyto loc', 1);
    set_symbol ('31F5', 'cyto loc', 1);
    set_symbol ('32A1', 'cyto loc', 1);
    set_symbol ('32A2', 'cyto loc', 1);
    set_symbol ('32A3', 'cyto loc', 1);
    set_symbol ('32A4', 'cyto loc', 1);
    set_symbol ('32A5', 'cyto loc', 1);
    set_symbol ('32B1', 'cyto loc', 1);
    set_symbol ('32B2', 'cyto loc', 1);
    set_symbol ('32B3', 'cyto loc', 1);
    set_symbol ('32B4', 'cyto loc', 1);
    set_symbol ('32C1', 'cyto loc', 1);
    set_symbol ('32C2', 'cyto loc', 1);
    set_symbol ('32C3', 'cyto loc', 1);
    set_symbol ('32C4', 'cyto loc', 1);
    set_symbol ('32C5', 'cyto loc', 1);
    set_symbol ('32D1', 'cyto loc', 1);
    set_symbol ('32D2', 'cyto loc', 1);
    set_symbol ('32D3', 'cyto loc', 1);
    set_symbol ('32D4', 'cyto loc', 1);
    set_symbol ('32D5', 'cyto loc', 1);
    set_symbol ('32E1', 'cyto loc', 1);
    set_symbol ('32E2', 'cyto loc', 1);
    set_symbol ('32E3', 'cyto loc', 1);
    set_symbol ('32E4', 'cyto loc', 1);
    set_symbol ('32E5', 'cyto loc', 1);
    set_symbol ('32F1', 'cyto loc', 1);
    set_symbol ('32F2', 'cyto loc', 1);
    set_symbol ('32F3', 'cyto loc', 1);
    set_symbol ('32F4', 'cyto loc', 1);
    set_symbol ('33A1', 'cyto loc', 1);
    set_symbol ('33A2', 'cyto loc', 1);
    set_symbol ('33A3', 'cyto loc', 1);
    set_symbol ('33A4', 'cyto loc', 1);
    set_symbol ('33A5', 'cyto loc', 1);
    set_symbol ('33A6', 'cyto loc', 1);
    set_symbol ('33A7', 'cyto loc', 1);
    set_symbol ('33A8', 'cyto loc', 1);
    set_symbol ('33B1', 'cyto loc', 1);
    set_symbol ('33B2', 'cyto loc', 1);
    set_symbol ('33B3', 'cyto loc', 1);
    set_symbol ('33B4', 'cyto loc', 1);
    set_symbol ('33B5', 'cyto loc', 1);
    set_symbol ('33B6', 'cyto loc', 1);
    set_symbol ('33B7', 'cyto loc', 1);
    set_symbol ('33B8', 'cyto loc', 1);
    set_symbol ('33B9', 'cyto loc', 1);
    set_symbol ('33B10', 'cyto loc', 1);
    set_symbol ('33B11', 'cyto loc', 1);
    set_symbol ('33B12', 'cyto loc', 1);
    set_symbol ('33B13', 'cyto loc', 1);
    set_symbol ('33B14', 'cyto loc', 1);
    set_symbol ('33C1', 'cyto loc', 1);
    set_symbol ('33C2', 'cyto loc', 1);
    set_symbol ('33C3', 'cyto loc', 1);
    set_symbol ('33C4', 'cyto loc', 1);
    set_symbol ('33C5', 'cyto loc', 1);
    set_symbol ('33C6', 'cyto loc', 1);
    set_symbol ('33D1', 'cyto loc', 1);
    set_symbol ('33D2', 'cyto loc', 1);
    set_symbol ('33D3', 'cyto loc', 1);
    set_symbol ('33D4', 'cyto loc', 1);
    set_symbol ('33D5', 'cyto loc', 1);
    set_symbol ('33E1', 'cyto loc', 1);
    set_symbol ('33E2', 'cyto loc', 1);
    set_symbol ('33E3', 'cyto loc', 1);
    set_symbol ('33E4', 'cyto loc', 1);
    set_symbol ('33E5', 'cyto loc', 1);
    set_symbol ('33E6', 'cyto loc', 1);
    set_symbol ('33E7', 'cyto loc', 1);
    set_symbol ('33E8', 'cyto loc', 1);
    set_symbol ('33E9', 'cyto loc', 1);
    set_symbol ('33E10', 'cyto loc', 1);
    set_symbol ('33F1', 'cyto loc', 1);
    set_symbol ('33F2', 'cyto loc', 1);
    set_symbol ('33F3', 'cyto loc', 1);
    set_symbol ('33F4', 'cyto loc', 1);
    set_symbol ('33F5', 'cyto loc', 1);
    set_symbol ('34A1', 'cyto loc', 1);
    set_symbol ('34A2', 'cyto loc', 1);
    set_symbol ('34A3', 'cyto loc', 1);
    set_symbol ('34A4', 'cyto loc', 1);
    set_symbol ('34A5', 'cyto loc', 1);
    set_symbol ('34A6', 'cyto loc', 1);
    set_symbol ('34A7', 'cyto loc', 1);
    set_symbol ('34A8', 'cyto loc', 1);
    set_symbol ('34A9', 'cyto loc', 1);
    set_symbol ('34A10', 'cyto loc', 1);
    set_symbol ('34A11', 'cyto loc', 1);
    set_symbol ('34B1', 'cyto loc', 1);
    set_symbol ('34B2', 'cyto loc', 1);
    set_symbol ('34B3', 'cyto loc', 1);
    set_symbol ('34B4', 'cyto loc', 1);
    set_symbol ('34B5', 'cyto loc', 1);
    set_symbol ('34B6', 'cyto loc', 1);
    set_symbol ('34B7', 'cyto loc', 1);
    set_symbol ('34B8', 'cyto loc', 1);
    set_symbol ('34B9', 'cyto loc', 1);
    set_symbol ('34B10', 'cyto loc', 1);
    set_symbol ('34B11', 'cyto loc', 1);
    set_symbol ('34B12', 'cyto loc', 1);
    set_symbol ('34C1', 'cyto loc', 1);
    set_symbol ('34C2', 'cyto loc', 1);
    set_symbol ('34C3', 'cyto loc', 1);
    set_symbol ('34C4', 'cyto loc', 1);
    set_symbol ('34C5', 'cyto loc', 1);
    set_symbol ('34C6', 'cyto loc', 1);
    set_symbol ('34C7', 'cyto loc', 1);
    set_symbol ('34D1', 'cyto loc', 1);
    set_symbol ('34D2', 'cyto loc', 1);
    set_symbol ('34D3', 'cyto loc', 1);
    set_symbol ('34D4', 'cyto loc', 1);
    set_symbol ('34D5', 'cyto loc', 1);
    set_symbol ('34D6', 'cyto loc', 1);
    set_symbol ('34D7', 'cyto loc', 1);
    set_symbol ('34D8', 'cyto loc', 1);
    set_symbol ('34E1', 'cyto loc', 1);
    set_symbol ('34E2', 'cyto loc', 1);
    set_symbol ('34E3', 'cyto loc', 1);
    set_symbol ('34E4', 'cyto loc', 1);
    set_symbol ('34E5', 'cyto loc', 1);
    set_symbol ('34E6', 'cyto loc', 1);
    set_symbol ('34F1', 'cyto loc', 1);
    set_symbol ('34F2', 'cyto loc', 1);
    set_symbol ('34F3', 'cyto loc', 1);
    set_symbol ('34F4', 'cyto loc', 1);
    set_symbol ('34F5', 'cyto loc', 1);
    set_symbol ('35A1', 'cyto loc', 1);
    set_symbol ('35A2', 'cyto loc', 1);
    set_symbol ('35A3', 'cyto loc', 1);
    set_symbol ('35A4', 'cyto loc', 1);
    set_symbol ('35B1', 'cyto loc', 1);
    set_symbol ('35B2', 'cyto loc', 1);
    set_symbol ('35B3', 'cyto loc', 1);
    set_symbol ('35B4', 'cyto loc', 1);
    set_symbol ('35B5', 'cyto loc', 1);
    set_symbol ('35B6', 'cyto loc', 1);
    set_symbol ('35B7', 'cyto loc', 1);
    set_symbol ('35B8', 'cyto loc', 1);
    set_symbol ('35B9', 'cyto loc', 1);
    set_symbol ('35B10', 'cyto loc', 1);
    set_symbol ('35C1', 'cyto loc', 1);
    set_symbol ('35C2', 'cyto loc', 1);
    set_symbol ('35C3', 'cyto loc', 1);
    set_symbol ('35C4', 'cyto loc', 1);
    set_symbol ('35C5', 'cyto loc', 1);
    set_symbol ('35D1', 'cyto loc', 1);
    set_symbol ('35D2', 'cyto loc', 1);
    set_symbol ('35D3', 'cyto loc', 1);
    set_symbol ('35D4', 'cyto loc', 1);
    set_symbol ('35D5', 'cyto loc', 1);
    set_symbol ('35D6', 'cyto loc', 1);
    set_symbol ('35D7', 'cyto loc', 1);
    set_symbol ('35E1', 'cyto loc', 1);
    set_symbol ('35E2', 'cyto loc', 1);
    set_symbol ('35E3', 'cyto loc', 1);
    set_symbol ('35E4', 'cyto loc', 1);
    set_symbol ('35E5', 'cyto loc', 1);
    set_symbol ('35E6', 'cyto loc', 1);
    set_symbol ('35F1', 'cyto loc', 1);
    set_symbol ('35F2', 'cyto loc', 1);
    set_symbol ('35F3', 'cyto loc', 1);
    set_symbol ('35F4', 'cyto loc', 1);
    set_symbol ('35F5', 'cyto loc', 1);
    set_symbol ('35F6', 'cyto loc', 1);
    set_symbol ('35F7', 'cyto loc', 1);
    set_symbol ('35F8', 'cyto loc', 1);
    set_symbol ('35F9', 'cyto loc', 1);
    set_symbol ('35F10', 'cyto loc', 1);
    set_symbol ('35F11', 'cyto loc', 1);
    set_symbol ('35F12', 'cyto loc', 1);
    set_symbol ('36A1', 'cyto loc', 1);
    set_symbol ('36A2', 'cyto loc', 1);
    set_symbol ('36A3', 'cyto loc', 1);
    set_symbol ('36A4', 'cyto loc', 1);
    set_symbol ('36A5', 'cyto loc', 1);
    set_symbol ('36A6', 'cyto loc', 1);
    set_symbol ('36A7', 'cyto loc', 1);
    set_symbol ('36A8', 'cyto loc', 1);
    set_symbol ('36A9', 'cyto loc', 1);
    set_symbol ('36A10', 'cyto loc', 1);
    set_symbol ('36A11', 'cyto loc', 1);
    set_symbol ('36A12', 'cyto loc', 1);
    set_symbol ('36A13', 'cyto loc', 1);
    set_symbol ('36A14', 'cyto loc', 1);
    set_symbol ('36B1', 'cyto loc', 1);
    set_symbol ('36B2', 'cyto loc', 1);
    set_symbol ('36B3', 'cyto loc', 1);
    set_symbol ('36B4', 'cyto loc', 1);
    set_symbol ('36B5', 'cyto loc', 1);
    set_symbol ('36B6', 'cyto loc', 1);
    set_symbol ('36B7', 'cyto loc', 1);
    set_symbol ('36B8', 'cyto loc', 1);
    set_symbol ('36C1', 'cyto loc', 1);
    set_symbol ('36C2', 'cyto loc', 1);
    set_symbol ('36C3', 'cyto loc', 1);
    set_symbol ('36C4', 'cyto loc', 1);
    set_symbol ('36C5', 'cyto loc', 1);
    set_symbol ('36C6', 'cyto loc', 1);
    set_symbol ('36C7', 'cyto loc', 1);
    set_symbol ('36C8', 'cyto loc', 1);
    set_symbol ('36C9', 'cyto loc', 1);
    set_symbol ('36C10', 'cyto loc', 1);
    set_symbol ('36C11', 'cyto loc', 1);
    set_symbol ('36D1', 'cyto loc', 1);
    set_symbol ('36D2', 'cyto loc', 1);
    set_symbol ('36D3', 'cyto loc', 1);
    set_symbol ('36E1', 'cyto loc', 1);
    set_symbol ('36E2', 'cyto loc', 1);
    set_symbol ('36E3', 'cyto loc', 1);
    set_symbol ('36E4', 'cyto loc', 1);
    set_symbol ('36E5', 'cyto loc', 1);
    set_symbol ('36E6', 'cyto loc', 1);
    set_symbol ('36F1', 'cyto loc', 1);
    set_symbol ('36F2', 'cyto loc', 1);
    set_symbol ('36F3', 'cyto loc', 1);
    set_symbol ('36F4', 'cyto loc', 1);
    set_symbol ('36F5', 'cyto loc', 1);
    set_symbol ('36F6', 'cyto loc', 1);
    set_symbol ('36F7', 'cyto loc', 1);
    set_symbol ('36F8', 'cyto loc', 1);
    set_symbol ('36F9', 'cyto loc', 1);
    set_symbol ('36F10', 'cyto loc', 1);
    set_symbol ('36F11', 'cyto loc', 1);
    set_symbol ('37A1', 'cyto loc', 1);
    set_symbol ('37A2', 'cyto loc', 1);
    set_symbol ('37A3', 'cyto loc', 1);
    set_symbol ('37A4', 'cyto loc', 1);
    set_symbol ('37A5', 'cyto loc', 1);
    set_symbol ('37A6', 'cyto loc', 1);
    set_symbol ('37B1', 'cyto loc', 1);
    set_symbol ('37B2', 'cyto loc', 1);
    set_symbol ('37B3', 'cyto loc', 1);
    set_symbol ('37B4', 'cyto loc', 1);
    set_symbol ('37B5', 'cyto loc', 1);
    set_symbol ('37B6', 'cyto loc', 1);
    set_symbol ('37B7', 'cyto loc', 1);
    set_symbol ('37B8', 'cyto loc', 1);
    set_symbol ('37B9', 'cyto loc', 1);
    set_symbol ('37B10', 'cyto loc', 1);
    set_symbol ('37B11', 'cyto loc', 1);
    set_symbol ('37B12', 'cyto loc', 1);
    set_symbol ('37B13', 'cyto loc', 1);
    set_symbol ('37C1', 'cyto loc', 1);
    set_symbol ('37C2', 'cyto loc', 1);
    set_symbol ('37C3', 'cyto loc', 1);
    set_symbol ('37C4', 'cyto loc', 1);
    set_symbol ('37C5', 'cyto loc', 1);
    set_symbol ('37C6', 'cyto loc', 1);
    set_symbol ('37C7', 'cyto loc', 1);
    set_symbol ('37D1', 'cyto loc', 1);
    set_symbol ('37D2', 'cyto loc', 1);
    set_symbol ('37D3', 'cyto loc', 1);
    set_symbol ('37D4', 'cyto loc', 1);
    set_symbol ('37D5', 'cyto loc', 1);
    set_symbol ('37D6', 'cyto loc', 1);
    set_symbol ('37D7', 'cyto loc', 1);
    set_symbol ('37E1', 'cyto loc', 1);
    set_symbol ('37E2', 'cyto loc', 1);
    set_symbol ('37E3', 'cyto loc', 1);
    set_symbol ('37E4', 'cyto loc', 1);
    set_symbol ('37E5', 'cyto loc', 1);
    set_symbol ('37F1', 'cyto loc', 1);
    set_symbol ('37F2', 'cyto loc', 1);
    set_symbol ('37F3', 'cyto loc', 1);
    set_symbol ('37F4', 'cyto loc', 1);
    set_symbol ('37F5', 'cyto loc', 1);
    set_symbol ('37F6', 'cyto loc', 1);
    set_symbol ('38A1', 'cyto loc', 1);
    set_symbol ('38A2', 'cyto loc', 1);
    set_symbol ('38A3', 'cyto loc', 1);
    set_symbol ('38A4', 'cyto loc', 1);
    set_symbol ('38A5', 'cyto loc', 1);
    set_symbol ('38A6', 'cyto loc', 1);
    set_symbol ('38A7', 'cyto loc', 1);
    set_symbol ('38A8', 'cyto loc', 1);
    set_symbol ('38B1', 'cyto loc', 1);
    set_symbol ('38B2', 'cyto loc', 1);
    set_symbol ('38B3', 'cyto loc', 1);
    set_symbol ('38B4', 'cyto loc', 1);
    set_symbol ('38B5', 'cyto loc', 1);
    set_symbol ('38B6', 'cyto loc', 1);
    set_symbol ('38C1', 'cyto loc', 1);
    set_symbol ('38C2', 'cyto loc', 1);
    set_symbol ('38C3', 'cyto loc', 1);
    set_symbol ('38C4', 'cyto loc', 1);
    set_symbol ('38C5', 'cyto loc', 1);
    set_symbol ('38C6', 'cyto loc', 1);
    set_symbol ('38C7', 'cyto loc', 1);
    set_symbol ('38C8', 'cyto loc', 1);
    set_symbol ('38C9', 'cyto loc', 1);
    set_symbol ('38C10', 'cyto loc', 1);
    set_symbol ('38D1', 'cyto loc', 1);
    set_symbol ('38D2', 'cyto loc', 1);
    set_symbol ('38D3', 'cyto loc', 1);
    set_symbol ('38D4', 'cyto loc', 1);
    set_symbol ('38D5', 'cyto loc', 1);
    set_symbol ('38E1', 'cyto loc', 1);
    set_symbol ('38E2', 'cyto loc', 1);
    set_symbol ('38E3', 'cyto loc', 1);
    set_symbol ('38E4', 'cyto loc', 1);
    set_symbol ('38E5', 'cyto loc', 1);
    set_symbol ('38E6', 'cyto loc', 1);
    set_symbol ('38E7', 'cyto loc', 1);
    set_symbol ('38E8', 'cyto loc', 1);
    set_symbol ('38E9', 'cyto loc', 1);
    set_symbol ('38E10', 'cyto loc', 1);
    set_symbol ('38F1', 'cyto loc', 1);
    set_symbol ('38F2', 'cyto loc', 1);
    set_symbol ('38F3', 'cyto loc', 1);
    set_symbol ('38F4', 'cyto loc', 1);
    set_symbol ('38F5', 'cyto loc', 1);
    set_symbol ('38F6', 'cyto loc', 1);
    set_symbol ('39A1', 'cyto loc', 1);
    set_symbol ('39A2', 'cyto loc', 1);
    set_symbol ('39A3', 'cyto loc', 1);
    set_symbol ('39A4', 'cyto loc', 1);
    set_symbol ('39A5', 'cyto loc', 1);
    set_symbol ('39A6', 'cyto loc', 1);
    set_symbol ('39A7', 'cyto loc', 1);
    set_symbol ('39B1', 'cyto loc', 1);
    set_symbol ('39B2', 'cyto loc', 1);
    set_symbol ('39B3', 'cyto loc', 1);
    set_symbol ('39B4', 'cyto loc', 1);
    set_symbol ('39C1', 'cyto loc', 1);
    set_symbol ('39C2', 'cyto loc', 1);
    set_symbol ('39C3', 'cyto loc', 1);
    set_symbol ('39C4', 'cyto loc', 1);
    set_symbol ('39D1', 'cyto loc', 1);
    set_symbol ('39D2', 'cyto loc', 1);
    set_symbol ('39D3', 'cyto loc', 1);
    set_symbol ('39D4', 'cyto loc', 1);
    set_symbol ('39D5', 'cyto loc', 1);
    set_symbol ('39E1', 'cyto loc', 1);
    set_symbol ('39E2', 'cyto loc', 1);
    set_symbol ('39E3', 'cyto loc', 1);
    set_symbol ('39E4', 'cyto loc', 1);
    set_symbol ('39E5', 'cyto loc', 1);
    set_symbol ('39E6', 'cyto loc', 1);
    set_symbol ('39E7', 'cyto loc', 1);
    set_symbol ('39F1', 'cyto loc', 1);
    set_symbol ('39F2', 'cyto loc', 1);
    set_symbol ('39F3', 'cyto loc', 1);
    set_symbol ('40A1', 'cyto loc', 1);
    set_symbol ('40A2', 'cyto loc', 1);
    set_symbol ('40A3', 'cyto loc', 1);
    set_symbol ('40A4', 'cyto loc', 1);
    set_symbol ('40A5', 'cyto loc', 1);
    set_symbol ('40A6', 'cyto loc', 1);
    set_symbol ('40B1', 'cyto loc', 1);
    set_symbol ('40B2', 'cyto loc', 1);
    set_symbol ('40B3', 'cyto loc', 1);
    set_symbol ('40B4', 'cyto loc', 1);
    set_symbol ('40B5', 'cyto loc', 1);
    set_symbol ('40C1', 'cyto loc', 1);
    set_symbol ('40C2', 'cyto loc', 1);
    set_symbol ('40C3', 'cyto loc', 1);
    set_symbol ('40D1', 'cyto loc', 1);
    set_symbol ('40D2', 'cyto loc', 1);
    set_symbol ('40D3', 'cyto loc', 1);
    set_symbol ('40D4', 'cyto loc', 1);
    set_symbol ('40D5', 'cyto loc', 1);
    set_symbol ('40E1', 'cyto loc', 1);
    set_symbol ('40E2', 'cyto loc', 1);
    set_symbol ('40E3', 'cyto loc', 1);
    set_symbol ('40E4', 'cyto loc', 1);
    set_symbol ('40E5', 'cyto loc', 1);
    set_symbol ('40F1', 'cyto loc', 1);
    set_symbol ('40F2', 'cyto loc', 1);
    set_symbol ('40F3', 'cyto loc', 1);
    set_symbol ('40F4', 'cyto loc', 1);
    set_symbol ('40F5', 'cyto loc', 1);
    set_symbol ('40F6', 'cyto loc', 1);
    set_symbol ('40F7', 'cyto loc', 1);
    set_symbol ('41A1', 'cyto loc', 1);
    set_symbol ('41A2', 'cyto loc', 1);
    set_symbol ('41A3', 'cyto loc', 1);
    set_symbol ('41B1', 'cyto loc', 1);
    set_symbol ('41B2', 'cyto loc', 1);
    set_symbol ('41B3', 'cyto loc', 1);
    set_symbol ('41C1', 'cyto loc', 1);
    set_symbol ('41C2', 'cyto loc', 1);
    set_symbol ('41C3', 'cyto loc', 1);
    set_symbol ('41C4', 'cyto loc', 1);
    set_symbol ('41C5', 'cyto loc', 1);
    set_symbol ('41C6', 'cyto loc', 1);
    set_symbol ('41C7', 'cyto loc', 1);
    set_symbol ('41D1', 'cyto loc', 1);
    set_symbol ('41D2', 'cyto loc', 1);
    set_symbol ('41D3', 'cyto loc', 1);
    set_symbol ('41D4', 'cyto loc', 1);
    set_symbol ('41E1', 'cyto loc', 1);
    set_symbol ('41E2', 'cyto loc', 1);
    set_symbol ('41E3', 'cyto loc', 1);
    set_symbol ('41E4', 'cyto loc', 1);
    set_symbol ('41E5', 'cyto loc', 1);
    set_symbol ('41E6', 'cyto loc', 1);
    set_symbol ('41F1', 'cyto loc', 1);
    set_symbol ('41F2', 'cyto loc', 1);
    set_symbol ('41F3', 'cyto loc', 1);
    set_symbol ('41F4', 'cyto loc', 1);
    set_symbol ('41F5', 'cyto loc', 1);
    set_symbol ('41F6', 'cyto loc', 1);
    set_symbol ('41F7', 'cyto loc', 1);
    set_symbol ('41F8', 'cyto loc', 1);
    set_symbol ('41F9', 'cyto loc', 1);
    set_symbol ('41F10', 'cyto loc', 1);
    set_symbol ('41F11', 'cyto loc', 1);
    set_symbol ('42A1', 'cyto loc', 1);
    set_symbol ('42A2', 'cyto loc', 1);
    set_symbol ('42A3', 'cyto loc', 1);
    set_symbol ('42A4', 'cyto loc', 1);
    set_symbol ('42A5', 'cyto loc', 1);
    set_symbol ('42A6', 'cyto loc', 1);
    set_symbol ('42A7', 'cyto loc', 1);
    set_symbol ('42A8', 'cyto loc', 1);
    set_symbol ('42A9', 'cyto loc', 1);
    set_symbol ('42A10', 'cyto loc', 1);
    set_symbol ('42A11', 'cyto loc', 1);
    set_symbol ('42A12', 'cyto loc', 1);
    set_symbol ('42A13', 'cyto loc', 1);
    set_symbol ('42A14', 'cyto loc', 1);
    set_symbol ('42A15', 'cyto loc', 1);
    set_symbol ('42A16', 'cyto loc', 1);
    set_symbol ('42A17', 'cyto loc', 1);
    set_symbol ('42A18', 'cyto loc', 1);
    set_symbol ('42A19', 'cyto loc', 1);
    set_symbol ('42B1', 'cyto loc', 1);
    set_symbol ('42B2', 'cyto loc', 1);
    set_symbol ('42B3', 'cyto loc', 1);
    set_symbol ('42B4', 'cyto loc', 1);
    set_symbol ('42B5', 'cyto loc', 1);
    set_symbol ('42C1', 'cyto loc', 1);
    set_symbol ('42C2', 'cyto loc', 1);
    set_symbol ('42C3', 'cyto loc', 1);
    set_symbol ('42C4', 'cyto loc', 1);
    set_symbol ('42C5', 'cyto loc', 1);
    set_symbol ('42C6', 'cyto loc', 1);
    set_symbol ('42C7', 'cyto loc', 1);
    set_symbol ('42C8', 'cyto loc', 1);
    set_symbol ('42C9', 'cyto loc', 1);
    set_symbol ('42C10', 'cyto loc', 1);
    set_symbol ('42D1', 'cyto loc', 1);
    set_symbol ('42D2', 'cyto loc', 1);
    set_symbol ('42D3', 'cyto loc', 1);
    set_symbol ('42D4', 'cyto loc', 1);
    set_symbol ('42D5', 'cyto loc', 1);
    set_symbol ('42D6', 'cyto loc', 1);
    set_symbol ('42E1', 'cyto loc', 1);
    set_symbol ('42E2', 'cyto loc', 1);
    set_symbol ('42E3', 'cyto loc', 1);
    set_symbol ('42E4', 'cyto loc', 1);
    set_symbol ('42E5', 'cyto loc', 1);
    set_symbol ('42E6', 'cyto loc', 1);
    set_symbol ('42E7', 'cyto loc', 1);
    set_symbol ('42F1', 'cyto loc', 1);
    set_symbol ('42F2', 'cyto loc', 1);
    set_symbol ('42F3', 'cyto loc', 1);
    set_symbol ('43A1', 'cyto loc', 1);
    set_symbol ('43A2', 'cyto loc', 1);
    set_symbol ('43A3', 'cyto loc', 1);
    set_symbol ('43A4', 'cyto loc', 1);
    set_symbol ('43B1', 'cyto loc', 1);
    set_symbol ('43B2', 'cyto loc', 1);
    set_symbol ('43B3', 'cyto loc', 1);
    set_symbol ('43C1', 'cyto loc', 1);
    set_symbol ('43C2', 'cyto loc', 1);
    set_symbol ('43C3', 'cyto loc', 1);
    set_symbol ('43C4', 'cyto loc', 1);
    set_symbol ('43C5', 'cyto loc', 1);
    set_symbol ('43C6', 'cyto loc', 1);
    set_symbol ('43C7', 'cyto loc', 1);
    set_symbol ('43D1', 'cyto loc', 1);
    set_symbol ('43D2', 'cyto loc', 1);
    set_symbol ('43D3', 'cyto loc', 1);
    set_symbol ('43D4', 'cyto loc', 1);
    set_symbol ('43D5', 'cyto loc', 1);
    set_symbol ('43D6', 'cyto loc', 1);
    set_symbol ('43D7', 'cyto loc', 1);
    set_symbol ('43E1', 'cyto loc', 1);
    set_symbol ('43E2', 'cyto loc', 1);
    set_symbol ('43E3', 'cyto loc', 1);
    set_symbol ('43E4', 'cyto loc', 1);
    set_symbol ('43E5', 'cyto loc', 1);
    set_symbol ('43E6', 'cyto loc', 1);
    set_symbol ('43E7', 'cyto loc', 1);
    set_symbol ('43E8', 'cyto loc', 1);
    set_symbol ('43E9', 'cyto loc', 1);
    set_symbol ('43E10', 'cyto loc', 1);
    set_symbol ('43E11', 'cyto loc', 1);
    set_symbol ('43E12', 'cyto loc', 1);
    set_symbol ('43E13', 'cyto loc', 1);
    set_symbol ('43E14', 'cyto loc', 1);
    set_symbol ('43E15', 'cyto loc', 1);
    set_symbol ('43E16', 'cyto loc', 1);
    set_symbol ('43E17', 'cyto loc', 1);
    set_symbol ('43E18', 'cyto loc', 1);
    set_symbol ('43F1', 'cyto loc', 1);
    set_symbol ('43F2', 'cyto loc', 1);
    set_symbol ('43F3', 'cyto loc', 1);
    set_symbol ('43F4', 'cyto loc', 1);
    set_symbol ('43F5', 'cyto loc', 1);
    set_symbol ('43F6', 'cyto loc', 1);
    set_symbol ('43F7', 'cyto loc', 1);
    set_symbol ('43F8', 'cyto loc', 1);
    set_symbol ('43F9', 'cyto loc', 1);
    set_symbol ('44A1', 'cyto loc', 1);
    set_symbol ('44A2', 'cyto loc', 1);
    set_symbol ('44A3', 'cyto loc', 1);
    set_symbol ('44A4', 'cyto loc', 1);
    set_symbol ('44A5', 'cyto loc', 1);
    set_symbol ('44A6', 'cyto loc', 1);
    set_symbol ('44A7', 'cyto loc', 1);
    set_symbol ('44A8', 'cyto loc', 1);
    set_symbol ('44B1', 'cyto loc', 1);
    set_symbol ('44B2', 'cyto loc', 1);
    set_symbol ('44B3', 'cyto loc', 1);
    set_symbol ('44B4', 'cyto loc', 1);
    set_symbol ('44B5', 'cyto loc', 1);
    set_symbol ('44B6', 'cyto loc', 1);
    set_symbol ('44B7', 'cyto loc', 1);
    set_symbol ('44B8', 'cyto loc', 1);
    set_symbol ('44B9', 'cyto loc', 1);
    set_symbol ('44C1', 'cyto loc', 1);
    set_symbol ('44C2', 'cyto loc', 1);
    set_symbol ('44C3', 'cyto loc', 1);
    set_symbol ('44C4', 'cyto loc', 1);
    set_symbol ('44C5', 'cyto loc', 1);
    set_symbol ('44C6', 'cyto loc', 1);
    set_symbol ('44D1', 'cyto loc', 1);
    set_symbol ('44D2', 'cyto loc', 1);
    set_symbol ('44D3', 'cyto loc', 1);
    set_symbol ('44D4', 'cyto loc', 1);
    set_symbol ('44D5', 'cyto loc', 1);
    set_symbol ('44D6', 'cyto loc', 1);
    set_symbol ('44D7', 'cyto loc', 1);
    set_symbol ('44D8', 'cyto loc', 1);
    set_symbol ('44E1', 'cyto loc', 1);
    set_symbol ('44E2', 'cyto loc', 1);
    set_symbol ('44E3', 'cyto loc', 1);
    set_symbol ('44E4', 'cyto loc', 1);
    set_symbol ('44F1', 'cyto loc', 1);
    set_symbol ('44F2', 'cyto loc', 1);
    set_symbol ('44F3', 'cyto loc', 1);
    set_symbol ('44F4', 'cyto loc', 1);
    set_symbol ('44F5', 'cyto loc', 1);
    set_symbol ('44F6', 'cyto loc', 1);
    set_symbol ('44F7', 'cyto loc', 1);
    set_symbol ('44F8', 'cyto loc', 1);
    set_symbol ('44F9', 'cyto loc', 1);
    set_symbol ('44F10', 'cyto loc', 1);
    set_symbol ('44F11', 'cyto loc', 1);
    set_symbol ('44F12', 'cyto loc', 1);
    set_symbol ('45A1', 'cyto loc', 1);
    set_symbol ('45A2', 'cyto loc', 1);
    set_symbol ('45A3', 'cyto loc', 1);
    set_symbol ('45A4', 'cyto loc', 1);
    set_symbol ('45A5', 'cyto loc', 1);
    set_symbol ('45A6', 'cyto loc', 1);
    set_symbol ('45A7', 'cyto loc', 1);
    set_symbol ('45A8', 'cyto loc', 1);
    set_symbol ('45A9', 'cyto loc', 1);
    set_symbol ('45A10', 'cyto loc', 1);
    set_symbol ('45A11', 'cyto loc', 1);
    set_symbol ('45A12', 'cyto loc', 1);
    set_symbol ('45A13', 'cyto loc', 1);
    set_symbol ('45B1', 'cyto loc', 1);
    set_symbol ('45B2', 'cyto loc', 1);
    set_symbol ('45B3', 'cyto loc', 1);
    set_symbol ('45B4', 'cyto loc', 1);
    set_symbol ('45B5', 'cyto loc', 1);
    set_symbol ('45B6', 'cyto loc', 1);
    set_symbol ('45B7', 'cyto loc', 1);
    set_symbol ('45B8', 'cyto loc', 1);
    set_symbol ('45B9', 'cyto loc', 1);
    set_symbol ('45C1', 'cyto loc', 1);
    set_symbol ('45C2', 'cyto loc', 1);
    set_symbol ('45C3', 'cyto loc', 1);
    set_symbol ('45C4', 'cyto loc', 1);
    set_symbol ('45C5', 'cyto loc', 1);
    set_symbol ('45C6', 'cyto loc', 1);
    set_symbol ('45C7', 'cyto loc', 1);
    set_symbol ('45C8', 'cyto loc', 1);
    set_symbol ('45C9', 'cyto loc', 1);
    set_symbol ('45D1', 'cyto loc', 1);
    set_symbol ('45D2', 'cyto loc', 1);
    set_symbol ('45D3', 'cyto loc', 1);
    set_symbol ('45D4', 'cyto loc', 1);
    set_symbol ('45D5', 'cyto loc', 1);
    set_symbol ('45D6', 'cyto loc', 1);
    set_symbol ('45D7', 'cyto loc', 1);
    set_symbol ('45D8', 'cyto loc', 1);
    set_symbol ('45D9', 'cyto loc', 1);
    set_symbol ('45D10', 'cyto loc', 1);
    set_symbol ('45E1', 'cyto loc', 1);
    set_symbol ('45E2', 'cyto loc', 1);
    set_symbol ('45E3', 'cyto loc', 1);
    set_symbol ('45E4', 'cyto loc', 1);
    set_symbol ('45F1', 'cyto loc', 1);
    set_symbol ('45F2', 'cyto loc', 1);
    set_symbol ('45F3', 'cyto loc', 1);
    set_symbol ('45F4', 'cyto loc', 1);
    set_symbol ('45F5', 'cyto loc', 1);
    set_symbol ('45F6', 'cyto loc', 1);
    set_symbol ('45F7', 'cyto loc', 1);
    set_symbol ('45F8', 'cyto loc', 1);
    set_symbol ('46A1', 'cyto loc', 1);
    set_symbol ('46A2', 'cyto loc', 1);
    set_symbol ('46A3', 'cyto loc', 1);
    set_symbol ('46A4', 'cyto loc', 1);
    set_symbol ('46B1', 'cyto loc', 1);
    set_symbol ('46B2', 'cyto loc', 1);
    set_symbol ('46B3', 'cyto loc', 1);
    set_symbol ('46B4', 'cyto loc', 1);
    set_symbol ('46B5', 'cyto loc', 1);
    set_symbol ('46B6', 'cyto loc', 1);
    set_symbol ('46B7', 'cyto loc', 1);
    set_symbol ('46B8', 'cyto loc', 1);
    set_symbol ('46B9', 'cyto loc', 1);
    set_symbol ('46B10', 'cyto loc', 1);
    set_symbol ('46B11', 'cyto loc', 1);
    set_symbol ('46B12', 'cyto loc', 1);
    set_symbol ('46B13', 'cyto loc', 1);
    set_symbol ('46B14', 'cyto loc', 1);
    set_symbol ('46C1', 'cyto loc', 1);
    set_symbol ('46C2', 'cyto loc', 1);
    set_symbol ('46C3', 'cyto loc', 1);
    set_symbol ('46C4', 'cyto loc', 1);
    set_symbol ('46C5', 'cyto loc', 1);
    set_symbol ('46C6', 'cyto loc', 1);
    set_symbol ('46C7', 'cyto loc', 1);
    set_symbol ('46C8', 'cyto loc', 1);
    set_symbol ('46C9', 'cyto loc', 1);
    set_symbol ('46C10', 'cyto loc', 1);
    set_symbol ('46C11', 'cyto loc', 1);
    set_symbol ('46C12', 'cyto loc', 1);
    set_symbol ('46D1', 'cyto loc', 1);
    set_symbol ('46D2', 'cyto loc', 1);
    set_symbol ('46D3', 'cyto loc', 1);
    set_symbol ('46D4', 'cyto loc', 1);
    set_symbol ('46D5', 'cyto loc', 1);
    set_symbol ('46D6', 'cyto loc', 1);
    set_symbol ('46D7', 'cyto loc', 1);
    set_symbol ('46D8', 'cyto loc', 1);
    set_symbol ('46D9', 'cyto loc', 1);
    set_symbol ('46E1', 'cyto loc', 1);
    set_symbol ('46E2', 'cyto loc', 1);
    set_symbol ('46E3', 'cyto loc', 1);
    set_symbol ('46E4', 'cyto loc', 1);
    set_symbol ('46E5', 'cyto loc', 1);
    set_symbol ('46E6', 'cyto loc', 1);
    set_symbol ('46E7', 'cyto loc', 1);
    set_symbol ('46E8', 'cyto loc', 1);
    set_symbol ('46E9', 'cyto loc', 1);
    set_symbol ('46F1', 'cyto loc', 1);
    set_symbol ('46F2', 'cyto loc', 1);
    set_symbol ('46F3', 'cyto loc', 1);
    set_symbol ('46F4', 'cyto loc', 1);
    set_symbol ('46F5', 'cyto loc', 1);
    set_symbol ('46F6', 'cyto loc', 1);
    set_symbol ('46F7', 'cyto loc', 1);
    set_symbol ('46F8', 'cyto loc', 1);
    set_symbol ('46F9', 'cyto loc', 1);
    set_symbol ('46F10', 'cyto loc', 1);
    set_symbol ('46F11', 'cyto loc', 1);
    set_symbol ('47A1', 'cyto loc', 1);
    set_symbol ('47A2', 'cyto loc', 1);
    set_symbol ('47A3', 'cyto loc', 1);
    set_symbol ('47A4', 'cyto loc', 1);
    set_symbol ('47A5', 'cyto loc', 1);
    set_symbol ('47A6', 'cyto loc', 1);
    set_symbol ('47A7', 'cyto loc', 1);
    set_symbol ('47A8', 'cyto loc', 1);
    set_symbol ('47A9', 'cyto loc', 1);
    set_symbol ('47A10', 'cyto loc', 1);
    set_symbol ('47A11', 'cyto loc', 1);
    set_symbol ('47A12', 'cyto loc', 1);
    set_symbol ('47A13', 'cyto loc', 1);
    set_symbol ('47A14', 'cyto loc', 1);
    set_symbol ('47A15', 'cyto loc', 1);
    set_symbol ('47A16', 'cyto loc', 1);
    set_symbol ('47B1', 'cyto loc', 1);
    set_symbol ('47B2', 'cyto loc', 1);
    set_symbol ('47B3', 'cyto loc', 1);
    set_symbol ('47B4', 'cyto loc', 1);
    set_symbol ('47B5', 'cyto loc', 1);
    set_symbol ('47B6', 'cyto loc', 1);
    set_symbol ('47B7', 'cyto loc', 1);
    set_symbol ('47B8', 'cyto loc', 1);
    set_symbol ('47B9', 'cyto loc', 1);
    set_symbol ('47B10', 'cyto loc', 1);
    set_symbol ('47B11', 'cyto loc', 1);
    set_symbol ('47B12', 'cyto loc', 1);
    set_symbol ('47B13', 'cyto loc', 1);
    set_symbol ('47B14', 'cyto loc', 1);
    set_symbol ('47C1', 'cyto loc', 1);
    set_symbol ('47C2', 'cyto loc', 1);
    set_symbol ('47C3', 'cyto loc', 1);
    set_symbol ('47C4', 'cyto loc', 1);
    set_symbol ('47C5', 'cyto loc', 1);
    set_symbol ('47C6', 'cyto loc', 1);
    set_symbol ('47C7', 'cyto loc', 1);
    set_symbol ('47D1', 'cyto loc', 1);
    set_symbol ('47D2', 'cyto loc', 1);
    set_symbol ('47D3', 'cyto loc', 1);
    set_symbol ('47D4', 'cyto loc', 1);
    set_symbol ('47D5', 'cyto loc', 1);
    set_symbol ('47D6', 'cyto loc', 1);
    set_symbol ('47D7', 'cyto loc', 1);
    set_symbol ('47D8', 'cyto loc', 1);
    set_symbol ('47E1', 'cyto loc', 1);
    set_symbol ('47E2', 'cyto loc', 1);
    set_symbol ('47E3', 'cyto loc', 1);
    set_symbol ('47E4', 'cyto loc', 1);
    set_symbol ('47E5', 'cyto loc', 1);
    set_symbol ('47E6', 'cyto loc', 1);
    set_symbol ('47F1', 'cyto loc', 1);
    set_symbol ('47F2', 'cyto loc', 1);
    set_symbol ('47F3', 'cyto loc', 1);
    set_symbol ('47F4', 'cyto loc', 1);
    set_symbol ('47F5', 'cyto loc', 1);
    set_symbol ('47F6', 'cyto loc', 1);
    set_symbol ('47F7', 'cyto loc', 1);
    set_symbol ('47F8', 'cyto loc', 1);
    set_symbol ('47F9', 'cyto loc', 1);
    set_symbol ('47F10', 'cyto loc', 1);
    set_symbol ('47F11', 'cyto loc', 1);
    set_symbol ('47F12', 'cyto loc', 1);
    set_symbol ('47F13', 'cyto loc', 1);
    set_symbol ('47F14', 'cyto loc', 1);
    set_symbol ('47F15', 'cyto loc', 1);
    set_symbol ('47F16', 'cyto loc', 1);
    set_symbol ('47F17', 'cyto loc', 1);
    set_symbol ('47F18', 'cyto loc', 1);
    set_symbol ('48A1', 'cyto loc', 1);
    set_symbol ('48A2', 'cyto loc', 1);
    set_symbol ('48A3', 'cyto loc', 1);
    set_symbol ('48A4', 'cyto loc', 1);
    set_symbol ('48A5', 'cyto loc', 1);
    set_symbol ('48A6', 'cyto loc', 1);
    set_symbol ('48B1', 'cyto loc', 1);
    set_symbol ('48B2', 'cyto loc', 1);
    set_symbol ('48B3', 'cyto loc', 1);
    set_symbol ('48B4', 'cyto loc', 1);
    set_symbol ('48B5', 'cyto loc', 1);
    set_symbol ('48B6', 'cyto loc', 1);
    set_symbol ('48B7', 'cyto loc', 1);
    set_symbol ('48B8', 'cyto loc', 1);
    set_symbol ('48C1', 'cyto loc', 1);
    set_symbol ('48C2', 'cyto loc', 1);
    set_symbol ('48C3', 'cyto loc', 1);
    set_symbol ('48C4', 'cyto loc', 1);
    set_symbol ('48C5', 'cyto loc', 1);
    set_symbol ('48C6', 'cyto loc', 1);
    set_symbol ('48C7', 'cyto loc', 1);
    set_symbol ('48C8', 'cyto loc', 1);
    set_symbol ('48D1', 'cyto loc', 1);
    set_symbol ('48D2', 'cyto loc', 1);
    set_symbol ('48D3', 'cyto loc', 1);
    set_symbol ('48D4', 'cyto loc', 1);
    set_symbol ('48D5', 'cyto loc', 1);
    set_symbol ('48D6', 'cyto loc', 1);
    set_symbol ('48D7', 'cyto loc', 1);
    set_symbol ('48D8', 'cyto loc', 1);
    set_symbol ('48E1', 'cyto loc', 1);
    set_symbol ('48E2', 'cyto loc', 1);
    set_symbol ('48E3', 'cyto loc', 1);
    set_symbol ('48E4', 'cyto loc', 1);
    set_symbol ('48E5', 'cyto loc', 1);
    set_symbol ('48E6', 'cyto loc', 1);
    set_symbol ('48E7', 'cyto loc', 1);
    set_symbol ('48E8', 'cyto loc', 1);
    set_symbol ('48E9', 'cyto loc', 1);
    set_symbol ('48E10', 'cyto loc', 1);
    set_symbol ('48E11', 'cyto loc', 1);
    set_symbol ('48E12', 'cyto loc', 1);
    set_symbol ('48F1', 'cyto loc', 1);
    set_symbol ('48F2', 'cyto loc', 1);
    set_symbol ('48F3', 'cyto loc', 1);
    set_symbol ('48F4', 'cyto loc', 1);
    set_symbol ('48F5', 'cyto loc', 1);
    set_symbol ('48F6', 'cyto loc', 1);
    set_symbol ('48F7', 'cyto loc', 1);
    set_symbol ('48F8', 'cyto loc', 1);
    set_symbol ('48F9', 'cyto loc', 1);
    set_symbol ('48F10', 'cyto loc', 1);
    set_symbol ('48F11', 'cyto loc', 1);
    set_symbol ('49A1', 'cyto loc', 1);
    set_symbol ('49A2', 'cyto loc', 1);
    set_symbol ('49A3', 'cyto loc', 1);
    set_symbol ('49A4', 'cyto loc', 1);
    set_symbol ('49A5', 'cyto loc', 1);
    set_symbol ('49A6', 'cyto loc', 1);
    set_symbol ('49A7', 'cyto loc', 1);
    set_symbol ('49A8', 'cyto loc', 1);
    set_symbol ('49A9', 'cyto loc', 1);
    set_symbol ('49A10', 'cyto loc', 1);
    set_symbol ('49A11', 'cyto loc', 1);
    set_symbol ('49A12', 'cyto loc', 1);
    set_symbol ('49A13', 'cyto loc', 1);
    set_symbol ('49B1', 'cyto loc', 1);
    set_symbol ('49B2', 'cyto loc', 1);
    set_symbol ('49B3', 'cyto loc', 1);
    set_symbol ('49B4', 'cyto loc', 1);
    set_symbol ('49B5', 'cyto loc', 1);
    set_symbol ('49B6', 'cyto loc', 1);
    set_symbol ('49B7', 'cyto loc', 1);
    set_symbol ('49B8', 'cyto loc', 1);
    set_symbol ('49B9', 'cyto loc', 1);
    set_symbol ('49B10', 'cyto loc', 1);
    set_symbol ('49B11', 'cyto loc', 1);
    set_symbol ('49B12', 'cyto loc', 1);
    set_symbol ('49C1', 'cyto loc', 1);
    set_symbol ('49C2', 'cyto loc', 1);
    set_symbol ('49C3', 'cyto loc', 1);
    set_symbol ('49C4', 'cyto loc', 1);
    set_symbol ('49D1', 'cyto loc', 1);
    set_symbol ('49D2', 'cyto loc', 1);
    set_symbol ('49D3', 'cyto loc', 1);
    set_symbol ('49D4', 'cyto loc', 1);
    set_symbol ('49D5', 'cyto loc', 1);
    set_symbol ('49D6', 'cyto loc', 1);
    set_symbol ('49D7', 'cyto loc', 1);
    set_symbol ('49E1', 'cyto loc', 1);
    set_symbol ('49E2', 'cyto loc', 1);
    set_symbol ('49E3', 'cyto loc', 1);
    set_symbol ('49E4', 'cyto loc', 1);
    set_symbol ('49E5', 'cyto loc', 1);
    set_symbol ('49E6', 'cyto loc', 1);
    set_symbol ('49E7', 'cyto loc', 1);
    set_symbol ('49F1', 'cyto loc', 1);
    set_symbol ('49F2', 'cyto loc', 1);
    set_symbol ('49F3', 'cyto loc', 1);
    set_symbol ('49F4', 'cyto loc', 1);
    set_symbol ('49F5', 'cyto loc', 1);
    set_symbol ('49F6', 'cyto loc', 1);
    set_symbol ('49F7', 'cyto loc', 1);
    set_symbol ('49F8', 'cyto loc', 1);
    set_symbol ('49F9', 'cyto loc', 1);
    set_symbol ('49F10', 'cyto loc', 1);
    set_symbol ('49F11', 'cyto loc', 1);
    set_symbol ('49F12', 'cyto loc', 1);
    set_symbol ('49F13', 'cyto loc', 1);
    set_symbol ('49F14', 'cyto loc', 1);
    set_symbol ('49F15', 'cyto loc', 1);
    set_symbol ('50A1', 'cyto loc', 1);
    set_symbol ('50A2', 'cyto loc', 1);
    set_symbol ('50A3', 'cyto loc', 1);
    set_symbol ('50A4', 'cyto loc', 1);
    set_symbol ('50A5', 'cyto loc', 1);
    set_symbol ('50A6', 'cyto loc', 1);
    set_symbol ('50A7', 'cyto loc', 1);
    set_symbol ('50A8', 'cyto loc', 1);
    set_symbol ('50A9', 'cyto loc', 1);
    set_symbol ('50A10', 'cyto loc', 1);
    set_symbol ('50A11', 'cyto loc', 1);
    set_symbol ('50A12', 'cyto loc', 1);
    set_symbol ('50A13', 'cyto loc', 1);
    set_symbol ('50A14', 'cyto loc', 1);
    set_symbol ('50A15', 'cyto loc', 1);
    set_symbol ('50B1', 'cyto loc', 1);
    set_symbol ('50B2', 'cyto loc', 1);
    set_symbol ('50B3', 'cyto loc', 1);
    set_symbol ('50B4', 'cyto loc', 1);
    set_symbol ('50B5', 'cyto loc', 1);
    set_symbol ('50B6', 'cyto loc', 1);
    set_symbol ('50B7', 'cyto loc', 1);
    set_symbol ('50B8', 'cyto loc', 1);
    set_symbol ('50B9', 'cyto loc', 1);
    set_symbol ('50C1', 'cyto loc', 1);
    set_symbol ('50C2', 'cyto loc', 1);
    set_symbol ('50C3', 'cyto loc', 1);
    set_symbol ('50C4', 'cyto loc', 1);
    set_symbol ('50C5', 'cyto loc', 1);
    set_symbol ('50C6', 'cyto loc', 1);
    set_symbol ('50C7', 'cyto loc', 1);
    set_symbol ('50C8', 'cyto loc', 1);
    set_symbol ('50C9', 'cyto loc', 1);
    set_symbol ('50C10', 'cyto loc', 1);
    set_symbol ('50C11', 'cyto loc', 1);
    set_symbol ('50C12', 'cyto loc', 1);
    set_symbol ('50C13', 'cyto loc', 1);
    set_symbol ('50C14', 'cyto loc', 1);
    set_symbol ('50C15', 'cyto loc', 1);
    set_symbol ('50C16', 'cyto loc', 1);
    set_symbol ('50C17', 'cyto loc', 1);
    set_symbol ('50C18', 'cyto loc', 1);
    set_symbol ('50C19', 'cyto loc', 1);
    set_symbol ('50C20', 'cyto loc', 1);
    set_symbol ('50C21', 'cyto loc', 1);
    set_symbol ('50C22', 'cyto loc', 1);
    set_symbol ('50C23', 'cyto loc', 1);
    set_symbol ('50D1', 'cyto loc', 1);
    set_symbol ('50D2', 'cyto loc', 1);
    set_symbol ('50D3', 'cyto loc', 1);
    set_symbol ('50D4', 'cyto loc', 1);
    set_symbol ('50D5', 'cyto loc', 1);
    set_symbol ('50D6', 'cyto loc', 1);
    set_symbol ('50D7', 'cyto loc', 1);
    set_symbol ('50E1', 'cyto loc', 1);
    set_symbol ('50E2', 'cyto loc', 1);
    set_symbol ('50E3', 'cyto loc', 1);
    set_symbol ('50E4', 'cyto loc', 1);
    set_symbol ('50E5', 'cyto loc', 1);
    set_symbol ('50E6', 'cyto loc', 1);
    set_symbol ('50E7', 'cyto loc', 1);
    set_symbol ('50E8', 'cyto loc', 1);
    set_symbol ('50E9', 'cyto loc', 1);
    set_symbol ('50F1', 'cyto loc', 1);
    set_symbol ('50F2', 'cyto loc', 1);
    set_symbol ('50F3', 'cyto loc', 1);
    set_symbol ('50F4', 'cyto loc', 1);
    set_symbol ('50F5', 'cyto loc', 1);
    set_symbol ('50F6', 'cyto loc', 1);
    set_symbol ('50F7', 'cyto loc', 1);
    set_symbol ('50F8', 'cyto loc', 1);
    set_symbol ('50F9', 'cyto loc', 1);
    set_symbol ('51A1', 'cyto loc', 1);
    set_symbol ('51A2', 'cyto loc', 1);
    set_symbol ('51A3', 'cyto loc', 1);
    set_symbol ('51A4', 'cyto loc', 1);
    set_symbol ('51A5', 'cyto loc', 1);
    set_symbol ('51A6', 'cyto loc', 1);
    set_symbol ('51A7', 'cyto loc', 1);
    set_symbol ('51A8', 'cyto loc', 1);
    set_symbol ('51B1', 'cyto loc', 1);
    set_symbol ('51B2', 'cyto loc', 1);
    set_symbol ('51B3', 'cyto loc', 1);
    set_symbol ('51B4', 'cyto loc', 1);
    set_symbol ('51B5', 'cyto loc', 1);
    set_symbol ('51B6', 'cyto loc', 1);
    set_symbol ('51B7', 'cyto loc', 1);
    set_symbol ('51B8', 'cyto loc', 1);
    set_symbol ('51B9', 'cyto loc', 1);
    set_symbol ('51B10', 'cyto loc', 1);
    set_symbol ('51B11', 'cyto loc', 1);
    set_symbol ('51C1', 'cyto loc', 1);
    set_symbol ('51C2', 'cyto loc', 1);
    set_symbol ('51C3', 'cyto loc', 1);
    set_symbol ('51C4', 'cyto loc', 1);
    set_symbol ('51C5', 'cyto loc', 1);
    set_symbol ('51C6', 'cyto loc', 1);
    set_symbol ('51C7', 'cyto loc', 1);
    set_symbol ('51D1', 'cyto loc', 1);
    set_symbol ('51D2', 'cyto loc', 1);
    set_symbol ('51D3', 'cyto loc', 1);
    set_symbol ('51D4', 'cyto loc', 1);
    set_symbol ('51D5', 'cyto loc', 1);
    set_symbol ('51D6', 'cyto loc', 1);
    set_symbol ('51D7', 'cyto loc', 1);
    set_symbol ('51D8', 'cyto loc', 1);
    set_symbol ('51D9', 'cyto loc', 1);
    set_symbol ('51D10', 'cyto loc', 1);
    set_symbol ('51D11', 'cyto loc', 1);
    set_symbol ('51D12', 'cyto loc', 1);
    set_symbol ('51E1', 'cyto loc', 1);
    set_symbol ('51E2', 'cyto loc', 1);
    set_symbol ('51E3', 'cyto loc', 1);
    set_symbol ('51E4', 'cyto loc', 1);
    set_symbol ('51E5', 'cyto loc', 1);
    set_symbol ('51E6', 'cyto loc', 1);
    set_symbol ('51E7', 'cyto loc', 1);
    set_symbol ('51E8', 'cyto loc', 1);
    set_symbol ('51E9', 'cyto loc', 1);
    set_symbol ('51E10', 'cyto loc', 1);
    set_symbol ('51E11', 'cyto loc', 1);
    set_symbol ('51F1', 'cyto loc', 1);
    set_symbol ('51F2', 'cyto loc', 1);
    set_symbol ('51F3', 'cyto loc', 1);
    set_symbol ('51F4', 'cyto loc', 1);
    set_symbol ('51F5', 'cyto loc', 1);
    set_symbol ('51F6', 'cyto loc', 1);
    set_symbol ('51F7', 'cyto loc', 1);
    set_symbol ('51F8', 'cyto loc', 1);
    set_symbol ('51F9', 'cyto loc', 1);
    set_symbol ('51F10', 'cyto loc', 1);
    set_symbol ('51F11', 'cyto loc', 1);
    set_symbol ('51F12', 'cyto loc', 1);
    set_symbol ('51F13', 'cyto loc', 1);
    set_symbol ('52A1', 'cyto loc', 1);
    set_symbol ('52A2', 'cyto loc', 1);
    set_symbol ('52A3', 'cyto loc', 1);
    set_symbol ('52A4', 'cyto loc', 1);
    set_symbol ('52A5', 'cyto loc', 1);
    set_symbol ('52A6', 'cyto loc', 1);
    set_symbol ('52A7', 'cyto loc', 1);
    set_symbol ('52A8', 'cyto loc', 1);
    set_symbol ('52A9', 'cyto loc', 1);
    set_symbol ('52A10', 'cyto loc', 1);
    set_symbol ('52A11', 'cyto loc', 1);
    set_symbol ('52A12', 'cyto loc', 1);
    set_symbol ('52A13', 'cyto loc', 1);
    set_symbol ('52A14', 'cyto loc', 1);
    set_symbol ('52B1', 'cyto loc', 1);
    set_symbol ('52B2', 'cyto loc', 1);
    set_symbol ('52B3', 'cyto loc', 1);
    set_symbol ('52B4', 'cyto loc', 1);
    set_symbol ('52B5', 'cyto loc', 1);
    set_symbol ('52C1', 'cyto loc', 1);
    set_symbol ('52C2', 'cyto loc', 1);
    set_symbol ('52C3', 'cyto loc', 1);
    set_symbol ('52C4', 'cyto loc', 1);
    set_symbol ('52C5', 'cyto loc', 1);
    set_symbol ('52C6', 'cyto loc', 1);
    set_symbol ('52C7', 'cyto loc', 1);
    set_symbol ('52C8', 'cyto loc', 1);
    set_symbol ('52C9', 'cyto loc', 1);
    set_symbol ('52D1', 'cyto loc', 1);
    set_symbol ('52D2', 'cyto loc', 1);
    set_symbol ('52D3', 'cyto loc', 1);
    set_symbol ('52D4', 'cyto loc', 1);
    set_symbol ('52D5', 'cyto loc', 1);
    set_symbol ('52D6', 'cyto loc', 1);
    set_symbol ('52D7', 'cyto loc', 1);
    set_symbol ('52D8', 'cyto loc', 1);
    set_symbol ('52D9', 'cyto loc', 1);
    set_symbol ('52D10', 'cyto loc', 1);
    set_symbol ('52D11', 'cyto loc', 1);
    set_symbol ('52D12', 'cyto loc', 1);
    set_symbol ('52D13', 'cyto loc', 1);
    set_symbol ('52D14', 'cyto loc', 1);
    set_symbol ('52D15', 'cyto loc', 1);
    set_symbol ('52E1', 'cyto loc', 1);
    set_symbol ('52E2', 'cyto loc', 1);
    set_symbol ('52E3', 'cyto loc', 1);
    set_symbol ('52E4', 'cyto loc', 1);
    set_symbol ('52E5', 'cyto loc', 1);
    set_symbol ('52E6', 'cyto loc', 1);
    set_symbol ('52E7', 'cyto loc', 1);
    set_symbol ('52E8', 'cyto loc', 1);
    set_symbol ('52E9', 'cyto loc', 1);
    set_symbol ('52E10', 'cyto loc', 1);
    set_symbol ('52E11', 'cyto loc', 1);
    set_symbol ('52F1', 'cyto loc', 1);
    set_symbol ('52F2', 'cyto loc', 1);
    set_symbol ('52F3', 'cyto loc', 1);
    set_symbol ('52F4', 'cyto loc', 1);
    set_symbol ('52F5', 'cyto loc', 1);
    set_symbol ('52F6', 'cyto loc', 1);
    set_symbol ('52F7', 'cyto loc', 1);
    set_symbol ('52F8', 'cyto loc', 1);
    set_symbol ('52F9', 'cyto loc', 1);
    set_symbol ('52F10', 'cyto loc', 1);
    set_symbol ('52F11', 'cyto loc', 1);
    set_symbol ('53A1', 'cyto loc', 1);
    set_symbol ('53A2', 'cyto loc', 1);
    set_symbol ('53A3', 'cyto loc', 1);
    set_symbol ('53A4', 'cyto loc', 1);
    set_symbol ('53A5', 'cyto loc', 1);
    set_symbol ('53B1', 'cyto loc', 1);
    set_symbol ('53B2', 'cyto loc', 1);
    set_symbol ('53B3', 'cyto loc', 1);
    set_symbol ('53B4', 'cyto loc', 1);
    set_symbol ('53B5', 'cyto loc', 1);
    set_symbol ('53B6', 'cyto loc', 1);
    set_symbol ('53C1', 'cyto loc', 1);
    set_symbol ('53C2', 'cyto loc', 1);
    set_symbol ('53C3', 'cyto loc', 1);
    set_symbol ('53C4', 'cyto loc', 1);
    set_symbol ('53C5', 'cyto loc', 1);
    set_symbol ('53C6', 'cyto loc', 1);
    set_symbol ('53C7', 'cyto loc', 1);
    set_symbol ('53C8', 'cyto loc', 1);
    set_symbol ('53C9', 'cyto loc', 1);
    set_symbol ('53C10', 'cyto loc', 1);
    set_symbol ('53C11', 'cyto loc', 1);
    set_symbol ('53C12', 'cyto loc', 1);
    set_symbol ('53C13', 'cyto loc', 1);
    set_symbol ('53C14', 'cyto loc', 1);
    set_symbol ('53C15', 'cyto loc', 1);
    set_symbol ('53D1', 'cyto loc', 1);
    set_symbol ('53D2', 'cyto loc', 1);
    set_symbol ('53D3', 'cyto loc', 1);
    set_symbol ('53D4', 'cyto loc', 1);
    set_symbol ('53D5', 'cyto loc', 1);
    set_symbol ('53D6', 'cyto loc', 1);
    set_symbol ('53D7', 'cyto loc', 1);
    set_symbol ('53D8', 'cyto loc', 1);
    set_symbol ('53D9', 'cyto loc', 1);
    set_symbol ('53D10', 'cyto loc', 1);
    set_symbol ('53D11', 'cyto loc', 1);
    set_symbol ('53D12', 'cyto loc', 1);
    set_symbol ('53D13', 'cyto loc', 1);
    set_symbol ('53D14', 'cyto loc', 1);
    set_symbol ('53D15', 'cyto loc', 1);
    set_symbol ('53E1', 'cyto loc', 1);
    set_symbol ('53E2', 'cyto loc', 1);
    set_symbol ('53E3', 'cyto loc', 1);
    set_symbol ('53E4', 'cyto loc', 1);
    set_symbol ('53E5', 'cyto loc', 1);
    set_symbol ('53E6', 'cyto loc', 1);
    set_symbol ('53E7', 'cyto loc', 1);
    set_symbol ('53E8', 'cyto loc', 1);
    set_symbol ('53E9', 'cyto loc', 1);
    set_symbol ('53E10', 'cyto loc', 1);
    set_symbol ('53E11', 'cyto loc', 1);
    set_symbol ('53F1', 'cyto loc', 1);
    set_symbol ('53F2', 'cyto loc', 1);
    set_symbol ('53F3', 'cyto loc', 1);
    set_symbol ('53F4', 'cyto loc', 1);
    set_symbol ('53F5', 'cyto loc', 1);
    set_symbol ('53F6', 'cyto loc', 1);
    set_symbol ('53F7', 'cyto loc', 1);
    set_symbol ('53F8', 'cyto loc', 1);
    set_symbol ('53F9', 'cyto loc', 1);
    set_symbol ('53F10', 'cyto loc', 1);
    set_symbol ('53F11', 'cyto loc', 1);
    set_symbol ('53F12', 'cyto loc', 1);
    set_symbol ('53F13', 'cyto loc', 1);
    set_symbol ('54A1', 'cyto loc', 1);
    set_symbol ('54A2', 'cyto loc', 1);
    set_symbol ('54A3', 'cyto loc', 1);
    set_symbol ('54B1', 'cyto loc', 1);
    set_symbol ('54B2', 'cyto loc', 1);
    set_symbol ('54B3', 'cyto loc', 1);
    set_symbol ('54B4', 'cyto loc', 1);
    set_symbol ('54B5', 'cyto loc', 1);
    set_symbol ('54B6', 'cyto loc', 1);
    set_symbol ('54B7', 'cyto loc', 1);
    set_symbol ('54B8', 'cyto loc', 1);
    set_symbol ('54B9', 'cyto loc', 1);
    set_symbol ('54B10', 'cyto loc', 1);
    set_symbol ('54B11', 'cyto loc', 1);
    set_symbol ('54B12', 'cyto loc', 1);
    set_symbol ('54B13', 'cyto loc', 1);
    set_symbol ('54B14', 'cyto loc', 1);
    set_symbol ('54B15', 'cyto loc', 1);
    set_symbol ('54B16', 'cyto loc', 1);
    set_symbol ('54B17', 'cyto loc', 1);
    set_symbol ('54B18', 'cyto loc', 1);
    set_symbol ('54C1', 'cyto loc', 1);
    set_symbol ('54C2', 'cyto loc', 1);
    set_symbol ('54C3', 'cyto loc', 1);
    set_symbol ('54C4', 'cyto loc', 1);
    set_symbol ('54C5', 'cyto loc', 1);
    set_symbol ('54C6', 'cyto loc', 1);
    set_symbol ('54C7', 'cyto loc', 1);
    set_symbol ('54C8', 'cyto loc', 1);
    set_symbol ('54C9', 'cyto loc', 1);
    set_symbol ('54C10', 'cyto loc', 1);
    set_symbol ('54C11', 'cyto loc', 1);
    set_symbol ('54C12', 'cyto loc', 1);
    set_symbol ('54D1', 'cyto loc', 1);
    set_symbol ('54D2', 'cyto loc', 1);
    set_symbol ('54D3', 'cyto loc', 1);
    set_symbol ('54D4', 'cyto loc', 1);
    set_symbol ('54D5', 'cyto loc', 1);
    set_symbol ('54D6', 'cyto loc', 1);
    set_symbol ('54E1', 'cyto loc', 1);
    set_symbol ('54E2', 'cyto loc', 1);
    set_symbol ('54E3', 'cyto loc', 1);
    set_symbol ('54E4', 'cyto loc', 1);
    set_symbol ('54E5', 'cyto loc', 1);
    set_symbol ('54E6', 'cyto loc', 1);
    set_symbol ('54E7', 'cyto loc', 1);
    set_symbol ('54E8', 'cyto loc', 1);
    set_symbol ('54E9', 'cyto loc', 1);
    set_symbol ('54E10', 'cyto loc', 1);
    set_symbol ('54F1', 'cyto loc', 1);
    set_symbol ('54F2', 'cyto loc', 1);
    set_symbol ('54F3', 'cyto loc', 1);
    set_symbol ('54F4', 'cyto loc', 1);
    set_symbol ('54F5', 'cyto loc', 1);
    set_symbol ('54F6', 'cyto loc', 1);
    set_symbol ('55A1', 'cyto loc', 1);
    set_symbol ('55A2', 'cyto loc', 1);
    set_symbol ('55A3', 'cyto loc', 1);
    set_symbol ('55A4', 'cyto loc', 1);
    set_symbol ('55B1', 'cyto loc', 1);
    set_symbol ('55B2', 'cyto loc', 1);
    set_symbol ('55B3', 'cyto loc', 1);
    set_symbol ('55B4', 'cyto loc', 1);
    set_symbol ('55B5', 'cyto loc', 1);
    set_symbol ('55B6', 'cyto loc', 1);
    set_symbol ('55B7', 'cyto loc', 1);
    set_symbol ('55B8', 'cyto loc', 1);
    set_symbol ('55B9', 'cyto loc', 1);
    set_symbol ('55B10', 'cyto loc', 1);
    set_symbol ('55B11', 'cyto loc', 1);
    set_symbol ('55B12', 'cyto loc', 1);
    set_symbol ('55C1', 'cyto loc', 1);
    set_symbol ('55C2', 'cyto loc', 1);
    set_symbol ('55C3', 'cyto loc', 1);
    set_symbol ('55C4', 'cyto loc', 1);
    set_symbol ('55C5', 'cyto loc', 1);
    set_symbol ('55C6', 'cyto loc', 1);
    set_symbol ('55C7', 'cyto loc', 1);
    set_symbol ('55C8', 'cyto loc', 1);
    set_symbol ('55C9', 'cyto loc', 1);
    set_symbol ('55C10', 'cyto loc', 1);
    set_symbol ('55C11', 'cyto loc', 1);
    set_symbol ('55C12', 'cyto loc', 1);
    set_symbol ('55C13', 'cyto loc', 1);
    set_symbol ('55D1', 'cyto loc', 1);
    set_symbol ('55D2', 'cyto loc', 1);
    set_symbol ('55D3', 'cyto loc', 1);
    set_symbol ('55D4', 'cyto loc', 1);
    set_symbol ('55E1', 'cyto loc', 1);
    set_symbol ('55E2', 'cyto loc', 1);
    set_symbol ('55E3', 'cyto loc', 1);
    set_symbol ('55E4', 'cyto loc', 1);
    set_symbol ('55E5', 'cyto loc', 1);
    set_symbol ('55E6', 'cyto loc', 1);
    set_symbol ('55E7', 'cyto loc', 1);
    set_symbol ('55E8', 'cyto loc', 1);
    set_symbol ('55E9', 'cyto loc', 1);
    set_symbol ('55E10', 'cyto loc', 1);
    set_symbol ('55E11', 'cyto loc', 1);
    set_symbol ('55E12', 'cyto loc', 1);
    set_symbol ('55F1', 'cyto loc', 1);
    set_symbol ('55F2', 'cyto loc', 1);
    set_symbol ('55F3', 'cyto loc', 1);
    set_symbol ('55F4', 'cyto loc', 1);
    set_symbol ('55F5', 'cyto loc', 1);
    set_symbol ('55F6', 'cyto loc', 1);
    set_symbol ('55F7', 'cyto loc', 1);
    set_symbol ('55F8', 'cyto loc', 1);
    set_symbol ('55F9', 'cyto loc', 1);
    set_symbol ('55F10', 'cyto loc', 1);
    set_symbol ('55F11', 'cyto loc', 1);
    set_symbol ('55F12', 'cyto loc', 1);
    set_symbol ('55F13', 'cyto loc', 1);
    set_symbol ('56A1', 'cyto loc', 1);
    set_symbol ('56A2', 'cyto loc', 1);
    set_symbol ('56A3', 'cyto loc', 1);
    set_symbol ('56B1', 'cyto loc', 1);
    set_symbol ('56B2', 'cyto loc', 1);
    set_symbol ('56B3', 'cyto loc', 1);
    set_symbol ('56B4', 'cyto loc', 1);
    set_symbol ('56B5', 'cyto loc', 1);
    set_symbol ('56B6', 'cyto loc', 1);
    set_symbol ('56B7', 'cyto loc', 1);
    set_symbol ('56C1', 'cyto loc', 1);
    set_symbol ('56C2', 'cyto loc', 1);
    set_symbol ('56C3', 'cyto loc', 1);
    set_symbol ('56C4', 'cyto loc', 1);
    set_symbol ('56C5', 'cyto loc', 1);
    set_symbol ('56C6', 'cyto loc', 1);
    set_symbol ('56C7', 'cyto loc', 1);
    set_symbol ('56C8', 'cyto loc', 1);
    set_symbol ('56C9', 'cyto loc', 1);
    set_symbol ('56C10', 'cyto loc', 1);
    set_symbol ('56C11', 'cyto loc', 1);
    set_symbol ('56D1', 'cyto loc', 1);
    set_symbol ('56D2', 'cyto loc', 1);
    set_symbol ('56D3', 'cyto loc', 1);
    set_symbol ('56D4', 'cyto loc', 1);
    set_symbol ('56D5', 'cyto loc', 1);
    set_symbol ('56D6', 'cyto loc', 1);
    set_symbol ('56D7', 'cyto loc', 1);
    set_symbol ('56D8', 'cyto loc', 1);
    set_symbol ('56D9', 'cyto loc', 1);
    set_symbol ('56D10', 'cyto loc', 1);
    set_symbol ('56D11', 'cyto loc', 1);
    set_symbol ('56D12', 'cyto loc', 1);
    set_symbol ('56D13', 'cyto loc', 1);
    set_symbol ('56D14', 'cyto loc', 1);
    set_symbol ('56D15', 'cyto loc', 1);
    set_symbol ('56E1', 'cyto loc', 1);
    set_symbol ('56E2', 'cyto loc', 1);
    set_symbol ('56E3', 'cyto loc', 1);
    set_symbol ('56E4', 'cyto loc', 1);
    set_symbol ('56E5', 'cyto loc', 1);
    set_symbol ('56E6', 'cyto loc', 1);
    set_symbol ('56F1', 'cyto loc', 1);
    set_symbol ('56F2', 'cyto loc', 1);
    set_symbol ('56F3', 'cyto loc', 1);
    set_symbol ('56F4', 'cyto loc', 1);
    set_symbol ('56F5', 'cyto loc', 1);
    set_symbol ('56F6', 'cyto loc', 1);
    set_symbol ('56F7', 'cyto loc', 1);
    set_symbol ('56F8', 'cyto loc', 1);
    set_symbol ('56F9', 'cyto loc', 1);
    set_symbol ('56F10', 'cyto loc', 1);
    set_symbol ('56F11', 'cyto loc', 1);
    set_symbol ('56F12', 'cyto loc', 1);
    set_symbol ('56F13', 'cyto loc', 1);
    set_symbol ('56F14', 'cyto loc', 1);
    set_symbol ('56F15', 'cyto loc', 1);
    set_symbol ('56F16', 'cyto loc', 1);
    set_symbol ('56F17', 'cyto loc', 1);
    set_symbol ('57A1', 'cyto loc', 1);
    set_symbol ('57A2', 'cyto loc', 1);
    set_symbol ('57A3', 'cyto loc', 1);
    set_symbol ('57A4', 'cyto loc', 1);
    set_symbol ('57A5', 'cyto loc', 1);
    set_symbol ('57A6', 'cyto loc', 1);
    set_symbol ('57A7', 'cyto loc', 1);
    set_symbol ('57A8', 'cyto loc', 1);
    set_symbol ('57A9', 'cyto loc', 1);
    set_symbol ('57A10', 'cyto loc', 1);
    set_symbol ('57B1', 'cyto loc', 1);
    set_symbol ('57B2', 'cyto loc', 1);
    set_symbol ('57B3', 'cyto loc', 1);
    set_symbol ('57B4', 'cyto loc', 1);
    set_symbol ('57B5', 'cyto loc', 1);
    set_symbol ('57B6', 'cyto loc', 1);
    set_symbol ('57B7', 'cyto loc', 1);
    set_symbol ('57B8', 'cyto loc', 1);
    set_symbol ('57B9', 'cyto loc', 1);
    set_symbol ('57B10', 'cyto loc', 1);
    set_symbol ('57B11', 'cyto loc', 1);
    set_symbol ('57B12', 'cyto loc', 1);
    set_symbol ('57B13', 'cyto loc', 1);
    set_symbol ('57B14', 'cyto loc', 1);
    set_symbol ('57B15', 'cyto loc', 1);
    set_symbol ('57B16', 'cyto loc', 1);
    set_symbol ('57B17', 'cyto loc', 1);
    set_symbol ('57B18', 'cyto loc', 1);
    set_symbol ('57B19', 'cyto loc', 1);
    set_symbol ('57B20', 'cyto loc', 1);
    set_symbol ('57C1', 'cyto loc', 1);
    set_symbol ('57C2', 'cyto loc', 1);
    set_symbol ('57C3', 'cyto loc', 1);
    set_symbol ('57C4', 'cyto loc', 1);
    set_symbol ('57C5', 'cyto loc', 1);
    set_symbol ('57C6', 'cyto loc', 1);
    set_symbol ('57C7', 'cyto loc', 1);
    set_symbol ('57C8', 'cyto loc', 1);
    set_symbol ('57C9', 'cyto loc', 1);
    set_symbol ('57D1', 'cyto loc', 1);
    set_symbol ('57D2', 'cyto loc', 1);
    set_symbol ('57D3', 'cyto loc', 1);
    set_symbol ('57D4', 'cyto loc', 1);
    set_symbol ('57D5', 'cyto loc', 1);
    set_symbol ('57D6', 'cyto loc', 1);
    set_symbol ('57D7', 'cyto loc', 1);
    set_symbol ('57D8', 'cyto loc', 1);
    set_symbol ('57D9', 'cyto loc', 1);
    set_symbol ('57D10', 'cyto loc', 1);
    set_symbol ('57D11', 'cyto loc', 1);
    set_symbol ('57D12', 'cyto loc', 1);
    set_symbol ('57D13', 'cyto loc', 1);
    set_symbol ('57E1', 'cyto loc', 1);
    set_symbol ('57E2', 'cyto loc', 1);
    set_symbol ('57E3', 'cyto loc', 1);
    set_symbol ('57E4', 'cyto loc', 1);
    set_symbol ('57E5', 'cyto loc', 1);
    set_symbol ('57E6', 'cyto loc', 1);
    set_symbol ('57E7', 'cyto loc', 1);
    set_symbol ('57E8', 'cyto loc', 1);
    set_symbol ('57E9', 'cyto loc', 1);
    set_symbol ('57E10', 'cyto loc', 1);
    set_symbol ('57E11', 'cyto loc', 1);
    set_symbol ('57F1', 'cyto loc', 1);
    set_symbol ('57F2', 'cyto loc', 1);
    set_symbol ('57F3', 'cyto loc', 1);
    set_symbol ('57F4', 'cyto loc', 1);
    set_symbol ('57F5', 'cyto loc', 1);
    set_symbol ('57F6', 'cyto loc', 1);
    set_symbol ('57F7', 'cyto loc', 1);
    set_symbol ('57F8', 'cyto loc', 1);
    set_symbol ('57F9', 'cyto loc', 1);
    set_symbol ('57F10', 'cyto loc', 1);
    set_symbol ('57F11', 'cyto loc', 1);
    set_symbol ('58A1', 'cyto loc', 1);
    set_symbol ('58A2', 'cyto loc', 1);
    set_symbol ('58A3', 'cyto loc', 1);
    set_symbol ('58A4', 'cyto loc', 1);
    set_symbol ('58B1', 'cyto loc', 1);
    set_symbol ('58B2', 'cyto loc', 1);
    set_symbol ('58B3', 'cyto loc', 1);
    set_symbol ('58B4', 'cyto loc', 1);
    set_symbol ('58B5', 'cyto loc', 1);
    set_symbol ('58B6', 'cyto loc', 1);
    set_symbol ('58B7', 'cyto loc', 1);
    set_symbol ('58B8', 'cyto loc', 1);
    set_symbol ('58B9', 'cyto loc', 1);
    set_symbol ('58B10', 'cyto loc', 1);
    set_symbol ('58C1', 'cyto loc', 1);
    set_symbol ('58C2', 'cyto loc', 1);
    set_symbol ('58C3', 'cyto loc', 1);
    set_symbol ('58C4', 'cyto loc', 1);
    set_symbol ('58C5', 'cyto loc', 1);
    set_symbol ('58C6', 'cyto loc', 1);
    set_symbol ('58C7', 'cyto loc', 1);
    set_symbol ('58D1', 'cyto loc', 1);
    set_symbol ('58D2', 'cyto loc', 1);
    set_symbol ('58D3', 'cyto loc', 1);
    set_symbol ('58D4', 'cyto loc', 1);
    set_symbol ('58D5', 'cyto loc', 1);
    set_symbol ('58D6', 'cyto loc', 1);
    set_symbol ('58D7', 'cyto loc', 1);
    set_symbol ('58D8', 'cyto loc', 1);
    set_symbol ('58E1', 'cyto loc', 1);
    set_symbol ('58E2', 'cyto loc', 1);
    set_symbol ('58E3', 'cyto loc', 1);
    set_symbol ('58E4', 'cyto loc', 1);
    set_symbol ('58E5', 'cyto loc', 1);
    set_symbol ('58E6', 'cyto loc', 1);
    set_symbol ('58E7', 'cyto loc', 1);
    set_symbol ('58E8', 'cyto loc', 1);
    set_symbol ('58E9', 'cyto loc', 1);
    set_symbol ('58E10', 'cyto loc', 1);
    set_symbol ('58F1', 'cyto loc', 1);
    set_symbol ('58F2', 'cyto loc', 1);
    set_symbol ('58F3', 'cyto loc', 1);
    set_symbol ('58F4', 'cyto loc', 1);
    set_symbol ('58F5', 'cyto loc', 1);
    set_symbol ('58F6', 'cyto loc', 1);
    set_symbol ('58F7', 'cyto loc', 1);
    set_symbol ('58F8', 'cyto loc', 1);
    set_symbol ('59A1', 'cyto loc', 1);
    set_symbol ('59A2', 'cyto loc', 1);
    set_symbol ('59A3', 'cyto loc', 1);
    set_symbol ('59A4', 'cyto loc', 1);
    set_symbol ('59B1', 'cyto loc', 1);
    set_symbol ('59B2', 'cyto loc', 1);
    set_symbol ('59B3', 'cyto loc', 1);
    set_symbol ('59B4', 'cyto loc', 1);
    set_symbol ('59B5', 'cyto loc', 1);
    set_symbol ('59B6', 'cyto loc', 1);
    set_symbol ('59B7', 'cyto loc', 1);
    set_symbol ('59B8', 'cyto loc', 1);
    set_symbol ('59C1', 'cyto loc', 1);
    set_symbol ('59C2', 'cyto loc', 1);
    set_symbol ('59C3', 'cyto loc', 1);
    set_symbol ('59C4', 'cyto loc', 1);
    set_symbol ('59C5', 'cyto loc', 1);
    set_symbol ('59D1', 'cyto loc', 1);
    set_symbol ('59D2', 'cyto loc', 1);
    set_symbol ('59D3', 'cyto loc', 1);
    set_symbol ('59D4', 'cyto loc', 1);
    set_symbol ('59D5', 'cyto loc', 1);
    set_symbol ('59D6', 'cyto loc', 1);
    set_symbol ('59D7', 'cyto loc', 1);
    set_symbol ('59D8', 'cyto loc', 1);
    set_symbol ('59D9', 'cyto loc', 1);
    set_symbol ('59D10', 'cyto loc', 1);
    set_symbol ('59D11', 'cyto loc', 1);
    set_symbol ('59E1', 'cyto loc', 1);
    set_symbol ('59E2', 'cyto loc', 1);
    set_symbol ('59E3', 'cyto loc', 1);
    set_symbol ('59E4', 'cyto loc', 1);
    set_symbol ('59F1', 'cyto loc', 1);
    set_symbol ('59F2', 'cyto loc', 1);
    set_symbol ('59F3', 'cyto loc', 1);
    set_symbol ('59F4', 'cyto loc', 1);
    set_symbol ('59F5', 'cyto loc', 1);
    set_symbol ('59F6', 'cyto loc', 1);
    set_symbol ('59F7', 'cyto loc', 1);
    set_symbol ('59F8', 'cyto loc', 1);
    set_symbol ('60A1', 'cyto loc', 1);
    set_symbol ('60A2', 'cyto loc', 1);
    set_symbol ('60A3', 'cyto loc', 1);
    set_symbol ('60A4', 'cyto loc', 1);
    set_symbol ('60A5', 'cyto loc', 1);
    set_symbol ('60A6', 'cyto loc', 1);
    set_symbol ('60A7', 'cyto loc', 1);
    set_symbol ('60A8', 'cyto loc', 1);
    set_symbol ('60A9', 'cyto loc', 1);
    set_symbol ('60A10', 'cyto loc', 1);
    set_symbol ('60A11', 'cyto loc', 1);
    set_symbol ('60A12', 'cyto loc', 1);
    set_symbol ('60A13', 'cyto loc', 1);
    set_symbol ('60A14', 'cyto loc', 1);
    set_symbol ('60A15', 'cyto loc', 1);
    set_symbol ('60A16', 'cyto loc', 1);
    set_symbol ('60B1', 'cyto loc', 1);
    set_symbol ('60B2', 'cyto loc', 1);
    set_symbol ('60B3', 'cyto loc', 1);
    set_symbol ('60B4', 'cyto loc', 1);
    set_symbol ('60B5', 'cyto loc', 1);
    set_symbol ('60B6', 'cyto loc', 1);
    set_symbol ('60B7', 'cyto loc', 1);
    set_symbol ('60B8', 'cyto loc', 1);
    set_symbol ('60B9', 'cyto loc', 1);
    set_symbol ('60B10', 'cyto loc', 1);
    set_symbol ('60B11', 'cyto loc', 1);
    set_symbol ('60B12', 'cyto loc', 1);
    set_symbol ('60B13', 'cyto loc', 1);
    set_symbol ('60C1', 'cyto loc', 1);
    set_symbol ('60C2', 'cyto loc', 1);
    set_symbol ('60C3', 'cyto loc', 1);
    set_symbol ('60C4', 'cyto loc', 1);
    set_symbol ('60C5', 'cyto loc', 1);
    set_symbol ('60C6', 'cyto loc', 1);
    set_symbol ('60C7', 'cyto loc', 1);
    set_symbol ('60C8', 'cyto loc', 1);
    set_symbol ('60D1', 'cyto loc', 1);
    set_symbol ('60D2', 'cyto loc', 1);
    set_symbol ('60D3', 'cyto loc', 1);
    set_symbol ('60D4', 'cyto loc', 1);
    set_symbol ('60D5', 'cyto loc', 1);
    set_symbol ('60D6', 'cyto loc', 1);
    set_symbol ('60D7', 'cyto loc', 1);
    set_symbol ('60D8', 'cyto loc', 1);
    set_symbol ('60D9', 'cyto loc', 1);
    set_symbol ('60D10', 'cyto loc', 1);
    set_symbol ('60D11', 'cyto loc', 1);
    set_symbol ('60D12', 'cyto loc', 1);
    set_symbol ('60D13', 'cyto loc', 1);
    set_symbol ('60D14', 'cyto loc', 1);
    set_symbol ('60D15', 'cyto loc', 1);
    set_symbol ('60D16', 'cyto loc', 1);
    set_symbol ('60E1', 'cyto loc', 1);
    set_symbol ('60E2', 'cyto loc', 1);
    set_symbol ('60E3', 'cyto loc', 1);
    set_symbol ('60E4', 'cyto loc', 1);
    set_symbol ('60E5', 'cyto loc', 1);
    set_symbol ('60E6', 'cyto loc', 1);
    set_symbol ('60E7', 'cyto loc', 1);
    set_symbol ('60E8', 'cyto loc', 1);
    set_symbol ('60E9', 'cyto loc', 1);
    set_symbol ('60E10', 'cyto loc', 1);
    set_symbol ('60E11', 'cyto loc', 1);
    set_symbol ('60E12', 'cyto loc', 1);
    set_symbol ('60F1', 'cyto loc', 1);
    set_symbol ('60F2', 'cyto loc', 1);
    set_symbol ('60F3', 'cyto loc', 1);
    set_symbol ('60F4', 'cyto loc', 1);
    set_symbol ('60F5', 'cyto loc', 1);
    set_symbol ('61A1', 'cyto loc', 1);
    set_symbol ('61A2', 'cyto loc', 1);
    set_symbol ('61A3', 'cyto loc', 1);
    set_symbol ('61A4', 'cyto loc', 1);
    set_symbol ('61A5', 'cyto loc', 1);
    set_symbol ('61A6', 'cyto loc', 1);
    set_symbol ('61B1', 'cyto loc', 1);
    set_symbol ('61B2', 'cyto loc', 1);
    set_symbol ('61B3', 'cyto loc', 1);
    set_symbol ('61C1', 'cyto loc', 1);
    set_symbol ('61C2', 'cyto loc', 1);
    set_symbol ('61C3', 'cyto loc', 1);
    set_symbol ('61C4', 'cyto loc', 1);
    set_symbol ('61C5', 'cyto loc', 1);
    set_symbol ('61C6', 'cyto loc', 1);
    set_symbol ('61C7', 'cyto loc', 1);
    set_symbol ('61C8', 'cyto loc', 1);
    set_symbol ('61C9', 'cyto loc', 1);
    set_symbol ('61D1', 'cyto loc', 1);
    set_symbol ('61D2', 'cyto loc', 1);
    set_symbol ('61D3', 'cyto loc', 1);
    set_symbol ('61D4', 'cyto loc', 1);
    set_symbol ('61E1', 'cyto loc', 1);
    set_symbol ('61E2', 'cyto loc', 1);
    set_symbol ('61E3', 'cyto loc', 1);
    set_symbol ('61F1', 'cyto loc', 1);
    set_symbol ('61F2', 'cyto loc', 1);
    set_symbol ('61F3', 'cyto loc', 1);
    set_symbol ('61F4', 'cyto loc', 1);
    set_symbol ('61F5', 'cyto loc', 1);
    set_symbol ('61F6', 'cyto loc', 1);
    set_symbol ('61F7', 'cyto loc', 1);
    set_symbol ('61F8', 'cyto loc', 1);
    set_symbol ('62A1', 'cyto loc', 1);
    set_symbol ('62A2', 'cyto loc', 1);
    set_symbol ('62A3', 'cyto loc', 1);
    set_symbol ('62A4', 'cyto loc', 1);
    set_symbol ('62A5', 'cyto loc', 1);
    set_symbol ('62A6', 'cyto loc', 1);
    set_symbol ('62A7', 'cyto loc', 1);
    set_symbol ('62A8', 'cyto loc', 1);
    set_symbol ('62A9', 'cyto loc', 1);
    set_symbol ('62A10', 'cyto loc', 1);
    set_symbol ('62A11', 'cyto loc', 1);
    set_symbol ('62A12', 'cyto loc', 1);
    set_symbol ('62B1', 'cyto loc', 1);
    set_symbol ('62B2', 'cyto loc', 1);
    set_symbol ('62B3', 'cyto loc', 1);
    set_symbol ('62B4', 'cyto loc', 1);
    set_symbol ('62B5', 'cyto loc', 1);
    set_symbol ('62B6', 'cyto loc', 1);
    set_symbol ('62B7', 'cyto loc', 1);
    set_symbol ('62B8', 'cyto loc', 1);
    set_symbol ('62B9', 'cyto loc', 1);
    set_symbol ('62B10', 'cyto loc', 1);
    set_symbol ('62B11', 'cyto loc', 1);
    set_symbol ('62B12', 'cyto loc', 1);
    set_symbol ('62C1', 'cyto loc', 1);
    set_symbol ('62C2', 'cyto loc', 1);
    set_symbol ('62C3', 'cyto loc', 1);
    set_symbol ('62C4', 'cyto loc', 1);
    set_symbol ('62D1', 'cyto loc', 1);
    set_symbol ('62D2', 'cyto loc', 1);
    set_symbol ('62D3', 'cyto loc', 1);
    set_symbol ('62D4', 'cyto loc', 1);
    set_symbol ('62D5', 'cyto loc', 1);
    set_symbol ('62D6', 'cyto loc', 1);
    set_symbol ('62D7', 'cyto loc', 1);
    set_symbol ('62E1', 'cyto loc', 1);
    set_symbol ('62E2', 'cyto loc', 1);
    set_symbol ('62E3', 'cyto loc', 1);
    set_symbol ('62E4', 'cyto loc', 1);
    set_symbol ('62E5', 'cyto loc', 1);
    set_symbol ('62E6', 'cyto loc', 1);
    set_symbol ('62E7', 'cyto loc', 1);
    set_symbol ('62E8', 'cyto loc', 1);
    set_symbol ('62E9', 'cyto loc', 1);
    set_symbol ('62F1', 'cyto loc', 1);
    set_symbol ('62F2', 'cyto loc', 1);
    set_symbol ('62F3', 'cyto loc', 1);
    set_symbol ('62F4', 'cyto loc', 1);
    set_symbol ('62F5', 'cyto loc', 1);
    set_symbol ('62F6', 'cyto loc', 1);
    set_symbol ('63A1', 'cyto loc', 1);
    set_symbol ('63A2', 'cyto loc', 1);
    set_symbol ('63A3', 'cyto loc', 1);
    set_symbol ('63A4', 'cyto loc', 1);
    set_symbol ('63A5', 'cyto loc', 1);
    set_symbol ('63A6', 'cyto loc', 1);
    set_symbol ('63A7', 'cyto loc', 1);
    set_symbol ('63B1', 'cyto loc', 1);
    set_symbol ('63B2', 'cyto loc', 1);
    set_symbol ('63B3', 'cyto loc', 1);
    set_symbol ('63B4', 'cyto loc', 1);
    set_symbol ('63B5', 'cyto loc', 1);
    set_symbol ('63B6', 'cyto loc', 1);
    set_symbol ('63B7', 'cyto loc', 1);
    set_symbol ('63B8', 'cyto loc', 1);
    set_symbol ('63B9', 'cyto loc', 1);
    set_symbol ('63B10', 'cyto loc', 1);
    set_symbol ('63B11', 'cyto loc', 1);
    set_symbol ('63B12', 'cyto loc', 1);
    set_symbol ('63B13', 'cyto loc', 1);
    set_symbol ('63B14', 'cyto loc', 1);
    set_symbol ('63C1', 'cyto loc', 1);
    set_symbol ('63C2', 'cyto loc', 1);
    set_symbol ('63C3', 'cyto loc', 1);
    set_symbol ('63C4', 'cyto loc', 1);
    set_symbol ('63C5', 'cyto loc', 1);
    set_symbol ('63C6', 'cyto loc', 1);
    set_symbol ('63D1', 'cyto loc', 1);
    set_symbol ('63D2', 'cyto loc', 1);
    set_symbol ('63D3', 'cyto loc', 1);
    set_symbol ('63E1', 'cyto loc', 1);
    set_symbol ('63E2', 'cyto loc', 1);
    set_symbol ('63E3', 'cyto loc', 1);
    set_symbol ('63E4', 'cyto loc', 1);
    set_symbol ('63E5', 'cyto loc', 1);
    set_symbol ('63E6', 'cyto loc', 1);
    set_symbol ('63E7', 'cyto loc', 1);
    set_symbol ('63E8', 'cyto loc', 1);
    set_symbol ('63E9', 'cyto loc', 1);
    set_symbol ('63F1', 'cyto loc', 1);
    set_symbol ('63F2', 'cyto loc', 1);
    set_symbol ('63F3', 'cyto loc', 1);
    set_symbol ('63F4', 'cyto loc', 1);
    set_symbol ('63F5', 'cyto loc', 1);
    set_symbol ('63F6', 'cyto loc', 1);
    set_symbol ('63F7', 'cyto loc', 1);
    set_symbol ('64A1', 'cyto loc', 1);
    set_symbol ('64A2', 'cyto loc', 1);
    set_symbol ('64A3', 'cyto loc', 1);
    set_symbol ('64A4', 'cyto loc', 1);
    set_symbol ('64A5', 'cyto loc', 1);
    set_symbol ('64A6', 'cyto loc', 1);
    set_symbol ('64A7', 'cyto loc', 1);
    set_symbol ('64A8', 'cyto loc', 1);
    set_symbol ('64A9', 'cyto loc', 1);
    set_symbol ('64A10', 'cyto loc', 1);
    set_symbol ('64A11', 'cyto loc', 1);
    set_symbol ('64A12', 'cyto loc', 1);
    set_symbol ('64B1', 'cyto loc', 1);
    set_symbol ('64B2', 'cyto loc', 1);
    set_symbol ('64B3', 'cyto loc', 1);
    set_symbol ('64B4', 'cyto loc', 1);
    set_symbol ('64B5', 'cyto loc', 1);
    set_symbol ('64B6', 'cyto loc', 1);
    set_symbol ('64B7', 'cyto loc', 1);
    set_symbol ('64B8', 'cyto loc', 1);
    set_symbol ('64B9', 'cyto loc', 1);
    set_symbol ('64B10', 'cyto loc', 1);
    set_symbol ('64B11', 'cyto loc', 1);
    set_symbol ('64B12', 'cyto loc', 1);
    set_symbol ('64B13', 'cyto loc', 1);
    set_symbol ('64B14', 'cyto loc', 1);
    set_symbol ('64B15', 'cyto loc', 1);
    set_symbol ('64B16', 'cyto loc', 1);
    set_symbol ('64B17', 'cyto loc', 1);
    set_symbol ('64C1', 'cyto loc', 1);
    set_symbol ('64C2', 'cyto loc', 1);
    set_symbol ('64C3', 'cyto loc', 1);
    set_symbol ('64C4', 'cyto loc', 1);
    set_symbol ('64C5', 'cyto loc', 1);
    set_symbol ('64C6', 'cyto loc', 1);
    set_symbol ('64C7', 'cyto loc', 1);
    set_symbol ('64C8', 'cyto loc', 1);
    set_symbol ('64C9', 'cyto loc', 1);
    set_symbol ('64C10', 'cyto loc', 1);
    set_symbol ('64C11', 'cyto loc', 1);
    set_symbol ('64C12', 'cyto loc', 1);
    set_symbol ('64C13', 'cyto loc', 1);
    set_symbol ('64C14', 'cyto loc', 1);
    set_symbol ('64C15', 'cyto loc', 1);
    set_symbol ('64D1', 'cyto loc', 1);
    set_symbol ('64D2', 'cyto loc', 1);
    set_symbol ('64D3', 'cyto loc', 1);
    set_symbol ('64D4', 'cyto loc', 1);
    set_symbol ('64D5', 'cyto loc', 1);
    set_symbol ('64D6', 'cyto loc', 1);
    set_symbol ('64D7', 'cyto loc', 1);
    set_symbol ('64E1', 'cyto loc', 1);
    set_symbol ('64E2', 'cyto loc', 1);
    set_symbol ('64E3', 'cyto loc', 1);
    set_symbol ('64E4', 'cyto loc', 1);
    set_symbol ('64E5', 'cyto loc', 1);
    set_symbol ('64E6', 'cyto loc', 1);
    set_symbol ('64E7', 'cyto loc', 1);
    set_symbol ('64E8', 'cyto loc', 1);
    set_symbol ('64E9', 'cyto loc', 1);
    set_symbol ('64E10', 'cyto loc', 1);
    set_symbol ('64E11', 'cyto loc', 1);
    set_symbol ('64E12', 'cyto loc', 1);
    set_symbol ('64E13', 'cyto loc', 1);
    set_symbol ('64F1', 'cyto loc', 1);
    set_symbol ('64F2', 'cyto loc', 1);
    set_symbol ('64F3', 'cyto loc', 1);
    set_symbol ('64F4', 'cyto loc', 1);
    set_symbol ('64F5', 'cyto loc', 1);
    set_symbol ('65A1', 'cyto loc', 1);
    set_symbol ('65A2', 'cyto loc', 1);
    set_symbol ('65A3', 'cyto loc', 1);
    set_symbol ('65A4', 'cyto loc', 1);
    set_symbol ('65A5', 'cyto loc', 1);
    set_symbol ('65A6', 'cyto loc', 1);
    set_symbol ('65A7', 'cyto loc', 1);
    set_symbol ('65A8', 'cyto loc', 1);
    set_symbol ('65A9', 'cyto loc', 1);
    set_symbol ('65A10', 'cyto loc', 1);
    set_symbol ('65A11', 'cyto loc', 1);
    set_symbol ('65A12', 'cyto loc', 1);
    set_symbol ('65A13', 'cyto loc', 1);
    set_symbol ('65A14', 'cyto loc', 1);
    set_symbol ('65A15', 'cyto loc', 1);
    set_symbol ('65B1', 'cyto loc', 1);
    set_symbol ('65B2', 'cyto loc', 1);
    set_symbol ('65B3', 'cyto loc', 1);
    set_symbol ('65B4', 'cyto loc', 1);
    set_symbol ('65B5', 'cyto loc', 1);
    set_symbol ('65C1', 'cyto loc', 1);
    set_symbol ('65C2', 'cyto loc', 1);
    set_symbol ('65C3', 'cyto loc', 1);
    set_symbol ('65C4', 'cyto loc', 1);
    set_symbol ('65C5', 'cyto loc', 1);
    set_symbol ('65D1', 'cyto loc', 1);
    set_symbol ('65D2', 'cyto loc', 1);
    set_symbol ('65D3', 'cyto loc', 1);
    set_symbol ('65D4', 'cyto loc', 1);
    set_symbol ('65D5', 'cyto loc', 1);
    set_symbol ('65D6', 'cyto loc', 1);
    set_symbol ('65E1', 'cyto loc', 1);
    set_symbol ('65E2', 'cyto loc', 1);
    set_symbol ('65E3', 'cyto loc', 1);
    set_symbol ('65E4', 'cyto loc', 1);
    set_symbol ('65E5', 'cyto loc', 1);
    set_symbol ('65E6', 'cyto loc', 1);
    set_symbol ('65E7', 'cyto loc', 1);
    set_symbol ('65E8', 'cyto loc', 1);
    set_symbol ('65E9', 'cyto loc', 1);
    set_symbol ('65E10', 'cyto loc', 1);
    set_symbol ('65E11', 'cyto loc', 1);
    set_symbol ('65E12', 'cyto loc', 1);
    set_symbol ('65F1', 'cyto loc', 1);
    set_symbol ('65F2', 'cyto loc', 1);
    set_symbol ('65F3', 'cyto loc', 1);
    set_symbol ('65F4', 'cyto loc', 1);
    set_symbol ('65F5', 'cyto loc', 1);
    set_symbol ('65F6', 'cyto loc', 1);
    set_symbol ('65F7', 'cyto loc', 1);
    set_symbol ('65F8', 'cyto loc', 1);
    set_symbol ('65F9', 'cyto loc', 1);
    set_symbol ('65F10', 'cyto loc', 1);
    set_symbol ('65F11', 'cyto loc', 1);
    set_symbol ('66A1', 'cyto loc', 1);
    set_symbol ('66A2', 'cyto loc', 1);
    set_symbol ('66A3', 'cyto loc', 1);
    set_symbol ('66A4', 'cyto loc', 1);
    set_symbol ('66A5', 'cyto loc', 1);
    set_symbol ('66A6', 'cyto loc', 1);
    set_symbol ('66A7', 'cyto loc', 1);
    set_symbol ('66A8', 'cyto loc', 1);
    set_symbol ('66A9', 'cyto loc', 1);
    set_symbol ('66A10', 'cyto loc', 1);
    set_symbol ('66A11', 'cyto loc', 1);
    set_symbol ('66A12', 'cyto loc', 1);
    set_symbol ('66A13', 'cyto loc', 1);
    set_symbol ('66A14', 'cyto loc', 1);
    set_symbol ('66A15', 'cyto loc', 1);
    set_symbol ('66A16', 'cyto loc', 1);
    set_symbol ('66A17', 'cyto loc', 1);
    set_symbol ('66A18', 'cyto loc', 1);
    set_symbol ('66A19', 'cyto loc', 1);
    set_symbol ('66A20', 'cyto loc', 1);
    set_symbol ('66A21', 'cyto loc', 1);
    set_symbol ('66A22', 'cyto loc', 1);
    set_symbol ('66B1', 'cyto loc', 1);
    set_symbol ('66B2', 'cyto loc', 1);
    set_symbol ('66B3', 'cyto loc', 1);
    set_symbol ('66B4', 'cyto loc', 1);
    set_symbol ('66B5', 'cyto loc', 1);
    set_symbol ('66B6', 'cyto loc', 1);
    set_symbol ('66B7', 'cyto loc', 1);
    set_symbol ('66B8', 'cyto loc', 1);
    set_symbol ('66B9', 'cyto loc', 1);
    set_symbol ('66B10', 'cyto loc', 1);
    set_symbol ('66B11', 'cyto loc', 1);
    set_symbol ('66B12', 'cyto loc', 1);
    set_symbol ('66B13', 'cyto loc', 1);
    set_symbol ('66C1', 'cyto loc', 1);
    set_symbol ('66C2', 'cyto loc', 1);
    set_symbol ('66C3', 'cyto loc', 1);
    set_symbol ('66C4', 'cyto loc', 1);
    set_symbol ('66C5', 'cyto loc', 1);
    set_symbol ('66C6', 'cyto loc', 1);
    set_symbol ('66C7', 'cyto loc', 1);
    set_symbol ('66C8', 'cyto loc', 1);
    set_symbol ('66C9', 'cyto loc', 1);
    set_symbol ('66C10', 'cyto loc', 1);
    set_symbol ('66C11', 'cyto loc', 1);
    set_symbol ('66C12', 'cyto loc', 1);
    set_symbol ('66C13', 'cyto loc', 1);
    set_symbol ('66D1', 'cyto loc', 1);
    set_symbol ('66D2', 'cyto loc', 1);
    set_symbol ('66D3', 'cyto loc', 1);
    set_symbol ('66D4', 'cyto loc', 1);
    set_symbol ('66D5', 'cyto loc', 1);
    set_symbol ('66D6', 'cyto loc', 1);
    set_symbol ('66D7', 'cyto loc', 1);
    set_symbol ('66D8', 'cyto loc', 1);
    set_symbol ('66D9', 'cyto loc', 1);
    set_symbol ('66D10', 'cyto loc', 1);
    set_symbol ('66D11', 'cyto loc', 1);
    set_symbol ('66D12', 'cyto loc', 1);
    set_symbol ('66D13', 'cyto loc', 1);
    set_symbol ('66D14', 'cyto loc', 1);
    set_symbol ('66D15', 'cyto loc', 1);
    set_symbol ('66E1', 'cyto loc', 1);
    set_symbol ('66E2', 'cyto loc', 1);
    set_symbol ('66E3', 'cyto loc', 1);
    set_symbol ('66E4', 'cyto loc', 1);
    set_symbol ('66E5', 'cyto loc', 1);
    set_symbol ('66E6', 'cyto loc', 1);
    set_symbol ('66F1', 'cyto loc', 1);
    set_symbol ('66F2', 'cyto loc', 1);
    set_symbol ('66F3', 'cyto loc', 1);
    set_symbol ('66F4', 'cyto loc', 1);
    set_symbol ('66F5', 'cyto loc', 1);
    set_symbol ('66F6', 'cyto loc', 1);
    set_symbol ('67A1', 'cyto loc', 1);
    set_symbol ('67A2', 'cyto loc', 1);
    set_symbol ('67A3', 'cyto loc', 1);
    set_symbol ('67A4', 'cyto loc', 1);
    set_symbol ('67A5', 'cyto loc', 1);
    set_symbol ('67A6', 'cyto loc', 1);
    set_symbol ('67A7', 'cyto loc', 1);
    set_symbol ('67A8', 'cyto loc', 1);
    set_symbol ('67A9', 'cyto loc', 1);
    set_symbol ('67B1', 'cyto loc', 1);
    set_symbol ('67B2', 'cyto loc', 1);
    set_symbol ('67B3', 'cyto loc', 1);
    set_symbol ('67B4', 'cyto loc', 1);
    set_symbol ('67B5', 'cyto loc', 1);
    set_symbol ('67B6', 'cyto loc', 1);
    set_symbol ('67B7', 'cyto loc', 1);
    set_symbol ('67B8', 'cyto loc', 1);
    set_symbol ('67B9', 'cyto loc', 1);
    set_symbol ('67B10', 'cyto loc', 1);
    set_symbol ('67B11', 'cyto loc', 1);
    set_symbol ('67B12', 'cyto loc', 1);
    set_symbol ('67B13', 'cyto loc', 1);
    set_symbol ('67C1', 'cyto loc', 1);
    set_symbol ('67C2', 'cyto loc', 1);
    set_symbol ('67C3', 'cyto loc', 1);
    set_symbol ('67C4', 'cyto loc', 1);
    set_symbol ('67C5', 'cyto loc', 1);
    set_symbol ('67C6', 'cyto loc', 1);
    set_symbol ('67C7', 'cyto loc', 1);
    set_symbol ('67C8', 'cyto loc', 1);
    set_symbol ('67C9', 'cyto loc', 1);
    set_symbol ('67C10', 'cyto loc', 1);
    set_symbol ('67C11', 'cyto loc', 1);
    set_symbol ('67D1', 'cyto loc', 1);
    set_symbol ('67D2', 'cyto loc', 1);
    set_symbol ('67D3', 'cyto loc', 1);
    set_symbol ('67D4', 'cyto loc', 1);
    set_symbol ('67D5', 'cyto loc', 1);
    set_symbol ('67D6', 'cyto loc', 1);
    set_symbol ('67D7', 'cyto loc', 1);
    set_symbol ('67D8', 'cyto loc', 1);
    set_symbol ('67D9', 'cyto loc', 1);
    set_symbol ('67D10', 'cyto loc', 1);
    set_symbol ('67D11', 'cyto loc', 1);
    set_symbol ('67D12', 'cyto loc', 1);
    set_symbol ('67D13', 'cyto loc', 1);
    set_symbol ('67E1', 'cyto loc', 1);
    set_symbol ('67E2', 'cyto loc', 1);
    set_symbol ('67E3', 'cyto loc', 1);
    set_symbol ('67E4', 'cyto loc', 1);
    set_symbol ('67E5', 'cyto loc', 1);
    set_symbol ('67E6', 'cyto loc', 1);
    set_symbol ('67E7', 'cyto loc', 1);
    set_symbol ('67F1', 'cyto loc', 1);
    set_symbol ('67F2', 'cyto loc', 1);
    set_symbol ('67F3', 'cyto loc', 1);
    set_symbol ('67F4', 'cyto loc', 1);
    set_symbol ('68A1', 'cyto loc', 1);
    set_symbol ('68A2', 'cyto loc', 1);
    set_symbol ('68A3', 'cyto loc', 1);
    set_symbol ('68A4', 'cyto loc', 1);
    set_symbol ('68A5', 'cyto loc', 1);
    set_symbol ('68A6', 'cyto loc', 1);
    set_symbol ('68A7', 'cyto loc', 1);
    set_symbol ('68A8', 'cyto loc', 1);
    set_symbol ('68A9', 'cyto loc', 1);
    set_symbol ('68B1', 'cyto loc', 1);
    set_symbol ('68B2', 'cyto loc', 1);
    set_symbol ('68B3', 'cyto loc', 1);
    set_symbol ('68B4', 'cyto loc', 1);
    set_symbol ('68C1', 'cyto loc', 1);
    set_symbol ('68C2', 'cyto loc', 1);
    set_symbol ('68C3', 'cyto loc', 1);
    set_symbol ('68C4', 'cyto loc', 1);
    set_symbol ('68C5', 'cyto loc', 1);
    set_symbol ('68C6', 'cyto loc', 1);
    set_symbol ('68C7', 'cyto loc', 1);
    set_symbol ('68C8', 'cyto loc', 1);
    set_symbol ('68C9', 'cyto loc', 1);
    set_symbol ('68C10', 'cyto loc', 1);
    set_symbol ('68C11', 'cyto loc', 1);
    set_symbol ('68C12', 'cyto loc', 1);
    set_symbol ('68C13', 'cyto loc', 1);
    set_symbol ('68C14', 'cyto loc', 1);
    set_symbol ('68C15', 'cyto loc', 1);
    set_symbol ('68D1', 'cyto loc', 1);
    set_symbol ('68D2', 'cyto loc', 1);
    set_symbol ('68D3', 'cyto loc', 1);
    set_symbol ('68D4', 'cyto loc', 1);
    set_symbol ('68D5', 'cyto loc', 1);
    set_symbol ('68D6', 'cyto loc', 1);
    set_symbol ('68E1', 'cyto loc', 1);
    set_symbol ('68E2', 'cyto loc', 1);
    set_symbol ('68E3', 'cyto loc', 1);
    set_symbol ('68E4', 'cyto loc', 1);
    set_symbol ('68F1', 'cyto loc', 1);
    set_symbol ('68F2', 'cyto loc', 1);
    set_symbol ('68F3', 'cyto loc', 1);
    set_symbol ('68F4', 'cyto loc', 1);
    set_symbol ('68F5', 'cyto loc', 1);
    set_symbol ('68F6', 'cyto loc', 1);
    set_symbol ('68F7', 'cyto loc', 1);
    set_symbol ('68F8', 'cyto loc', 1);
    set_symbol ('69A1', 'cyto loc', 1);
    set_symbol ('69A2', 'cyto loc', 1);
    set_symbol ('69A3', 'cyto loc', 1);
    set_symbol ('69A4', 'cyto loc', 1);
    set_symbol ('69A5', 'cyto loc', 1);
    set_symbol ('69B1', 'cyto loc', 1);
    set_symbol ('69B2', 'cyto loc', 1);
    set_symbol ('69B3', 'cyto loc', 1);
    set_symbol ('69B4', 'cyto loc', 1);
    set_symbol ('69B5', 'cyto loc', 1);
    set_symbol ('69C1', 'cyto loc', 1);
    set_symbol ('69C2', 'cyto loc', 1);
    set_symbol ('69C3', 'cyto loc', 1);
    set_symbol ('69C4', 'cyto loc', 1);
    set_symbol ('69C5', 'cyto loc', 1);
    set_symbol ('69C6', 'cyto loc', 1);
    set_symbol ('69C7', 'cyto loc', 1);
    set_symbol ('69C8', 'cyto loc', 1);
    set_symbol ('69C9', 'cyto loc', 1);
    set_symbol ('69C10', 'cyto loc', 1);
    set_symbol ('69C11', 'cyto loc', 1);
    set_symbol ('69D1', 'cyto loc', 1);
    set_symbol ('69D2', 'cyto loc', 1);
    set_symbol ('69D3', 'cyto loc', 1);
    set_symbol ('69D4', 'cyto loc', 1);
    set_symbol ('69D5', 'cyto loc', 1);
    set_symbol ('69D6', 'cyto loc', 1);
    set_symbol ('69E1', 'cyto loc', 1);
    set_symbol ('69E2', 'cyto loc', 1);
    set_symbol ('69E3', 'cyto loc', 1);
    set_symbol ('69E4', 'cyto loc', 1);
    set_symbol ('69E5', 'cyto loc', 1);
    set_symbol ('69E6', 'cyto loc', 1);
    set_symbol ('69E7', 'cyto loc', 1);
    set_symbol ('69E8', 'cyto loc', 1);
    set_symbol ('69F1', 'cyto loc', 1);
    set_symbol ('69F2', 'cyto loc', 1);
    set_symbol ('69F3', 'cyto loc', 1);
    set_symbol ('69F4', 'cyto loc', 1);
    set_symbol ('69F5', 'cyto loc', 1);
    set_symbol ('69F6', 'cyto loc', 1);
    set_symbol ('69F7', 'cyto loc', 1);
    set_symbol ('70A1', 'cyto loc', 1);
    set_symbol ('70A2', 'cyto loc', 1);
    set_symbol ('70A3', 'cyto loc', 1);
    set_symbol ('70A4', 'cyto loc', 1);
    set_symbol ('70A5', 'cyto loc', 1);
    set_symbol ('70A6', 'cyto loc', 1);
    set_symbol ('70A7', 'cyto loc', 1);
    set_symbol ('70A8', 'cyto loc', 1);
    set_symbol ('70B1', 'cyto loc', 1);
    set_symbol ('70B2', 'cyto loc', 1);
    set_symbol ('70B3', 'cyto loc', 1);
    set_symbol ('70B4', 'cyto loc', 1);
    set_symbol ('70B5', 'cyto loc', 1);
    set_symbol ('70B6', 'cyto loc', 1);
    set_symbol ('70B7', 'cyto loc', 1);
    set_symbol ('70C1', 'cyto loc', 1);
    set_symbol ('70C2', 'cyto loc', 1);
    set_symbol ('70C3', 'cyto loc', 1);
    set_symbol ('70C4', 'cyto loc', 1);
    set_symbol ('70C5', 'cyto loc', 1);
    set_symbol ('70C6', 'cyto loc', 1);
    set_symbol ('70C7', 'cyto loc', 1);
    set_symbol ('70C8', 'cyto loc', 1);
    set_symbol ('70C9', 'cyto loc', 1);
    set_symbol ('70C10', 'cyto loc', 1);
    set_symbol ('70C11', 'cyto loc', 1);
    set_symbol ('70C12', 'cyto loc', 1);
    set_symbol ('70C13', 'cyto loc', 1);
    set_symbol ('70C14', 'cyto loc', 1);
    set_symbol ('70C15', 'cyto loc', 1);
    set_symbol ('70D1', 'cyto loc', 1);
    set_symbol ('70D2', 'cyto loc', 1);
    set_symbol ('70D3', 'cyto loc', 1);
    set_symbol ('70D4', 'cyto loc', 1);
    set_symbol ('70D5', 'cyto loc', 1);
    set_symbol ('70D6', 'cyto loc', 1);
    set_symbol ('70D7', 'cyto loc', 1);
    set_symbol ('70E1', 'cyto loc', 1);
    set_symbol ('70E2', 'cyto loc', 1);
    set_symbol ('70E3', 'cyto loc', 1);
    set_symbol ('70E4', 'cyto loc', 1);
    set_symbol ('70E5', 'cyto loc', 1);
    set_symbol ('70E6', 'cyto loc', 1);
    set_symbol ('70E7', 'cyto loc', 1);
    set_symbol ('70E8', 'cyto loc', 1);
    set_symbol ('70F1', 'cyto loc', 1);
    set_symbol ('70F2', 'cyto loc', 1);
    set_symbol ('70F3', 'cyto loc', 1);
    set_symbol ('70F4', 'cyto loc', 1);
    set_symbol ('70F5', 'cyto loc', 1);
    set_symbol ('70F6', 'cyto loc', 1);
    set_symbol ('70F7', 'cyto loc', 1);
    set_symbol ('71A1', 'cyto loc', 1);
    set_symbol ('71A2', 'cyto loc', 1);
    set_symbol ('71A3', 'cyto loc', 1);
    set_symbol ('71A4', 'cyto loc', 1);
    set_symbol ('71B1', 'cyto loc', 1);
    set_symbol ('71B2', 'cyto loc', 1);
    set_symbol ('71B3', 'cyto loc', 1);
    set_symbol ('71B4', 'cyto loc', 1);
    set_symbol ('71B5', 'cyto loc', 1);
    set_symbol ('71B6', 'cyto loc', 1);
    set_symbol ('71B7', 'cyto loc', 1);
    set_symbol ('71B8', 'cyto loc', 1);
    set_symbol ('71C1', 'cyto loc', 1);
    set_symbol ('71C2', 'cyto loc', 1);
    set_symbol ('71C3', 'cyto loc', 1);
    set_symbol ('71C4', 'cyto loc', 1);
    set_symbol ('71D1', 'cyto loc', 1);
    set_symbol ('71D2', 'cyto loc', 1);
    set_symbol ('71D3', 'cyto loc', 1);
    set_symbol ('71D4', 'cyto loc', 1);
    set_symbol ('71E1', 'cyto loc', 1);
    set_symbol ('71E2', 'cyto loc', 1);
    set_symbol ('71E3', 'cyto loc', 1);
    set_symbol ('71E4', 'cyto loc', 1);
    set_symbol ('71E5', 'cyto loc', 1);
    set_symbol ('71F1', 'cyto loc', 1);
    set_symbol ('71F2', 'cyto loc', 1);
    set_symbol ('71F3', 'cyto loc', 1);
    set_symbol ('71F4', 'cyto loc', 1);
    set_symbol ('71F5', 'cyto loc', 1);
    set_symbol ('72A1', 'cyto loc', 1);
    set_symbol ('72A2', 'cyto loc', 1);
    set_symbol ('72A3', 'cyto loc', 1);
    set_symbol ('72A4', 'cyto loc', 1);
    set_symbol ('72A5', 'cyto loc', 1);
    set_symbol ('72B1', 'cyto loc', 1);
    set_symbol ('72B2', 'cyto loc', 1);
    set_symbol ('72C1', 'cyto loc', 1);
    set_symbol ('72C2', 'cyto loc', 1);
    set_symbol ('72C3', 'cyto loc', 1);
    set_symbol ('72D1', 'cyto loc', 1);
    set_symbol ('72D2', 'cyto loc', 1);
    set_symbol ('72D3', 'cyto loc', 1);
    set_symbol ('72D4', 'cyto loc', 1);
    set_symbol ('72D5', 'cyto loc', 1);
    set_symbol ('72D6', 'cyto loc', 1);
    set_symbol ('72D7', 'cyto loc', 1);
    set_symbol ('72D8', 'cyto loc', 1);
    set_symbol ('72D9', 'cyto loc', 1);
    set_symbol ('72D10', 'cyto loc', 1);
    set_symbol ('72D11', 'cyto loc', 1);
    set_symbol ('72D12', 'cyto loc', 1);
    set_symbol ('72E1', 'cyto loc', 1);
    set_symbol ('72E2', 'cyto loc', 1);
    set_symbol ('72E3', 'cyto loc', 1);
    set_symbol ('72E4', 'cyto loc', 1);
    set_symbol ('72E5', 'cyto loc', 1);
    set_symbol ('72F1', 'cyto loc', 1);
    set_symbol ('72F2', 'cyto loc', 1);
    set_symbol ('72F3', 'cyto loc', 1);
    set_symbol ('72F4', 'cyto loc', 1);
    set_symbol ('73A1', 'cyto loc', 1);
    set_symbol ('73A2', 'cyto loc', 1);
    set_symbol ('73A3', 'cyto loc', 1);
    set_symbol ('73A4', 'cyto loc', 1);
    set_symbol ('73A5', 'cyto loc', 1);
    set_symbol ('73A6', 'cyto loc', 1);
    set_symbol ('73A7', 'cyto loc', 1);
    set_symbol ('73A8', 'cyto loc', 1);
    set_symbol ('73A9', 'cyto loc', 1);
    set_symbol ('73A10', 'cyto loc', 1);
    set_symbol ('73A11', 'cyto loc', 1);
    set_symbol ('73B1', 'cyto loc', 1);
    set_symbol ('73B2', 'cyto loc', 1);
    set_symbol ('73B3', 'cyto loc', 1);
    set_symbol ('73B4', 'cyto loc', 1);
    set_symbol ('73B5', 'cyto loc', 1);
    set_symbol ('73B6', 'cyto loc', 1);
    set_symbol ('73B7', 'cyto loc', 1);
    set_symbol ('73C1', 'cyto loc', 1);
    set_symbol ('73C2', 'cyto loc', 1);
    set_symbol ('73C3', 'cyto loc', 1);
    set_symbol ('73C4', 'cyto loc', 1);
    set_symbol ('73C5', 'cyto loc', 1);
    set_symbol ('73D1', 'cyto loc', 1);
    set_symbol ('73D2', 'cyto loc', 1);
    set_symbol ('73D3', 'cyto loc', 1);
    set_symbol ('73D4', 'cyto loc', 1);
    set_symbol ('73D5', 'cyto loc', 1);
    set_symbol ('73D6', 'cyto loc', 1);
    set_symbol ('73D7', 'cyto loc', 1);
    set_symbol ('73E1', 'cyto loc', 1);
    set_symbol ('73E2', 'cyto loc', 1);
    set_symbol ('73E3', 'cyto loc', 1);
    set_symbol ('73E4', 'cyto loc', 1);
    set_symbol ('73E5', 'cyto loc', 1);
    set_symbol ('73E6', 'cyto loc', 1);
    set_symbol ('73F1', 'cyto loc', 1);
    set_symbol ('73F2', 'cyto loc', 1);
    set_symbol ('73F3', 'cyto loc', 1);
    set_symbol ('73F4', 'cyto loc', 1);
    set_symbol ('74A1', 'cyto loc', 1);
    set_symbol ('74A2', 'cyto loc', 1);
    set_symbol ('74A3', 'cyto loc', 1);
    set_symbol ('74A4', 'cyto loc', 1);
    set_symbol ('74A5', 'cyto loc', 1);
    set_symbol ('74A6', 'cyto loc', 1);
    set_symbol ('74B1', 'cyto loc', 1);
    set_symbol ('74B2', 'cyto loc', 1);
    set_symbol ('74B3', 'cyto loc', 1);
    set_symbol ('74B4', 'cyto loc', 1);
    set_symbol ('74B5', 'cyto loc', 1);
    set_symbol ('74C1', 'cyto loc', 1);
    set_symbol ('74C2', 'cyto loc', 1);
    set_symbol ('74C3', 'cyto loc', 1);
    set_symbol ('74C4', 'cyto loc', 1);
    set_symbol ('74D1', 'cyto loc', 1);
    set_symbol ('74D2', 'cyto loc', 1);
    set_symbol ('74D3', 'cyto loc', 1);
    set_symbol ('74D4', 'cyto loc', 1);
    set_symbol ('74D5', 'cyto loc', 1);
    set_symbol ('74E1', 'cyto loc', 1);
    set_symbol ('74E2', 'cyto loc', 1);
    set_symbol ('74E3', 'cyto loc', 1);
    set_symbol ('74E4', 'cyto loc', 1);
    set_symbol ('74E5', 'cyto loc', 1);
    set_symbol ('74F1', 'cyto loc', 1);
    set_symbol ('74F2', 'cyto loc', 1);
    set_symbol ('74F3', 'cyto loc', 1);
    set_symbol ('74F4', 'cyto loc', 1);
    set_symbol ('75A1', 'cyto loc', 1);
    set_symbol ('75A2', 'cyto loc', 1);
    set_symbol ('75A3', 'cyto loc', 1);
    set_symbol ('75A4', 'cyto loc', 1);
    set_symbol ('75A5', 'cyto loc', 1);
    set_symbol ('75A6', 'cyto loc', 1);
    set_symbol ('75A7', 'cyto loc', 1);
    set_symbol ('75A8', 'cyto loc', 1);
    set_symbol ('75A9', 'cyto loc', 1);
    set_symbol ('75A10', 'cyto loc', 1);
    set_symbol ('75B1', 'cyto loc', 1);
    set_symbol ('75B2', 'cyto loc', 1);
    set_symbol ('75B3', 'cyto loc', 1);
    set_symbol ('75B4', 'cyto loc', 1);
    set_symbol ('75B5', 'cyto loc', 1);
    set_symbol ('75B6', 'cyto loc', 1);
    set_symbol ('75B7', 'cyto loc', 1);
    set_symbol ('75B8', 'cyto loc', 1);
    set_symbol ('75B9', 'cyto loc', 1);
    set_symbol ('75B10', 'cyto loc', 1);
    set_symbol ('75B11', 'cyto loc', 1);
    set_symbol ('75B12', 'cyto loc', 1);
    set_symbol ('75B13', 'cyto loc', 1);
    set_symbol ('75C1', 'cyto loc', 1);
    set_symbol ('75C2', 'cyto loc', 1);
    set_symbol ('75C3', 'cyto loc', 1);
    set_symbol ('75C4', 'cyto loc', 1);
    set_symbol ('75C5', 'cyto loc', 1);
    set_symbol ('75C6', 'cyto loc', 1);
    set_symbol ('75C7', 'cyto loc', 1);
    set_symbol ('75D1', 'cyto loc', 1);
    set_symbol ('75D2', 'cyto loc', 1);
    set_symbol ('75D3', 'cyto loc', 1);
    set_symbol ('75D4', 'cyto loc', 1);
    set_symbol ('75D5', 'cyto loc', 1);
    set_symbol ('75D6', 'cyto loc', 1);
    set_symbol ('75D7', 'cyto loc', 1);
    set_symbol ('75D8', 'cyto loc', 1);
    set_symbol ('75E1', 'cyto loc', 1);
    set_symbol ('75E2', 'cyto loc', 1);
    set_symbol ('75E3', 'cyto loc', 1);
    set_symbol ('75E4', 'cyto loc', 1);
    set_symbol ('75E5', 'cyto loc', 1);
    set_symbol ('75E6', 'cyto loc', 1);
    set_symbol ('75E7', 'cyto loc', 1);
    set_symbol ('75F1', 'cyto loc', 1);
    set_symbol ('75F2', 'cyto loc', 1);
    set_symbol ('75F3', 'cyto loc', 1);
    set_symbol ('75F4', 'cyto loc', 1);
    set_symbol ('75F5', 'cyto loc', 1);
    set_symbol ('75F6', 'cyto loc', 1);
    set_symbol ('75F7', 'cyto loc', 1);
    set_symbol ('75F8', 'cyto loc', 1);
    set_symbol ('75F9', 'cyto loc', 1);
    set_symbol ('75F10', 'cyto loc', 1);
    set_symbol ('75F11', 'cyto loc', 1);
    set_symbol ('76A1', 'cyto loc', 1);
    set_symbol ('76A2', 'cyto loc', 1);
    set_symbol ('76A3', 'cyto loc', 1);
    set_symbol ('76A4', 'cyto loc', 1);
    set_symbol ('76A5', 'cyto loc', 1);
    set_symbol ('76A6', 'cyto loc', 1);
    set_symbol ('76A7', 'cyto loc', 1);
    set_symbol ('76B1', 'cyto loc', 1);
    set_symbol ('76B2', 'cyto loc', 1);
    set_symbol ('76B3', 'cyto loc', 1);
    set_symbol ('76B4', 'cyto loc', 1);
    set_symbol ('76B5', 'cyto loc', 1);
    set_symbol ('76B6', 'cyto loc', 1);
    set_symbol ('76B7', 'cyto loc', 1);
    set_symbol ('76B8', 'cyto loc', 1);
    set_symbol ('76B9', 'cyto loc', 1);
    set_symbol ('76B10', 'cyto loc', 1);
    set_symbol ('76B11', 'cyto loc', 1);
    set_symbol ('76C1', 'cyto loc', 1);
    set_symbol ('76C2', 'cyto loc', 1);
    set_symbol ('76C3', 'cyto loc', 1);
    set_symbol ('76C4', 'cyto loc', 1);
    set_symbol ('76C5', 'cyto loc', 1);
    set_symbol ('76C6', 'cyto loc', 1);
    set_symbol ('76D1', 'cyto loc', 1);
    set_symbol ('76D2', 'cyto loc', 1);
    set_symbol ('76D3', 'cyto loc', 1);
    set_symbol ('76D4', 'cyto loc', 1);
    set_symbol ('76D5', 'cyto loc', 1);
    set_symbol ('76D6', 'cyto loc', 1);
    set_symbol ('76D7', 'cyto loc', 1);
    set_symbol ('76D8', 'cyto loc', 1);
    set_symbol ('76E1', 'cyto loc', 1);
    set_symbol ('76E2', 'cyto loc', 1);
    set_symbol ('76E3', 'cyto loc', 1);
    set_symbol ('76E4', 'cyto loc', 1);
    set_symbol ('76F1', 'cyto loc', 1);
    set_symbol ('76F2', 'cyto loc', 1);
    set_symbol ('76F3', 'cyto loc', 1);
    set_symbol ('77A1', 'cyto loc', 1);
    set_symbol ('77A2', 'cyto loc', 1);
    set_symbol ('77A3', 'cyto loc', 1);
    set_symbol ('77A4', 'cyto loc', 1);
    set_symbol ('77B1', 'cyto loc', 1);
    set_symbol ('77B2', 'cyto loc', 1);
    set_symbol ('77B3', 'cyto loc', 1);
    set_symbol ('77B4', 'cyto loc', 1);
    set_symbol ('77B5', 'cyto loc', 1);
    set_symbol ('77B6', 'cyto loc', 1);
    set_symbol ('77B7', 'cyto loc', 1);
    set_symbol ('77B8', 'cyto loc', 1);
    set_symbol ('77B9', 'cyto loc', 1);
    set_symbol ('77C1', 'cyto loc', 1);
    set_symbol ('77C2', 'cyto loc', 1);
    set_symbol ('77C3', 'cyto loc', 1);
    set_symbol ('77C4', 'cyto loc', 1);
    set_symbol ('77C5', 'cyto loc', 1);
    set_symbol ('77C6', 'cyto loc', 1);
    set_symbol ('77C7', 'cyto loc', 1);
    set_symbol ('77D1', 'cyto loc', 1);
    set_symbol ('77D2', 'cyto loc', 1);
    set_symbol ('77D3', 'cyto loc', 1);
    set_symbol ('77D4', 'cyto loc', 1);
    set_symbol ('77D5', 'cyto loc', 1);
    set_symbol ('77E1', 'cyto loc', 1);
    set_symbol ('77E2', 'cyto loc', 1);
    set_symbol ('77E3', 'cyto loc', 1);
    set_symbol ('77E4', 'cyto loc', 1);
    set_symbol ('77E5', 'cyto loc', 1);
    set_symbol ('77E6', 'cyto loc', 1);
    set_symbol ('77E7', 'cyto loc', 1);
    set_symbol ('77E8', 'cyto loc', 1);
    set_symbol ('77F1', 'cyto loc', 1);
    set_symbol ('77F2', 'cyto loc', 1);
    set_symbol ('77F3', 'cyto loc', 1);
    set_symbol ('77F4', 'cyto loc', 1);
    set_symbol ('77F5', 'cyto loc', 1);
    set_symbol ('78A1', 'cyto loc', 1);
    set_symbol ('78A2', 'cyto loc', 1);
    set_symbol ('78A3', 'cyto loc', 1);
    set_symbol ('78A4', 'cyto loc', 1);
    set_symbol ('78A5', 'cyto loc', 1);
    set_symbol ('78A6', 'cyto loc', 1);
    set_symbol ('78A7', 'cyto loc', 1);
    set_symbol ('78B1', 'cyto loc', 1);
    set_symbol ('78B2', 'cyto loc', 1);
    set_symbol ('78B3', 'cyto loc', 1);
    set_symbol ('78B4', 'cyto loc', 1);
    set_symbol ('78C1', 'cyto loc', 1);
    set_symbol ('78C2', 'cyto loc', 1);
    set_symbol ('78C3', 'cyto loc', 1);
    set_symbol ('78C4', 'cyto loc', 1);
    set_symbol ('78C5', 'cyto loc', 1);
    set_symbol ('78C6', 'cyto loc', 1);
    set_symbol ('78C7', 'cyto loc', 1);
    set_symbol ('78C8', 'cyto loc', 1);
    set_symbol ('78C9', 'cyto loc', 1);
    set_symbol ('78D1', 'cyto loc', 1);
    set_symbol ('78D2', 'cyto loc', 1);
    set_symbol ('78D3', 'cyto loc', 1);
    set_symbol ('78D4', 'cyto loc', 1);
    set_symbol ('78D5', 'cyto loc', 1);
    set_symbol ('78D6', 'cyto loc', 1);
    set_symbol ('78D7', 'cyto loc', 1);
    set_symbol ('78D8', 'cyto loc', 1);
    set_symbol ('78E1', 'cyto loc', 1);
    set_symbol ('78E2', 'cyto loc', 1);
    set_symbol ('78E3', 'cyto loc', 1);
    set_symbol ('78E4', 'cyto loc', 1);
    set_symbol ('78E5', 'cyto loc', 1);
    set_symbol ('78E6', 'cyto loc', 1);
    set_symbol ('78F1', 'cyto loc', 1);
    set_symbol ('78F2', 'cyto loc', 1);
    set_symbol ('78F3', 'cyto loc', 1);
    set_symbol ('78F4', 'cyto loc', 1);
    set_symbol ('79A1', 'cyto loc', 1);
    set_symbol ('79A2', 'cyto loc', 1);
    set_symbol ('79A3', 'cyto loc', 1);
    set_symbol ('79A4', 'cyto loc', 1);
    set_symbol ('79A5', 'cyto loc', 1);
    set_symbol ('79A6', 'cyto loc', 1);
    set_symbol ('79A7', 'cyto loc', 1);
    set_symbol ('79B1', 'cyto loc', 1);
    set_symbol ('79B2', 'cyto loc', 1);
    set_symbol ('79B3', 'cyto loc', 1);
    set_symbol ('79C1', 'cyto loc', 1);
    set_symbol ('79C2', 'cyto loc', 1);
    set_symbol ('79C3', 'cyto loc', 1);
    set_symbol ('79D1', 'cyto loc', 1);
    set_symbol ('79D2', 'cyto loc', 1);
    set_symbol ('79D3', 'cyto loc', 1);
    set_symbol ('79D4', 'cyto loc', 1);
    set_symbol ('79E1', 'cyto loc', 1);
    set_symbol ('79E2', 'cyto loc', 1);
    set_symbol ('79E3', 'cyto loc', 1);
    set_symbol ('79E4', 'cyto loc', 1);
    set_symbol ('79E5', 'cyto loc', 1);
    set_symbol ('79E6', 'cyto loc', 1);
    set_symbol ('79E7', 'cyto loc', 1);
    set_symbol ('79E8', 'cyto loc', 1);
    set_symbol ('79F1', 'cyto loc', 1);
    set_symbol ('79F2', 'cyto loc', 1);
    set_symbol ('79F3', 'cyto loc', 1);
    set_symbol ('79F4', 'cyto loc', 1);
    set_symbol ('79F5', 'cyto loc', 1);
    set_symbol ('79F6', 'cyto loc', 1);
    set_symbol ('80A1', 'cyto loc', 1);
    set_symbol ('80A2', 'cyto loc', 1);
    set_symbol ('80A3', 'cyto loc', 1);
    set_symbol ('80A4', 'cyto loc', 1);
    set_symbol ('80B1', 'cyto loc', 1);
    set_symbol ('80B2', 'cyto loc', 1);
    set_symbol ('80B3', 'cyto loc', 1);
    set_symbol ('80C1', 'cyto loc', 1);
    set_symbol ('80C2', 'cyto loc', 1);
    set_symbol ('80C3', 'cyto loc', 1);
    set_symbol ('80C4', 'cyto loc', 1);
    set_symbol ('80C5', 'cyto loc', 1);
    set_symbol ('80D1', 'cyto loc', 1);
    set_symbol ('80D2', 'cyto loc', 1);
    set_symbol ('80D3', 'cyto loc', 1);
    set_symbol ('80D4', 'cyto loc', 1);
    set_symbol ('80D5', 'cyto loc', 1);
    set_symbol ('80E1', 'cyto loc', 1);
    set_symbol ('80E2', 'cyto loc', 1);
    set_symbol ('80E3', 'cyto loc', 1);
    set_symbol ('80F1', 'cyto loc', 1);
    set_symbol ('80F2', 'cyto loc', 1);
    set_symbol ('80F3', 'cyto loc', 1);
    set_symbol ('80F4', 'cyto loc', 1);
    set_symbol ('80F5', 'cyto loc', 1);
    set_symbol ('80F6', 'cyto loc', 1);
    set_symbol ('80F7', 'cyto loc', 1);
    set_symbol ('80F8', 'cyto loc', 1);
    set_symbol ('80F9', 'cyto loc', 1);
    set_symbol ('81F1', 'cyto loc', 1);
    set_symbol ('81F2', 'cyto loc', 1);
    set_symbol ('81F3', 'cyto loc', 1);
    set_symbol ('81F4', 'cyto loc', 1);
    set_symbol ('81F5', 'cyto loc', 1);
    set_symbol ('81F6', 'cyto loc', 1);
    set_symbol ('82A1', 'cyto loc', 1);
    set_symbol ('82A2', 'cyto loc', 1);
    set_symbol ('82A3', 'cyto loc', 1);
    set_symbol ('82A4', 'cyto loc', 1);
    set_symbol ('82A5', 'cyto loc', 1);
    set_symbol ('82A6', 'cyto loc', 1);
    set_symbol ('82B1', 'cyto loc', 1);
    set_symbol ('82B2', 'cyto loc', 1);
    set_symbol ('82B3', 'cyto loc', 1);
    set_symbol ('82B4', 'cyto loc', 1);
    set_symbol ('82C1', 'cyto loc', 1);
    set_symbol ('82C2', 'cyto loc', 1);
    set_symbol ('82C3', 'cyto loc', 1);
    set_symbol ('82C4', 'cyto loc', 1);
    set_symbol ('82C5', 'cyto loc', 1);
    set_symbol ('82D1', 'cyto loc', 1);
    set_symbol ('82D2', 'cyto loc', 1);
    set_symbol ('82D3', 'cyto loc', 1);
    set_symbol ('82D4', 'cyto loc', 1);
    set_symbol ('82D5', 'cyto loc', 1);
    set_symbol ('82D6', 'cyto loc', 1);
    set_symbol ('82D7', 'cyto loc', 1);
    set_symbol ('82D8', 'cyto loc', 1);
    set_symbol ('82E1', 'cyto loc', 1);
    set_symbol ('82E2', 'cyto loc', 1);
    set_symbol ('82E3', 'cyto loc', 1);
    set_symbol ('82E4', 'cyto loc', 1);
    set_symbol ('82E5', 'cyto loc', 1);
    set_symbol ('82E6', 'cyto loc', 1);
    set_symbol ('82E7', 'cyto loc', 1);
    set_symbol ('82E8', 'cyto loc', 1);
    set_symbol ('82F1', 'cyto loc', 1);
    set_symbol ('82F2', 'cyto loc', 1);
    set_symbol ('82F3', 'cyto loc', 1);
    set_symbol ('82F4', 'cyto loc', 1);
    set_symbol ('82F5', 'cyto loc', 1);
    set_symbol ('82F6', 'cyto loc', 1);
    set_symbol ('82F7', 'cyto loc', 1);
    set_symbol ('82F8', 'cyto loc', 1);
    set_symbol ('82F9', 'cyto loc', 1);
    set_symbol ('82F10', 'cyto loc', 1);
    set_symbol ('82F11', 'cyto loc', 1);
    set_symbol ('83A1', 'cyto loc', 1);
    set_symbol ('83A2', 'cyto loc', 1);
    set_symbol ('83A3', 'cyto loc', 1);
    set_symbol ('83A4', 'cyto loc', 1);
    set_symbol ('83A5', 'cyto loc', 1);
    set_symbol ('83A6', 'cyto loc', 1);
    set_symbol ('83A7', 'cyto loc', 1);
    set_symbol ('83A8', 'cyto loc', 1);
    set_symbol ('83A9', 'cyto loc', 1);
    set_symbol ('83B1', 'cyto loc', 1);
    set_symbol ('83B2', 'cyto loc', 1);
    set_symbol ('83B3', 'cyto loc', 1);
    set_symbol ('83B4', 'cyto loc', 1);
    set_symbol ('83B5', 'cyto loc', 1);
    set_symbol ('83B6', 'cyto loc', 1);
    set_symbol ('83B7', 'cyto loc', 1);
    set_symbol ('83B8', 'cyto loc', 1);
    set_symbol ('83B9', 'cyto loc', 1);
    set_symbol ('83C1', 'cyto loc', 1);
    set_symbol ('83C2', 'cyto loc', 1);
    set_symbol ('83C3', 'cyto loc', 1);
    set_symbol ('83C4', 'cyto loc', 1);
    set_symbol ('83C5', 'cyto loc', 1);
    set_symbol ('83C6', 'cyto loc', 1);
    set_symbol ('83C7', 'cyto loc', 1);
    set_symbol ('83C8', 'cyto loc', 1);
    set_symbol ('83C9', 'cyto loc', 1);
    set_symbol ('83D1', 'cyto loc', 1);
    set_symbol ('83D2', 'cyto loc', 1);
    set_symbol ('83D3', 'cyto loc', 1);
    set_symbol ('83D4', 'cyto loc', 1);
    set_symbol ('83D5', 'cyto loc', 1);
    set_symbol ('83E1', 'cyto loc', 1);
    set_symbol ('83E2', 'cyto loc', 1);
    set_symbol ('83E3', 'cyto loc', 1);
    set_symbol ('83E4', 'cyto loc', 1);
    set_symbol ('83E5', 'cyto loc', 1);
    set_symbol ('83E6', 'cyto loc', 1);
    set_symbol ('83E7', 'cyto loc', 1);
    set_symbol ('83E8', 'cyto loc', 1);
    set_symbol ('83F1', 'cyto loc', 1);
    set_symbol ('83F2', 'cyto loc', 1);
    set_symbol ('83F3', 'cyto loc', 1);
    set_symbol ('83F4', 'cyto loc', 1);
    set_symbol ('84A1', 'cyto loc', 1);
    set_symbol ('84A2', 'cyto loc', 1);
    set_symbol ('84A3', 'cyto loc', 1);
    set_symbol ('84A4', 'cyto loc', 1);
    set_symbol ('84A5', 'cyto loc', 1);
    set_symbol ('84A6', 'cyto loc', 1);
    set_symbol ('84B1', 'cyto loc', 1);
    set_symbol ('84B2', 'cyto loc', 1);
    set_symbol ('84B3', 'cyto loc', 1);
    set_symbol ('84B4', 'cyto loc', 1);
    set_symbol ('84B5', 'cyto loc', 1);
    set_symbol ('84B6', 'cyto loc', 1);
    set_symbol ('84C1', 'cyto loc', 1);
    set_symbol ('84C2', 'cyto loc', 1);
    set_symbol ('84C3', 'cyto loc', 1);
    set_symbol ('84C4', 'cyto loc', 1);
    set_symbol ('84C5', 'cyto loc', 1);
    set_symbol ('84C6', 'cyto loc', 1);
    set_symbol ('84C7', 'cyto loc', 1);
    set_symbol ('84C8', 'cyto loc', 1);
    set_symbol ('84D1', 'cyto loc', 1);
    set_symbol ('84D2', 'cyto loc', 1);
    set_symbol ('84D3', 'cyto loc', 1);
    set_symbol ('84D4', 'cyto loc', 1);
    set_symbol ('84D5', 'cyto loc', 1);
    set_symbol ('84D6', 'cyto loc', 1);
    set_symbol ('84D7', 'cyto loc', 1);
    set_symbol ('84D8', 'cyto loc', 1);
    set_symbol ('84D9', 'cyto loc', 1);
    set_symbol ('84D10', 'cyto loc', 1);
    set_symbol ('84D11', 'cyto loc', 1);
    set_symbol ('84D12', 'cyto loc', 1);
    set_symbol ('84D13', 'cyto loc', 1);
    set_symbol ('84D14', 'cyto loc', 1);
    set_symbol ('84E1', 'cyto loc', 1);
    set_symbol ('84E2', 'cyto loc', 1);
    set_symbol ('84E3', 'cyto loc', 1);
    set_symbol ('84E4', 'cyto loc', 1);
    set_symbol ('84E5', 'cyto loc', 1);
    set_symbol ('84E6', 'cyto loc', 1);
    set_symbol ('84E7', 'cyto loc', 1);
    set_symbol ('84E8', 'cyto loc', 1);
    set_symbol ('84E9', 'cyto loc', 1);
    set_symbol ('84E10', 'cyto loc', 1);
    set_symbol ('84E11', 'cyto loc', 1);
    set_symbol ('84E12', 'cyto loc', 1);
    set_symbol ('84E13', 'cyto loc', 1);
    set_symbol ('84F1', 'cyto loc', 1);
    set_symbol ('84F2', 'cyto loc', 1);
    set_symbol ('84F3', 'cyto loc', 1);
    set_symbol ('84F4', 'cyto loc', 1);
    set_symbol ('84F5', 'cyto loc', 1);
    set_symbol ('84F6', 'cyto loc', 1);
    set_symbol ('84F7', 'cyto loc', 1);
    set_symbol ('84F8', 'cyto loc', 1);
    set_symbol ('84F9', 'cyto loc', 1);
    set_symbol ('84F10', 'cyto loc', 1);
    set_symbol ('84F11', 'cyto loc', 1);
    set_symbol ('84F12', 'cyto loc', 1);
    set_symbol ('84F13', 'cyto loc', 1);
    set_symbol ('84F14', 'cyto loc', 1);
    set_symbol ('84F15', 'cyto loc', 1);
    set_symbol ('84F16', 'cyto loc', 1);
    set_symbol ('85A1', 'cyto loc', 1);
    set_symbol ('85A2', 'cyto loc', 1);
    set_symbol ('85A3', 'cyto loc', 1);
    set_symbol ('85A4', 'cyto loc', 1);
    set_symbol ('85A5', 'cyto loc', 1);
    set_symbol ('85A6', 'cyto loc', 1);
    set_symbol ('85A7', 'cyto loc', 1);
    set_symbol ('85A8', 'cyto loc', 1);
    set_symbol ('85A9', 'cyto loc', 1);
    set_symbol ('85A10', 'cyto loc', 1);
    set_symbol ('85A11', 'cyto loc', 1);
    set_symbol ('85B1', 'cyto loc', 1);
    set_symbol ('85B2', 'cyto loc', 1);
    set_symbol ('85B3', 'cyto loc', 1);
    set_symbol ('85B4', 'cyto loc', 1);
    set_symbol ('85B5', 'cyto loc', 1);
    set_symbol ('85B6', 'cyto loc', 1);
    set_symbol ('85B7', 'cyto loc', 1);
    set_symbol ('85B8', 'cyto loc', 1);
    set_symbol ('85B9', 'cyto loc', 1);
    set_symbol ('85C1', 'cyto loc', 1);
    set_symbol ('85C2', 'cyto loc', 1);
    set_symbol ('85C3', 'cyto loc', 1);
    set_symbol ('85C4', 'cyto loc', 1);
    set_symbol ('85C5', 'cyto loc', 1);
    set_symbol ('85C6', 'cyto loc', 1);
    set_symbol ('85C7', 'cyto loc', 1);
    set_symbol ('85C8', 'cyto loc', 1);
    set_symbol ('85C9', 'cyto loc', 1);
    set_symbol ('85C10', 'cyto loc', 1);
    set_symbol ('85C11', 'cyto loc', 1);
    set_symbol ('85C12', 'cyto loc', 1);
    set_symbol ('85C13', 'cyto loc', 1);
    set_symbol ('85D1', 'cyto loc', 1);
    set_symbol ('85D2', 'cyto loc', 1);
    set_symbol ('85D3', 'cyto loc', 1);
    set_symbol ('85D4', 'cyto loc', 1);
    set_symbol ('85D5', 'cyto loc', 1);
    set_symbol ('85D6', 'cyto loc', 1);
    set_symbol ('85D7', 'cyto loc', 1);
    set_symbol ('85D8', 'cyto loc', 1);
    set_symbol ('85D9', 'cyto loc', 1);
    set_symbol ('85D10', 'cyto loc', 1);
    set_symbol ('85D11', 'cyto loc', 1);
    set_symbol ('85D12', 'cyto loc', 1);
    set_symbol ('85D13', 'cyto loc', 1);
    set_symbol ('85D14', 'cyto loc', 1);
    set_symbol ('85D15', 'cyto loc', 1);
    set_symbol ('85D16', 'cyto loc', 1);
    set_symbol ('85D17', 'cyto loc', 1);
    set_symbol ('85D18', 'cyto loc', 1);
    set_symbol ('85D19', 'cyto loc', 1);
    set_symbol ('85D20', 'cyto loc', 1);
    set_symbol ('85D21', 'cyto loc', 1);
    set_symbol ('85D22', 'cyto loc', 1);
    set_symbol ('85D23', 'cyto loc', 1);
    set_symbol ('85D24', 'cyto loc', 1);
    set_symbol ('85D25', 'cyto loc', 1);
    set_symbol ('85D26', 'cyto loc', 1);
    set_symbol ('85D27', 'cyto loc', 1);
    set_symbol ('85E1', 'cyto loc', 1);
    set_symbol ('85E2', 'cyto loc', 1);
    set_symbol ('85E3', 'cyto loc', 1);
    set_symbol ('85E4', 'cyto loc', 1);
    set_symbol ('85E5', 'cyto loc', 1);
    set_symbol ('85E6', 'cyto loc', 1);
    set_symbol ('85E7', 'cyto loc', 1);
    set_symbol ('85E8', 'cyto loc', 1);
    set_symbol ('85E9', 'cyto loc', 1);
    set_symbol ('85E10', 'cyto loc', 1);
    set_symbol ('85E11', 'cyto loc', 1);
    set_symbol ('85E12', 'cyto loc', 1);
    set_symbol ('85E13', 'cyto loc', 1);
    set_symbol ('85E14', 'cyto loc', 1);
    set_symbol ('85E15', 'cyto loc', 1);
    set_symbol ('85F1', 'cyto loc', 1);
    set_symbol ('85F2', 'cyto loc', 1);
    set_symbol ('85F3', 'cyto loc', 1);
    set_symbol ('85F4', 'cyto loc', 1);
    set_symbol ('85F5', 'cyto loc', 1);
    set_symbol ('85F6', 'cyto loc', 1);
    set_symbol ('85F7', 'cyto loc', 1);
    set_symbol ('85F8', 'cyto loc', 1);
    set_symbol ('85F9', 'cyto loc', 1);
    set_symbol ('85F10', 'cyto loc', 1);
    set_symbol ('85F11', 'cyto loc', 1);
    set_symbol ('85F12', 'cyto loc', 1);
    set_symbol ('85F13', 'cyto loc', 1);
    set_symbol ('85F14', 'cyto loc', 1);
    set_symbol ('85F15', 'cyto loc', 1);
    set_symbol ('85F16', 'cyto loc', 1);
    set_symbol ('86A1', 'cyto loc', 1);
    set_symbol ('86A2', 'cyto loc', 1);
    set_symbol ('86A3', 'cyto loc', 1);
    set_symbol ('86A4', 'cyto loc', 1);
    set_symbol ('86A5', 'cyto loc', 1);
    set_symbol ('86A6', 'cyto loc', 1);
    set_symbol ('86A7', 'cyto loc', 1);
    set_symbol ('86A8', 'cyto loc', 1);
    set_symbol ('86B1', 'cyto loc', 1);
    set_symbol ('86B2', 'cyto loc', 1);
    set_symbol ('86B3', 'cyto loc', 1);
    set_symbol ('86B4', 'cyto loc', 1);
    set_symbol ('86B5', 'cyto loc', 1);
    set_symbol ('86B6', 'cyto loc', 1);
    set_symbol ('86C1', 'cyto loc', 1);
    set_symbol ('86C2', 'cyto loc', 1);
    set_symbol ('86C3', 'cyto loc', 1);
    set_symbol ('86C4', 'cyto loc', 1);
    set_symbol ('86C5', 'cyto loc', 1);
    set_symbol ('86C6', 'cyto loc', 1);
    set_symbol ('86C7', 'cyto loc', 1);
    set_symbol ('86C8', 'cyto loc', 1);
    set_symbol ('86C9', 'cyto loc', 1);
    set_symbol ('86C10', 'cyto loc', 1);
    set_symbol ('86C11', 'cyto loc', 1);
    set_symbol ('86C12', 'cyto loc', 1);
    set_symbol ('86C13', 'cyto loc', 1);
    set_symbol ('86C14', 'cyto loc', 1);
    set_symbol ('86C15', 'cyto loc', 1);
    set_symbol ('86D1', 'cyto loc', 1);
    set_symbol ('86D2', 'cyto loc', 1);
    set_symbol ('86D3', 'cyto loc', 1);
    set_symbol ('86D4', 'cyto loc', 1);
    set_symbol ('86D5', 'cyto loc', 1);
    set_symbol ('86D6', 'cyto loc', 1);
    set_symbol ('86D7', 'cyto loc', 1);
    set_symbol ('86D8', 'cyto loc', 1);
    set_symbol ('86D9', 'cyto loc', 1);
    set_symbol ('86D10', 'cyto loc', 1);
    set_symbol ('86E1', 'cyto loc', 1);
    set_symbol ('86E2', 'cyto loc', 1);
    set_symbol ('86E3', 'cyto loc', 1);
    set_symbol ('86E4', 'cyto loc', 1);
    set_symbol ('86E5', 'cyto loc', 1);
    set_symbol ('86E6', 'cyto loc', 1);
    set_symbol ('86E7', 'cyto loc', 1);
    set_symbol ('86E8', 'cyto loc', 1);
    set_symbol ('86E9', 'cyto loc', 1);
    set_symbol ('86E10', 'cyto loc', 1);
    set_symbol ('86E11', 'cyto loc', 1);
    set_symbol ('86E12', 'cyto loc', 1);
    set_symbol ('86E13', 'cyto loc', 1);
    set_symbol ('86E14', 'cyto loc', 1);
    set_symbol ('86E15', 'cyto loc', 1);
    set_symbol ('86E16', 'cyto loc', 1);
    set_symbol ('86E17', 'cyto loc', 1);
    set_symbol ('86E18', 'cyto loc', 1);
    set_symbol ('86E19', 'cyto loc', 1);
    set_symbol ('86E20', 'cyto loc', 1);
    set_symbol ('86F1', 'cyto loc', 1);
    set_symbol ('86F2', 'cyto loc', 1);
    set_symbol ('86F3', 'cyto loc', 1);
    set_symbol ('86F4', 'cyto loc', 1);
    set_symbol ('86F5', 'cyto loc', 1);
    set_symbol ('86F6', 'cyto loc', 1);
    set_symbol ('86F7', 'cyto loc', 1);
    set_symbol ('86F8', 'cyto loc', 1);
    set_symbol ('86F9', 'cyto loc', 1);
    set_symbol ('86F10', 'cyto loc', 1);
    set_symbol ('86F11', 'cyto loc', 1);
    set_symbol ('87A1', 'cyto loc', 1);
    set_symbol ('87A2', 'cyto loc', 1);
    set_symbol ('87A3', 'cyto loc', 1);
    set_symbol ('87A4', 'cyto loc', 1);
    set_symbol ('87A5', 'cyto loc', 1);
    set_symbol ('87A6', 'cyto loc', 1);
    set_symbol ('87A7', 'cyto loc', 1);
    set_symbol ('87A8', 'cyto loc', 1);
    set_symbol ('87A9', 'cyto loc', 1);
    set_symbol ('87A10', 'cyto loc', 1);
    set_symbol ('87B1', 'cyto loc', 1);
    set_symbol ('87B2', 'cyto loc', 1);
    set_symbol ('87B3', 'cyto loc', 1);
    set_symbol ('87B4', 'cyto loc', 1);
    set_symbol ('87B5', 'cyto loc', 1);
    set_symbol ('87B6', 'cyto loc', 1);
    set_symbol ('87B7', 'cyto loc', 1);
    set_symbol ('87B8', 'cyto loc', 1);
    set_symbol ('87B9', 'cyto loc', 1);
    set_symbol ('87B10', 'cyto loc', 1);
    set_symbol ('87B11', 'cyto loc', 1);
    set_symbol ('87B12', 'cyto loc', 1);
    set_symbol ('87B13', 'cyto loc', 1);
    set_symbol ('87B14', 'cyto loc', 1);
    set_symbol ('87B15', 'cyto loc', 1);
    set_symbol ('87C1', 'cyto loc', 1);
    set_symbol ('87C2', 'cyto loc', 1);
    set_symbol ('87C3', 'cyto loc', 1);
    set_symbol ('87C4', 'cyto loc', 1);
    set_symbol ('87C5', 'cyto loc', 1);
    set_symbol ('87C6', 'cyto loc', 1);
    set_symbol ('87C7', 'cyto loc', 1);
    set_symbol ('87C8', 'cyto loc', 1);
    set_symbol ('87C9', 'cyto loc', 1);
    set_symbol ('87D1', 'cyto loc', 1);
    set_symbol ('87D2', 'cyto loc', 1);
    set_symbol ('87D3', 'cyto loc', 1);
    set_symbol ('87D4', 'cyto loc', 1);
    set_symbol ('87D5', 'cyto loc', 1);
    set_symbol ('87D6', 'cyto loc', 1);
    set_symbol ('87D7', 'cyto loc', 1);
    set_symbol ('87D8', 'cyto loc', 1);
    set_symbol ('87D9', 'cyto loc', 1);
    set_symbol ('87D10', 'cyto loc', 1);
    set_symbol ('87D11', 'cyto loc', 1);
    set_symbol ('87D12', 'cyto loc', 1);
    set_symbol ('87D13', 'cyto loc', 1);
    set_symbol ('87D14', 'cyto loc', 1);
    set_symbol ('87E1', 'cyto loc', 1);
    set_symbol ('87E2', 'cyto loc', 1);
    set_symbol ('87E3', 'cyto loc', 1);
    set_symbol ('87E4', 'cyto loc', 1);
    set_symbol ('87E5', 'cyto loc', 1);
    set_symbol ('87E6', 'cyto loc', 1);
    set_symbol ('87E7', 'cyto loc', 1);
    set_symbol ('87E8', 'cyto loc', 1);
    set_symbol ('87E9', 'cyto loc', 1);
    set_symbol ('87E10', 'cyto loc', 1);
    set_symbol ('87E11', 'cyto loc', 1);
    set_symbol ('87E12', 'cyto loc', 1);
    set_symbol ('87F1', 'cyto loc', 1);
    set_symbol ('87F2', 'cyto loc', 1);
    set_symbol ('87F3', 'cyto loc', 1);
    set_symbol ('87F4', 'cyto loc', 1);
    set_symbol ('87F5', 'cyto loc', 1);
    set_symbol ('87F6', 'cyto loc', 1);
    set_symbol ('87F7', 'cyto loc', 1);
    set_symbol ('87F8', 'cyto loc', 1);
    set_symbol ('87F9', 'cyto loc', 1);
    set_symbol ('87F10', 'cyto loc', 1);
    set_symbol ('87F11', 'cyto loc', 1);
    set_symbol ('87F12', 'cyto loc', 1);
    set_symbol ('87F13', 'cyto loc', 1);
    set_symbol ('87F14', 'cyto loc', 1);
    set_symbol ('87F15', 'cyto loc', 1);
    set_symbol ('88A1', 'cyto loc', 1);
    set_symbol ('88A2', 'cyto loc', 1);
    set_symbol ('88A3', 'cyto loc', 1);
    set_symbol ('88A4', 'cyto loc', 1);
    set_symbol ('88A5', 'cyto loc', 1);
    set_symbol ('88A6', 'cyto loc', 1);
    set_symbol ('88A7', 'cyto loc', 1);
    set_symbol ('88A8', 'cyto loc', 1);
    set_symbol ('88A9', 'cyto loc', 1);
    set_symbol ('88A10', 'cyto loc', 1);
    set_symbol ('88A11', 'cyto loc', 1);
    set_symbol ('88A12', 'cyto loc', 1);
    set_symbol ('88B1', 'cyto loc', 1);
    set_symbol ('88B2', 'cyto loc', 1);
    set_symbol ('88B3', 'cyto loc', 1);
    set_symbol ('88B4', 'cyto loc', 1);
    set_symbol ('88B5', 'cyto loc', 1);
    set_symbol ('88B6', 'cyto loc', 1);
    set_symbol ('88B7', 'cyto loc', 1);
    set_symbol ('88B8', 'cyto loc', 1);
    set_symbol ('88B9', 'cyto loc', 1);
    set_symbol ('88C1', 'cyto loc', 1);
    set_symbol ('88C2', 'cyto loc', 1);
    set_symbol ('88C3', 'cyto loc', 1);
    set_symbol ('88C4', 'cyto loc', 1);
    set_symbol ('88C5', 'cyto loc', 1);
    set_symbol ('88C6', 'cyto loc', 1);
    set_symbol ('88C7', 'cyto loc', 1);
    set_symbol ('88C8', 'cyto loc', 1);
    set_symbol ('88C9', 'cyto loc', 1);
    set_symbol ('88C10', 'cyto loc', 1);
    set_symbol ('88C11', 'cyto loc', 1);
    set_symbol ('88D1', 'cyto loc', 1);
    set_symbol ('88D2', 'cyto loc', 1);
    set_symbol ('88D3', 'cyto loc', 1);
    set_symbol ('88D4', 'cyto loc', 1);
    set_symbol ('88D5', 'cyto loc', 1);
    set_symbol ('88D6', 'cyto loc', 1);
    set_symbol ('88D7', 'cyto loc', 1);
    set_symbol ('88D8', 'cyto loc', 1);
    set_symbol ('88D9', 'cyto loc', 1);
    set_symbol ('88D10', 'cyto loc', 1);
    set_symbol ('88E1', 'cyto loc', 1);
    set_symbol ('88E2', 'cyto loc', 1);
    set_symbol ('88E3', 'cyto loc', 1);
    set_symbol ('88E4', 'cyto loc', 1);
    set_symbol ('88E5', 'cyto loc', 1);
    set_symbol ('88E6', 'cyto loc', 1);
    set_symbol ('88E7', 'cyto loc', 1);
    set_symbol ('88E8', 'cyto loc', 1);
    set_symbol ('88E9', 'cyto loc', 1);
    set_symbol ('88E10', 'cyto loc', 1);
    set_symbol ('88E11', 'cyto loc', 1);
    set_symbol ('88E12', 'cyto loc', 1);
    set_symbol ('88E13', 'cyto loc', 1);
    set_symbol ('88F1', 'cyto loc', 1);
    set_symbol ('88F2', 'cyto loc', 1);
    set_symbol ('88F3', 'cyto loc', 1);
    set_symbol ('88F4', 'cyto loc', 1);
    set_symbol ('88F5', 'cyto loc', 1);
    set_symbol ('88F6', 'cyto loc', 1);
    set_symbol ('88F7', 'cyto loc', 1);
    set_symbol ('88F8', 'cyto loc', 1);
    set_symbol ('88F9', 'cyto loc', 1);
    set_symbol ('89A1', 'cyto loc', 1);
    set_symbol ('89A2', 'cyto loc', 1);
    set_symbol ('89A3', 'cyto loc', 1);
    set_symbol ('89A4', 'cyto loc', 1);
    set_symbol ('89A5', 'cyto loc', 1);
    set_symbol ('89A6', 'cyto loc', 1);
    set_symbol ('89A7', 'cyto loc', 1);
    set_symbol ('89A8', 'cyto loc', 1);
    set_symbol ('89A9', 'cyto loc', 1);
    set_symbol ('89A10', 'cyto loc', 1);
    set_symbol ('89A11', 'cyto loc', 1);
    set_symbol ('89A12', 'cyto loc', 1);
    set_symbol ('89A13', 'cyto loc', 1);
    set_symbol ('89B1', 'cyto loc', 1);
    set_symbol ('89B2', 'cyto loc', 1);
    set_symbol ('89B3', 'cyto loc', 1);
    set_symbol ('89B4', 'cyto loc', 1);
    set_symbol ('89B5', 'cyto loc', 1);
    set_symbol ('89B6', 'cyto loc', 1);
    set_symbol ('89B7', 'cyto loc', 1);
    set_symbol ('89B8', 'cyto loc', 1);
    set_symbol ('89B9', 'cyto loc', 1);
    set_symbol ('89B10', 'cyto loc', 1);
    set_symbol ('89B11', 'cyto loc', 1);
    set_symbol ('89B12', 'cyto loc', 1);
    set_symbol ('89B13', 'cyto loc', 1);
    set_symbol ('89B14', 'cyto loc', 1);
    set_symbol ('89B15', 'cyto loc', 1);
    set_symbol ('89B16', 'cyto loc', 1);
    set_symbol ('89B17', 'cyto loc', 1);
    set_symbol ('89B18', 'cyto loc', 1);
    set_symbol ('89B19', 'cyto loc', 1);
    set_symbol ('89B20', 'cyto loc', 1);
    set_symbol ('89B21', 'cyto loc', 1);
    set_symbol ('89B22', 'cyto loc', 1);
    set_symbol ('89C1', 'cyto loc', 1);
    set_symbol ('89C2', 'cyto loc', 1);
    set_symbol ('89C3', 'cyto loc', 1);
    set_symbol ('89C4', 'cyto loc', 1);
    set_symbol ('89C5', 'cyto loc', 1);
    set_symbol ('89C6', 'cyto loc', 1);
    set_symbol ('89C7', 'cyto loc', 1);
    set_symbol ('89D1', 'cyto loc', 1);
    set_symbol ('89D2', 'cyto loc', 1);
    set_symbol ('89D3', 'cyto loc', 1);
    set_symbol ('89D4', 'cyto loc', 1);
    set_symbol ('89D5', 'cyto loc', 1);
    set_symbol ('89D6', 'cyto loc', 1);
    set_symbol ('89D7', 'cyto loc', 1);
    set_symbol ('89D8', 'cyto loc', 1);
    set_symbol ('89D9', 'cyto loc', 1);
    set_symbol ('89E1', 'cyto loc', 1);
    set_symbol ('89E2', 'cyto loc', 1);
    set_symbol ('89E3', 'cyto loc', 1);
    set_symbol ('89E4', 'cyto loc', 1);
    set_symbol ('89E5', 'cyto loc', 1);
    set_symbol ('89E6', 'cyto loc', 1);
    set_symbol ('89E7', 'cyto loc', 1);
    set_symbol ('89E8', 'cyto loc', 1);
    set_symbol ('89E9', 'cyto loc', 1);
    set_symbol ('89E10', 'cyto loc', 1);
    set_symbol ('89E11', 'cyto loc', 1);
    set_symbol ('89E12', 'cyto loc', 1);
    set_symbol ('89E13', 'cyto loc', 1);
    set_symbol ('89F1', 'cyto loc', 1);
    set_symbol ('89F2', 'cyto loc', 1);
    set_symbol ('89F3', 'cyto loc', 1);
    set_symbol ('89F4', 'cyto loc', 1);
    set_symbol ('90A1', 'cyto loc', 1);
    set_symbol ('90A2', 'cyto loc', 1);
    set_symbol ('90A3', 'cyto loc', 1);
    set_symbol ('90A4', 'cyto loc', 1);
    set_symbol ('90A5', 'cyto loc', 1);
    set_symbol ('90A6', 'cyto loc', 1);
    set_symbol ('90A7', 'cyto loc', 1);
    set_symbol ('90B1', 'cyto loc', 1);
    set_symbol ('90B2', 'cyto loc', 1);
    set_symbol ('90B3', 'cyto loc', 1);
    set_symbol ('90B4', 'cyto loc', 1);
    set_symbol ('90B5', 'cyto loc', 1);
    set_symbol ('90B6', 'cyto loc', 1);
    set_symbol ('90B7', 'cyto loc', 1);
    set_symbol ('90B8', 'cyto loc', 1);
    set_symbol ('90C1', 'cyto loc', 1);
    set_symbol ('90C2', 'cyto loc', 1);
    set_symbol ('90C3', 'cyto loc', 1);
    set_symbol ('90C4', 'cyto loc', 1);
    set_symbol ('90C5', 'cyto loc', 1);
    set_symbol ('90C6', 'cyto loc', 1);
    set_symbol ('90C7', 'cyto loc', 1);
    set_symbol ('90C8', 'cyto loc', 1);
    set_symbol ('90C9', 'cyto loc', 1);
    set_symbol ('90C10', 'cyto loc', 1);
    set_symbol ('90D1', 'cyto loc', 1);
    set_symbol ('90D2', 'cyto loc', 1);
    set_symbol ('90D3', 'cyto loc', 1);
    set_symbol ('90D4', 'cyto loc', 1);
    set_symbol ('90D5', 'cyto loc', 1);
    set_symbol ('90D6', 'cyto loc', 1);
    set_symbol ('90E1', 'cyto loc', 1);
    set_symbol ('90E2', 'cyto loc', 1);
    set_symbol ('90E3', 'cyto loc', 1);
    set_symbol ('90E4', 'cyto loc', 1);
    set_symbol ('90E5', 'cyto loc', 1);
    set_symbol ('90E6', 'cyto loc', 1);
    set_symbol ('90E7', 'cyto loc', 1);
    set_symbol ('90F1', 'cyto loc', 1);
    set_symbol ('90F2', 'cyto loc', 1);
    set_symbol ('90F3', 'cyto loc', 1);
    set_symbol ('90F4', 'cyto loc', 1);
    set_symbol ('90F5', 'cyto loc', 1);
    set_symbol ('90F6', 'cyto loc', 1);
    set_symbol ('90F7', 'cyto loc', 1);
    set_symbol ('90F8', 'cyto loc', 1);
    set_symbol ('90F9', 'cyto loc', 1);
    set_symbol ('90F10', 'cyto loc', 1);
    set_symbol ('90F11', 'cyto loc', 1);
    set_symbol ('91A1', 'cyto loc', 1);
    set_symbol ('91A2', 'cyto loc', 1);
    set_symbol ('91A3', 'cyto loc', 1);
    set_symbol ('91A4', 'cyto loc', 1);
    set_symbol ('91A5', 'cyto loc', 1);
    set_symbol ('91A6', 'cyto loc', 1);
    set_symbol ('91A7', 'cyto loc', 1);
    set_symbol ('91A8', 'cyto loc', 1);
    set_symbol ('91B1', 'cyto loc', 1);
    set_symbol ('91B2', 'cyto loc', 1);
    set_symbol ('91B3', 'cyto loc', 1);
    set_symbol ('91B4', 'cyto loc', 1);
    set_symbol ('91B5', 'cyto loc', 1);
    set_symbol ('91B6', 'cyto loc', 1);
    set_symbol ('91B7', 'cyto loc', 1);
    set_symbol ('91B8', 'cyto loc', 1);
    set_symbol ('91C1', 'cyto loc', 1);
    set_symbol ('91C2', 'cyto loc', 1);
    set_symbol ('91C3', 'cyto loc', 1);
    set_symbol ('91C4', 'cyto loc', 1);
    set_symbol ('91C5', 'cyto loc', 1);
    set_symbol ('91C6', 'cyto loc', 1);
    set_symbol ('91C7', 'cyto loc', 1);
    set_symbol ('91D1', 'cyto loc', 1);
    set_symbol ('91D2', 'cyto loc', 1);
    set_symbol ('91D3', 'cyto loc', 1);
    set_symbol ('91D4', 'cyto loc', 1);
    set_symbol ('91D5', 'cyto loc', 1);
    set_symbol ('91E1', 'cyto loc', 1);
    set_symbol ('91E2', 'cyto loc', 1);
    set_symbol ('91E3', 'cyto loc', 1);
    set_symbol ('91E4', 'cyto loc', 1);
    set_symbol ('91E5', 'cyto loc', 1);
    set_symbol ('91E6', 'cyto loc', 1);
    set_symbol ('91F1', 'cyto loc', 1);
    set_symbol ('91F2', 'cyto loc', 1);
    set_symbol ('91F3', 'cyto loc', 1);
    set_symbol ('91F4', 'cyto loc', 1);
    set_symbol ('91F5', 'cyto loc', 1);
    set_symbol ('91F6', 'cyto loc', 1);
    set_symbol ('91F7', 'cyto loc', 1);
    set_symbol ('91F8', 'cyto loc', 1);
    set_symbol ('91F9', 'cyto loc', 1);
    set_symbol ('91F10', 'cyto loc', 1);
    set_symbol ('91F11', 'cyto loc', 1);
    set_symbol ('91F12', 'cyto loc', 1);
    set_symbol ('91F13', 'cyto loc', 1);
    set_symbol ('92A1', 'cyto loc', 1);
    set_symbol ('92A2', 'cyto loc', 1);
    set_symbol ('92A3', 'cyto loc', 1);
    set_symbol ('92A4', 'cyto loc', 1);
    set_symbol ('92A5', 'cyto loc', 1);
    set_symbol ('92A6', 'cyto loc', 1);
    set_symbol ('92A7', 'cyto loc', 1);
    set_symbol ('92A8', 'cyto loc', 1);
    set_symbol ('92A9', 'cyto loc', 1);
    set_symbol ('92A10', 'cyto loc', 1);
    set_symbol ('92A11', 'cyto loc', 1);
    set_symbol ('92A12', 'cyto loc', 1);
    set_symbol ('92A13', 'cyto loc', 1);
    set_symbol ('92A14', 'cyto loc', 1);
    set_symbol ('92B1', 'cyto loc', 1);
    set_symbol ('92B2', 'cyto loc', 1);
    set_symbol ('92B3', 'cyto loc', 1);
    set_symbol ('92B4', 'cyto loc', 1);
    set_symbol ('92B5', 'cyto loc', 1);
    set_symbol ('92B6', 'cyto loc', 1);
    set_symbol ('92B7', 'cyto loc', 1);
    set_symbol ('92B8', 'cyto loc', 1);
    set_symbol ('92B9', 'cyto loc', 1);
    set_symbol ('92B10', 'cyto loc', 1);
    set_symbol ('92B11', 'cyto loc', 1);
    set_symbol ('92C1', 'cyto loc', 1);
    set_symbol ('92C2', 'cyto loc', 1);
    set_symbol ('92C3', 'cyto loc', 1);
    set_symbol ('92C4', 'cyto loc', 1);
    set_symbol ('92C5', 'cyto loc', 1);
    set_symbol ('92C6', 'cyto loc', 1);
    set_symbol ('92D1', 'cyto loc', 1);
    set_symbol ('92D2', 'cyto loc', 1);
    set_symbol ('92D3', 'cyto loc', 1);
    set_symbol ('92D4', 'cyto loc', 1);
    set_symbol ('92D5', 'cyto loc', 1);
    set_symbol ('92D6', 'cyto loc', 1);
    set_symbol ('92D7', 'cyto loc', 1);
    set_symbol ('92D8', 'cyto loc', 1);
    set_symbol ('92D9', 'cyto loc', 1);
    set_symbol ('92E1', 'cyto loc', 1);
    set_symbol ('92E2', 'cyto loc', 1);
    set_symbol ('92E3', 'cyto loc', 1);
    set_symbol ('92E4', 'cyto loc', 1);
    set_symbol ('92E5', 'cyto loc', 1);
    set_symbol ('92E6', 'cyto loc', 1);
    set_symbol ('92E7', 'cyto loc', 1);
    set_symbol ('92E8', 'cyto loc', 1);
    set_symbol ('92E9', 'cyto loc', 1);
    set_symbol ('92E10', 'cyto loc', 1);
    set_symbol ('92E11', 'cyto loc', 1);
    set_symbol ('92E12', 'cyto loc', 1);
    set_symbol ('92E13', 'cyto loc', 1);
    set_symbol ('92E14', 'cyto loc', 1);
    set_symbol ('92E15', 'cyto loc', 1);
    set_symbol ('92F1', 'cyto loc', 1);
    set_symbol ('92F2', 'cyto loc', 1);
    set_symbol ('92F3', 'cyto loc', 1);
    set_symbol ('92F4', 'cyto loc', 1);
    set_symbol ('92F5', 'cyto loc', 1);
    set_symbol ('92F6', 'cyto loc', 1);
    set_symbol ('92F7', 'cyto loc', 1);
    set_symbol ('92F8', 'cyto loc', 1);
    set_symbol ('92F9', 'cyto loc', 1);
    set_symbol ('92F10', 'cyto loc', 1);
    set_symbol ('92F11', 'cyto loc', 1);
    set_symbol ('92F12', 'cyto loc', 1);
    set_symbol ('92F13', 'cyto loc', 1);
    set_symbol ('93A1', 'cyto loc', 1);
    set_symbol ('93A2', 'cyto loc', 1);
    set_symbol ('93A3', 'cyto loc', 1);
    set_symbol ('93A4', 'cyto loc', 1);
    set_symbol ('93A5', 'cyto loc', 1);
    set_symbol ('93A6', 'cyto loc', 1);
    set_symbol ('93A7', 'cyto loc', 1);
    set_symbol ('93B1', 'cyto loc', 1);
    set_symbol ('93B2', 'cyto loc', 1);
    set_symbol ('93B3', 'cyto loc', 1);
    set_symbol ('93B4', 'cyto loc', 1);
    set_symbol ('93B5', 'cyto loc', 1);
    set_symbol ('93B6', 'cyto loc', 1);
    set_symbol ('93B7', 'cyto loc', 1);
    set_symbol ('93B8', 'cyto loc', 1);
    set_symbol ('93B9', 'cyto loc', 1);
    set_symbol ('93B10', 'cyto loc', 1);
    set_symbol ('93B11', 'cyto loc', 1);
    set_symbol ('93B12', 'cyto loc', 1);
    set_symbol ('93B13', 'cyto loc', 1);
    set_symbol ('93C1', 'cyto loc', 1);
    set_symbol ('93C2', 'cyto loc', 1);
    set_symbol ('93C3', 'cyto loc', 1);
    set_symbol ('93C4', 'cyto loc', 1);
    set_symbol ('93C5', 'cyto loc', 1);
    set_symbol ('93C6', 'cyto loc', 1);
    set_symbol ('93C7', 'cyto loc', 1);
    set_symbol ('93D1', 'cyto loc', 1);
    set_symbol ('93D2', 'cyto loc', 1);
    set_symbol ('93D3', 'cyto loc', 1);
    set_symbol ('93D4', 'cyto loc', 1);
    set_symbol ('93D5', 'cyto loc', 1);
    set_symbol ('93D6', 'cyto loc', 1);
    set_symbol ('93D7', 'cyto loc', 1);
    set_symbol ('93D8', 'cyto loc', 1);
    set_symbol ('93D9', 'cyto loc', 1);
    set_symbol ('93D10', 'cyto loc', 1);
    set_symbol ('93E1', 'cyto loc', 1);
    set_symbol ('93E2', 'cyto loc', 1);
    set_symbol ('93E3', 'cyto loc', 1);
    set_symbol ('93E4', 'cyto loc', 1);
    set_symbol ('93E5', 'cyto loc', 1);
    set_symbol ('93E6', 'cyto loc', 1);
    set_symbol ('93E7', 'cyto loc', 1);
    set_symbol ('93E8', 'cyto loc', 1);
    set_symbol ('93E9', 'cyto loc', 1);
    set_symbol ('93E10', 'cyto loc', 1);
    set_symbol ('93E11', 'cyto loc', 1);
    set_symbol ('93F1', 'cyto loc', 1);
    set_symbol ('93F2', 'cyto loc', 1);
    set_symbol ('93F3', 'cyto loc', 1);
    set_symbol ('93F4', 'cyto loc', 1);
    set_symbol ('93F5', 'cyto loc', 1);
    set_symbol ('93F6', 'cyto loc', 1);
    set_symbol ('93F7', 'cyto loc', 1);
    set_symbol ('93F8', 'cyto loc', 1);
    set_symbol ('93F9', 'cyto loc', 1);
    set_symbol ('93F10', 'cyto loc', 1);
    set_symbol ('93F11', 'cyto loc', 1);
    set_symbol ('93F12', 'cyto loc', 1);
    set_symbol ('93F13', 'cyto loc', 1);
    set_symbol ('93F14', 'cyto loc', 1);
    set_symbol ('94A1', 'cyto loc', 1);
    set_symbol ('94A2', 'cyto loc', 1);
    set_symbol ('94A3', 'cyto loc', 1);
    set_symbol ('94A4', 'cyto loc', 1);
    set_symbol ('94A5', 'cyto loc', 1);
    set_symbol ('94A6', 'cyto loc', 1);
    set_symbol ('94A7', 'cyto loc', 1);
    set_symbol ('94A8', 'cyto loc', 1);
    set_symbol ('94A9', 'cyto loc', 1);
    set_symbol ('94A10', 'cyto loc', 1);
    set_symbol ('94A11', 'cyto loc', 1);
    set_symbol ('94A12', 'cyto loc', 1);
    set_symbol ('94A13', 'cyto loc', 1);
    set_symbol ('94A14', 'cyto loc', 1);
    set_symbol ('94A15', 'cyto loc', 1);
    set_symbol ('94A16', 'cyto loc', 1);
    set_symbol ('94B1', 'cyto loc', 1);
    set_symbol ('94B2', 'cyto loc', 1);
    set_symbol ('94B3', 'cyto loc', 1);
    set_symbol ('94B4', 'cyto loc', 1);
    set_symbol ('94B5', 'cyto loc', 1);
    set_symbol ('94B6', 'cyto loc', 1);
    set_symbol ('94B7', 'cyto loc', 1);
    set_symbol ('94B8', 'cyto loc', 1);
    set_symbol ('94B9', 'cyto loc', 1);
    set_symbol ('94B10', 'cyto loc', 1);
    set_symbol ('94B11', 'cyto loc', 1);
    set_symbol ('94C1', 'cyto loc', 1);
    set_symbol ('94C2', 'cyto loc', 1);
    set_symbol ('94C3', 'cyto loc', 1);
    set_symbol ('94C4', 'cyto loc', 1);
    set_symbol ('94C5', 'cyto loc', 1);
    set_symbol ('94C6', 'cyto loc', 1);
    set_symbol ('94C7', 'cyto loc', 1);
    set_symbol ('94C8', 'cyto loc', 1);
    set_symbol ('94C9', 'cyto loc', 1);
    set_symbol ('94D1', 'cyto loc', 1);
    set_symbol ('94D2', 'cyto loc', 1);
    set_symbol ('94D3', 'cyto loc', 1);
    set_symbol ('94D4', 'cyto loc', 1);
    set_symbol ('94D5', 'cyto loc', 1);
    set_symbol ('94D6', 'cyto loc', 1);
    set_symbol ('94D7', 'cyto loc', 1);
    set_symbol ('94D8', 'cyto loc', 1);
    set_symbol ('94D9', 'cyto loc', 1);
    set_symbol ('94D10', 'cyto loc', 1);
    set_symbol ('94D11', 'cyto loc', 1);
    set_symbol ('94D12', 'cyto loc', 1);
    set_symbol ('94D13', 'cyto loc', 1);
    set_symbol ('94E1', 'cyto loc', 1);
    set_symbol ('94E2', 'cyto loc', 1);
    set_symbol ('94E3', 'cyto loc', 1);
    set_symbol ('94E4', 'cyto loc', 1);
    set_symbol ('94E5', 'cyto loc', 1);
    set_symbol ('94E6', 'cyto loc', 1);
    set_symbol ('94E7', 'cyto loc', 1);
    set_symbol ('94E8', 'cyto loc', 1);
    set_symbol ('94E9', 'cyto loc', 1);
    set_symbol ('94E10', 'cyto loc', 1);
    set_symbol ('94E11', 'cyto loc', 1);
    set_symbol ('94E12', 'cyto loc', 1);
    set_symbol ('94E13', 'cyto loc', 1);
    set_symbol ('94F1', 'cyto loc', 1);
    set_symbol ('94F2', 'cyto loc', 1);
    set_symbol ('94F3', 'cyto loc', 1);
    set_symbol ('94F4', 'cyto loc', 1);
    set_symbol ('94F5', 'cyto loc', 1);
    set_symbol ('94F6', 'cyto loc', 1);
    set_symbol ('95A1', 'cyto loc', 1);
    set_symbol ('95A2', 'cyto loc', 1);
    set_symbol ('95A3', 'cyto loc', 1);
    set_symbol ('95A4', 'cyto loc', 1);
    set_symbol ('95A5', 'cyto loc', 1);
    set_symbol ('95A6', 'cyto loc', 1);
    set_symbol ('95A7', 'cyto loc', 1);
    set_symbol ('95A8', 'cyto loc', 1);
    set_symbol ('95A9', 'cyto loc', 1);
    set_symbol ('95A10', 'cyto loc', 1);
    set_symbol ('95B1', 'cyto loc', 1);
    set_symbol ('95B2', 'cyto loc', 1);
    set_symbol ('95B3', 'cyto loc', 1);
    set_symbol ('95B4', 'cyto loc', 1);
    set_symbol ('95B5', 'cyto loc', 1);
    set_symbol ('95B6', 'cyto loc', 1);
    set_symbol ('95B7', 'cyto loc', 1);
    set_symbol ('95B8', 'cyto loc', 1);
    set_symbol ('95B9', 'cyto loc', 1);
    set_symbol ('95C1', 'cyto loc', 1);
    set_symbol ('95C2', 'cyto loc', 1);
    set_symbol ('95C3', 'cyto loc', 1);
    set_symbol ('95C4', 'cyto loc', 1);
    set_symbol ('95C5', 'cyto loc', 1);
    set_symbol ('95C6', 'cyto loc', 1);
    set_symbol ('95C7', 'cyto loc', 1);
    set_symbol ('95C8', 'cyto loc', 1);
    set_symbol ('95C9', 'cyto loc', 1);
    set_symbol ('95C10', 'cyto loc', 1);
    set_symbol ('95C11', 'cyto loc', 1);
    set_symbol ('95C12', 'cyto loc', 1);
    set_symbol ('95C13', 'cyto loc', 1);
    set_symbol ('95C14', 'cyto loc', 1);
    set_symbol ('95D1', 'cyto loc', 1);
    set_symbol ('95D2', 'cyto loc', 1);
    set_symbol ('95D3', 'cyto loc', 1);
    set_symbol ('95D4', 'cyto loc', 1);
    set_symbol ('95D5', 'cyto loc', 1);
    set_symbol ('95D6', 'cyto loc', 1);
    set_symbol ('95D7', 'cyto loc', 1);
    set_symbol ('95D8', 'cyto loc', 1);
    set_symbol ('95D9', 'cyto loc', 1);
    set_symbol ('95D10', 'cyto loc', 1);
    set_symbol ('95D11', 'cyto loc', 1);
    set_symbol ('95E1', 'cyto loc', 1);
    set_symbol ('95E2', 'cyto loc', 1);
    set_symbol ('95E3', 'cyto loc', 1);
    set_symbol ('95E4', 'cyto loc', 1);
    set_symbol ('95E5', 'cyto loc', 1);
    set_symbol ('95E6', 'cyto loc', 1);
    set_symbol ('95E7', 'cyto loc', 1);
    set_symbol ('95E8', 'cyto loc', 1);
    set_symbol ('95F1', 'cyto loc', 1);
    set_symbol ('95F2', 'cyto loc', 1);
    set_symbol ('95F3', 'cyto loc', 1);
    set_symbol ('95F4', 'cyto loc', 1);
    set_symbol ('95F5', 'cyto loc', 1);
    set_symbol ('95F6', 'cyto loc', 1);
    set_symbol ('95F7', 'cyto loc', 1);
    set_symbol ('95F8', 'cyto loc', 1);
    set_symbol ('95F9', 'cyto loc', 1);
    set_symbol ('95F10', 'cyto loc', 1);
    set_symbol ('95F11', 'cyto loc', 1);
    set_symbol ('95F12', 'cyto loc', 1);
    set_symbol ('95F13', 'cyto loc', 1);
    set_symbol ('95F14', 'cyto loc', 1);
    set_symbol ('95F15', 'cyto loc', 1);
    set_symbol ('96A1', 'cyto loc', 1);
    set_symbol ('96A2', 'cyto loc', 1);
    set_symbol ('96A3', 'cyto loc', 1);
    set_symbol ('96A4', 'cyto loc', 1);
    set_symbol ('96A5', 'cyto loc', 1);
    set_symbol ('96A6', 'cyto loc', 1);
    set_symbol ('96A7', 'cyto loc', 1);
    set_symbol ('96A8', 'cyto loc', 1);
    set_symbol ('96A9', 'cyto loc', 1);
    set_symbol ('96A10', 'cyto loc', 1);
    set_symbol ('96A11', 'cyto loc', 1);
    set_symbol ('96A12', 'cyto loc', 1);
    set_symbol ('96A13', 'cyto loc', 1);
    set_symbol ('96A14', 'cyto loc', 1);
    set_symbol ('96A15', 'cyto loc', 1);
    set_symbol ('96A16', 'cyto loc', 1);
    set_symbol ('96A17', 'cyto loc', 1);
    set_symbol ('96A18', 'cyto loc', 1);
    set_symbol ('96A19', 'cyto loc', 1);
    set_symbol ('96A20', 'cyto loc', 1);
    set_symbol ('96A21', 'cyto loc', 1);
    set_symbol ('96A22', 'cyto loc', 1);
    set_symbol ('96A23', 'cyto loc', 1);
    set_symbol ('96A24', 'cyto loc', 1);
    set_symbol ('96A25', 'cyto loc', 1);
    set_symbol ('96B1', 'cyto loc', 1);
    set_symbol ('96B2', 'cyto loc', 1);
    set_symbol ('96B3', 'cyto loc', 1);
    set_symbol ('96B4', 'cyto loc', 1);
    set_symbol ('96B5', 'cyto loc', 1);
    set_symbol ('96B6', 'cyto loc', 1);
    set_symbol ('96B7', 'cyto loc', 1);
    set_symbol ('96B8', 'cyto loc', 1);
    set_symbol ('96B9', 'cyto loc', 1);
    set_symbol ('96B10', 'cyto loc', 1);
    set_symbol ('96B11', 'cyto loc', 1);
    set_symbol ('96B12', 'cyto loc', 1);
    set_symbol ('96B13', 'cyto loc', 1);
    set_symbol ('96B14', 'cyto loc', 1);
    set_symbol ('96B15', 'cyto loc', 1);
    set_symbol ('96B16', 'cyto loc', 1);
    set_symbol ('96B17', 'cyto loc', 1);
    set_symbol ('96B18', 'cyto loc', 1);
    set_symbol ('96B19', 'cyto loc', 1);
    set_symbol ('96B20', 'cyto loc', 1);
    set_symbol ('96B21', 'cyto loc', 1);
    set_symbol ('96C1', 'cyto loc', 1);
    set_symbol ('96C2', 'cyto loc', 1);
    set_symbol ('96C3', 'cyto loc', 1);
    set_symbol ('96C4', 'cyto loc', 1);
    set_symbol ('96C5', 'cyto loc', 1);
    set_symbol ('96C6', 'cyto loc', 1);
    set_symbol ('96C7', 'cyto loc', 1);
    set_symbol ('96C8', 'cyto loc', 1);
    set_symbol ('96C9', 'cyto loc', 1);
    set_symbol ('96D1', 'cyto loc', 1);
    set_symbol ('96D2', 'cyto loc', 1);
    set_symbol ('96D3', 'cyto loc', 1);
    set_symbol ('96D4', 'cyto loc', 1);
    set_symbol ('96D5', 'cyto loc', 1);
    set_symbol ('96D6', 'cyto loc', 1);
    set_symbol ('96E1', 'cyto loc', 1);
    set_symbol ('96E2', 'cyto loc', 1);
    set_symbol ('96E3', 'cyto loc', 1);
    set_symbol ('96E4', 'cyto loc', 1);
    set_symbol ('96E5', 'cyto loc', 1);
    set_symbol ('96E6', 'cyto loc', 1);
    set_symbol ('96E7', 'cyto loc', 1);
    set_symbol ('96E8', 'cyto loc', 1);
    set_symbol ('96E9', 'cyto loc', 1);
    set_symbol ('96E10', 'cyto loc', 1);
    set_symbol ('96E11', 'cyto loc', 1);
    set_symbol ('96E12', 'cyto loc', 1);
    set_symbol ('96F1', 'cyto loc', 1);
    set_symbol ('96F2', 'cyto loc', 1);
    set_symbol ('96F3', 'cyto loc', 1);
    set_symbol ('96F4', 'cyto loc', 1);
    set_symbol ('96F5', 'cyto loc', 1);
    set_symbol ('96F6', 'cyto loc', 1);
    set_symbol ('96F7', 'cyto loc', 1);
    set_symbol ('96F8', 'cyto loc', 1);
    set_symbol ('96F9', 'cyto loc', 1);
    set_symbol ('96F10', 'cyto loc', 1);
    set_symbol ('96F11', 'cyto loc', 1);
    set_symbol ('96F12', 'cyto loc', 1);
    set_symbol ('96F13', 'cyto loc', 1);
    set_symbol ('96F14', 'cyto loc', 1);
    set_symbol ('97A1', 'cyto loc', 1);
    set_symbol ('97A2', 'cyto loc', 1);
    set_symbol ('97A3', 'cyto loc', 1);
    set_symbol ('97A4', 'cyto loc', 1);
    set_symbol ('97A5', 'cyto loc', 1);
    set_symbol ('97A6', 'cyto loc', 1);
    set_symbol ('97A7', 'cyto loc', 1);
    set_symbol ('97A8', 'cyto loc', 1);
    set_symbol ('97A9', 'cyto loc', 1);
    set_symbol ('97A10', 'cyto loc', 1);
    set_symbol ('97B1', 'cyto loc', 1);
    set_symbol ('97B2', 'cyto loc', 1);
    set_symbol ('97B3', 'cyto loc', 1);
    set_symbol ('97B4', 'cyto loc', 1);
    set_symbol ('97B5', 'cyto loc', 1);
    set_symbol ('97B6', 'cyto loc', 1);
    set_symbol ('97B7', 'cyto loc', 1);
    set_symbol ('97B8', 'cyto loc', 1);
    set_symbol ('97B9', 'cyto loc', 1);
    set_symbol ('97B10', 'cyto loc', 1);
    set_symbol ('97C1', 'cyto loc', 1);
    set_symbol ('97C2', 'cyto loc', 1);
    set_symbol ('97C3', 'cyto loc', 1);
    set_symbol ('97C4', 'cyto loc', 1);
    set_symbol ('97C5', 'cyto loc', 1);
    set_symbol ('97D1', 'cyto loc', 1);
    set_symbol ('97D2', 'cyto loc', 1);
    set_symbol ('97D3', 'cyto loc', 1);
    set_symbol ('97D4', 'cyto loc', 1);
    set_symbol ('97D5', 'cyto loc', 1);
    set_symbol ('97D6', 'cyto loc', 1);
    set_symbol ('97D7', 'cyto loc', 1);
    set_symbol ('97D8', 'cyto loc', 1);
    set_symbol ('97D9', 'cyto loc', 1);
    set_symbol ('97D10', 'cyto loc', 1);
    set_symbol ('97D11', 'cyto loc', 1);
    set_symbol ('97D12', 'cyto loc', 1);
    set_symbol ('97D13', 'cyto loc', 1);
    set_symbol ('97D14', 'cyto loc', 1);
    set_symbol ('97D15', 'cyto loc', 1);
    set_symbol ('97E1', 'cyto loc', 1);
    set_symbol ('97E2', 'cyto loc', 1);
    set_symbol ('97E3', 'cyto loc', 1);
    set_symbol ('97E4', 'cyto loc', 1);
    set_symbol ('97E5', 'cyto loc', 1);
    set_symbol ('97E6', 'cyto loc', 1);
    set_symbol ('97E7', 'cyto loc', 1);
    set_symbol ('97E8', 'cyto loc', 1);
    set_symbol ('97E9', 'cyto loc', 1);
    set_symbol ('97E10', 'cyto loc', 1);
    set_symbol ('97E11', 'cyto loc', 1);
    set_symbol ('97F1', 'cyto loc', 1);
    set_symbol ('97F2', 'cyto loc', 1);
    set_symbol ('97F3', 'cyto loc', 1);
    set_symbol ('97F4', 'cyto loc', 1);
    set_symbol ('97F5', 'cyto loc', 1);
    set_symbol ('97F6', 'cyto loc', 1);
    set_symbol ('97F7', 'cyto loc', 1);
    set_symbol ('97F8', 'cyto loc', 1);
    set_symbol ('97F9', 'cyto loc', 1);
    set_symbol ('97F10', 'cyto loc', 1);
    set_symbol ('97F11', 'cyto loc', 1);
    set_symbol ('98A1', 'cyto loc', 1);
    set_symbol ('98A2', 'cyto loc', 1);
    set_symbol ('98A3', 'cyto loc', 1);
    set_symbol ('98A4', 'cyto loc', 1);
    set_symbol ('98A5', 'cyto loc', 1);
    set_symbol ('98A6', 'cyto loc', 1);
    set_symbol ('98A7', 'cyto loc', 1);
    set_symbol ('98A8', 'cyto loc', 1);
    set_symbol ('98A9', 'cyto loc', 1);
    set_symbol ('98A10', 'cyto loc', 1);
    set_symbol ('98A11', 'cyto loc', 1);
    set_symbol ('98A12', 'cyto loc', 1);
    set_symbol ('98A13', 'cyto loc', 1);
    set_symbol ('98A14', 'cyto loc', 1);
    set_symbol ('98A15', 'cyto loc', 1);
    set_symbol ('98B1', 'cyto loc', 1);
    set_symbol ('98B2', 'cyto loc', 1);
    set_symbol ('98B3', 'cyto loc', 1);
    set_symbol ('98B4', 'cyto loc', 1);
    set_symbol ('98B5', 'cyto loc', 1);
    set_symbol ('98B6', 'cyto loc', 1);
    set_symbol ('98B7', 'cyto loc', 1);
    set_symbol ('98B8', 'cyto loc', 1);
    set_symbol ('98C1', 'cyto loc', 1);
    set_symbol ('98C2', 'cyto loc', 1);
    set_symbol ('98C3', 'cyto loc', 1);
    set_symbol ('98C4', 'cyto loc', 1);
    set_symbol ('98C5', 'cyto loc', 1);
    set_symbol ('98D1', 'cyto loc', 1);
    set_symbol ('98D2', 'cyto loc', 1);
    set_symbol ('98D3', 'cyto loc', 1);
    set_symbol ('98D4', 'cyto loc', 1);
    set_symbol ('98D5', 'cyto loc', 1);
    set_symbol ('98D6', 'cyto loc', 1);
    set_symbol ('98D7', 'cyto loc', 1);
    set_symbol ('98E1', 'cyto loc', 1);
    set_symbol ('98E2', 'cyto loc', 1);
    set_symbol ('98E3', 'cyto loc', 1);
    set_symbol ('98E4', 'cyto loc', 1);
    set_symbol ('98E5', 'cyto loc', 1);
    set_symbol ('98E6', 'cyto loc', 1);
    set_symbol ('98F1', 'cyto loc', 1);
    set_symbol ('98F2', 'cyto loc', 1);
    set_symbol ('98F3', 'cyto loc', 1);
    set_symbol ('98F4', 'cyto loc', 1);
    set_symbol ('98F5', 'cyto loc', 1);
    set_symbol ('98F6', 'cyto loc', 1);
    set_symbol ('98F7', 'cyto loc', 1);
    set_symbol ('98F8', 'cyto loc', 1);
    set_symbol ('98F9', 'cyto loc', 1);
    set_symbol ('98F10', 'cyto loc', 1);
    set_symbol ('98F11', 'cyto loc', 1);
    set_symbol ('98F12', 'cyto loc', 1);
    set_symbol ('98F13', 'cyto loc', 1);
    set_symbol ('98F14', 'cyto loc', 1);
    set_symbol ('99A1', 'cyto loc', 1);
    set_symbol ('99A2', 'cyto loc', 1);
    set_symbol ('99A3', 'cyto loc', 1);
    set_symbol ('99A4', 'cyto loc', 1);
    set_symbol ('99A5', 'cyto loc', 1);
    set_symbol ('99A6', 'cyto loc', 1);
    set_symbol ('99A7', 'cyto loc', 1);
    set_symbol ('99A8', 'cyto loc', 1);
    set_symbol ('99A9', 'cyto loc', 1);
    set_symbol ('99A10', 'cyto loc', 1);
    set_symbol ('99A11', 'cyto loc', 1);
    set_symbol ('99B1', 'cyto loc', 1);
    set_symbol ('99B2', 'cyto loc', 1);
    set_symbol ('99B3', 'cyto loc', 1);
    set_symbol ('99B4', 'cyto loc', 1);
    set_symbol ('99B5', 'cyto loc', 1);
    set_symbol ('99B6', 'cyto loc', 1);
    set_symbol ('99B7', 'cyto loc', 1);
    set_symbol ('99B8', 'cyto loc', 1);
    set_symbol ('99B9', 'cyto loc', 1);
    set_symbol ('99B10', 'cyto loc', 1);
    set_symbol ('99B11', 'cyto loc', 1);
    set_symbol ('99C1', 'cyto loc', 1);
    set_symbol ('99C2', 'cyto loc', 1);
    set_symbol ('99C3', 'cyto loc', 1);
    set_symbol ('99C4', 'cyto loc', 1);
    set_symbol ('99C5', 'cyto loc', 1);
    set_symbol ('99C6', 'cyto loc', 1);
    set_symbol ('99C7', 'cyto loc', 1);
    set_symbol ('99C8', 'cyto loc', 1);
    set_symbol ('99D1', 'cyto loc', 1);
    set_symbol ('99D2', 'cyto loc', 1);
    set_symbol ('99D3', 'cyto loc', 1);
    set_symbol ('99D4', 'cyto loc', 1);
    set_symbol ('99D5', 'cyto loc', 1);
    set_symbol ('99D6', 'cyto loc', 1);
    set_symbol ('99D7', 'cyto loc', 1);
    set_symbol ('99D8', 'cyto loc', 1);
    set_symbol ('99D9', 'cyto loc', 1);
    set_symbol ('99E1', 'cyto loc', 1);
    set_symbol ('99E2', 'cyto loc', 1);
    set_symbol ('99E3', 'cyto loc', 1);
    set_symbol ('99E4', 'cyto loc', 1);
    set_symbol ('99E5', 'cyto loc', 1);
    set_symbol ('99F1', 'cyto loc', 1);
    set_symbol ('99F2', 'cyto loc', 1);
    set_symbol ('99F3', 'cyto loc', 1);
    set_symbol ('99F4', 'cyto loc', 1);
    set_symbol ('99F5', 'cyto loc', 1);
    set_symbol ('99F6', 'cyto loc', 1);
    set_symbol ('99F7', 'cyto loc', 1);
    set_symbol ('99F8', 'cyto loc', 1);
    set_symbol ('99F9', 'cyto loc', 1);
    set_symbol ('99F10', 'cyto loc', 1);
    set_symbol ('99F11', 'cyto loc', 1);
    set_symbol ('100A1', 'cyto loc', 1);
    set_symbol ('100A2', 'cyto loc', 1);
    set_symbol ('100A3', 'cyto loc', 1);
    set_symbol ('100A4', 'cyto loc', 1);
    set_symbol ('100A5', 'cyto loc', 1);
    set_symbol ('100A6', 'cyto loc', 1);
    set_symbol ('100A7', 'cyto loc', 1);
    set_symbol ('100B1', 'cyto loc', 1);
    set_symbol ('100B2', 'cyto loc', 1);
    set_symbol ('100B3', 'cyto loc', 1);
    set_symbol ('100B4', 'cyto loc', 1);
    set_symbol ('100B5', 'cyto loc', 1);
    set_symbol ('100B6', 'cyto loc', 1);
    set_symbol ('100B7', 'cyto loc', 1);
    set_symbol ('100B8', 'cyto loc', 1);
    set_symbol ('100B9', 'cyto loc', 1);
    set_symbol ('100C1', 'cyto loc', 1);
    set_symbol ('100C2', 'cyto loc', 1);
    set_symbol ('100C3', 'cyto loc', 1);
    set_symbol ('100C4', 'cyto loc', 1);
    set_symbol ('100C5', 'cyto loc', 1);
    set_symbol ('100C6', 'cyto loc', 1);
    set_symbol ('100C7', 'cyto loc', 1);
    set_symbol ('100D1', 'cyto loc', 1);
    set_symbol ('100D2', 'cyto loc', 1);
    set_symbol ('100D3', 'cyto loc', 1);
    set_symbol ('100D4', 'cyto loc', 1);
    set_symbol ('100E1', 'cyto loc', 1);
    set_symbol ('100E2', 'cyto loc', 1);
    set_symbol ('100E3', 'cyto loc', 1);
    set_symbol ('100F1', 'cyto loc', 1);
    set_symbol ('100F2', 'cyto loc', 1);
    set_symbol ('100F3', 'cyto loc', 1);
    set_symbol ('100F4', 'cyto loc', 1);
    set_symbol ('100F5', 'cyto loc', 1);
    set_symbol ('101F1', 'cyto loc', 1);
    set_symbol ('102A1', 'cyto loc', 1);
    set_symbol ('102A2', 'cyto loc', 1);
    set_symbol ('102A3', 'cyto loc', 1);
    set_symbol ('102A4', 'cyto loc', 1);
    set_symbol ('102A5', 'cyto loc', 1);
    set_symbol ('102A6', 'cyto loc', 1);
    set_symbol ('102A7', 'cyto loc', 1);
    set_symbol ('102A8', 'cyto loc', 1);
    set_symbol ('102B1', 'cyto loc', 1);
    set_symbol ('102B2', 'cyto loc', 1);
    set_symbol ('102B3', 'cyto loc', 1);
    set_symbol ('102B4', 'cyto loc', 1);
    set_symbol ('102B5', 'cyto loc', 1);
    set_symbol ('102B6', 'cyto loc', 1);
    set_symbol ('102B7', 'cyto loc', 1);
    set_symbol ('102B8', 'cyto loc', 1);
    set_symbol ('102C1', 'cyto loc', 1);
    set_symbol ('102C2', 'cyto loc', 1);
    set_symbol ('102C3', 'cyto loc', 1);
    set_symbol ('102C4', 'cyto loc', 1);
    set_symbol ('102C5', 'cyto loc', 1);
    set_symbol ('102C6', 'cyto loc', 1);
    set_symbol ('102D1', 'cyto loc', 1);
    set_symbol ('102D2', 'cyto loc', 1);
    set_symbol ('102D3', 'cyto loc', 1);
    set_symbol ('102D4', 'cyto loc', 1);
    set_symbol ('102D5', 'cyto loc', 1);
    set_symbol ('102D6', 'cyto loc', 1);
    set_symbol ('102E1', 'cyto loc', 1);
    set_symbol ('102E2', 'cyto loc', 1);
    set_symbol ('102E3', 'cyto loc', 1);
    set_symbol ('102E4', 'cyto loc', 1);
    set_symbol ('102E5', 'cyto loc', 1);
    set_symbol ('102E6', 'cyto loc', 1);
    set_symbol ('102E7', 'cyto loc', 1);
    set_symbol ('102F1', 'cyto loc', 1);
    set_symbol ('102F2', 'cyto loc', 1);
    set_symbol ('102F3', 'cyto loc', 1);
    set_symbol ('102F4', 'cyto loc', 1);
    set_symbol ('102F5', 'cyto loc', 1);
    set_symbol ('102F6', 'cyto loc', 1);
    set_symbol ('102F7', 'cyto loc', 1);
    set_symbol ('102F8', 'cyto loc', 1);

# The telomeres.  This is a subset of the cytolocations.

    set_symbol ('YLt', 'telomere', 1);
    set_symbol ('YSt', 'telomere', 1);
    set_symbol ('1Lt', 'telomere', 1);
    set_symbol ('1Rt', 'telomere', 1);
    set_symbol ('2Lt', 'telomere', 1);
    set_symbol ('2Rt', 'telomere', 1);
    set_symbol ('3Lt', 'telomere', 1);
    set_symbol ('3Rt', 'telomere', 1);
    set_symbol ('4Lt', 'telomere', 1);
    set_symbol ('4Rt', 'telomere', 1);

# complete chromosomes for Dmel
    set_symbol ('X', 'chromosome', 1);
    set_symbol ('Y', 'chromosome', 1);
    set_symbol ('2', 'chromosome', 1);
    set_symbol ('3', 'chromosome', 1);
    set_symbol ('4', 'chromosome', 1);

# chromosome arms for Dmel (should maybe be replaced by query to chado to get current values if possible, especially when used as part of sequence location, although maybe only want a subset to be allowed in curation in which case having the subset here may be fine)

# this is for the 'traditional' arms that can apply both to sequence location AND also arm location based on genetic mapping. A separate 'chromosome arm scaffold' lookup is used for arms just valid for sequence location
    set_symbol ('X', 'chromosome arm', 1);
    set_symbol ('Y', 'chromosome arm', 1);
    set_symbol ('2L', 'chromosome arm', 1);
    set_symbol ('2R', 'chromosome arm', 1);
    set_symbol ('3L', 'chromosome arm', 1);
    set_symbol ('3R', 'chromosome arm', 1);
    set_symbol ('4', 'chromosome arm', 1);
#    set_symbol ('', 'chromosome arm', 1);

# this set is for the arms that are valid for sequence locations

    set_symbol ('211000022278279', 'chromosome arm scaffold', 1);
    set_symbol ('211000022278436', 'chromosome arm scaffold', 1);
    set_symbol ('211000022278449', 'chromosome arm scaffold', 1);
    set_symbol ('211000022278760', 'chromosome arm scaffold', 1);
    set_symbol ('211000022279165', 'chromosome arm scaffold', 1);
    set_symbol ('211000022279188', 'chromosome arm scaffold', 1);
    set_symbol ('211000022279264', 'chromosome arm scaffold', 1);
    set_symbol ('211000022279392', 'chromosome arm scaffold', 1);
    set_symbol ('211000022279681', 'chromosome arm scaffold', 1);
    set_symbol ('211000022280328', 'chromosome arm scaffold', 1);
    set_symbol ('211000022280341', 'chromosome arm scaffold', 1);
    set_symbol ('211000022280347', 'chromosome arm scaffold', 1);
    set_symbol ('211000022280481', 'chromosome arm scaffold', 1);
    set_symbol ('211000022280494', 'chromosome arm scaffold', 1);
    set_symbol ('211000022280703', 'chromosome arm scaffold', 1);
    set_symbol ('Unmapped_Scaffold_8_D1580_D1567', 'chromosome arm scaffold', 1);
    set_symbol ('mitochondrion_genome', 'chromosome arm scaffold', 1);
    set_symbol ('rDNA', 'chromosome arm scaffold', 1);
    
    
# set allowed value for fields that only have a single allowed value
# genome release number
	set_symbol ('genome_release', 'current_value', '6');
# allowed value for Information on availablity field
	set_symbol ('availablity', 'current_value', 'Stated to be lost.');
# allowed value for MA21f
	set_symbol ('MA21f_value', 'current_value', 'y');
# fields that can only contain 'y'
	set_symbol ('positive', 'current_value', 'y');
# fields that can only contain 'n'
	set_symbol ('negative', 'current_value', 'n');
	
# allowed value for IN2b, plus double check its still a current psi-mi term
	set_symbol ('IN2b_value', 'current_value', 'physical association');
	valid_symbol ((valid_symbol ('IN2b_value', 'current_value')), 'MI:default') or print "***WARNING: the default value for IN2b, \'" . valid_symbol ('IN2b_value', 'current_value') . "\' is no longer a valid PSI-MI term, this will need fixing in the proforma and then Peeves will need altering to cope.\n";

# commonly used values for IN7c, plus double check that they are still current psi-mi terms

	my @IN7c_role_common = ('sufficient binding region', 'necessary binding region', 'mutation disrupting interaction', 'mutation decreasing interaction', 'mutation increasing interaction', 'enzyme target', 'unspecified role');

	foreach my $term (@IN7c_role_common) {

		set_symbol ($term, 'IN7c_role_common', '1');
		valid_symbol ($term, 'MI:default') or print "MAJOR PEEVES ERROR in basic ontology processing: the '$term' term listed in Peeves as a common value for IN7c is no longer a valid PSI-MI term, Peeves will need altering to cope (probably by replacing this obsolete term with a new valid one).\n\n";

	}

# commonly used values for IN7d, plus double check that they are still current psi-mi terms

	my @IN7d_role_common = ('unspecified role');

	foreach my $term (@IN7d_role_common) {

		set_symbol ($term, 'IN7d_role_common', '1');
		valid_symbol ($term, 'MI:default') or print "MAJOR PEEVES ERROR in basic ontology processing: the '$term' term listed in Peeves as a common value for IN7d is no longer a valid PSI-MI term, Peeves will need altering to cope (probably by replacing this obsolete term with a new valid one).\n\n";

	}

# allowed value for HH14b, plus double check its still a current chado database name
	set_symbol ('HH14b_value', 'current_value', 'BDSC_HD');
	valid_symbol ((valid_symbol ('HH14b_value', 'current_value')), 'chado database name') or print "***WARNING: the default value for HH14b, \'" . valid_symbol ('HH14b_value', 'current_value') . "\' is no longer a valid chado database name, this will need fixing in the proforma and then Peeves will need altering to cope.\n";


# allowed value for F2, plus double check its still a current SO term ; id pair

	my %F2_value_workaround = (
	
		'synthetic_sequence' => 'SO:0000351',
	);
	
	foreach my $term (keys %F2_value_workaround) {
		set_symbol ('F2_value', 'current_value', "$term $F2_value_workaround{$term}");
		unless (valid_symbol ($term, 'SO:default') && valid_symbol ($term, 'SO:default') eq $F2_value_workaround{$term}) {
		
			print "MAJOR PEEVES ERROR in basic ontology processing: the '$term $F2_value_workaround{$term}' pair listed in Peeves as the current allowed value for F2 is no longer a valid SO term ; id pair, Peeves will need altering to cope (probably by replacing this obsolete/mismatched term ; id pair with a new valid one).\n\n"; 
		}

	}

# allowed values for SO terms attached to gene symbols in G38, plus double check that they are still current SO terms

	my @G38_SO_types = ('gene_group', 'gene_array');

	foreach my $term (@G38_SO_types) {

		set_symbol ($term, 'G38_SO_types', '1');
		valid_symbol ($term, 'SO:default') or print "MAJOR PEEVES ERROR in basic ontology processing: the '$term' term listed in Peeves as an allowed value for SO terms attached to gene symbols in G38 is no longer a valid SO term, Peeves will need altering to cope (probably by replacing this obsolete term with a new valid one).\n\n";

	}


# Assays for TAP statements - would be lovely if these were in an ontology, but Harvard appears to be reluctant, so here they are. Full definitions included where available ;P). For now there is nothing but general typing ('assay'). In future this should probably be further subdivided to allow checking that assay is appropriate to gene product type. The assay name is stored as a value, but is not actually used except to return 'true' as of 111028 (DOS).

# transcript assays:
    set_symbol ('is', 'assay', 'in situ');
    set_symbol ('nb', 'assay', 'northern blot');
    set_symbol ('db', 'assay', 'dot blot');
    set_symbol ('de', 'assay', 'transcript distribution deduced from reporter protein or transcript distribution');
    set_symbol ('debs', 'assay', 'transcript distribution deduced from reporter protein distribution, binary system (Gal4 UAS)');
    set_symbol ('rp', 'assay', 'RNAse protection, primer extension, SI, etc.');
    set_symbol ('mi', 'assay', 'miscellaneous');
    set_symbol ('pc', 'assay', 'pcr');
    set_symbol ('race', 'assay', 'RACE');
    set_symbol ('ri', 'assay', 'radioisotope in situ');
    set_symbol ('rtpc', 'assay', 'RT-PCR');
    set_symbol ('dt', 'assay', 'dissected tissue');
    set_symbol ('as', 'assay', 'antisense RNA probes');
    set_symbol ('ema', 'assay', 'expression microarray');
    set_symbol ('rs', 'assay', 'RNA-seq');
    set_symbol ('scrs', 'assay', 'single cell RNA-seq');
    set_symbol ('vis', 'assay', 'virtual in situ hybridization');

# polypeptide assays:
    set_symbol ('il', 'assay', 'immunolocalization');
    set_symbol ('ea', 'assay', 'enzyme assay or biochemical detection');
    set_symbol ('wb', 'assay', 'western blot');
    set_symbol ('sp', 'assay', 'spectrophotometric analysis');
    set_symbol ('id', 'assay', 'immunodetection (other than il)');
    set_symbol ('ih', 'assay', 'immunohistochemistry');
    set_symbol ('imem', 'assay', 'Immuno-electronmicroscopy');
    set_symbol ('el', 'assay', 'electrophoresis');
    set_symbol ('et', 'assay', 'epitope tag');
    set_symbol ('ms', 'assay', 'mass spectroscopy');
    set_symbol ('dep', 'assay', 'protein expression deduced from reporter fusion or direct labeling');
    set_symbol ('cef', 'assay', 'cell fractionation');
    set_symbol ('xr', 'assay', 'x-ray crystallography');

# 'Event' assays
    set_symbol ('ip', 'assay', 'immunoprecipitation');
    set_symbol ('cl', 'assay', 'crosslink');
    set_symbol ('cc', 'assay', 'column chromatography');
    set_symbol ('gs', 'assay', 'gel shift assay');
    set_symbol ('fp', 'assay', 'foot print');
    set_symbol ('ta', 'assay', 'transfection assay');
    set_symbol ('ib', 'assay', 'in vitro binding assay');
    set_symbol ('ov', 'assay', 'overlay assay');
    set_symbol ('act', 'assay', 'activity');
    set_symbol ('aff', 'assay', 'affinity binding');
    set_symbol ('ias', 'assay', 'inferred from author statements');
    set_symbol ('ga', 'assay', 'genetic assay');
    set_symbol ('tani', 'assay', 'transfection assay, non-insect cells');
    set_symbol ('tai', 'assay', 'transfection assay insect cells');
    set_symbol ('tad', 'assay', 'transfection assay Drosophila cells');
    set_symbol ('cf', 'assay', 'co-fractionation');
    set_symbol ('y1h', 'assay', 'yeast one hybrid assay');
    set_symbol ('mi', 'assay', 'microinjection');
    set_symbol ('ir', 'assay', 'inferred from reporter assay');
    set_symbol ('nda', 'assay', 'inferred from assay using non-Drosophila orthologues');
    set_symbol ('ma', 'assay', 'mutational analysis');
    set_symbol ('cca', 'assay', 'cell culture assay');
    set_symbol ('pa', 'assay', 'peptide analysis');
    set_symbol ('hplc', 'assay', 'HPLC');
    set_symbol ('aa', 'assay', 'aggregation assay');
    set_symbol ('rca', 'assay', 'reporter complementation assay');


# antibody types

    set_symbol ('monoclonal', 'antibody', 1);
    set_symbol ('polyclonal', 'antibody', 1);

# allowed databases for accession numbers in G35. Set final value to the valid species abbreviation for that database for cross-checking

	set_symbol ('HGNC', 'foreign_database', 'Hsap');
	set_symbol ('SGD', 'foreign_database', 'Scer');
	set_symbol ('MGI', 'foreign_database', 'Mmus');

## Information for checking ti.pro.  Hopefully most of this will eventually end up in a separate file located in ontologies so that there is a single file for curator browsing and for computation such as Peeves checking, as that will be more robust for maintenance, but adding them here now to get the checking implemented in Peeves.

# allowed values in MA8
    set_symbol ('viable', 'insertion_phenotype', 1);
    set_symbol ('fertile', 'insertion_phenotype', 1);

# allowed values in MA24
    set_symbol ('y', 'MA24_value', 1);
    set_symbol ('p', 'MA24_value', 1);

# allowed values in MA27

    set_symbol ('synTE_insertion', 'insertion_category', 1);
    set_symbol ('TI_insertion', 'insertion_category', 'TI');
    set_symbol ('natTE_isolate', 'insertion_category', 1);
    set_symbol ('natTE_isolate_named', 'insertion_category', 1);
    set_symbol ('natTE_partial_named', 'insertion_category', 1);
    set_symbol ('natTE_sequenced_strain_1', 'insertion_category', 1);

# allowed values in GA90k

	my @GA90k = ('point_mutation', 'rescue_region', 'insertion', 'sequence_variant', 'complex_substitution', 'deletion', 'insertion_site', 'sequence_alteration');

	foreach my $term (@GA90k) {

		set_symbol ($term, 'lesion_type', '1');
		valid_symbol ($term, 'SO:default') or print "MAJOR PEEVES ERROR in basic ontology processing: the '$term' term listed in Peeves as a valid value for GA90k is no longer a valid SO term, Peeves will need altering to cope (probably by replacing this obsolete term with a new valid one).\n\n";
	}


# allowed values for fields that can contain 'y' or 'n'.  There is also a 'check_y_or_n' subroutine, but
# useful to have this set of allowed values to check for 'y' or 'n' in fields that can be multiplied within
# the same proforma
    set_symbol ('y', 'y or n', 1);
    set_symbol ('n', 'y or n', 1);
# unfortunately, some fields require upper case Y or N !!
    set_symbol ('Y', 'Y or N', 1);
    set_symbol ('N', 'Y or N', 1);

# allowed values for MA23b

    set_symbol ('Mutation candidate.', 'MA23b_value', 1);
    set_symbol ('Gene trap candidate.', 'MA23b_value', 1);
    set_symbol ('Enhancer trap candidate.', 'MA23b_value', 1);
    set_symbol ('Activated gene candidate.', 'MA23b_value', 1);

# allowed values for orientation of sequence location

    set_symbol ('+', 'orientation', 1);
    set_symbol ('-', 'orientation', 1);

# additional allowed 'orientation' values for MA6, MA23g

    set_symbol ('p', 'additional_orientation', 1);
    set_symbol ('m', 'additional_orientation', 1);

# allowed values for MA19b

    set_symbol ('5\'', 'MA19b_value', 1);
    set_symbol ('3\'', 'MA19b_value', 1);
    set_symbol ('b', 'MA19b_value', 1);

# allowed values for MA19e
    set_symbol ('Replaced.', 'MA19e_value', 1);
    set_symbol ('Mislabeled.', 'MA19e_value', 1);
    set_symbol ('Invalid.', 'MA19e_value', 1);
    set_symbol ('Sequence repeated in genome.', 'MA19e_value', 1);

# allowed values for MS16 - have included what type of moseg the value should be used with
# as this may be useful for cross-checking with symbol for new mosegs - might need to change
# format of value to get the cross-checking to work

    set_symbol ('transgenic_transposable_element', 'MS16_value', 'FBtp');
    set_symbol ('engineered_plasmid', 'MS16_value', 'FBmc');
    set_symbol ('cloned_region', 'MS16_value', 'FBms');
    set_symbol ('engineered_region', 'MS16_value', 'TI'); # TI style constructs
    set_symbol ('engineered_transposable_element', 'MS16_value', 'FBtp'); # replaces 'natural_transposon_isolate_named'

# allowed values for MS4a (would be better to have reliable way to get this out of chado - 
# These come from the 'transgene_description' cv (but there are lots of other
# values in that cv in chado which are no longer used for curation) so can't just get them
# from chado easily.
# have included what type of moseg the value should be used with
# as this may be useful for cross-checking with symbol for new mosegs - might need to change
# format of value to get the cross-checking to work

    set_symbol ('transposon', 'MS4a_value', 'FBtp');
    set_symbol ('transposon_modified_in_vivo', 'MS4a_value', 'FBtp');
    set_symbol ('transposon_modified_in_vivo_partial', 'MS4a_value', 'FBtp');
    set_symbol ('plasmid', 'MS4a_value', 'FBmc');
    set_symbol ('cosmid', 'MS4a_value', 'FBmc');
    set_symbol ('BAC', 'MS4a_value', 'FBmc');
    set_symbol ('component_segment', 'MS4a_value', 'FBms');
    

# allowed values for fields which help make a relationship between a dataset and its members

    set_symbol ('member_of_reagent_collection', 'relationship_to_dataset', 1);
    set_symbol ('experimental_result', 'relationship_to_dataset', 1);


# allowed values for LC12b, is a subset of library_featureprop type


    set_symbol ('allele_used', 'LC12b_value', 1);
    set_symbol ('depletion_target', 'LC12b_value', 1);
    set_symbol ('RNAi_target', 'LC12b_value', 1);
    set_symbol ('inhibitor_target', 'LC12b_value', 1);
    set_symbol ('activator_target', 'LC12b_value', 1);
    set_symbol ('antibody_target', 'LC12b_value', 1);
    set_symbol ('bait_protein', 'LC12b_value', 1);
    set_symbol ('bait_RNA', 'LC12b_value', 1);
    set_symbol ('transgene_used', 'LC12b_value', 1);
    set_symbol ('overexpressed_factor', 'LC12b_value', 1);
    set_symbol ('ectopic_factor', 'LC12b_value', 1);
    set_symbol ('experimental_design', 'LC12b_value', 1);

# allowed values for HH1g - would be better if could get out of chado/ontology file

    set_symbol ('disease', 'HH1g_value', 1);
    set_symbol ('health-related process', 'HH1g_value', 1);

# allowed values for HH1g - would be better if could get out of chado/ontology file
# (although they are being stored in db as a prop so may not be appropriate)

    set_symbol ('parent entity', 'human_health_category', 'parent');
    set_symbol ('sub-entity', 'human_health_category', 'sub');
    set_symbol ('specific entity', 'human_health_category', 'specific');
    set_symbol ('group entity', 'human_health_category', 'group');

# allowed values for IN2a - have set value to be the type expected in
# the IN6 <symbol> sub-field for each value of IN2a - should make
# implementing IN2a<->IN6 cross-checking easier

    set_symbol ('protein-protein', 'IN2a_value', 'FBpp');
    set_symbol ('RNA-protein', 'IN2a_value', 'FBtr');
    set_symbol ('RNA-RNA', 'IN2a_value', 'FBtr');

# allowed values for SP5

    set_symbol ('drosophilid', 'tax group', '1');
    set_symbol ('DIOPT', 'tax group', '1');
    set_symbol ('OrthoDB', 'tax group', '1');

# allowed values in SF5e
    set_symbol ('H', 'SF5e_value', 1);
    set_symbol ('M', 'SF5e_value', 1);
    set_symbol ('L', 'SF5e_value', 1);

# allowed values in SF10a
    set_symbol ('DNaseI protection assay', 'SF10a_value', 1);
    set_symbol ('mobility shift assay', 'SF10a_value', 1);
    set_symbol ('coimmunoprecipitation', 'SF10a_value', 1);
    set_symbol ('coimmunoprecipitation with mutational analysis', 'SF10a_value', 1);

# allowed values for SF2a

    set_symbol ('DNA', 'SF2a_value', 1);
    set_symbol ('RNA', 'SF2a_value', 1);
    set_symbol ('polypeptide', 'SF2a_value', 1);

# allowed values for TC4b

    set_symbol ('isolate_of', 'TC4b_value', 1);
    set_symbol ('cloned_from', 'TC4b_value', 1);
    set_symbol ('selected_from', 'TC4b_value', 1);
    set_symbol ('targeted_mutant_from', 'TC4b_value', 1);
    set_symbol ('transformed_from', 'TC4b_value', 1);

# allowed values for TC5c

    set_symbol ('male', 'TC5c_value', 1);
    set_symbol ('female', 'TC5c_value', 1);


# SO term if that turns out to be needed.

	my @SF2b = ('enhancer', 'exon_junction', 'insulator', 'modified_RNA_base_feature', 'origin_of_replication', 'protein_binding_site', 'region', 'regulatory_region', 'RNAi_reagent', 'silencer', 'TF_binding_site', 'polypeptide_region', 'polyA_site', 'repeat_region', 'satellite_DNA', 'TSS', 'experimental_result_region', 'sgRNA');

	foreach my $term (@SF2b) {

		set_symbol ($term, 'SF2b_value', '1');
		valid_symbol ($term, 'SO:default') or print "MAJOR PEEVES ERROR in basic ontology processing: the '$term' term listed in Peeves as a valid value for SF2b is no longer a valid SO term, Peeves will need altering to cope (probably by replacing this obsolete term with a new valid one).\n\n";
	}
	
# allowed values for SF20a

    set_symbol ('genomic DNA', 'SF20a_value', 1);
    set_symbol ('cDNA', 'SF20a_value', 1);


## commenting out code for DC-547 as decided not to implement this fix
## left code in place in case useful for something similar to replace
## spec in DC-547
# temporary set of relationships betweeen subcellular FBbt terms and GO terms
# that will eventually replace them (DC-547)

##    set_symbol ('female pronucleus', 'FBbt_to_GO', 'GO:0001939');
##    set_symbol ('male pronucleus', 'FBbt_to_GO', 'GO:0001940');
##    set_symbol ('chorion', 'FBbt_to_GO', 'GO:0042600');
##    set_symbol ('pronucleus', 'FBbt_to_GO', 'GO:0045120');
##    set_symbol ('pigment granule', 'FBbt_to_GO', 'GO:0048770');
##    set_symbol ('micropyle', 'FBbt_to_GO', 'GO:0070825');
##    set_symbol ('acroblast', 'FBbt_to_GO', 'GO:0036063');
##    set_symbol ('dendrite', 'FBbt_to_GO', 'GO:0030425');
##    set_symbol ('dendritic tree', 'FBbt_to_GO', 'GO:0097447');
##    set_symbol ('fusome', 'FBbt_to_GO', 'GO:0045169');
##    set_symbol ('ring canal', 'FBbt_to_GO', 'GO:0045172');
##    set_symbol ('major mitochondrial derivative', 'FBbt_to_GO', 'GO:0016008');
##    set_symbol ('minor mitochondrial derivative', 'FBbt_to_GO', 'GO:0016009');
##    set_symbol ('Nebenkern derivative', 'FBbt_to_GO', 'GO:0016007');
##    set_symbol ('Nebenkern', 'FBbt_to_GO', 'GO:0016006');
##    set_symbol ('neuromuscular junction', 'FBbt_to_GO', 'GO:0031594');
##    set_symbol ('cell body', 'FBbt_to_GO', 'GO:0043025');
##    set_symbol ('pole granule', 'FBbt_to_GO', 'GO:0043186');
##    set_symbol ('pole plasm', 'FBbt_to_GO', 'GO:0045495');
##    set_symbol ('rhabdomere', 'FBbt_to_GO', 'GO:0016028');
##    set_symbol ('synapse', 'FBbt_to_GO', 'GO:0045202');
##    set_symbol ('bouton', 'FBbt_to_GO', 'GO:0043195');
##    set_symbol ('type I bouton', 'FBbt_to_GO', 'GO:0061174');
##    set_symbol ('type II bouton', 'FBbt_to_GO', 'GO:0061175');
##    set_symbol ('type III bouton', 'FBbt_to_GO', 'GO:0097467');
##    set_symbol ('yolk', 'FBbt_to_GO', 'GO:0060417');


# valid shorthands for natural transposons (natTEs) used as part of transgenic construct symbol (to indicate the original of the ends of the construct).
# value is the full name of the natTE.

	my $drosophilid_natTE_shorthand = {

		'Doc2' => 'Doc2-element',
		'Doc3' => 'Doc3-element',
		'Doc4' => 'Doc4-element',
		'F' => 'F-element',
		'G' => 'G-element',
		'H' => 'hobo',
		'I' => 'I-element',
		'M' => 'Dmau\mariner',
		'P' => 'P-element',
		'Q' => 'Q-element',
		'S' => 'S-element',
		'X' => 'X-element',
		'Y' => 'Y-element',

	};


	my $construct_natTE_shorthand = {

		'PBac' => 'Tni\piggyBac',
		'Mi' => 'Dhyd\Minos',
		'TI' => 'TI', # set value to TI even though its not actually a valid natTE symbol as it is useful to have a value to return, so can easily distinguish TI-style constructs and insertions from regular transposable element-based ones.
#		'' => '',



	};

# store shorthand in form that can be extracted using valid_symbol
	foreach my $shortcut (keys %{$drosophilid_natTE_shorthand}) {

    	set_symbol ($shortcut, 'insertion_natTE_shorthand_to_full', $drosophilid_natTE_shorthand->{$shortcut});
	  	set_symbol ($drosophilid_natTE_shorthand->{$shortcut}, 'insertion_natTE_full_to_shorthand', $shortcut);

    	set_symbol ($shortcut, 'construct_natTE_shorthand_to_full', $drosophilid_natTE_shorthand->{$shortcut});
	  	set_symbol ($drosophilid_natTE_shorthand->{$shortcut}, 'construct_natTE_full_to_shorthand', $shortcut);


	}

	foreach my $shortcut (keys %{$construct_natTE_shorthand}) {

    	set_symbol ($shortcut, 'construct_natTE_shorthand_to_full', $construct_natTE_shorthand->{$shortcut});
	  	set_symbol ($construct_natTE_shorthand->{$shortcut}, 'construct_natTE_full_to_shorthand', $shortcut);

	}



}

sub display_symtab_stats()
{
#  Display useful statistics about the contents of the symbol table.  Used primarily for debugging and
#  documentation.

    my %type_stats = ();
    print "Number of keys in symbol table ", scalar keys %symbol_table, "\n\n";
    foreach my $typehash (values %symbol_table)
    {
	foreach my $type (keys %{$typehash})
	{
	    if (exists $type_stats{$type})
	    {
		$type_stats{$type}++;
	    }
	    else
	    {
		$type_stats{$type} = 1;
	    }

	    if ($type eq 'FBbs')
	    {
		print "Found FBbs symbol ", $typehash->{$type}, "\n";
	    }
	}
    }
    foreach my $type (sort keys %type_stats)
    {
	printf ("%30s\t%7d\n", $type, $type_stats{$type});
    }
}

# A generally useful sub.  Made because needed in TAP parsing as part of a weirdly convoluted method for getting an ontology term ID from its name. This turned out to be necessary because of the vagaries of how symtab stores various ontology terms and IDs.  A better fix would involve improving or extending symtab to make this lookup trivial, but this is potentially delicate, so will have to wait. DOS 111028

sub get_types_from_sym {
  my $sym = shift;
  my @type;
  my ($key, $value);
  while (($key, $value) = each %{$symbol_table{$sym}}) {
    push @type, $key if ($value); # It is important to only record types for sym type combinations that return true. 
  }
  return \@type
}


sub valid_chado_symbol ($$)
{

# based on 'valid_chado_symbol_used_in_cross_check_FBid_symbol', which I suspect that there is a bug in.
# Because 'valid_chado_symbol_used_in_cross_check_FBid_symbol' is used in a very complicated subroutine
# where I am not sure exactly how it is used, I have made a new
# 'valid_chado_symbol' subroutine which works for what I want,
# and hopefully at some point in the future I can reconcile the two [gm140304].

# This subroutine is designed to check whether a symbol exists as a non-obsolete symbol of
# the requisite type in Chado i.e. pre-instantiation of symbols doesn't count towards validity.
# The subroutine puts the symbol table back to where it was before this subroutine was run, so that
# it doesn't mess with pre-instantiation.


	my ($symbol, $type) = @_;
	my $value = valid_symbol ($symbol, $type); # need to keep this value to put the symbol table back to this later

	delete_symbol ($symbol, $type);		# Delete the symbol from the symbol table
	my $chado_value = valid_symbol ($symbol, $type);	# Find out whether it's *really* in Chado
	set_symbol ($symbol, $type, $value);	# Restore status quo.
	return $chado_value;					# Return true Chado validity.
}

sub valid_symbol_of_list_of_types {

# $symbol = symbol to be tested for validity
# $list_of_types = reference to an array containing a list of types that the symbol
# should be tested for validity for e.g. FBtp, FBmc, FBms.
# Returns either 1 or 0, depending on whether the $symbol is a valid symbol of one of the
# $list_of_types.
# This array should be declared as follows before calling valid_symbol_of_list_of_types,
# to specify particular types of symbol to test for validity against:
#
# a. a field where allele and construct symbols may be entered (fictional example):
#
# my @allowed_types = ('FBal', 'FBtp');
# valid_symbol_of_list_of_types ($symbol, \@allowed_types) or 
#    report ($file, "%s: Invalid stamp \@%s\@ in '%s'", $code, $1, $data);
#
# b. although this will probably be mostly used for checking the validity of features
# for fields where symbols of multiple types are allowed, the subroutine can take
# any type - so it could be used to test for validity of anything that is put in the
# %symbol_table, if that made sense (fictional example)
#
# my @allowed_types = ('P40_flag', 'P41_flag');

	my ($symbol, $list_of_types) = @_;

	unless (@{$list_of_types}) {

		print "***MAJOR PEEVES ERROR: there is a call to the 'valid_symbol_of_list_of_types' subroutine where the '\$list_of_types\' variable is not a reference to an array containing types to check against - let Gillian know so this can be fixed.\n\n";;
	}


# return as soon as find a valid symbol
	foreach my $type (@{$list_of_types}) {

		valid_symbol ($symbol, $type) and return 1;
	}

		return 0;
}


sub valid_chado_symbol_of_list_of_types {

# $symbol = symbol to be tested for validity
# $list_of_types = reference to an array containing a list of types that the symbol
# should be tested for validity against e.g. FBtp, FBmc, FBms.
#
# This array should be declared as follows before calling valid_symbol_of_list_of_types,
# to specify particular types of symbol to test for validity against:
#
# a. a field where transcript and polypeptide symbols may be entered:
#
# my @allowed_types = ('FBtr', 'FBpp');
# valid_chado_symbol_of_list_of_types ($symbol, \@allowed_types) or 
#    report ($file, "%s: text", $code);
#
# The types to be tested should be ones that are stored in chado (no testing that this is the case is done
# here, as any such test should probably be added to the valid_chado_symbol subroutine this one calls).
# Thus, the subroutine is designed to be a wrapper for valid_chado_symbol, e.g. so that checking can be done
# on the validity of the primary symbol field in those cases where multiple FBid types can be entered in
# the same proforma e.g. expression.pro, moseg.pro.
# The subroutine returns as soon as it finds a valid chado symbol, returning the valid value
# in the symbol_table for that chado symbol (which will in practise be the FBid number).


	my ($symbol, $list_of_types) = @_;
	

	unless (@{$list_of_types}) {

		print "***MAJOR PEEVES ERROR: there is a call to the 'valid_chado_symbol_of_list_of_types' subroutine where the '\$list_of_types\' variable is not a reference to an array containing types to check against - let Gillian know so this can be fixed.\n\n";;
	}


	foreach my $type (@{$list_of_types}) {

		my $chado_value = valid_chado_symbol ($symbol, $type);
# return as soon as find a valid chado symbol
		if ($chado_value) {
			return $chado_value;
		}
	}
	
	return 0;

}
sub valid_species {

# not included as part of valid_symbol because checking of organism info
# for species proforma requires two separate 'symbol' arguments (genus and species)
# to be checked at the same time, not just one (as occurs in valid_symbol).

	my ($genus, $species, $type) = @_;

	if ($type eq 'chado_full_species_validity') {
# since organism table uniquename is genus+species, can only have one line returned
# so just test for presence of first array element
		defined (chat_to_chado ('chado_full_species_validity', $genus, $species)->[0]) ? return 1 : return 0;
	}

	if ($type eq 'chado_full_species_abbreviation') {

		my $chado_ref = chat_to_chado ('chado_full_species_abbreviation', $genus, $species)->[0];

# return the abbreviation is there is one
		if (defined $chado_ref) {
	   		my ($abbreviation) = @{$chado_ref};

# store the abbreviation in the symbol table, in case it is needed later, for efficiency
# substitution may need changing later if change the types once species completely moved
# over to using chado and not FBsp.obo
			if ($abbreviation) {

				my $shortened_type = $type;
				$shortened_type =~ s/full_//;
				set_symbol ($abbreviation, $shortened_type, ("$genus $species"));

			}

			return $abbreviation;

		}


		return 0;
	}


}


1;				# Boilerplate.
