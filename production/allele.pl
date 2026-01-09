# Code to parse allele proformae

use strict;
our (%fsm, $want_next, $chado, %prepared_queries);

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

our $g_gene_sym_list;		# reference to array of gene symbols in G1a
our $g_gene_species_list;		# reference to array of species derived from gene symbols in G1a
our @g_assoc_aberr;		# Associated aberration: from GA10g to A4 and A6
my $primary_symbol_list;						# Reference to dehashed data from primary symbol field
#our %GA21_hash;			# Cross-reference complemented / complementing alleles in different GA21
our %x1a_symbols;		# For detecting duplicate proformae in a record
our %new_symbols;		# List of symbols instantiated or invalidated by this record.
our $g_GA34a_count; # count of number of filled in GA34a fields
our $g_GA34b_count; # count of number of filled in GA34b fields

our $change_count = 0; # count of number of !c lines in the proforma, peeves global as needs to be seen by changes in tools.pl

my ($file, $proforma);
my %proforma_fields;		# Keep track of the latest entry seen for each code
my %dup_proforma_fields; # keep track of full picture for fields that can be duplicated within a proforma


my @inclusion_essential = qw (GA1a GA1g);	# Fields which must be present in the proforma.

my %can_dup = (GA90a => 1, GA90b => 1, GA90c => 1, GA90d => 1, GA90e => 1, GA90f => 1, GA90g => 1, GA90h => 1, GA90i => 1, GA90j => 1, GA90k => 1,); # Fields which may be duplicated in a proforma.

my $g1a_gene = '';		# Gene symbol inherited from preceding gene proforma
my $g1a_species = '';		# Species of gene inherited from preceding gene proforma
my $hash_entries;		# Number of elements in hash list, defined by counting elements in GA1a.  Used when calling dehash within allele proforma field checking.
my @FBal_list = ();		# List of FBal identifiers given in GA1h

my @GA1e_list = ();		# Dehashed data from GA1e
my @GA1f_list = ();		# Dehashed data from GA1f
my @GA2a_list = ();		# Dehashed data from GA2a.
my @GA2c_list = ();		# Dehashed data from GA2c.
my @GA10a_list = ();		# List of lists of FBtp symbols given in GA10a
my @GA10b_list = ();		# List of lists of FBtp names given in GA10b
my @GA10c_list = ();		# List of lists of FBti symbols given in GA10c
my @GA10d_list = ();		# List of lists of FBti names given in GA10d
my @GA10e_list = ();		# List of lists of FBti symbols given in GA10e
my @GA10f_list = ();		# List of lists of FBti names given in GA10f
my @GA4_list = ();

my $firstGeneAllele; # because GA1h is above GA1a

my $GA1h_ng=0; # misformed or too many FBids...


# the arrays below store data returned by process_field_data, so are dehashed, but have NOT
# been split on \n
my @GA8_list = ();		# keeping this here as may eventually need to communicate between aberration and allele data (needs to be our in that case ?) if full checking is implemented. [gm140627]
my @GA11_list = ();		# keeping this here as may eventually need to communicate between aberration and allele data (needs to be our in that case ?) if full checking is implemented. [gm140627]

sub do_allele_proforma ($$)
{
# Process an allele proforma, the text of which is in the second argument which has been read from the file named
# in the first argument.

    ($file, $proforma) = @_;
    %proforma_fields = ();
	%dup_proforma_fields = ();
# The first occurring GA1a record defines the number of expected symbols in a hash list.

    $proforma =~ /!.? GA1a\..*? :(.*)/;		# Get GA1a data, if any
    {
	no warnings;				# split in scalar context raises deprecation warning.
	$hash_entries = split / \# /, $1;		# Count fields
	$firstGeneAllele = $1;
    }
    $primary_symbol_list = ['Missing_primary_symbol_data'];	# Set a default so that other checks don't fail with undef value.
	my $primary_species_list;

	$change_count = 0;

# A set of local variables for post-checks, clear them out at the beginning of eacch proforma

    my $GA1g_data = '';			# The y/n data found in GA1g.

    @GA1e_list = ();			# proforma field is omitted.
    @GA1f_list = ();
    @GA2a_list = ();
    @GA2c_list = ();
    @GA10a_list = ();
    @GA10b_list = ();
    @GA10c_list = ();
    @GA10d_list = ();
    @GA10e_list = ();
    @GA10f_list = ();
    $GA1h_ng=0;


	my @GA1g_list = ();

# the arrays below store data returned by process_field_data (or equivalent),
# so are dehashed, but have NOT been split on \n
    my @GA1b_list = ();
	my @GA2b_list = ();
    my @GA30a_list = ();
    my @GA30b_list = ();
    my @GA30c_list = ();
    my @GA30d_list = ();
    my @GA30e_list = ();
    my @GA30f_list = ();
    my @GA35_list = ();


	@GA8_list = ();
	@GA11_list = ();


	my @GA90a_list = ();
	my @GA90b_list = ();
	my @GA90c_list = ();
	my @GA90d_list = ();
	my @GA90e_list = ();
	my @GA90f_list = ();
	my @GA90g_list = ();
	my @GA90h_list = ();
	my @GA90i_list = ();
	my @GA90j_list = ();
	my @GA90k_list = ();

	my @GA12a_list = ();
	my @GA12b_list = ();

	my @GA91_list = ();
	my @GA91a_list = ();


# We know only one gene was given in G1a, because allele proformae are not allowed to follow gene proformae
# which contain hash lists.  Consequently, the only gene symbol will be found in $g_gene_sym_list->[0] and
# similarly for the species.

    $g1a_gene = $g_gene_sym_list->[0];
    $g1a_species = $g_gene_species_list->[0];

FIELD:
    foreach my $field (split (/\n!/, $proforma))
    {
	if ($field =~ /^(.*?) (GA1h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GA1h ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (GA1a)\..*? :(.*)/s)
	{
	    my ($change, $code, $data) = ($1, $2, $3);

	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);

	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);

# Enforce the rule that at most one of G1a and GA1a may use hash lists.  This is a fatal error condition and
# it's not safe trying to validate anything else in the proforma.  $g_num_syms contains the number of entries
# in G1a's hash list.

	    if ($g_num_syms > 1 and $hash_entries > 1)
	    {
		report ($file, "%s: Can't use a hashed allele proforma after a hashed gene proforma.\n!%s", $code, $proforma_fields{$code});
			$want_next = $fsm{'ALLELE'};
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
			$want_next = $fsm{'ALLELE'};
			return;
		}

		($primary_symbol_list, $primary_species_list) = validate_primary_proforma_field ($file, $code, $change, $hash_entries, $data, \%proforma_fields);

# check for mis-match between symbols in GA1a and primary gene here

		for (my $i = 0; $i < $hash_entries; $i++) {

			if (my ($gene, $super) = ($primary_symbol_list->[$i] =~ /(.+)\[(.+)\]$/)) {
				$gene eq $g1a_gene or report ($file, "%s: Mismatch between gene symbol '%s' in preceding G1a and the gene portion '%s' given in\n!%s", $code, $g1a_gene, $gene, $proforma_fields{$code});

			}
		}	

	}
	elsif ($field =~ /^(.*?) (GA1b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA1b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA1e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@GA1e_list = validate_rename ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?) (GA1f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		unless (double_query ($file, $2, $3)) {
			@GA1f_list = validate_x1f ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}
	}
	elsif ($field =~ /^(.*?) (GA1g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    $GA1g_data = $3; # for now, keeping $GA1g_data (not dehashed) as well as storing @GA1g_list (dehashed), until worked out whether its safe/desirable to change existing code to use dehashed @GA1g_list version [gm140625]

		unless (double_query ($file, $2, $3)) {
			@GA1g_list = validate_x1g ($file, $2, $hash_entries, $1, $3, $proforma_fields{$2});
		}

#	    double_query ($file, $2, $3) or validate_x1g ($file, $2, $1, $3, $proforma_fields{$2});
	}
	elsif ($field =~ /^(.*?) (GA2a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA2a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GA2b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA2b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA2c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA2c_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GA31)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA32a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			validate_obsolete ($file, $1, $2, $3, \%proforma_fields);
		}
	}
	elsif ($field =~ /^(.*?) (GA32b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_dissociate ($file, $1, $2, $3,  \%proforma_fields);

	}
	elsif ($field =~ /^(.*?) (GA4)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA4_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA56)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GA56 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (GA17)\.(.*?)\s+\*\w+\s? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $4) or validate_GA17 ($2, $1, $4) if($4 ne '');# do the check anyway

	}
	elsif ($field =~ /^(.*?) (GA7a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA2[89]{1}[ab]{1})\.\s*(.*?)\s+\*\w+\s? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $4);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $4) or validate_GA289ab ($2, $1, $4) if($4 ne '');# do the check anyway
	}
	elsif ($field =~ /^(.*?) (GA2[89]c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA21)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GA21 ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (GA22)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA10a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GA10a ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (GA10b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA10b_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA10c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@GA10c_list = validate_GA10ce ($2, $1, $3);
		}
	}
	elsif ($field =~ /^(.*?) (GA10d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA10d_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA10e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
		unless (double_query ($file, $2, $3)) {
			@GA10e_list = validate_GA10ce ($2, $1, $3);
		}
	}
	elsif ($field =~ /^(.*?) (GA10f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA10f_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA10g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GA10g ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (GA8)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA8_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}

	elsif ($field =~ /^(.*?)\s+(GA36)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}

	elsif ($field =~ /^(.*?) (GA11)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA11_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA23a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GA23a ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (GA23b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA12a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA12a_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA12b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    @GA12b_list = process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA30a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @GA30a_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA30b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @GA30b_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA30c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @GA30c_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA30d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @GA30d_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA30e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @GA30e_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA30f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @GA30f_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GA35)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		push @GA35_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA13)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA20)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?) (GA33)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA14)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?) (GA34a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    check_non_utf8 ($file, $2, $3);
	    check_non_ascii ($file, $2, $3);
	    double_query ($file, $2, $3) or validate_GA34a ($2, $1, $3);
	}
	elsif ($field =~ /^(.*?) (GA34b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
		if ($3) {
			$g_GA34b_count++; # add to the count as GA34b contains data
		}


	}
	elsif ($field =~ /^(.*?) (GA34c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');

	}
	elsif ($field =~ /^(.*?)\s+(GA90a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90a_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90b_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90c)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90c_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90d)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90d_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90e)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90e_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90f)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90f_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90g)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90g_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90h)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90h_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90i)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90i_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA90j)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90j_list, process_field_data ($file, $hash_entries, $1, '1', $2, $3, \%proforma_fields, '0');
	}
	elsif ($field =~ /^(.*?)\s+(GA90k)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		no_hashes_in_proforma ($file, $2, $hash_entries, $3);
		check_site_specific_field($file, $2, 'Harvard', \%proforma_fields) if $3;
		push @GA90k_list, process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA91)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA91_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA91a)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
		@GA91a_list = process_field_data ($file, $hash_entries, $1, '0', $2, $3, \%proforma_fields, '1');
	}
	elsif ($field =~ /^(.*?)\s+(GA85|GA81a|GA84b)\..*? :(.*)/s)
	{
	    check_dups ($file, $2, $field, \%proforma_fields, \%dup_proforma_fields, $primary_symbol_list, $can_dup{$2} ? 1 : 0);
	    python_parser_field_stub ($file, $1, $2, $3, $proforma_fields{$2});
	}
	elsif ($field =~ /^(.*?) GA(.+?)\..*?:(.*)$/s)
	{
	    report ($file, "Invalid proforma field\n!%s", $field);
	} elsif ($field =~ /.*GA.*/s) {

		unless ($field =~ /END OF RECORD FOR THIS PUBLICATION/s) {
		    report ($file, "Malformed proforma field (message tripped in allele.pl).\nThis is often caused by the line of !!! before the PROFORMA line below ending with a space (here is a line to help find that case):\n!!!!!!! \n!\n(if that does not work and you think there is nothing wrong with this line let Gillian know as it might indicate a bug with the format of the field-specific regular expressions in Peeves):\n'!%s'", $field);
		}
	}
    }

