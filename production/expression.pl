# Code to parse expression proformae

### Fields not checked:
# F6, F5, 

use strict;

our (%fsm, $want_next);	  # Global variables for finite state machine.
our ($chado, %prepared_queries); # Global variables for communication with Chado.
our %Peeves_config;

our $standard_symbol_mapping;

# A set of Peeves-global variables for communicating between different proformae.

our $g_FBrf;  # Publication ID: from P22 to (G31b, GA32b, A27b, AB11b)
our $g_pub_type;    # Publication type: from P1 to (*[12]b, GA10[a-h])
our $unattributed;              # Set to 1 if P22 = 'unattributed', otherwise '0'

our %x1a_symbols;   # For detecting duplicate proformae in a record
our %new_symbols; # List of symbols instantiated or invalidated by this record.

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

# A set of file-global variables for communicating between different proforma fields.

my $primary_symbol_list;						# Reference to dehashed data from primary symbol field
my @primary_id_list;  # List of gene product ids given in F1f
my %can_dup = (); # If decide any fields can be duplicated, add all as FC => 1.

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma
my @inclusion_essential = qw (F1f F1a);	# Fields which must be present in the proforma.  Minimal list, may want to revisit to add more.
my $hash_entries ='';						# Number of elements in hash list.


# A set of file-global variables for communicating between different proforma fields.