# Tests that can only be done after parsing the entire proforma.

    check_presence ($file, \%proforma_fields, \@inclusion_essential, $primary_symbol_list);
	
	if ($hash_entries and exists $proforma_fields{'GA1h'} and !$GA1h_ng )# new from March 09 ie test >> production
    {
	cross_check_FBid_symbol ($file, 1, 0, 'FBal', 'allele', $hash_entries,
				 'GA1h', \@FBal_list, 'GA1a', $primary_symbol_list,
				 'GA1e', \@GA1e_list, 'GA1f', \@GA1f_list);		
    }

    if (exists $proforma_fields{'GA1g'})
    {
	cross_check_1a_1g ($file, 'GA', 'FBal', 'allele', $hash_entries, $GA1g_data, $primary_symbol_list);
    }

# If GA1e is filled in, check GA1g is 'n'
	if ($hash_entries and exists $proforma_fields{'GA1e'}) {

		cross_check_x1e_x1g ($file, 'GA1e', $hash_entries, $GA1g_data, \@GA1e_list, $proforma_fields{'GA1e'});

	}


# GA1e and GA1f must not both contain data.

    rename_merge_check ($file, 'GA1e', \@GA1e_list, $proforma_fields{'GA1e'}, 'GA1f', \@GA1f_list, $proforma_fields{'GA1f'});

# check for rename across species.
	check_for_rename_across_species ($file, $hash_entries, 'GA', $primary_species_list, \@GA1e_list, \%proforma_fields);


# no !c if GA1f is filled in

	plingc_merge_check ($file, $change_count,'GA1f', \@GA1f_list, $proforma_fields{'GA1f'});

# cross-checks for fullname renames
	cross_check_full_name_rename ($file, 'GA', $hash_entries, $primary_symbol_list, \@GA1e_list, \@GA2c_list, \%proforma_fields);

# If GA2c is filled in, GA2a must be filled in. PLUS value in GA2a and GA2c must not be the same
compare_field_pairs ($file, $hash_entries, 'GA2c', \@GA2c_list, 'GA2a', \@GA2a_list, \%proforma_fields, 'dependent', 'not same');

# GA2c and GA1f must not both be filled in
compare_field_pairs ($file, $hash_entries, 'GA1f', \@GA1f_list, 'GA2c', \@GA2c_list, \%proforma_fields, 'single', '');

# Typically, only one of GA30c and GA30d are filled in

compare_field_pairs ($file, $hash_entries, 'GA30c', \@GA30c_list, 'GA30d', \@GA30d_list, \%proforma_fields, 'single::(except in rare cases, which is usually some kind of sensor tool)', '');

compare_field_pairs ($file, $hash_entries, 'GA10a', \@GA10a_list, 'GA4', \@GA4_list, \%proforma_fields, 'single::(GA4 should not be used for transgenic alleles)', '');


# If GA35 is filled in then GA30d should not typically be filled in
# (cross-checks between GA35 and GA30c are now done further down, to allow more nuanced checking)
compare_field_pairs ($file, $hash_entries, 'GA35', \@GA35_list, 'GA30d', \@GA30d_list, \%proforma_fields, 'single::(except in rare cases, which is usually when the transgene can be used both to study the function of the encoded product and as an experimental tool, depending on circumstance)', '');

# check that if have filled in any of GA10 'synonym' fields, that the relevant 'valid symbol' field is filled in

compare_field_pairs ($file, $hash_entries, 'GA10b', \@GA10b_list, 'GA10a', \@GA10a_list, \%proforma_fields, 'dependent', '');
compare_field_pairs ($file, $hash_entries, 'GA10d', \@GA10d_list, 'GA10c', \@GA10c_list, \%proforma_fields, 'dependent', '');
compare_field_pairs ($file, $hash_entries, 'GA10f', \@GA10f_list, 'GA10e', \@GA10e_list, \%proforma_fields, 'dependent', '');



# if any of GA90[b-k] are filled in, GA90a must be filled in.
compare_duplicated_field_pairs ($file, 'GA90b', \@GA90b_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90c', \@GA90c_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90d', \@GA90d_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90e', \@GA90e_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90f', \@GA90f_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90g', \@GA90g_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90h', \@GA90h_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90i', \@GA90i_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90j', \@GA90j_list, 'GA90a', \@GA90a_list, \%dup_proforma_fields, 'dependent', '');
compare_duplicated_field_pairs ($file, 'GA90a', \@GA90a_list, 'GA90k', \@GA90k_list, \%dup_proforma_fields, 'pair::if either is filled in', '');

compare_duplicated_field_pairs ($file, 'GA90b', \@GA90b_list, 'GA90c', \@GA90c_list, \%dup_proforma_fields, 'pair::if either is filled in', '');

compare_field_pairs ($file, $hash_entries, 'GA91', \@GA91_list, 'GA91a', \@GA91a_list, \%proforma_fields, 'pair::if either is filled in', '');


# check that the same value does not appear in multiple instances of a 'dupl for multiple'
# field in the same proforma (where that is not appropriate)
check_for_duplicated_field_values ($file, 'GA90a', \@GA90a_list);

# check that mutagen and nature of lesion are filled in for new transgenic construct alleles
# only attempt if hashing is correct for GA10 (is good to not check that
# hashing is correct for GA8 and GA12b, as it then catches cases of hashed
# proformae where these fields are only filled in for one of the alleles
if ($hash_entries and $#GA10a_list + 1 == $hash_entries) {

	for (my $i = 0; $i < $hash_entries; $i++) {

		my $object_status = get_object_status ('GA', $GA1g_list[$i], $GA1e_list[$i], $GA1f_list[$i]);


		if ($object_status eq 'new') {

			compare_pairs_of_data($file, 'GA10a', $GA10a_list[$i], 'GA8', $GA8_list[$i], \%proforma_fields, "dependent::for a new transgenic construct allele\n!$proforma_fields{GA1a}", '');

			compare_pairs_of_data($file, 'GA10a', $GA10a_list[$i], 'GA12b', $GA12b_list[$i], \%proforma_fields, "dependent::for a new transgenic construct allele\n!$proforma_fields{GA1a}", '');


		}


	}
}


# GA30a-f field cross-checks

if ($hash_entries) {

	for (my $i = 0; $i < $hash_entries; $i++) {

		my $object_status = get_object_status ('GA', $GA1g_list[$i], $GA1e_list[$i], $GA1f_list[$i]);
		my $allele_type = get_allele_type($primary_symbol_list->[$i], $GA10a_list[$i], $GA10c_list[$i], $GA10e_list[$i]);

# if GA30a is filled in
		if (defined $GA30a_list[$i] && $GA30a_list[$i] ne '') {

			if ($allele_type eq 'classical') {

				unless (valid_symbol ($file, 'record_type') eq 'EDIT') {
					report ($file, "%s must not be filled in for a '%s' allele (did you forget to put a construct in GA10a or a TI-style insertion in GA10c/GA10e ?\n!%s\n!%s", 'GA30a', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30a'});
				}

			} elsif ($allele_type eq 'regular insertion') {

				unless (defined $GA30f_list[$i] && $GA30f_list[$i] ne '') {
					report ($file, "%s must not be filled in for a '%s' allele unless GA30f is filled in.\n!%s\n!%s", 'GA30a', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30a'});
				}
			}

		}

# if GA30b is filled in
		if (defined $GA30b_list[$i] && $GA30b_list[$i] ne '') {

			if ($allele_type eq 'classical') {
				unless (valid_symbol ($file, 'record_type') eq 'EDIT') {
					report ($file, "%s must not be filled in for a '%s' allele (did you forget to put a construct in GA10a or a TI-style insertion in GA10c/GA10e ?\n!%s\n!%s", 'GA30b', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30b'});
				}
			} elsif ($allele_type eq 'regular insertion') {

				unless (defined $GA30f_list[$i] && $GA30f_list[$i] ne '') {
					report ($file, "%s must not be filled in for a '%s' allele unless GA30f is filled in.\n!%s\n!%s", 'GA30b', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30b'});
				}
			}

		}


# if GA30c is filled in
		if (defined $GA30c_list[$i] && $GA30c_list[$i] ne '') {

			if ($allele_type eq 'classical') {
				unless (valid_symbol ($file, 'record_type') eq 'EDIT') {
					report ($file, "%s must not be filled in for a '%s' allele (did you forget to put a construct in GA10a or a TI-style insertion in GA10c/GA10e ?\n!%s\n!%s", 'GA30c', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30c'});
				}
			} elsif ($allele_type eq 'regular insertion' || $allele_type eq 'TI insertion') {

				unless (defined $GA30f_list[$i] && $GA30f_list[$i] ne '') {
					report ($file, "%s must not be filled in for a '%s' allele unless GA30f is filled in.\n!%s\n!%s", 'GA30c', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30c'});
				}
			}

# in this loop, GA30c is empty
		} else {

# check to see whether GA30c/GA30d were left empty by mistake for new construct alleles of 'tool' genes
			if ($object_status eq 'new' && $allele_type eq 'construct') {

				if (my $id = valid_chado_symbol($g1a_gene, 'FBgn')) {

					my $common_tool_uses = chat_to_chado ('common_tool_uses', $id)->[0];

# if the gene is typically used as a tool
					if (defined $common_tool_uses && (scalar @{$common_tool_uses} > 0)) {

# think could remove GA30c in this loop and change to commented line below - as already tested in loop above and is empty if are here, but will check at end
#						unless (defined $GA30d_list[$i] && $GA30d_list[$i] ne '')) {
						unless ((defined $GA30c_list[$i] && $GA30c_list[$i] ne '') || (defined $GA30d_list[$i] && $GA30d_list[$i] ne '')) {

# check whether or not GA35 is filled in, and print slightly different message in the two cases.

							unless (defined $GA35_list[$i] && $GA35_list[$i] ne '') {
								report ($file, "WARNING: An 'encoded tool' field is usually filled in for a new 'construct' allele when the parent gene is commonly used as a tool (as is the case for '%s'), did you forget to fill in either GA30c or GA30d ?\n!%s", $g1a_gene, $proforma_fields{'GA1a'});

							} else {

								report ($file, "WARNING: An 'encoded tool' field is usually filled in for a new 'construct' allele when the parent gene is commonly used as a tool (as is the case for '%s'). You have filled in GA35, so this may be a rare 'non-tool' allele of the gene, in which case this message is a false-positive.\n!%s", $g1a_gene, $proforma_fields{'GA1a'});

							}

						}

					}
				}

			}
		}


# if GA30d is filled in
		if (defined $GA30d_list[$i] && $GA30d_list[$i] ne '') {

			if ($allele_type eq 'classical') {

				unless (valid_symbol ($file, 'record_type') eq 'EDIT') {
					report ($file, "%s must not be filled in for a '%s' allele (did you forget to put a construct in GA10a or a TI-style insertion in GA10c/GA10e ?\n!%s\n!%s", 'GA30d', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30d'});
				}
			} elsif ($allele_type eq 'regular insertion' || $allele_type eq 'TI insertion') {

				unless (defined $GA30f_list[$i] && $GA30f_list[$i] ne '') {
					report ($file, "%s must not be filled in for a '%s' allele unless GA30f is filled in.\n!%s\n!%s", 'GA30d', $allele_type, $proforma_fields{'GA1a'}, $proforma_fields{'GA30d'});
				}
			}

		}

# if GA30e is filled in

		if (defined $GA30e_list[$i] && $GA30e_list[$i] ne '') {

			unless (valid_symbol ($file, 'record_type') eq 'EDIT') {
				unless ($allele_type eq 'construct') {
					report ($file, "%s can only be filled in for a 'construct' allele.\n!%s\n!%s", 'GA30e',$proforma_fields{'GA1a'}, $proforma_fields{'GA30e'});

				}
			}
		} else {

			if ($allele_type eq 'construct' && $object_status eq 'new') {
				report ($file, "WARNING: %s is usually filled in for a new '%s' allele, did you forget to fill it in ?\n!%s", 'GA30e', $allele_type, $proforma_fields{'GA1a'});
			}
		}

# if GA30f is filled in

		if (defined $GA30f_list[$i] && $GA30f_list[$i] ne '') {

			unless ($allele_type eq 'regular insertion' || $allele_type eq 'TI insertion') {

				report ($file, "%s can only be filled in for an 'insertion' allele, did you forget to fill in GA10c or GA10e?\n!%s", 'GA30f', $proforma_fields{'GA1a'});

			}

		}

# checks for GA35

		if (defined $GA35_list[$i] && $GA35_list[$i] ne '') {

			unless (valid_symbol ($file, 'record_type') eq 'EDIT') {
				unless ($allele_type eq 'construct') {
					report ($file, "%s can only be filled in for a 'construct' allele.\n!%s\n!%s", 'GA35',$proforma_fields{'GA1a'}, $proforma_fields{'GA35'});

				}
			}
# add check for DC-996 - only use 'genomic_DNA' or 'cDNA' with wild_type
			my $wild_type = 0;
			my $dna_type = 0;

			foreach my $GA35_item (split /\n/, $GA35_list[$i]) {

				if ($GA35_item eq 'wild_type') {

					$wild_type++;

				} elsif ($GA35_item eq 'genomic_DNA' || $GA35_item eq 'cDNA') {

					$dna_type++;
				}

			}

			if ($dna_type) {

				unless ($wild_type) {

					report ($file, "%s contains 'genomic_DNA' or 'cDNA' without 'wild_type'.\n!%s\n!%s", 'GA35',$proforma_fields{'GA1a'}, $proforma_fields{'GA35'});
				}
			}

# check that if GA35 AND GA30c/GA30d are filled in, it is appropriate, and warn if not
# do as separate from above loop, in case data goes in in an .edit record

			if (defined $GA30c_list[$i] && $GA30c_list[$i] ne '') {

				my @targeting_types = ('SO:oligo', 'additional_targeting_GA35');
				my $targeting_tool = 0;
				my $targeting_match = 0;

				foreach my $GA30c_item (split /\n/, $GA30c_list[$i]) {
					if (my $id = valid_symbol($GA30c_item, 'FBsf')) {

						if ($id =~ m/^FBsf/) {
							my $tool_type = chat_to_chado ('feature_type_from_id', $id)->[0]->[0];

							if (valid_symbol_of_list_of_types ($tool_type, \@targeting_types)) {
								$targeting_tool++;
							}

							if ($GA35_list[$i] eq $tool_type) {
								$targeting_match++;
							}

						} else {
						# this will be new FBsf generated in record

							my $targeting_mapping = {
								'dsRNA' => 'RNAi_reagent',
								'sgRNA' => 'sgRNA',
							};

							my $tool_type = '';

							if ($GA30c_item =~ m/^(.+?)-/) {
								$tool_type = $1;
							}

							if (exists $targeting_mapping->{$tool_type}) {

								$targeting_tool++;

								if ($GA35_list[$i] eq $targeting_mapping->{$tool_type}) {
									$targeting_match++;
								}

							}
						}
					}
				}


				unless ($targeting_tool) {

					report($file, "%s and %s must NOT both contain data for non-sequence targeting reagents (except in rare cases, which is usually when the transgene can be used both to study the function of the encoded product and as an experimental tool, depending on circumstance).\n!%s\n!%s\n!%s", 'GA35', 'GA30c', $proforma_fields{'GA1a'}, $proforma_fields{'GA35'}, $proforma_fields{'GA30c'});

				} else {

					unless ($targeting_match) {
						report($file, "Mis-match between sequence targeting reagent SO term(s) in %s and type of tool in %s.\n!%s\n!%s\n!%s", 'GA35', 'GA30c', $proforma_fields{'GA1a'}, $proforma_fields{'GA35'}, $proforma_fields{'GA30c'});

					}

				}

			}

		} else {

# warn that GA35 should be filled in for new, non-tool construct alleles
			if ($allele_type eq 'construct' && $object_status eq 'new') {

				if (my $id = valid_chado_symbol($g1a_gene, 'FBgn')) {

					my $common_tool_uses = chat_to_chado ('common_tool_uses', $id)->[0];

					unless (defined $common_tool_uses && (scalar @{$common_tool_uses} > 0)) {


						report ($file, "WARNING: %s is usually filled in for a new '%s' allele of a 'non-experimental tool' parent gene, did you forget to fill it in ?\n!%s", 'GA35', $allele_type, $proforma_fields{'GA1a'});
					}

				}

			}
		}

	}
}



# check that valid symbol is in the symbol synonym field when !c-ing it under the  'unattributed' pub.
# Only do the check if the symbol synonym field contains some data
if ($unattributed && $#GA1b_list + 1 == $hash_entries) {

	check_unattributed_synonym_correction ($file, $hash_entries, 'GA1a', $primary_symbol_list, 'GA1b', \@GA1b_list, \%proforma_fields, "You must include the valid symbol in GA1b when \!c-ing it under the 'unnattributed' publication.");

}


    $want_next = $fsm{'ALLELE'};		# I have been touched by his noodly appendage!
}

sub validate_GA1h ($$$)
{
# Data is either a single FBal or empty.  It should be present for author-curated proformae.  Issue a warning if
# it is present in other proforma types.

    my ($code, $change, $FBals) = @_;
    $FBals = trim_space_from_ends ($file, $code, $FBals);

    if (valid_symbol ($file, 'curator_type') eq 'USER' || valid_symbol ($file, 'curator_type') eq 'AUTO')
    {
	$FBals eq '' and report ($file, "%s: %s-curated proformae should have data.", $code,valid_symbol ($file, 'curator_type'));
    }
    else
    {
	$FBals eq '' or report ($file, "%s: Curators don't usually fill in the FBal field.  " .
				"Are you sure you want to for '%s'?", $code, $firstGeneAllele, join (' # ', @{$primary_symbol_list}));
    }
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});


# Note that '$GA1h_ng' appears specific to GA1h compared to other validate_x1h subroutines - this is probably a bug and the implementation should be standardised across the other x1h fields - but need to figure out cross_check_FBid_symbol first - see comment in GA1h.txt doc file for details [gm140228]
    unless (single_line ($file, $code, $FBals, $proforma_fields{$code}))
    {
	# in this case don't continue checiking -FBal is not correctly set
	$GA1h_ng=1;
	return;
    }
    @FBal_list = FBid_list_check ($file, $code, 'FBal', $hash_entries, $FBals);

# More tests at the post-check phase.
}


sub is_a_driver ($)
{
# Return 1 or 0 according to whether the only argument looks like a driver or not.

    return ($_[0] =~ /^Scer\\GAL4/ ||
	    $_[0] =~ /^Scer\\GAL80/ ||
	    $_[0] =~ /^Tn10\\tetR/ ||
	    $_[0] =~ /^Ecol\\lexA/ ||
	    $_[0] =~ /^Ncra\\QF/ ||
	    $_[0] =~ /^Ncra\\QS/ ||
	    $_[0] =~ /^Scer\\FLP1/ ||
	    $_[0] =~ /^P1\\cre/ ||
	    $_[0] =~ /^Hsim\\VP16/ ||
	    $_[0] =~ /^Hsap\\RELA/ ||
	    $_[0] =~ /^Spyo\\Cas9/ ||
	    $_[0] =~ /^Dcr-2/
# there were alleles that matched cases below . Will no longer have this kind of symbol once retrofit done
# so commented out (will see if causes phen curators any problems as not sure that they ARE all drivers).
# Best solution is probably to replace entire/most of subroutine with a look-up that the
# allele is a driver (or maybe that the parent gene has a 'common_tool_uses' of driver CV term) but kept
# above hack for now.
#	    $_[0] =~ /\[.*T:Scer\\GAL4.*?\]/ ||
#	    $_[0] =~ /\[.*T:Ecol\\lexA.*?\]/ ||
#	    $_[0] =~ /\[.*T:Ncra\\QF.*?\]/
	    );
}

sub do_withs ($$$$)
{

# Comment this properly!!!!!

# One or more things, usually alleles, separated by ", " or "/".  Treat both categories the same for now.
# Eventually someone may specify that be dealt with differently...

    my ($code, $with, $ga1a, $context) = @_;

    if ($with =~ m/, /) {

	report ($file, "%s: '(with )' portion contains a comma. Please follow 'coping with complex with' instructions in the phen_curation.sop to rearrange the following line to prevent a problematic genotype:\n%s", $code, $context);

    }

    foreach my $with_thing (split (/, |\//, $with))
    {
	$with_thing = trim_space_from_ends ($file, $code, $with_thing);

# $with_thing has to be either any valid aberration symbol or a rather constrained allele symbol.

	next if valid_symbol ($with_thing, 'FBab');		# Always ok if a valid abs symbol
	if (my $fbal = valid_symbol ($with_thing, 'FBal'))
	{
	    if (my ($gene, undef) = ($with_thing =~ /(.+)\[(.+)\]$/))	# Slice out gene portion.
	    {
		$gene eq $g1a_gene or report ($file,
					      "%s: Mismatch between gene symbol '%s' in GA1a " .
					      "and the gene portion '%s' given in '(with %s)' in the line\n%s",
					      $code, $g1a_gene, $gene, $with, $context);
	    }

	    # add check to see whether allele is transgenic and print a warning if so, to prevent problematic genotypes being made in db
	    my $assoc_list = chat_to_chado ('associated_with_FBtp', $fbal);
	    if (@{$assoc_list}) {

		report ($file, "%s: '(with )' portion contains a transgenic allele (%s) which will cause a problematic genotype on loading. Please rearrange the line (replacing %s with the allele in GA1a) and put it in the %s proforma instead:\n%s", $code, $with_thing, $with_thing, $with_thing, $context);


	    }

	}
	else
	{
	    report ($file, "%s: '%s' is neither a valid allele or aberration in '%s'",
		    $code, $with_thing, $context);
	}
    }
}

sub do_allele_list ($$$$$$)
{
# The first argument is the proforma code, as usual.
#
# The second is an <allele_list> as defined by the BNF in validate_GA289ab()
#
# The third argument is a pattern which matches the characters used to separate the individual alleles.  It is
# usually either ', ' or ', |/'
#
# The fourth argument is a term from a phenotypic class in FBcv, or a body part term taken from a variety of
# sources, or an empty string if term is not available for whatever reason.

# The fifth argument is a small integer.  Legal values are:

#    0 -- only drivers are permitted
#    1 -- any valid allele symbols are permitted
#    2 -- any valid symbol of type FBal, FBab, FBba or the string '+' and, if an allele,
#         must not be of the same gene as G1a
#    3 -- any valid allele symbol, or valid aberration or valid TI or the string '+'
#
# The sixth argument is a snippet from the proforma field data intended to give a context to any reports
# issued.

    my ($code, $allele_list, $sep, $phenotype, $type_code, $context) = @_;

    foreach my $allele (split (/$sep/, $allele_list))
    {
	$allele = trim_space_from_ends ($file, $code, $allele);

# If $phenotype is a descendent of the 'modifier of variegation' node in FBcv, things other than alleles are also
# acceptable.  Deal with this special case first.

	if (valid_symbol ($phenotype, 'FBcv:modifier of variegation'))
	{
	    (is_a_driver ($allele) and $allele =~ /\[-\]$/) or	# To allow Scer\GAL4[-] etc
	    ($allele eq '+' and $type_code == 0) or		# because this code short circuits that below.
	    ($allele eq '+' and $type_code == 3) or		# because this code short circuits that below.
	    valid_symbol ($allele, 'FBab') or
	    valid_symbol ($allele, 'FBti') or
	    valid_symbol ($allele, 'FBal') or
	    valid_symbol ($allele, 'FBba') or
	    report ($file, "%s: '%s' is not a valid object or is of the wrong type in '{ %s }' in the line\n%s",
		    $code, $allele, $allele_list, $context);
	    next;
	}

	if ($type_code == 0)			# Only drivers are acceptable.  Someday drivers may be marked
	{					# explicitly but, until then, use a few heuristics.
	    if (is_a_driver ($allele))
	    {
		valid_symbol ($allele, 'FBal') or
		    $allele =~ /\[-\]$/ or
		    report ($file, "%s: '%s' is not a valid driver in '{ %s }' in the line\n%s",
			    $code, $allele, $allele_list, $context);
	    }
	    else
	    {
		report ($file, "%s: '%s' is not a valid driver in '{ %s }' in the line\n%s",
			$code, $allele, $allele_list, $context);
	    }
	}
	elsif ($type_code == 1)
	{
	    valid_symbol ($allele, 'FBal') or $allele =~ /\[-\]$/ or
		report ($file, "%s: '%s' is not a valid allele in '{ %s }' in the line\n%s",
			$code, $allele, $allele_list, $context);
	}
	elsif ($type_code == 2)
	{
	    next if valid_symbol ($allele, 'FBab') or
		    valid_symbol ($allele, 'FBba') or
#		    valid_symbol ($allele, 'FBti') or	# Legal in some cases, but want warnings anyway.
		    $allele eq '+' or
		    $allele =~ /\[-\]$/;

	    valid_symbol ($allele, 'FBal') or
		report ($file, "%s: '%s' is not a valid object or is of the wrong type in '{ %s }' in the line\n%s",
			$code, $allele, $allele_list, $context);
	    $allele =~ /(.*)\[/;
	    $1 eq $g1a_gene and
		report ($file, "%s: allele '%s' in %s must not be an allele of the gene given in G1a, '%s'",
			$code, $allele, $context, $g1a_gene);
	}
	elsif ($type_code == 3)
	{
	    $allele eq '+' or
	    valid_symbol ($allele, 'FBal') or
	    valid_symbol ($allele, 'FBab') or
	    valid_symbol ($allele, 'FBba') or
	    $allele =~ /\[-\]$/ or
		report ($file, "%s: '%s' is not a valid object or is of the wrong type in '{ %s }' in the line\n%s",
			$code, $allele, $allele_list, $context);
	}
    }
}

sub do_phen_class ($$$)
{
# Validate a (possibly qualified) phenotypic class on behalf GA56, GA28a and GA29a.

    my ($code, $qualified_phenotype, $context) = @_;

    my $errmsg;			# Message to be displayed by report();
    my $drvmsg = '';		# An additional message displayed if the driver portion looks dodgy.
    my @phen_fields = split (' \| ', $qualified_phenotype);

	my $allowed_types = valid_symbol('phenotypic class', 'allowed_qualifier_list');

# $phen_fields[0] is now the phenotypic class and any remaining elements are qualifiers.  Make sure they are
# all valid terms from FBcv.

    my $phenotype = trim_space_from_ends ($file, $code, shift @phen_fields);
#    my $phenotype_id = valid_symbol ($phenotype, 'phenotypic_class');
    unless (valid_symbol ($phenotype, 'FBcv:phenotypic_class'))
    {
	$errmsg = "%s: '%s' is not a valid phenotypic class";
	if ($phenotype =~ /[\{\}]/)
	{
	    $drvmsg = '.  Did you miss a space next to a curly bracket perhaps?';
	}
	if ($phenotype eq $context)
	{
	    report ($file, $errmsg . $drvmsg, $code, $phenotype);
	}
	else
	{
	    report ($file, $errmsg . " in '%s'" . $drvmsg, $code, $phenotype, $context);
	}
    }
    foreach my $qualifier (@phen_fields)
    {
	unless (valid_symbol_of_list_of_types ($qualifier, $allowed_types))
	{
	    $errmsg = "%s: '%s' is not a valid qualifier in '%s'";
	    if ($qualifier =~ /[\{\}]/)
	    {
		$drvmsg = '.  Did you miss a space next to a curly bracket perhaps?';
	    }
	    report ($file, $errmsg . $drvmsg, $code, $qualifier, $context);
	}
	my $add_msg = '';
	# Code to check for illegal combination of FBdv term with descendants of the 'increased mortality during development' term.
	if ((valid_symbol ($phenotype, 'FBcv:increased mortality during development'))&&(valid_symbol ($qualifier, 'FBdv:default')))
	{
       	    $errmsg = "%s: '%s' is not a valid qualifier with '%s'";
	    {
		$add_msg = '.  Stage qualifiers are not allowed with phenotypic class terms specifying the stage of death.';
	    }
	    report ($file, $errmsg . $add_msg, $code, $qualifier, $context);
	}
    }
    return $phenotype;
}

sub do_phen_bodytype ($$$)
{
# Validate a (possibly qualified) body part phenotype on behalf GA17, GA28b and GA29b.

    my ($code, $qualified_phenotype_list, $context) = @_;

    my $errmsg;			# Message to be displayed by report();
    my $drvmsg = '';		# An additional message displayed if the driver portion looks dodgy.

	my $allowed_types = valid_symbol('phenotype manifest', 'allowed_qualifier_list');


	if($qualified_phenotype_list=~/\s\&\s/){
	   report($file,"$code:Compounding anatomy and cell component terms using ' & ' is no longer allowed ('$qualified_phenotype_list').");
	}

    foreach my $qualified_phenotype (split (' \& ', $qualified_phenotype_list))
    {
	my @phen_fields = split (' \| ', $qualified_phenotype);

# $phen_fields[0] is now the body part term and any remaining elements are qualifiers.  Make sure they are all
# valid terms from the appropriate CV.

	my $body_part_term = trim_space_from_ends ($file, $code, shift @phen_fields);

	unless (valid_symbol ($body_part_term, 'FBbt:default') || valid_symbol ($body_part_term, 'GO:cellular_component'))
	{
	    $errmsg = "%s: '%s' is not a valid body part";
	    if ($qualified_phenotype =~ /[\{\}&]/)
	    {
		$drvmsg = '.  Did you miss a space next to a {, a } or an & perhaps?';
	    }
	    if ($body_part_term eq $context)
	    {
		report ($file, $errmsg . $drvmsg, $code, $body_part_term);
	    }
	    else
	    {
		report ($file, $errmsg . " in '%s'" . $drvmsg, $code, $body_part_term, $context);
	    }
	}
##	} else {
## commenting out code for DC-547 as decided not to implement this fix
## left code in place in case useful for something similar to replace
## spec in DC-547
## temporary message suggesting GO term for subcellular FBbt terms (DC-547)
##		if (my $GO_id = valid_symbol ($body_part_term, 'FBbt_to_GO')) {
##			if (my $GO_term = valid_symbol ($GO_id, 'GO:id')) {
##				unless ($GO_term eq $body_part_term) {
##					report ($file, "%s: %s\nYou have used the sub-cellular '%s' FBbt term which is going to be replaced by the '%s' GO term - you should use the GO term (or possibly one of its children) in your curation instead.",$code, $context, $body_part_term, $GO_term);
##				}
##			} else {
##			report ($file, "Peeves error, please let Gillian know the following so that it can be fixed: The '%s' GO id in the FBbt_to_GO mapping for the '%s' FBbt term is no longer a valid id, and needs updating in symbtab.pl.",$GO_id, $body_part_term);
##			}
##		}
##	}
## end temporary message for DC-547

	foreach my $qualifier (@phen_fields)
	{
	    unless (valid_symbol_of_list_of_types ($qualifier, $allowed_types))
	    {
		$errmsg = "%s: '%s' is not a valid qualifier in '%s'";
		if ($qualifier =~ /[\{\}&]/)
		{
		    $drvmsg = '.  Did you miss a space next to a {, a } or an & perhaps?';
		}
		report ($file, $errmsg . $drvmsg, $code, $qualifier, $context);
	    }
	}
    }
}

sub validate_GA56 ($$$)
{
# Phenotypic or dominance class.

    my ($code, $change, $phenclass_list) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    $phenclass_list eq '' and return;		# Absence of data is always acceptable.

    my @phenclasses = dehash ($file, $code, $hash_entries, $phenclass_list);
    for (my $i = 0; $i < $hash_entries; $i++)
    {
	foreach my $phenclass (split /\n/, $phenclasses[$i])
	{
	    $phenclass = trim_space_from_ends ($file, $code, $phenclass);
	    next if $phenclass eq '';

	    my (undef, $with, $remainder) = ($phenclass =~ /^(\(with (.*)\) )?(.*)/);

	    my ($qualified_phenotype, undef, $driver) = ($remainder =~ /(.*?)( \{ (.*) \})?$/);
	    $qualified_phenotype = trim_space_from_ends ($file, $code, $qualified_phenotype);

	    if ($qualified_phenotype eq '')
	    {
		report ($file, "%s: Missing phenotypic class in '%s'", $code, $phenclass);
		next;
	    }
	    my $phenotype = do_phen_class ($code, $qualified_phenotype, $phenclass);

	    if ($with)
	    {
		do_withs ($code, $with, $primary_symbol_list->[$i], $phenclass);
		foreach my $qualifier (split (' \| ', $qualified_phenotype))
		{
		    if ($qualifier eq 'dominant') {
			report ($file, "%s: Can't use '%s' with a '(with )' in '%s'",
				$code, $qualifier, $phenclass);
		    } elsif ($qualifier eq 'recessive') {

			# want to allow 'recessive' for simple homozygotes only
			# this means can do a simple test of whether $with is the same as allele in GA1a
			# without having to split out the components (if there is more than one component
			# recessive isn't really applicable)
			unless ($with eq silent_trim_space($primary_symbol_list->[$i])) {

				report ($file, "%s: Can't use '%s' with '(with )' (not a simple homozygote) in '%s'",
					$code, $qualifier, $phenclass);
			}
		    }
		}
	    }

	    if ($driver)
	    {
		my $separator = valid_symbol ($phenotype, 'FBcv:modifier of variegation') ? ', |/' : ', ';
		unless (is_a_driver($primary_symbol_list->[$i])) {
			do_allele_list ($code, $driver, $separator, $phenotype, 0, $phenclass);
		} else {
			do_allele_list ($code, $driver, $separator, $phenotype, 1, $phenclass);
		
		}
	    }
	}
    }
}

sub validate_GA17 ($$$)
{
# Phenotype

    my ($code, $change, $phenotype_list) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    $phenotype_list eq '' and return;		# Absence of data is always acceptable.

    my @phenotypes = dehash ($file, $code, $hash_entries, $phenotype_list);
    for (my $i = 0; $i < $hash_entries; $i++)
    {
	foreach my $phenotype (split /\n/, $phenotypes[$i])
	{
	    $phenotype = trim_space_from_ends ($file, $code, $phenotype);
	    next if $phenotype eq '';
	    
	    my (undef, $with, $remainder) = ($phenotype =~ /^(\(with (.*)\) )?(.*)/);
	    $with and do_withs ($code, $with, $primary_symbol_list->[$i], $phenotype);

	    my ($qualified_phenotype_list, undef, $driver) = ($remainder =~ /(.*?)( \{ (.*) \})?$/);
	    $qualified_phenotype_list = trim_space_from_ends ($file, $code, $qualified_phenotype_list);

	    if ($qualified_phenotype_list eq '')
	    {
		report ($file, "%s: Missing phenotype in '%s'", $code, $phenotype);
		next;
	    }
	    do_phen_bodytype ($code, $qualified_phenotype_list, $phenotype); #tells you you can't use ' & '

		if ($driver) {
			unless (is_a_driver($primary_symbol_list->[$i])) {
		
				do_allele_list ($code, $driver, ', ', '', 0, $phenotype);
			} else {
			
				do_allele_list ($code, $driver, ', ', '', 1, $phenotype);
			
			}
		}

	}
    }
}

sub validate_GA289ab ($$$)
{

# Genetic interaction between two or more genes.  The general format of the data is:
#
# (with gene1[allele2]) <phenotype > { gene2[allele1] }, <genetic interaction qualifier> { interacting alleles }
#
# where each portion may have complicated substructure, described below, and some of them may be optional.
#
# The difference between GA28[ab] and GA29[ab]a is that the former must test to see whether at least one of
# gene2[allele1] is the same species as the allele in GA1a and must not have data for non-Drosophilid genes.
#
# The difference between GA2[89]a and GA2[89]b is that the former's phenotype describes the phenotypic class
# and the latter the body type --- the same relationship as there is between GA56 and GA17
#
# Partial BNF, where ::= is the definition operator and || the alternation operator, for the data field is:
#
# <allele_list>    ::= <allele> || '<allele_list>, <allele>' || '<allele_list>/<allele>'
# <qualifier_list> ::= <qualifier> || '<qualifier_list> | <qualifier>'
# <qualified_phenotype>      ::= <phen_class_term> || '<phen_class_term> | <qualifier_list>'
# <with_list>      ::= '(with <allele_list>) '
# <wp_prefix>      ::= <with_list> || <qualified_phenotype> || <with_list><qualified_phenotype>
# <git_prefix>     ::= '{ <allele_list>}' || <wp_prefix> || <wp_prefix> { <allele_list> }'
# <qualified_git>  ::= <genetic_interaction_qualifier> || '<genetic_interaction_qualifier> | <qualifier>'
# <gi_data>        ::= '<qualified_git> { <allele_list>}' || '<git_prefix>, <qualified_git> { <allele_list> }'

    my ($code, $change, $interaction_list) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});
    $interaction_list eq '' and return;		# Absence of data is always acceptable.

    if ($code =~ /^GA28/ and !valid_symbol ($g1a_species, 'taxgroup:drosophilid'))
    {
	report ($file, "%s: Can't have data '%s' when the species in GA1a (%s) is a non-drosophilid. Perhaps you meant to put the CV statement in %s ?",
		$code, $interaction_list, $g1a_species, 'GA29');
	return;
    }

    my @interactions = dehash ($file, $code, $hash_entries, $interaction_list);
    for (my $i = 0; $i < $hash_entries; $i++)
    {
	foreach my $gi_data (split /\n/, $interactions[$i])
	{
	    $gi_data = trim_space_from_ends ($file, $code, $gi_data);
	    next if $gi_data eq '';

# Slice up the line into its constituent parts as best we can, despite any errors that may be present.  There
# may be up to three <allele_lists> in a complete valid $gi_data and they are rather inconvenient because they
# can contain a comma as a separator so tricky to distinguish between from the comma which terminates optional
# <git_prefix>.

	    my ($with_list, $qualified_phenotype, $allele_list, $prefixed_qualified_git, $qualified_git, $interacting_alleles);

# Ideally, we'd follow the BNF above and split off the <genetic_interaction_qualifier> first, but the
# <with_list>, if it appears, is easily distinguished from everything else so chop it off first, thereby
# reducing the number of <allele_list>s to be considered.

	    (undef, $with_list, $prefixed_qualified_git) = ($gi_data =~ /^(\(with (.*)\) )?(.*)/);

# Now look for remaining <allele_list>s.  There must be one at the end of the line (the interacting alleles)
# and there may also be one near the start.  Don't bother trimming spaces because the call above ensures that
# there are none at the end of the string, but see if we may need to put one just before a terminal '}' in
# order to make progress.

	    unless ($prefixed_qualified_git =~ /\}$/)
	    {
		my $open_count  = $prefixed_qualified_git =~ s/\{/\{/g;
		my $close_count = $prefixed_qualified_git =~ s/\}/\}/g;

		if ($open_count == $close_count + 1)
		{
		    report ($file, "%s: I think you may have omitted the final ' }' in '%s'," .
			" so I'm adding one and carrying on, hoping for the best.", $code, $gi_data);
		    $prefixed_qualified_git .= ' }';
		}
		else
		{

# Not sure what to do here in an else-clause.  There are at least three plausible approaches.

# 1) Add a closing curly and see what happens.
# 2) Give up right now and don't check anything else.
# 3) Carry on regardless.

# In the absence of any better idea, I chose to carry on regardless.  The missing interacting_alleles check
# below should provide a modicum of safety.

		}
	    }

	    if ($prefixed_qualified_git =~ s/(.*\S)\}$/$1 \}/)
	    {
		report ($file, "%s: I think you may have missed a space before the final } in '%s'," .
			" so I'm inserting one and carrying on, hoping for the best.", $code, $gi_data);
	    }

# Next, slice off the interacting alleles.  The regexp has to be careful not to pick up any '}' or '{' which
# bracket a preceding <allele_list'> without falsely matching on a curly bracket appearing as part of a FBti
# which, despite the name, is legal in an <allele_list> under rare circumstances.

	    $prefixed_qualified_git =~ /(.*)( \{ ((?! [{}][, ]).*?) \})$/;
	    $prefixed_qualified_git = $1;
	    $interacting_alleles = trim_space_from_ends ($file, $code, $3);

	    if ($interacting_alleles eq '')
	    {
		report ($file, "%s: I can't find the interacting_alleles in '%s'" .
			" --- did you omit that data, or a curly bracket or a space perhaps?", $code, $gi_data);

# This is mandatory data and if the error arose through misplaced or missing curly brackets it's not easy to
# recover in general, so just abandon ship right here.

		next;
	    }

# Now trim the spaces in case there was leading whitespace, or too much before the interacting alleles.

	    $prefixed_qualified_git = trim_space_from_ends ($file, $code, $prefixed_qualified_git);

# Dig out the remaining <allele_list>, if any.  Nothing remaining in the data may legally contain curly
# brackets, so be as greedy as possible so that any extras will be reported when the <allele_list> is checked.
# Leave the separators (spaces and possibly a comma) still attached to the fragments of
# $prefixed_qualified_git so that we stand a chance of detecting whether they were there or not, and to report
# and correct as needed.

	    ($qualified_phenotype, undef, $allele_list, $qualified_git) =
		($prefixed_qualified_git =~ /([^{,}]*)(\{(.*)\})?(.*?)$/);


# If $prefixed_qualified_git consists only of a $qualified_git, that value will have ended up in $qualified_phenotype
# instead.  Rather than making the above regexp even hairier, it's much easier to detect and correct as
# follows.

	    if ($qualified_git eq '' and ! defined $allele_list)
	    {
		($qualified_phenotype, $qualified_git) = ('', $qualified_phenotype);
	    }

# Make best efforts to detect missing spaces in $allele_list and to remove any that are (properly) present.

	    if ($allele_list)
	    {
		$allele_list =~ s/^ // or
		    report ($file, "%s: Missing space between { and '%s' in '%s'", $code, $allele_list, $gi_data);
		$allele_list =~ s/ $// or
		    report ($file, "%s: Missing space between '%s' and } in '%s'", $code, $allele_list, $gi_data);

		if ($qualified_phenotype)
		{
		    $qualified_phenotype =~ s/ $// or
			report ($file, "%s: Missing space between } and '%s' in '%s'", $code, $allele_list, $gi_data);
		    $qualified_phenotype = trim_space_from_ends ($file, $code, $qualified_phenotype);
		}
	    }

# If there is anything at all before the <qualified_git>, it must be terminated with a ', '.  The
# space-trimming is to pick up erroneous additional spaces.

	    if ($allele_list or $qualified_phenotype)
	    {
		$qualified_git = trim_space_from_ends ($file, $code, $qualified_git);
		$qualified_git =~ s/^,// or
		    report ($file, "%s: Missing comma before '%s' in '%s'", $code, $qualified_git, $gi_data);
		$qualified_git =~ s/^ // or
		    report ($file, "%s: Missing space before '%s' in '%s'", $code, $qualified_git, $gi_data);
		$qualified_git = trim_space_from_ends ($file, $code, $qualified_git);
	    }

# At this point we now have $gi_data dismantled into bite-sized chunks that can be handed off to subroutines
# for detailed checking.

# Processing $with_list is identical to GA56 and GA17.

	    if ($with_list)
	    {
		do_withs ($code, $with_list, $primary_symbol_list->[$i], $gi_data);
		foreach my $qualifier (split (' \| ', $qualified_phenotype))
		{
		    if ($qualifier eq 'dominant') {
			report ($file, "%s: Can't use '%s' with a '(with )' in '%s'",
				$code, $qualifier, $gi_data);
		    } elsif ($qualifier eq 'recessive') {

			# want to allow 'recessive' for simple homozygotes only
			# this means can do a simple test of whether $with is the same as allele in GA1a
			# without having to split out the components (if there is more than one component
			# recessive isn't really applicable)
			unless ($with_list eq silent_trim_space($primary_symbol_list->[$i])) {

				report ($file, "%s: Can't use '%s' with '(with )' (not a simple homozygote) in '%s'",
					$code, $qualifier, $gi_data);
			}
		    }

		}
	    }

# If $qualified_phenotype is non-empty, validate it exactly as in GA56/GA17.

	    my $phenotype = '';	# variable to store phenotypic class term returned by do_phen_class subroutine.
	    if ($qualified_phenotype)
	    {
		if ($code eq 'GA28a' or $code eq 'GA29a')	# GA2[89]a is phenotypic class
		{
		    $phenotype = do_phen_class ($code, $qualified_phenotype, $gi_data);
		}
		else
		{
		    do_phen_bodytype ($code, $qualified_phenotype, $gi_data); # tells you you can't use ' & '
		}
	    }

# Strictly speaking, $allele_list need not be checked as restrictively as the drivers in GA56 and GA17, as
# triple-mutants will generate a false positive.  However, it has been decided that is this not a Bad Thing
# for the moment, so that's what we'll do.  When the policy changes, the fifth argument should be 2, not 0.

	    $allele_list and do_allele_list ($code, $allele_list, ', |/', '', 2, $gi_data);

	    my @q_list = split (' \| ', $qualified_git);

	    my $git = shift @q_list;
	    $git = trim_space_from_ends ($file, $code, $git);

	    if (valid_symbol ($git, 'FBcv:genetic_interaction_type') or $git eq 'UI' or $git eq 'non-modified')
	    {
	    
			if (valid_symbol ($git, 'FBcv:do_not_manually_annotate')) {
	    
				report ($file, "%s: '%s' term can not be used for manual annotation.  If possible, record the genetic interaction from the inverse point of view in the appropriate allele proforma.", $code, $git);	    
			}
			
			foreach my $qualifier (@q_list) {
				$qualifier = trim_space_from_ends ($file, $code, $qualifier);
#
# These next two are called GITQ1 in allele.check.pro
#		    
				valid_symbol ($qualifier, 'FBcv:genotype_to_phenotype_relation') and next;
				valid_symbol ($qualifier, 'FBcv:sex_qualifier') and next;
				valid_symbol ($qualifier, 'FBcv:clone_qualifier') and next;
#
# This is GITQ2
#
				$git eq 'suppressible' and valid_symbol ($qualifier, 'FBcv:extent') and next;
#
# and this is GITQ3
#
				$git eq 'suppressible' || $git eq 'enhanceable' || $git eq 'UI' and
				valid_symbol ($qualifier, 'FBcv:environmental_qualifier') and next;	

				report ($file, "%s: Invalid qualifier '%s' in '%s'", $code, $qualifier, $gi_data);
			}
	    }
	    elsif ($git eq '')				# The $git is mandatory data.
	    {
		report ($file, "%s: Missing genetic interaction type in '%s'", $code, $gi_data);
	    }		    
	    else
	    {
		report ($file, "%s: Invalid genetic interaction type '%s' in '%s'", $code, $git, $gi_data);
	    }

	    if ($interacting_alleles eq '')		# $interacting_alleles is mandatory data.
	    {
		report ($file, "%s: Missing interacting_alleles in '%s'", $code, $gi_data);
	    }
	    else
	    {
		do_allele_list ($code, $interacting_alleles, ', |/', $phenotype, 2, $gi_data);
	    }

# Species checks.  Already aborted GA28 for non-Drosophilids.

	    my $all_ga1a_species = 1;
	    foreach my $allele (split (', |/', $interacting_alleles))
	    {
		next if is_a_driver ($allele);
		next if $allele eq '+';

		my ($species, $backslash) = ($allele =~ /^([^\\\[\]]*)(\\)?/);
		$backslash or $species = 'Dmel';
		if ($species ne $g1a_species)
		{
		    if ($code =~ /^GA28/)
		    {
			report ($file, "%s: Allele '%s' in '%s' is not the same species as given in GA1a (%s).  Perhaps you meant to put the CV statement in %s ?",
			    $code, $allele, $gi_data, $g1a_species, 'GA29');
		    }
		    else
		    {
			$all_ga1a_species = 0;
		    }

		}
	    }
	    if ($code =~ /GA29/ and $all_ga1a_species and valid_symbol ($g1a_species, 'taxgroup:drosophilid'))
	    {
		report ($file, "%s: Can't find a non-driver allele in '%s' with a different species from that in GA1a (%s).  Perhaps you meant to put the CV statement in %s ?",
			$code, $gi_data, $g1a_species, 'GA28');
	    }
	}
    }
}

sub validate_GA21 ($$$)
{
    my ($code, $change, $complement_data) = @_;
    changes ($file, $code, $change) and report ($file, "%s: Can't use !c in this field \n!%s",$code,$proforma_fields{$code});

# Data is one of six softCV prefices followed by interallelic complementation data

    $complement_data eq '' and return;		# Absence of data is always acceptable.

    my @complement_list = dehash ($file, $code, $hash_entries, $complement_data);
    for (my $i = 0; $i < $hash_entries; $i++)
    {
	next if $complement_list[$i] eq '';		# Absence of data is always acceptable.

	my $uniqued_complement_list = check_for_duplicated_lines($file,$code,$complement_list[$i],$proforma_fields{$code});

	foreach my $c_line (keys %{$uniqued_complement_list})

	{
	    $c_line = trim_space_from_ends ($file, $code, $c_line);
	    next if $c_line eq '';			# Completely empty line, the same as no data.

	  PARSE_C_LINE:
	    my ($softcv, $colon, $space, $complement) =
		($c_line =~ /^(Rescues|Fails to rescue|Partially rescues|Complements|Fails to complement|Partially complements)(:*)( *)(.*)/);

	    if (defined $softcv)
	    {
		if ($colon eq '')
		{
		    report ($file, "%s: Missing colon after SoftCV in '%s'", $code, $c_line);
		}
		elsif (length ($colon) > 1)
		{
		    report ($file, "%s: More than one colon after SoftCV in '%s'", $code, $c_line);
		}
		if ($space eq '')
		{
		    report ($file, "%s: Missing space after SoftCV: in '%s'", $code, $c_line);
		}
		elsif (length ($space) > 1)
		{
		    report ($file, "%s: More than one space after SoftCV: in '%s'", $code, $c_line);
		}
	    }
	    else
	    {
		if ($c_line =~ /^(\(with .*?\) )(.*: )(.*)/)
		{
		    report ($file, "%s: It looks like you put the \"with\" before the SoftCV in '%s'\n" .
			    "I'm going to assume you meant '%s' and try checking it again",
			    $code, $c_line, "$2$1$3");
		    $c_line = "$2$1$3";
		    goto PARSE_C_LINE;
		}
		report ($file, "%s: Missing or unrecognized SoftCV prefix in '%s'\n" .
			"Legal values are\n\tRescues:\n\tFails to rescue:\n\tPartially rescues:\n" .
			"\tComplements:\n\tFails to complement:\n\tPartially complements:",
			$code, $c_line);
		next;
	    }
	    next if $complement eq '';			# Absence of data is always acceptable.

#  Funky stuff here.

# General pattern in terms of the BNF above is
#
#	<with_list> <allele_list> { <allele_list> } 
#
# but with variations and constraints according to the SoftCV term in use.

	    my (undef, $with_list, $remainder) = ($complement =~ /^(\(with (.*)\) )?(.*)/);
	    
	    $remainder = trim_space_from_ends ($file, $code, $remainder);

# Now look for remaining <allele_list>s.  There may be one in curly brackets at the end of the line (a driver)
# and there must also be an unadorned one at the start.  See if we may need to put a space in just before a terminal
# '}' in order to make progress.

	    if ($remainder =~ s/(.*\S)\}$/$1 \}/)
	    {
		report ($file, "%s: I think you may have missed a space before the final } in '%s'," .
			" so I'm inserting one and carrying on, hoping for the best.", $code, $c_line);
	    }

# Next, split into the allele(s) and the driver, if any.

	    my ($alleles, undef, $driver) = ($remainder =~ /(.*?)( \{ ((?! [{}][, ]).*?) \})?$/);
	    my ($allele1, $allele2) = split ('/', $alleles);
	    $allele1 = trim_space_from_ends ($file, $code, $allele1);

# $allele1 is mandatory, and if it is absent we may as well give up now.

	    if ($allele1 eq '')
	    {
		report ($file, "%s: Missing allele in '%s'", $code, $c_line);
		next;
	    }
	    if (valid_symbol ($allele1, 'FBal') or $allele1 =~ /\[-\]$/)
	    {

			unless ($softcv =~ /omplement/) {
				$allele1 =~ /(.+)\[(.+)\]$/;		# Slice out gene portion.
				$1 eq $g1a_gene or report ($file,
					   "%s: Mismatch between gene symbol '%s' in GA1a " .
					   "and the gene portion '%s' given in '%s' in the line\n%s",
					   $code, $g1a_gene, $1, $allele1, $c_line);
			}
	   	}
	    elsif (valid_symbol ($allele1, 'FBab'))
	    {

# How to find out whether it disrupts the gene in question?

# Answer: some serious reading of the entrails of Chado is required in general, and the consensus among camcur
# is that implementation can wait for TFOT.  Accordingly, comment out the report but leave it in place as a
# reminder.

#		report ($file, "%s: %s is a valid aberration symbol in '%s' \n" .
#			"but I don't yet know how to check whether it disrupts %s",
#			$code, $allele1, $c_line, $g1a_gene);
	    }
	    else
	    {
		report ($file, "%s: Invalid allele or aberration symbol '%s' in '%s'",
			$code, $allele1, $c_line);
	    }

	    $driver = trim_space_from_ends ($file, $code, $driver);

# Treatment of $allele2 and $with_list depends on SoftCV.  In the case of the complementation statements, the
# reciprocal statement must also be curated in the same record, so save this data for the post-check phase.

	    if ($softcv =~ /omplement/)
	    {
		$with_list and report ($file, "%s: Can't have \"with\" with SoftCV %s: in '%s'",
				       $code, $softcv, $c_line);
		$allele2 and report  ($file, "%s: Can't have '/%s' with SoftCV %s: in '%s'",
				       $code, $allele2, $softcv, $c_line);
		$driver and report ($file, "%s: Can't have driver '%s' with SoftCV %s: in '%s'",
				    $code, $driver, $softcv, $c_line);

# '£' is never a valid character so can safely use it as a separator.

#		$GA21_hash{join '£', ($allele1, $softcv, $primary_symbol_list->[$i])} = 1;
	    }
	    else
	    {
		$with_list and do_withs ($code, $with_list, $primary_symbol_list->[$i], $c_line);

# Driver is always legitimate but never mandatory.

		$driver and do_allele_list ($code, $driver, ', ', '', 0, $c_line);

# Can have /+ or /allele or /allele[-]

		$allele2 = trim_space_from_ends ($file, $code, $allele2);
		unless ($allele2 eq '' || $allele2 eq '+' || $allele2 eq '-')
		{
		    if (valid_symbol ($allele2, 'FBal'))
		    {
			$allele2 =~ /(.+)\[(.+)\]$/;		# Slice out gene portion.
			$1 eq $g1a_gene or report ($file,
						   "%s: Mismatch between gene symbol '%s' in GA1a " .
						   "and the gene portion '%s' given in '%s/%s' in the line\n%s",
						   $code, $g1a_gene, $1, $allele1, $allele2, $c_line);
		    }
		    elsif (valid_symbol ($allele2, 'FBab'))
		    {

# How to find out whether it disrupts the gene in question?

# Answer: some serious reading of the entrails of Chado is required in general, and the consensus among camcur
# is that implementation can wait for TFOT.  Accordingly, comment out the report but leave it in place as a
# reminder.

#			report ($file, "%s: %s is a valid aberration symbol in '%s/%s' in the line\n%s\n" .
#				"but I don't yet know how to check whether it disrupts %s",
#				$code, $allele2, $allele1, $allele2, $c_line, $g1a_gene);
		    }
		    else
		    {
			report ($file, "%s: Invalid allele or aberration symbol '%s' in '%s'",
				$code, $allele2, $c_line);
		    }
		}
	    }
	}

# I've no idea what the next comments mean.  I typed them while non compos mentis with a migraine.

# qrd bwzr>

# suns
# unit
# nice
# stem
    }
}