sub do_expression_proforma ($$) {

  # Process an expression proforma, the text of which is in the second argument, which has been read from the file
  # named in the first argument.

	($file, $proforma) = @_;
	%proforma_fields = ();
	%dup_proforma_fields = ();


	$primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.

	@primary_id_list = ('Missing_F1f_data'); # should be able to get rid of this once standardised all fields

	$change_count = 0;

	my @F1b_list = ();
	my @F1c_list = ();
	
	my @F2_list = ();
	my @F3_list = ();
	my @F4_list = ();
	my @F91_list = ();
	my @F91a_list = ();

	my @F11_list = ();
	my @F11a_list = ();
	my @F11b_list = ();
	my @F12_list = ();

	$proforma =~ /!.? F1a\..*? :(.*)/;		# Get F1a data, if any
	{
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count fields
	}


 FIELD:
	foreach my $field (split (/\n!/, $proforma))
	{
	if ($field =~ /^(.*?)\s+(F1a)\..*? :(.*)/s)
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
			$want_next = $fsm{'GENEPRODUCT ATTRIBUTES/EXPRESSION'};
			return;
		}

# not trapping species here - will need to be checked but do at end of proforma
# where determine whether the symbol is based on a gene/allele base
		($primary_symbol_list, undef) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);
	
	}
	elsif ($field =~ /^(.*?)\s+(F1f)\..*? :(.*)/s)
	{

		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@primary_id_list = validate_primary_FBid_field ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(F1b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@F1b_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(F1c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@F1c_list = validate_merge_using_ids ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?)\s+(F1d)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?)\s+(F1e)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_non_utf8 ($file, $2, $3);
		double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);
	}
	elsif ($field =~ /^(.*?)\s+(F2)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F2_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');


	}
	elsif ($field =~ /^(.*?)\s+(F3)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F3_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(F4)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F4_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(F5)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(F6)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(F9)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
# can't convert TAP_check to process_field_data format as ideally need to cross-check *part*
# of field with type of symbol (polypeptide vs transcript) in F1a
		changes ($file, $2, $1);
		check_non_utf8 ($file, $2, $3);
		double_query ($file, $2, $3) or TAP_check ($file, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(F10)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(F11)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F11_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(F11a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F11a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(F11b)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F11b_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(F12)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F12_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(F13)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(F14)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(F15)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(F16a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		validate_stub ($file, $1, $2, $3);
	}
	elsif ($field =~ /^(.*?)\s+(F17)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (F91)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F91_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (F91a)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@F91a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}

# fields that are not checked at all yet - validate_stub used to prevent false-positive
# 'Invalid proforma field' message.  Remember to take field codes out of second set of ()
# if checking for the field is implemented.
	elsif ($field =~ /^(.*?)\s+(F16b|F16c)\..*? :(.*)/s)
	{
		check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		validate_stub ($file, $1, $2, $3);
	}
	 elsif ($field =~ /^(.*?)\s+F(.+?)\..*?:(.*)$/s)
	{
		report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*F.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
			report ($file, "Malformed proforma field (message tripped in expression.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
  }

### Start of tests that can only be done after parsing the entire proforma. ###

	check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);

	cross_check_harv_style_symbol_rename_merge_fields ($file, 'F', $hash_entries, \@primary_id_list, $primary_symbol_list, \@F1b_list, \@F1c_list, \%proforma_fields);

	plingc_merge_check ($file, $change_count,'F1c', \@F1c_list, $proforma_fields{'F1c'});

# rename and merge fields must not both contain data
	rename_merge_check ($file, 'F1b', \@F1b_list, $proforma_fields{'F1b'}, 'F1c', \@F1c_list, $proforma_fields{'F1c'});

# only do tests when the number of (dehashed) entries in F1a and F1f are the same
	if ($hash_entries and $#{$primary_symbol_list} + 1 == $hash_entries and $#primary_id_list + 1 == $hash_entries) {

		for (my $i = 0; $i < $hash_entries; $i++) {

			my $gene_product_status = get_object_status ('F', $primary_id_list[$i], $F1b_list[$i], $F1c_list[$i]);

# only do tests if primary, rename and merge fields pass basic checks
			if ($gene_product_status) {

# get formatting information for gene product symbol in F1a
				my ($gene_product_type, $parent_symbols, $parent_type) = type_gene_product ($primary_symbol_list->[$i], '1');

# if gene product type can be determined
				if ($gene_product_type) {


# check symbol formatting for all except existing symbols.
					unless ($gene_product_status eq 'existing') {

						# check that the 'parent' part(s) of the gene product symbol are each a valid symbol of the expected type
						# (combinations have multiple allele symbol parents, so $parent_symbols is an array reference)
						foreach my $symbol (@{$parent_symbols}) {
							valid_symbol ($symbol, $parent_type) or report ($file, "%s: '%s' gene product symbol is based on the invalid %s symbol '%s'", 'F1a', $primary_symbol_list->[$i], $parent_type, $symbol);
						}

# extra checks for FBco
						if ($gene_product_type eq 'FBco') {

							# first, for new FBco symbols with two allele components, double-check that the reversed order of components is not already in chado, and warn as appropriate if it is.
							if (scalar @{$parent_symbols} == 2) {

								my $reversed_symbol = $parent_symbols->[1] . '&cap;'. $parent_symbols->[0];

								# use valid_chado_symbol so works for renames
								if (my $FBco = valid_chado_symbol($reversed_symbol, 'FBco')) {

									unless ($gene_product_status eq 'rename') {

										report ($file, "%s: You have entered '%s' as the symbol for a %s, but the 'reverse' symbol - %s - already exists in chado (%s), did you mean the existing FBco instead ?.", 'F1a', $primary_symbol_list->[$i], ($gene_product_status eq 'new' ? "$gene_product_status combination" : "combination $gene_product_status"), $reversed_symbol, $FBco);

									} else {

										if ($F1b_list[$i] eq $reversed_symbol) {

											report ($file, "%s: You appear to be trying to 'reverse' the components of the '%s' combination symbol by renaming it to '%s' - was this your intention ?.", 'F1a', $F1b_list[$i], $primary_symbol_list->[$i]);

										} else {

											report ($file, "%s: You have entered '%s' as the new valid symbol to rename %s (id given as %s in F1f), but the 'reverse' symbol - %s - already exists in chado (%s), either choose a new symbol for the rename, or correct the entry in F1f as appropriate.", 'F1a', $primary_symbol_list->[$i], $F1b_list[$i], $primary_id_list[$i],  $reversed_symbol, $FBco);

										}
									}
								}
							}

							# second, do additional checks on the allele parts of the symbol, to check they are of the expected type and in the correct order
							# at the moment, to simplify checking, this is only doing the checking when the component allele is already in chado
							# (this should normally be the case anyway given partition of curation).


							my $counter = 1; # use counter as easy way of keeping track of which index of array have got to

							foreach my $symbol (@{$parent_symbols}) {
								# only do checks for symbols already in chado
								if (my $FBal = valid_chado_symbol($symbol, 'FBal')) {

									my $split_switch = 0; # switch that gets set below if a split system component is found associated with the FBal

									# try to get any encoded tool informaion attached directly to FBal first
									my $encoded_tool_list = chat_to_chado ('tool_relationship', $FBal, 'encodes_tool');

									foreach my $encoded_tool (@{$encoded_tool_list}) {
										my $tool_uses_list = chat_to_chado ('tool_uses', $encoded_tool->[0]); # need to add ->[0] as the data is retrieved from chado as an array of arrays (each returned row generates an array that itself contains an array of the return values for that row, and as in this case the query returns one value per matching row, it is retrieved by the ->[0])

										foreach my $tool_uses (@{$tool_uses_list}) {

											if (valid_symbol ($tool_uses->[0], 'FBcv:split system component')) {
												$split_switch++;

												if (my $order = valid_symbol($tool_uses->[0], 'FBco_order')) {
													unless ($counter == $order) {
														report ($file, "%s: The '%s' part of the '%s' combination symbol is in position %s in the symbol, but it is expected to be in position %s.", 'F1a', $symbol, $primary_symbol_list->[$i], $counter, $order);
													}
												}
											}
										}
									}

									# if that fails, get inserted elements (via the associated insertion(s)) and use tool info attached to inserted element(s)
									unless (scalar @{$encoded_tool_list} > 0) {

										my $inserted_element_list = chat_to_chado ('inserted_element', $FBal);

										foreach my $inserted_element (@{$inserted_element_list}) {

											my $encoded_tool_list = chat_to_chado ('tool_relationship', $inserted_element->[0], 'encodes_tool');

											foreach my $encoded_tool (@{$encoded_tool_list}) {

												my $tool_uses_list = chat_to_chado ('tool_uses', $encoded_tool->[0]);

												foreach my $tool_uses (@{$tool_uses_list}) {

													if (valid_symbol ($tool_uses->[0], 'FBcv:split system component')) {
														$split_switch++;

														if (my $order = valid_symbol($tool_uses->[0], 'FBco_order')) {
															unless ($counter == $order) {
																report ($file, "%s: The '%s' part of the '%s' combination symbol is in position %s in the symbol, but it is expected to be in position %s.", 'F1a', $symbol, $primary_symbol_list->[$i], $counter, $order);
															}
														}
													}
												}
											}
										}
									}


									# report if the component of the new FBco symbol is not a split system component
									unless ($split_switch) {
										report ($file, "%s: The '%s' part of the '%s' combination symbol is not a split system component, this is NOT currently allowed.", 'F1a', $symbol, $primary_symbol_list->[$i]);
									}


								} else {

									if (valid_symbol($symbol, 'FBal')) {
										report ($file, "%s: The '%s' part of the new '%s' combination symbol is an allele newly generated in this record, which means that Peeves cannot currently perform additional checks on this allele symbol (it should be a 'split system component' and the DBD half should be listed before the AD half for DBD+AD hemidriver combinations.", 'F1a', $symbol, $primary_symbol_list->[$i]);
									}
								}

							$counter++; # increment counter
							}

						}
## end additional checks for FBco


# renames: check that the format of the new valid symbol (F1a) matches the FBid type of the gene product being renamed (FBti number in F1f)
						if ($gene_product_status eq 'rename') {

							my $id_type = $primary_id_list[$i];
							$id_type =~ s/[0-9]{1,}$//;
							unless ($id_type eq $gene_product_type) {

									report ($file, "Mis-match between FBid type and symbol format in gene product rename: the '%s' symbol matches %s format, but the FBid of the gene product being renamed is a %s:\n!%s\n!%s", $primary_symbol_list->[$i], $gene_product_type, $id_type, $proforma_fields{'F1f'}, $proforma_fields{'F1a'});
							}


						}
# merges: check that the format of the new valid symbol (F1a) matches the FBid type of the gene products being merged (F1c), and that only one type of FBid is listed in F1c
						if ($gene_product_status eq 'merge') {

							my $id_type;
							my $allowed_id_types = join '|', @{$standard_symbol_mapping->{'F'}->{id}};

							foreach my $id (@{$F1c_list[$i]}) {
								if ($id =~ m/^($allowed_id_types)\d{7,}$/) {
									$id_type->{$1}++;
								}
							}
							if (scalar keys %{$id_type} > 1) {

								report ($file, "%s: Merge field contains FBids of multiple types:\n!%s\n%s", 'F1c', $proforma_fields{'F1a'}, $proforma_fields{'F1c'});

							} elsif (scalar keys %{$id_type} == 1) {

								my $merge_field_id_type = join '', keys %{$id_type};

								unless ($merge_field_id_type eq $gene_product_type) {

									report ($file, "Mis-match between FBid type and symbol format in gene product merge: the '%s' symbol matches %s format, but the FBid type of the gene products being merged is %s:\n!%s\n!%s", $primary_symbol_list->[$i], $gene_product_type, $merge_field_id_type, $proforma_fields{'F1a'}, $proforma_fields{'F1c'});
								}
							}

						}
					}

# F2 must be filled in for new/merged gene products where expression is from a transgene or a combination
					if (defined $F2_list[$i] && $F2_list[$i] ne '') {

						unless ($parent_type eq 'FBal') {
							report ($file, "%s must only be filled in if expression is from a transgene:\n!%s\n!%s", 'F2', $proforma_fields{'F1a'}, $proforma_fields{'F2'});
						}

					} else {

						if ($parent_type eq 'FBal') {
							if ($gene_product_status eq 'new' || $gene_product_status eq 'merge') {

								report ($file, "%s must be filled in for a %s where expression is from a transgene:\n!%s\n!%s", 'F2', ($gene_product_status eq 'new' ? "$gene_product_status gene product" : "gene product $gene_product_status"), $proforma_fields{'F1a'}, $proforma_fields{'F2'});
							}

						}
					}

# cross-checks for F3
					if (defined $F3_list[$i] && $F3_list[$i] ne '') {

						if ($gene_product_type eq 'FBtr') {

							validate_exp_pro_CV_field ('F3', $F3_list[$i], 'SO:transcript', 'FBtr');

						} elsif ($gene_product_type eq 'FBpp') {

							validate_exp_pro_CV_field ('F3', $F3_list[$i], 'SO:polypeptide', 'FBpp');

						} elsif ($gene_product_type eq 'FBco') {

							validate_exp_pro_CV_field ('F3', $F3_list[$i], 'FBcv:split system combination', 'FBco');

						}

					} else {

							if ($gene_product_status eq 'new' || $gene_product_status eq 'merge') {

								report ($file, "%s must be filled in for a %s:\n!%s\n!%s", 'F3', ($gene_product_status eq 'new' ? "$gene_product_status gene product" : "gene product $gene_product_status"), $proforma_fields{'F1a'}, $proforma_fields{'F3'});
							}


					}
# cross-checks for F12
					if (defined $F12_list[$i] && $F12_list[$i] ne '') {
						unless ($gene_product_type eq 'FBpp') {
							report ($file, "%s: can only be filled in for a 'FBpp' type gene product:\n!%s\n!%s)",'F12', $proforma_fields{'F1a'}, $proforma_fields{'F12'});
						}
					}

# cross-checks for F11 fields
					if (defined $F11_list[$i] && $F11_list[$i] ne '') {

						if ($gene_product_type eq 'FBco') {
							report ($file, "%s: should not be filled in for a 'FBco' type gene product:\n!%s\n!%s)",'F11', $proforma_fields{'F1a'}, $proforma_fields{'F11'});
						}

					}

					if (defined $F11a_list[$i] && $F11a_list[$i] ne '') {

						if ($gene_product_type eq 'FBco') {
							report ($file, "%s: should not be filled in for a 'FBco' type gene product:\n!%s\n!%s)",'F11a', $proforma_fields{'F1a'}, $proforma_fields{'F11a'});
						}

					}

					if (defined $F11b_list[$i] && $F11b_list[$i] ne '') {

						if ($gene_product_type eq 'FBco') {
							report ($file, "%s: should not be filled in for a 'FBco' type gene product:\n!%s\n!%s)",'F11b', $proforma_fields{'F1a'}, $proforma_fields{'F11b'});
						}

					}



				} else {

					report ($file, "%s: Symbol '%s' does not match any of the formats allowed for a gene product symbol", 'F1a', $primary_symbol_list->[$i]);

				}
			}
		}
	}


compare_field_pairs ($file, $hash_entries, 'F91', \@F91_list, 'F91a', \@F91a_list, \%proforma_fields, 'pair::if either is filled in', '');


compare_field_pairs ($file, $hash_entries, 'F11a', \@F11a_list, 'F11', \@F11_list, \%proforma_fields, 'dependent', '');
compare_field_pairs ($file, $hash_entries, 'F11b', \@F11b_list, 'F11', \@F11_list, \%proforma_fields, 'dependent', '');


# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#F4_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'F1a', $primary_symbol_list, 'F4', \@F4_list, \%proforma_fields, "You must include the valid symbol in F4 when \!c-ing it under the 'unnattributed' publication.");

}

### End of tests that can only be done after parsing the entire proforma. ###

# The following line must always be at the bottom of this subroutine

    $want_next = $fsm{'GENEPRODUCT ATTRIBUTES/EXPRESSION'};

}


sub validate_exp_pro_CV_field {

	my ($code, $content, $cv_type, $gp_type) = @_;

	if ($content =~ m/^(.+) ([a-zA-Z]{1,}\:\d{7})/) {
  
  	my $term = $1;
  	my $id = $2;
  	# have lost error message context for the case where a curator chose the wrong kind of SO term for that type of gene product
  	# by updating, may put that back as field cross-check later
  	check_ontology_term_id_pair($file, $code, $term, $id, $cv_type, $content, " for a $gp_type type gene product.");

  } else {
	report ($file, "%s: Invalid format in %s (should be CV_term CV_id).",  $code, $content);
  }
}


sub validate_F10 {
# process_field_data + %field_specific_checks format. 150922.

# The arguments are:
# $file = curation record
# $code = proforma field code
# $term_id_pair_list = dehashed contents of a proforma field containing a list of ontology term ; id pairs, without proforma field text
# $context = hash reference to %proforma_fields, so can provide context (including proforma field text) in error messages

	my ($file, $code, $term_id_pair_list, $context) = @_;

	$term_id_pair_list eq '' and return;			# Absence of data is permissible.


# include check_for_duplicated_lines so that subroutine works for both single and multiple line fields
	my $uniqued_term_id_pair_list = check_for_duplicated_lines($file,$code,$term_id_pair_list,$context->{$code});

	foreach my $term_id_pair (keys %{$uniqued_term_id_pair_list}) {

		unless ($term_id_pair =~ / ; /) {
			report ($file, "%s: Incorrect format '%s', required format is 'cvterm_name ; cvterm_id'", $code, $term_id_pair);
			next;
		}

		my ($term, $id) = ($term_id_pair =~ /(.*?) ; (.*)/);

		if (my $GO_id = valid_symbol ($term, 'GO:cellular_component')) {


# if its  term that is valid in both GO cellular component and anatomy
#			if (my $GO_id = valid_symbol ($term, 'FBbt_to_GO')) {
			if (my $purported_id = valid_symbol ($term, 'FBbt:default')) {

					if ($id eq $purported_id) {

						report ($file, "%s: You have used the sub-cellular '%s' FBbt term which has an equivalent '%s; %s' GO cellular_component term - you should probably use the GO term (or possibly one of its children) in your curation instead.",$code, $term_id_pair, $term, $GO_id);

					} else {

						check_ontology_term_id_pair($file, $code, $term, $id, 'GO:cellular_component', $term_id_pair, '');

					}




			} else {
		
		
				check_ontology_term_id_pair($file, $code, $term, $id, 'GO:cellular_component', $term_id_pair, '');

			}

# can't use check_ontology_term_id_pair as FBbt term and id pairs not stored reciprocally		

		} elsif (my $purported_id = valid_symbol ($term, 'FBbt:default')) {
		
			unless ($id eq $purported_id) {
				report ($file, "%s: id '%s' does not match term '%s' given in '%s'", $code, $id, $term, $term_id_pair);
			
			}


		} else {
		
			report ($file, "%s: '%s' is not a valid 'term ; id' pair from either the anatomy or GO cellular component ontology", $code, $term_id_pair);
		}
		


	}
}



1; # return true