sub validate_GA10a ($$$)
{

# Associated construct data.  The data is a (list of) FBtp symbol(s).
# The pre-instantiation code already run in Peeves will have created new symbols of FBtp
# type willy-nilly for the benefit of any other proforma fields which use them before we get a chance to
# validate the symbols.  What we do here is see whether they look like a FBtp.
# We must also check that existing constructs are indeed associated with the allele.  A cross-dependency with
# GA10b will be dealt with in the post-check phase (not yet implemented).

    my ($code, $change, $construct_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.

    @GA10a_list = ();
    $construct_list eq '' and return;			# Absence of data is often acceptable.

    my @constructs = dehash ($file, $code, $hash_entries, $construct_list);
    for (my $i=0; $i <= $#constructs; $i++)		# Don't use $hash_entries in case of hash list mismatch
    {
	my @c_list = ();
	next if $constructs[$i] eq '';			# Absence of data is often acceptable.
	foreach my $construct (split /\n/, $constructs[$i])
	{
	    $construct = trim_space_from_ends ($file, $code, $construct);
	    next if $construct eq '';			# Absence of data is often acceptable.
	    push @c_list, $construct;			# Save original form for later, then
	    $construct =~ s/^NEW://;			# remove any new construct indicator.

# do not need an else loop for the case where the construct is neither in chado nor instantiated in the record, as that check is done after the first-pass symbol instantiation/invalidation in Peeves
# only allow FBtp in GA10a (if the construct is an FBmc, moseg.pro should be used to link allele and construct instead, not allele.pro)
	    if (my $fbtp = valid_symbol ($construct, 'FBtp')) {

# construct created in curation record (i.e. pre-instantiated)
			if ($fbtp =~ /^good_/) {

				my $nat_te_end = check_construct_symbol_format ($file, $code, $construct, \%proforma_fields);

# initial test for "defined $nat_te_end" is to prevent terminal messages for the case
# where the construct fails the basic test for construct format (e.g. if put an insertion
# in GA10a by mistake)
				if (defined $nat_te_end && $nat_te_end eq 'TI') {

# do not allow *new* TI-style constructs to be 
					report ($file, "%s: new 'TI-style' constructs should not be submitted in an allele.pro - please submit the '%s' construct using a moseg.pro instead so that the appropriate comment can be filled in in that proforma). (Note also that in most cases, this moseg.pro should generally be submitted under the general FlyBase analysis reference FBrf0105495).\n! %s ", $code, $construct, $proforma_fields{$code});
				}

# construct already in chado
			} else {

				my $fbal = valid_symbol ($primary_symbol_list->[$i], 'FBal');
				if ($fbal =~ /^good_/) {
					report ($file, "%s: '%s' exists in Chado already but the allele in GA1a, '%s', does not.\n" . "Did you intend to associate an existing construct with a new allele?", $code, $construct, $primary_symbol_list->[$i]);
# Check $primary_symbol_list->[$i] is associated with $construct.
				} else {
					my $assoc_list = chat_to_chado ('associated_with_FBal', $fbtp);

# $assoc_list now contains everything which Chado considers to be associated with $fbtp.  See if $fbal appears
# in that list.
					grep {$fbal eq $_->[0]} @{$assoc_list} or report ($file, "%s: %s is not associated with GA1a allele '%s' in Chado.", $code, $construct, $primary_symbol_list->[$i]);
				}
			}
	    }


	}
	push @GA10a_list, [@c_list];		# A list of lists ...
    }
}


sub validate_GA10ce ($$$)
{

# Associated insertion data.  The data is a (list of) FBti symbol(s).
# The pre-instantiation code already run in Peeves will have created new symbols of FBti
# type willy-nilly for the benefit of any other proforma fields which use them before we get a chance to
# validate the symbols.  What we do here is see whether they look like a FBti.
# We must also check that existing insertions are indeed associated with the allele.  A cross-dependency with
# GA10e/GA10f will be dealt with in the post-check phase (not yet implemented).


    my ($code, $change, $insert_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.

	my @return_list;
    return () if $insert_list eq '';			# Absence of data is often acceptable.

    my @inserts = dehash ($file, $code, $hash_entries, $insert_list);


    for (my $i=0; $i <= $#inserts; $i++)	# Don't use $hash_entries in case of hash list mismatch.
    {
	my @i_list = ();
	next if $inserts[$i] eq '';			# Absence of data is acceptable.
	foreach my $insert (split /\n/, $inserts[$i])
	{
		$insert = trim_space_from_ends ($file, $code, $insert);
		next if $insert eq '';			# Absence of data is acceptable.
	    push @i_list, $insert;			# Save original form for later, then
		$insert =~ s/^NEW://;			# remove new TI indicator.

# do not need an else loop for the case where the insertion is neither in chado nor instantiated in the record, as that check is done after the first-pass symbol instantiation/invalidation in Peeves
		if (my $fbti = valid_symbol ($insert, 'FBti')) {

# Insertion created in curation record (i.e. pre-instantiated)
			if ($fbti =~ /^good_/) {

				my ($inserted_element, $identifier, $full_symbol_of_inserted_element) = check_insertion_symbol_format ($file, $code, $insert, \%proforma_fields);

				if ($code eq 'GA10c' && $identifier ne $primary_symbol_list->[$i]) {

					report ($file, "%s: Identifier '%s' in the symbol '%s' differs from the corresponding allele, '%s', in GA1a.", $code, $identifier, $insert, $primary_symbol_list->[$i]);

				}


# Insertion already in chado
			} else {

				my $fbal = valid_symbol ($primary_symbol_list->[$i], 'FBal');

				if ($fbal =~ /^good_/) {
					report ($file, "%s: '%s' exists in Chado already but the allele in GA1a, '%s', does not.\n" . "Did you intend to associate an existing TI with a new allele?", $code, $insert, $primary_symbol_list->[$i]);
# Check $primary_symbol_list->[$i] is associated with $insert.
				} else {
					my $assoc_list = chat_to_chado ('associated_with_FBal', $fbti);

# $assoc_list now contains everything which Chado considers to be associated with $fbti.  See if $fbal appears
# in that list.
					grep {$fbal eq $_->[0]} @{$assoc_list} or report ($file, "%s: %s is not associated with GA1a allele '%s' in Chado.", $code, $insert, $primary_symbol_list->[$i]);
				}
	    	}
		}



    }

	push @return_list, [@i_list];		# A list of lists ...
    }

	return @return_list;
}

sub validate_GA10g ($$$)
{
# Associated cytology.

    my ($code, $change, $assoc_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    $assoc_list eq '' and return;		# Absence of data is always acceptable.

    foreach my $assocs (dehash ($file, $code, $hash_entries, $assoc_list))
    {
	next if $assocs eq '';			# Absence of data is always acceptable.
	foreach my $assoc (split /\n/, $assocs)
	{
	    $assoc = trim_space_from_ends ($file, $code, $assoc);

#  Review these next few lines, along with GA8 and GA11, when checking A4 and A6.  May need attention.

	    next if $assoc eq '' or $assoc eq '+' ;
	    if (valid_symbol ($assoc, 'FBab'))
	    {
		push @g_assoc_aberr, $assoc;
	    }
	    else
	    {
		report ($file, "%s: Invalid aberration symbol '%s'", $code, $assoc);
	    }
	}
    }
}




sub validate_GA23a ($$$)
{
# Notes on origin: must be preceded by a valid SoftCV prefix.  The following material is essentially a single
# line of free text, for which we need only check material within stamps.

    my ($code, $change, $n_o_o) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    $n_o_o eq '' and return;			# Absence of data is always acceptable.

    foreach my $notes (dehash ($file, $code, $hash_entries, $n_o_o))
    {
	next if $notes eq '';						# Absence of data is always acceptable.
	foreach my $note (split /\n/, $notes)
	{
	    $note = trim_space_from_ends ($file, $code, $note);
	    next if $note eq '';					# Ignore blank lines.
	    my (undef, $softcv, $space, $rest) = ($note =~ /^((.*?):)?( )?(.*)/);
	    if (defined $softcv)
	    {
		valid_symbol ($softcv, 'notes on origin') or report ($file, "%s: Invalid SoftCV prefix '%s' in '%s'",
								     $code, $softcv, $note);
		defined $space or report ($file, "%s: I think you omitted the space after the SoftCV prefix in '%s'",
					  $code, $note);

# Add temporary message that 'Associated with:' is not allowed - will eventually just remove
# as allowed value from symtab.pl
		if ($softcv eq 'Associated with') {

			report ($file, "%s: 'Associated with:' is no longer an allowed SoftCV prefix - remove this line and any associated data in GA23b, and simply describe the nature of the mutation (including all genes affected) in the GA12b 'Nature of the lesion' field instead.\n!%s", $code, $proforma_fields{$code});

		}
		
	    }
	    else
	    {
		report ($file, "%s: Missing SoftCV prefix in '%s'", $code, $note);
	    }
	    check_stamps ($file, $code, trim_space_from_ends ($rest));
	}
    }
}






sub validate_GA34a ($$$)
{
# DO (disease ontology) data.

    my ($code, $change, $data_list) = @_;
    changes ($file, $code, $change);		# Check for garbage, but otherwise don't worry about $change.
    $data_list = trim_space_from_ends ($file, $code, $data_list);
    $data_list eq '' and return;		# Absence of data is always acceptable.

	$g_GA34a_count++; # add to the count as GA34a contains data

    foreach my $data (dehash ($file, $code, $hash_entries, $data_list))
    {
	next if $data eq '';
	foreach my $datum (split ('\n', $data))
	{
	    $datum = trim_space_from_ends ($file, $code, $datum);
	    next if $datum eq '';

		my $qualifier = '';
		my $provenance = '';
		my $term = '';
		
# Assign provenance, check it, and remove it from $datum for checking that follows
		($datum,$provenance) = set_provenance ($datum,$provenance,"DO");

# A single datum looks like <qualifier><DO_term> ; <DO_ID_number> | <evidence_code><evidence_data>
#
# First enforce basic structural similarity to this pattern and then slice up the datum

	    unless ($datum =~ / ; /)
	    {
		report ($file, "%s: Missing ' ; ' separator in '%s'", $code, $datum);
		next;
	    }
	    unless ($datum =~ / \| /)
	    {
		report ($file, "%s: Missing ' | ' separator in '%s'", $code, $datum);
		next;
	    }
	    unless ($datum =~ / ; .* \| /)
	    {
		report ($file, "%s: ' ; ' and ' | ' separators in wrong order in '%s'", $code, $datum);
		next;
	    }
	    my ($qualified_term, $id, $evidence) = ($datum =~ /(.*?) ; (.*?) \| (.*)/);

# Check for a qualifier and remove it from the qualified_term if a valid one is found to allow subsequent checking of term

	    ($qualifier,$term) = check_qualifier($file, $code, $datum, $qualified_term);


# Check $term and $id for validity and that they match each other

		check_ontology_term_id_pair ($file, $code, $term, $id, "DOID:default", $datum, '');

# Check the evidence data

	    do_do_evidence ($code, $datum, $id, $evidence, $qualifier);
	}
    }
}





sub do_do_evidence ($$$$$)
{
# Validate DO evidence given in the fourth argument for the DO-id given in the third.  The first two arguments tell us which proforma field is being validated and its data.

# don't need $id for DO checking (needed in GO for IC checking), but keep in case manage to make merged do_evidence subroutine based on this in the future
    my ($code, $context, $id, $evidence, $qualifier) = @_;
    my ($ev_code, $ev_data);

# The evidence consists of an evidence code possible followed by some evidence data.  Determining which is
# which can be a real bugger because the code can contain spaces and the word "from" which is also used as an
# introducer for the data portion in some circumstances.  This may help explain why the material below looks
# so ugly and why we can't just use a clever regexp and a call to valid_symbol().

    $evidence = trim_space_from_ends ($file, $code, $evidence);

# Have grouped evidence codes below into groups which have similar checking
# to make it easier to add new evidence codes/change requirements for existing evidence codes


# MANDATORIALLY HAS VALUE AFTER CODE:' with ' followed by at least one database identifier
# i.e. must HAVE 'with ' after evidence code

    if (($ev_code, $ev_data) = ($evidence =~ /^(CEA|CEC)(.*)/)) {

		check_evidence_data($file,$code, $context, $ev_code, $ev_data);

		unless ($qualifier eq 'model of' || $qualifier eq 'DOES NOT model') {

			report ($file, "%s: the '%s' evidence code must not be used with the '%s' qualifier:\n%s",$code,$ev_code,$qualifier,$context);

		}
    }
 


# MANDATORIALLY HAS VALUE AFTER CODE: ' with ' followed by at least one database identifier
# i.e. must HAVE 'with ' after evidence code

 
    elsif (($ev_code, $ev_data) = ($evidence =~ /^(modeled)(.*)/)) {

		check_evidence_data($file,$code, $context, $ev_code, $ev_data);

		if ($qualifier eq 'model of' || $qualifier eq 'DOES NOT model') {

			report ($file, "%s: the '%s' evidence code must not be used with the '%s' qualifier:\n%s",$code,$ev_code,$qualifier,$context);

		}
    }

# temporary code until get used to new evidence codes

    elsif (($ev_code, $ev_data) = ($evidence =~ /^(inferred from mutant phenotype|IMP|in combination|IC)(.*)/)) {

			report ($file, "%s: the '%s' evidence code is no longer valid for DO curation - use either 'CEC' or 'CEA' instead:\n%s",$code,$ev_code,$context);

	}

    else
    {
	report ($file, "%s: Bad evidence code '%s' in '%s'", $code, $evidence, $context);
    }
}


sub validate_GA90a {
# process_field_data + %field_specific_checks format. 150223.

	my ($file, $code, $dehashed_data, $context) = @_;

	$dehashed_data eq '' and return;

	my $uniqued_data = check_for_duplicated_lines($file,$code,$dehashed_data,$context->{$code});

	foreach my $datum (keys %{$uniqued_data}) {

		unless ($datum eq $primary_symbol_list->[-1]) {

			if (my ($symbol) = ($datum =~ m/^(.+)-[1-9]{1}[0-9]{0,}$/)) {

				unless ($symbol eq $primary_symbol_list->[-1]) {
					report ($file, "%s: Symbol portion '%s' does not match symbol in GA1a:\n!%s\n!%s", $code, $symbol, $context->{'GA1a'}, $context->{$code});

				}

			} else {

				report ($file, "%s: Invalid format '%s':\n!%s\n!%s", $code, $datum, $context->{'GA1a'}, $context->{$code});
			}
		}
	}
}


1;				# Standard boilerplate.
